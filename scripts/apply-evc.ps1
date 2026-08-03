$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAevc:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAevc
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$rsid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$RH=@{'vmware-api-session-id'=$rsid}
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing
$vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $RH
$vcls=$vms | Where-Object {$_.name -like 'vCLS*'}
foreach($v in $vcls){
  $rc=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:ApplyEvcModeVM_Task><urn:_this type="VirtualMachine">$($v.vm)</urn:_this><urn:completeMasks>true</urn:completeMasks></urn:ApplyEvcModeVM_Task>
</soapenv:Body></soapenv:Envelope>
"@
  try{ $r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $rc -Headers $hdr -WebSession $sess -UseBasicParsing
    $tid=([xml]$r.Content).SelectSingleNode("//*[local-name()='returnval']").InnerText
    Write-Host "$($v.name) : ApplyEvcModeVM (disable) task=$tid" }
  catch{ Write-Host "$($v.name) ERR"; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host ($sr.ReadToEnd().Substring(0,[math]::Min(400,900)))} }
}