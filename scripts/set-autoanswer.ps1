$plink="C:\Program Files\PuTTY\plink.exe"
$pw='<VC_ESXI_PASSWORD>'
$hosts=@('192.168.110.145','192.168.110.146','192.168.110.147','192.168.110.148')
$cmd='if ! grep -q "vmx.autoAnswer" /etc/vmware/config; then echo ''vmx.autoAnswer = "TRUE"'' >> /etc/vmware/config; fi; echo CONFIG:; grep -i autoanswer /etc/vmware/config; echo VERSION:; vmware -v'
foreach($h in $hosts){
  Write-Host "==== $h ===="
  # cache host key
  cmd /c "echo y | `"$plink`" -ssh -pw $pw root@$h exit" 2>&1 | Out-Null
  $out = & $plink -ssh -batch -pw $pw root@$h $cmd 2>&1
  Write-Host ($out -join "`n")
}