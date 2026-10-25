#!/bin/bash
# poll converge; screenshot progress page on milestone change; exit on terminal state or first FAILED subtask
cd "$(dirname "$0")/.."; ID=${1:?usage: monitor-converge.sh <deployment-id>}  # needs $INSTPASS
 LAST=""; N=20
tok(){ curl.exe -sk -X POST -H "Content-Type: application/json" --max-time 20 "https://10.0.1.155/v1/tokens" -d '{"username":"admin@local","password":"'"$INSTPASS"'"}' | python -I -c "import sys,json;print(json.load(sys.stdin)['accessToken'])"; }
TOK=$(tok); T0=$(date +%s)
while true; do
  [ $(( $(date +%s) - T0 )) -gt 2400 ] && { TOK=$(tok); T0=$(date +%s); }
  curl.exe -sk -H "Authorization: Bearer $TOK" --max-time 30 "https://10.0.1.155/v1/sddcs/$ID" > conv-status.json 2>/dev/null
  S=$(python -I -c "
import json
d=json.load(open('conv-status.json'))
ms=d.get('milestones') or []
ok=sum(m.get('completedTasks') or 0 for m in ms); tot=sum(m.get('totalTasks') or 0 for m in ms)
fail=[t.get('name') for t in (d.get('sddcSubTasks') or []) if 'FAIL' in (t.get('status') or '')]
cur=[m.get('name') for m in ms if m.get('status')=='IN_PROGRESS']
print(d.get('status'),'|',ok,'/',tot,'| cur=',(cur[0][:50] if cur else '-'),'| fail=',fail[:2])
" 2>/dev/null)
  [ -z "$S" ] && { TOK=$(tok); sleep 60; continue; }
  echo "$(date +%H:%M) $S" >> conv-progress.log
  MS=$(echo "$S" | sed 's/.*cur= \(.*\) | fail.*/\1/')
  if [ "$MS" != "$LAST" ]; then N=$((N+1)); python -I ui/inst.py shot "doc/shots/p6-$N-progress.png" >/dev/null 2>&1; LAST="$MS"; echo "MILESTONE -> $MS ($S)"; fi
  case "$S" in COMPLETED*|FAILED*|*"fail= ['"*) python -I ui/inst.py shot doc/shots/p6-99-final.png >/dev/null 2>&1; echo "DONE: $S"; exit 0;; esac
  sleep 120
done
