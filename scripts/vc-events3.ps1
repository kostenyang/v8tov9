$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAe3:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAe3
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
$begin = (Get-Date).ToUniversalTime().AddMinutes(-6).ToString("yyyy-MM-ddTHH:mm:ssZ")
$q = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:QueryEvents><urn:_this type="EventManager">EventManager</urn:_this>
<urn:filter>
<urn:entity><urn:entity type="ClusterComputeResource">domain-c9</urn:entity><urn:recursion>all</urn:recursion></urn:entity>
<urn:time><urn:beginTime>$begin</urn:beginTime></urn:time>
</urn:filter></urn:QueryEvents></soapenv:Body></soapenv:Envelope>
"@
$r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q -Headers $hdr -WebSession $sess -UseBasicParsing
[xml]$x=$r.Content
$events = $x.SelectNodes("//*[local-name()='returnval']/*[local-name()='Event' or local-name()='EventEx' or local-name()='TaskEvent']")
# fall back: iterate all children of returnval
$rv = $x.SelectSingleNode("//*[local-name()='QueryEventsResponse']/*[local-name()='returnval']")
if(-not $rv){ $rv = $x.SelectSingleNode("//*[local-name()='returnval']") }
$items = @()
if($rv){ foreach($c in $rv.ChildNodes){ $items += $c } }
Write-Host "EVENTS last 6m: $($items.Count)"
$list=@()
foreach($e in $items){
  $ct=$e.SelectSingleNode("./*[local-name()='createdTime']").InnerText
  $fm=$e.SelectSingleNode("./*[local-name()='fullFormattedMessage']")
  $msg = if($fm){$fm.InnerText}else{''}
  if($msg -match 'vCLS' -or $msg -match 'ower' -or $msg -match 'ail' -or $msg -match 'rror' -or $msg -match 'esource' -or $msg -match 'econfig' -or $msg -match 'reate' -or $msg -match 'emove'){
    $list += [pscustomobject]@{t=$ct; m=$msg}
  }
}
$list | Sort-Object t | Select-Object -Last 40 | ForEach-Object { Write-Host "$($_.t)  $($_.m)" }