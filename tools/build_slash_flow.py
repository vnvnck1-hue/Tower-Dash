"""Periodic geometric energy field: R=broad sheets, G=channels, B=fine needles.

The shader advects this tile in arc UV space; it is not an animation atlas.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
W, H, S = 1024, 256, 4
channels = [Image.new("L", (W * S, H * S)) for _ in range(3)]


def shape(channel, points, value=255):
    draw = ImageDraw.Draw(channels[channel])
    for wrap in (-1, 0, 1):
        for wrap_y in (-1, 0, 1):
            draw.polygon([((x + wrap) * W * S, (y + wrap_y) * H * S) for x, y in points], fill=value)


# Swept wedges: long pointed tails, bevelled heads, different widths and offsets.
for x, y, length, width in [(-.15, .14, .72, .11), (.28, .38, .62, .15),
                           (-.02, .65, .84, .13), (.49, .90, .57, .17)]:
    shape(0, [(x, y), (x + length * .62, y - width * .24),
              (x + length, y - width), (x + length * .84, y + width * .24),
              (x + length * .35, y + width * .42)])
for x, y, length, width in [(.06, .24, .64, .055), (.48, .52, .56, .085),
                           (-.24, .77, .75, .07), (.57, .99, .62, .05)]:
    shape(1, [(x, y), (x + length * .72, y - width),
              (x + length, y - width * .5), (x + length * .34, y + width * .3)])
for x, y, length, width in [(.31, .12, .39, .016), (-.18, .43, .58, .025),
                           (.16, .58, .52, .018), (.63, .73, .44, .025),
                           (-.12, .92, .65, .022)]:
    shape(2, [(x, y), (x + length * .88, y - width),
              (x + length, y - width * .3), (x + length * .30, y + width * .45)])
image = Image.merge("RGB", channels).resize((W, H), Image.Resampling.LANCZOS)
image.save(ROOT / "textures/slash_flow_field.png")
print("Authored periodic geometric flow field (RGB).")
