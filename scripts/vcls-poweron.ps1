$ErrorActionPreference='Continue'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAp:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAp
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$sid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$H=@{'vmware-api-session-id'=$sid}
$vms=@('vm-3207','vm-3208','vm-3209')
foreach($vm in $vms){
  try{
    Invoke-RestMethod -Method Post -Uri "https://$vc/api/vcenter/vm/$vm/power?action=start" -Headers $H | Out-Null
    Write-Host "$vm -> start issued"
  }catch{
    $code=$_.Exception.Response.StatusCode.value__
    $body=''
    if($_.Exception.Response){ $sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $body=$sr.ReadToEnd() }
    Write-Host "$vm -> ERR $code $body"
  }
}
Start-Sleep 5
Write-Host "=== power state after ==="
foreach($vm in $vms){
  $s=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm/$vm" -Headers $H
  Write-Host "  $vm  $($s.name)  $($s.power_state)"
}