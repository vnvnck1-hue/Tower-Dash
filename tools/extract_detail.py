"""Extract a tileable hand-drawn brick detail texture from the reference tower (lit face)."""
import os
from PIL import Image, ImageFilter
import numpy as np
os.chdir(os.path.join(os.path.dirname(__file__), ".."))
ref = Image.open("reference/ref.webp").convert("L")
patch = np.asarray(ref.crop((700, 90, 1000, 420))).astype(float)
blur = np.asarray(Image.fromarray(patch.astype(np.uint8)).filter(ImageFilter.GaussianBlur(40))).astype(float)
detail = patch / np.maximum(blur, 1.0)
H, W = detail.shape
r = np.roll(np.roll(detail, H // 2, 0), W // 2, 1)
yy, xx = np.mgrid[0:H, 0:W]
wgt = np.maximum(np.abs(yy - H / 2) / (H / 2), np.abs(xx - W / 2) / (W / 2)) ** 2
t = detail * (1 - wgt) + r * wgt
t = np.clip(t / t.mean(), 0, 2)
Image.fromarray((t * 127.5).clip(0, 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS).save("textures/brick_detail.png")
print("saved textures/brick_detail.png")
