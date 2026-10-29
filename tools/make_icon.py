# -*- coding: utf-8 -*-
"""Draws the game icon (dusk sky, dark tower with a spiral stair, hooded runner with a greatsword)
-> icon.png (512, project/boot icon) + icon.ico (16..256, embedded in the Windows exe)."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024  # supersampled canvas


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# dusk gradient (pink horizon -> violet top), rounded square
sky = Image.new("RGBA", (S, S))
sd = ImageDraw.Draw(sky)
top, mid, low = (38, 30, 78), (120, 64, 128), (236, 140, 150)
for y in range(S):
    t = y / S
    c = lerp(top, mid, t / 0.6) if t < 0.6 else lerp(mid, low, (t - 0.6) / 0.4)
    sd.line([(0, y), (S, y)], fill=c + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=200, fill=255)
img.paste(sky, (0, 0), mask)
d = ImageDraw.Draw(img)

ink = (16, 14, 34, 255)
# tower: dark column with lit right edge, gothic window, spiral stair bands
tx0, tx1 = 300, 724
d.rectangle([tx0, 130, tx1, S], fill=(44, 40, 82, 255))
d.rectangle([tx1 - 70, 130, tx1, S], fill=(72, 66, 120, 255))
d.rectangle([tx0 - 20, 100, tx1 + 20, 150], fill=ink)               # parapet
for x in range(tx0 - 20, tx1 + 20, 74):
    d.rectangle([x, 60, x + 40, 110], fill=ink)                       # crenels
d.ellipse([470, 230, 560, 320], fill=(255, 196, 120, 255))            # window arch
d.rectangle([470, 275, 560, 380], fill=(255, 196, 120, 255))
# one stair band under the runner's feet (rising to the right, like the climb)
d.polygon([(0, 990), (S, 800), (S, 880), (0, 1070)], fill=ink)
d.polygon([(0, 990), (S, 800), (S, 826), (0, 1016)], fill=(200, 196, 230, 255))

# runner: diagonal drive pose, red hood, greatsword trailing back
red, red_d, navy, skin, steel = (170, 60, 66, 255), (90, 30, 40, 255), (30, 36, 70, 255), (214, 160, 128, 255), (190, 204, 222, 255)
def quad(pts, fill, w=16):
    d.polygon(pts, fill=fill, outline=ink, width=w)
# greatsword (behind body), trailing back-up from the hand
quad([(70, 250), (140, 190), (600, 520), (540, 590)], steel)
quad([(70, 250), (40, 200), (140, 190)], steel)                                 # tip
d.line([(140, 240), (530, 520)], fill=(50, 58, 74, 255), width=30)            # fuller
quad([(500, 470), (580, 410), (660, 580), (590, 630)], (120, 130, 150, 255))   # guard
# back leg (straight), front leg (knee up)
quad([(470, 700), (520, 660), (360, 900), (310, 890)], navy)
quad([(290, 870), (380, 890), (370, 940), (270, 930)], red_d)
quad([(560, 690), (620, 700), (720, 700), (720, 760), (600, 770)], navy)
quad([(690, 700), (750, 700), (760, 860), (700, 870)], navy)
quad([(690, 860), (790, 850), (800, 900), (690, 910)], red_d)
# torso leaning forward + cape streaming back
quad([(520, 470), (300, 420), (330, 520), (500, 560)], red)
quad([(480, 470), (640, 420), (700, 560), (560, 720), (470, 690)], navy)
# arms: front fist up, back arm high
quad([(640, 470), (760, 560), (730, 600), (620, 520)], navy)
quad([(740, 540), (800, 470), (840, 500), (770, 580)], skin)
quad([(540, 460), (440, 330), (480, 300), (590, 440)], navy)
# head + hood
quad([(600, 300), (760, 280), (790, 440), (630, 460)], skin)
quad([(580, 260), (770, 230), (800, 300), (750, 300), (620, 330), (590, 420), (540, 400)], red)
d.rectangle([720, 350, 745, 380], fill=ink)                            # eye

img = img.resize((512, 512), Image.LANCZOS)
img.save(os.path.join(ROOT, "icon.png"))
img.save(os.path.join(ROOT, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("icon.png / icon.ico written")
