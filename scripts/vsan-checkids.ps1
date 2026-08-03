$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAc:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAc
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
$vhdr = @{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vsan/8.0.2.0' }
$req = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<VsanQueryAllSupportedHealthChecks xmlns="urn:vsan">
<_this type="VsanVcClusterHealthSystem">vsan-cluster-health-system</_this>
</VsanQueryAllSupportedHealthChecks>
</soapenv:Body></soapenv:Envelope>
"@
try{
 $r=Invoke-WebRequest -Uri "https://$vc/vsanHealth" -Method Post -Body $req -Headers $vhdr -WebSession $sess -UseBasicParsing
 [xml]$x=$r.Content
 $checks=$x.SelectNodes("//*[local-name()='returnval']")
 Write-Host "SUPPORTED CHECKS: $($checks.Count)"
 foreach($c in $checks){
   $id=$c.SelectSingleNode("./*[local-name()='testId']").InnerText
   $nm=$c.SelectSingleNode("./*[local-name()='testName']").InnerText
   if($id -match 'controller' -or $nm -match 'ertified' -or $id -match 'hcl'){ Write-Host "  id=$id  name=$nm" }
 }
}catch{ Write-Host "ERR"; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd()} }