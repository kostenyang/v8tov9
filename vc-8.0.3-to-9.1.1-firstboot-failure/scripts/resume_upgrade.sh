#!/bin/bash
LOG=/var/log/vmware/upgrade/resume_upgrade.log
exec > >(tee -a $LOG) 2>&1
echo "=== $(date -u) RESUME v2 START ==="
source /etc/profile 2>/dev/null
INSTALL_SRCDIR=/tmp/mount; mkdir -p $INSTALL_SRCDIR; mountpoint -q $INSTALL_SRCDIR || mount /dev/sdb $INSTALL_SRCDIR
source $INSTALL_SRCDIR/common-install.sh
type python_init >/dev/null 2>&1 && python_init
checkIsUpgrade
echo "isUpgrade=$isUpgrade  vmdir.password len=$(/bin/install-parameter vmdir.password | wc -c)  vpxd.ip=$(/bin/install-parameter upgrade.source.vpxd.ip)"
echo "--- workaround: stop stale vmdird ---"; systemctl stop vmdird; sleep 2; ps -eo pid,args | grep "[v]mdird" || echo "vmdird stopped"
mkdir -p /var/log/firstboot/prev-fail-$(date +%H%M); mv /var/log/firstboot/failed /var/log/firstboot/prev-fail-$(date +%H%M)/ 2>/dev/null; rm -f /var/log/firstboot/failed
prune_sensitive_param="False"     # keep params on failure so we can iterate; prune manually at the end
set_vcsa_deploy_state "config_in_progress"
echo "--- firstboot ---";            log_time firstboot
echo "--- upgrade_import ---";       log_time upgrade_import
echo "--- post_install_cleanup ---"; log_time post_install_cleanup
set_vcsa_deploy_state "configured"
echo "=== $(date -u) RESUME COMPLETE: configured ==="
