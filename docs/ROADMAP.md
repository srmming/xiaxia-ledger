# 路线图

## 第一版（Mac + CLI）

- [x] 工程骨架：FinanceCore + fin + Mac app 外壳 + 测试
- [x] logo、界面设计稿初稿（design/）
- [ ] 界面设计稿定稿（ming 看过再写页面代码）
- [ ] 定正式存储（SQLite / iCloud 同步），保证 app 和 CLI 读同一份
- [ ] 导入 CaixaBank、imagin、Revolut 对账单，自动去重
- [ ] 待确认：AI 改动先进待确认，一键确认 / 撤销，全部留记录
- [ ] Mac 页面：总览、趋势、分类、流水（搜索、筛选）、待确认、导入
- [ ] `fin` 写入命令 + skill
- [ ] 导入 1–11 月真实流水核对

## 第二版

iPhone 随手记、Apple Pay 快捷指令自动记、小组件；MCP。

## 第三版

银行自动同步、给 gestoría 的季度材料、共享账本。

## 决定记录

- 2026-11-21：名字「夏夏账本」，公开仓库 srmming/xiaxia-ledger，MIT。
- 2026-11-21：界面用原生 SwiftUI + Swift Charts。
- 2026-11-21：金额用整数「分」存；显示西班牙格式 1.234,56 €（自己实现，系统 es_ES 四位数不加千分位）。
- 2026-11-21：骨架先用 JSON 文件存储（接口 `LedgerStore`），正式方案另定。
- 2026-11-21：自用分发，不上 Mac App Store（避开沙盒，CLI 能直接读账本）。
