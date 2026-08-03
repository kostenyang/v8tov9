$plink="C:\Program Files\PuTTY\plink.exe"
$pw='<VC_ESXI_PASSWORD>'
$hosts=@('192.168.110.145','192.168.110.146','192.168.110.147','192.168.110.148')
foreach($h in $hosts){
  Write-Host "==== restarting hostd on $h ===="
  $out = & $plink -ssh -batch -pw $pw root@$h "/etc/init.d/hostd restart" 2>&1
  Write-Host ($out -join "`n")
  Start-Sleep 25
}
Write-Host "done"