$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAh:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAh
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'

# 1) vim SOAP login on /sdk to get session cookie
$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$soapHdr = @{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }

$login = @"
<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25">
<soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this>
<urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password>
</urn:Login></soapenv:Body></soapenv:Envelope>
"@
$null = Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $soapHdr -WebSession $sess -UseBasicParsing
Write-Host "vim login done (cookies: $($sess.Cookies.GetCookies("https://$vc").Count))"

# 2) vSAN health summary on /vsanHealth
$vsanHdr = @{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vsan/8.0.2.0' }
$req = @"
<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25">
<soapenv:Body>
<VsanQueryVcClusterHealthSummary xmlns="urn:vsan">
<_this type="VsanVcClusterHealthSystem">vsan-cluster-health-system</_this>
<cluster type="ClusterComputeResource">domain-c9</cluster>
<includeObjUuids>false</includeObjUuids>
<fetchFromCache>true</fetchFromCache>
</VsanQueryVcClusterHealthSummary>
</soapenv:Body></soapenv:Envelope>
"@
try{
 $resp = Invoke-WebRequest -Uri "https://$vc/vsanHealth" -Method Post -Body $req -Headers $vsanHdr -WebSession $sess -UseBasicParsing
 $resp.Content | Out-File "C:\Users\mjalan\Documents\vspher8to9\vsan-health-raw.xml" -Encoding utf8
 [xml]$x = $resp.Content
 $ovh = $x.SelectSingleNode("//*[local-name()='overallHealth']")
 if($ovh){ Write-Host "OVERALL HEALTH: $($ovh.InnerText)" }
 $groups = $x.SelectNodes("//*[local-name()='groups']")
 Write-Host "GROUPS: $($groups.Count)"
 foreach($g in $groups){
   $gname = $g.SelectSingleNode("./*[local-name()='groupName']").InnerText
   $ghealth = $g.SelectSingleNode("./*[local-name()='groupHealth']").InnerText
   Write-Host "GROUP [$ghealth] $gname"
   foreach($t in $g.SelectNodes("./*[local-name()='groupTests']")){
      $th=$t.SelectSingleNode("./*[local-name()='testHealth']").InnerText
      $tn=$t.SelectSingleNode("./*[local-name()='testName']").InnerText
      if($th -ne 'green' -and $th -ne 'skipped'){ Write-Host "    [$th] $tn" }
   }
 }
}catch{
 Write-Host "VSAN ERR $($_.Exception.Message)"
 if($_.Exception.Response){ $sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host ($sr.ReadToEnd().Substring(0,[math]::Min(2000,$sr.BaseStream.Length))) }
}
