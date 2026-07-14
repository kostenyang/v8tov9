$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAs:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAs
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

$checks = @('controllerdiskmode','controlleronhcl','controllerdriver','controllerfirmware','controllerreleasesupport','hcldbuptodate','hcldiskclaimcheck','hclhostbadstate')
$adds = ($checks | ForEach-Object { "<addSilentChecks>$_</addSilentChecks>" }) -join ''
$req = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<VsanHealthSetVsanClusterSilentChecks xmlns="urn:vsan">
<_this type="VsanVcClusterHealthSystem">vsan-cluster-health-system</_this>
<cluster type="ClusterComputeResource">domain-c9</cluster>
$adds
</VsanHealthSetVsanClusterSilentChecks>
</soapenv:Body></soapenv:Envelope>
"@
$vhdr = @{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vsan/8.0.2.0' }
try{
  $r=Invoke-WebRequest -Uri "https://$vc/vsanHealth" -Method Post -Body $req -Headers $vhdr -WebSession $sess -UseBasicParsing
  Write-Host "SILENCE OK"; Write-Host $r.Content
}catch{ Write-Host "SILENCE ERR"; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd()} }
