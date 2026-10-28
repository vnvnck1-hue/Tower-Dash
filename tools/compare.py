"""Render comparison: side-by-side image + numeric stats against the reference."""
import os, sys, glob
from PIL import Image
import numpy as np
os.chdir(os.path.join(os.path.dirname(__file__), ".."))
shot = next((x for x in sys.argv[1:] if not x.startswith("--")), "screenshots/final.png")
ref = Image.open("reference/ref.webp").convert("RGB")
out = Image.open(shot).convert("RGB").resize(ref.size)
sb = Image.new("RGB", (ref.width * 2 + 16, ref.height)); sb.paste(ref, (0, 0)); sb.paste(out, (ref.width + 16, 0))
sb.save("screenshots/compare_side_by_side.png")
a = np.asarray(ref).astype(int); b = np.asarray(out).astype(int)
hx = lambda c: "#%02x%02x%02x" % tuple(int(v) for v in c)
print("overall mean ref", hx(a.reshape(-1, 3).mean(0)), "ours", hx(b.reshape(-1, 3).mean(0)))
la = a.mean(2); lb = b.mean(2)
print("ink(<16) share ref %.0f%% ours %.0f%%" % ((la < 16).mean() * 100, (lb < 16).mean() * 100))
print("lum hist ref ", [int(h * 100 / la.size) for h in np.histogram(la, bins=8, range=(0, 256))[0]])
print("lum hist ours", [int(h * 100 / lb.size) for h in np.histogram(lb, bins=8, range=(0, 256))[0]])
# hue/sat of the mid-tones (stone colour fidelity)
def hsv_stats(x, lo=40, hi=140):
    l = x.mean(2); sel = x[(l > lo) & (l < hi)]
    m = sel.mean(0); r, g, bl = m
    return hx(m)
print("mid-tone stone mean ref", hsv_stats(a), "ours", hsv_stats(b))
if "--wrap" in sys.argv:
    w = np.asarray(Image.open("screenshots/final_wrap.png").convert("RGB")).astype(int)
    f = np.asarray(Image.open("screenshots/final.png").convert("RGB")).astype(int)
    print("wrap seam: pixels differing >24: %.2f%%" % ((np.abs(w - f).max(2) > 24).mean() * 100))
if "--gif" in sys.argv:
    frames = [Image.open(x).convert("RGB").resize((768, 512)) for x in sorted(glob.glob("screenshots/seq/frame_*.png"))]
    frames[0].save("screenshots/climb_loop.gif", save_all=True, append_images=frames[1:], duration=200, loop=0)
    print("gif frames", len(frames))
