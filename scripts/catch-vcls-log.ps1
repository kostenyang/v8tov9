$plink="C:\Program Files\PuTTY\plink.exe"; $pw='<VC_ESXI_PASSWORD>'
$h='192.168.110.145'
# find a recent vCLS vmware.log on the shared vSAN datastore and dump crash-relevant lines
$find='P=$(find /vmfs/volumes/vsan:*/ -maxdepth 3 -iname vmware.log -mmin -8 2>/dev/null | head -20); for f in $P; do if grep -q vCLS "$f" 2>/dev/null; then echo "FOUND:$f"; fi; done'
for($i=0;$i -lt 14;$i++){
  $paths = & $plink -ssh -batch -pw $pw root@$h $find 2>&1 | Select-String "FOUND:" | ForEach-Object { ($_ -replace '.*FOUND:','').Trim() }
  if($paths){
    $p0 = $paths | Select-Object -First 1
    Write-Host "=== $p0 ==="
    $dump = & $plink -ssh -batch -pw $pw root@$h "grep -iE 'reset|panic|fault|triple|Msg_|MsgHint|exit|POWERING|CPUID|feature|MONITOR|unsupported|Exception|WARNING|error' `"$p0`" | tail -45" 2>&1
    Write-Host (($dump | Select-String -NotMatch "Keyboard-interactive|End of keyboard") -join "`n")
    break
  } else { Write-Host "pass $i : no recent vCLS vmware.log yet" }
  Start-Sleep 10
}