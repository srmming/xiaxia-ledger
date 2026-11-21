# 夏夏账本 · 给 AI 协作者的说明

- 全程用中文和 ming 沟通。方案原文在 ming 的 Notion「💶 财务 App 方案」，项目进度在 Notion「项目 / 夏夏账本」。
- **公开仓库**：绝不提交真实流水、对账单、账本文件、截图里的真实金额。测试只用编造数据。
- 核心逻辑只写在 `Sources/FinanceCore`；app 和 `fin` 只调用它，不各写一套规则。
- 金额一律用 `Money`（整数分），显示用 `Money.formatted`（1.234,56 €）。
- 界面：苹果原生 SwiftUI 组件，按 HIG；页面先有设计稿（design/）并经 ming 确认再写代码；每页过 docs 里的界面标准清单（有数据/空/加载/出错、深浅色、大字号、窗口缩放、VoiceOver、快捷键）。
- AI 写入一律先进「待确认」，不直接改账。
- 改动后跑 `swift build && swift test`。
