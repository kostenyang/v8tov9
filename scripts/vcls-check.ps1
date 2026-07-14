$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAv:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAv
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
$cid='domain-c9'
Write-Host "=== VMs in cluster (name / power) ==="
$vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=$cid" -Headers $H
$vms | Sort-Object name | ForEach-Object { Write-Host ("  {0,-40} {1}" -f $_.name,$_.power_state) }
Write-Host "=== vCLS VMs ==="
$vms | Where-Object { $_.name -like 'vCLS*' } | ForEach-Object { Write-Host "  $($_.vm)  $($_.name)  $($_.power_state)" }
