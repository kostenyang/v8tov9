param([string]$hostmo)
$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAwh:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAwh
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
for($i=0;$i -lt 40;$i++){
  try{
    $hs=Invoke-RestMethod -Uri "https://$vc/api/vcenter/host?clusters=domain-c9" -Headers $H
    $th=$hs | Where-Object {$_.host -eq $hostmo}
    $vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $H
    $vclsOn=($vms | Where-Object {$_.name -like 'vCLS*' -and $_.power_state -eq 'POWERED_ON'}).Count
    $t=(Get-Date).ToString('HH:mm:ss')
    Write-Host "[$t] $($th.name) conn=$($th.connection_state) | vCLS_ON=$vclsOn"
    if($th.connection_state -eq 'CONNECTED' -and $vclsOn -ge 1){ Write-Host "HOST BACK + vCLS RUNNING"; break }
  }catch{ Write-Host "poll err $($_.Exception.Message)" }
  Start-Sleep 12
}