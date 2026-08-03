param([string]$vmname,[string]$targethost)
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAmv:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAmv
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$rsid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$RH=@{'vmware-api-session-id'=$rsid}
$vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $RH
$vm=($vms | Where-Object {$_.name -eq $vmname}).vm
Write-Host "migrating $vmname ($vm) -> $targethost"
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing
$mg=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:MigrateVM_Task><urn:_this type="VirtualMachine">$vm</urn:_this><urn:host type="HostSystem">$targethost</urn:host><urn:priority>defaultPriority</urn:priority><urn:state>poweredOn</urn:state></urn:MigrateVM_Task>
</soapenv:Body></soapenv:Envelope>
"@
$r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $mg -Headers $hdr -WebSession $sess -UseBasicParsing
$tid=([xml]$r.Content).SelectSingleNode("//*[local-name()='returnval']").InnerText
Write-Host "task=$tid"
for($i=0;$i -lt 60;$i++){ Start-Sleep 5
  $tq=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>Task</urn:type><urn:pathSet>info.state</urn:pathSet><urn:pathSet>info.progress</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="Task">$tid</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
  $tr=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $tq -Headers $hdr -WebSession $sess -UseBasicParsing
  [xml]$tx=$tr.Content
  $st=$tx.SelectSingleNode("//*[local-name()='name'][.='info.state']/following-sibling::*[local-name()='val']").InnerText
  $pg=$tx.SelectSingleNode("//*[local-name()='name'][.='info.progress']/following-sibling::*[local-name()='val']").InnerText
  Write-Host "  state=$st progress=$pg"
  if($st -eq 'success'){ Write-Host "MIGRATE success"; break }
  if($st -eq 'error'){ Write-Host "MIGRATE error"; Write-Host $tr.Content; break }
}