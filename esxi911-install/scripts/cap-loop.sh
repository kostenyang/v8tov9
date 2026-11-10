#!/bin/bash
# 每 N 秒抓一次 VM console,存成序號 PNG(只保留與上一張不同的)
export MSYS_NO_PATHCONV=1; export GOVC_URL='https://10.0.0.101' GOVC_USERNAME='administrator@vsphere.local' GOVC_PASSWORD='<PASSWORD>' GOVC_INSECURE=1
G=/e/9.1/tools/govc.exe
OUT=E:/9.1/doc-shots/esxi911-install/raw
INT=${1:-3}; DUR=${2:-600}
end=$(( $(date +%s) + DUR )); prev=""
while [ $(date +%s) -lt $end ]; do
  f=$OUT/$(date +%H%M%S).png
  $G vm.console -capture "$f" esx911-demo 2>/dev/null
  if [ -s "$f" ]; then h=$(md5sum "$f" | cut -d' ' -f1); if [ "$h" = "$prev" ]; then rm -f "$f"; else prev=$h; fi; fi
  sleep $INT
done
