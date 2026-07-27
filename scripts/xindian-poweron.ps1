$ErrorActionPreference='Continue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TApon2:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TApon2
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.32'; $u='administrator@vsphere.local'; $p='<PHYSICAL_VC_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
foreach($vm in @('vm-29025','vm-29026','vm-29027','vm-29028')){
  $s=(Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm/power" -Headers $H).state
  if($s -eq 'POWERED_ON'){ Write-Host "$vm already ON" }
  else{ try{ Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=start" -Headers $H | Out-Null; Write-Host "$vm -> start issued" }catch{ Write-Host "$vm err: $($_.Exception.Message)" } }
}