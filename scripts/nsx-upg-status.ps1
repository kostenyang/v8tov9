$ErrorActionPreference='Continue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAnu:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAnu
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$nsx='192.168.110.143'; $u='admin'; $p='<NSX_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$H=@{Authorization="Basic $pair"}
function G($path){ try{ return Invoke-RestMethod -Uri "https://$nsx$path" -Headers $H }catch{ Write-Host "  $path -> ERR $($_.Exception.Response.StatusCode.value__)"; return $null } }
Write-Host "=== status-summary (HOST) ==="
$s=G "/api/v1/upgrade/status-summary?component_type=HOST"
if($s){ $s | ConvertTo-Json -Depth 6 }
Write-Host "=== overall status-summary ==="
$o=G "/api/v1/upgrade/status-summary"
if($o){ $o.component_status | ForEach-Object { Write-Host "  $($_.component_type): status=$($_.status) percent=$($_.percentage)" } }