"""Check motion of the actual white silhouette, not animated color inside a static clip."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAP = ROOT / "screenshots/outline_v3_review"
NAMES = ["Blade Flow", "Layered Surge", "Ripped Torrent"]
grid = np.asarray(json.loads((CAP / "ring_grid.json").read_text()))
report = {}


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def white_mask(a):
    return a.min(axis=2) > 165


def energy_mask(a):
    r, g, b = a.transpose(2, 0, 1)
    return (g > 105) & (b > 90) & (g > r * 1.14)


def arc_center(array):
    h, w = array.shape[:2]
    xy = np.rint(grid).astype(int)
    x, y = xy[..., 0].clip(0, w - 1), xy[..., 1].clip(0, h - 1)
    brightness = array[y, x].min(axis=2)
    mass = (brightness > 165).sum(axis=1)
    angle = np.arange(len(mass)) * 2 * np.pi / len(mass)
    return np.angle((mass * np.exp(1j * angle)).sum())


for preset, name in enumerate(NAMES):
    a = load(CAP / f"p{preset}_silhouette_00.png")
    b = load(CAP / f"p{preset}_silhouette_01.png")
    ma, mb = white_mask(a), white_mask(b)
    motion = float((ma ^ mb).sum() / (ma | mb).sum())
    degrees = float(np.degrees(np.angle(np.exp(1j * (arc_center(b) - arc_center(a))))))
    assert motion > .22, (name, "Outline has remained static", motion)
    assert degrees > 9, (name, "Outline did not advance with sword sweep", degrees)
    stopped_a = load(CAP / f"p{preset}_stopped_00.png")
    stopped_b = load(CAP / f"p{preset}_stopped_01.png")
    stopped_motion = int((white_mask(stopped_a) ^ white_mask(stopped_b)).sum())
    assert stopped_motion <= 5, (name, "Outline ignores the attack clock", stopped_motion)
    counts = [int(energy_mask(load(CAP / f"p{preset}_life_{i:02}.png")).sum()) for i in range(15)]
    assert counts[0] == counts[-1] == 0, (name, "Endpoints are visible", counts)
    assert max(counts) > 20000, (name, "Missing blade volume", counts)
    for attack in ("attack2", "attack3", "air_attack", "slam"):
        assert energy_mask(load(CAP / f"p{preset}_{attack}.png")).sum() > 10000
    report[name] = {"white_silhouette_changed_fraction_40ms": round(motion, 3),
                    "outline_advance_degrees_40ms": round(degrees, 1),
                    "zero_speed_changed_pixels": stopped_motion,
                    "life_coverage": counts}
(CAP / "outline_verification.json").write_text(json.dumps(report, indent=2))

FONT = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 21)
SMALL = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)


def frame(kind, i, caption):
    out = Image.new("RGB", (1260, 480), "#25272b")
    draw = ImageDraw.Draw(out)
    for p, name in enumerate(NAMES):
        im = Image.open(CAP / f"p{p}_{kind}_{i:02}.png").convert("RGB")
        im = im.crop((80, 35, 1060, 880))
        im.thumbnail((416, 416), Image.Resampling.LANCZOS)
        out.paste(im, (p * 420 + 2, 40 + (416 - im.height) // 2))
        draw.text((p * 420 + 16, 10), f"{p + 1}. {name}", font=FONT, fill="#a5fff0")
    draw.text((12, 457), caption, font=SMALL, fill="#cccccc")
    return out


for kind, count, filename, duration, caption in [
    ("life", 15, "presets_slow.gif", 60, "Actual 0.19 s attack - slow replay; the exterior travels with the blade"),
    ("flow", 10, "outline_motion.gif", 55, "Lifetime held fixed - the pointed oval OUTLINES travel along the arc"),
    ("silhouette", 3, "white_silhouette.gif", 180, "All shading replaced with white - actual silhouette transport, no color animation"),
]:
    frames = [frame(kind, i, caption) for i in range(count)]
    frames[0].save(CAP / filename, save_all=True, append_images=frames[1:], duration=duration, loop=0)
frame("flow", 4, "Curved pointed ovals with dark inner volume and a pale outer face").save(CAP / "presets.jpg", quality=94)
print(json.dumps(report))
print("PASS: actual silhouettes advance along the arc; zero speed freezes outlines; all presets/attacks render and end transparent.")
