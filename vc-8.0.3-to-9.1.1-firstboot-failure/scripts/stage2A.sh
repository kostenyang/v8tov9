#!/bin/bash
N=/e/9.1/tools/node-v24.16.0-win-x64/node.exe; S=${S:-E:/9.1/chtvcd/rep4}
A(){ timeout 60 $N cdp-attach.mjs --port 9333 --match 5480 --exprfile "$1" 2>&1 | tail -1; }; F(){ timeout 60 $N /e/9.1/tools/cdp-frame.mjs --port 9333 --match 5480 "$@" 2>&1; }
W(){ for i in $(seq 1 30); do sleep 15; T=$(F --expr "const t=document.body.innerText; return (/in progress/.test(t)?'INPROGRESS':'')+(t.includes('Pre-upgrade check result')?' RESULT':'')+(t.includes('Confirmation')?' CONFIRM':'')+' ACTIVE='+[...document.querySelectorAll('.active')].map(e=>e.textContent.trim().replace(/\s+/g,' ')).filter(x=>/^Step/.test(x)).join('/')"); echo "[$(date -u +%H:%M:%S)] $T"; echo "$T" | grep -q INPROGRESS || break; done; }
$N cdp-io.mjs --click 997,589 --wait 15000 >/dev/null 2>&1
for i in $(seq 1 20); do B=$(F --expr "return [...document.querySelectorAll('button')].filter(b=>b.offsetParent!==null).map(b=>b.textContent.trim()).join('|')"); echo "$B" | grep -q "Next" && break; sleep 5; done
F --expr "return 'ok'" --shot $S/A07-0-stage2-intro.png | tail -1
A v2next.js; W; F --expr "const t=document.body.innerText.replace(/\n{2,}/g,'\n'); const i=t.lastIndexOf('Pre-upgrade check result'); const s=t.slice(i,i+2500); return 'errors='+(s.match(/\nError\n/g)||[]).length+' warnings='+(s.match(/\nWarning\n/g)||[]).length" --shot $S/A07-stage2-precheck.png | tail -2
A v2close.js; sleep 2; A v2next.js; W; F --expr "return 'ok'" --shot $S/A07b-confirm.png | tail -1
A v2proceed.js; sleep 3; A v2next.js; W
F --expr "const t=document.body.innerText.replace(/\n{2,}/g,'\n'); const i=t.lastIndexOf('Pre-upgrade check result'); const s=t.slice(i,i+2500); return 'errors='+(s.match(/\nError\n/g)||[]).length+' warnings='+(s.match(/\nWarning\n/g)||[]).length" | tail -1
A v2close.js; sleep 2; A v2next.js; W; A v2next.js; sleep 5
F --expr "const t=document.body.innerText.replace(/\n{2,}/g,'\n'); const i=t.lastIndexOf('Ready to complete\n'); return t.slice(i,i+300)" --shot $S/A08-stage2-ready.png | head -6
A v2ack.js | tail -c 80; echo; A v2finish.js; sleep 4; A v2ok.js; sleep 20
F --expr "const t=document.body.innerText.replace(/\n{2,}/g,'\n'); const i=t.lastIndexOf('Beginning of Modal Content'); return t.slice(i,i+300)" --shot $S/A09-stage2-progress.png | head -8
echo "stage2 started $(date -u +%H:%M:%S)"
last=""; for i in $(seq 1 90); do T=$(F --expr "const t=document.body.innerText.replace(/\n{2,}/g,'\n'); const i=t.lastIndexOf('Beginning of Modal Content'); return t.slice(i,i+700)"); P=$(echo "$T" | grep -oE "[0-9]+%" | head -1); L=$(echo "$T" | grep -vE "Modal Content|^[0-9]+%$|^Upgrade - Stage|CLOSE" | grep -vE "^\s*$" | head -3 | tr '\n' ' ' | cut -c1-200); echo "[$(date -u +%H:%M:%S)] $P $L"; K="$(echo "$L" | cut -c1-30)"; [ "$K" != "$last" ] && { F --expr "return 1" --shot "$S/A09-stage2-$(date -u +%H%M%S).png" >/dev/null 2>&1; last="$K"; }; echo "$T" | grep -qiE "Encountered an internal error|Firstboot Error|Traceback|successfully upgraded|has been upgraded|upgrade.*complete" && { echo "END"; F --expr "return 1" --shot $S/A10-stage2-done.png >/dev/null 2>&1; break; }; sleep 45; done
