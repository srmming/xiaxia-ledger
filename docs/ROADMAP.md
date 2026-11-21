# 路线图

## 第一版（Mac + CLI）

- [x] 工程骨架：FinanceCore + fin + Mac app 外壳 + 测试
- [x] logo、界面设计稿初稿（design/）
- [ ] 界面设计稿定稿（ming 看过再写页面代码）
- [x] 正式存储：SQLite，放 iCloud 云盘「夏夏账本」，app 和 CLI 读同一份；旧 JSON 自动迁移
- [x] 导入框架：Revolut CSV、通用 CSV（列名可配），自动去重，整批能撤销
- [ ] 用真实 CaixaBank、imagin 导出文件确认列名（等 ming 同意读对账单）
- [ ] 改动记录：每次写入记下谁改的、改了什么，`fin undo` 和 app 里都能撤销
- [ ] Mac 页面：总览、趋势、分类、流水（搜索、筛选）、改动记录、导入
- [x] `fin` 写入命令 + skill（add、debt、categorize、assign、transfer、import、undo，都能 --dry-run）
- [x] MCP 服务 `fin mcp`（stdio）
- [x] 借款往来、分期、目标的数据模型和只读命令（`fin debts` / `installments` / `goals`）
- [x] 记欠款、记还款、私房钱（`fin debt add/repay`、`fin account add --private`）
- [x] `fin add`、`fin history`、`fin undo`
- [x] iPhone + Mac app 第一版界面（总览、流水、记一笔、计划、改动记录、设置）
- [x] 分期写入：`fin installment add/pay`（买的那天全额算支出，每期还款算还债）
- [x] 目标写入：`fin goal add/deposit/withdraw`（储蓄账户、划出两种都支持，锁定的不能取）
- [ ] 导入 1–11 月真实流水核对

## 第二版

目标和储蓄的 app 页面与提醒（到期、扣款日）；Apple Pay 快捷指令自动记、小组件。

## 以后

- 宝宝存钱小游戏：假装养一个宝宝从出生到长大，随机事件「要花钱」，但钱其实转进锁定储蓄（`Goal.locked`）不能动。

## 第三版

银行自动同步、给 gestoría 的季度材料、共享账本。

## 决定记录

- 2026-11-21：名字「夏夏账本」，公开仓库 srmming/xiaxia-ledger，MIT。
- 2026-11-21：界面用原生 SwiftUI + Swift Charts。
- 2026-11-21：金额用整数「分」存；显示西班牙格式 1.234,56 €（自己实现，系统 es_ES 四位数不加千分位）。
- 2026-11-21：骨架先用 JSON 文件存储（接口 `LedgerStore`），正式方案另定。
- 2026-11-21：不做「待确认」队列（ming 定）。app 主要给 Codex、Claude、DeepSeek 这类 AI 工具通过 CLI/MCP 对接；要确认的事在对话里说清楚，确认后直接写，靠改动记录撤销兜底。
- 2026-11-21：自用分发，不上 Mac App Store（避开沙盒，CLI 能直接读账本）。
- 2026-11-21：加「谁欠我钱、分期、目标和储蓄」。借贷和存进目标的钱不算收支；分期每期扣款算支出（后来改了，见下面）。借款往来和分期放第一版，目标和储蓄的数据和命令第一版就有，页面和提醒放第二版（可调整）。
- 2026-11-21：ming 定：不再改设计稿，直接开发 iOS 和 Mac app，界面以后再改；借款只做记欠款、记还款；加私房钱（账户默认隐藏、不进总览）；宝宝存钱小游戏以后做，数据先留锁定储蓄。
- 2026-11-21：改分期口径（ming 同意推荐）：买的那天按全额记支出，之后每期还款是还债（不进收支），手续费和利息单独记支出。取代前面「每期扣款算支出」。
- 2026-11-21：正式存储定为 SQLite，放 iCloud 云盘「夏夏账本」文件夹，用 DELETE 日志模式（不用 WAL，避免 iCloud 单独同步 -wal 文件）；同一时间只在一台设备上写，iPhone 接 iCloud 时再换 CloudKit。
- 2026-11-21：目标的钱放哪（ming 同意推荐）：两种都支持。挂了专门储蓄账户的按那个账户余额算；没挂的在现有账户里划出，每笔存入单独记。
