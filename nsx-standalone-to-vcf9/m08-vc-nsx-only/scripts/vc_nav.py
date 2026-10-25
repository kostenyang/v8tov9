"""Go to a vCenter object URL, then click a sequence of visible text labels, then screenshot.
   python vc_nav.py <url> <out.png> "Configure" "VMkernel adapters" ..."""
import sys, re
from playwright.sync_api import sync_playwright
url, out, labels = sys.argv[1], sys.argv[2], sys.argv[3:]
with sync_playwright() as p:
    b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg = [x for c in b.contexts for x in c.pages if "10.0.1.144/ui" in x.url][0]
    pg.bring_to_front(); pg.goto(url); pg.wait_for_timeout(7000)
    for lab in labels:
        loc = pg.get_by_text(re.compile(r"^\s*" + re.escape(lab) + r"\s*$")).locator("visible=true").first
        loc.scroll_into_view_if_needed(); bb = loc.bounding_box()
        pg.mouse.click(bb["x"] + bb["width"] / 2, bb["y"] + bb["height"] / 2); pg.wait_for_timeout(4000)
    pg.wait_for_timeout(2000); pg.screenshot(path=out); print(pg.url[:140])
