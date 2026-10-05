#!/usr/bin/env python3
"""輪詢 VCF Installer 的部署進度(converge:既有 vCenter + 既有 VCF Operations)。
每 3 分鐘印一次里程碑進度,狀態有變才印細節。"""
import time
from playwright.sync_api import sync_playwright

MILESTONE_JS = """() => {
  const out=[];
  document.querySelectorAll('*').forEach(e=>{
    const t=(e.innerText||'').trim();
    const m=t.match(/^(.+?)\\s+(\\d+)\\s*\\/\\s*(\\d+)\\s+Completed$/);
    if(m && e.children.length<4 && !out.some(x=>x.name===m[1])) out.push({name:m[1],done:+m[2],total:+m[3]});
  });
  return out;
}"""
STATUS_JS = """() => {
  const t=document.body.innerText;
  const g=(re)=>{const m=t.match(re); return m?m[1]:'?';};
  return {notStarted:g(/Not Started \\((\\d+)\\)/), inprog:g(/In progress \\((\\d+)\\)/),
          ok:g(/Successful \\((\\d+)\\)/), failed:g(/Failed \\((\\d+)\\)/)};
}"""

with sync_playwright() as p:
    b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg = [x for c in b.contexts for x in c.pages if "vcf-m03-inst01" in x.url][0]
    pg.set_default_timeout(60000)
    last = None
    for i in range(400):           # 400 x 3 分鐘 = 20 小時上限
        try:
            ms = pg.evaluate(MILESTONE_JS)
            st = pg.evaluate(STATUS_JS)
        except Exception as e:
            print(f"{time.strftime('%H:%M:%S')} (讀取失敗 {str(e)[:60]})", flush=True)
            time.sleep(180); continue
        line = " | ".join(f"{m['name']} {m['done']}/{m['total']}" for m in ms)
        key = line + str(st)
        if key != last:
            print(f"{time.strftime('%H:%M:%S')} 成功={st['ok']} 進行中={st['inprog']} 失敗={st['failed']}", flush=True)
            for m in ms:
                print(f"    {m['done']:>3}/{m['total']:<3} {m['name']}", flush=True)
            last = key
        if st['failed'] not in ('0', '?'):
            print("DEPLOY-HAS-FAILURES", flush=True)
            pg.screenshot(path="E:/9.1/doc-shots/m03-ops/101-deploy-failed.png")
        if ms and all(m['done'] == m['total'] for m in ms):
            print("DEPLOY-DONE", flush=True)
            pg.screenshot(path="E:/9.1/doc-shots/m03-ops/101-deploy-done.png")
            break
        time.sleep(180)
    else:
        print("DEPLOY-TIMEOUT", flush=True)
