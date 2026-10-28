# -*- coding: utf-8 -*-
"""Build pose_review.html: every key pose of every runner clip (captured with
`-- --poses=screenshots/poses`) laid out in order, with a comment box and a sketch
overlay per key so the review can be exported as JSON (pose_feedback.json)."""
import base64, io, json, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "screenshots", "poses")
OUT = os.path.join(ROOT, "pose_review.html")
W = 960  # embedded image width

ORDER = ["run", "jump", "jump2", "dash", "attack", "attack2", "attack3", "air_attack", "slam", "drop", "hang", "recover", "hurt", "fall"]
META = {
    "run": ("달리기", "루프. 큰 보폭 + 강한 전경. 속도에 따라 컨트롤러가 전경을 더 얹음"),
    "jump": ("점프", "웅크림 → 스트레치 → 긴 체공 → 낙하 → 착지"),
    "jump2": ("2단 점프", "현재 높이에서 앞으로 턱 플립"),
    "dash": ("대시", "즉시 앞으로 도약하는 카툰 포즈, 매우 짧음"),
    "attack": ("공격 1", "수평 베기 + 짧은 런지"),
    "attack2": ("공격 2", "앞으로 밀고 나가는 내려찍기"),
    "attack3": ("공격 3", "앞으로 깡총 뛰며 올려베기"),
    "air_attack": ("공중 공격", "현재 높이에서 전방 베기 (급강하 없음), 이후 drop"),
    "slam": ("슬램", "뛰어올라 앞으로 회전, 대검을 계단에 내리꽂기 (공중에서 아래+공격)"),
    "drop": ("낙하", "공중 동작 후 현재 높이에서 내려와 착지, 복귀"),
    "hang": ("매달리기", "루프. 계단을 놓쳤을 때 손으로 가장자리에 매달림"),
    "recover": ("복귀", "끌어올려 높이 뒤로 도약, 체공, 달리며 착지"),
    "hurt": ("피격", "뒤로 밀리며 팔 벌어짐, 다시 바로 섬"),
    "fall": ("추락", "아래로 떨어짐 (게임 오버 연출)"),
}

manifest = json.load(open(os.path.join(SRC, "poses.json"), encoding="utf-8"))
clips = {}
for m in manifest:
    clips.setdefault(m["clip"], []).append(m)
for k in clips:
    clips[k].sort(key=lambda m: m["index"])
order = [c for c in ORDER if c in clips] + [c for c in clips if c not in ORDER]


def b64(path):
    im = Image.open(path).convert("RGB")
    h = round(im.height * W / im.width)
    im = im.resize((W, h), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode(), h


data = []
img_h = None
for c in order:
    keys = []
    for m in clips[c]:
        src, img_h = b64(os.path.join(SRC, m["file"]))
        keys.append({"i": m["index"], "t": m["time"], "src": src})
    ko, desc = META.get(c, (c, ""))
    data.append({"id": c, "name": ko, "desc": desc, "len": clips[c][0]["len"], "keys": keys})

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pose_review_template.html")
html = open(TEMPLATE, encoding="utf-8").read()
import time
html = html.replace("__DATA__", json.dumps(data, ensure_ascii=False)).replace("__IMGH__", str(img_h)).replace("__STAMP__", time.strftime("%Y%m%d_%H%M"))
open(OUT, "w", encoding="utf-8").write(html)
print("wrote", OUT, round(os.path.getsize(OUT) / 1e6, 2), "MB,", sum(len(c["keys"]) for c in data), "keys,", len(data), "clips")
