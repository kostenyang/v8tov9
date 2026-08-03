# nsx-precheck.ps1 — 建 session+XSRF，跑 pre-upgrade-checks 並輪詢
$ErrorActionPreference='Continue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAncP:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAncP
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$nsx='192.168.110.143'; $u='admin'; $p='<NSX_SDDC_OPS_PASSWORD>'
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$body="j_username=$u&j_password=$([uri]::EscapeDataString($p))"
$r=Invoke-WebRequest -Uri "https://$nsx/api/session/create" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -WebSession $sess -UseBasicParsing
$xsrf=$r.Headers['x-xsrf-token']
if($xsrf -is [array]){$xsrf=$xsrf[0]}
"session ok, xsrf=$($xsrf.Substring(0,8))..."
$H=@{ 'X-XSRF-TOKEN'=$xsrf }

# 啟動 pre-upgrade-checks
foreach($pa in @('/api/v1/upgrade/pre-upgrade-checks','/api/v1/upgrade?action=pre_upgrade_checks')){
  try{
    $resp=Invoke-WebRequest -Uri "https://$nsx$pa" -Method Post -Headers $H -WebSession $sess -UseBasicParsing
    "OK POST $pa -> $($resp.StatusCode)"; break
  }catch{
    $code=$_.Exception.Response.StatusCode.value__
    $b=''; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $b=$sr.ReadToEnd()}
    "POST $pa -> $code : $($b.Substring(0,[math]::Min(200,$b.Length)))"
  }
}
# 輪詢 pre-check 狀態
"=== 輪詢 pre-check 狀態（最多 15 分）==="
$deadline=(Get-Date).AddMinutes(15)
while((Get-Date) -lt $deadline){
  try{
    $s=Invoke-RestMethod -Uri "https://$nsx/api/v1/upgrade/pre-upgrade-checks-info" -Method Get -Headers $H -WebSession $sess
    $st=$s.status; $ec=$s.error_count; $wc=$s.warning_count
    "$(Get-Date -Format HH:mm:ss) precheck status=$st err=$ec warn=$wc"
    if($st -match 'COMPLETED|SUCCESS|FAILED|COMPLETE'){ break }
  }catch{ "poll err: $($_.Exception.Message)" }
  Start-Sleep 20
}
