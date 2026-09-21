D=/etc/vmware/install-defaults
w(){ printf '%s' "$2" > "$D/$1"; chmod 644 "$D/$1"; chown root:root "$D/$1"; printf "%-40s len=%s\n" "$1" "$(wc -c < "$D/$1")"; }
echo "##### writing pruned params directly #####"
w vmdir.password '<SSO_ADMIN_PASSWORD>'
w upgrade.source.vpxd.password '<SSO_ADMIN_PASSWORD>'
w upgrade.source.sso.password '<SSO_ADMIN_PASSWORD>'
w upgrade.source.guest.password '<SOURCE_ROOT_PASSWORD>'
w upgrade.source.guestops.host.password '<VCHA_OR_ANY>'
w appliance.root.passwd '<SOURCE_ROOT_PASSWORD>'
w vpxd.ha.management.password '<VCHA_OR_ANY>'
w upgrade.source.vpxd.ip 'tko-100085-vc.evs.vs.local'
echo "##### verify via tool under login shell #####"; /usr/bin/env -i /bin/bash -lc '/bin/install-parameter vmdir.password | wc -c; /bin/install-parameter upgrade.source.vpxd.ip' 2>/dev/null
echo "##### relaunch resume v2 #####"; head -4 /tmp/resume_upgrade.sh | tail -1; chmod +x /tmp/resume_upgrade.sh; : > /var/log/vmware/upgrade/resume_upgrade.log
setsid -f /bin/bash /tmp/resume_upgrade.sh </dev/null >/dev/null 2>&1
sleep 50
echo "##### resume log #####"; grep -vE "SyntaxWarning|^\s+'|TMOUT|^\s*$" /var/log/vmware/upgrade/resume_upgrade.log | head -30
echo "##### firstboot status #####"; cat /var/log/firstboot/status; echo; grep -E '"stepsStarted"|"stepsCompleted"|"finalStatus"|"failedSteps"' /var/log/firstboot/firstbootStatus.json 2>/dev/null
echo "##### vmdird / 389 #####"; ps -eo pid,args | grep "[v]mdird" | cut -c1-95; ss -ltn | grep -qE ":389 " && echo "389 LISTENING" || echo "389 not yet"
