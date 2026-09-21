// cdp-frame.mjs — 在指定子 frame(例如 vSphere Client 內的 plugin iframe)的 context 執行 JS,並可截整頁圖。
//   node cdp-frame.mjs --port 9222 --match "tko-100085" --frame "lcm-ui" --exprfile x.js [--shot out.png] [--wait ms]
//   exprfile 內以 function body 撰寫(可用 return)。
import { readFileSync, writeFileSync } from 'node:fs';
const args = {};
for (let i = 2; i < process.argv.length; i += 2) args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
const PORT = args.port || '9222', MATCH = args.match || '', FRAME = args.frame || '';
const EXPR = args.exprfile ? readFileSync(args.exprfile, 'utf8') : (args.expr || 'return "no-expr"');
const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
const t = list.find(x => x.type === 'page' && x.url.includes(MATCH));
if (!t) { console.error('no page matching ' + MATCH); process.exit(1); }
const ws = new WebSocket(t.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let id = 0;
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const mid = ++id;
  const onMsg = (ev) => { let m; try { m = JSON.parse(ev.data); } catch { return; }
    if (m.id === mid) { ws.removeEventListener('message', onMsg);
      m.error ? reject(new Error(method + ': ' + JSON.stringify(m.error))) : resolve(m.result); } };
  ws.addEventListener('message', onMsg);
  ws.send(JSON.stringify({ id: mid, method, params }));
  setTimeout(() => { ws.removeEventListener('message', onMsg); reject(new Error(method + ' timeout')); }, 90000);
});
await send('Page.enable'); await send('Runtime.enable');
const tree = await send('Page.getFrameTree');
const frames = []; (function walk(n) { frames.push(n.frame); (n.childFrames || []).forEach(walk); })(tree.frameTree);
const fr = FRAME ? frames.find(f => f.url.includes(FRAME)) : frames[0];
if (!fr) { console.error('no frame matching ' + FRAME + '; frames=' + frames.map(f => f.url.slice(0, 80)).join(' ; ')); process.exit(1); }
const { executionContextId } = await send('Page.createIsolatedWorld', { frameId: fr.id, worldName: 'cdpframe', grantUniveralAccess: true });
const r = await send('Runtime.evaluate', { expression: `(function(){ ${EXPR} })()`, contextId: executionContextId, returnByValue: true, awaitPromise: true });
if (r.exceptionDetails) console.error('EXC: ' + (r.exceptionDetails.exception?.description || JSON.stringify(r.exceptionDetails)));
else console.log(typeof r.result.value === 'string' ? r.result.value : JSON.stringify(r.result.value, null, 2));
if (args.wait) await new Promise(res => setTimeout(res, parseInt(args.wait, 10)));
if (args.shot) { const s = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(args.shot, Buffer.from(s.data, 'base64')); console.error('SHOT ' + args.shot); }
ws.close(); process.exit(0);
