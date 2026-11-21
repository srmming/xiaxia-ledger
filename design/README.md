# 设计

- `logo/`：App 图标。`app-icon.svg` 是源文件，PNG 是导出的各尺寸（1024 到 16）。
  概念：夏天的太阳（夏夏）从一本打开的账本后升起，右页是上升的柱状图。2026-11-21 ming 选定 v2 的方案 A（晨光账本）作为正式图标。
- `logo/v2/`：App 图标新方案 A/B/C（SVG + 1024 PNG），A 已选定并替换为正式版本，B、C 留作备选。
- `icons/`：tab 图标和记账分类图标草稿（layered two-tone 风格），说明见 `icons/README.md`。
- `ui-kit/`：UI 套件 v1（财务看板版），取代下面的 mockups，见 `ui-kit/README.md`。
- `mockups/`：界面设计稿（风格「原生精致」，可点、带动效）。iPhone：总览、记一笔、流水；Mac：总览、流水。
  在线查看和评论：https://claude.ai/artifact/PqBdUQUreqF6CuDiBqXvgX （需要 ming 分享后别人才能打开）。
  这些 `.dc.html` 是设计画布的源文件，界面里的数字全是编造的示例。

设计稿经 ming 确认后，再按它写 SwiftUI 页面。
