#!/usr/bin/env python3
"""官网标题用的手写字体（霞鹜文楷 Medium，SIL OFL 开源字体）：只截页面标题里用到的字，存成 site/assets/fonts/xiaxia-hand.woff2。

  python3 scripts/site-font.py

什么时候跑：改了官网标题文字以后（scripts/changelog.py site 和 scripts/site-i18n.py 跑完会自己调用）。
哪些字：site/ 下所有页面里 <h1>–<h3> 和 class 带 hand 的元素里的字，加上英文字母、数字和常用标点。
需要：pip install fonttools brotli。原字体第一次用时从 GitHub 下载到 ~/Library/Caches/xiaxia-site/（约 25 MB，不进仓库）。
"""
import glob, html, os, re, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, "site")
OUT = os.path.join(SITE, "assets", "fonts", "xiaxia-hand.woff2")
URL = "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Medium.ttf"
CACHE = os.path.expanduser("~/Library/Caches/xiaxia-site/LXGWWenKai-Medium.ttf")
EXTRA = "".join(chr(c) for c in range(0x20, 0x7F)) + "，。、？！：；（）「」『』《》—…·→←’‘“”«»¿¡áéíóúñüÁÉÍÓÚÑÜ€ "


def chars():
    found = set(EXTRA)
    rx_tag = re.compile(r"<(h[1-3])\b[^>]*>(.*?)</\1>", re.S)
    rx_hand = re.compile(r'<(\w+)\b[^>]*class="[^"]*\bhand\b[^"]*"[^>]*>(.*?)</\1>', re.S)
    for path in glob.glob(os.path.join(SITE, "**", "*.html"), recursive=True):
        page = open(path, encoding="utf-8").read()
        for rx in (rx_tag, rx_hand):
            for m in rx.finditer(page):
                found |= set(html.unescape(re.sub(r"<[^>]+>", "", m.group(2))))
    found.discard("\n")
    return "".join(sorted(found))


def main():
    try:
        from fontTools import subset  # noqa: F401
        import brotli  # noqa: F401
    except ImportError:
        print("✗ 需要 fonttools 和 brotli：python3 -m pip install fonttools brotli", file=sys.stderr)
        return 1
    src = os.environ.get("XIAXIA_HAND_FONT", CACHE)
    if not os.path.exists(src):
        print(f"▸ 下载霞鹜文楷 Medium → {src}")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        urllib.request.urlretrieve(URL, src + ".part")
        os.replace(src + ".part", src)
    text = chars()
    from fontTools import subset
    opts = subset.Options()
    opts.flavor = "woff2"
    opts.layout_features = ["kern", "liga", "calt", "locl", "vert", "halt", "palt"]
    opts.name_IDs = ["*"]  # 保留字体名字和版权、许可信息（OFL 要求）
    font = subset.load_font(src, opts)
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    subset.save_font(font, OUT, opts)
    han = sum(1 for c in text if "㐀" <= c <= "鿿")
    print(f"写好了 site/assets/fonts/xiaxia-hand.woff2（{han} 个汉字，{os.path.getsize(OUT) // 1024} KB）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
