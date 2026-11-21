# 图标草稿 v2

打开 `preview.html` 一次看全部（或看 `preview.png`）。

## 风格
- layered two-tone：每个图标只用一个颜色，浅色主体（同色 32% 不透明）+ 实色重点。参考 Kubai Icons 的 Layered 画法，没有复制它的图形。
- 24×24 网格，圆角、实心为主，少量粗描边（2px，圆头）。
- `tabs/`：Tab 栏和 Mac 侧边栏用，颜色是 `currentColor`，跟随系统强调色或 SwiftUI 的 `.foregroundStyle`。
- `categories/`：记账分类，每个分类有固定颜色，见 `manifest.json`。
- `png/`：72×72（24pt @3x）透明底导出，tab 的 PNG 用珊瑚色 #FF7A59 预览。

## 接进 SwiftUI
SVG 可以直接拖进 Asset Catalog（勾选 Preserve Vector Data），tab 图标设为 Template Image 就能跟着 tint 变色。
以后如果要做成自定义 SF Symbol（能用符号动画 `.symbolEffect`），再按 Apple 的符号模板重画一版。

## 待定
- App 图标三选一，见 `../logo/v2/`。
- 分类表以开发线程最终定的默认分类为准，缺的再补。
