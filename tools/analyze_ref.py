import sys
from PIL import Image
import numpy as np
im = Image.open(sys.argv[1]).convert("RGB")
a = np.asarray(im).astype(int)
H, W, _ = a.shape
print("size", W, H)
def hx(c): return "#%02x%02x%02x" % tuple(int(v) for v in c)
def region(name, x0, y0, x1, y1):
    r = a[y0:y1, x0:x1].reshape(-1, 3)
    med = np.median(r, axis=0); mean = r.mean(axis=0)
    print(f"{name:28s} med {hx(med)} mean {hx(mean)} lum {r.mean():.0f}")
# sky visible through windows
region("sky_top_window_right", 1140, 220, 1180, 300)
region("sky_bottom_window_right", 1130, 800, 1180, 880)
region("sky_left_window_top", 320, 120, 380, 200)
region("sky_left_window_mid", 320, 330, 380, 400)
region("sky_bottom_left", 170, 600, 230, 680)
region("spire_silhouette", 330, 290, 370, 360)
region("tower_lit_right", 900, 150, 1000, 300)
region("tower_mid", 650, 200, 800, 380)
region("tower_dark_left", 400, 150, 480, 300)
region("tower_grime", 560, 120, 640, 220)
region("tower_bottom", 600, 700, 800, 900)
region("stair_tread_front", 560, 630, 640, 660)
region("stair_riser", 700, 560, 760, 620)
region("stair_snow", 300, 790, 400, 820)
region("outer_wall_left", 40, 400, 120, 520)
region("outer_wall_right", 1300, 450, 1400, 560)
region("pillar_under_stair", 1000, 760, 1040, 1000)
region("arch_bottom_dark", 300, 920, 500, 1010)
region("chandelier", 1280, 650, 1440, 700)
region("bell", 120, 120, 200, 200)
region("cape_red", 950, 340, 1000, 390)
# global dominant colors via k-means-ish quantization
q = im.quantize(colors=12, method=Image.Quantize.MEDIANCUT)
pal = q.getpalette()[:36]
counts = sorted(q.getcolors(), reverse=True)
print("dominant colors:")
for cnt, idx in counts:
    print(f"  {hx(pal[idx*3:idx*3+3])} {cnt*100/(W*H):.1f}%")
# luminance histogram -> check two-tone split
lum = a.mean(axis=2)
hist, edges = np.histogram(lum, bins=16, range=(0,256))
print("lum hist:", [int(h*100/lum.size) for h in hist])
