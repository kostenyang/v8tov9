# Lab shutdown step A: verify vSAN resync=0, shutdown NSX+SDDC VMs, stop vCLS (keep vCenter + hosts up)
$ErrorActionPreference='Continue'
$plink="C:\Program Files\PuTTY\plink.exe"; $espw='<VC_ESXI_PASSWORD>'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAsd:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAsd
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'

Write-Host "=== vSAN resync check (must be 0 before shutdown) ==="
& $plink -ssh -batch -pw $espw root@192.168.110.145 "esxcli vsan debug resync summary get 2>/dev/null | head -1" 2>&1 | Select-String -NotMatch "Keyboard-interactive|End of keyboard"

$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$H=@{'vmware-api-session-id'=(Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"})}
$vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $H
foreach($name in @('vcf-m01-nsx01a','vcf-m01-sddcm01')){
  $vm=($vms | Where-Object {$_.name -eq $name}).vm
  if($vm){
    try{ Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/guest/power?action=shutdown" -Headers $H | Out-Null; Write-Host "guest shutdown: $name ($vm)" }
    catch{ Write-Host "$name shutdown err: $($_.Exception.Message)" }
  }
}
Write-Host "=== disable vCLS (retreat) so vCLS VMs stop ==="
& powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\mjalan\Documents\vspher8to9\vcls-retreat.ps1" false | Select-String UPDATE
Write-Host "waiting 40s for VMs to power off..."
Start-Sleep 40
$vms2=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $H
$vms2 | Sort-Object name | ForEach-Object { Write-Host ("  {0,-42} {1}" -f $_.name,$_.power_state) }