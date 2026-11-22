# 把夏夏账本发给别人

## 别人从零到「对 AI 说一句就记上账」

| 步骤 | 以前（只有 ming 能走通） | 现在 |
|---|---|---|
| 1. 拿到 app | 自己装 Xcode、下代码、编译 | 下载 dmg，把「夏夏账本」拖进「应用程序」 |
| 2. 装 fin（AI 用来读写账本的程序） | 自己编译，跑 `scripts/install-global.sh` | 不用装：app 里自带（`夏夏账本.app/Contents/MacOS/fin`） |
| 3. 让 AI 工具认识账本 | 手动改各家配置文件 | 第一次打开 app 自动弹「连上你的 AI」：认出这台 Mac 上的 Claude 桌面版、Claude Code、Codex、Hermes Agent、Cursor、Gemini CLI，默认勾好，点「连上」 |
| 4. 重开 AI 工具 | — | 引导里写着每个工具要怎么重开（比如 Claude 要 ⌘Q 退出再开） |
| 5. 试一句 | — | 引导里点「复制并打开 Claude」，粘贴发出去；AI 一连上账本，引导页就变绿，记下第一笔会显示出来 |

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

代码已做好，**签了名的正式版才生效**（没签名的开发版和 CI 构建不带 iCloud 权限，仍用老位置）：

- 账本放在 app 自己的 iCloud 容器里（iCloud 云盘里显示为「夏夏账本」app 文件夹），Mac 和 iPhone 用同一个 Apple ID 就看同一本账。
- Mac 第一次开正式版：把老位置（iCloud 云盘根目录「夏夏账本」文件夹）的 ledger.sqlite **复制**进容器，老文件留着当备份，并放一个「已搬家-请看这里.txt」。容器里已经有账本就不再搬、不覆盖。
- fin 也认容器：容器里有账本就读它，所以 AI 和 app 还是同一份。
- iPhone 打开时，账本如果还只是 iCloud 占位文件，会先等它下载（最多 15 秒），免得把没下完的当空账本。
- 同一时间两台设备都在改，iCloud 可能留下冲突副本；账本用 DELETE 日志模式（不用 WAL），不会出现只同步了一半的情况。

## 发版前

每次发版前按 [CHECKLIST.md](CHECKLIST.md) 从头跑一遍，其中「8. 连 AI 引导」一节专门查这一页说的流程。
