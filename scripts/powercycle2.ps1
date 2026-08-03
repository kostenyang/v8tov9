param([string]$vm)
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TApc2:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TApc2
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.32'; $u='administrator@vsphere.local'; $p='<PHYSICAL_VC_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$rsid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$RH=@{'vmware-api-session-id'=$rsid}
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing
function Get-Pwr($vm){ (Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm/power" -Headers $RH).state }
Write-Host "[$vm] power=$(Get-Pwr $vm), guestOS=$((Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm" -Headers $RH).guest_OS)"
# power off
if((Get-Pwr $vm) -eq 'POWERED_ON'){
  try{ Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/guest/power?action=shutdown" -Headers $RH | Out-Null; Write-Host "guest shutdown issued" }catch{ Write-Host "hard stop"; Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=stop" -Headers $RH | Out-Null }
  for($i=0;$i -lt 25;$i++){ Start-Sleep 6; if((Get-Pwr $vm) -eq 'POWERED_OFF'){break}; Write-Host "  ...waiting off" }
  if((Get-Pwr $vm) -ne 'POWERED_OFF'){ try{Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=stop" -Headers $RH|Out-Null}catch{}; Start-Sleep 8 }
}
Write-Host "[$vm] powered off. Setting guestId=vmkernel8Guest ..."
$rc=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:ReconfigVM_Task><urn:_this type="VirtualMachine">$vm</urn:_this><urn:spec><urn:guestId>vmkernel8Guest</urn:guestId></urn:spec></urn:ReconfigVM_Task>
</soapenv:Body></soapenv:Envelope>
"@
$r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $rc -Headers $hdr -WebSession $sess -UseBasicParsing
Start-Sleep 4
Write-Host "[$vm] guestOS now = $((Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm" -Headers $RH).guest_OS)"
Write-Host "[$vm] powering on..."
Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=start" -Headers $RH | Out-Null
Write-Host "[$vm] started. power=$(Get-Pwr $vm)"