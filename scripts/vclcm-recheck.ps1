$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TArc:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TArc
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
$cid='domain-c9'
$tid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/esx/settings/clusters/$cid/software`?action=check&vmw-task=true" -Headers $H -Body '{}' -ContentType 'application/json'
for($i=0;$i -lt 40;$i++){ Start-Sleep 6; try{ $t=Invoke-RestMethod -Uri "https://$vc/api/cis/tasks/$tid" -Headers $H }catch{continue}; if($t.status -eq 'SUCCEEDED' -or $t.status -eq 'FAILED'){ break } }
Write-Host "check task: $($t.status)"
$obj=Invoke-RestMethod -Uri "https://$vc/api/esx/settings/clusters/$cid/software/reports/last-check-result" -Headers $H
$anyErr=$false
foreach($er in $obj.entity_results){
  $lbl = if($er.type -eq 'HOST'){$er.host}else{$er.cluster}
  $errs = $er.check_statuses | Where-Object {$_.status -eq 'ERROR'}
  if($errs){ $anyErr=$true; Write-Host "== $($er.type) $lbl =="; foreach($cs in $errs){
    Write-Host "  [ERROR] $($cs.check.name.default_message)"
    foreach($iss in $cs.issues){ Write-Host "      - $($iss.default_message)" }
  } }
}
if(-not $anyErr){ Write-Host "*** NO ERRORS ??all checks pass ***" }
