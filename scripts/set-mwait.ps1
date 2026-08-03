$plink="C:\Program Files\PuTTY\plink.exe"; $pw='<VC_ESXI_PASSWORD>'
$hosts=@('192.168.110.145','192.168.110.146','192.168.110.147','192.168.110.148')
$cmd='if ! grep -q "enable_mwait" /etc/vmware/config; then echo ''monitor_control.enable_mwait = "TRUE"'' >> /etc/vmware/config; fi; echo CONFIG:; grep -iE "mwait|autoanswer" /etc/vmware/config'
foreach($h in $hosts){
  Write-Host "==== $h ===="
  $out = & $plink -ssh -batch -pw $pw root@$h $cmd 2>&1
  Write-Host (($out | Select-String -NotMatch "Keyboard-interactive|End of keyboard") -join "`n")
}