#!/usr/bin/env python3
"""
VCF Installer Deployment Wizard — 一次填完 Introduction + Prepare 九步(m03b greenfield)

用 Playwright 接現有的有頭 Chrome(CDP 9222),全程走 UI。
每一步都截圖到 E:/9.1/doc-shots/m03-ops/。

  python pw_wizard_m03b.py            # 從頭跑(會先取消舊的精靈進度)
  python pw_wizard_m03b.py --resume   # 不取消,直接從目前這一步接下去
"""
import os, sys
import sys, time
from playwright.sync_api import sync_playwright

SHOT = "E:/9.1/doc-shots/m03-ops/"
PW = os.environ.get("LABPASS") or sys.exit("set LABPASS")
DOMAIN = "home.lab"

HOSTS = [f"vcf-m03b-esx0{i}.{DOMAIN}" for i in (1, 2, 3, 4)]

NET = {  # 欄位 label 片段 -> 值(Networks 那一步靠順序對應,見 fill_networks)
    "esx_mgmt": ("0", "10.0.0.1/23"),
    "vm_mgmt":  ("0", "10.0.0.1/23"),
    "pool_mgmt": "10.0.1.80 - 10.0.1.95",
    "pool_vcfa": "10.0.1.96 - 10.0.1.102",
    "vmotion": ("0", "9000", "192.168.35.1/24", "192.168.35.11", "192.168.35.20"),
    "vsan":    ("0", "9000", "192.168.36.1/24", "192.168.36.11", "192.168.36.20"),
    "nsx":     ("0", "192.168.37.1/24", "192.168.37.11", "192.168.37.30"),
}

MGMT = {   # VCF Management 那一步
    "ops_primary": f"vcf-m03-ops01.{DOMAIN}",      # 既有!
    "ops_replica": f"vcf-m03-ops02.{DOMAIN}",
    "cloud_proxy": f"vcf-m03-opsc01.{DOMAIN}",
    "license":     f"vcf-m03-lic01.{DOMAIN}",      # 既有!
    "fleet":       f"vcf-m03-fleet01.{DOMAIN}",
    "instance":    f"vcf-m03-shared01.{DOMAIN}",
    "vidb":        f"vcf-m03-vidb.{DOMAIN}",
    "vsp":         f"vcf-m03-vsp01.{DOMAIN}",
    "auto":        f"vcf-m03-auto-vip.{DOMAIN}",
    "auto_plat":   f"vcf-m03-auto-platform.{DOMAIN}",
}
VCENTER = f"vcf-m03b-vc01.{DOMAIN}"
NSX = {"vip": f"vcf-m03-nsx01.{DOMAIN}",
       "a": f"vcf-m03-nsx01a.{DOMAIN}", "b": f"vcf-m03-nsx01b.{DOMAIN}", "c": f"vcf-m03-nsx01c.{DOMAIN}"}
SDDCM = f"vcf-m03-sddcm01.{DOMAIN}"


def page_of(b):
    return [x for c in b.contexts for x in c.pages if "vcf-m03-inst01" in x.url][0]


def txt(pg, n=2500):
    t = pg.evaluate("()=>document.body.innerText")
    return " | ".join(x.strip() for x in t.split("\n") if x.strip())[:n]


def click_label(pg, label):
    """🔴 精靈按鈕的 class 每一步都不同,DOM 文字又是 ' Next '(大寫是 CSS 變的)。
       唯一穩的做法:在頁面裡用 innerText 找『可見且未 disabled』的那一顆。"""
    idx = pg.evaluate("""(label)=>{const bs=[...document.querySelectorAll('button')];
      for(let i=0;i<bs.length;i++){const b=bs[i];
        if(b.offsetParent && !b.disabled && (b.innerText||'').trim().toUpperCase()===label) return i;}
      return -1;}""", label.upper())
    if idx < 0:
        raise RuntimeError(f"找不到可按的 {label}")
    pg.locator("button").nth(idx).click()


def inputs(pg):
    """回傳目前這一步可見的 input/select:[(id, type, label)]"""
    return pg.evaluate("""() => [...document.querySelectorAll('input,select,textarea')]
      .filter(e=>e.offsetParent)
      .map(e=>{const l=document.querySelector('label[for="'+e.id+'"]');
        return [e.id, e.type||e.tagName.toLowerCase(), ((l&&l.innerText)||'').trim()];})""")


def errors(pg):
    return pg.evaluate("""()=>[...document.querySelectorAll('.clr-subtext')]
      .filter(e=>e.offsetParent&&e.innerText.trim()).map(e=>e.innerText.trim()).join(' || ')""")


def step(pg, name, shot=None, wait=6):
    time.sleep(wait)
    if shot:
        pg.screenshot(path=SHOT + shot)
    print(f"--- {name}" + (f"  [{shot}]" if shot else ""))


def main():
    resume = "--resume" in sys.argv
    with sync_playwright() as p:
        b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
        pg = page_of(b)
        pg.set_default_timeout(45000)

        if not resume:
            pg.goto("https://vcf-m03-inst01.home.lab/vcf-installer-ui/portal/getting-started")
            pg.wait_for_load_state("networkidle"); time.sleep(3)
            if "CANCEL PROGRESS" in pg.evaluate("()=>document.body.innerText").upper():
                click_label(pg, "CANCEL PROGRESS"); time.sleep(3)
                # 可能跳確認對話框
                try:
                    click_label(pg, "CANCEL PROGRESS"); time.sleep(2)
                except Exception:
                    for lbl in ("YES", "CONFIRM", "OK"):
                        try: click_label(pg, lbl); time.sleep(2); break
                        except Exception: pass
                print("已取消舊的精靈進度")
            time.sleep(2)
            # 開精靈:DEPLOYMENT WIZARD 是下拉,Clarity 只吃鍵盤 Enter
            pg.evaluate("""()=>{const b=[...document.querySelectorAll('button')]
              .find(x=>x.offsetParent&&(x.innerText||'').trim()==='DEPLOYMENT WIZARD'); b && b.focus();}""")
            pg.keyboard.press("Enter"); time.sleep(2)
            pg.get_by_text("VMware Cloud Foundation", exact=True).last.click()
            step(pg, "Introduction 1/2 About", "70-wiz-intro.png")
            click_label(pg, "NEXT")
            step(pg, "Introduction 2/2 Deployment Paths", "71-wiz-paths.png")
            click_label(pg, "NEXT")          # 預設已選 Deploy a new VCF fleet
            step(pg, "Prepare 1 General Information")

        # ---- Prepare 1:General Information -------------------------------
        f = {lbl: i for i, t, lbl in inputs(pg)}
        pg.locator("#" + f["VCF Instance name"]).fill("vcf-m03b-instance")
        pg.locator("#" + f["Management domain name"]).fill("vcf-m03b")
        for i, t, lbl in inputs(pg):          # 兩個 Opt-in:CEIP 與 Autogenerate passwords
            if lbl == "Opt-in":
                c = pg.locator("#" + i)
                if c.is_checked():
                    c.uncheck(force=True); time.sleep(0.8)
        step(pg, "Prepare 1 填完", "72-wiz-general.png", 3)
        click_label(pg, "NEXT")

        # ---- Prepare 2:Hosts ---------------------------------------------
        step(pg, "Prepare 2 Hosts", None, 6)
        ids = [i for i, t, lbl in inputs(pg) if lbl == "FQDN / hostname"]
        pwd = [i for i, t, lbl in inputs(pg) if t == "password"]
        chk = [i for i, t, lbl in inputs(pg) if t == "checkbox"]
        pg.locator("#" + ids[0]).fill(HOSTS[0])
        pg.locator("#" + pwd[0]).fill(PW); time.sleep(1)
        if chk:
            c = pg.locator("#" + chk[0])
            if not c.is_checked(): c.check(force=True)
            time.sleep(1.5)
        for k in range(1, 4):
            pg.locator("#" + ids[k]).fill(HOSTS[k])
            try:
                pf = [i for i, t, lbl in inputs(pg) if t == "password"]
                if len(pf) > k and not pg.locator("#" + pf[k]).input_value():
                    pg.locator("#" + pf[k]).fill(PW)
            except Exception:
                pass
            time.sleep(0.4)
        click_label(pg, "CONFIRM ALL FINGERPRINTS")
        step(pg, "Prepare 2 指紋確認", "73-wiz-hosts.png", 25)
        click_label(pg, "NEXT")
        time.sleep(4)
        if "YES, PROCEED" in pg.evaluate("()=>document.body.innerText").upper():
            pg.screenshot(path=SHOT + "74-wiz-resource-warning.png")
            click_label(pg, "YES, PROCEED")
            print("    (已接受 Resource Requirements Warning)")

        # ---- Prepare 3:Networks ------------------------------------------
        step(pg, "Prepare 3 Networks", None, 6)
        fill_networks(pg)
        step(pg, "Prepare 3 填完", "75-wiz-networks.png", 3)
        click_label(pg, "NEXT")

        # ---- Prepare 4:VCF Management -------------------------------------
        step(pg, "Prepare 4 VCF Management", None, 6)
        f = {}
        for i, t, lbl in inputs(pg):
            f.setdefault(lbl, []).append(i)
        pg.locator("#" + f["Primary node FQDN"][0]).fill(MGMT["ops_primary"])
        pg.locator("#" + f["Replica node FQDN"][0]).fill(MGMT["ops_replica"])
        pg.locator("#" + f["Administrator Password"][0]).fill(PW)
        pg.locator("#" + f["Primary Node Root Password"][0]).fill(PW)
        pg.locator("#" + f["Replica Node Root Password"][0]).fill(PW)
        pg.locator("#" + f["FQDN"][0]).fill(MGMT["cloud_proxy"])     # Cloud Proxy
        pg.locator("#" + f["Root Password"][0]).fill(PW)
        pg.locator("#" + f["FQDN"][1]).fill(MGMT["license"])         # License Server(既有)
        pg.locator("#" + f["Fleet components FQDN"][0]).fill(MGMT["fleet"])
        pg.locator("#" + f["Instance components FQDN"][0]).fill(MGMT["instance"])
        pg.locator("#" + f["Identity Broker FQDN"][0]).fill(MGMT["vidb"])
        pg.locator("#" + f["VCF services runtime FQDN"][0]).fill(MGMT["vsp"])
        pg.locator("#" + f["System User password"][0]).fill(PW)
        pg.locator("#" + f["VCF Automation FQDN"][0]).fill(MGMT["auto"])
        pg.locator("#" + f["VCF services runtime FQDN"][1]).fill(MGMT["auto_plat"])
        pg.locator("#" + f["Administrator Password"][1]).fill(PW)
        step(pg, "Prepare 4 填完", "76-wiz-vcfmgmt.png", 4)
        print("    errors:", errors(pg) or "(none)")
        click_label(pg, "NEXT")

        # ---- Prepare 5:vCenter --------------------------------------------
        step(pg, "Prepare 5 vCenter", None, 6)
        f = {lbl: i for i, t, lbl in inputs(pg)}
        pg.locator("#" + f["vCenter FQDN"]).fill(VCENTER)
        pg.locator("#" + f["Administrator Password"]).fill(PW)
        pg.locator("#" + f["Root password"]).fill(PW)
        step(pg, "Prepare 5 填完", "77-wiz-vcenter.png", 3)
        click_label(pg, "NEXT")

        # ---- Prepare 6:Storage(用預設的 datastore 名稱,這是新叢集)-------
        step(pg, "Prepare 6 Storage", "78-wiz-storage.png", 6)
        click_label(pg, "NEXT")

        # ---- Prepare 7:Distributed Switch(選 Default profile)-------------
        step(pg, "Prepare 7 Distributed Switch", "79-wiz-vds-profile.png", 6)
        click_label(pg, "SELECT")             # 第一個 SELECT = Default profile
        step(pg, "Prepare 7 Default profile", "80-wiz-vds-config.png", 8)
        click_label(pg, "NEXT")

        # ---- Prepare 8:NSX Manager -----------------------------------------
        step(pg, "Prepare 8 NSX Manager", None, 6)
        f = {lbl: i for i, t, lbl in inputs(pg)}
        pg.locator("#" + f["Cluster FQDN"]).fill(NSX["vip"])
        pg.locator("#hostname-0").fill(NSX["a"])
        pg.locator("#hostname-1").fill(NSX["b"])
        pg.locator("#hostname-2").fill(NSX["c"])
        for lbl in ("Administrator Password", "Root password", "Audit Password"):
            pg.locator("#" + f[lbl]).fill(PW)
        step(pg, "Prepare 8 填完", "81-wiz-nsx.png", 3)
        click_label(pg, "NEXT")

        # ---- Prepare 9:SDDC Manager ----------------------------------------
        step(pg, "Prepare 9 SDDC Manager", None, 6)
        f = {lbl: i for i, t, lbl in inputs(pg)}
        pg.locator("#" + f["SDDC Manager FQDN"]).fill(SDDCM)
        for lbl in ("Administrator Password", "Root password", "VCF Password"):
            pg.locator("#" + f[lbl]).fill(PW)
        step(pg, "Prepare 9 填完", "82-wiz-sddcm.png", 3)
        click_label(pg, "NEXT")

        # ---- Review ---------------------------------------------------------
        step(pg, "Review 摘要", "83-wiz-review.png", 10)
        print(txt(pg, 400))
        print("\n>>> Prepare 九步填完。下一步:NEXT 進 Validate & Deploy")


def fill_networks(pg):
    """Networks 這一步欄位沒有唯一 label,靠 DOM 順序對應。
       🔴 填完 Gateway 後,UI 會『非同步』自動塞 IP Address Range From 的預設值,
          會跟先前填的值串在一起變成 '192.168.35.2192.168.35.11' —— 要最後再補填一次。"""
    ins = inputs(pg)
    vlan = [i for i, t, lbl in ins if lbl == "VLAN ID"]
    gw   = [i for i, t, lbl in ins if lbl == "IPv4 Gateway (CIDR notation)"]
    mtu  = [i for i, t, lbl in ins if lbl == "MTU"]
    rfrom = [i for i, t, lbl in ins if lbl == "IP Address Range From"]
    rto   = [i for i, t, lbl in ins if lbl == "IP Address Range To"]
    ta    = [i for i, t, lbl in ins if t == "textarea"]

    pg.locator("#" + vlan[0]).fill(NET["esx_mgmt"][0]); pg.locator("#" + gw[0]).fill(NET["esx_mgmt"][1])
    pg.locator("#" + vlan[1]).fill(NET["vm_mgmt"][0]);  pg.locator("#" + gw[1]).fill(NET["vm_mgmt"][1])
    pg.locator("#" + ta[0]).fill(NET["pool_mgmt"])
    pg.locator("#" + ta[1]).fill(NET["pool_vcfa"])
    vm = NET["vmotion"]; vs = NET["vsan"]; nx = NET["nsx"]
    pg.locator("#" + vlan[2]).fill(vm[0]); pg.locator("#" + mtu[0]).fill(vm[1]); pg.locator("#" + gw[2]).fill(vm[2])
    pg.locator("#" + vlan[3]).fill(vs[0]); pg.locator("#" + mtu[1]).fill(vs[1]); pg.locator("#" + gw[3]).fill(vs[2])
    pg.locator("#" + vlan[4]).fill(nx[0]); pg.locator("#" + gw[4]).fill(nx[2 - 1])
    time.sleep(2)
    for sel, val in ((rfrom[0], vm[3]), (rto[0], vm[4]),
                     (rfrom[1], vs[3]), (rto[1], vs[4]),
                     (rfrom[2], nx[2]), (rto[2], nx[3])):
        pg.locator("#" + sel).fill(""); time.sleep(0.3)
        pg.locator("#" + sel).fill(val); time.sleep(0.3)


if __name__ == "__main__":
    main()
