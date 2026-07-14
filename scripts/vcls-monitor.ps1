$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAmon:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAmon
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
for($i=0;$i -lt 18;$i++){
  $vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $H
  $vcls=$vms | Where-Object {$_.name -like 'vCLS*'}
  $on=($vcls | Where-Object {$_.power_state -eq 'POWERED_ON'}).Count
  $t=(Get-Date).ToString('HH:mm:ss')
  Write-Host "[$t] vCLS total=$($vcls.Count) ON=$on :: $(( $vcls | ForEach-Object { $_.power_state.Substring(8,2) }) -join ' ')"
  if($on -ge 1){ Write-Host "AT LEAST ONE vCLS POWERED ON"; }
  if($on -ge 3){ Write-Host "QUORUM (3) REACHED"; break }
  Start-Sleep 10
}
