# 夏夏图标和组件（icon kit）

夏夏账本自己画的一整套图标，全部原创：分类 138 个（分 12 组：吃喝、出行、住家、购物、健康美容、玩乐、家人人情、学习工作、钱和金融、店里、收入、其他）、
账户 5 个、导航 9 个、操作 24 个、小徽章 10 个，11 张空状态插画。

夏夏的形象不在这里画，另有线程用 ChatGPT 生成（`design/xiaxia-mascot/`）。app 里 `XiaxiaAvatar` 现在是占位（靛蓝圆 + 小星星），出图后只换它的 body。

- 在线看：https://claude.ai/artifact/Asb5hqx7Uoq2Q25uFQooFA （ming 分享后别人才能打开）
- `index.html`：展示页，浏览器直接打开（由 `template.html` + 图标数据生成），里面能点着试「新建分类」面板。
- `icons.py`：图标源头，每个图标几行，用圆角矩形、圆、磨圆多边形拼出来；末尾 `SECTIONS` 是挑图标时的分组（一个图标可以在几组里）。
- `illos.py`：空状态插画（地面影子 + 放大的道具 + 小星星）。
- `palette.py`：颜色（浅色、深色各一套）。
- `build.py`：改完跑 `python3 design/icon-kit/build.py`，一次生成：
  - `svg/<分组>/<名字>.svg`（浅色版）
  - `glyphs.json`
  - `index.html`
  - `Sources/LedgerUI/XiaGlyphData.swift`、`XiaPaletteData.swift`（app 画图用，别手改）
  - `Sources/FinanceCore/CategoryIcons.swift`（分类图标目录：名字、中文名、分组；fin / MCP 用它查图标名）
- app 里怎么用：`Sources/LedgerUI/XiaIcons.swift` 顶部有组件一览（XiaIcon、XiaTile、AccountIcon、XiaxiaAvatar、XiaxiaIllustration、XiaBadge、`XiaGlyph.image(size:)`）。

## 自己建分类、换图标

- app：记一笔里「＋ 新分类」、设置 · 管理分类里「新建分类…」弹出 `CategoryCreator`（先挑图标再填名字，没挑就按名字自动配）；管理分类里点分类前面的图标打开 `CategoryIconEditor` 换图标。都在 `Sources/LedgerUI/CategoryPicker.swift`。
- 账本：挑的图标存在 profile 的自建分类里（`CustomCategory.icon`），走改动记录，能撤销。`Ledger.addCategory(_:income:icon:author:)`、`Ledger.setCategoryIcon(_:icon:author:)`。
- MCP：`list_category_icons` 列出能用的图标；`add_category` 带 `icon`；`set_category_icon`（icon 传空 = 改回自动）。

## 画法

24 格（插画 160×120），浅色主体（同色 34%，深色 42%）在后、实色重点在前、左上一道白色反光；
所有角磨圆，线条圆头，描边 1.2–2.4；每个图标最多一处小爱心或小星星。

分类名 → 图标：先看用户挑过的，再看 `Sources/LedgerUI/Components.swift` 的 `CategoryStyle.glyphs`，对不上就按开头找，再不行用「其他」。
