#!/usr/bin/env bash
# 等 vcf-m03-lic01 OVF 部署完成並開機
export GOVC_URL="https://10.0.1.60/sdk"
export GOVC_USERNAME='administrator@vsphere.local'
export GOVC_PASSWORD="${VCPASS:?set VCPASS}"
export GOVC_INSECURE=1
for i in $(seq 1 120); do
  st=$(/e/9.1/tools/govc.exe vm.info -json vcf-m03-lic01 2>/dev/null | python -c "import sys,json;d=json.load(sys.stdin);v=(d.get('virtualMachines') or [None])[0];print(v['runtime']['powerState'] if v else 'absent')" 2>/dev/null || echo err)
  echo "$(date +%H:%M:%S) $st"
  [ "$st" = "poweredOn" ] && { echo LIC-VM-ON; break; }
  sleep 30
done
