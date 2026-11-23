# 夏夏账本官网

一个静态页面（`index.html` + `assets/`），同时是 Mac 版的下载和自动更新地址。

| 网址 | 是什么 | 谁生成 |
|---|---|---|
| `/` | 官网 | 这个目录 |
| `/download/xiaxia-ledger.dmg` | 最新版安装包（官网下载按钮） | `scripts/release-share.sh` → `dist/download/` |
| `/download/xiaxia-ledger-<版本>.dmg` | 每个版本一份，appcast 指向它 | 同上 |
| `/appcast.xml` | Sparkle 自动更新文件（app 的 SUFeedURL） | 同上 → `dist/appcast.xml` |

官网会读 `/appcast.xml`，自动显示最新版本号和大小。

## 第一次上线（每台 VPS 只做一次）

1. 域名的 A 记录指向 VPS 的 IP。
2. `cp site/deploy.env.example site/deploy.env`，填 ssh 别名和域名。
3. `ssh <别名> 'sudo bash -s <域名>' < site/server/setup.sh`：装 Caddy、自动配 HTTPS。

## 以后

- 改了网页：`bash site/deploy.sh --site`
- 发新版：`scripts/release-share.sh` 做好 `dist/` 后会调用 `bash site/deploy.sh --release`（先传 dmg，最后传 appcast.xml）

截图只用示例账本（`-XiaxiaDemo`），不能放真实账目。
