$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAxl:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAxl
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.32'; $u='administrator@vsphere.local'; $p='<PHYSICAL_VC_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
Write-Host "Xindian vCenter session OK"
$vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm" -Headers $H
$nested = $vms | Where-Object { $_.name -match 'vcf-m01-esx' }
foreach($v in ($nested | Sort-Object name)){
  # get host placement
  $info=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$($v.vm)" -Headers $H
  Write-Host "$($v.vm)  $($v.name)  power=$($v.power_state)"
}
