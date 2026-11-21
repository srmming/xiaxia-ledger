---
name: fin
description: 用 fin 命令行查看和整理夏夏账本里的财务数据（账本、账户、流水、月度汇总、借款往来、分期、目标和储蓄）。用户问到收支、余额、某月花销、谁欠我钱、分期还剩多少、存钱进度、对账或导入对账单时使用。
---

# fin：夏夏账本命令行

开始任何财务任务前，先跑：

```bash
fin context --json
```

它会告诉你有哪些账本和账户、数据覆盖的日期、最近改动，以及统计口径。按口径回答，不要自己另定规则。

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `fin books --json` | 列账本 |
| `fin accounts --json` | 列账户和余额 |
| `fin tx --month 2026-11 --book miora --json` | 查流水（可加 `--account`、`--category`、`--limit`） |
| `fin summary --month 2026-11 [--book personal] --json` | 月度收支和分类汇总；不加 `--book` 是「全部」，账本间转账已抵消 |
| `fin debts [--all] --json` | 谁欠我钱、我欠谁：还欠多少、是否过期 |
| `fin installments --json` | 分期：第几期、每期多少、还剩多少、下次扣款日 |
| `fin add -12,50 超市 --account cash --book personal --author Claude` | 记一笔（负数支出、正数收入） |
| `fin debt add 阿华 500 --they-owe-me --account revolut --author Claude` | 记一笔欠款（我欠别人用 `--i-owe`） |
| `fin debt repay 阿华 100 --account revolut --author Claude` | 记一笔还款 |
| `fin account add stash 私房钱 --kind cash --private` | 加账户；`--private` 是私房钱 |
| `fin import 文件.csv --account revolut --format revolut --dry-run` | 导入对账单；先预演，ming 确认后去掉 `--dry-run` |
| `fin categorize --category 餐饮 <编号…>` | 改分类（编号是 `fin tx` 第一列的 8 位） |
| `fin assign --book miora <编号…>` | 分账本 |
| `fin transfer link <转出编号> <转入编号>` / `fin transfer new 200 --from miora --to personal --account cash` | 账本间转账 |
| `fin history` / `fin undo <编号>` | 看改动记录、撤销 |
| `fin goals --json` | 目标和储蓄进度（有专门储蓄账户时按该账户余额算） |

## 规矩

- 金额正数是收入、负数是支出；给人看用 1.234,56 € 格式。
- 借出、借入、还款和存进目标的钱都是「往来」，不算收入也不算支出；分期每期扣款才算支出。
- 用户提到「借给某某」「某某还我」「分期买了」「存进应急金」时，先确认对方、金额、账本，再记。
- 拿不准的事（某笔属于个人还是店里、怎么分类、是不是账本间转账）先在对话里问 ming，确认后再写，不要猜着写。
- 写入会记进改动记录，写明是你（如 Claude / Codex）改的；写错了用 `fin undo` 撤销。
- 任何写入命令都能加 `--dry-run` 预演；批量改动（导入、改一批分类）先预演给 ming 看。
- 写入一律用 fin 命令，并用 `--author` 写清你是谁（Claude、Codex、DeepSeek）；不要手改 ledger.json。
- 私房钱（isPrivate 账户）只在 ming 问到时说，给店里、合伙人、gestoría 的报表不算进去。
- 真实财务数据不要贴到公开地方，也不要提交进 git。
