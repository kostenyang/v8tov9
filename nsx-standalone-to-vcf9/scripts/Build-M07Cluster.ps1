# =============================================================================
# m07 第二輪(10-22):vCenter 8.0U3c(vcsa-deploy CLI)起來後把叢集補齊
#   改自 E:\9.1\m07\Build-M07Cluster.ps1;CLI 部署不會建 DC/cluster → 這裡自己建
#   1. DC m07-dc / cluster m07-cl01(vSAN on)→ 加 esx01(vCSA 所在,已 esxcli bootstrap vSAN)、esx02、esx03
#   2. vmk0 開 vMotion + vSAN(lab 簡化:mgmt/vMotion/vSAN 共用 vmk0,vmnic1 留給 VDS/NSX)
#   3. esx02/03 認領 vSAN 碟(60 GB cache / 1000 GB capacity,capacityFlash tag)
#   4. VDS m07-vds01(8.0.0, MTU 9000, uplink vmnic1)
#   5. DRS Fully Automated、HA 關;vSAN HCL 類健康檢查靜音
#   授權不套(evaluation 60 天)
#   pwsh -File Build-M07Cluster.ps1     需要 $env:VCPASS(vCenter SSO)、$env:ESXPASS
# =============================================================================
$ErrorActionPreference = 'Stop'
$PCLI = '13.5.1.25718932'
'Sdk','Core','Vds','Storage' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null
$LogFile = 'E:\9.1\m07-521\build-cluster.log'
function Log($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append $LogFile }

$vc = Connect-VIServer vcf-m07-vc01.home.lab -User administrator@vsphere.local -Password $env:VCPASS -Force
$dc = Get-Datacenter m07-dc -ErrorAction SilentlyContinue
if (-not $dc) { $dc = New-Datacenter -Name m07-dc -Location (Get-Folder -NoRecursion); Log 'created DC m07-dc' }
$cl = Get-Cluster m07-cl01 -ErrorAction SilentlyContinue
if (-not $cl) { $cl = New-Cluster -Name m07-cl01 -Location $dc; Log 'created cluster m07-cl01' }
if (-not (Get-VsanClusterConfiguration -Cluster $cl).VsanEnabled) {
  # PowerCLI 13.5: Set-VsanClusterConfiguration has no -VsanEnabled; Set-Cluster still does
  Set-Cluster -Cluster $cl -VsanEnabled $true -Confirm:$false | Out-Null; Log 'vSAN enabled on m07-cl01'
}

foreach ($h in 'vcf-m07-esx01.home.lab','vcf-m07-esx02.home.lab','vcf-m07-esx03.home.lab') {
  if (-not (Get-VMHost -Name $h -ErrorAction SilentlyContinue)) {
    Add-VMHost -Name $h -Location $cl -User root -Password $env:ESXPASS -Force | Out-Null; Log "added $h"
  }
}
$hosts = Get-VMHost -Location $cl | Sort-Object Name

foreach ($vh in $hosts) {
  Get-VMHostNetworkAdapter -VMHost $vh -Name vmk0 | Set-VMHostNetworkAdapter -VMotionEnabled $true -VsanTrafficEnabled $true -Confirm:$false | Out-Null
  Log "$($vh.Name) vmk0 vMotion+vSAN on"
}

foreach ($vh in $hosts) {
  if (Get-VsanDiskGroup -VMHost $vh -ErrorAction SilentlyContinue) { Log "$($vh.Name) 已有 disk group"; continue }
  $luns = Get-ScsiLun -VmHost $vh -LunType disk | Where-Object { $_.CapacityGB -ge 50 }
  $cache = ($luns | Where-Object { [int]$_.CapacityGB -eq 60 }).CanonicalName
  $cap   = ($luns | Where-Object { [int]$_.CapacityGB -eq 1000 }).CanonicalName
  $esxcli = Get-EsxCli -VMHost $vh -V2
  $esxcli.vsan.storage.tag.add.Invoke(@{disk=$cap; tag='capacityFlash'}) | Out-Null
  New-VsanDiskGroup -VMHost $vh -SsdCanonicalName $cache -DataDiskCanonicalName $cap | Out-Null
  Log "$($vh.Name) disk group cache=$cache cap=$cap"
}

$vds = Get-VDSwitch -Name m07-vds01 -ErrorAction SilentlyContinue
if (-not $vds) {
  $vds = New-VDSwitch -Name m07-vds01 -Location $dc -Version '8.0.0' -Mtu 9000 -NumUplinkPorts 1
  Log 'created VDS m07-vds01 8.0.0 MTU 9000'
}
foreach ($vh in $hosts) {
  if (-not ($vds | Get-VMHost | Where-Object Name -eq $vh.Name)) {
    Add-VDSwitchVMHost -VDSwitch $vds -VMHost $vh | Out-Null
    $nic = Get-VMHostNetworkAdapter -VMHost $vh -Physical -Name vmnic1
    Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic $nic -Confirm:$false
    Log "$($vh.Name) joined VDS with vmnic1"
  }
}

Set-Cluster -Cluster $cl -DrsEnabled $true -DrsAutomationLevel FullyAutomated -HAEnabled $false -Confirm:$false | Out-Null
Log 'DRS FullyAutomated, HA off'

# nested: silence vSAN HCL-type health checks (short ids; see E:\9.1\m07\Silence-VsanHcl.ps1)
$hs = Get-VsanView -Id 'VsanVcClusterHealthSystem-vsan-cluster-health-system'
$ids = 'controllerdiskmode','controlleronhcl','controllerreleasesupport','controllerdriver','controllerfirmware','hcldbuptodate','autohclupdate','smalldiskstest','vsanenablesupportinsight','vumconfig','vumrecommendation','physdiskcapacity'
$hs.VsanHealthSetVsanClusterSilentChecks($cl.ExtensionData.MoRef, $ids, $null) | Out-Null
Log ("silenced: " + ($hs.VsanHealthGetVsanClusterSilentChecks($cl.ExtensionData.MoRef) -join ','))

Log '=== summary ==='
Get-VMHost -Location $cl | Select-Object Name,Version,Build,ConnectionState | Format-Table | Out-String | ForEach-Object { Log $_ }
"vSAN members: " + (($hosts | ForEach-Object { (Get-EsxCli -VMHost $_ -V2).vsan.cluster.get.Invoke().SubClusterMemberCount }) -join ',') | ForEach-Object { Log $_ }
Get-Datastore vsanDatastore | Select-Object Name,CapacityGB,FreeSpaceGB | Format-Table | Out-String | ForEach-Object { Log $_ }
Disconnect-VIServer $vc -Confirm:$false
