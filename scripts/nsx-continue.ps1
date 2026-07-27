param([string]$action='continue',[string]$component='HOST')
$ErrorActionPreference='Continue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAnc:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAnc
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$nsx='192.168.110.143'; $u='admin'; $p='<NSX_PASSWORD>'
# form-based session to get XSRF token
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$body="j_username=$u&j_password=$([uri]::EscapeDataString($p))"
$r=Invoke-WebRequest -Uri "https://$nsx/api/session/create" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -WebSession $sess -UseBasicParsing
$xsrf=$r.Headers['x-xsrf-token']
Write-Host "session ok, xsrf=$($xsrf.Substring(0,8))..."
$H=@{ 'X-XSRF-TOKEN'=$xsrf; 'Content-Type'='application/json' }
# try continue/upgrade host plan
$paths=@(
 "/api/v1/upgrade/plan?action=$action&component_type=$component",
 "/api/v1/upgrade?action=$action&component_type=$component",
 "/api/v1/upgrade?action=$action"
)
foreach($pa in $paths){
  try{
    $resp=Invoke-WebRequest -Uri "https://$nsx$pa" -Method Post -Headers $H -WebSession $sess -UseBasicParsing
    Write-Host "OK POST $pa -> $($resp.StatusCode)"
    break
  }catch{
    $code=$_.Exception.Response.StatusCode.value__
    $b=''; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $b=$sr.ReadToEnd()}
    Write-Host "POST $pa -> $code : $($b.Substring(0,[math]::Min(300,$b.Length)))"
  }
}