#!/bin/bash
# Step 6: verify the upgraded vCenter
source /etc/profile >/dev/null 2>&1
echo "## version: $(vpxd -v)"
echo "## deploy state: $(cat /etc/vmware/install-defaults/vcsa.deploy.state 2>/dev/null || echo n/a) / firstboot: $(cat /var/log/firstboot/status)"
echo "## vmon not STARTED:"; for x in $(vmon-cli -l); do st=$(vmon-cli -s $x | grep -E "^RunState" | awk '{print $2}'); [ "$st" != "STARTED" ] && echo -n "$x "; done; echo "(these are disabled by default)"
T=$(curl -sk -m 15 -u "administrator@vsphere.local:<SSO_ADMIN_PASSWORD>" -X POST https://localhost/api/session | tr -d '"')
echo "## SSO login: $([ -n "$T" ] && echo OK || echo FAIL)"
for e in datacenter cluster host vm; do echo -n "## $e: "; curl -sk -m 20 -H "vmware-api-session-id: $T" https://localhost/api/vcenter/$e | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"; done
