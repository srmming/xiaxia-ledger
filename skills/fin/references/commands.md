# fin 命令和 MCP 工具对照

账本位置可以用环境变量 `XIAXIA_LEDGER_PATH` 改（测试时指向临时文件，`.json` 结尾用 JSON）。写入作者也可以用 `XIAXIA_AUTHOR` 设。所有查询命令加 `--json` 输出 JSON；所有写入命令都能加 `--dry-run` 预演、`--author` 写明是谁。

负数金额可以直接写：`fin add -12,50 超市 --account cash --book personal`。作为选项值的负数要写等号：`--amount=-12,50`、`--balance=-100`。

金额写 `-12,50`、`-12.50`、`1.234,56` 都行；负数支出、正数收入（借款、还款、目标的金额写正数）。日期写 `2026-11-21`，月份写 `2026-11`。流水编号、改动编号都用前 8 位。

## 查

| 想做的事 | 命令行 | MCP |
| --- | --- | --- |
| 说明书（先看这个） | `fin context [--json]` | `context` |
| 账本文件在哪 | `fin where` | — |
| 装进 / 检查 AI 工具 | `fin setup [--dry-run] [--check] [--remove]`（MCP、skill、提示词一次装好，最后自检）；只连 MCP：`fin connect --list`、`fin connect codex` | — |
| 账本列表 | `fin books` | 在 `context` 里 |
| 账户和余额 | `fin accounts` | `accounts` |
| 查流水 | `fin tx [--include-private] [--book shop] [--account daily] [--month 2026-11] [--category 餐饮] [--limit 50]` | `list_transactions`（还能 `query` 搜说明；私房钱要 `include_private`） |
| 收支和分类汇总 | `fin summary --month 2026-11｜--year 2026｜--from 2026-01 --to 2026-06 [--book personal] [--include-private]`（JSON 字段：period book income expense net byCategory months） | `summary`（month 或 year 或 from+to） |
| 谁欠我、我欠谁 | `fin debts [--all]` | `debts` |
| 分期 | `fin installments` | `installments` |
| 目标（1 大 3 小、哪天到手、要问的事） | `fin goals` | `goals` |
| 月报（直接能读） | `fin report [--month 2026-11] [--book shop] [--include-private]` | `monthly_report` |
| 对账（只看不改） | `fin reconcile --account revolut --balance 105,84 [--date …]` | `reconcile` |
| 改动记录 | `fin history [--limit 20]` | `history` |
| 夏夏的记忆 | `fin memory [list] [--kind rule｜topic｜lesson] [--json]`；`fin memory show <id 或话题名>`；`fin memory search 关键词` | `memory`（不带参数：规矩全文 + 目录；`id`；`query`） |
| 工资、房租等每月固定进出 | `fin regulars [--include-private] [--json]` | `regulars` |

`fin tx` 每行：`编号 日期 金额 账本 分类 说明`；JSON 字段是 `id date amount description accountID bookID category transferID source flow`，`bookID`/`category` 为空表示还没整理。

## 写

| 想做的事 | 命令行 | MCP |
| --- | --- | --- |
| 记一笔 | `fin add -12,50 超市 --account cash --book personal [--category 餐饮] [--date …] [--note …] [--tag 旅行] [--repeat monthly [--until …]]`（金额可写算式 `-12,50-3,20`） | `add_transaction`（`note`、`tags`、`repeat`） |
| 拆开一笔 | `fin split <编号> 30:超市 18,30:日用品[:说明]` | `split_transaction` |
| 复制一笔 | `fin copy <编号> [--date …]` | `duplicate_transaction` |
| 记退款 | `fin refund <编号> [--amount 20]` | `add_refund` |
| 标签 | `fin tag <编号…> --add 旅行 [--remove …]`；查：`fin tx --tag 旅行` 或 `--query "#旅行"` | `tag_transactions`；`list_transactions` 的 `tag` |
| 重复记账 | `fin repeat list｜set <编号> monthly｜run｜pause｜resume｜rm <编号或说明>` | `list_recurring`、`set_recurring`、`update_recurring`、`run_recurring` |

注意：重复记账是 app 打开时自动记上的。导入银行对账单前先看一眼 `fin repeat list` / `list_recurring`：对账单里的房租、话费如果已经被重复记账记过，导完要把重复的那一笔删掉（或者跟用户商量把那条重复记账停掉，以后以对账单为准），别让一笔钱算两次。

| 借出 / 借入 | `fin debt add 阿华 500 --they-owe-me｜--i-owe [--account cash] [--due …] [--note …] [--book personal]` | `add_debt`（`direction`: `they_owe_me` / `i_owe`） |
| 还款 | `fin debt repay 阿华 100 --account cash [--adjust shorten｜lower｜next｜extend]` | `repay_debt`（有计划又多还/少还时先不带 `adjust` 调一次看选项） |
| 欠款改分期（排还款计划） | `fin debt plan 阿华 --per-month 100｜--count 6 [--start 2026-12-20]`；`--clear` 取消 | `plan_debt`；改某一期 `edit_debt_plan`；这期没还 `skip_debt_payment` |
| 改分类 | `fin categorize --category 餐饮 <编号…>` | `categorize` |
| 新建分类 / 换图标 | 只有 MCP | `add_category`（可带 `icon`）、`set_category_icon`；图标名先用 `list_category_icons` 查 |
| 分账本 | `fin assign --book shop <编号…>` | `assign_book` |
| 改一笔 | `fin edit <编号> [--amount=-12,50] [--text] [--date] [--account] [--book] [--category] [--note] [--tags a,b]` | `edit_transaction` |
| 删流水 | `fin rm <编号…>`（先 `--dry-run`） | `delete_transactions` |
| 自己账户间挪钱 | `fin transfer move 50 --from-account daily --to-account cash` | `account_transfer` |
| 已导入的标成互转 | `fin transfer mark <编号…> [--counter-account cash]` | `mark_account_transfer` |
| 账本间转账 | `fin transfer new 200 --from shop --to personal --account daily`；已有两笔：`fin transfer link <转出> <转入>` | `book_transfer`（新记） |
| 导入对账单 | `fin import 文件.csv --account revolut`（Revolut 自动认）；通用：`--date-col --amount-col｜--debit-col --credit-col --desc-col [--skip-rows] [--category-col --book-col --flow-col] [--book]` | `import_statement` |
| 加账户 | `fin account add stash 私房钱 --kind bank｜credit｜cash｜wallet｜savings [--private]` | `add_account`（可带 `opening_balance`） |
| 开账余额 | `fin account opening daily 382,64 [--date …]`（信用卡欠款写负数） | `set_opening_balance` |
| 分期 | `fin installment add 名称 总额 --count 6 --account … --book … [--first] [--fee] [--category]`；`fin installment pay 名称 [--tx 编号] [--amount]` | `add_installment`、`pay_installment` |
| 目标 | `fin goal plan 金额 [--deadline]`；`fin goal add 名称 金额 [--deadline] [--main] [--stash jar\|card\|spot] [--stash-note] [--savings-account] [--locked]`；`fin goal deposit 名称 金额 --from 账户 [--held-back 咖啡]`；`fin goal withdraw 名称 金额 --to 账户`；`fin goal main 名称`；`fin goal check 名称 keep\|pause`；`fin goal rm 名称` | `plan_goal`、`add_goal`、`goal_deposit`、`goal_withdraw`、`set_main_goal`、`goal_check`、`set_goal_stash`、`remove_goal` |
| 多币种 | `fin fx`；`fin fx update`；`fin fx account 账户 USD`；`fin fx set-rate <编号> --bank 46,12｜--rate 0,925`；`fin fx base USD`；记一笔带原价 `fin add … --original "50 USD"`；外币账户 `fin account add … --currency USD` | `currency`、`update_rates`、`set_account_currency`、`set_rate`、`set_base_currency`、`add_transaction` 的 `original`、`add_account` 的 `currency` |
| 订阅 | `fin subscriptions [--all]`；`fin subscription find`；`fin subscription add 名称 金额 --next 日期 [--cycle weekly｜monthly｜quarterly｜yearly] [--account] [--book] [--category] [--match 关键词] [--currency]`；`fin subscription edit 名称 [--amount …]`；`fin subscription cancel 名称`；`fin subscription remove 名称` | `subscriptions`、`find_subscriptions`、`add_subscription`、`edit_subscription`、`remove_subscription` |
| 记住一件事 | `fin memory add 话题 "一句话" [--kind rule｜topic｜lesson] [--source said｜corrected｜confirmed｜observed] [--quote 原话] [--story 经过] [--review-on 2027-03-31] [--link category:工资 account:daily] [--new-topic]`（时间写具体，不写「明年」「下个月」） | `remember` |
| 改记忆 | `fin memory edit <id 或话题名> [--line 行号] [--text …] [--title …] [--kind …] [--review-on 日期｜none] [--pin｜--no-pin] [--keep]` | `update_memory` |
| 删记忆 | `fin memory forget <id 或话题名> [--line 行号]`（能撤销）；`--forever` 彻底忘掉（不能撤销） | `forget_memory`（`forever`） |
| 每月整理记忆 | `fin memory tidy`（列出）；`fin memory tidy --remove <id…>`；`fin memory tidy --done` | `tidy_memory`（`remove`、`done`） |
| AI 意见 | `fin insight add review｜alert｜tip｜good｜action "结论" [--body] [--month] [--book] [--metric]`；`fin insight list [--month] [--book] [--all]`；`fin insight dismiss <编号>` | `add_insight`、`list_insights`、`dismiss_insight`；`ai_status` 看谁最近写过 |
| 账本 | `fin book add 名字 [--kind personal｜business]`；`fin book rename <id> 新名字`；`fin book rm <id> [--move-to <id>]`（先 `--dry-run`） | `add_book`、`rename_book`、`remove_book` |
| 改 / 删账户 | 暂无 | `edit_account`、`remove_account` |
| 分类改名或合并 | 暂无 | `rename_category` |
| 撤销 | `fin undo <改动编号>` | `undo` |

## 还做不到的（要做就告诉用户，别绕过去直接改文件）

- 转账、借款、分期、目标里的流水不能 `edit`，要先 `undo` 再重记。
- MCP 里没有 `transfer link`（把已有两笔标成账本间转账），用命令行。
