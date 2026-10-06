#!/usr/bin/env bash
export GOVC_URL="https://10.0.0.101/sdk" GOVC_USERNAME='administrator@vsphere.local' GOVC_PASSWORD='<從環境變數帶入>' GOVC_INSECURE=1
for i in $(seq 1 120); do
  ps=$(MSYS_NO_PATHCONV=1 /e/9.1/tools/govc.exe vm.info vcf-m03-inst01 2>/dev/null | grep -oE 'poweredOn|poweredOff')
  [ -z "$ps" ] && ps=absent
  c=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 6 https://10.0.1.71/ 2>/dev/null); [ -z "$c" ] && c=000
  echo "$(date +%H:%M:%S) vm=$ps https=$c"
  if [ "$c" != "000" ]; then echo INST-UP; break; fi
  sleep 30
done
