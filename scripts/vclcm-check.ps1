$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAx:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAx
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
$cid='domain-c9'

Write-Host "=== trigger check (async) ==="
try{
  $tid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/esx/settings/clusters/$cid/software`?action=check&vmw-task=true" -Headers $H -Body '{}' -ContentType 'application/json'
  Write-Host "TASK: $tid"
}catch{ Write-Host "CHECK ERR $($_.Exception.Message)"; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host ($sr.ReadToEnd())}; exit }

for($i=0;$i -lt 30;$i++){
  Start-Sleep 6
  try{ $t=Invoke-RestMethod -Uri "https://$vc/api/cis/tasks/$tid" -Headers $H }catch{ continue }
  Write-Host "  status=$($t.status) progress=$($t.progress.completed)"
  if($t.status -eq 'SUCCEEDED' -or $t.status -eq 'FAILED'){ break }
}
Write-Host "=== last-check-result after ==="
try{
 $r=Invoke-RestMethod -Uri "https://$vc/api/esx/settings/clusters/$cid/software/reports/last-check-result" -Headers $H
 $r | ConvertTo-Json -Depth 10
}catch{ Write-Host "ERR $($_.Exception.Message)"; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host ($sr.ReadToEnd())} }
