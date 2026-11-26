#!/usr/bin/env python3
"""把 template.html 里的 {{img:名字}}、{{svg:路径}} 换成内嵌数据，生成 ../business-mode.html（单文件，离线能开）。
用法：python3 design/mockups/business-mode/build.py"""
import base64, pathlib, re
here = pathlib.Path(__file__).resolve().parent
root = here.parents[2]
mascot = root / "Sources/LedgerUI/Resources/Mascot"
icons = root / "design/icon-kit/svg"
samples = here / "img"   # 秘书形象样稿等额外图片（可选）

def img(name):
    for p in (samples / f"{name}.png", samples / f"{name}.webp", mascot / f"{name}.webp"):
        if p.exists():
            mime = "image/png" if p.suffix == ".png" else "image/webp"
            return f'<img alt="" src="data:{mime};base64,{base64.b64encode(p.read_bytes()).decode()}">'
    raise SystemExit(f"找不到图片 {name}")

def svg(path):
    s = (icons / f"{path}.svg").read_text()
    return re.sub(r"<\?xml[^>]*>", "", s)

html = (here / "template.html").read_text()
html = re.sub(r"\{\{img:([\w-]+)\}\}", lambda m: img(m.group(1)), html)
html = re.sub(r"\{\{svg:([\w/-]+)\}\}", lambda m: svg(m.group(1)), html)
out = here.parent / "business-mode.html"
out.write_text(html)
print(out, f"{out.stat().st_size // 1024} KB")
