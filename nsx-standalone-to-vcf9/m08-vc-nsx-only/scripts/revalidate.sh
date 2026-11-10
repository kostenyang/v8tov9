#!/bin/bash
cd "$(dirname "$0")/.."   # needs $INSTPASS; posts converge-m08-spec.json
OUT=${1:-val-m08-api3.json}
TOK=$(curl.exe -sk -X POST -H "Content-Type: application/json" --max-time 20 "https://10.0.1.155/v1/tokens" -d '{"username":"admin@local","password":"'"$INSTPASS"'"}' | python -I -c "import sys,json;print(json.load(sys.stdin)['accessToken'])")
VID=$(curl.exe -sk -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" --max-time 60 --data-binary @converge-m08-spec.json "https://10.0.1.155/v1/sddcs/validations" | python -I -c "import sys,json;print(json.load(sys.stdin)['id'])")
echo "validation $VID"
for i in $(seq 1 45); do sleep 20
  R=$(curl.exe -sk -H "Authorization: Bearer $TOK" --max-time 25 "https://10.0.1.155/v1/sddcs/validations/$VID")
  ST=$(echo "$R" | python -I -c "import sys,json;d=json.load(sys.stdin);print(d.get('executionStatus'),d.get('resultStatus'))" 2>/dev/null)
  case "$ST" in *IN_PROGRESS*|*UNKNOWN*|"") ;; *) echo "$R" > "$OUT"; break;; esac
done
python -I -c "
import json,sys
d=json.load(open(sys.argv[1]))
print('OVERALL:',d.get('executionStatus'),d.get('resultStatus'))
for c in d.get('validationChecks',[]):
    print('  [%s] %s'%(c.get('resultStatus'),c.get('description')))
    for ne in ((c.get('errorResponse') or {}).get('nestedErrors') or []): print('      -',ne.get('errorCode'),'::',(ne.get('message') or '')[:160])
" "$OUT"
