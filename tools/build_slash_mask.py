"""Author the slash's UV-space cut-paper shapes; no baked color or animation.

R = pale edge, G = fine light streaks, A = silhouette. UV.y runs inner -> outer.
Run with Python + Pillow, then reimport in Godot.
"""
from pathlib import Path
from math import sin, pi
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
S = 4
W, H = 1024, 256
im = Image.new("RGBA", (W * S, H * S))
d = ImageDraw.Draw(im)


def poly(points, color):
    d.polygon([(round(x * W * S), round(y * H * S)) for x, y in points], fill=color)


def smooth(a, b, x):
    t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def outer(u):
    return .90 + .025 * sin(u * 9)


def width(u):
    return .88 * sin(pi * u) ** .62 * (.07 + .93 * smooth(.03, .68, u))


us = [i / 1024 for i in range(1025)]
poly([(u, outer(u)) for u in us] + [(u, outer(u) - width(u)) for u in reversed(us)], (0, 0, 0, 255))
# Broad, pale outside face. Its boundary sweeps with the blade, never a uniform outline.
poly([(u, outer(u)) for u in us] + [(u, outer(u) - width(u) * (.26 + .17 * smooth(.35, .9, u))) for u in reversed(us)], (255, 0, 0, 255))
# Long, directional cutouts. The points lean along the swing rather than making noisy teeth.
for shape in [
    [(.10, .96), (.14, .83), (.19, .80), (.15, .96)],
    [(.24, .96), (.275, .82), (.33, .77), (.285, .96)],
    [(.44, .96), (.465, .82), (.53, .76), (.475, .96)],
    [(.73, .96), (.75, .80), (.80, .74), (.765, .96)],
    [(.97, .97), (.935, .81), (.965, .78), (1, .80)],
    [(.33, .44), (.39, .66), (.46, .70), (.41, .60)],
    [(.58, .00), (.64, .33), (.69, .42), (.65, .06)],
    [(.79, .00), (.815, .27), (.86, .36), (.84, .00)],
    [(.90, .00), (.90, .35), (.95, .50), (.935, .00)],
]:
    poly(shape, (0, 0, 0, 0))
# Thin internal speed highlights, each tapering to an actual point.
for shape in [
    [(.49, .74), (.57, .68), (.69, .56), (.62, .66)],
    [(.69, .47), (.75, .44), (.83, .44), (.77, .48)],
    [(.84, .59), (.89, .61), (.945, .69), (.89, .64)],
]:
    poly(shape, (130, 255, 0, 255))
# Detached trailing needles.
poly([(.025, .74), (.07, .77), (.12, .83), (.075, .79)], (0, 0, 0, 235))
poly([(.14, .69), (.22, .71), (.32, .75), (.23, .74)], (0, 0, 0, 255))
path = ROOT / "textures" / "slash_cut_mask.png"
im.resize((W, H), Image.Resampling.LANCZOS).save(path)
print(path)
