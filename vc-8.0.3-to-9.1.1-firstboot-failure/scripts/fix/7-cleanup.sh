#!/bin/bash
# Step 7: do what exit_cleanup would have done + release temp IP
/bin/prune-sensitive-info >/dev/null 2>&1
echo "## password params left: $(ls /etc/vmware/install-defaults/ | grep -ciE passw) (db.password_services is normal)"
bash /storage/seat/cis-export-folder/system-data/release_temp_addresses.sh >/dev/null 2>&1
echo "## addresses:"; ip -4 -br addr | grep eth0
