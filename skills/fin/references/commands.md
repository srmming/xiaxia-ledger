# fin 命令和 MCP 工具对照

账本位置可以用环境变量 `XIAXIA_LEDGER_PATH` 改（测试时指向临时文件，`.json` 结尾用 JSON）。写入作者也可以用 `XIAXIA_AUTHOR` 设。所有查询命令加 `--json` 输出 JSON；所有写入命令都能加 `--dry-run` 预演、`--author` 写明是谁。

负数金额可以直接写：`fin add -12,50 超市 --account cash --book personal`。作为选项值的负数要写等号：`--amount=-12,50`、`--balance=-100`。

金额写 `-12,50`、`-12.50`、`1.234,56` 都行；负数支出、正数收入（借款、还款、目标的金额写正数）。日期写 `2026-11-21`，月份写 `2026-11`。流水编号、改动编号都用前 8 位。

## 查

| 想做的事 | 命令行 | MCP |
| --- | --- | --- |
| 说明书（先看这个） | `fin context [--json]` | `context` |
| 账本文件在哪 | `fin where` | — |
| 账本列表 | `fin books` | 在 `context` 里 |
| 账户和余额 | `fin accounts` | `accounts` |
| 查流水 | `fin tx [--include-private] [--book miora] [--account caixa] [--month 2026-11] [--category 餐饮] [--limit 50]` | `list_transactions`（还能 `query` 搜说明；私房钱要 `include_private`） |
| 收支和分类汇总 | `fin summary --month 2026-11｜--year 2026｜--from 2026-01 --to 2026-06 [--book personal] [--include-private]`（JSON 字段：period book income expense net byCategory months） | `summary`（month 或 year 或 from+to） |
| 谁欠我、我欠谁 | `fin debts [--all]` | `debts` |
| 分期 | `fin installments` | `installments` |
| 目标和储蓄 | `fin goals` | `goals` |
| 月报（直接能读） | `fin report [--month 2026-11] [--book miora] [--include-private]` | `monthly_report` |
| 对账（只看不改） | `fin reconcile --account revolut --balance 105,84 [--date …]` | `reconcile` |
| 改动记录 | `fin history [--limit 20]` | `history` |

`fin tx` 每行：`编号 日期 金额 账本 分类 说明`；JSON 字段是 `id date amount description accountID bookID category transferID source flow`，`bookID`/`category` 为空表示还没整理。

## 写

| 想做的事 | 命令行 | MCP |
| --- | --- | --- |
| 记一笔 | `fin add -12,50 超市 --account cash --book personal [--category 餐饮] [--date …]` | `add_transaction` |
| 借出 / 借入 | `fin debt add 阿华 500 --they-owe-me｜--i-owe [--account cash] [--due …] [--note …] [--book personal]` | `add_debt`（`direction`: `they_owe_me` / `i_owe`） |
| 还款 | `fin debt repay 阿华 100 --account cash` | `repay_debt` |
| 改分类 | `fin categorize --category 餐饮 <编号…>` | `categorize` |
| 新建分类 / 换图标 | 只有 MCP | `add_category`（可带 `icon`）、`set_category_icon`；图标名先用 `list_category_icons` 查 |
| 分账本 | `fin assign --book miora <编号…>` | `assign_book` |
| 改一笔 | `fin edit <编号> [--amount=-12,50] [--text] [--date] [--account] [--book] [--category]` | `edit_transaction` |
| 删流水 | `fin rm <编号…>`（先 `--dry-run`） | `delete_transactions` |
| 自己账户间挪钱 | `fin transfer move 50 --from-account caixa --to-account cash` | `account_transfer` |
| 已导入的标成互转 | `fin transfer mark <编号…> [--counter-account cash]` | `mark_account_transfer` |
| 账本间转账 | `fin transfer new 200 --from miora --to personal --account caixa`；已有两笔：`fin transfer link <转出> <转入>` | `book_transfer`（新记） |
| 导入对账单 | `fin import 文件.csv --account revolut`（Revolut 自动认）；通用：`--date-col --amount-col｜--debit-col --credit-col --desc-col [--skip-rows] [--category-col --book-col --flow-col] [--book]` | `import_statement` |
| 加账户 | `fin account add stash 私房钱 --kind bank｜credit｜cash｜wallet｜savings [--private]` | `add_account`（可带 `opening_balance`） |
| 开账余额 | `fin account opening caixa 382,64 [--date …]`（信用卡欠款写负数） | `set_opening_balance` |
| 分期 | `fin installment add 名称 总额 --count 6 --account … --book … [--first] [--fee] [--category]`；`fin installment pay 名称 [--tx 编号] [--amount]` | `add_installment`、`pay_installment` |
| 目标 | `fin goal add 名称 金额 [--savings-account] [--locked] [--deadline]`；`fin goal deposit 名称 金额 --from 账户`；`fin goal withdraw 名称 金额 --to 账户` | `add_goal`、`goal_deposit`、`goal_withdraw` |
| 多币种 | `fin fx`；`fin fx update`；`fin fx account 账户 USD`；`fin fx set-rate <编号> --bank 46,12｜--rate 0,925`；`fin fx base USD`；记一笔带原价 `fin add … --original "50 USD"`；外币账户 `fin account add … --currency USD` | `currency`、`update_rates`、`set_account_currency`、`set_rate`、`set_base_currency`、`add_transaction` 的 `original`、`add_account` 的 `currency` |
| 订阅 | `fin subscriptions [--all]`；`fin subscription find`；`fin subscription add 名称 金额 --next 日期 [--cycle weekly｜monthly｜quarterly｜yearly] [--account] [--book] [--category] [--match 关键词] [--currency]`；`fin subscription edit 名称 [--amount …]`；`fin subscription cancel 名称`；`fin subscription remove 名称` | `subscriptions`、`find_subscriptions`、`add_subscription`、`edit_subscription`、`remove_subscription` |
| 撤销 | `fin undo <改动编号>` | `undo` |

## 还做不到的（要做就告诉 ming，别绕过去直接改文件）

- 转账、借款、分期、目标里的流水不能 `edit`，要先 `undo` 再重记。
- MCP 里没有 `transfer link`（把已有两笔标成账本间转账），用命令行。
