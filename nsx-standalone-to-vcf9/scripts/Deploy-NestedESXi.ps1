# =============================================================================
# m07 第二輪(10-22):部 nested ESXi 8.0U3b 給手動 VCF 5.2.1 BOM(vC 8.0U3c + NSX 4.2.1)
#   改自 m03\Deploy-M03B-NestedESXi.ps1(該配方 10-06 greenfield 成功)
#
#   pwsh ./Deploy-NestedESXi.ps1 -Set m04      # 3 台 20 vCPU / 72 GB / capacity 2400 GB,保留記憶體
#   pwsh ./Deploy-NestedESXi.ps1 -Set m05      # 3 台 12 vCPU / 64 GB / capacity 1500 GB(含 VKS 空間)
#   pwsh ./Deploy-NestedESXi.ps1 -Set m06      # 3 台 20 vCPU / 80 GB / capacity 2400 GB(VPC air-gap no-VCFMS)
#   需要 $env:VIPASS(外層 vC)、$env:ESXPASS(nested root)
#
#   🔴 device 順序 [0]=開機碟(不動) [1]=cache [2]=capacity,不要用容量排序挑碟
#   🔴 createvmfs=false:碟要留給 vSAN,不能有 VMFS partition
# =============================================================================
param([Parameter(Mandatory)][ValidateSet('m07')][string]$Set)
$ErrorActionPreference = 'Stop'
$PCLI = '13.5.1.25718932'
'Sdk','Core' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

$VIPass  = if ($env:VIPASS)  { $env:VIPASS }  else { throw 'set $env:VIPASS' }
$ESXPass = if ($env:ESXPASS) { $env:ESXPASS } else { throw 'set $env:ESXPASS' }

$OVA='C:\Users\Administrator\OneDrive\桌面\VCF\Nested_ESXi8.0u3b_Appliance_Template_v1.ova'
$Net='Trunk-Nobinding'; $Folder='VCF'; $TargetHost='10.0.0.95'
$Mask='255.255.254.0'; $GW='10.0.0.1'; $DNS='10.0.0.200'; $NTP='10.0.1.254'; $Domain='home.lab'

$Cfg = @{
  # m07(10-21):vC 8U3g + NSX 4.2.2.1 -> 9.1.1.0100 in-place 測試;3 台 16 vCPU / 80 GB,capacity 1000 GB thin
  m07 = @{ cpu=16; mem=80; cache=60;  cap=1000; reserve=$false; hosts=[ordered]@{
          'vcf-m07-esx01'=@{ip='10.0.1.161'; ds='vmfs-samsung4t'}
          'vcf-m07-esx02'=@{ip='10.0.1.162'; ds='vmfs-wdblue4t'}
          'vcf-m07-esx03'=@{ip='10.0.1.163'; ds='vmfs-samsung4t'} } }
}[$Set]

$LogFile = "E:\9.1\m07-521\deploy-esx.log"
function Log($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append $LogFile }

Log "connecting 10.0.0.101 (set=$Set)"
$vi=Connect-VIServer 10.0.0.101 -User 'administrator@vsphere.local' -Password $VIPass -Force -WarningAction SilentlyContinue
$vmhost=Get-VMHost -Name $TargetHost
$fld=Get-Folder -Name $Folder -Type VM | Select-Object -First 1
Log ("host {0}  free mem {1:N0} GB" -f $vmhost.Name, ($vmhost.MemoryTotalGB-$vmhost.MemoryUsageGB))

foreach($name in $Cfg.hosts.Keys){
  if(Get-VM -Name $name -ErrorAction SilentlyContinue){ Log "$name 已存在,略過"; continue }
  $ip=$Cfg.hosts[$name].ip; $ds=Get-Datastore -Name $Cfg.hosts[$name].ds
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
  $ovf.Common.guestinfo.createvmfs.value = $false
  Log "  importing OVA..."
  $vm=Import-VApp -Source $OVA -OvfConfiguration $ovf -Name $name -VMHost $vmhost `
        -Datastore $ds -InventoryLocation $fld -DiskStorageFormat thin
  Set-VM -VM $vm -NumCpu $Cfg.cpu -MemoryGB $Cfg.mem -Confirm:$false | Out-Null
  Log "  set $($Cfg.cpu) vCPU / $($Cfg.mem) GB"
  $disks=Get-HardDisk -VM $vm
  Log ("  disks(原始順序): " + (($disks | ForEach-Object { [int]$_.CapacityGB }) -join ' / '))
  Set-HardDisk -HardDisk $disks[1] -CapacityGB $Cfg.cache -Confirm:$false | Out-Null
  Set-HardDisk -HardDisk $disks[2] -CapacityGB $Cfg.cap   -Confirm:$false | Out-Null
  Log "  cache=$($Cfg.cache) GB capacity=$($Cfg.cap) GB"
  if($Cfg.reserve){
    # 外層記憶體保留:防外層 swap 拖垮 VSP(memory vcf91-rebuild-recipe)
    # CPU 也保留 16 GHz/台:第一輪 VSP 裝 Identity Broker 時任務排隊太久 → Conductor 重送 → 重複執行(KB 439260)
    $vm | Get-VMResourceConfiguration | Set-VMResourceConfiguration -MemReservationGB $Cfg.mem -CpuReservationMhz 16000 | Out-Null
    Log "  mem reservation=$($Cfg.mem) GB, cpu reservation=16000 MHz"
  }
  Start-VM -VM $vm -Confirm:$false | Out-Null
  Log "  powered on"
}
Log "=== summary ==="
Get-VM -Name "vcf-$Set-esx0*" | Select-Object Name,NumCpu,MemoryGB,PowerState |
  Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Disconnect-VIServer $vi -Confirm:$false | Out-Null
Log 'done'
