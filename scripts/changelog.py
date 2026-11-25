#!/usr/bin/env python3
"""夏夏账本更新日志：一份数据（Sources/LedgerUI/Resources/Changelog.json），三处用。

  python3 scripts/changelog.py site              # 生成官网 site/changelog.html，还有 site/en/、site/es/ 里的英文、西语版
  python3 scripts/changelog.py notes 0.2.5 out.html  # 生成 Mac 更新窗口里显示的「新版改了什么」
  python3 scripts/changelog.py add 0.2.5         # 发版时调用：没有这一版就按上次发版以来的 PR 标题起草一条
  python3 scripts/changelog.py check [0.2.5]     # 检查格式（可选：这一版必须有）

只用 Python 自带的库。
"""
import datetime, html, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "Sources", "LedgerUI", "Resources", "Changelog.json")
SITE = os.path.join(ROOT, "site")


def load():
    with open(DATA, encoding="utf-8") as f:
        return json.load(f)


def save(d):
    with open(DATA, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
        f.write("\n")


def vkey(v):
    return tuple(int(x) for x in re.findall(r"\d+", v))


def check(d, need=None):
    errs = []
    rs = d.get("releases", [])
    seen = set()
    for r in rs:
        v = r.get("version", "")
        if not re.fullmatch(r"\d+\.\d+\.\d+", v): errs.append(f"版本号不对：{v!r}")
        if v in seen: errs.append(f"{v} 写了两次")
        seen.add(v)
        try: datetime.date.fromisoformat(r.get("date", ""))
        except ValueError: errs.append(f"{v} 的日期不对：{r.get('date')!r}")
        for k in ("title", "summary"):
            if not r.get(k): errs.append(f"{v} 缺 {k}")
        if not r.get("items"): errs.append(f"{v} 至少写一条改动")
        for lang in ("en", "es"):
            t = r.get(lang)
            if t is None: continue
            if not t.get("title") or not t.get("summary"): errs.append(f"{v} 的 {lang} 缺 title 或 summary")
            if len(t.get("items", [])) != len(r.get("items", [])): errs.append(f"{v} 的 {lang} 条数和中文不一样")
        for im in images_of(r):
            src = im.get("src") or ""
            if not src or not os.path.isfile(os.path.join(SITE, src)): errs.append(f"{v} 的配图 site/{src} 不存在（images 里每张都要写 src）")
            # 只有新写法 images 必须写 alt；旧写法 image 用默认的「x.y.z 版截图（示例数据）」
            elif r.get("images") and im.get("style") != "art" and not (im.get("alt") or {}).get("zh"):
                errs.append(f"{v} 的配图 {src} 缺 alt（写清图里是什么）")
    vs = [vkey(r["version"]) for r in rs if re.fullmatch(r"\d+\.\d+\.\d+", r.get("version", ""))]
    if vs != sorted(vs, reverse=True): errs.append("新版本要放在最前面")
    if need and need not in seen: errs.append(f"还没有 {need} 这一条")
    return errs


def git(*a):
    return subprocess.run(["git", "-C", ROOT, *a], capture_output=True, text=True).stdout.strip()


def add(version):
    d = load()
    if any(r["version"] == version for r in d["releases"]):
        print(f"更新日志里已经有 {version}，不动它")
        return
    last = next((r.get("commit") for r in d["releases"] if r.get("commit")), None)
    rng = f"{last}..HEAD" if last else "HEAD~20..HEAD"
    subjects = [s for s in git("log", "--first-parent", "--format=%s", rng).splitlines() if s]
    items = []
    for s in subjects:
        s = re.sub(r"\s*\(#\d+\)\s*$", "", s).strip()
        if not s or s.startswith(("Merge ", "官网", "合并 main")) or "更新日志" in s: continue
        items.append(s if s.endswith(("。", "！", "）")) else s + "。")
    if not items: items = ["小修小补，用起来更顺。"]
    title = re.sub(r"[。]$", "", items[0].split("：")[0])
    r = {"version": version, "date": datetime.date.today().isoformat(), "commit": git("rev-parse", "--short", "HEAD"),
         "title": title, "summary": "这一版的改动都在下面。", "items": items[:6]}
    d["releases"].insert(0, r)
    save(d)
    print(f"⚠︎ 更新日志里没有 {version}，按 PR 标题起草了一条（记得改成大白话、配张示例数据截图，再提交）：")
    print(json.dumps(r, ensure_ascii=False, indent=2))


def notes(version, out):
    r = next((r for r in load()["releases"] if r["version"] == version), None)
    if not r: sys.exit(f"更新日志里没有 {version}")
    e = html.escape
    lis = "".join(f"<li>{e(i)}</li>" for i in r["items"])
    body = f"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><style>
body{{font:13px -apple-system,"PingFang SC",sans-serif;line-height:1.55;margin:12px 14px;color:#1d1d1f}}
h2{{font-size:15px;margin:0 0 4px}} p{{margin:0 0 8px;color:#55555c}} ul{{margin:0;padding-left:18px}} li{{margin:3px 0}}
a{{color:#ff7a3d}}
@media (prefers-color-scheme:dark){{body{{color:#f5f5f7}} p{{color:#b4b4bb}}}}
</style></head><body><h2>{e(r['title'])}</h2><p>{e(r['summary'])}</p><ul>{lis}</ul>
<p style="margin-top:10px"><a href="https://xiaxia.ming95.com/changelog.html#v{e(version)}">看完整更新日志</a></p></body></html>
"""
    with open(out, "w", encoding="utf-8") as f: f.write(body)


# 更新日志页上除了每一版内容以外的文字。
CHROME = {
    "zh": {"lang": "zh-CN", "date": lambda d: f"{d.year} 年 {d.month} 月 {d.day} 日", "shot": "{v} 版截图（示例数据）", "new": "最新"},
    "en": {"lang": "en", "date": lambda d: f"{d.day} {EN_MONTHS[d.month - 1]} {d.year}", "shot": "Screenshot of version {v} (sample data)", "new": "Latest",
           "text": {"主导航": "Main navigation", "更新日志 · 夏夏账本": "Changelog · Xiaxia Ledger", "夏夏账本每个版本改了什么，用大白话写。": "What changed in each version of Xiaxia Ledger, in plain words.",
                    "夏夏账本 · 更新日志": "Xiaxia Ledger · Changelog", "夏夏账本更新": "Xiaxia Ledger updates", "看看界面": "Tour", "怎么装": "Install", "更新日志": "Changelog", "下载": "Download",
                    "每一版改了什么，大白话写在这里。装好的 app 有新版会在左下角提醒，点一下就更新。": "What changed in each version, in plain words. The installed app shows a reminder in the bottom-left corner when a new version is out; one click updates it.",
                    "截图里的金额和人名都是示例数据。": "Amounts and names in the screenshots are sample data; screenshots show the Chinese interface.", "夏夏账本": "Xiaxia Ledger",
                    "跳到正文": "Skip to content", "菜单": "Menu", "更早的版本": "Earlier versions", "点开看这一版改了什么": "Open to see what changed",
                    "点图片看大图": "Click a picture to see it full size", "回首页": "Back to home", "夏夏在欢呼": "Xiaxia cheering"}},
    "es": {"lang": "es", "date": lambda d: f"{d.day} de {ES_MONTHS[d.month - 1]} de {d.year}", "shot": "Captura de la versión {v} (datos de ejemplo)", "new": "Última",
           "text": {"主导航": "Navegación principal", "更新日志 · 夏夏账本": "Novedades · Xiaxia Ledger", "夏夏账本每个版本改了什么，用大白话写。": "Qué ha cambiado en cada versión de Xiaxia Ledger, explicado con claridad.",
                    "夏夏账本 · 更新日志": "Xiaxia Ledger · Novedades", "夏夏账本更新": "Novedades de Xiaxia Ledger", "看看界面": "Recorrido", "怎么装": "Instalar", "更新日志": "Novedades", "下载": "Descargar",
                    "每一版改了什么，大白话写在这里。装好的 app 有新版会在左下角提醒，点一下就更新。": "Qué ha cambiado en cada versión, explicado con claridad. La app instalada avisa abajo a la izquierda cuando hay versión nueva; un clic la actualiza.",
                    "截图里的金额和人名都是示例数据。": "Los importes y nombres de las capturas son datos de ejemplo; las capturas muestran la interfaz en chino.", "夏夏账本": "Xiaxia Ledger",
                    "跳到正文": "Saltar al contenido", "菜单": "Menú", "更早的版本": "Versiones anteriores", "点开看这一版改了什么": "Ábrelo para ver qué cambió",
                    "点图片看大图": "Pulsa una imagen para verla en grande", "回首页": "Volver al inicio", "夏夏在欢呼": "Xiaxia celebrando"}},
}
EN_MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
ES_MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]


def images_of(r):
    """这一版的配图：新写法 images（列表），旧写法 image + imageStyle 也认。"""
    if r.get("images"): return r["images"]
    if r.get("image"): return [{"src": r["image"], "style": r.get("imageStyle")}]
    return []


def img_size(path):
    """读 webp / png 的宽高（只用自带的库），读不出来返回 None。"""
    try:
        with open(path, "rb") as f: b = f.read(64)
    except OSError:
        return None
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return int.from_bytes(b[16:20], "big"), int.from_bytes(b[20:24], "big")
    if b[:4] == b"RIFF" and b[8:12] == b"WEBP":
        kind = b[12:16]
        if kind == b"VP8X": return 1 + int.from_bytes(b[24:27], "little"), 1 + int.from_bytes(b[27:30], "little")
        if kind == b"VP8 ": return int.from_bytes(b[26:28], "little") & 0x3FFF, int.from_bytes(b[28:30], "little") & 0x3FFF
        if kind == b"VP8L":
            n = int.from_bytes(b[21:25], "little")
            return (n & 0x3FFF) + 1, ((n >> 14) & 0x3FFF) + 1
    return None


def site():
    d = load()
    for lang in ("zh", "en", "es"):
        page = render(d, lang)
        rel = "changelog.html" if lang == "zh" else f"{lang}/changelog.html"
        path = os.path.join(SITE, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f: f.write(page)
        print(f"写好了 site/{rel}")
        missing = [r["version"] for r in d["releases"] if lang != "zh" and not r.get(lang)]
        if missing: print(f"⚠︎ {lang} 还没翻的版本（先显示中文）：{'、'.join(missing)}")
    # 标题用的手写字体只截了页面上用到的字；新写的标题要重新截一次。
    font = os.path.join(os.path.dirname(os.path.abspath(__file__)), "site-font.py")
    if subprocess.run([sys.executable, font]).returncode != 0:
        print("⚠︎ 标题字体没更新（见上面的提示）；新标题里的字会先用系统楷体顶上")


def figures(r, lang, up, eager):
    e = html.escape
    c = CHROME[lang]
    out = []
    for im in images_of(r):
        alt = im.get("alt") or {}
        alt = alt.get(lang) or alt.get("zh") or c["shot"].format(v=r["version"])
        size = img_size(os.path.join(SITE, im["src"]))
        wh = f' width="{size[0]}" height="{size[1]}"' if size else ""
        src = e(up + im["src"])
        if im.get("style") == "art":
            out.append(f'<figure class="art"><img src="{src}" alt="{e(alt)}"{wh} loading="lazy"></figure>')
        else:
            out.append(f'<figure><a href="{src}"><img src="{src}" alt="{e(alt)}"{wh} loading="{"eager" if eager else "lazy"}" decoding="async"></a></figure>')
    if not out: return ""
    many = " many" if len(out) > 1 else ""
    return f'<div class="figs{many}">' + "".join(out) + "</div>"


def render(d, lang):
    e = html.escape
    c = CHROME[lang]
    up = "" if lang == "zh" else "../"
    rs = d["releases"]
    parts = []
    for i, r in enumerate(rs):
        t = r if lang == "zh" else (r.get(lang) or r)
        v = e(r["version"])
        date = c["date"](datetime.date.fromisoformat(r["date"]))
        lis = "".join(f"<li>{e(x)}</li>" for x in t["items"])
        if i == 0:
            parts.append(f"""<section class="latest" id="v{v}" aria-labelledby="t{v}">
  <div class="stub"><span class="new">{c["new"]}</span><a class="ver" href="#v{v}">{v}</a><time datetime="{e(r['date'])}">{date}</time></div>
  <h2 class="hand" id="t{v}">{e(t['title'])}</h2>
  <p class="sum">{e(t['summary'])}</p>
  <ul>{lis}</ul>
  {figures(r, lang, up, True)}
</section>
<h2 class="older-h hand">更早的版本</h2>
<ol class="older">""")
        else:
            parts.append(f"""<li id="v{v}"><details>
  <summary><span class="ver">{v}</span><time datetime="{e(r['date'])}">{date}</time><span class="t">{e(t['title'])}</span></summary>
  <div class="body">
    <p class="sum">{e(t['summary'])}</p>
    <ul>{lis}</ul>
    {figures(r, lang, up, False)}
  </div>
</details></li>""")
    if len(rs) > 1: parts.append("</ol>")
    page = TEMPLATE
    if lang != "zh":
        # 中文页才有的（按浏览器语言跳转）去掉；外面的文字换掉，长的先换，一次扫完。
        page = re.sub(r"<!--zh-only-->.*?<!--/zh-only-->\n?", "", page, flags=re.S)
        page = page.replace("{{CARDS}}", "\n".join(parts))
        text = c["text"]
        # 只换模板里的固定文字，不碰每一版的内容（内容已经是这种语言了）
        head, sep, rest = page.partition('<section class="latest"')
        tail_i = rest.find("</main>")
        body, tail = rest[:tail_i], rest[tail_i:]
        rx = re.compile("|".join(re.escape(k) for k in sorted(text, key=len, reverse=True)))
        fix = lambda s: rx.sub(lambda m: text[m.group(0)], s)
        body = body.replace('<h2 class="older-h hand">更早的版本</h2>', f'<h2 class="older-h hand">{text["更早的版本"]}</h2>')
        page = fix(head) + sep + body + fix(tail)
        page = page.replace('<html lang="zh-CN">', f'<html lang="{c["lang"]}">')
        page = re.sub(r'((?:src|href)=")assets/', r"\1../assets/", page)
        page = page.replace("url(assets/", "url(../assets/")
        page = page.replace('href="/#', f'href="/{lang}/#').replace('href="/"', f'href="/{lang}/"')
        page = page.replace(' data-lang="zh" aria-current="true"', ' data-lang="zh"')
        page = page.replace(f' data-lang="{lang}"', f' data-lang="{lang}" aria-current="true"')
        return page
    return page.replace("{{CARDS}}", "\n".join(parts))


TEMPLATE = """<!doctype html>
<!-- 这个文件由 scripts/changelog.py site 生成，别直接改；改 Sources/LedgerUI/Resources/Changelog.json -->
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>更新日志 · 夏夏账本</title>
<meta name="description" content="夏夏账本每个版本改了什么，用大白话写。">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#fff8ee" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#141a3a" media="(prefers-color-scheme: dark)">
<meta property="og:title" content="夏夏账本 · 更新日志">
<meta property="og:image" content="https://xiaxia.ming95.com/assets/og.png">
<link rel="alternate" hreflang="zh" href="https://xiaxia.ming95.com/changelog.html">
<link rel="alternate" hreflang="en" href="https://xiaxia.ming95.com/en/changelog.html">
<link rel="alternate" hreflang="es" href="https://xiaxia.ming95.com/es/changelog.html">
<!--zh-only-->
<script>
// 浏览器是英文或西班牙语、又没自己选过语言的，带去对应的页面；选过就听选的。
(function(){try{var c=localStorage.getItem('xiaxia.lang'),l=c||(navigator.language||'').slice(0,2).toLowerCase();
if(l==='en'||l==='es')location.replace('/'+l+'/changelog.html'+location.hash)}catch(e){}})();
</script>
<!--/zh-only-->
<link rel="icon" type="image/png" href="assets/app-icon-64.png">
<link rel="alternate" type="application/rss+xml" title="夏夏账本更新" href="/appcast.xml">
<link rel="preload" href="assets/fonts/xiaxia-hand.woff2" as="font" type="font/woff2" crossorigin>
<style>
@font-face{font-family:"XiaHand";src:url(assets/fonts/xiaxia-hand.woff2) format("woff2");font-weight:500;font-display:swap}
:root{
  color-scheme:light dark;
  --paper:#fff8ee; --paper2:#fbefdc; --card:#fff; --ink:#1f2a5a; --ink2:#4a5378; --ink3:#5f6789;
  --rule:rgba(31,42,90,.07); --line:rgba(31,42,90,.14); --coral:#c4501a; --coral-h:#a84415; --coral-t:#b04716; --on-coral:#fff;
  --coin:#f6c452; --coin-soft:rgba(246,196,82,.45); --sea:#2a7d89;
  --shadow:0 1px 0 rgba(31,42,90,.05),0 18px 40px -22px rgba(31,42,90,.4);
  --hand:"XiaHand","Kaiti SC","STKaiti","KaiTi",serif;
  --sans:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
  --round:ui-rounded,"SF Pro Rounded",-apple-system,sans-serif;
}
@media (prefers-color-scheme:dark){
  :root{--paper:#141a3a;--paper2:#19204a;--card:#1e2650;--ink:#fff8ee;--ink2:#c9cee6;--ink3:#9aa2c6;--rule:rgba(255,248,238,.045);--line:rgba(255,248,238,.13);
    --coral:#ff9a5c;--coral-h:#ffb27a;--coral-t:#ffb27a;--on-coral:#141a3a;--coin-soft:rgba(246,196,82,.25);--sea:#8fdde3;
    --shadow:0 1px 0 rgba(0,0,0,.25),0 22px 50px -24px rgba(0,0,0,.8)}
}
*{box-sizing:border-box;margin:0}
html{-webkit-text-size-adjust:100%;scroll-padding-top:80px;-webkit-tap-highlight-color:transparent}
body{background:var(--paper);color:var(--ink);font:17px/1.65 var(--sans);-webkit-font-smoothing:antialiased;overflow-x:hidden;
  background-image:repeating-linear-gradient(180deg,transparent 0 31px,var(--rule) 31px 32px)}
img{max-width:100%;height:auto;display:block}
a{color:inherit}
:focus-visible{outline:3px solid var(--sea);outline-offset:3px;border-radius:6px}
.hand{font-family:var(--hand);font-weight:500;font-synthesis:none;letter-spacing:0}
:lang(en) .hand,:lang(es) .hand{letter-spacing:-.03em}
.skip{position:absolute;left:12px;top:-60px;z-index:50;background:var(--ink);color:var(--paper);padding:8px 14px;border-radius:10px;text-decoration:none;font-weight:600}
.skip:focus{top:12px}
.wrap{max-width:860px;margin:0 auto;padding:0 20px}
/* nav */
nav{position:sticky;top:0;z-index:20;backdrop-filter:saturate(160%) blur(16px);-webkit-backdrop-filter:saturate(160%) blur(16px);
  background:color-mix(in srgb,var(--paper) 82%,transparent);border-bottom:1px solid var(--line)}
nav .wrap{display:flex;align-items:center;gap:14px;height:60px;max-width:1120px}
.logo{display:flex;align-items:center;gap:10px;font-weight:700;text-decoration:none;white-space:nowrap}
.logo img{width:30px;height:30px;border-radius:8px}
.links{margin-left:auto;display:flex;gap:22px;align-items:center;font-size:15px;color:var(--ink2)}
.links a{text-decoration:none;text-underline-offset:4px}
.links a:hover,.links a[aria-current=page]{color:var(--ink);text-decoration:underline;text-decoration-color:var(--coin);text-decoration-thickness:3px}
.lang{display:flex;gap:4px;font-size:14px;white-space:nowrap}
.lang a{padding:4px 6px;border-radius:6px;text-decoration:none;color:var(--ink2)}
.lang a[aria-current]{color:var(--ink);font-weight:700;background:var(--coin-soft)}
.btn{white-space:nowrap;display:inline-flex;align-items:center;justify-content:center;gap:8px;border-radius:999px;padding:8px 16px;font-weight:700;text-decoration:none;
  background:var(--coral);color:var(--on-coral);font-size:15px;border:0;cursor:pointer;touch-action:manipulation;transition:background-color .15s,transform .15s}
.btn:hover{background:var(--coral-h)}
.menu{display:none;position:relative}
.menu summary{white-space:nowrap;list-style:none;cursor:pointer;padding:6px 12px;border:1px solid var(--line);border-radius:999px;font-size:14px;font-weight:600}
.menu summary::-webkit-details-marker{display:none}
.menu div{position:absolute;right:0;top:calc(100% + 8px);background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:var(--shadow);padding:8px;display:grid;min-width:170px}
.menu div a{padding:10px 12px;border-radius:8px;text-decoration:none}
.menu div a:hover{background:var(--paper2)}
.mlang{display:flex;gap:4px;padding:8px 6px 4px;margin-top:4px;border-top:1px dashed var(--line)}
@media (max-width:760px){.links>a:not(.btn){display:none}.menu{display:block}.links{gap:10px}}
@media (max-width:520px){.links>.lang{display:none}}
@media (min-width:521px){.mlang{display:none}}
.mdl{display:none}
@media (max-width:400px){nav .wrap{gap:8px;padding:0 14px}.links>.btn{display:none}.mdl{display:block;font-weight:700;color:var(--coral-t)}.logo{gap:8px;font-size:15px}}
/* header */
.top{display:flex;align-items:flex-end;justify-content:space-between;gap:20px;padding:56px 0 28px}
.top h1{font-size:clamp(40px,7vw,60px);line-height:1.1;text-wrap:balance}
.top p{color:var(--ink2);margin-top:10px;max-width:520px;text-wrap:pretty}
.top img{width:120px;flex:none}
/* latest: a receipt */
.latest{position:relative;background:var(--card);border-radius:18px 18px 0 0;padding:28px 30px 40px;box-shadow:var(--shadow);margin-bottom:56px}
.latest::after{content:"";position:absolute;left:0;right:0;bottom:-12px;height:12px;
  background:linear-gradient(-45deg,transparent 8px,var(--card) 0) 0 0/16px 12px repeat-x,linear-gradient(45deg,transparent 8px,var(--card) 0) 0 0/16px 12px repeat-x}
.stub{display:flex;align-items:baseline;gap:12px;flex-wrap:wrap;padding-bottom:16px;margin-bottom:18px;border-bottom:2px dashed var(--line)}
.ver{font-family:var(--round);font-weight:800;font-variant-numeric:tabular-nums;text-decoration:none;letter-spacing:-.01em}
.stub .ver{font-size:30px}
.new{background:var(--coin);color:#1f2a5a;border-radius:999px;font-size:13px;font-weight:800;padding:2px 10px;align-self:center}
time{font-size:14px;color:var(--ink3)}
.latest h2{font-size:clamp(26px,4vw,34px);line-height:1.25;text-wrap:balance}
.sum{color:var(--ink2);margin-top:8px;text-wrap:pretty}
.latest ul,.body ul{margin-top:16px;padding-left:1.25em}
li{margin:7px 0}
.latest li::marker,.body li::marker{color:var(--coral-t);content:"● ";font-size:.7em}
.figs{display:grid;gap:14px;margin-top:22px}
figure{border-radius:12px;overflow:hidden;border:1px solid var(--line);background:var(--paper2)}
figure a{display:block;border-radius:inherit}
figure a:focus-visible{outline:3px solid var(--sea);outline-offset:-5px}
figure img{width:100%}
figure.art{border:0;background:none;border-radius:0}
figure.art img{width:160px;margin:0 auto}
/* older */
.older-h{font-size:28px;margin-bottom:12px}
.older{list-style:none;padding:0;border-top:2px solid var(--ink);margin-bottom:56px}
.older>li{margin:0;border-bottom:1px dashed var(--line)}
.older summary{display:grid;grid-template-columns:76px 160px 1fr 24px;align-items:baseline;gap:12px;padding:16px 4px;cursor:pointer;list-style:none}
.older summary::-webkit-details-marker{display:none}
.older summary::after{content:"+";font-size:22px;line-height:1;color:var(--ink3);justify-self:end}
.older details[open] summary::after{content:"–"}
.older summary:hover .t{text-decoration:underline;text-decoration-color:var(--coin);text-decoration-thickness:3px;text-underline-offset:4px}
.older .ver{font-size:20px}
.older .t{font-weight:600;min-width:0}
.body{padding:0 4px 24px 100px}
footer{padding:28px 0 44px;font-size:14px;color:var(--ink3);border-top:1px solid var(--line)}
footer .wrap{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;max-width:1120px}
@media (max-width:760px){
  .top{padding:36px 0 20px}.top img{width:84px}
  .latest{padding:22px 18px 32px}
  .older summary{grid-template-columns:auto 1fr 20px;row-gap:2px}
  .older summary .t{grid-column:1/3;grid-row:2}
  .older summary::after{grid-row:1/3;grid-column:3;align-self:center}
  .body{padding:0 4px 20px}
}
</style>
</head>
<body>
<a class="skip" href="#main">跳到正文</a>
<nav aria-label="主导航">
  <div class="wrap">
    <a href="/" class="logo"><img src="assets/app-icon-64.png" alt="" width="30" height="30">夏夏账本</a>
    <div class="links">
      <a href="/#tour">看看界面</a>
      <a href="/#install">怎么装</a>
      <a href="changelog.html" aria-current="page">更新日志</a>
      <span class="lang" aria-label="Language"><a href="/changelog.html" hreflang="zh" lang="zh" data-lang="zh" aria-current="true">中文</a><a href="/en/changelog.html" hreflang="en" lang="en" data-lang="en">EN</a><a href="/es/changelog.html" hreflang="es" lang="es" data-lang="es">ES</a></span>
      <details class="menu"><summary>菜单</summary><div><a href="/#tour">看看界面</a><a href="/#install">怎么装</a><a href="changelog.html" aria-current="page">更新日志</a><a class="mdl" href="/download/xiaxia-ledger.dmg">下载</a><span class="lang mlang" aria-label="Language"><a href="/changelog.html" hreflang="zh" lang="zh" data-lang="zh" aria-current="true">中文</a><a href="/en/changelog.html" hreflang="en" lang="en" data-lang="en">EN</a><a href="/es/changelog.html" hreflang="es" lang="es" data-lang="es">ES</a></span></div></details>
      <a class="btn" href="/download/xiaxia-ledger.dmg">下载</a>
    </div>
  </div>
</nav>
<main class="wrap" id="main">
<header class="top">
  <div>
    <h1 class="hand">更新日志</h1>
    <p>每一版改了什么，大白话写在这里。装好的 app 有新版会在左下角提醒，点一下就更新。</p>
  </div>
  <img src="assets/xiaxia-cheer.webp" alt="" width="300" height="300">
</header>
{{CARDS}}
</main>
<footer>
  <div class="wrap">
    <span>© 2026 夏夏账本 · <a href="/">回首页</a></span>
    <span>截图里的金额和人名都是示例数据。</span>
  </div>
</footer>
<script>
document.querySelectorAll('.lang a').forEach(function(a){a.addEventListener('click',function(){try{localStorage.setItem('xiaxia.lang',a.dataset.lang)}catch(e){}})});
// 地址里带着 #v0.2.3 这种：把那一版展开
function openHash(){var el=location.hash&&document.getElementById(decodeURIComponent(location.hash.slice(1)));var d=el&&el.querySelector('details');if(d){d.open=true;el.scrollIntoView()}}
openHash();window.addEventListener('hashchange',openHash);
</script>
</body>
</html>
"""

if __name__ == "__main__":
    a = sys.argv[1:]
    if not a: sys.exit(__doc__)
    cmd = a[0]
    if cmd == "site":
        errs = check(load())
        if errs: sys.exit("\n".join(errs))
        site()
    elif cmd == "notes" and len(a) == 3: notes(a[1], a[2])
    elif cmd == "add" and len(a) == 2: add(a[1])
    elif cmd == "check":
        errs = check(load(), a[1] if len(a) > 1 else None)
        if errs: sys.exit("\n".join(errs))
        print("更新日志没问题")
    else: sys.exit(__doc__)
