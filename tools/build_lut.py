"""Build a per-channel colour-grading LUT (256x1 RGB) that maps the ungraded render's
channel histograms onto the reference image's, i.e. histogram matching. Baked into
textures/grade_lut.png and applied by the post-process shader in main.gd.

Usage: python -I tools/build_lut.py [ungraded_render.png]
"""
import os, sys
from PIL import Image
import numpy as np
os.chdir(os.path.join(os.path.dirname(__file__), ".."))
src = sys.argv[1] if len(sys.argv) > 1 else "screenshots/ungraded.png"
ref = np.asarray(Image.open("reference/ref.webp").convert("RGB"))
out = np.asarray(Image.open(src).convert("RGB").resize((ref.shape[1], ref.shape[0])))
# grade only "stone" pixels (blue-grey: g > r); sky / windows keep their painted palette
m_ref = ref[..., 1].astype(int) > ref[..., 0].astype(int)
m_out = out[..., 1].astype(int) > out[..., 0].astype(int)
ref_s = ref[m_ref]; out_s = out[m_out]
print("stone pixel share ref %.0f%% render %.0f%%" % (m_ref.mean() * 100, m_out.mean() * 100))
lut = np.zeros((1, 256, 3), dtype=np.uint8)
for c in range(3):
    h_src = np.bincount(out_s[:, c].ravel(), minlength=256).astype(float)
    h_ref = np.bincount(ref_s[:, c].ravel(), minlength=256).astype(float)
    cdf_src = np.cumsum(h_src) / h_src.sum()
    cdf_ref = np.cumsum(h_ref) / h_ref.sum()
    # for every source value find the reference value with the same cumulative share
    mapping = np.interp(cdf_src, cdf_ref, np.arange(256))
    # keep the mapping monotone and smooth a little to avoid banding
    mapping = np.maximum.accumulate(mapping)
    k = np.ones(5) / 5.0
    sm = np.convolve(np.pad(mapping, 2, mode="edge"), k, mode="valid")
    lut[0, :, c] = np.clip(sm, 0, 255).astype(np.uint8)
Image.fromarray(lut, "RGB").save("textures/grade_lut.png")
print("saved textures/grade_lut.png; sample mapping (in->out) at 0,32,64,128,192,255:")
for v in (0, 32, 64, 128, 192, 255):
    print(f"  {v:3d} -> {tuple(int(x) for x in lut[0, v])}")
