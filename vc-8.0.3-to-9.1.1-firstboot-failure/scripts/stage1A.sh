#!/bin/bash
# Robust Stage 1 driver for the 9.1.1 installer (window 1120x971): waits for page text before each step.
N=/e/9.1/tools/node-v24.16.0-win-x64/node.exe; S=${S:-E:/9.1/chtvcd/rep4}; VMNAME=${VMNAME:-chtvcd-91-A}; TMPIP=${TMPIP:-10.0.0.92}
c(){ $N cdp-io.mjs --click "$1" --wait "${2:-500}" >/dev/null 2>&1; }; t(){ $N cdp-io.mjs --type "$1" --wait 300 >/dev/null 2>&1; }
shot(){ $N cdp-io.mjs --shot "$S/$1" --wait 300 2>&1 | tail -1; }
txt(){ timeout 40 $N /e/9.1/tools/cdp-frame.mjs --port 9333 --match "vCenter Installer" --expr "return document.body.innerText.replace(/\n{2,}/g,'\n')" 2>/dev/null; }
wf(){ for i in $(seq 1 "${2:-40}"); do T=$(txt); echo "$T" | grep -qE "$1" && { echo "  [ok] $1"; return 0; }; sleep 3; done; echo "  [TIMEOUT] $1"; txt | head -c 300; return 1; }
nobusy(){ for i in $(seq 1 60); do T=$(txt); echo "$T" | grep -qE "Connecting to source|Validating|Loading" || return 0; sleep 3; done; }
sed -i "s/'10.0.0.9[0-9]'/'$TMPIP'/" netfill92.js
# assumes wizard is on "Connect to source appliance" with FQDN typed and connect clicked (or do it here)
wf "Certificate Viewer" && shot A05a-source-cert.png; c 782,794 1000; nobusy; wf "SSO Password"
c 768,509; t '<SSO_ADMIN_PASSWORD>'; c 768,571; t '<SOURCE_ROOT_PASSWORD>'; c 768,702; t '10.0.0.101'; c 768,825; t 'administrator@vsphere.local'; c 768,887; t '<OUTER_VC_PASSWORD>'; shot A05-1-form.png
c 1059,938 1000; nobusy; wf "Certificate Viewer" && c 782,794 1000; nobusy; wf "vCenter deployment target" && shot A05c-target.png
c 777,337; t '10.0.0.101'; c 777,445; t 'administrator@vsphere.local'; c 777,499; t '<OUTER_VC_PASSWORD>'; c 1059,938 1000; nobusy; wf "Certificate Viewer" && c 782,794 1000; nobusy
wf "Select folder" && { c 470,311 800; c 1059,938 1000; }; nobusy; wf "Select compute resource" && { c 393,314 2500; c 500,422 800; shot A05d-compute.png; c 1059,938 1000; }; nobusy
wf "Set up target vCenter VM" && { $N setname.mjs 777,317 "$VMNAME" >/dev/null 2>&1; c 777,371; t '<SOURCE_ROOT_PASSWORD>'; c 777,425; t '<SOURCE_ROOT_PASSWORD>'; c 1059,938 1000; }; nobusy
wf "Select deployment size" && c 1059,938 1000; nobusy
wf "Select datastore" && { sleep 3; c 386,462; c 353,553; c 1059,938 1000; }; nobusy
wf "Configure network settings" && { timeout 60 $N /e/9.1/tools/cdp-frame.mjs --port 9333 --match "vCenter Installer" --exprfile netfill92.js 2>&1 | tail -1; c 1059,938 1000; }; nobusy
wf "Ready to complete stage 1" && shot A05-stage1-ready.png
