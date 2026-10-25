"""Installer tab helper (10.0.1.155).
   python inst.py shot <out.png>                -> screenshot + list visible buttons/links
   python inst.py click "<regex>" <out.png>     -> real mouse click on last visible match, then shot
   python inst.py file <out.png> <path>         -> set first input[type=file]"""
import sys, re
from playwright.sync_api import sync_playwright
mode = sys.argv[1]
with sync_playwright() as p:
    b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg = [x for c in b.contexts for x in c.pages if "10.0.1.155" in x.url][0]
    pg.bring_to_front()
    if mode == "click":
        pat = re.compile(sys.argv[2], re.I); out = sys.argv[3]; hit = None
        for el in pg.query_selector_all("button,a,[role=button],[role=tab],clr-radio-wrapper label,label"):
            t = (el.inner_text() or "").strip()
            if t and pat.fullmatch(t) and el.is_visible() and el.is_enabled(): hit = (el, t)
        if not hit: print("NOT_FOUND"); out = out.replace(".png", "-NOTFOUND.png")
        else:
            el = hit[0]; el.scroll_into_view_if_needed(); pg.wait_for_timeout(600); bb = el.bounding_box()
            pg.mouse.click(bb["x"] + bb["width"] / 2, bb["y"] + bb["height"] / 2); print("CLICKED", hit[1])
        pg.wait_for_timeout(5000)
    elif mode == "file":
        out = sys.argv[2]; pg.set_input_files("input[type=file]", sys.argv[3]); pg.wait_for_timeout(4000); print("FILE SET")
    else:
        out = sys.argv[2]
    pg.screenshot(path=out); print("URL", pg.url)
    seen = []
    for el in pg.query_selector_all("button,a,[role=tab]"):
        try:
            t = (el.inner_text() or "").strip().replace("\n", " ")
            if t and el.is_visible() and t not in seen: seen.append(t + ("" if el.is_enabled() else "(disabled)"))
        except Exception: pass
    print("BTNS", seen[:40])
