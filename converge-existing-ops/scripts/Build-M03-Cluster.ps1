# =============================================================================
# m03:把 esx02-04 加進 cluster → 建 VDS + portgroup → 搬 vmk0 → 收 vSAN → DRS/HA
#   $env:VCPASS='...'; $env:ESXPASS='...'; pwsh ./Build-M03-Cluster.ps1
# =============================================================================
param([switch]$SkipHostAdd,[switch]$SkipVds,[switch]$SkipVsan)
$ErrorActionPreference='Stop'
$PCLI='13.5.1.25718932'
'Sdk','Core','Vds','Storage' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

$VC='vcf-m03-vc01.home.lab'
$VCPass = if($env:VCPASS){$env:VCPASS}else{throw 'set $env:VCPASS'}
$ESXPass= if($env:ESXPASS){$env:ESXPASS}else{throw 'set $env:ESXPASS'}
$DC='vcf-m03-dc01'; $ClusterN='vcf-m03-cl01'
$NewHosts=@('vcf-m03-esx02.home.lab','vcf-m03-esx03.home.lab','vcf-m03-esx04.home.lab')
$VdsName='vcf-m03-cl01-vds01'; $VdsMtu=9000
$PgMgmt='SDDC-DPortGroup-VM-Mgmt'          # converge spec 的 xRegionNetwork 指這個
$PgVmot='vcf-m03-cl01-vds01-pg-vmotion'; $PgVsan='vcf-m03-cl01-vds01-pg-vsan'
$VlanVmot=0; $VlanVsan=0                    # nested:全部走 untagged,vmk 另給網段
$UplinkNics=@('vmnic0','vmnic1')
$VmkMap=@{
  'vcf-m03-esx01.home.lab'=@{vmotion='192.168.35.11'; vsan='192.168.36.11'}
  'vcf-m03-esx02.home.lab'=@{vmotion='192.168.35.12'; vsan='192.168.36.12'}
  'vcf-m03-esx03.home.lab'=@{vmotion='192.168.35.13'; vsan='192.168.36.13'}
  'vcf-m03-esx04.home.lab'=@{vmotion='192.168.35.14'; vsan='192.168.36.14'}
}
function Log($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append 'E:\9.1\m03\cluster.log' }

$srv=Connect-VIServer $VC -User 'administrator@vsphere.local' -Password $VCPass -Force
$cl=Get-Cluster -Name $ClusterN; $dc=Get-Datacenter -Name $DC
Log "cluster $($cl.Name), hosts now: $((Get-VMHost -Location $cl).Name -join ', ')"

if(-not $SkipHostAdd){
  foreach($h in $NewHosts){
    if(Get-VMHost -Name $h -ErrorAction SilentlyContinue){ Log "  $h 已在"; continue }
    Log "  adding $h ..."
    Add-VMHost -Name $h -Location $cl -User root -Password $ESXPass -Force -Confirm:$false | Out-Null
  }
}
$hosts=Get-VMHost -Location $cl | Sort-Object Name
Log "hosts: $($hosts.Name -join ', ')"

if(-not $SkipVds){
  $vds=Get-VDSwitch -Name $VdsName -ErrorAction SilentlyContinue
  if(-not $vds){ Log "建 VDS $VdsName (MTU $VdsMtu)"; $vds=New-VDSwitch -Name $VdsName -Location $dc -Mtu $VdsMtu -NumUplinkPorts 2 }
  foreach($pg in @(@{n=$PgMgmt;v=0},@{n=$PgVmot;v=$VlanVmot},@{n=$PgVsan;v=$VlanVsan})){
    if(Get-VDPortgroup -VDSwitch $vds -Name $pg.n -ErrorAction SilentlyContinue){ continue }
    Log "  portgroup $($pg.n) (VLAN $($pg.v))"
    $p=New-VDPortgroup -VDSwitch $vds -Name $pg.n -VlanId $pg.v
    $spec=New-Object VMware.Vim.DVPortgroupConfigSpec
    $spec.ConfigVersion=$p.ExtensionData.Config.ConfigVersion
    $spec.DefaultPortConfig=New-Object VMware.Vim.VMwareDVSPortSetting
    $sec=New-Object VMware.Vim.DVSSecurityPolicy
    foreach($f in 'AllowPromiscuous','ForgedTransmits','MacChanges'){ $b=New-Object VMware.Vim.BoolPolicy; $b.Value=$true; $sec.$f=$b }
    $sec.Inherited=$false; $spec.DefaultPortConfig.SecurityPolicy=$sec
    $p.ExtensionData.ReconfigureDVPortgroup_Task($spec) | Out-Null
  }
  foreach($h in $hosts){
    if(-not (Get-VDSwitch -VMHost $h -Name $VdsName -ErrorAction SilentlyContinue)){
      Log "  加 $($h.Name) 進 VDS"; Add-VDSwitchVMHost -VDSwitch $vds -VMHost $h -Confirm:$false | Out-Null }
    $vdsPnics=@(Get-VMHostNetworkAdapter -VMHost $h -Physical -DistributedSwitch $vds -ErrorAction SilentlyContinue)
    if($vdsPnics.Name -notcontains $UplinkNics[1]){
      Log "  掛 $($UplinkNics[1]) on $($h.Name)"
      $nic1=Get-VMHostNetworkAdapter -VMHost $h -Physical -Name $UplinkNics[1]
      Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic $nic1 -Confirm:$false | Out-Null
      $vdsPnics=@(Get-VMHostNetworkAdapter -VMHost $h -Physical -DistributedSwitch $vds)
    }
    if($vdsPnics.Count -lt 1){ throw "$($h.Name): VDS 上沒有 uplink,中止" }
    Log "  $($h.Name) VDS uplinks: $($vdsPnics.Name -join ', ')"
    $mgmtPgObj=Get-VDPortgroup -VDSwitch $vds -Name $PgMgmt
    foreach($vm in (Get-VM -Location $h -ErrorAction SilentlyContinue)){
      foreach($na in (Get-NetworkAdapter -VM $vm)){
        if($na.NetworkName -ne $PgMgmt){ Log "  搬 VM $($vm.Name) NIC -> $PgMgmt"
          Set-NetworkAdapter -NetworkAdapter $na -Portgroup $mgmtPgObj -Confirm:$false | Out-Null } } }
    $vmk0=Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
    if($vmk0.PortGroupName -ne $PgMgmt){
      Log "  搬 vmk0 + $($UplinkNics[0]) on $($h.Name)"
      $nic0=Get-VMHostNetworkAdapter -VMHost $h -Physical -Name $UplinkNics[0]
      Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic $nic0 `
        -VirtualNicPortgroup $mgmtPgObj -VMHostVirtualNic $vmk0 -Confirm:$false | Out-Null
    }
  }
}

if(-not $SkipVsan){
  foreach($h in $hosts){
    if(Get-VsanDiskGroup -VMHost $h -ErrorAction SilentlyContinue){ Log "  $($h.Name) disk group 已存在"; continue }
    $all=Get-ScsiLun -VmHost $h -LunType disk
    $cache=$all|Where-Object{[math]::Round($_.CapacityGB) -ge 95 -and [math]::Round($_.CapacityGB) -le 105}|Select-Object -First 1
    $cap  =$all|Where-Object{[math]::Round($_.CapacityGB) -ge 900}|Select-Object -First 1
    if(-not $cache -or -not $cap){ Log "  !! $($h.Name): cache/capacity 找不到"; continue }
    Log "  $($h.Name) disk group: cache $($cache.CanonicalName) + capacity $($cap.CanonicalName)"
    New-VsanDiskGroup -VMHost $h -SsdCanonicalName $cache.CanonicalName -DataDiskCanonicalName $cap.CanonicalName -Confirm:$false | Out-Null
  }
}
Log "開 DRS + HA"
Set-Cluster -Cluster $cl -DrsEnabled $true -DrsAutomationLevel FullyAutomated -Confirm:$false | Out-Null
Set-Cluster -Cluster $cl -HAEnabled $true -Confirm:$false | Out-Null
Log "=== summary ==="
Get-VMHost -Location $cl | Sort-Object Name | Select-Object Name,ConnectionState,Version,Build |
  Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Get-Datastore | Select-Object Name,Type,CapacityGB,FreeSpaceGB | Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Disconnect-VIServer $srv -Confirm:$false | Out-Null
