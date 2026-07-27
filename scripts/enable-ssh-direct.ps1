# Enable SSH directly on each ESXi host via its own /sdk (no vCenter needed)
$ErrorActionPreference='Continue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAsshd:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAsshd
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$u='root'; $p='<VC_ESXI_PASSWORD>'
foreach($h in @('192.168.110.145','192.168.110.146','192.168.110.147','192.168.110.148')){
  $sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $hdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
  $login=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">ha-sessionmgr</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
  try{
    $null=Invoke-WebRequest -Uri "https://$h/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing
    # ESXi single-host serviceSystem MoRef = "serviceSystem"
    $s=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:StartService><urn:_this type="HostServiceSystem">serviceSystem</urn:_this><urn:id>TSM-SSH</urn:id></urn:StartService>
</soapenv:Body></soapenv:Envelope>
"@
    $r=Invoke-WebRequest -Uri "https://$h/sdk" -Method Post -Body $s -Headers $hdr -WebSession $sess -UseBasicParsing
    if($r.Content -match 'StartServiceResponse'){ Write-Host "$h : SSH started" }
    else{ Write-Host "$h : $($r.Content.Substring(0,[math]::Min(200,$r.Content.Length)))" }
  }catch{ $b=''; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $b=$sr.ReadToEnd()}; Write-Host "$h ERR: $($_.Exception.Message) $($b.Substring(0,[math]::Min(200,$b.Length)))" }
}