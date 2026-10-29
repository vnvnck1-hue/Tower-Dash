"""Summarize actual Godot renders and assemble a compact visual review."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAP = ROOT / "screenshots" / "slash_final"
report = {}
for attack in ("attack", "attack2", "attack3", "air_attack", "slam"):
    counts = {}
    for life in (0, 5, 22, 46, 72, 94, 100):
        image = Image.open(CAP / f"{attack}_{life:02}.png").convert("RGB")
        counts[life] = sum(g > 105 and b > 90 and g > r * 1.22 for r, g, b in image.get_flattened_data())
    assert counts[0] == 0 and counts[100] == 0, (attack, counts)
    assert counts[22] > 8000, (attack, counts)
    assert counts[22] > counts[72] > counts[94] > counts[100], (attack, counts)
    report[attack] = counts
(CAP / "visibility_review.json").write_text(json.dumps(report, indent=2))

font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 19)
sheet = Image.new("RGB", (1320, 590), "#25272b")
draw = ImageDraw.Draw(sheet)
for col, life in enumerate((5, 22, 46, 72)):
    im = Image.open(CAP / f"attack_{life:02}.png").convert("RGB")
    im.thumbnail((330, 280))
    sheet.paste(im, (col * 330, 36))
    draw.text((col * 330 + 12, 10), f"Life {life / 100:.2f}", font=font, fill="white")
for col, filename in enumerate(("attack2_22.png", "attack3_22.png", "aim_up.png", "facing_left.png")):
    im = Image.open(CAP / filename).convert("RGB")
    im.thumbnail((330, 260))
    sheet.paste(im, (col * 330, 325))
    draw.text((col * 330 + 12, 300), filename.removesuffix(".png"), font=font, fill="white")
sheet.save(CAP / "review.jpg", quality=92)

game = ROOT / "screenshots" / "slash_game_final"
frames = []
for path in sorted(game.glob("frame_*.png")):
    im = Image.open(path).convert("RGB")
    # Crop the gameplay capture around the player without changing any visual content.
    im = im.crop((850, 230, 1850, 930))
    im.thumbnail((800, 560))
    frames.append(im)
if frames:
    frames[0].save(CAP / "gameplay.gif", save_all=True, append_images=frames[1:], duration=50, loop=0)
print(json.dumps(report))
print("PASS: 5 attacks visible at peak, diminishing tail, transparent at both endpoints.")
