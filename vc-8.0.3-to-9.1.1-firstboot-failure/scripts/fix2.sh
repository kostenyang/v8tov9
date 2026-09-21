echo "##### evidence: afd.db perms vs vmafdd process #####"
ls -la /storage/db/vmware-vmafd/ 2>/dev/null; ps -eo user,pid,lstart,args | grep -E "[v]mafdd|[v]mcad|[l]wsmd|[v]mdird" | cut -c1-100
grep -E "^(User|Group|ExecStart)=" /usr/lib/systemd/system/vmafdd.service 2>/dev/null; id vmafd 2>/dev/null || echo "(no 'vmafd' user; likely runs as root)"
echo "##### corrected workaround: stop ALL boot-started identity services #####"
systemctl stop vmdird vmcad vmafdd lwsmd 2>&1; sleep 3
ps -eo pid,args | grep -E "[v]mafdd|[v]mcad|[l]wsmd|[v]mdird" || echo "all four stopped"
echo "##### reset markers + relaunch resume v2 #####"
mkdir -p /var/log/firstboot/prev-fail2; mv /var/log/firstboot/failed /var/log/firstboot/prev-fail2/ 2>/dev/null; rm -f /var/log/firstboot/failed
: > /var/log/vmware/upgrade/resume_upgrade.log
setsid -f /bin/bash /tmp/resume_upgrade.sh </dev/null >/dev/null 2>&1
sleep 70
echo "##### status after 70s #####"; cat /var/log/firstboot/status; echo; grep -E '"stepsCompleted"|"finalStatus"|"failedSteps"' /var/log/firstboot/firstbootStatus.json
ps -eo user,pid,lstart,args | grep -E "[v]mafdd|[v]mdird" | cut -c1-100; ss -ltn | grep -qE ":389 " && echo "389 LISTENING" || echo "389 not yet"
ls -la /storage/db/vmware-vmafd/afd.db 2>/dev/null
echo "--- latest vmafd stdout tail ---"; O=$(ls -t /var/log/firstboot/vmafd-firstboot.py_*_stdout.log 2>/dev/null | head -1); grep -vE "Getting value|lwregshell|lwreg|lwsmd already|SyntaxWarning" "$O" 2>/dev/null | tail -6 | cut -c1-150
echo "--- vmafdd.log last errors ---"; tail -3 /var/log/vmware/vmafdd/vmafdd.log | cut -c1-150
