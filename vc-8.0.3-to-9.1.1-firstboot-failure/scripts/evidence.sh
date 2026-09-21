echo "##### A. first-failure firstbootStatus (prev-fail) #####"
for d in /var/log/firstboot/prev-fail-*/ /var/log/firstboot/prev-fail2/; do ls $d 2>/dev/null | head -3; done
F=$(ls -d /var/log/firstboot/prev-fail-*/failed 2>/dev/null | head -1); echo "dir=$F"; ls $F 2>/dev/null | head
echo "##### B. first failure traceback (vmafd stderr, original run) #####"
ls -t /var/log/firstboot/vmafd-firstboot.py_*_stderr.log | tail -1 | xargs -I{} sh -c 'echo {}; grep -nE "File \"|Error|refused" {} | head -12 | cut -c1-170'
echo "##### C. vmdird boot-start evidence (journal) #####"
journalctl -b -u vmdird --no-pager -o short-iso 2>/dev/null | head -5 | cut -c1-160
grep -m3 -E "Have NOT yet started listening|listening on LDAP port" /var/log/vmware/vmdird/vmdird*.log 2>/dev/null | cut -c1-170
echo "##### D. vmafd Error14 evidence (second failure) #####"
grep -m3 -E "lstat\(/storage/db/vmware-vmafd/afd.db\)|Failed to update trusted roots" /var/log/vmware/vmafdd/vmafdd.log | cut -c1-170
echo "##### E. success evidence #####"
grep -E '"finalStatus"|"stepsCompleted"' /var/log/firstboot/firstbootStatus.json
grep -E "RESUME v2 START|--- firstboot|--- upgrade_import|--- post_install|RESUME COMPLETE" /var/log/vmware/upgrade/resume_upgrade.log | cut -c1-120
grep -E "SUCCESS: Upgrade IMPORT" /var/log/vmware/upgrade/upgrade-import.log
echo "##### F. vmdirUpgrade.py key lines #####"
grep -nE "def start_service|systemctl.*start.*vmdird|def import_data_files|rmtree|copytree|def open_ldap_connection|def start_upgrade" /usr/lib/vmware-vmafd/firstboot/identityinstall/vmdirUpgrade.py | head -12
sed -n '/def start_service/,/^    def /p' /usr/lib/vmware-vmafd/firstboot/identityinstall/vmdirUpgrade.py | head -15
echo "##### G. vmafd vecs_force_refresh #####"
grep -nE "def vecs_force_refresh|force-refresh|vecs_force_refresh_failed" /usr/lib/vmware-vmafd/firstboot/identityinstall/vmafdInstall.py | head -6
echo "##### H. systemd enabled by rpminstall #####"; systemctl is-enabled vmdird vmafdd vmcad lwsmd 2>&1 | tr '\n' ' '; echo
