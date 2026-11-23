# 把夏夏账本发给别人

## 别人从零到「对 AI 说一句就记上账」

| 步骤 | 以前（只有 ming 能走通） | 现在 |
|---|---|---|
| 1. 拿到 app | 自己装 Xcode、下代码、编译 | 下载 dmg，把「夏夏账本」拖进「应用程序」 |
| 2. 装 fin（AI 用来读写账本的程序） | 自己编译，跑 `scripts/install-global.sh` | 不用装：app 里自带（`夏夏账本.app/Contents/MacOS/fin`） |
| 3. 让 AI 工具认识账本 | 手动改各家配置文件 | 第一次打开 app 自动弹「连上你的 AI」：认出这台 Mac 上的 Claude 桌面版、Claude Code、Codex、Hermes Agent、Cursor、Gemini CLI，默认勾好，点「连上」 |
| 4. 重开 AI 工具 | — | 引导里写着每个工具要怎么重开（比如 Claude 要 ⌘Q 退出再开） |
| 5. 试一句 | — | 引导里点「复制并打开 Claude」，粘贴发出去；AI 一连上账本，引导页就变绿，记下第一笔会显示出来 |

另一条路：在引导页或「设置」里点「一键复制配置提示词」，粘给任何一个 AI（Claude Code、Codex、Hermes、Gemini CLI、Cursor、Claude 桌面版……）。能执行命令的 AI 会跑 `fin setup`，把这台 Mac 上所有 AI 工具的 MCP、使用说明（skill）和提示词一次装好（改前留 .bak-xiaxia 备份），最后调一次只读的 summary 确认读得到账本；不能执行命令的 AI 会一步步告诉你把配置粘到哪儿。

装了 Claude Code、Codex 或 Hermes 的人，第 5 步直接点「在夏夏对话栏里试」，不用离开 app。只有 Claude 桌面版的人，app 里的例句一律「复制并打开 Claude」，不会塞进一个答不了话的对话栏。

dmg 里附了「打不开看这里.txt」：没签名的版本第一次会被 Mac 拦下，按说明去「系统设置 → 隐私与安全性」点「仍要打开」。签名公证后不会出现。

没装任何 AI 工具：引导里给「下载 Claude 桌面版」；用 DeepSeek 的，装 Hermes Agent（能自动连）；用通义千问、Kimi 的，装 Cherry Studio，再点「复制配置」粘进它的 MCP 设置。别的支持 MCP 的工具同样粘这段。

iPhone 不需要引导：AI 工具只能在 Mac 上接本地账本，手机上只看。（手机和 Mac 靠 iCloud 看同一本账，见下面「iPhone 和 Mac 同步」。）

app 挪过位置（比如先在「下载」里打开过，后来拖进「应用程序」）：下次打开时自动把各 AI 工具配置里的路径改过来，不用重新连。

## 安装包从哪来

GitHub Actions 里的 **release** 流程（`.github/workflows/release.yml`）：

- 在 Actions 页面手动点「Run workflow」：做一个 dmg，挂在那次运行的 Artifacts 里，自己先下载试。
- 推一个 `v0.2.0` 这样的 tag：除了做 dmg，还建一个 GitHub Release **草稿**，ming 看过再点「Publish」才公开。

## 三种发法

| | A. 未签名 dmg（现在就能发） | B. 签名 + 公证的 dmg（推荐） | C. 用线直接装 iPhone（ming 定：不上架） |
|---|---|---|---|
| 别人打开 | 第一次会被拦下（「无法验证开发者」），要去「系统设置 → 隐私与安全性」最下面点「仍要打开」 | 双击就开，和普通软件一样 | Mac 上跑 `release-local.sh --iphone` 装进连着的 iPhone |
| 能不能一键连 AI | 能 | 能 | **Mac App Store 不行**：上架必须开沙盒，沙盒里的 app 不能改别的 AI 工具的配置、也不能让 AI 读账本。所以 Mac 版走 B |
| iPhone | 装不了 | 装不了 | 自己的 iPhone 直接装；别人的要先登记 UDID |
| 要花的钱 | 0 | Apple Developer Program 每年 99 €（个人身份就行） | 同一个开发者账号，不另收钱 |

建议：**Mac 用 B，iPhone 用 C**。不上 App Store（2026-11-22 ming 定）。开发者账号下来之前，先用 A 给愿意多点一步的朋友试。

## 要 ming 本人做的（安全相关，Claude 不能代办）

开发者账号已开通（团队 `U33A8DX2JT`）。推荐**在 ming 的 Mac 上本地打包**：证书和公证密码只留在这台 Mac 的钥匙串里，不用往 GitHub 放任何密钥。按顺序：

1. **Xcode 登录开发者账号**：Xcode → 设置（⌘,）→ Accounts → 「+」→ Apple ID，确认能看到团队 U33A8DX2JT。
2. **建证书**：选中账号 → Manage Certificates… → 「+」→ **Developer ID Application**；再「+」一次 **Apple Development**。
3. **公证密码**：<https://appleid.apple.com> → 登录与安全 → App 专用密码 → 生成（名字 xiaxia-notary），然后在终端：
   `xcrun notarytool store-credentials xiaxia-notary --apple-id <Apple ID 邮箱> --team-id U33A8DX2JT --password <专用密码>`
4. **iCloud 容器和 App ID**：通常不用手动，打包时 Xcode 自动注册。报错的话去 developer.apple.com → Certificates, IDs & Profiles → Identifiers：先建 iCloud Container `iCloud.com.srmming.xiaxia-ledger`，再建 App ID `com.srmming.xiaxia-ledger`（iPhone）和 `com.srmming.xiaxia-ledger.mac`（Mac），都勾 iCloud 并选这个容器。
5. **iPhone（不上架）**：不用去 App Store Connect。第一次把 iPhone 用线连到 Mac → 点「信任这台电脑」→ iPhone 设置 → 隐私与安全性 → **开发者模式** 打开（会重启一次）。之后跑 `release-local.sh --iphone` 就装上，一年内有效，到期再跑一次。
6. **第一次打包时的弹窗**：钥匙串问 codesign 能不能用密钥，点「始终允许」。
7. **发布**：不上 App Store。dmg 发给别人前，GitHub Release 草稿由 ming 点最后那一下。

别人的 iPhone 想装（不走 TestFlight）：要把那台 iPhone 的 UDID 登记到开发者账号（每年最多 100 台），再给他单独打一份。人多了再考虑 TestFlight（只是私下测试，不是上架）。

做完以后，在 Mac 的仓库目录里：

```
bash scripts/release-local.sh --install   # Mac：签名 + 公证 dmg 到 dist/，并装到 ~/Applications（旧版进废纸篓）
bash scripts/release-local.sh --iphone    # iPhone：装到用线连着的那台 iPhone
```

### 想让 GitHub 自动打包（可选，不推荐先做）

`.github/workflows/release.yml` 在仓库 Secrets 里有下面 6 样时会自动签名公证。要导出证书私钥、上传 API 密钥，安全上不如本地打包，需要时再放：`DEVELOPER_ID_P12`（.p12 的 base64）、`DEVELOPER_ID_P12_PASSWORD`、`APPLE_TEAM_ID`（U33A8DX2JT）、`NOTARY_KEY_P8`、`NOTARY_KEY_ID`、`NOTARY_ISSUER_ID`（App Store Connect → 用户和访问 → 集成 → 团队密钥）。

## iPhone 和 Mac 同步

代码已做好，**签了名、带 iCloud 权限的正式版才生效**。app 启动时会检查自己的签名权限：没签名的开发版、CI 构建，哪怕系统给了容器文件夹，也照样用老位置。原因是苹果不会同步没权限的容器，2026-11-22 在 Mac 上遇到过一次，账本被搬进了一个不同步的文件夹。

- 账本放在 app 自己的 iCloud 容器里（iCloud 云盘里显示为「夏夏账本」app 文件夹），Mac 和 iPhone 用同一个 Apple ID 就看同一本账。
- Mac 第一次开正式版：把老位置（iCloud 云盘根目录「夏夏账本」文件夹）的 ledger.sqlite **复制**进容器，老文件留着当备份，并放一个「已搬家-请看这里.txt」。已经搬过就不再搬。iPhone 先开过、容器里只有空账本的，把空的挪开（改名留着）再搬；容器里已经有流水就不覆盖。
- fin 也认容器：容器里有账本、且老位置已经搬过家（或者本来就没有老账本），就读容器里的，所以 AI 和 app 还是同一份；iPhone 先建了空账本而 Mac 还没搬时，fin 仍读老账本，不会突然变空。
- iPhone 打开时，账本如果还只是 iCloud 占位文件，会先等它下载（最多 15 秒），免得把没下完的当空账本。
- 同一时间两台设备都在改，iCloud 可能留下冲突副本；账本用 DELETE 日志模式（不用 WAL），不会出现只同步了一半的情况。

## 发版前

每次发版前按 [CHECKLIST.md](CHECKLIST.md) 从头跑一遍，其中「8. 连 AI 引导」一节专门查这一页说的流程。

## 发给别人 + 自动更新（2026-11-23 起）

仓库改成私有以后，别人下不到仓库里的东西，所以安装包和更新信息放在一个**只放安装包的公开仓库** `srmming/xiaxia-ledger-releases`（没有源代码）：

- `appcast.xml`：最新版本的清单。别人的 app 里写着它的地址（`SUFeedURL`），每天看一次，有新版就在后台下载，下次退出 / 打开时换好，不弹窗（ming：「软件可以自己更新吗？」）。设置 →「同步」→「更新」里能关自动更新、手动检查；菜单「夏夏账本 → 检查更新…」也能查。换之前会把账本复制到账本旁边的「更新前备份」（留最近 5 份）；更新本身只换 app，不碰账本。
- `download/xiaxia-ledger-<版本>.dmg`：每个版本一份，只留最近 3 个；`download/xiaxia-ledger.dmg` 永远是最新版（下载按钮用）。
- 网址前缀只写在 `App/project.yml` 的 `XIAXIA_UPDATE_BASE` 一处。官网域名定了就换成 `https://<域名>`，`release-share.sh` 会改用 `site/deploy.sh` 上传 dist/。换网址的那一版要先在旧网址发一次，旧版用户才跟得过去。
- 更新包用 Sparkle 的 EdDSA 密钥签名：私钥只在 ming 的 Mac 钥匙串里（Sparkle 的 `generate_keys` 生成），公钥写在 `App/project.yml` 的 `XIAXIA_SPARKLE_PUBLIC_KEY`。私钥丢了，旧版就收不到新版的更新，要让大家重新下载一次，所以钥匙串要和 Mac 一起备份。

发一个新版只要一句（在 Mac 的仓库目录）：

```
bash scripts/release-share.sh 0.2.1            # 编译 → Developer ID 签名 → 公证 → dmg → 写 appcast → 推到 xiaxia-ledger-releases
bash scripts/release-share.sh 0.2.1 --adhoc    # 还没有 Developer ID 证书时：临时签名，别人第一次打开要多点一步
```

版本号每次要比上次大（0.2.0 → 0.2.1）。给别人的包**不带 iCloud 权限**：账本放在对方 iCloud 云盘的「夏夏账本」文件夹（开了 iCloud 云盘时）或「应用程序支持」里，app 和 AI 都读这一份；少了的只是「iPhone 和 Mac 同步」（要开发者账号给每台设备签 iCloud 权限，以后再做）。

### 第一次要 ming 本人点的（按顺序，大约 15 分钟）

1. **建只放安装包的公开仓库**：打开 <https://github.com/new>，名字填 `xiaxia-ledger-releases`，选 **Public**，勾「Add a README file」，点 Create。然后终端：`git clone https://github.com/srmming/xiaxia-ledger-releases ~/xiaxia-ledger-releases`。
2. **Developer ID 证书**：Xcode → 设置（⌘,）→ Accounts → 选你的 Apple ID → Manage Certificates… → 左下「+」→ **Developer ID Application**。
3. **公证用的 App 专用密码**：<https://account.apple.com> → 登录与安全 → App 专用密码 → 生成（名字 xiaxia-notary），复制，然后终端：
   `xcrun notarytool store-credentials xiaxia-notary --apple-id <你的 Apple ID 邮箱> --team-id U33A8DX2JT`，提示输密码时粘贴。
4. **第一次签名时钥匙串弹窗**：问 codesign 能不能用密钥，输开机密码，点「始终允许」。

做完告诉 Claude，Claude 跑 `release-share.sh 0.2.0`，出来的 dmg 双击就能开、以后自动更新。
