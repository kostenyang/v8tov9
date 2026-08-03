param([string]$vm, [string]$hostip)
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TApc:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TApc
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.32'; $u='administrator@vsphere.local'; $p='<PHYSICAL_VC_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
function Get-Pwr($vm){ (Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm/power" -Headers $H).state }
Write-Host "[$vm] current power = $(Get-Pwr $vm)"
# graceful guest shutdown
try{ Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/guest/power?action=shutdown" -Headers $H | Out-Null; Write-Host "guest shutdown issued" }
catch{ Write-Host "guest shutdown failed ($($_.Exception.Message)); doing hard power off"; Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=stop" -Headers $H | Out-Null }
for($i=0;$i -lt 30;$i++){ Start-Sleep 6; $s=Get-Pwr $vm; if($s -eq 'POWERED_OFF'){ break }; Write-Host "  waiting power off... ($s)" }
if((Get-Pwr $vm) -ne 'POWERED_OFF'){ Write-Host "still not off, hard stop"; try{Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=stop" -Headers $H | Out-Null}catch{}; Start-Sleep 8 }
Write-Host "[$vm] powered off. Powering on..."
Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=start" -Headers $H | Out-Null
Write-Host "[$vm] power on issued. state=$(Get-Pwr $vm)"
