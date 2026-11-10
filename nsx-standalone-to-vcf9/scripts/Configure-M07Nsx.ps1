# =============================================================================
# m07 第二輪(10-22):NSX 4.2.1 單節點部好後 → compute manager → host prep(policy API)
#   1. compute manager vcf-m07-vc01(SHA-256 thumbprint 現抓,OIDC on)
#   2. uplink profile m07-uplink-profile(FAILOVER_ORDER uplink-1,transport VLAN 0)
#   3. TEP pool m07-tep-pool 192.168.173.11-20 /24(同 L2,不設 gw)
#   4. TNP m07-tnp:VDS m07-vds01 + 內建 overlay TZ(nsx-overlay-transportzone)
#   5. TNC 套到 m07-cl01 → 等 3 台 host prep SUCCESS
#   需要 $env:NSXPASS(admin)、$env:VCPASS(vCenter SSO);VDS uuid/uplink 名稱從 vCenter 讀
# =============================================================================
$ErrorActionPreference = 'Stop'
$N = 'https://10.0.1.165'
$cred = New-Object PSCredential('admin', (ConvertTo-SecureString $env:NSXPASS -AsPlainText -Force))
$LogFile = 'E:\9.1\m07-521\configure-nsx.log'
function Log($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append $LogFile }
function Nsx($method, $path, $body) {
  $p = @{ Uri = "$N$path"; Method = $method; Credential = $cred; Authentication = 'Basic'; SkipCertificateCheck = $true; ContentType = 'application/json' }
  if ($body) { $p.Body = ($body | ConvertTo-Json -Depth 12) }
  Invoke-RestMethod @p
}

# --- vCenter side facts: thumbprint, VDS uuid + uplink name, cluster moref
$tcp = New-Object Net.Sockets.TcpClient('10.0.1.164', 443)
$ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, { $true }); $ssl.AuthenticateAsClient('vcf-m07-vc01.home.lab')
$x509 = New-Object Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
$thumb = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($x509.RawData))) -replace '-', ':'
$ssl.Dispose(); $tcp.Dispose()
Log "vC thumbprint $thumb"

$PCLI = '13.5.1.25718932'
'Sdk','Core','Vds' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false -Confirm:$false -Scope Session | Out-Null
$vc = Connect-VIServer vcf-m07-vc01.home.lab -User administrator@vsphere.local -Password $env:VCPASS -Force
$vds = Get-VDSwitch m07-vds01
$vdsUuid = $vds.ExtensionData.Uuid
$vdsUplink = $vds.ExtensionData.Config.UplinkPortPolicy.UplinkPortName[0]
Disconnect-VIServer $vc -Confirm:$false
Log "VDS uuid=$vdsUuid uplink='$vdsUplink'"

# --- 1. compute manager
$cm = (Nsx GET '/api/v1/fabric/compute-managers').results | Where-Object server -in 'vcf-m07-vc01.home.lab','10.0.1.164'
if (-not $cm) {
  $cm = Nsx POST '/api/v1/fabric/compute-managers' @{
    server = 'vcf-m07-vc01.home.lab'; origin_type = 'vCenter'; display_name = 'vcf-m07-vc01'; set_as_oidc_provider = $true
    credential = @{ credential_type = 'UsernamePasswordLoginCredential'; username = 'administrator@vsphere.local'; password = $env:VCPASS; thumbprint = $thumb } }
  Log "compute manager created $($cm.id)"
}
$d = (Get-Date).AddMinutes(15)
do { Start-Sleep 20; $st = Nsx GET "/api/v1/fabric/compute-managers/$($cm.id)/status"; Log "CM registration=$($st.registration_status) connection=$($st.connection_status)" }
while (($st.registration_status -ne 'REGISTERED' -or $st.connection_status -ne 'UP') -and (Get-Date) -lt $d)

# --- 2. uplink profile
Nsx PATCH '/policy/api/v1/infra/host-switch-profiles/m07-uplink-profile' @{
  resource_type = 'PolicyUplinkHostSwitchProfile'; display_name = 'm07-uplink-profile'; transport_vlan = 0
  teaming = @{ policy = 'FAILOVER_ORDER'; active_list = @(@{ uplink_name = 'uplink-1'; uplink_type = 'PNIC' }) } } | Out-Null
Log 'uplink profile m07-uplink-profile'

# --- 3. TEP pool
Nsx PATCH '/policy/api/v1/infra/ip-pools/m07-tep-pool' @{ display_name = 'm07-tep-pool' } | Out-Null
Nsx PATCH '/policy/api/v1/infra/ip-pools/m07-tep-pool/ip-subnets/m07-tep-subnet' @{
  resource_type = 'IpAddressPoolStaticSubnet'; cidr = '192.168.173.0/24'
  allocation_ranges = @(@{ start = '192.168.173.11'; end = '192.168.173.20' }) } | Out-Null
Log 'TEP pool m07-tep-pool 192.168.173.11-20'

# --- 4. TNP (default overlay TZ)
$tz = (Nsx GET '/policy/api/v1/infra/sites/default/enforcement-points/default/transport-zones').results |
      Where-Object { $_.tz_type -eq 'OVERLAY_STANDARD' -and $_.is_default } | Select-Object -First 1
Log "overlay TZ $($tz.display_name) $($tz.path)"
Nsx PUT '/policy/api/v1/infra/host-transport-node-profiles/m07-tnp' @{
  resource_type = 'PolicyHostTransportNodeProfile'; display_name = 'm07-tnp'
  host_switch_spec = @{ resource_type = 'StandardHostSwitchSpec'; host_switches = @(@{
    host_switch_id = $vdsUuid; host_switch_type = 'VDS'; host_switch_mode = 'STANDARD'
    host_switch_profile_ids = @(@{ key = 'UplinkHostSwitchProfile'; value = '/infra/host-switch-profiles/m07-uplink-profile' })
    uplinks = @(@{ uplink_name = 'uplink-1'; vds_uplink_name = $vdsUplink })
    ip_assignment_spec = @{ resource_type = 'StaticIpPoolSpec'; ip_pool_id = '/infra/ip-pools/m07-tep-pool' }
    transport_zone_endpoints = @(@{ transport_zone_id = $tz.path }) }) } } | Out-Null
Log 'TNP m07-tnp'

# --- 5. TNC on m07-cl01
$d = (Get-Date).AddMinutes(10)
do { $cc = (Nsx GET '/api/v1/fabric/compute-collections').results | Where-Object display_name -eq 'm07-cl01'; if (-not $cc) { Start-Sleep 20 } } while (-not $cc -and (Get-Date) -lt $d)
Log "compute collection $($cc.external_id)"
Nsx PUT '/policy/api/v1/infra/sites/default/enforcement-points/default/transport-node-collections/m07-tnc' @{
  resource_type = 'HostTransportNodeCollection'; display_name = 'm07-tnc'
  compute_collection_id = $cc.external_id; transport_node_profile_id = '/infra/host-transport-node-profiles/m07-tnp' } | Out-Null
Log 'TNC m07-tnc applied -> host prep running'

$d = (Get-Date).AddMinutes(45)
do {
  Start-Sleep 60
  $s = Nsx GET '/policy/api/v1/infra/sites/default/enforcement-points/default/transport-node-collections/m07-tnc/state'
  Log "TNC state=$($s.state) " + (($s.validation_errors | ForEach-Object discovered_node_id) -join ',')
} while ($s.state -notin 'success','failed_to_realize','failed' -and (Get-Date) -lt $d)

$tn = (Nsx GET '/policy/api/v1/infra/sites/default/enforcement-points/default/host-transport-nodes').results
foreach ($t in $tn) {
  $ts = Nsx GET "/policy/api/v1/infra/sites/default/enforcement-points/default/host-transport-nodes/$($t.id)/state"
  Log ("  {0,-26} {1}" -f $t.display_name, $ts.state)
}
Log 'done'
