#!/usr/bin/env python3
"""官网多语言：从中文首页 site/index.html 生成 site/en/index.html 和 site/es/index.html。

  python3 scripts/site-i18n.py          # 生成
  python3 scripts/site-i18n.py --check  # 只检查：有没有漏翻的中文、生成的和仓库里的是否一致（不一致返回 1）

翻译表在 scripts/site_i18n_table.py。改了首页文字：改表 → 跑这个脚本 → 一起提交。
更新日志页的英文、西语由 scripts/changelog.py site 生成。只用 Python 自带的库。
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, "site")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from site_i18n_table import T  # noqa: E402

LANGS = {"en": 0, "es": 1}
HTML_LANG = {"en": "en", "es": "es"}
HAN = re.compile(r"[一-鿿]")
# 译文里故意留着的中文：app 在访达里的名字、语言切换里的「中文」。
KEEP = ("夏夏账本", "中文")


def localize(page, lang, table):
    """把一页中文换成 lang。一次扫完（长的键先配），译文不会被再换一遍。"""
    i = LANGS[lang]
    # 只在中文页用的东西（按浏览器语言跳转的那段脚本）去掉
    page = re.sub(r"<!--zh-only-->.*?<!--/zh-only-->\n?", "", page, flags=re.S)
    keys = sorted(table, key=len, reverse=True)
    rx = re.compile("|".join(re.escape(k) for k in keys))
    page = rx.sub(lambda m: table[m.group(0)][i], page)
    page = page.replace('<html lang="zh-CN">', f'<html lang="{HTML_LANG[lang]}">')
    # 子目录里的页面，图片这些要往上找一层
    page = re.sub(r'((?:src|srcset|href|data-img|data-girl|data-boy)=")assets/', r"\1../assets/", page)
    page = page.replace("url(assets/", "url(../assets/")
    # 站内链接留在同一种语言里
    page = page.replace('href="/#', f'href="/{lang}/#').replace('class="logo" href="/"', f'class="logo" href="/{lang}/"')
    # 语言切换：当前语言标出来
    page = page.replace(' data-lang="zh" aria-current="true"', ' data-lang="zh"')
    page = page.replace(f' data-lang="{lang}"', f' data-lang="{lang}" aria-current="true"')
    return page


def leftovers(page):
    """还剩的中文（去掉故意留的）。"""
    t = page
    for k in KEEP: t = t.replace(k, "")
    return sorted({m.group(0) for m in re.finditer(r"[^<>\"'\n]*[一-鿿][^<>\"'\n]*", t)})


def main():
    check = "--check" in sys.argv
    src = open(os.path.join(SITE, "index.html"), encoding="utf-8").read()
    bad = 0
    for lang in LANGS:
        out = localize(src, lang, T)
        left = leftovers(out)
        if left:
            bad = 1
            print(f"✗ {lang} 还有没翻的中文（{len(left)} 处）：")
            for x in left: print("   ", x.strip()[:120])
        path = os.path.join(SITE, lang, "index.html")
        if check:
            old = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
            if old != out:
                bad = 1
                print(f"✗ site/{lang}/index.html 和首页对不上，跑一次 python3 scripts/site-i18n.py 再提交")
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f: f.write(out)
            print(f"写好了 site/{lang}/index.html")
    if not check:
        # 标题用的手写字体只截了页面上用到的字，改了标题要重新截
        font = os.path.join(os.path.dirname(os.path.abspath(__file__)), "site-font.py")
        if subprocess.run([sys.executable, font]).returncode != 0:
            print("⚠︎ 标题字体没更新（见上面的提示）；新标题里的字会先用系统楷体顶上")
    sys.exit(bad)


if __name__ == "__main__":
    main()
