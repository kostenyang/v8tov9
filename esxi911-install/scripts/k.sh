#!/bin/bash
# 用法: k.sh KEY_ENTER | k.sh -s "text" ;  k.sh shot <name>
export MSYS_NO_PATHCONV=1; export GOVC_URL='https://10.0.0.101' GOVC_USERNAME='administrator@vsphere.local' GOVC_PASSWORD='<PASSWORD>' GOVC_INSECURE=1
G=/e/9.1/tools/govc.exe
if [ "$1" = shot ]; then for t in 1 2 3 4 5 6; do $G vm.console -capture "E:/9.1/doc-shots/esxi911-install/$2.png" esx911-demo 2>/dev/null && { echo "saved $2.png"; break; }; sleep 1; done;
elif [ "$1" = -s ]; then $G vm.keystrokes -vm esx911-demo -s "$2" && echo "typed";
else for c in "$@"; do $G vm.keystrokes -vm esx911-demo -c "$c"; done && echo "sent $*"; fi
