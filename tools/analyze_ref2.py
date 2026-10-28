import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int)
def hx(c): return "#%02x%02x%02x" % tuple(int(v) for v in c)
def bright(name, x0,y0,x1,y1, pct=85):
    r = a[y0:y1, x0:x1].reshape(-1,3); l = r.mean(axis=1)
    sel = r[l >= np.percentile(l, pct)]
    print(f"{name:26s} top{100-pct}% med {hx(np.median(sel,axis=0))}  n={len(sel)}")
def dark(name, x0,y0,x1,y1, pct=15):
    r = a[y0:y1, x0:x1].reshape(-1,3); l = r.mean(axis=1)
    sel = r[l <= np.percentile(l, pct)]
    print(f"{name:26s} low{pct}% med {hx(np.median(sel,axis=0))}")
bright("sky pink right-top", 1120, 200, 1200, 330)
bright("sky pink right-low", 1120, 780, 1200, 900)
bright("sky purple top-left", 300, 60, 400, 150)
bright("sky left mid", 300, 300, 400, 420)
bright("sky far left low", 160, 560, 230, 680)
bright("sky top right corner", 1440, 20, 1520, 120)
bright("sky far right low", 1150, 930, 1190, 1000)
bright("spire lit", 330, 250, 380, 330, 70)
bright("stair tread lit", 520, 600, 700, 700, 90)
bright("snow highlight", 280, 780, 420, 830, 92)
bright("snow highlight2", 560, 640, 700, 690, 95)
bright("tower lit stone", 880, 120, 1000, 320, 80)
bright("tower lit stone2", 900, 500, 1000, 650, 80)
bright("outer wall right lit", 1300, 400, 1420, 600, 85)
bright("outer wall left lit", 20, 380, 130, 520, 85)
bright("pillar lit", 1000, 760, 1040, 980, 85)
bright("step edge light (top-right)", 1080, 460, 1260, 530, 90)
bright("red cape", 940, 320, 1010, 400, 90)
bright("red scarf", 310, 590, 400, 640, 90)
bright("bell lit", 110, 100, 210, 210, 85)
bright("chain lit", 1320, 100, 1350, 500, 90)
bright("railing lit", 70, 290, 320, 320, 85)
dark("tower shadow", 650, 200, 800, 380)
dark("tread shadow", 520, 600, 700, 700, 30)
dark("riser", 700, 560, 760, 620, 50)
dark("mortar", 880, 120, 1000, 320, 10)
