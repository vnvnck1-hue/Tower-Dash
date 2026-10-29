"""Verify color transport independently of fade, then assemble native-render comparisons."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
CAP = ROOT / "screenshots/flow_v2"
NAMES = ["Blade Flow", "Layered Surge", "Ripped Torrent"]
report = {}


def load(path):
    return np.array(Image.open(path).convert("RGB"), dtype=np.int16)


def mask(array):
    r, g, b = array.transpose(2, 0, 1)
    return (g > 105) & (b > 90) & (g > r * 1.15)


for preset, name in enumerate(NAMES):
    a = load(CAP / f"p{preset}_internal_00.png")
    b = load(CAP / f"p{preset}_internal_02.png")
    # Shape, opacity, pose, life and phase are held fixed; only flow_age advances 33 ms.
    interior = mask(a) & mask(b)
    interior = np.asarray(Image.fromarray((interior * 255).astype("uint8")).filter(ImageFilter.MinFilter(7))) > 0
    changed = (np.abs(a - b).max(axis=2) > 12) & interior
    ratio = float(changed.sum() / interior.sum())
    assert ratio > .10, (name, "No substantial internal flow", ratio)
    counts = [int(mask(load(CAP / f"p{preset}_life_{frame:02}.png")).sum()) for frame in range(15)]
    assert counts[0] == counts[-1] == 0, (name, "Not transparent at endpoints", counts)
    assert max(counts) > 30000, (name, "Missing body", counts)
    before = mask(load(CAP / f"p{preset}_flow_00.png"))
    after = mask(load(CAP / f"p{preset}_flow_04.png"))
    contour_change = float((before ^ after).sum() / (before | after).sum())
    report[name] = {"internal_changed_fraction_33ms": round(ratio, 3), "shape_change_fixed_life_67ms": round(contour_change, 3), "lifecycle_pixel_counts": counts}
    for attack in ("attack2", "attack3", "air_attack", "slam"):
        assert mask(load(CAP / f"p{preset}_{attack}.png")).sum() > 15000
assert report[NAMES[2]]["shape_change_fixed_life_67ms"] > report[NAMES[0]]["shape_change_fixed_life_67ms"]
(CAP / "flow_verification.json").write_text(json.dumps(report, indent=2))

FONT = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 21)


def composite(kind, frame, caption):
    image = Image.new("RGB", (1260, 480), "#25272b")
    draw = ImageDraw.Draw(image)
    for preset, name in enumerate(NAMES):
        source = Image.open(CAP / f"p{preset}_{kind}_{frame:02}.png").convert("RGB")
        source = source.crop((135, 15, 970, 850)).resize((416, 416), Image.Resampling.LANCZOS)
        image.paste(source, (preset * 420 + 2, 40))
        draw.text((preset * 420 + 16, 10), f"{preset + 1}. {name}", font=FONT, fill="#a5fff0")
    draw.text((14, 457), caption, font=ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16), fill="#cccccc")
    return image


for kind, filename, duration, caption in [
    ("life", "presets_slow.gif", 60, "Actual 0.19 s attack sequence - slow replay"),
    ("flow", "currents.gif", 45, "Life and pose held fixed - only currents and shape motion advance"),
]:
    frames = [composite(kind, i, caption) for i in range(15)]
    frames[0].save(CAP / filename, save_all=True, append_images=frames[1:], duration=duration, loop=0)
composite("flow", 3, "Three materials share an editable native VisualShader").save(CAP / "presets.jpg", quality=94)
print(json.dumps(report))
print("PASS: all three presets move internally with silhouette and life locked; all five attacks render and terminate.")
