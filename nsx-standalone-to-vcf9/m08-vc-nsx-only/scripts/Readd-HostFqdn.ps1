# VCF converge requires FQDN host names. Proven flow (esx02, 2026-10-24):
#  MM(EnsureAccessibility) -> move out of cluster (NSX TNC auto-unprep) -> remove from VDS -> remove from vCenter
#  -> add by FQDN to DC -> add VDS+vmnic1 -> move into cluster -> wait NSX TN success (retry TNC) -> exit MM
#  Prereq: host DNS must resolve *.home.lab (only 10.0.0.200; 10.0.0.1 returns NXDOMAIN) else vLCM DepotConnectError
param([Parameter(Mandatory)][string]$Ip,[Parameter(Mandatory)][string]$Fqdn)
$ErrorActionPreference='Stop'
$PCLI='13.5.1.25718932'; 'Sdk','Core','Vds' | % { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
function L($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append 'E:\9.1\m08-clean\readd-fqdn.log' }
$P=$env:VCPASS   # vCenter SSO + ESXi root (lab: same password)
$cred=New-Object PSCredential('admin',(ConvertTo-SecureString $P -AsPlainText -Force))
$B='https://10.0.1.145/policy/api/v1/infra/sites/default/enforcement-points/default'
function Tn($rx){ (Invoke-RestMethod "$B/host-transport-nodes" -Credential $cred -Authentication Basic -SkipCertificateCheck).results | ? { $_.display_name -match $rx } }
$vc=Connect-VIServer 10.0.1.144 -User administrator@vsphere.local -Password $P -Force
$dc=Get-Datacenter m08-dc; $cl=Get-Cluster m08-cl01; $vds=Get-VDSwitch m08-vds01
$h=Get-VMHost $Ip
L "=== $Ip -> $Fqdn ; VMs: $((Get-VM -Location $h | % Name) -join ',')"
Set-VMHost -VMHost $h -State Maintenance -VsanDataMigrationMode EnsureAccessibility -Evacuate:$true -Confirm:$false | Out-Null
L "in MM"
Move-VMHost -VMHost $h -Destination $dc -Confirm:$false | Out-Null; L "moved out of cluster"
$short=$Ip.Split('.')[-1]
for($i=0;$i -lt 30;$i++){ Start-Sleep 20; $v=(Get-VMHostNetworkAdapter -VMHost (Get-VMHost $Ip) -VMKernel).Name; if(-not ($v -match 'vmk10|vmk50')){ break } }
L "NSX unprepped; vmks: $((Get-VMHostNetworkAdapter -VMHost (Get-VMHost $Ip) -VMKernel).Name -join ',')"
Remove-VDSwitchVMHost -VDSwitch $vds -VMHost (Get-VMHost $Ip) -Confirm:$false; L "removed from VDS"
Remove-VMHost -VMHost (Get-VMHost $Ip) -Confirm:$false; L "removed from vCenter"
Start-Sleep 10
$n=Add-VMHost -Name $Fqdn -Location $dc -User root -Password $P -Force -Confirm:$false; L "added $($n.Name) state=$($n.ConnectionState)"
Add-VDSwitchVMHost -VDSwitch $vds -VMHost $n | Out-Null
Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic (Get-VMHostNetworkAdapter -VMHost $n -Physical -Name vmnic1) -Confirm:$false; L "VDS+vmnic1"
if((Get-VMHost $Fqdn).ConnectionState -ne 'Maintenance'){ Set-VMHost -VMHost (Get-VMHost $Fqdn) -State Maintenance -VsanDataMigrationMode NoDataMigration -Confirm:$false | Out-Null }
Move-VMHost -VMHost (Get-VMHost $Fqdn) -Destination $cl -Confirm:$false | Out-Null; L "into cluster; vSAN DG=$((Get-VsanDiskGroup -VMHost (Get-VMHost $Fqdn)).Count)"
Disconnect-VIServer $vc -Confirm:$false
$name=$Fqdn.Split('.')[0]; $ok=$false
for($i=0;$i -lt 40;$i++){
  Start-Sleep 30; $t=Tn $name
  if($t){ $st=Invoke-RestMethod "$B/host-transport-nodes/$($t.id)/state" -Credential $cred -Authentication Basic -SkipCertificateCheck
    L "NSX $($st.state)/$($st.node_deployment_state.state) $($st.deployment_progress_state.current_step_title)"
    if($st.state -eq 'success'){ $ok=$true; break }
    if($st.node_deployment_state.state -eq 'failed'){ Invoke-RestMethod "$B/transport-node-collections/m08-tnc?action=retry_profile_realization" -Method Post -Credential $cred -Authentication Basic -SkipCertificateCheck | Out-Null; L "retry TNC" } }
}
$vc=Connect-VIServer 10.0.1.144 -User administrator@vsphere.local -Password $P -Force
Set-VMHost -VMHost (Get-VMHost $Fqdn) -State Connected -Confirm:$false | Out-Null
L "exit MM -> $((Get-VMHost $Fqdn).ExtensionData.Runtime.InMaintenanceMode) ; NSX ok=$ok"
Disconnect-VIServer $vc -Confirm:$false
