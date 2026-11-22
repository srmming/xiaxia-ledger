"""夏夏和三个 AI 伙伴的形象：把 ChatGPT 生成的原图（raw/，不进仓库，原图在项目文件夹 mascot/raw）
缩成 app 用的透明 WebP，并算出每张图里脸的位置（头像要用），写进 Sources/LedgerUI/MascotData.swift。

用法：python3 design/mascot/build.py <raw 目录>
眨眼 / 说话帧要先用 patch.py 把原图的眼睛 / 嘴巴贴回定稿图上（见 README.md），放在 raw/ 里叫 *-blink.png / *-talk.png。
"""
import sys, os, json
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "Sources/LedgerUI/Resources/Mascot")
SIZE = 640
# 自动找脸找错时手动指定（比如庆祝图里粉色存钱罐会被当成脸）
OVERRIDES = {"xiaxia-celebrate": (0.455, 0.37, 0.4)}

def face(im):
    """脸在图里的位置：亮肤色像素最集中的地方。返回 (中心 x, 中心 y, 边长)，都按图宽归一化。"""
    a = np.array(im)
    rgb = a[:, :, :3].astype(int); r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    skin = (a[:, :, 3] > 40) & (r > 215) & (g > 170) & (b > 150) & (r >= g) & (g >= b - 10) & (r - b > 15) & (r - b < 90)
    H, W = skin.shape
    ys, xs = np.where(skin[: int(H * 0.62)])
    cx, cy = np.median(xs), np.median(ys)
    m = (abs(xs - cx) < W * 0.18) & (abs(ys - cy) < H * 0.16)
    cx, cy = xs[m].mean(), ys[m].mean()
    return round(cx / W, 3), round(cy / H - 0.02, 3), 0.4

def main(raw):
    os.makedirs(OUT, exist_ok=True)
    faces = {}
    for name in sorted(os.listdir(raw)):
        if not name.endswith(".png"):
            continue
        key = name[:-4]
        im = Image.open(os.path.join(raw, name)).convert("RGBA")
        # 眨眼 / 说话帧沿用定稿图的脸位置，免得头像跳
        base = key.rsplit("-", 1)[0] + "-idle"
        if not (key.endswith("-blink") or key.endswith("-talk")):
            faces[key] = OVERRIDES.get(key) or face(im)
        im.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, key + ".webp"), "WEBP", quality=88, method=6)
        print(key)
    lines = ["// 由 design/mascot/build.py 生成，别手改。每张形象图里脸的位置（中心 x、中心 y、边长，按图宽算）。",
             "import CoreGraphics", "", "enum MascotData {", "    static let faces: [String: (x: CGFloat, y: CGFloat, size: CGFloat)] = ["]
    for k, (x, y, s) in sorted(faces.items()):
        lines.append(f'        "{k}": ({x}, {y}, {s}),')
    lines += ["    ]", "}", ""]
    open(os.path.join(ROOT, "Sources/LedgerUI/MascotData.swift"), "w").write("\n".join(lines))

if __name__ == "__main__":
    main(sys.argv[1])
