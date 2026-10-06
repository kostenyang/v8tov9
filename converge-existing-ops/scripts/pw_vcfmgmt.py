# Prepare 第 4 步 VCF Management
#   🔑 這一步就是「把既有元件指進去」的地方:
#      - VCF Operations Primary node FQDN 指向**已經存在**的 vcf-m03-ops01
#      - License Server FQDN 指向**已經存在**的 vcf-m03-lic01(這欄只要 FQDN,
#        沒有密碼欄 → 本來就是設計成指既有的)
import os, sys
import time
from playwright.sync_api import sync_playwright

PW = os.environ.get("LABPASS") or sys.exit("set LABPASS")
FIELDS = [
    ("#clr-form-control-53",  "vcf-m03-ops01.home.lab"),          # VCF Ops Primary(既有)
    ("#clr-form-control-145", PW),                                 # Ops Administrator Password
    ("#clr-form-control-146", PW),                                 # Ops Primary Node Root Password
    ("#clr-form-control-147", PW),                                 # Ops Replica Node Root Password
    ("#clr-form-control-56",  "vcf-m03-opsc01.home.lab"),          # Cloud Proxy FQDN
    ("#clr-form-control-148", PW),                                 # Cloud Proxy Root Password
    ("#clr-form-control-57",  "vcf-m03-lic01.home.lab"),           # License Server(既有)
    ("#clr-form-control-59",  "vcf-m03-fleet01.home.lab"),         # Fleet components
    ("#clr-form-control-60",  "vcf-m03-shared01.home.lab"),        # Instance components
    ("#clr-form-control-61",  "vcf-m03-vidb.home.lab"),            # Identity Broker
    ("#clr-form-control-58",  "vcf-m03-vsp01.home.lab"),           # VCF services runtime(Mgmt)
    ("#clr-form-control-149", PW),                                 # System User password
    ("#clr-form-control-63",  "vcf-m03-auto-vip.home.lab"),        # VCF Automation FQDN
    ("#clr-form-control-64",  "vcf-m03-auto-platform.home.lab"),   # VCF Automation services runtime
    ("#clr-form-control-150", PW),                                 # VCFA Administrator Password
]
with sync_playwright() as p:
    b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg = [x for c in b.contexts for x in c.pages if "vcf-m03-inst01" in x.url][0]
    pg.set_default_timeout(30000)
    for sel, val in FIELDS:
        pg.locator(sel).fill(val)
        time.sleep(0.25)
    time.sleep(3)
    print(pg.evaluate("""() => [...document.querySelectorAll('input,select')].filter(e=>e.offsetParent).map(e=>{
       const l=document.querySelector('label[for="'+e.id+'"]');
       return ((l&&l.innerText||'').trim().replace(/\s+/g,' ').slice(0,30)).padEnd(32)
              +' = '+(e.type==='password'?(e.value.length+'c'):e.value);}).join(String.fromCharCode(10))"""))
    pg.screenshot(path="E:/9.1/doc-shots/m03-ops/58-prepare-vcf-management.png")
