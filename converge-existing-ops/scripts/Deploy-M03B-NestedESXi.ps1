# =============================================================================
# greenfield 重跑:4 台**全新乾淨**的 nested ESXi,給 VCF Installer 的
# Deployment Wizard 用(舊的 m03 叢集保留,當「既有 vROps + License Server」的家)
#
#   vcf-m03b-esx01~04 / 10.0.1.110-113,各 16 vCPU / 128 GB
#   cache 100 GB + capacity 1000 GB,網路 Trunk-Nobinding(mgmt untagged)
#
#   🔴 這次「乾淨」的定義由 Installer 的驗證決定,實測錯誤碼:
#        MANAGEMENT_VSWITCH_VMNIC_IN_USE  vmnic0 要掛在 vSwitch0(剛好 1 張)
#        VMNIC_IN_USE                     其餘 vmnic 要未指派
#        MORE_THAN_ONE_VMKERNEL_CONFIGURED 只能有 vmk0
#        VSAN_PARTITION_FOUND_ON_HOST     磁碟不能有 vSAN partition
#        VSAN_ZERO_SSD_DISKS_VALIDATION   至少一顆要標記成 SSD
#        VSWITCH_EXISTS                   不能有同名的 VDS
#      → 直接從 OVA 部一套新的最快,不要去「拆」舊的。
#
#   🔴 不要用容量排序挑碟!device 順序 [0]=開機碟(不動) [1]=cache [2]=capacity
#
#   $env:VIPASS='...'; $env:ESXPASS='...'; pwsh ./Deploy-M03B-NestedESXi.ps1
# =============================================================================
$ErrorActionPreference = 'Stop'
$PCLI = '13.5.1.25718932'
'Sdk','Core','Vds' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

$VIServer='10.0.0.101'; $VIUser='administrator@vsphere.local'
$VIPass  = if ($env:VIPASS)  { $env:VIPASS }  else { throw 'set $env:VIPASS' }
$ESXPass = if ($env:ESXPASS) { $env:ESXPASS } else { throw 'set $env:ESXPASS' }

$OVA='E:\9.1\Nested_ESXi9.1.0.0_Appliance_Template_v1.0.ova'
$Net='Trunk-Nobinding'; $Folder='VCF'; $TargetHost='10.0.0.95'
$Mask='255.255.254.0'; $GW='10.0.0.1'; $DNS='10.0.0.200'; $NTP='10.0.1.254'; $Domain='home.lab'
$vCPU=16; $vMEMGB=128; $CacheGB=100; $CapGB=1000

# 分散 datastore:4 台全擠 ForNFS 會把那兩顆 SATA SSD 打爆
$Hosts=[ordered]@{
  'vcf-m03b-esx01'=@{ip='10.0.1.110'; ds='vmfs-samsung4t'}
  'vcf-m03b-esx02'=@{ip='10.0.1.111'; ds='vmfs-wdblue4t'}
  'vcf-m03b-esx03'=@{ip='10.0.1.112'; ds='ForNFS'}
  'vcf-m03b-esx04'=@{ip='10.0.1.113'; ds='ForNFS'}
}
function Log($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append 'E:\9.1\m03\deploy-m03b.log' }

Log "connecting $VIServer"
$vi=Connect-VIServer $VIServer -User $VIUser -Password $VIPass -Force -WarningAction SilentlyContinue
$vmhost=Get-VMHost -Name $TargetHost
$fld=Get-Folder -Name $Folder -Type VM | Select-Object -First 1
Log ("host {0}  free mem {1:N0} GB" -f $vmhost.Name, ($vmhost.MemoryTotalGB-$vmhost.MemoryUsageGB))

foreach($name in $Hosts.Keys){
  if(Get-VM -Name $name -ErrorAction SilentlyContinue){ Log "$name 已存在,略過"; continue }
  $ip=$Hosts[$name].ip; $ds=Get-Datastore -Name $Hosts[$name].ds
  Log "=== $name ($ip) on $($ds.Name) ==="
  $ovf=Get-OvfConfiguration $OVA
  $ovf.NetworkMapping.VM_Network.value   = $Net
  $ovf.Common.guestinfo.hostname.value   = "$name.$Domain"
  $ovf.Common.guestinfo.ipaddress.value  = $ip
  $ovf.Common.guestinfo.netmask.value    = $Mask
  $ovf.Common.guestinfo.gateway.value    = $GW
  $ovf.Common.guestinfo.dns.value        = $DNS
  $ovf.Common.guestinfo.domain.value     = $Domain
  $ovf.Common.guestinfo.ntp.value        = $NTP
  $ovf.Common.guestinfo.password.value   = $ESXPass
  $ovf.Common.guestinfo.ssh.value        = $true
  $ovf.Common.guestinfo.createvmfs.value = $false      # 碟要留給 vSAN,不能有 VMFS partition
  Log "  importing OVA..."
  $vm=Import-VApp -Source $OVA -OvfConfiguration $ovf -Name $name -VMHost $vmhost `
        -Datastore $ds -InventoryLocation $fld -DiskStorageFormat thin
  Log "  set $vCPU vCPU / $vMEMGB GB"
  Set-VM -VM $vm -NumCpu $vCPU -MemoryGB $vMEMGB -Confirm:$false | Out-Null
  $disks=Get-HardDisk -VM $vm
  Log ("  disks(原始順序): " + (($disks | ForEach-Object { [int]$_.CapacityGB }) -join ' / '))
  Set-HardDisk -HardDisk $disks[1] -CapacityGB $CacheGB -Confirm:$false | Out-Null
  Set-HardDisk -HardDisk $disks[2] -CapacityGB $CapGB   -Confirm:$false | Out-Null
  Log "  cache=$CacheGB GB capacity=$CapGB GB"
  Start-VM -VM $vm -Confirm:$false | Out-Null
  Log "  powered on"
}
Log "=== summary ==="
Get-VM -Name 'vcf-m03b-esx0*' | Select-Object Name,NumCpu,MemoryGB,PowerState |
  Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Disconnect-VIServer $vi -Confirm:$false | Out-Null
Log 'done'
