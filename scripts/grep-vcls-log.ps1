$plink="C:\Program Files\PuTTY\plink.exe"
$pw='<VC_ESXI_PASSWORD>'
$hosts=@('192.168.110.145','192.168.110.146','192.168.110.147','192.168.110.148')
$cmd='echo "== recent vCLS power events =="; grep -i "vCLS" /var/log/hostd.log 2>/dev/null | grep -iE "power|fail|error|question|invalid|denied|insuff|refuse" | tail -12; echo "== vmkernel vCLS =="; grep -i "vCLS" /var/log/vmkernel.log 2>/dev/null | tail -6'
foreach($h in $hosts){
  Write-Host "############ $h ############"
  $out = & $plink -ssh -batch -pw $pw root@$h $cmd 2>&1
  Write-Host ($out -join "`n")
}