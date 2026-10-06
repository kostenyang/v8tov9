# Prepare 第 3 步 Networks
# nested lab:全部 untagged(VLAN 0),vMotion/vSAN/TEP 各給獨立網段
import time
from playwright.sync_api import sync_playwright

F = {
  "esx_mgmt_vlan":"#clr-form-control-24", "esx_mgmt_gw":"#clr-form-control-25",
  "vm_mgmt_vlan":"#clr-form-control-35",  "vm_mgmt_gw":"#clr-form-control-36",
  "pool_mgmt":"#ip-pool-1-textarea",      "pool_vcfa":"#ip-pool-2-textarea",
  "vmot_vlan":"#clr-form-control-42","vmot_mtu":"#clr-form-control-43","vmot_gw":"#clr-form-control-44",
  "vmot_from":"#clr-form-control-45","vmot_to":"#clr-form-control-46",
  "vsan_vlan":"#clr-form-control-37","vsan_mtu":"#clr-form-control-38","vsan_gw":"#clr-form-control-39",
  "vsan_from":"#clr-form-control-40","vsan_to":"#clr-form-control-41",
  "nsx_vlan":"#clr-form-control-47","nsx_gw":"#clr-form-control-48",
  "nsx_from":"#clr-form-control-51","nsx_to":"#clr-form-control-52",
}
V = {
  "esx_mgmt_vlan":"0","esx_mgmt_gw":"10.0.0.1/23",
  "vm_mgmt_vlan":"0","vm_mgmt_gw":"10.0.0.1/23",
  "pool_mgmt":"10.0.1.80 - 10.0.1.95",
  "pool_vcfa":"10.0.1.96 - 10.0.1.102",
  "vmot_vlan":"0","vmot_mtu":"9000","vmot_gw":"192.168.35.1/24",
  "vmot_from":"192.168.35.11","vmot_to":"192.168.35.20",
  "vsan_vlan":"0","vsan_mtu":"9000","vsan_gw":"192.168.36.1/24",
  "vsan_from":"192.168.36.11","vsan_to":"192.168.36.20",
  "nsx_vlan":"0","nsx_gw":"192.168.37.1/24",
  "nsx_from":"192.168.37.11","nsx_to":"192.168.37.30",
}
with sync_playwright() as p:
    b=p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg=[x for c in b.contexts for x in c.pages if "vcf-m03-inst01" in x.url][0]
    pg.set_default_timeout(30000)
    for k,sel in F.items():
        pg.locator(sel).fill(V[k]); time.sleep(0.25)
    time.sleep(2)
    print(pg.evaluate("""() => [...document.querySelectorAll('input,textarea')].filter(e=>e.offsetParent).map(e=>{
       const l=document.querySelector('label[for="'+e.id+'"]');
       return (e.id+'  '+((l&&l.innerText||'').trim().slice(0,28))+' = '+(e.type==='radio'||e.type==='checkbox'?e.checked:e.value));}).join(String.fromCharCode(10))"""))
    pg.screenshot(path="E:/9.1/doc-shots/m03-ops/57-prepare-networks.png")
