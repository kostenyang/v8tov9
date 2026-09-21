#!/bin/bash
# usage: con.sh <vm> <outpng> <wait_sec> "<text to type>"   (text typed then ENTER; empty text = just capture)
export GOVC_URL="https://10.0.0.101/sdk" GOVC_USERNAME="administrator@vsphere.local" GOVC_PASSWORD='<OUTER_VC_PASSWORD>' GOVC_INSECURE=1
G="/e/9.1/tools/govc.exe"; VM="$1"; OUT="$2"; W="${3:-3}"; TXT="$4"
if [ -n "$TXT" ]; then "$G" vm.keystrokes -vm "$VM" -s "$TXT" >/dev/null 2>&1; "$G" vm.keystrokes -vm "$VM" -c KEY_ENTER >/dev/null 2>&1; fi
sleep "$W"; "$G" vm.console -capture "$OUT" "$VM" >/dev/null 2>&1 && echo "captured $OUT"
