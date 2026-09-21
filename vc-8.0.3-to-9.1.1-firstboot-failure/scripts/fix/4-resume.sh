#!/bin/bash
# Step 4: resume the upgrade from firstboot (export already done)
: > /var/log/vmware/upgrade/resume_upgrade.log
setsid -f /bin/bash /root/fix/resume_upgrade.sh </dev/null >/dev/null 2>&1
sleep 20; echo "## resume started:"; grep -E "RESUME|isUpgrade|--- firstboot" /var/log/vmware/upgrade/resume_upgrade.log | head -4 | cut -c1-100
echo "## firstboot:"; cat /var/log/firstboot/status 2>/dev/null; echo
