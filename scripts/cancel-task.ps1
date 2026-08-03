param([string]$task)
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAct:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAct
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing
$c=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:CancelTask><urn:_this type="Task">$task</urn:_this></urn:CancelTask>
</soapenv:Body></soapenv:Envelope>
"@
try{ $null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $c -Headers $hdr -WebSession $sess -UseBasicParsing; Write-Host "cancel $task issued" }
catch{ if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd()} }