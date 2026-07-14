param([int]$rounds=6,[int]$interval=25)
$ErrorActionPreference='Continue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAnm:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAnm
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$nsx='192.168.110.143'; $u='admin'; $p='<NSX_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$H=@{Authorization="Basic $pair"}
for($i=0;$i -lt $rounds;$i++){
  try{
    $s=Invoke-RestMethod -Uri "https://$nsx/api/v1/upgrade/status-summary?component_type=HOST" -Headers $H
    $cs=$s.component_status[0]
    $t=(Get-Date).ToString('HH:mm:ss')
    Write-Host "[$t] overall=$($s.overall_upgrade_status) HOST=$($cs.status) pct=$($cs.percent_complete) at-target=$($cs.node_count_at_target_version)/4 details=$($cs.details)"
  }catch{ Write-Host "poll err $($_.Exception.Message)" }
  if($i -lt $rounds-1){ Start-Sleep $interval }
}
