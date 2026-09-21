#!/bin/bash
# Step 0: make sure the installer's failure cleanup (exit_cleanup -> prune-sensitive-info) has finished
# before touching anything, otherwise it will wipe the parameters you restore in Step 2.
for i in $(seq 1 60); do
  n=$(ls /etc/vmware/install-defaults/ | grep -ciE passw); p=$(ps -eo stat,args | grep -E "[i]nvoke_upgrade" | grep -vc "Z")
  echo "$(date +%H:%M:%S) password-params=$n  invoke_upgrade running=$p"
  [ "$p" = "0" ] && [ "$n" -le 1 ] && { echo "## cleanup finished - safe to continue"; exit 0; }
  sleep 10
done
