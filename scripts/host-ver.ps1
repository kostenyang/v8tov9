param([string]$hostmo)
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAhv2:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAhv2
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
$q=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>HostSystem</urn:type>
<urn:pathSet>name</urn:pathSet><urn:pathSet>runtime.connectionState</urn:pathSet><urn:pathSet>runtime.inMaintenanceMode</urn:pathSet><urn:pathSet>summary.config.product.fullName</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="HostSystem">$hostmo</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
$r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q -Headers $hdr -WebSession $sess -UseBasicParsing
[xml]$x=$r.Content
function GV($n){ $x.SelectSingleNode("//*[local-name()='name'][.='$n']/following-sibling::*[local-name()='val']").InnerText }
Write-Host "name=$(GV 'name')"
Write-Host "connectionState=$(GV 'runtime.connectionState')"
Write-Host "inMaintenanceMode=$(GV 'runtime.inMaintenanceMode')"
Write-Host "product=$(GV 'summary.config.product.fullName')"