#!/usr/bin/env bash
# 在 VCF Installer UI 設定 offline depot(全程 UI 操作,只是用 CDP 代打)
#   🔴 三個已驗證的要點:
#     1) 欄位要用「逐字 keyDown/keyUp(帶 text)」真打字 —— Input.insertText 不會讓
#        Angular form control 變 dirty,toggle 會一直是 disabled
#     2) Clarity toggle 要用真實滑鼠點「input 的即時座標」—— 對話框會重新排版,
#        座標要在點之前重新量
#     3) 自簽憑證會跳 Certificate Thumbprint 對話框,要比對後 CONFIRM
set -eu
export PATH="/e/9.1/tools/node-v24.16.0-win-x64:$PATH"; cd /e/9.1/tools
M="vcf-m03-inst01"
URL="${DEPOT_URL:-https://vcf9depotserver.home.lab}"
USER="${DEPOT_USER:-vcfdepot}"
PASS="${DEPOT_PASS:?set DEPOT_PASS}"

say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "開 Offline Depot 對話框"
cat > /tmp/_od1.js <<'JS'
function fire(el){const r=el.getBoundingClientRect();const cx=r.x+r.width/2,cy=r.y+r.height/2;
const o={bubbles:true,cancelable:true,composed:true,clientX:cx,clientY:cy,button:0,buttons:1,view:window};
el.dispatchEvent(new PointerEvent("pointerdown",o));el.dispatchEvent(new MouseEvent("mousedown",o));
if(el.focus)el.focus();
el.dispatchEvent(new PointerEvent("pointerup",{...o,buttons:0}));el.dispatchEvent(new MouseEvent("mouseup",{...o,buttons:0}));
el.dispatchEvent(new MouseEvent("click",{...o,buttons:0}));el.click();}
const bs=[...document.querySelectorAll('button')].filter(b=>b.offsetParent&&(b.innerText||'').trim().toUpperCase()==='CONFIGURE');
if(bs.length<2) return 'only '+bs.length+' CONFIGURE';
fire(bs[1]); return 'ok';
JS
node cdp-frame.mjs --match "$M" --exprfile /tmp/_od1.js
sleep 3

URLID=$(node cdp-frame.mjs --match "$M" --expr "const d=[...document.querySelectorAll('.modal-dialog')].filter(x=>x.offsetParent).pop(); return d.querySelector('input[type=text]').id;")
say "URL 欄位 = $URLID"
node cdp-type.mjs --match "$M" --sel "#$URLID" --text "$URL" --clear 1

say "量 toggle 即時座標並點"
XY=$(node cdp-frame.mjs --match "$M" --expr "const d=[...document.querySelectorAll('.modal-dialog')].filter(x=>x.offsetParent).pop(); const c=d.querySelector('input[type=checkbox]'); const r=c.getBoundingClientRect(); return Math.round(r.x+r.width/2)+','+Math.round(r.y+r.height/2);")
node cdp-xy.mjs --match "$M" --xy "$XY" --wait 2000

IDS=$(node cdp-frame.mjs --match "$M" --expr "const d=[...document.querySelectorAll('.modal-dialog')].filter(x=>x.offsetParent).pop(); const t=[...d.querySelectorAll('input[type=text]')].filter(i=>i.offsetParent); const p=d.querySelector('input[type=password]'); return t[t.length-1].id+' '+(p?p.id:'NONE');")
USERID=$(echo "$IDS" | awk '{print $1}'); PID=$(echo "$IDS" | awk '{print $2}')
say "帳號欄=$USERID 密碼欄=$PID"
[ "$PID" = "NONE" ] && { echo "toggle 沒打開,中止"; exit 1; }
node cdp-type.mjs --match "$M" --sel "#$USERID" --text "$USER"
node cdp-type.mjs --match "$M" --sel "#$PID" --text "$PASS"
say "填好,等你的下一步(CONFIGURE)"
