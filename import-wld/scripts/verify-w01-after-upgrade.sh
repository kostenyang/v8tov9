#!/usr/bin/env bash
# 階段 3 升級後驗證:vCenter 版本、主機連線、vSAN。
set -u
cd /e/9.1/tools
export GOVC_URL='https://10.0.1.49' GOVC_USERNAME='administrator@vsphere.local' \
       GOVC_PASSWORD="${VCPASS:?set VCPASS}" GOVC_INSECURE=1 MSYS_NO_PATHCONV=1
echo "=== w01 升級後 $(date '+%F %T') ==="
./govc.exe about | grep -E "FullName|Version|Build"
echo "--- hosts"
for h in vcf-w01-esx01 vcf-w01-esx02 vcf-w01-esx03; do
  echo -n "  $h.home.lab : "
  ./govc.exe object.collect -s "/vcf-w01-dc01/host/vcf-w01-cl01/$h.home.lab" \
      config.product.fullName runtime.connectionState 2>/dev/null | tr '\n' ' '; echo
done
echo "--- datastore"
./govc.exe datastore.info vsanDatastore | grep -E "Name|Capacity|Free"
echo "--- VMs"
./govc.exe find /vcf-w01-dc01 -type m | sed 's#.*/##'
