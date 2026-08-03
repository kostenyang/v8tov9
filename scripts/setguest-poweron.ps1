param([string]$vm,[string]$gid='vmkernel7Guest')
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAsp:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAsp
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
$rc=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:ReconfigVM_Task><urn:_this type="VirtualMachine">$vm</urn:_this><urn:spec><urn:guestId>$gid</urn:guestId></urn:spec></urn:ReconfigVM_Task>
</soapenv:Body></soapenv:Envelope>
"@
$null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $rc -Headers $hdr -WebSession $sess -UseBasicParsing
Start-Sleep 4
Write-Host "[$vm] guestOS now = $((Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm" -Headers $RH).guest_OS)"
# power on via SOAP, capture fault
$po=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:PowerOnVM_Task><urn:_this type="VirtualMachine">$vm</urn:_this></urn:PowerOnVM_Task>
</soapenv:Body></soapenv:Envelope>
"@
$r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $po -Headers $hdr -WebSession $sess -UseBasicParsing
$tid=([xml]$r.Content).SelectSingleNode("//*[local-name()='returnval']").InnerText
Start-Sleep 8
$tq=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>Task</urn:type><urn:pathSet>info.state</urn:pathSet><urn:pathSet>info.error</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="Task">$tid</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
$tr=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $tq -Headers $hdr -WebSession $sess -UseBasicParsing
$state=([xml]$tr.Content).SelectSingleNode("//*[local-name()='name'][.='info.state']/following-sibling::*[local-name()='val']").InnerText
Write-Host "[$vm] power-on task state = $state"
if($state -eq 'error'){ Write-Host $tr.Content }