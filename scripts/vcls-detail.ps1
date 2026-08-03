$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAd:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAd
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
Write-Host "vCLS VMs: $($vcls.Count)"
foreach($v in $vcls){
  $q=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>VirtualMachine</urn:type>
<urn:pathSet>config.files.vmPathName</urn:pathSet><urn:pathSet>runtime.powerState</urn:pathSet><urn:pathSet>runtime.host</urn:pathSet>
<urn:pathSet>summary.runtime.bootTime</urn:pathSet><urn:pathSet>config.template</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="VirtualMachine">$($v.vm)</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
  $r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q -Headers $hdr -WebSession $sess -UseBasicParsing
  [xml]$x=$r.Content
  $props=@{}
  foreach($pv in $x.SelectNodes("//*[local-name()='propSet']")){ $props[$pv.SelectSingleNode("./*[local-name()='name']").InnerText]=$pv.SelectSingleNode("./*[local-name()='val']").InnerText }
  Write-Host "  $($v.name)"
  Write-Host "     path=$($props['config.files.vmPathName'])  power=$($props['runtime.powerState'])  host=$($props['runtime.host'])  boot=$($props['summary.runtime.bootTime'])"
}