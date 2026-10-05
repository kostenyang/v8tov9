# 在 VCF Installer UI 選 VCF 9.1.1.0 的全部元件並下載(全程 UI,用 Playwright 代打)
import time
from playwright.sync_api import sync_playwright

SHOT = "E:/9.1/doc-shots/m03-ops/"
NL = "String.fromCharCode(10)"

ROWS_JS = (
    "() => [...document.querySelectorAll('clr-dg-row')].filter(r=>r.offsetParent)"
    ".map(r=>r.innerText.split(" + NL + ").map(x=>x.trim()).filter(Boolean).join(' / ').slice(0,90))"
)
TEXT_JS = "() => document.body.innerText"

with sync_playwright() as p:
    b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg = [x for c in b.contexts for x in c.pages if "vcf-m03-inst01" in x.url][0]
    pg.set_default_timeout(30000)

    pg.select_option("#product", "VMware Cloud Foundation")
    time.sleep(2)
    pg.select_option("#version", "9.1.1.0")
    time.sleep(5)
    print("filters:", pg.input_value("#product"), "/", pg.input_value("#version"))

    rows = pg.evaluate(ROWS_JS)
    print("元件列數:", len(rows))
    for r in rows:
        print("   ", r)

    pg.locator("#clr-dg-select-all-clr-id-1").check(force=True)
    time.sleep(2)
    n = pg.evaluate("()=>[...document.querySelectorAll('clr-dg-row input[type=checkbox]')].filter(c=>c.checked).length")
    print("已勾選:", n)
    pg.screenshot(path=SHOT + "49-binary-selection.png")

    btn = pg.locator("#downloadBundleButton")
    print("DOWNLOAD disabled:", btn.is_disabled())
    if not btn.is_disabled():
        btn.click()
        time.sleep(8)
        print("已按下載")
        txt = pg.evaluate(TEXT_JS)
        print(" | ".join(x.strip() for x in txt.split("\n") if x.strip())[:700])
        pg.screenshot(path=SHOT + "50-binary-download-started.png")
