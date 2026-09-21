#!/bin/bash
# Step 3: stop the four stale identity services that systemd auto-started at boot
systemctl stop vmdird vmcad vmafdd lwsmd; sleep 2
echo "## still running?"; ps -eo pid,args | grep -E "[v]mdird|[v]mcad|[v]mafdd|[l]wsmd" || echo "none (all four stopped)"
mkdir -p /var/log/firstboot/prev-fail; mv /var/log/firstboot/failed /var/log/firstboot/prev-fail/ 2>/dev/null
echo "## failed marker removed:"; ls /var/log/firstboot/failed 2>&1 | head -1
