$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAy:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAy
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
Write-Host "=== datastores ==="
$ds=Invoke-RestMethod -Uri "https://$vc/api/vcenter/datastore" -Headers $H
foreach($d in $ds){
  $capGB=[math]::Round($d.capacity/1GB,1); $freeGB=[math]::Round($d.free_space/1GB,1)
  $usedPct = if($d.capacity -gt 0){[math]::Round(100*($d.capacity-$d.free_space)/$d.capacity,1)}else{0}
  Write-Host "  $($d.name)  type=$($d.type)  cap=${capGB}GB free=${freeGB}GB used=${usedPct}%"
}