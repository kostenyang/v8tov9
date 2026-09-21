#!/bin/bash
# Step 1: evidence of the failure (short output for console)
echo "## firstboot status:"; grep -E '"stepsCompleted"|"finalStatus"|"failedSteps"' /var/log/firstboot/firstbootStatus.json
echo "## last error line:"; grep -hE "Errno|refused" $(ls -t /var/log/firstboot/vmafd-firstboot.py_*_stderr.log | head -1) | tail -1 | cut -c1-110
echo "## vmdird/vmafdd started at boot (stale):"; ps -eo pid,lstart,args | grep -E "[v]mdird|[v]mafdd" | cut -c1-70
echo "## boot time:"; uptime -s
echo "## LDAP 389 listening?"; ss -ltn | grep -qE ":389 " && echo "yes" || echo "NO - Connection refused"
echo "## password install-params left:"; ls /etc/vmware/install-defaults/ | grep -ciE "passw"
