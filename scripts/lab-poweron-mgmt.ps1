$ErrorActionPreference='Continue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TApm:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TApm
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$H=@{'vmware-api-session-id'=(Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"})}
$vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $H
foreach($name in @('vcf-m01-nsx01a','vcf-m01-sddcm01')){
  $v=$vms | Where-Object {$_.name -eq $name}
  if($v.power_state -eq 'POWERED_ON'){ Write-Host "$name already ON" }
  elseif($v){ try{ Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$($v.vm)/power?action=start" -Headers $H | Out-Null; Write-Host "$name -> start" }catch{ Write-Host "$name err: $($_.Exception.Message)" } }
}
Write-Host "=== re-enable vCLS (retreat off) ==="
& powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\mjalan\Documents\vspher8to9\vcls-retreat.ps1" true | Select-String UPDATE