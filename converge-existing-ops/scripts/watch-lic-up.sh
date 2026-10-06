#!/usr/bin/env bash
for i in $(seq 1 120); do
  if ping -n 1 -w 1000 10.0.1.62 >/dev/null 2>&1; then p=ping-ok; else p=ping-no; fi
  c=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 6 https://10.0.1.62/ 2>/dev/null)
  [ -z "$c" ] && c=000
  echo "$(date +%H:%M:%S) $p https=$c"
  if [ "$c" != "000" ]; then echo LIC-UP; break; fi
  sleep 20
done
