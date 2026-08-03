$plink="C:\Program Files\PuTTY\plink.exe"
$pw='<VC_ESXI_PASSWORD>'
# search vSAN datastore for a vCLS vmware.log (accessible from any host)
$cmd=@'
L=$(find /vmfs/volumes/vsan* -maxdepth 2 -iname 'vmware.log' -path '*vCLS*' 2>/dev/null | head -1)
echo "LOG: $L"
if [ -n "$L" ]; then
  echo "==== tail (panic/reset/cpu/error) ===="
  grep -iE 'panic|reset|triple|monitor|vcpu-0|unsupported|cpuid|feature|MSR|Exception|E1000|Failed|error|vmx has' "$L" 2>/dev/null | tail -30
  echo "==== last 15 lines ===="
  tail -15 "$L"
fi
'@
$out = & $plink -ssh -batch -pw $pw root@192.168.110.145 $cmd 2>&1
Write-Host ($out -join "`n")