<p align="center"><img src="design/logo/app-icon-1024.png" width="128" alt="夏夏账本"></p>

# 夏夏账本 · Xiaxia Ledger

一份本地账本，两个入口：

- **给人用**：原生 SwiftUI 的 Mac（之后 iPhone）app，看图表、随手记账、确认 AI 的改动。
- **给 AI 用**：`fin` 命令行（之后加 MCP），一连上就懂你的财务，能导入对账单、去重、分类、对账、出月报。

两边读写同一份数据，AI 导入后 app 里马上能看到。拿不准的事 AI 在对话里先问你，app 里不设「待确认」；每次改动都有记录，可以撤销。支持多账本（比如「个人」和「店铺」），账本间转账汇总时自动抵消。

> A local-first personal & small-business ledger for macOS. Native SwiftUI app for humans, `fin` CLI for AI agents, one shared core.

## 隐私

这是公开仓库，**只放代码**。真实流水、对账单、账本文件一律不进仓库（见 `.gitignore`）。账本是一个 SQLite 文件，
默认在 iCloud 云盘的「夏夏账本/ledger.sqlite」（没开 iCloud 云盘就在 `~/Library/Application Support/XiaxiaLedger/`），
app 和 `fin` 读写同一份。旧的 `ledger.json` 第一次打开时会自动搬进 SQLite，原文件留作备份。

## 结构

```
Sources/
  FinanceCore/      共享核心：模型、金额（分为单位）、汇总口径、去重、存储
  fin/              命令行，给 AI 用（每个命令都支持 --json）
  XiaxiaLedgerApp/  Mac app（SwiftUI 外壳；页面按 design/ 的设计稿做）
Tests/              单元测试（只用编造数据）
design/             logo、界面设计稿
skills/fin/         给 AI 的使用说明（skill）
docs/               路线图和决定记录
```

## 运行（需要 macOS 14+、Xcode 16+）

```bash
swift build
swift test
swift run fin context          # 说明书：账本、账户、口径
swift run XiaxiaLedgerApp -XiaxiaDemo   # Mac 开发版，用编造的示例账本
cd App && xcodegen generate && open XiaxiaLedger.xcodeproj   # iOS / Mac 正式工程
swift run fin summary --month 2026-11 --book miora
swift run XiaxiaLedgerApp      # 打开 Mac app（也可以用 Xcode 打开 Package.swift 再运行）
```

用 `XIAXIA_LEDGER_PATH=/path/to/test.json` 可以指向一份测试账本。

## 现在能做什么

| 命令 | 状态 |
| --- | --- |
| `fin context` / `books` / `accounts` / `tx` / `summary` | ✅ 可用 |
| `fin debts` / `installments` / `goals`（谁欠我钱、分期、目标和储蓄，只读） | ✅ 可用 |
| `fin add`、`fin debt add` / `repay`（记一笔、记欠款、记还款）、`fin account add [--private]`（私房钱） | ✅ 可用 |
| `fin history` / `undo`（改动记录、撤销） | ✅ 可用 |
| iPhone + Mac app（App/，XcodeGen 生成工程） | 🚧 第一版界面 |
| `fin import`（Revolut CSV、通用 CSV，自动去重）、`categorize`、`assign`、`transfer link/new` | ✅ 写好，待 Mac 上编译验证 |
| `fin mcp`（MCP 服务，给 Claude 桌面版、Codex、DeepSeek 用） | ✅ 写好，待验证 |
| 所有写入命令都能加 `--dry-run` 预演 | ✅ |

路线图见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 许可

MIT
