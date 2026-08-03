$ErrorActionPreference='SilentlyContinue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAz:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAz
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
$cid='domain-c9'
$paths=@(
 "/api/vcenter/cluster/$cid/vsan/health",
 "/api/vcenter/vsan/cluster/$cid/health",
 "/api/vsan/health/cluster/$cid",
 "/api/vcenter/namespace-management/clusters/$cid",
 "/api/esx/settings/clusters/$cid/enabled-software/reports/last-check-result"
)
foreach($pa in $paths){
  try{ $r=Invoke-WebRequest -Uri "https://$vc$pa" -Headers $H -UseBasicParsing; Write-Host "OK $pa -> $($r.StatusCode)"; }
  catch{ Write-Host "$($_.Exception.Response.StatusCode.value__) $pa" }
}