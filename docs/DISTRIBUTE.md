# 把夏夏账本发给别人

## 别人从零到「对 AI 说一句就记上账」

| 步骤 | 以前（只有 ming 能走通） | 现在 |
|---|---|---|
| 1. 拿到 app | 自己装 Xcode、下代码、编译 | 下载 dmg，把「夏夏账本」拖进「应用程序」 |
| 2. 装 fin（AI 用来读写账本的程序） | 自己编译，跑 `scripts/install-global.sh` | 不用装：app 里自带（`夏夏账本.app/Contents/MacOS/fin`） |
| 3. 让 AI 工具认识账本 | 手动改各家配置文件 | 第一次打开 app 自动弹「连上你的 AI」：认出这台 Mac 上的 Claude 桌面版、Claude Code、Codex、Cursor、Gemini CLI，默认勾好，点「连上」 |
| 4. 重开 AI 工具 | — | 引导里写着每个工具要怎么重开（比如 Claude 要 ⌘Q 退出再开） |
| 5. 试一句 | — | 引导里点「复制并打开 Claude」，粘贴发出去；AI 一连上账本，引导页就变绿，记下第一笔会显示出来 |

没装任何 AI 工具：引导里给「下载 Claude 桌面版」；用 DeepSeek、通义千问、Kimi 的，装 Cherry Studio，再点「复制配置」粘进它的 MCP 设置。别的支持 MCP 的工具同样粘这段。

iPhone 不需要引导：AI 工具只能在 Mac 上接本地账本，手机上只看。（手机和 Mac 看同一本账要等 iCloud 同步做完，见下面「iPhone」。）

app 挪过位置（比如先在「下载」里打开过，后来拖进「应用程序」）：下次打开时自动把各 AI 工具配置里的路径改过来，不用重新连。

## 安装包从哪来

GitHub Actions 里的 **release** 流程（`.github/workflows/release.yml`）：

- 在 Actions 页面手动点「Run workflow」：做一个 dmg，挂在那次运行的 Artifacts 里，自己先下载试。
- 推一个 `v0.2.0` 这样的 tag：除了做 dmg，还建一个 GitHub Release **草稿**，ming 看过再点「Publish」才公开。

## 三种发法

| | A. 未签名 dmg（现在就能发） | B. 签名 + 公证的 dmg（推荐） | C. App Store / TestFlight |
|---|---|---|---|
| 别人打开 | 第一次会被拦下（「无法验证开发者」），要去「系统设置 → 隐私与安全性」最下面点「仍要打开」 | 双击就开，和普通软件一样 | 从 App Store / TestFlight 装 |
| 能不能一键连 AI | 能 | 能 | **Mac App Store 不行**：上架必须开沙盒，沙盒里的 app 不能改别的 AI 工具的配置、也不能让 AI 读账本。所以 Mac 版走 B |
| iPhone | 装不了 | 装不了 | iPhone 只能走这条：TestFlight 先给朋友试，再上 App Store |
| 要花的钱 | 0 | Apple Developer Program 每年 99 €（个人身份就行） | 同一个开发者账号，不另收钱 |

建议：**Mac 用 B，iPhone 用 TestFlight（以后再上 App Store）**。开发者账号下来之前，先用 A 给愿意多点一步的朋友试。

## 要 ming 本人做的（安全相关，Claude 不能代办）

1. **注册 Apple Developer Program**（个人）：<https://developer.apple.com/programs/enroll/>，用自己的 Apple ID（要开双重认证），每年 99 €，审核一般一两天。
2. **建 Developer ID Application 证书**：开发者网站 → Certificates → 「+」→ Developer ID Application（只有账号持有人能建）。在 Mac 的「钥匙串访问」里把证书连私钥导出成 .p12，设一个密码。
3. **建公证用的 API 密钥**：App Store Connect → 用户和访问 → 集成 → App Store Connect API → 团队密钥，「开发者」权限就够。下载 .p8（只能下一次），记下 Key ID 和 Issuer ID。
4. **把这 6 样放进 GitHub 仓库的 Secrets**（仓库 → Settings → Secrets and variables → Actions → New repository secret）：

   | 名字 | 填什么 |
   |---|---|
   | `DEVELOPER_ID_P12` | .p12 文件的 base64（终端里 `base64 -i 证书.p12 \| pbcopy` 后粘贴） |
   | `DEVELOPER_ID_P12_PASSWORD` | 导出 .p12 时设的密码 |
   | `APPLE_TEAM_ID` | 开发者网站右上角 Membership 里的 Team ID（10 位） |
   | `NOTARY_KEY_P8` | .p8 文件的全部文字 |
   | `NOTARY_KEY_ID` | API 密钥的 Key ID |
   | `NOTARY_ISSUER_ID` | API 密钥页面上方的 Issuer ID |

   放好以后 release 流程会自动签名、公证，不用再改代码。
5. **iPhone 走 TestFlight 时**：在 App Store Connect 新建 app（套装 ID `com.srmming.xiaxia-ledger`），加测试的人。给外部测试（不在你团队里的朋友）发，第一个版本要过苹果的 Beta 审核。
6. **发布**：Release 草稿和 App Store 提交，都由 ming 点最后那一下。

## iPhone 和同步（还没做完）

现在的 iPhone 版把账本存在手机本机，**还不会**和 Mac 同步。要「装上、用同一个 Apple ID 就能看到 Mac 上的账」，需要给 app 开 iCloud 容器（iCloud Documents），Mac 和 iPhone 都改用这个容器里的账本。这一步要在开发者账号里开 iCloud 能力，所以排在 ming 注册开发者账号之后做。做的时候 Mac 上已有的账本（iCloud 云盘「夏夏账本」文件夹）会自动搬过去，旧文件留作备份。

## 发版前

每次发版前按 [CHECKLIST.md](CHECKLIST.md) 从头跑一遍，其中「8. 连 AI 引导」一节专门查这一页说的流程。
