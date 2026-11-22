# 夏夏图标和组件（icon kit）

夏夏账本自己画的一整套图标，全部原创：分类 46 个、账户 5 个、导航 9 个、操作 24 个、小徽章 10 个，
夏夏（头顶嫩叶的小太阳）四种性格 + 五种心情，11 张空状态插画。

- 在线看：https://claude.ai/artifact/Asb5hqx7Uoq2Q25uFQooFA （ming 分享后别人才能打开）
- `index.html`：展示页，浏览器直接打开（由 `template.html` + 图标数据生成）。
- `icons.py` / `mascot.py`：图标源头，每个图标几行，用圆角矩形、圆、磨圆多边形拼出来。
- `palette.py`：颜色（浅色、深色各一套）。
- `build.py`：改完跑 `python3 design/icon-kit/build.py`，一次生成：
  - `svg/<分组>/<名字>.svg`（浅色版）
  - `glyphs.json`
  - `index.html`
  - `Sources/LedgerUI/XiaGlyphData.swift`、`XiaPaletteData.swift`（app 用，别手改）
- app 里怎么用：`Sources/LedgerUI/XiaIcons.swift` 顶部有组件一览（XiaIcon、XiaTile、AccountIcon、XiaxiaAvatar、XiaxiaIllustration、XiaBadge、`XiaGlyph.image(size:)`）。

画法：24 格（夏夏 64，插画 160×120），浅色主体（同色 34%，深色 42%）在后、实色重点在前、左上一道白色反光；
所有角磨圆，线条圆头，描边 1.2–2.4；每个图标最多一处小爱心或小星星。

分类名 → 图标的对应在 `Sources/LedgerUI/Components.swift` 的 `CategoryStyle.glyphs`，对不上就按开头找，再不行用「其他」。
