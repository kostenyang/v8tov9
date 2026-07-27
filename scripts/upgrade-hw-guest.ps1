param([string]$vm,[string]$ver='vmx-20',[string]$gid='vmkernel8Guest',[switch]$hardoff)
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAuhg:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAuhg
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.32'; $u='administrator@vsphere.local'; $p='<PHYSICAL_VC_PASSWORD>'
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
function Get-Pwr($vm){ (Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm/power" -Headers $RH).state }
function Wait-Task($tid){ for($i=0;$i -lt 40;$i++){ Start-Sleep 4
  $tq=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>Task</urn:type><urn:pathSet>info.state</urn:pathSet><urn:pathSet>info.error</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="Task">$tid</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
  $tr=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $tq -Headers $hdr -WebSession $sess -UseBasicParsing
  $st=([xml]$tr.Content).SelectSingleNode("//*[local-name()='name'][.='info.state']/following-sibling::*[local-name()='val']").InnerText
  if($st -eq 'success'){ return 'success' }
  if($st -eq 'error'){ return $tr.Content } }
  return 'timeout' }
# power off
if((Get-Pwr $vm) -eq 'POWERED_ON'){
  if($hardoff){ try{Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=stop" -Headers $RH|Out-Null}catch{} }
  else{ try{Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/guest/power?action=shutdown" -Headers $RH|Out-Null}catch{ Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=stop" -Headers $RH|Out-Null } }
  for($i=0;$i -lt 30;$i++){ Start-Sleep 6; if((Get-Pwr $vm) -eq 'POWERED_OFF'){break} }
  if((Get-Pwr $vm) -ne 'POWERED_OFF'){ try{Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=stop" -Headers $RH|Out-Null}catch{}; Start-Sleep 8 }
}
Write-Host "[$vm] off. Upgrading vHW to $ver ..."
$up=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:UpgradeVM_Task><urn:_this type="VirtualMachine">$vm</urn:_this><urn:version>$ver</urn:version></urn:UpgradeVM_Task>
</soapenv:Body></soapenv:Envelope>
"@
$r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $up -Headers $hdr -WebSession $sess -UseBasicParsing
$tid=([xml]$r.Content).SelectSingleNode("//*[local-name()='returnval']").InnerText
$res=Wait-Task $tid; Write-Host "  upgrade vHW: $res"
Write-Host "[$vm] Setting guestId=$gid ..."
$rc=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:ReconfigVM_Task><urn:_this type="VirtualMachine">$vm</urn:_this><urn:spec><urn:guestId>$gid</urn:guestId></urn:spec></urn:ReconfigVM_Task>
</soapenv:Body></soapenv:Envelope>
"@
$r2=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $rc -Headers $hdr -WebSession $sess -UseBasicParsing
$tid2=([xml]$r2.Content).SelectSingleNode("//*[local-name()='returnval']").InnerText
Write-Host "  set guestId: $(Wait-Task $tid2)"
Write-Host "[$vm] guestOS now = $((Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm" -Headers $RH).guest_OS)"
Write-Host "[$vm] powering on ..."
$po=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:PowerOnVM_Task><urn:_this type="VirtualMachine">$vm</urn:_this></urn:PowerOnVM_Task>
</soapenv:Body></soapenv:Envelope>
"@
$r3=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $po -Headers $hdr -WebSession $sess -UseBasicParsing
$tid3=([xml]$r3.Content).SelectSingleNode("//*[local-name()='returnval']").InnerText
$res3=Wait-Task $tid3
Write-Host "[$vm] POWER ON: $res3"