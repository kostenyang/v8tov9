param([string]$mode='query')  # query | false | true
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAr:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAr
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr = @{ 'Content-Type'='text/xml; charset=utf-8' }
$login = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null = Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing
$key='config.vcls.clusters.domain-c9.enabled'

if($mode -eq 'query'){
  $q = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:QueryOptions><urn:_this type="OptionManager">VpxSettings</urn:_this><urn:name>$key</urn:name></urn:QueryOptions>
</soapenv:Body></soapenv:Envelope>
"@
  try{
    $r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q -Headers $hdr -WebSession $sess -UseBasicParsing
    Write-Host "QUERY RESULT:"; Write-Host $r.Content
  }catch{ if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd()} }
} else {
  $val = $mode  # 'true' or 'false'
  $up = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:UpdateOptions><urn:_this type="OptionManager">VpxSettings</urn:_this>
<urn:changedValue xsi:type="OptionValue" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<urn:key>$key</urn:key><urn:value xsi:type="xsd:string" xmlns:xsd="http://www.w3.org/2001/XMLSchema">$val</urn:value>
</urn:changedValue></urn:UpdateOptions>
</soapenv:Body></soapenv:Envelope>
"@
  try{
    $r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $up -Headers $hdr -WebSession $sess -UseBasicParsing
    Write-Host "UPDATE ($key=$val) OK"; Write-Host $r.Content
  }catch{ Write-Host "UPDATE ERR"; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd()} }
}