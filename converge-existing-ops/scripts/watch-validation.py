#!/usr/bin/env python3
"""輪詢 VCF Installer 精靈的 Validate & Deploy 表格,直到 16 項驗證全部跑完。"""
import time
from playwright.sync_api import sync_playwright

ROWS_JS = """() => [...document.querySelectorAll('clr-dg-row')].filter(r=>r.offsetParent)
  .map(r=>r.innerText.split(String.fromCharCode(10)).map(x=>x.trim()).filter(Boolean).join(' :: '))"""

with sync_playwright() as p:
    b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg = [x for c in b.contexts for x in c.pages if "vcf-m03-inst01" in x.url][0]
    pg.set_default_timeout(30000)
    last = None
    for i in range(120):
        rows = pg.evaluate(ROWS_JS)
        done = [r for r in rows if "Not Started" not in r and "In Progress" not in r]
        state = f"{len(done)}/{len(rows)}"
        if state != last:
            print(f"{time.strftime('%H:%M:%S')} 完成 {state}", flush=True)
            last = state
        if rows and len(done) == len(rows):
            print("VALIDATION-DONE", flush=True)
            for r in rows:
                print("  " + r[:160], flush=True)
            pg.screenshot(path="E:/9.1/doc-shots/m03-ops/99-validation-converge.png")
            break
        time.sleep(30)
    else:
        print("VALIDATION-TIMEOUT", flush=True)
