$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAph:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAph
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.32'; $u='administrator@vsphere.local'; $p='<PHYSICAL_VC_PASSWORD>'
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing
# product + environmentBrowser of host-28001
$q=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>HostSystem</urn:type><urn:pathSet>summary.config.product.fullName</urn:pathSet><urn:pathSet>parent</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="HostSystem">host-28001</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
$r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q -Headers $hdr -WebSession $sess -UseBasicParsing
[xml]$x=$r.Content
$full=$x.SelectSingleNode("//*[local-name()='name'][.='summary.config.product.fullName']/following-sibling::*[local-name()='val']").InnerText
$parent=$x.SelectSingleNode("//*[local-name()='name'][.='parent']/following-sibling::*[local-name()='val']").InnerText
Write-Host "PHYS HOST: $full"
Write-Host "parent CR: $parent"
# environmentBrowser of parent CR
$q2=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>ComputeResource</urn:type><urn:pathSet>environmentBrowser</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="ComputeResource">$parent</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
$r2=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q2 -Headers $hdr -WebSession $sess -UseBasicParsing
$eb=([xml]$r2.Content).SelectSingleNode("//*[local-name()='val']").InnerText
Write-Host "envBrowser: $eb"
# query supported guest ids containing vmkernel
$q3=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:QueryConfigOption><urn:_this type="EnvironmentBrowser">$eb</urn:_this><urn:host type="HostSystem">host-28001</urn:host></urn:QueryConfigOption>
</soapenv:Body></soapenv:Envelope>
"@
$r3=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q3 -Headers $hdr -WebSession $sess -UseBasicParsing
[xml]$x3=$r3.Content
$ids=$x3.SelectNodes("//*[local-name()='guestOSDescriptor']/*[local-name()='id']") | ForEach-Object { $_.InnerText } | Where-Object { $_ -match 'vmkernel|other' }
Write-Host "supported vmkernel/other guestIds:"
$ids | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }