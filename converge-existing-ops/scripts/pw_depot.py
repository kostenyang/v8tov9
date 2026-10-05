# 用 Playwright 在 VCF Installer UI 設定 offline depot(全程 UI)
import os, sys
import sys, time
from playwright.sync_api import sync_playwright

URL  = sys.argv[1] if len(sys.argv) > 1 else "https://10.0.0.61"
USER = "vcfdepot"
PASS = os.environ.get("LABPASS") or sys.exit("set LABPASS")
SHOT = "E:/9.1/doc-shots/m03-ops/"

with sync_playwright() as p:
    b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg = [x for c in b.contexts for x in c.pages if "vcf-m03-inst01" in x.url][0]
    pg.set_default_timeout(30000)

    pg.goto("https://vcf-m03-inst01.home.lab/vcf-installer-ui/portal/depot-home")
    pg.wait_for_load_state("networkidle")
    time.sleep(2)
    print("目前狀態:", " | ".join(x.strip() for x in pg.evaluate("()=>document.body.innerText").split("\n") if x.strip())[:400])
    pg.screenshot(path=SHOT+"46a-depot-home-before.png")

    # Offline Depot 區塊的 CONFIGURE
    offline = pg.locator("section,div").filter(has_text="Offline Depot").last
    pg.get_by_role("button", name="CONFIGURE").nth(1).click()
    pg.wait_for_selector(".modal-dialog", timeout=15000)
    time.sleep(1.5)

    dlg = pg.locator(".modal-dialog").last
    dlg.locator("input[type=text]").first.fill(URL)
    print("URL 填好:", URL)

    # Authentication toggle
    chk = dlg.locator("input[type=checkbox]").first
    if not chk.is_checked():
        chk.check(force=True)
    print("auth toggle:", chk.is_checked())
    time.sleep(1.5)

    dlg.locator("input[type=text]").nth(1).fill(USER)
    dlg.locator("input[type=password]").first.fill(PASS)
    pg.screenshot(path=SHOT+"46-offline-depot-config.png")
    print("帳密填好")

    dlg.get_by_role("button", name="CONFIGURE").click()
    # 憑證指紋對話框
    try:
        pg.wait_for_selector("text=Certificate Thumbprint", timeout=20000)
        time.sleep(1)
        tdlg = pg.locator(".modal-dialog").filter(has_text="Certificate Thumbprint").last
        print("指紋:", tdlg.locator("text=/[0-9A-F]{2}(:[0-9A-F]{2}){10,}/").first.inner_text()[:100])
        pg.screenshot(path=SHOT+"47-depot-cert-thumbprint.png")
        tdlg.locator("input[type=checkbox]").first.check(force=True)
        tdlg.get_by_role("button", name="CONFIRM").click()
        print("已確認指紋")
    except Exception as e:
        print("(沒有指紋對話框或已信任):", str(e)[:120])

    time.sleep(12)
    pg.wait_for_load_state("networkidle")
    txt = " | ".join(x.strip() for x in pg.evaluate("()=>document.body.innerText").split("\n") if x.strip())
    print("結果:", txt[:700])
    pg.screenshot(path=SHOT+"48-depot-configured.png")
