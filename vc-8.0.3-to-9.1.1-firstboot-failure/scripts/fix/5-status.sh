#!/bin/bash
# Step 5: watch progress
echo "## $(date -u +%H:%M:%S) phase: $(cat /var/log/firstboot/status 2>/dev/null)"
grep -E '"stepsCompleted"|"finalStatus"' /var/log/firstboot/firstbootStatus.json 2>/dev/null
echo "## current: $(ls -t /var/log/firstboot/*_stdout.log 2>/dev/null | head -1 | xargs -n1 basename | sed 's/_[0-9]*_stdout.log//')"
echo "## resume log:"; grep -E "^--- |RESUME COMPLETE|Result: Failure|SUCCESS: Upgrade IMPORT" /var/log/vmware/upgrade/resume_upgrade.log /var/log/vmware/upgrade/upgrade-import.log 2>/dev/null | sed 's#.*/##' | tail -4 | cut -c1-90
echo "## vmdird (started by firstboot):"; ps -eo pid,lstart,args | grep "[v]mdird" | cut -c1-60; ss -ltn | grep -qE ":389 " && echo "389 listening" || echo "389 not yet"
