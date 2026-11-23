#!/usr/bin/env python3
"""夏夏账本更新日志：一份数据（Sources/LedgerUI/Resources/Changelog.json），三处用。

  python3 scripts/changelog.py site              # 生成官网 site/changelog.html
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
        img = r.get("image")
        if img and not os.path.exists(os.path.join(SITE, img)): errs.append(f"{v} 的截图 site/{img} 不存在")
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


def site():
    d = load()
    e = html.escape
    cards = []
    for i, r in enumerate(d["releases"]):
        dt = datetime.date.fromisoformat(r["date"])
        date = f"{dt.year} 年 {dt.month} 月 {dt.day} 日"
        lis = "".join(f"<li>{e(x)}</li>" for x in r["items"])
        img = ""
        if r.get("image"):
            cls = ' class="art"' if r.get("imageStyle") == "art" else ""
            img = (f'<figure{cls}><img src="{e(r["image"])}" alt="{e(r["version"])} 版截图（示例数据）" '
                   f'loading="{"eager" if i == 0 else "lazy"}"></figure>')
        tag = '<span class="new">最新</span>' if i == 0 else ""
        cards.append(f"""<article id="v{e(r['version'])}">
  <div class="when"><a class="ver" href="#v{e(r['version'])}">{e(r['version'])}</a>{tag}<time datetime="{e(r['date'])}">{date}</time></div>
  <div class="card">
    <h2>{e(r['title'])}</h2>
    <p class="sum">{e(r['summary'])}</p>
    <ul>{lis}</ul>
    {img}
  </div>
</article>""")
    page = TEMPLATE.replace("{{CARDS}}", "\n".join(cards))
    with open(os.path.join(SITE, "changelog.html"), "w", encoding="utf-8") as f: f.write(page)
    print("写好了 site/changelog.html")


TEMPLATE = """<!doctype html>
<!-- 这个文件由 scripts/changelog.py site 生成，别直接改；改 Sources/LedgerUI/Resources/Changelog.json -->
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>更新日志 · 夏夏账本</title>
<meta name="description" content="夏夏账本每个版本改了什么，用大白话写。">
<meta name="theme-color" content="#0f0f14">
<meta property="og:title" content="夏夏账本 · 更新日志">
<meta property="og:image" content="https://xiaxia.ming95.com/assets/og.png">
<link rel="icon" type="image/png" href="assets/app-icon-64.png">
<link rel="alternate" type="application/rss+xml" title="夏夏账本更新" href="/appcast.xml">
<style>
:root{
  --bg:#fbfaf8; --bg2:#f3f1ee; --card:#ffffff; --fg:#1d1d1f; --fg2:#55555c; --fg3:#86868b;
  --line:rgba(0,0,0,.08); --brand:#ff7a3d; --shadow:0 1px 2px rgba(0,0,0,.04),0 12px 40px rgba(0,0,0,.08);
  font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
}
@media (prefers-color-scheme:dark){
  :root{--bg:#0d0d11;--bg2:#15151b;--card:#1b1b22;--fg:#f5f5f7;--fg2:#b4b4bb;--fg3:#7d7d85;--line:rgba(255,255,255,.09);
    --shadow:0 1px 2px rgba(0,0,0,.3),0 12px 40px rgba(0,0,0,.4)}
}
*{box-sizing:border-box;margin:0}
html{-webkit-text-size-adjust:100%;scroll-padding-top:72px}
body{background:var(--bg);color:var(--fg);line-height:1.6;font-size:17px;-webkit-font-smoothing:antialiased;overflow-x:hidden}
img{max-width:100%;height:auto;display:block}
a{color:inherit}
.wrap{max-width:880px;margin:0 auto;padding:0 16px}
nav{position:sticky;top:0;z-index:20;backdrop-filter:saturate(180%) blur(20px);-webkit-backdrop-filter:saturate(180%) blur(20px);
  background:color-mix(in srgb,var(--bg) 72%,transparent);border-bottom:1px solid var(--line)}
nav .wrap{display:flex;align-items:center;gap:12px;height:56px;max-width:1120px}
nav .logo{display:flex;align-items:center;gap:10px;font-weight:600;text-decoration:none}
nav .logo img{width:28px;height:28px;border-radius:7px}
nav .links{margin-left:auto;display:flex;gap:22px;align-items:center;font-size:14px;color:var(--fg2)}
nav .links a{text-decoration:none}
nav .links a:hover{color:var(--fg)}
.btn{display:inline-flex;align-items:center;border-radius:999px;padding:7px 14px;font-weight:600;text-decoration:none;background:var(--brand);color:#fff;font-size:14px}
.btn:hover{background:#ff6a26}
header{padding:64px 0 32px}
header h1{font-size:clamp(32px,5vw,48px);line-height:1.15;letter-spacing:-.02em}
header p{color:var(--fg2);margin-top:12px;font-size:18px}
article{display:grid;grid-template-columns:140px 1fr;gap:24px;padding:0 0 40px;position:relative}
.when{position:sticky;top:76px;align-self:start;display:flex;flex-direction:column;gap:4px}
.ver{font-family:ui-rounded,"SF Pro Rounded",-apple-system,sans-serif;font-size:26px;font-weight:700;text-decoration:none;letter-spacing:-.01em}
.new{align-self:flex-start;background:var(--brand);color:#fff;border-radius:999px;font-size:12px;font-weight:600;padding:1px 9px}
time{font-size:14px;color:var(--fg3)}
.card{background:var(--card);border:1px solid var(--line);border-radius:20px;box-shadow:var(--shadow);padding:24px 26px}
.card h2{font-size:22px;line-height:1.35;letter-spacing:-.01em}
.sum{color:var(--fg2);margin-top:6px}
.card ul{margin-top:14px;padding-left:1.2em}
.card li{margin:6px 0}
.card li::marker{color:var(--brand)}
figure{margin-top:20px;border-radius:12px;overflow:hidden;border:1px solid var(--line);background:var(--bg2)}
figure img{width:100%;max-height:440px;object-fit:cover;object-position:top}
figure.art{border:0;background:none;border-radius:0}
figure.art img{width:180px;margin:0 auto}
footer{padding:28px 0 40px;font-size:13px;color:var(--fg3);border-top:1px solid var(--line)}
footer .wrap{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap}
@media (max-width:720px){
  nav .links a:not(.btn){display:none}
  header{padding:40px 0 24px}
  article{grid-template-columns:1fr;gap:10px}
  .when{position:static;flex-direction:row;align-items:baseline;gap:10px}
  .card{padding:18px}
  .card h2{font-size:19px}
}
</style>
</head>
<body>
<nav aria-label="主导航">
  <div class="wrap">
    <a class="logo" href="/"><img src="assets/app-icon-64.png" alt="" width="28" height="28">夏夏账本</a>
    <div class="links">
      <a href="/#tour">看看界面</a>
      <a href="/#install">怎么装</a>
      <a href="changelog.html" aria-current="page">更新日志</a>
      <a class="btn" href="/download/xiaxia-ledger.dmg">下载</a>
    </div>
  </div>
</nav>
<main class="wrap">
<header>
  <h1>更新日志</h1>
  <p>每一版改了什么，大白话写在这里。装好的 app 有新版会在左下角提醒，点一下就更新。</p>
</header>
{{CARDS}}
</main>
<footer>
  <div class="wrap">
    <span>© 2026 夏夏账本</span>
    <span>截图里的金额和人名都是示例数据。</span>
  </div>
</footer>
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
