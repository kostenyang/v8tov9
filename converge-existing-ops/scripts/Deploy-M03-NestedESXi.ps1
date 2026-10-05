# =============================================================================
# m03 converge 目標端:4 台 nested ESXi 9.1.0
#   vcf-m03-esx01~04 / 10.0.1.56-59,各 16 vCPU / 128 GB
#   cache 100 GB + capacity 1000 GB,網路 Trunk-Nobinding(mgmt untagged)
#   $env:VIPASS='...'; $env:ESXPASS='...'; pwsh ./Deploy-M03-NestedESXi.ps1
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
$Net='Trunk-Nobinding'; $Cluster='Cluster'; $Folder='VCF'; $TargetHost='10.0.0.95'
$VAppName='Nested-VCF-M03'
$Mask='255.255.254.0'; $GW='10.0.0.1'; $DNS='10.0.0.200'; $NTP='10.0.1.254'; $Domain='home.lab'
$vCPU=16; $vMEMGB=128; $CacheGB=100; $CapGB=1000

$Hosts=[ordered]@{
  'vcf-m03-esx01'=@{ip='10.0.1.56'; ds='ForNFS'}
  'vcf-m03-esx02'=@{ip='10.0.1.57'; ds='vmfs-wdblue4t'}
  'vcf-m03-esx03'=@{ip='10.0.1.58'; ds='vmfs-samsung4t'}
  'vcf-m03-esx04'=@{ip='10.0.1.59'; ds='ForNFS'}
}
function Log($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append 'E:\9.1\m03\deploy.log' }

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
  # ToHashTable() 會把 Common. 前綴吃掉,但物件存取仍要走 $ovf.Common.guestinfo.*
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
  $ovf.Common.guestinfo.createvmfs.value = $false
  Log "  importing OVA..."
  $vm=Import-VApp -Source $OVA -OvfConfiguration $ovf -Name $name -VMHost $vmhost `
        -Datastore $ds -InventoryLocation $fld -DiskStorageFormat thin
  Log "  set $vCPU vCPU / $vMEMGB GB"
  Set-VM -VM $vm -NumCpu $vCPU -MemoryGB $vMEMGB -Confirm:$false | Out-Null
  # 🔴 不要用容量排序挑碟!device 順序 [0]=開機碟(不動) [1]=cache [2]=capacity
  $disks=Get-HardDisk -VM $vm
  Log ("  disks(原始順序): " + (($disks | ForEach-Object { [int]$_.CapacityGB }) -join ' / '))
  Set-HardDisk -HardDisk $disks[1] -CapacityGB $CacheGB -Confirm:$false | Out-Null
  Set-HardDisk -HardDisk $disks[2] -CapacityGB $CapGB   -Confirm:$false | Out-Null
  Log "  cache=$CacheGB GB capacity=$CapGB GB"
  Start-VM -VM $vm -Confirm:$false | Out-Null
  Log "  powered on"
}
Log "=== summary ==="
Get-VM -Name 'vcf-m03-esx0*' | Select-Object Name,NumCpu,MemoryGB,PowerState |
  Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Disconnect-VIServer $vi -Confirm:$false | Out-Null
