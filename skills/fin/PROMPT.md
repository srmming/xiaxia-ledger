# 夏夏账本 · 通用提示词

给没有 skill 机制的 AI 工具用（Codex 的 AGENTS.md、Gemini 的 GEMINI.md、DeepSeek / Qwen / Kimi 的全局指令等）：把下面「---」之间整段贴进去。`scripts/install-global.sh` 会自动把它写进已装工具的全局指令文件。

---

## 夏夏账本（ming 的财务）

ming 的个人和 Miora 美甲店财务（西班牙，欧元）记在「夏夏账本」里：iCloud 云盘「夏夏账本/ledger.sqlite」，Mac app、命令行 `fin`（`~/.local/bin/fin`）和 MCP 服务 `xiaxia-ledger`（`fin mcp`）读写同一份。账本 `personal`（个人）、`miora`（店里）。

ming 说到记一笔、花了多少、收支、余额、月报、对账、导入对账单、分类、店里还是个人、谁欠我钱、还款、分期、存钱目标、私房钱，或者 Caixa、imagin、Revolut、MyCard 时：

1. 先跑 `fin context`（或 MCP 工具 `context`），按里面的账户 id 和统计口径来；命令不熟就看 `fin --help`、`fin <命令> --help`。完整说明在 `~/.agents/skills/fin/SKILL.md`。
2. 拿不准的（哪个账户、个人还是店里、什么分类、是不是自己账户互转）先在对话里问 ming，确认后再写。
3. 导入和批量修改先加 `--dry-run` 预演给 ming 看，同意后再正式写；写入加 `--author 你的名字`，写完告诉他改动编号，写错用 `fin undo <编号>` 撤销。
4. 只用 fin / MCP 写，不直接改账本文件。命令行里负数金额要放在 `--` 后面：`fin add --account cash --book personal -- -12,50 超市`。
5. 不算收支的：借款和还款、存取目标、自己账户之间转钱、分期每期还款；分期买的那天按全额算支出；退款冲减原分类的支出。
6. 私房钱账户只在 ming 本人问时提，给店里或 gestoría 的报表不算进去。
7. 金额显示成 1.234,56 €。真实数字不贴到公开地方、不提交进 git。连不上 fin 时直接说，不要编数字。

---
