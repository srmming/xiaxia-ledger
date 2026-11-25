#!/usr/bin/env python3
"""挑样子设计稿：把 template.html 的占位换成内嵌图片，生成 ../pick-look.html（单文件，离线能开）。
用法：python3 design/mockups/pick-look/build.py <宠物样稿目录> <7 样同框图.png>"""
import base64, io, json, os, re, sys
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, "../../.."))
sys.path.insert(0, os.path.join(root, "design/mascot"))
from build import face
pets, seven = sys.argv[1], sys.argv[2]
M = os.path.join(root, "Sources/LedgerUI/Resources/Mascot")
LOOKS = [("girl", "女孩", f"{M}/xiaxia-idle.webp", "skin", f"{M}/xiaxia-hello.webp"),
         ("boy", "男孩", f"{M}/xiaxia-boy-idle.webp", "skin", None),
         ("woman", "成年女", f"{M}/xiaxia-woman-idle.webp", "top", None),
         ("man", "成年男", f"{M}/xiaxia-man-idle.webp", "top", None),
         ("cat", "金渐层猫", f"{pets}/cat-idle.png", "alpha", f"{pets}/cat-celebrate.png"),
         ("westie", "西高地白㹴", f"{pets}/westie-idle.png", "alpha", None),
         ("capy", "水豚", f"{pets}/capy-idle.png", "alpha", None)]

def uri(im, size=None, fmt="WEBP"):
    if size: im = im.resize(size)
    b = io.BytesIO(); im.save(b, fmt, quality=85)
    return f"data:image/{fmt.lower()};base64," + base64.b64encode(b.getvalue()).decode()

faces, full = {}, {}
for k, _, p, how, act in LOOKS:
    im = Image.open(p).convert("RGBA"); fx, fy, fs = face(im, how); w = im.width
    faces[k] = uri(im.crop((int((fx - fs/2)*w), int((fy - fs/2)*w), int((fx + fs/2)*w), int((fy + fs/2)*w))), (160, 160))
    full[k] = uri(im, (440, 440))
    if act: full[k + "-act"] = uri(Image.open(act).convert("RGBA"), (440, 440))

def picks(sel):
    out = []
    for k, n, *_ in LOOKS:
        new = '<span class="new">新</span>' if k in ("cat", "westie", "capy") else ""
        out.append(f'<div class="pick{" on" if k == sel else ""}">{new}<div class="av{" on" if k == sel else ""}"><img src="{faces[k]}"></div>{n}</div>')
    return "".join(out)

def tiles(sel):
    out = []
    for k, n, *_ in LOOKS:
        new = '<span class="new">新</span>' if k in ("cat", "westie", "capy") else ""
        out.append(f'<div class="tile{" on" if k == sel else ""}">{new}<div class="av"><img src="{faces[k]}"></div>{n}</div>')
    return "".join(out)

html = open(os.path.join(here, "template.html")).read()
html = re.sub(r"\{\{picks:(\w+)\}\}", lambda m: picks(m.group(1)), html)
html = re.sub(r"\{\{tiles:(\w+)\}\}", lambda m: tiles(m.group(1)), html)
html = re.sub(r"\{\{face:(\w+)\}\}", lambda m: faces[m.group(1)], html)
html = re.sub(r"\{\{full:([\w-]+)\}\}", lambda m: full[m.group(1)], html)
html = html.replace("{{img:pets}}", f'<img src="{uri(Image.open(os.path.join(pets, "overview.png")).convert("RGB"), (1000, 1000), "JPEG")}">')
s = Image.open(seven).convert("RGB")
html = html.replace("{{img:seven}}", f'<img src="{uri(s, (1600, int(1600 * s.height / s.width)), "JPEG")}">')
out = os.path.join(here, "..", "pick-look.html")
open(out, "w").write(html)
print(os.path.abspath(out), os.path.getsize(out) // 1024, "KB")
