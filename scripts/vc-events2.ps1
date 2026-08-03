$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAe2:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAe2
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
$begin = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
$q = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:QueryEvents><urn:_this type="EventManager">EventManager</urn:_this>
<urn:filter>
<urn:entity><urn:entity type="ClusterComputeResource">domain-c9</urn:entity><urn:recursion>all</urn:recursion></urn:entity>
<urn:time><urn:beginTime>$begin</urn:beginTime></urn:time>
</urn:filter>
</urn:QueryEvents></soapenv:Body></soapenv:Envelope>
"@
try{ $r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q -Headers $hdr -WebSession $sess -UseBasicParsing }
catch{ if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host ($sr.ReadToEnd())}; exit }
[xml]$x=$r.Content
$msgs = $x.SelectNodes("//*[local-name()='fullFormattedMessage']")
Write-Host "EVENTS (last 30m, cluster): $($msgs.Count)"
$seen=@{}
foreach($m in $msgs){
  $t=$m.InnerText.Trim()
  if($t -match 'vCLS' -or $t -match 'ower' -or $t -match 'agent' -or $t -match 'nsufficient' -or $t -match 'ail' -or $t -match 'annot' -or $t -match 'rror' -or $t -match 'esource'){
    $k=$t.Substring(0,[math]::Min(120,$t.Length))
    if(-not $seen.ContainsKey($k)){ $seen[$k]=1; Write-Host "  * $t" }
  }
}