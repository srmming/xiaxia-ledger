"""逐帧动画片段：把 forge 做的动作帧（透明 PNG）整理成 app 用的样子，放进 Resources/Mascot/clips/<名字>/。

用法：python3 design/mascot/clips.py <名字> <帧目录> <参照图 key> [每帧毫秒,逗号分隔]
  名字：<样子前缀>-<动作>，比如 xiaxia-hello、xiaxia-celebrate（女孩版的「接金币」当庆祝用）。
  帧目录：按文件名排序的 PNG；目录上一层有 info.json 的话从里面读 frame_ms，否则用命令行给的。
  参照图：同一个样子的单张图（比如 xiaxia-idle），第一帧会缩放、对齐到它的身形（同样高、脚底同一条线、左右居中），
         换成动画时人不会一下变大变小。后面的帧用同一个缩放和位移，所以动作本身的起落不变。

输出 01.webp…（640×640，和单张图一样大）和 clip.json（frame_ms）。只用本机文件，不联网。
"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MASCOT = os.path.join(ROOT, "Sources/LedgerUI/Resources/Mascot")
SIZE = 640

def bbox(im):
    """身形的框。头顶上飘的金币、星星只占很窄一条，不算（从「这一行有 8% 宽是实心的」算起）。"""
    a = np.array(im)[:, :, 3] > 40
    rows = np.where(a.sum(axis=1) > a.shape[1] * 0.08)[0]
    body = a[rows[0]: rows[-1] + 1]
    ys, xs = np.where(body)
    return xs.min(), rows[0], xs.max(), rows[-1]

def main(name, frames_dir, ref_key, ms_arg=None):
    files = sorted(f for f in os.listdir(frames_dir) if f.lower().endswith(".png"))
    info = os.path.join(os.path.dirname(frames_dir.rstrip("/")), "info.json")
    ms = json.load(open(info))["frame_ms"] if os.path.exists(info) else [int(x) for x in ms_arg.split(",")]
    assert len(ms) == len(files), f"{len(files)} 帧但有 {len(ms)} 个时长"
    ref = Image.open(os.path.join(MASCOT, ref_key + ".webp")).convert("RGBA").resize((SIZE, SIZE))
    rx0, ry0, rx1, ry1 = bbox(ref)
    first = Image.open(os.path.join(frames_dir, files[0])).convert("RGBA")
    fx0, fy0, fx1, fy1 = bbox(first)
    k = (ry1 - ry0) / (fy1 - fy0)
    dx = (rx0 + rx1) / 2 - (fx0 + fx1) / 2 * k
    dy = ry1 - fy1 * k
    out = os.path.join(MASCOT, "clips", name)
    os.makedirs(out, exist_ok=True)
    for i, f in enumerate(files):
        im = Image.open(os.path.join(frames_dir, f)).convert("RGBA")
        im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.alpha_composite(im, (round(dx), round(dy))) if dx >= 0 and dy >= 0 else canvas.paste(im, (round(dx), round(dy)), im)
        a = np.array(canvas)
        a[a[:, :, 3] < 20] = 0          # 去掉边上几乎透明的杂点
        Image.fromarray(a).save(os.path.join(out, f"{i + 1:02d}.webp"), "WEBP", quality=86, method=6)
    json.dump({"frame_ms": ms, "from": os.path.basename(frames_dir.rstrip("/"))}, open(os.path.join(out, "clip.json"), "w"), ensure_ascii=False)
    print(name, len(files), "帧", sum(ms), "ms", f"缩放 {k:.2f}")

if __name__ == "__main__":
    main(*sys.argv[1:])
