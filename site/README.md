# 夏夏账本官网

一个静态页面（`index.html` + `assets/`），同时是 Mac 版的下载和自动更新地址。

| 网址 | 是什么 | 谁生成 |
|---|---|---|
| `/` | 官网 | 这个目录 |
| `/download/xiaxia-ledger.dmg` | 最新版安装包（官网下载按钮） | `scripts/release-share.sh` → `dist/download/` |
| `/download/xiaxia-ledger-<版本>.dmg` | 每个版本一份，appcast 指向它 | 同上 |
| `/appcast.xml` | Sparkle 自动更新文件（app 的 SUFeedURL），每版带「改了什么」 | 同上 → `dist/appcast.xml` |
| `/changelog.html` | 更新日志页，每版一段大白话 + 截图 | `python3 scripts/changelog.py site`，数据在 `Sources/LedgerUI/Resources/Changelog.json` |

更新日志只改 `Changelog.json`（新版放最前面；配图写在 `images` 里，每张带 `alt`（zh/en/es 写清图里是什么），图放 `assets/changelog/`，只用示例数据、只截改动的那一块，宽 1200–1600 的 webp），再跑 `python3 scripts/changelog.py site`。app 里「这次更新了什么」和 Mac 更新窗口读的也是它。发版时 `release-share.sh` 会自动检查：没写这一版就按 PR 标题起草一条，记得改成大白话再提交。

官网会读 `/appcast.xml`，自动显示最新版本号和大小。

## 样子（2026-11-25 改版）

- 配色从夏夏身上取：奶油底 `#FFF8EE`、墨蓝字 `#1F2A5A`（深色模式底 `#141A3A`）、海水青 `#2A7D89`/`#8FDDE3`、金币黄 `#F6C452`；橙色 `#C4501A`（深色 `#FF9A5C`）只用在下载按钮上。浅色底上有淡淡的账本横线。
- 标题用手写字体霞鹜文楷（SIL OFL，许可证在 `assets/fonts/LXGWWenKai-OFL.txt`），只截了页面上用到的字（`assets/fonts/xiaxia-hand.woff2`，三十几 KB）。改了标题文字要跑 `python3 scripts/site-font.py`（需要 `pip install fonttools brotli`）；`site-i18n.py` 和 `changelog.py site` 跑完会自己调用，装不上也不出错，新字先用系统楷体顶着。
- 首页英文、西语页由 `python3 scripts/site-i18n.py` 从中文首页生成，翻译表在 `scripts/site_i18n_table.py`；改完跑 `python3 scripts/site-i18n.py --check` 看有没有漏翻。

## 第一次上线（每台 VPS 只做一次）

1. 域名的 A 记录指向 VPS 的 IP。
2. `cp site/deploy.env.example site/deploy.env`，填 ssh 别名和域名。
3. 干净的服务器：`ssh <别名> 'sudo bash -s <域名>' < site/server/setup.sh`，装 Caddy、自动配 HTTPS。
   已经跑着 Coolify 的服务器（现在用的 ovh-fr-1，要加 sudo）：`ssh <别名> 'bash -s <域名>' < site/server/setup-coolify.sh`，起一个 nginx 小容器，让 Coolify 的 Traefik 代理并签证书，不改 Coolify 自己的配置。

现在线上：https://xiaxia.ming95.com （ovh-fr-1 = 51.38.40.203，网页在 /var/www/xiaxia，容器 xiaxia-site；DNS 在 Cloudflare，仅 DNS 灰云）。发新版：`XIAXIA_SSH=ovh-fr-1 bash site/deploy.sh --release`。

## 以后

- 改了网页：`bash site/deploy.sh --site`
- 发新版：`scripts/release-share.sh` 做好 `dist/` 后会调用 `bash site/deploy.sh --release`（先传 dmg，最后传 appcast.xml）

截图只用示例账本（`-XiaxiaDemo`），不能放真实账目。
