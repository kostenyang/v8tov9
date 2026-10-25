# m08 converge prereq: migrate each host's vmnic0 + vmk0 (mgmt) from vSwitch0 to m08-vds01-pg-mgmt,
# atomically so vMotion rollback protects us if vCenter connection drops. vmnic1 is already the VDS uplink.
$PCLI='13.5.1.25718932'; 'Sdk','Core','Vds' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false -Confirm:$false -Scope Session | Out-Null
$log='E:\9.1\m08-clean\vmk0-migrate.log'
function L($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append $log }

$vc=Connect-VIServer vcf-m08-vc01.home.lab -User administrator@vsphere.local -Password $env:VCPASS -Force
$vds=Get-VDSwitch m08-vds01
$pg =Get-VDPortgroup -VDSwitch $vds -Name 'm08-vds01-pg-mgmt'

foreach($hn in 'vcf-m08-esx01.home.lab','vcf-m08-esx02.home.lab','vcf-m08-esx03.home.lab'){
  $h=Get-VMHost $hn
  $vmk0=Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
  if($vmk0.ExtensionData.Spec.DistributedVirtualPort){ L "$hn vmk0 already on VDS, skip"; continue }
  $vmnic0=Get-VMHostNetworkAdapter -VMHost $h -Physical -Name vmnic0
  L "${hn}: moving vmnic0 + vmk0 -> $($pg.Name)"
  # single call: add pnic AND move the vmkernel in one host network reconfigure
  Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic $vmnic0 `
      -VMHostVirtualNic $vmk0 -VirtualNicPortgroup $pg -Confirm:$false
  Start-Sleep 8
  $vmk0b=Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
  L ("  result: vmk0 onVDS={0}; VDS uplinks now [{1}]" -f [bool]$vmk0b.ExtensionData.Spec.DistributedVirtualPort, ((Get-VDSwitch m08-vds01 | Get-VMHostNetworkAdapter -VMHost $h -Physical).Name -join ','))
  # verify host still responding
  Start-Sleep 5
  $st=(Get-VMHost $hn).ConnectionState
  L "  host state=$st"
  if($st -ne 'Connected'){ L "  !! host not Connected - stopping"; break }
}
L "=== summary ==="
Get-VMHost | Sort Name | % { $v=Get-VMHostNetworkAdapter -VMHost $_ -Name vmk0; L ("  {0}: vmk0 onVDS={1} state={2}" -f $_.Name,[bool]$v.ExtensionData.Spec.DistributedVirtualPort,$_.ConnectionState) }
Disconnect-VIServer $vc -Confirm:$false
