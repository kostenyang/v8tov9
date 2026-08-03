$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAe:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAe
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr = @{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null = Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing

# fetch EventManager.latestPage
$rp = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>EventManager</urn:type><urn:pathSet>latestPage</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="EventManager">EventManager</urn:obj></urn:objectSet></urn:specSet>
<urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
try{ $r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $rp -Headers $hdr -WebSession $sess -UseBasicParsing }
catch{ if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host ($sr.ReadToEnd())}; exit }
[xml]$x=$r.Content
$msgs = $x.SelectNodes("//*[local-name()='fullFormattedMessage']")
Write-Host "EVENTS: $($msgs.Count)"
$seen=@{}
foreach($m in $msgs){
  $t=$m.InnerText
  if($t -match 'vCLS' -or $t -match 'power on' -or $t -match 'agent' -or $t -match 'insufficient' -or $t -match 'fail' -or $t -match 'cannot'){
    if(-not $seen.ContainsKey($t)){ $seen[$t]=1; Write-Host "  * $t" }
  }
}