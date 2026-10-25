"""wait for a visible button (regex) in any frame of the vCenter tab, real-mouse click it, screenshot.
   python -I vc_click.py "<regex>" <timeout_s> <shot_name> [--noclick]"""
import io,sys,re,time
sys.stdout=io.TextIOWrapper(sys.stdout.buffer,encoding='utf-8')
from playwright.sync_api import sync_playwright
pat=re.compile(sys.argv[1],re.I); tmo=int(sys.argv[2]); shot=sys.argv[3]; noclick='--noclick' in sys.argv
D=r"E:/9.1/doc-shots/m08/"
with sync_playwright() as p:
    b=p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg=[x for c in b.contexts for x in c.pages if '10.0.1.144' in x.url][0]
    end=time.time()+tmo; hit=None
    while time.time()<end and not hit:
        for f in pg.frames:
            try:
                for el in f.query_selector_all("button,a[role=button],.btn"):
                    t=(el.inner_text() or '').strip()
                    if t and pat.fullmatch(t) and el.is_visible() and el.is_enabled():
                        hit=(el,t); break
            except Exception: pass
            if hit: break
        if not hit: time.sleep(5)
    if not hit:
        pg.screenshot(path=D+shot+"-NOTFOUND.png"); print("NOT FOUND within",tmo,"s"); sys.exit(2)
    el,t=hit
    pg.screenshot(path=D+shot+".png"); print("found:",t)
    if not noclick:
        el.scroll_into_view_if_needed(); pg.wait_for_timeout(800)
        bb=el.bounding_box()
        pg.mouse.click(bb['x']+bb['width']/2, bb['y']+bb['height']/2)
        print("clicked at",int(bb['x']+bb['width']/2),int(bb['y']+bb['height']/2))
        pg.wait_for_timeout(6000)
        pg.screenshot(path=D+shot+"-after.png")
