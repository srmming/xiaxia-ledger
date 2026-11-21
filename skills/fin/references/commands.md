# fin 命令和 MCP 工具对照

账本位置可以用环境变量 `XIAXIA_LEDGER_PATH` 改（测试时指向临时文件，`.json` 结尾用 JSON）。写入作者也可以用 `XIAXIA_AUTHOR` 设。所有查询命令加 `--json` 输出 JSON；所有写入命令都能加 `--dry-run` 预演、`--author` 写明是谁。

负数金额在命令行里要放在 `--` 后面（`fin add --account cash --book personal -- -12,50 超市`），否则会被当成选项。

金额写 `-12,50`、`-12.50`、`1.234,56` 都行；负数支出、正数收入（借款、还款、目标的金额写正数）。日期写 `2026-11-21`，月份写 `2026-11`。流水编号、改动编号都用前 8 位。

## 查

| 想做的事 | 命令行 | MCP |
| --- | --- | --- |
| 说明书（先看这个） | `fin context [--json]` | `context` |
| 账本列表 | `fin books` | 在 `context` 里 |
| 账户和余额 | `fin accounts` | 在 `context` 里 |
| 查流水 | `fin tx [--book miora] [--account caixa] [--month 2026-11] [--category 餐饮] [--limit 50]` | `list_transactions`（还能 `query` 搜说明；私房钱要 `include_private`） |
| 月度收支和分类 | `fin summary --month 2026-11 [--book personal]` | `summary` |
| 谁欠我、我欠谁 | `fin debts [--all]` | `debts` |
| 分期 | `fin installments` | `installments` |
| 目标和储蓄 | `fin goals` | `goals` |
| 改动记录 | `fin history [--limit 20]` | `history` |

`fin tx` 每行：`编号 日期 金额 账本 分类 说明`；JSON 字段是 `id date amount description accountID bookID category transferID source flow`，`bookID`/`category` 为空表示还没整理。

## 写

| 想做的事 | 命令行 | MCP |
| --- | --- | --- |
| 记一笔 | `fin add --account cash --book personal [--category 餐饮] [--date …] -- -12,50 超市`（负数前要有 `--`） | `add_transaction` |
| 借出 / 借入 | `fin debt add 阿华 500 --they-owe-me｜--i-owe [--account cash] [--due …] [--note …] [--book personal]` | `add_debt`（`direction`: `they_owe_me` / `i_owe`） |
| 还款 | `fin debt repay 阿华 100 --account cash` | `repay_debt` |
| 改分类 | `fin categorize --category 餐饮 <编号…>` | `categorize` |
| 分账本 | `fin assign --book miora <编号…>` | `assign_book` |
| 自己账户间挪钱 | `fin transfer move 50 --from-account caixa --to-account cash` | 暂无，用命令行 |
| 已导入的标成互转 | `fin transfer mark <编号…> [--counter-account cash]` | 暂无 |
| 账本间转账 | `fin transfer new 200 --from miora --to personal --account caixa`；已有两笔：`fin transfer link <转出> <转入>` | 暂无 |
| 导入对账单 | `fin import 文件.csv --account revolut --format revolut`；通用：`--date-col --amount-col｜--debit-col --credit-col --desc-col [--skip-rows] [--category-col --book-col --flow-col] [--book]` | `import_statement` |
| 加账户 | `fin account add stash 私房钱 --kind bank｜credit｜cash｜wallet｜savings [--private]` | 暂无 |
| 分期 | `fin installment add 名称 总额 --count 6 --account … --book … [--first] [--fee] [--category]`；`fin installment pay 名称 [--tx 编号] [--amount]` | `add_installment`、`pay_installment` |
| 目标 | `fin goal add 名称 金额 [--savings-account] [--locked] [--deadline]`；`fin goal deposit 名称 金额 --from 账户`；`fin goal withdraw 名称 金额 --to 账户` | `add_goal`、`goal_deposit`（取钱暂无） |
| 撤销 | `fin undo <改动编号>` | `undo` |

## 还做不到的（要做就告诉 ming，别绕过去直接改文件）

- 删除或修改一笔流水的金额、日期、说明（app 里能改；命令行只能 `undo` 整条改动）。
- 按日期范围、按全年汇总（按月跑 `summary` 再加）。
- 直接把账户余额校准到某个数。
