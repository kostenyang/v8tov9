$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAxm:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAxm
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
$vms=@('vm-29025','vm-29026','vm-29027','vm-29028')
foreach($vm in $vms){
  $rc=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soapenv:Body>
<urn:ReconfigVM_Task><urn:_this type="VirtualMachine">$vm</urn:_this>
<urn:spec><urn:extraConfig><urn:key>monitor_control.enable_mwait</urn:key><urn:value xsi:type="xsd:string">TRUE</urn:value></urn:extraConfig></urn:spec>
</urn:ReconfigVM_Task></soapenv:Body></soapenv:Envelope>
"@
  try{ $r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $rc -Headers $hdr -WebSession $sess -UseBasicParsing
    $tid=([xml]$r.Content).SelectSingleNode("//*[local-name()='returnval']").InnerText
    Write-Host "$vm : ReconfigVM task=$tid" }
  catch{ Write-Host "$vm ERR"; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd()} }
}