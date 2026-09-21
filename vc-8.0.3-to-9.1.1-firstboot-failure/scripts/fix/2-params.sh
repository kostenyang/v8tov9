#!/bin/bash
# Step 2: restore the install parameters pruned by exit_cleanup (edit passwords first!)
D=/etc/vmware/install-defaults
SSO='<SSO_ADMIN_PASSWORD>'; ROOT='<SOURCE_ROOT_PASSWORD>'; ESXI='<ESXI_ROOT_PASSWORD>'; PNID='tko-100085-vc.evs.vs.local'
for k in vmdir.password upgrade.source.vpxd.password upgrade.source.sso.password; do printf '%s' "$SSO" > $D/$k; done
for k in appliance.root.passwd upgrade.source.guest.password; do printf '%s' "$ROOT" > $D/$k; done
printf '%s' "$ESXI" > $D/upgrade.source.guestops.host.password
printf '%s' "$ESXI" > $D/vpxd.ha.management.password
printf '%s' "$PNID" > $D/upgrade.source.vpxd.ip
chmod 644 $D/*.password $D/*.passwd $D/upgrade.source.vpxd.ip
echo "## restored:"; ls $D | grep -E "passw|upgrade.source.vpxd.ip"
