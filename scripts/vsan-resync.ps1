$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TArs:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TArs
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vsan/8.0.2.0' }
$vhdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $vhdr -WebSession $sess -UseBasicParsing
$req=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<VsanQuerySyncingVsanObjects xmlns="urn:vsan"><_this type="VsanObjectSystem">vsan-cluster-object-system</_this>
<cluster type="ClusterComputeResource">domain-c9</cluster></VsanQuerySyncingVsanObjects>
</soapenv:Body></soapenv:Envelope>
"@
try{
  $r=Invoke-WebRequest -Uri "https://$vc/vsanHealth" -Method Post -Body $req -Headers $hdr -WebSession $sess -UseBasicParsing
  [xml]$x=$r.Content
  $objs=$x.SelectNodes("//*[local-name()='objects']")
  Write-Host "vSAN resyncing objects: $($objs.Count)"
}catch{ Write-Host "resync query err: $($_.Exception.Message)" }
# hosts
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$RH=@{'vmware-api-session-id'=(Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"})}
$hs=Invoke-RestMethod -Uri "https://$vc/api/vcenter/host?clusters=domain-c9" -Headers $RH
$hs | ForEach-Object { Write-Host "  $($_.name) $($_.connection_state)" }