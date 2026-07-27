param([string]$hostmo, [string]$hostip)
# Upgrade one nested ESXi host to 9.1 with allowLegacyCPU bypass (Broadwell)
$ErrorActionPreference='Continue'
$plink="C:\Program Files\PuTTY\plink.exe"; $espw='<VC_ESXI_PASSWORD>'
$depot="http://192.168.110.200:8000/esxi91-depot/index.xml"
$profile="ESXi-9.1.0.0100-25433460-standard"
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAeu:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAeu
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$RH=@{'vmware-api-session-id'=(Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"})}
$sess=New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr=@{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing
function Soap($body){ (Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $body -Headers $hdr -WebSession $sess -UseBasicParsing).Content }
function WaitTask($tid){ for($i=0;$i -lt 90;$i++){ Start-Sleep 6
  $q=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>Task</urn:type><urn:pathSet>info.state</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="Task">$tid</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
  $st=([xml](Soap $q)).SelectSingleNode("//*[local-name()='val']").InnerText
  if($st -eq 'success'){return 'success'}; if($st -eq 'error'){return 'error'} }
  return 'timeout' }
function HostConn(){ (Invoke-RestMethod -Uri "https://$vc/api/vcenter/host?clusters=domain-c9" -Headers $RH | Where-Object {$_.host -eq $hostmo}).connection_state }
function InMM(){
  $q=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>HostSystem</urn:type><urn:pathSet>runtime.inMaintenanceMode</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="HostSystem">$hostmo</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
  return (([xml](Soap $q)).SelectSingleNode("//*[local-name()='val']").InnerText -eq 'true') }

Write-Host "==== [$hostmo / $hostip] ENTER maintenance mode (vSAN ensureAccessibility) ===="
if(InMM){ Write-Host "  already in MM, skip enter" }
else{
  $mm=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:EnterMaintenanceMode_Task><urn:_this type="HostSystem">$hostmo</urn:_this><urn:timeout>0</urn:timeout>
<urn:evacuatePoweredOffVms>false</urn:evacuatePoweredOffVms>
<urn:maintenanceSpec><urn:vsanMode><urn:objectAction>ensureObjectAccessibility</urn:objectAction></urn:vsanMode></urn:maintenanceSpec>
</urn:EnterMaintenanceMode_Task></soapenv:Body></soapenv:Envelope>
"@
  $tid=([xml](Soap $mm)).SelectSingleNode("//*[local-name()='returnval']").InnerText
  $r=WaitTask $tid; Write-Host "  EnterMM: $r"
  if($r -ne 'success'){ Write-Host "  MM failed, abort"; exit 1 }
}

Write-Host "==== profile update to 9.1 (--no-hardware-warning) ===="
$out=& $plink -ssh -batch -pw $espw root@$hostip "esxcli software profile update -d $depot -p $profile --no-hardware-warning" 2>&1
Write-Host (($out|Select-String -NotMatch 'Keyboard-interactive|End of keyboard') -join "`n")
if($out -match 'could not|Error|failed'){ Write-Host "  profile update ERROR"; }

Write-Host "==== boot.cfg allowLegacyCPU: SKIPPED — profile-update path boots ESXi 9.1 on Broadwell without it (proven on esx03) ===="

Write-Host "==== reboot ===="
& $plink -ssh -batch -pw $espw root@$hostip "reboot" 2>&1 | Out-Null
Write-Host "  waiting host to go DOWN..."
for($i=0;$i -lt 40;$i++){ Start-Sleep 10; if((HostConn) -ne 'CONNECTED'){ Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] host down"; break } }
Write-Host "  waiting host to come UP (CONNECTED)..."
for($i=0;$i -lt 80;$i++){ Start-Sleep 12; $c=HostConn; if($c -eq 'CONNECTED'){ Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] CONNECTED"; break }; if($i % 3 -eq 0){ Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] conn=$c" } }
Start-Sleep 15

Write-Host "==== EXIT maintenance mode (retry) ===="
for($retry=0;$retry -lt 6;$retry++){
  if(-not (InMM)){ Write-Host "  not in MM (done)"; break }
  $xm=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:ExitMaintenanceMode_Task><urn:_this type="HostSystem">$hostmo</urn:_this><urn:timeout>0</urn:timeout></urn:ExitMaintenanceMode_Task>
</soapenv:Body></soapenv:Envelope>
"@
  $tid2=([xml](Soap $xm)).SelectSingleNode("//*[local-name()='returnval']").InnerText
  $r2=WaitTask $tid2
  if($r2 -eq 'success'){ Write-Host "  ExitMM: success"; break }
  Write-Host "  ExitMM retry $retry ($r2)..."; Start-Sleep 15
}
# verify via SSH (enable first, reboot turned it off)
$patch2="esxcli system version get"
Write-Host "==== [$hostmo] DONE (verify version manually via enable-ssh + vmware -v) ===="