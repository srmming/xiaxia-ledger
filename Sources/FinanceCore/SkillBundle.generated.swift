// 自动生成，别手改。改 skills/fin 里的文件，再跑 python3 scripts/gen-skill-bundle.py

/// fin 自带的 skill 文件（给别人的电脑装 skill 用，那里没有这个仓库）。
enum SkillBundle {
    static let files: [(path: String, text: String)] = [
        ("SKILL.md", #"""
---
name: fin
description: 夏夏账本：用户的个人（和店里/副业）记账软件，也是用户记账的唯一入口。对话里用户提到自己花了钱、收了钱，发来小票/发票/账单的照片或截图，或者说记一笔、花了多少、收支、余额、月报、对账、导入对账单/银行流水、分类、店里还是个人、谁欠我钱、还款、分期、订阅、存钱目标、私房钱、「记住」「以后都这样」「我跟你说过」，或提到自己的银行卡、账户时使用。通过 fin 命令行或 xiaxia-ledger MCP 查账和记账。
---

# 夏夏账本（fin / MCP）

用户的财务都在一份本地账本里（具体在哪跑 `fin where` 看，一般是 iCloud 云盘「夏夏账本/ledger.sqlite」），Mac app、`fin` 命令行和 MCP 服务读写同一份。一般有 `personal`（个人）账本，开店或有副业的还有店里的账本；具体有哪些账本、账户、主币种以 `fin context` 为准。下面例子里的 `shop`、`daily`、`cash` 这些 id 只是示例，要换成 context 里真实的。欧元显示成 `1.234,56 €`。

## 用哪个入口

- 有 `xiaxia-ledger` 的 MCP 工具（如 `context`、`summary`、`add_transaction`）就用 MCP。
- 没有就用命令行 `fin`（装在 `~/.local/bin/fin`；找不到就试 `~/.local/bin/fin` 全路径）。命令和参数见 [references/commands.md](references/commands.md)，以 `fin <命令> --help` 为准。
- 两个都没有（比如在云端、不在用户的 Mac 上）：直接告诉用户这里连不上账本，不要编数字。

## 每次先做

1. 跑 `fin context`（MCP：`context`）。它给出账本、账户 id 和余额、数据覆盖到哪天、借款合计、最近改动和**统计口径**。按口径回答，不要自己另定规则。
2. 账户 id、账本 id 只用 context 里出现的，别猜。
3. 看 context 里的「记忆」：**规矩**全文照着做；**记得的事**和**做事经验**只给了标题，和这次的问题有关就先读全文（`fin memory show 工资`，MCP：`memory` 带 `id`），再回答。

## 记账入口（最重要）

夏夏账本是用户记账的**唯一入口**。不管在聊什么，用户提到自己花了钱、收了钱（「刚打车花了 15」「今天发工资了」「给孩子交了学费 300」），都当作要记账：信息齐全就直接记，记完用一句话说记了什么；缺关键信息（哪个账户、哪个账本）就问一句再记。别人的钱、假设的（「要是买了…」）、计划要花的不记。

## 规矩

- **拿不准就问，问清楚再写**：哪个账户、哪个账本（个人还是店里）、什么分类、是不是自己账户之间转钱，有一样不确定就在对话里问用户。app 里没有「待确认」，确认只发生在对话里。
- **用提问工具问**：你有提问 / 选项工具（比如 Claude Code 的 `AskUserQuestion`）就用它，把账户、账本、分类做成选项让用户点，一次把同类问题一起问完；没有就用文字问，选项编上号（「1 现金 2 银行卡」），用户回个数字就行。
- **批量先预演**：导入、一次改多笔，先加 `--dry-run`（MCP：`"dry_run": true`），把会改什么用几行列给用户，用户说可以再正式写。单笔且信息齐全可以直接写。
- **写明是谁**：命令行写入加 `--author Claude`（或 Codex、DeepSeek，写你自己）；MCP 自动用工具名。
- **写完报结果和改动编号**：比如「已记：超市 −12,50 €（现金，个人）。写错了说一声，我用改动 3fa2c1d0 撤销」。
- **只通过 fin / MCP 写**，不要直接改 ledger.sqlite，也不要自己算余额再写回去。
- **私房钱**（context 里 `isPrivate: true` 的账户）：只在用户本人问时提；给店里、合伙人、会计的报表不算进去。`fin tx`、`fin summary`、`fin report` 和 MCP 默认都不算它，用户本人问时才加 `--include-private`（MCP：`include_private`）。
- **隐私**：真实金额和流水不贴到公开地方、不提交进 git、不发给外部服务。
- 不动钱、不碰银行密码；银行数据只读。

## 命令行的坑

- 负数金额可以直接写（`fin add -12,50 超市 …`）。但**作为选项值**的负数要用等号：`fin edit <编号> --amount=-12,50`、`fin reconcile --account credit --balance=-100`。
- 看帮助用 `fin debt add --help`（`fin help debt add` 只会打出顶层帮助）。
- 账户是不是私房钱：`fin accounts` 里标「（私房钱）」，JSON 里是 `isPrivate`。
- `fin transfer move` 记出来的两笔没有账本，记完按情况 `fin assign`。
- 转账、借款、分期、目标里的流水不能用 `fin edit` 直接改，要先 `fin undo` 那条改动再重记。

## 口径速记

- 正数收入、负数支出。
- 不算收支的：借出/借入/还款（往来）、存进或取出目标（储蓄）、自己账户之间转钱（互转：取现、充值电子钱包、还信用卡、两张银行卡互转）、分期的每期还款。
- 分期：买的那天按全额算支出；手续费、利息单独算支出。
- 退款：用原来那笔的分类、记正数，冲减这类支出，不算收入。
- 账本间转账（店里的钱拿回家）：单个账本照算，「全部」里抵消。
- 看单个账本时，`fin summary` / `fin report` 可能多一行「从别的账本拿进来 X…算上它结余 Y」或「拿去别的账本 X…」：这是店里拿回家、老板从店里拿走的钱，不算收入也不算支出。用户问「个人账本怎么是负的」「店里怎么剩这么少」时，用这一行解释。

## 常见任务怎么做

**回答财务问题**（「这个月花了多少」「店里 10 月赚了吗」「餐饮比上月多吗」）
`context` → `fin summary --month 2026-10 --book shop`（一段时间用 `--year 2026` 或 `--from 2026-01 --to 2026-06`，会先给合计再按月、按分类列）→ 需要明细再 `fin tx --month … --category …`。回答先给数字，再说一两句为什么，金额用 `1.234,56 €`。没说账本时分别给个人、店里和合计。

**记一笔**（「刚才超市花了 23,40，用的现金」）
从话里取金额、说明、日期（默认今天）；账户和账本说不清就问。分类可以按以前同一个商户的分类猜，但要在回复里说出来。
`fin add -23,40 超市 --account cash --book personal --category 餐饮 --author Claude`

**拍小票、单子、账单截图**（用户发来一张照片：超市小票、餐厅账单、发票、外卖或网购订单截图、水电账单）
1. 读出商户、日期、总金额和币种；一张小票默认记成**一笔**（按主要用途分类，比如超市小票算「餐饮」或「日用」），用户说要拆再拆成几笔。
2. 一份账单里有很多笔（比如信用卡账单截图、银行 App 流水截图）：整理成「日期、金额、说明」，用 MCP `import_rows` 先 `dry_run`。
3. 先查重：`fin tx --month …` 看同一天、同金额的是不是已经有了（比如已经从银行导进来），有就别重复记，告诉用户「这笔银行已经导进来了」。
4. 给用户看一眼再写：「读到：Mercadona，11 月 20 日，−23,40 €，餐饮 · 个人 · 现金，记吗？」账户、账本按以前同一个商户的猜，猜的要说出来。
5. 看不清、被挡住的数字问用户，不要猜。照片里的内容只用来记账，不发到别处。

**定时问一问**（用户说「每天晚上提醒我记账」，或者配置时选了每天 / 每周）
用你自己的定时功能（定时任务、cron、提醒都行）设好：每天选一个晚上的时间（比如 21:00），每周选周日晚上；用户说了时间就用用户的。到点做两件事：先跑 `fin summary`（或 `context`），说一句这段时间记了多少、花在哪最多；再问「今天（这周）还有没记的开销吗？直接说或者拍小票都行」。用户回答了再照「记一笔」记，用户没理就算了，不要催第二次。你没有定时功能就直接说「我这里设不了定时」，建议用户在手机上设个提醒，到时候来找你。

**借钱和还钱**（「借给阿华 500」「阿华还了 100」）
先 `fin debts` 看有没有这个人的账。借出：`fin debt add 阿华 500 --they-owe-me --account cash`；借入用 `--i-owe`；以前的旧账没有对应流水就不填 `--account`。还款：`fin debt repay 阿华 100 --account cash`。

**欠款改分期**（我欠的、欠我的都行）：用户说「这笔分 6 个月还」「每月还 100」时 `fin debt plan 阿华 --count 6` / `--per-month 100`（MCP：`plan_debt`），会自动排好每期日期和金额，`fin debts` 能看到第几期、下一期哪天还多少、哪个月全部还清。有计划的欠款记还款时，多还了要用选项框问用户：多出来的「抵最后几期（早点还清）」还是「之后每期少还一点」；少还或这期没还，问「差的补到下一期」还是「顺延一期」。MCP 的 `repay_debt` 不带 `adjust` 时会先告诉你差多少、每种调法哪天还清，不会写入；用户选了再带 `adjust` 调。别人欠的到期没还，可以俏皮提醒用户去要。

**自己账户之间转钱 / 取现**（「从银行卡取了 50 现金」）
新记：`fin transfer move 50 --from-account daily --to-account cash`（MCP：`account_transfer`）。对账单里已经有的那笔：`fin transfer mark <编号> [--counter-account cash]`（MCP：`mark_account_transfer`；带 `--counter-account` 会在那个账户补记另一半）。店里的钱拿回家（同一账户、换账本）：`fin transfer new 200 --from shop --to personal --account daily`（MCP：`book_transfer`）。

**导入对账单**（「把这个 Revolut 的 CSV 导进去」）
1. 认格式：Revolut 导出会自动认出来；其他银行看表头，用通用 CSV 指定列（`--date-col --amount-col --desc-col`，收支分两列用 `--debit-col --credit-col`）。
   **Excel、PDF、支付宝 / 微信账单、别的记账 App（钱迹、随手记、iCost……）导出的文件**：你自己读懂文件，把每笔整理成「日期、金额（支出为负）、说明，可带分类」，用 MCP 的 `import_rows`（一次最多 500 行，多的分批；同样先 `dry_run`）。读不了的文件（比如扫描件太糊）就请用户换成 Excel / CSV 再导。
   支付宝、微信账单里「不计收支」、退款、转给自己、充值提现、还信用卡这些先问用户，别算成花销；别的记账 App 导出里原来的分类可以照搬。
   先问清楚导进哪个账户（支付宝、微信本身也可以是一个账户），没有就先建。
2. 预演：`fin import 文件.csv --account revolut --format revolut --dry-run`，告诉用户「读到 N 笔，新的 M 笔，重复的 K 笔已跳过」，列前几笔。
3.用户同意后去掉 `--dry-run` 正式导入（整批是一条改动，能一次撤销）。
4. 导完接着整理：没分类、没分账本的按商户分组，一组一句话问用户（例：「Mercadona 3 笔共 −67,20 €，都算个人·餐饮？」），确认后用 `fin categorize` / `fin assign` 一次写。

**整理没分类 / 分店里还是个人**
`fin tx --json` 里 `category` 为空、`bookID` 为空的就是没整理的（`fin context` 里有「未分账本」数量）。按商户分组提建议，一次问完，确认后批量写：`fin categorize --category 材料 <编号…>`、`fin assign --book shop <编号…>`。编号是 `fin tx` 第一列的 8 位。

**对余额**（「Revolut 网银显示 105,84」）
`fin reconcile --account revolut --balance 105,84 [--date 2026-11-20]`（MCP：`reconcile`）只看不改，会说差多少、可能差在哪几笔。把结论告诉用户，确认后再补记、`fin edit` 或 `fin rm`。

**改错、删掉一笔**（「昨天那笔超市其实是 32,40」「这笔重复了删掉」）
先 `fin tx` 找到编号并和用户对一下是哪笔。改：`fin edit <编号> --amount=-32,40 [--text --date --account --book --category]`；删：`fin rm <编号…> --dry-run` 给用户看，确认后去掉 `--dry-run`。都能 `fin undo`。

**新账户、开账余额**（「我开了个 N26，里面有 200」）
`fin account add n26 N26 --kind bank`，再 `fin account opening n26 200 [--date …]`（信用卡欠款写负数）。开账余额不算收入。MCP：`add_account` 可以同时带 `opening_balance`。

**分期**：`fin installment add 美甲灯 329,40 --count 6 --account daily --book shop`；扣了一期 `fin installment pay 美甲灯`，对账单里已有的扣款用 `--tx <编号>` 认领。`fin installments` 看还剩几期。

**多币种**：`fin fx` 看主币种和外币账户（原币余额 + 约合主币种）。外币账户 `fin account add wise 美元卡 --currency USD`（MCP：`add_account` 的 `currency`），已有账户 `fin fx account wise USD`。外币账户里的流水金额写那个币种的数（美元卡记美元），汇总自动按当天欧洲央行汇率换成主币种；`fin fx update`（MCP：`update_rates`）取汇率。银行实际扣了多少主币种以银行为准：`fin fx set-rate <id> --bank 46,12`。欧元卡在国外刷外币：金额记银行扣的欧元，`--original "50 USD"` 记原价。改主币种 `fin fx base USD`（已有金额不变）。

**订阅**：`fin subscriptions`（MCP：`subscriptions`）看每月 / 一年合计、下次哪天扣、可能涨价的。用户问「我订了哪些」「每月固定扣多少」就用它。从流水里找：`fin subscription find`（MCP：`find_subscriptions`），只列不写；把列表给用户看，问哪些是真订阅，确认后 `fin subscription add 视频会员 13,99 --next 2026-12-03 --account revolut --match netflix [--cycle yearly]`。涨价 `fin subscription edit 视频会员 --amount 15,99`，不续了 `fin subscription cancel 视频会员`，登记错了 `fin subscription remove`。

**存钱目标**：`fin goal add 应急金 6000 [--savings-account pot] [--locked]`；`fin goal deposit 应急金 300 --from daily`；`fin goal withdraw 应急金 100 --to daily`（MCP：`goal_withdraw`；锁定的不能取，也不要建议取）。`fin goals` 看进度。

**出月报**（「出一份 11 月月报」）
先跑 `fin report --month 2026-11 [--book shop]`（MCP：`monthly_report`），它已经写好了收支、花在哪、和上月比、要留意什么，默认不含私房钱。在它的基础上用大白话整理给用户；需要更细时再按账本分别跑 `fin summary --month 2026-11 --book personal` / `--book shop` 和不加 `--book` 的合计，再跑上个月做对比；加上 `fin debts`、`fin installments`、`fin goals`。写成：一句话结论 → 收入/支出/结余（和上月比）→ 支出前 5 类 → 店里单独一段 → 借款、分期、目标 → 需要用户处理的事（没分类的笔数、过期的借款）。给店里或会计的版本不含私房钱。

**记住一件事**（「记住，还姐姐的钱不算支出」「我明年 3 月退健身房」「以后导入先问我店里还是个人」）
1. 先看有没有这件事：`fin memory search 健身`（MCP：`memory` 带 `query`）。有就加在那一条下面，别另开一条。
2. 记：`fin memory add 健身房 "2027 年 3 月退掉。" --kind topic --quote "我明年 3 月退健身房" --review-on 2027-03-31 --link category:运动 --author Claude`（MCP：`remember`）。三类：`rule` 用户定的规矩（以后都这样做）、`topic` 记得的事（一件事一条，默认）、`lesson` 做事经验（踩过的坑、导入某家银行要注意什么）。
3. **时间写具体**：用户说「明年」「下个月」「下周三」，`text` 里写成「2027 年 3 月」这种具体时间（常见说法会自动换，「月底」「年底」要自己写清）；`--quote` 里的原话照原样。有期限的事加 `--review-on`，到那天整理时会提醒。
4. 该记什么：用户明说的规矩和纠正；流水里看不出来的事实；这次做错了、下次要避开的做法（`--kind lesson --story "当时出了什么事"`）。**你自己看出来的规律先问用户**（「看起来你每月 27 号发工资，要我记下吗？」），点头了再记，`--source confirmed`。
5. 不记：金额、余额、每月花多少（要用时现算：`fin regulars` 看工资和固定开销，`fin summary` 看收支）；卡号、密码、验证码；闲聊。
6. 改：`fin memory edit 健身房 --text "…"`；用户说「这个不对」就改那一行，不要再加一行相反的。删：`fin memory forget 健身房`（能撤销）；用户说「彻底忘掉」「别留痕迹」才加 `--forever`（不能撤销，先跟用户确认）。

**每月整理记忆**
context 的记忆里出现「该整理了」时，找个不打断用户的时候提一句。`fin memory tidy`（MCP：`tidy_memory`）列出可能该清掉的（到期的、半年没用上的、挂的分类或借款已经没了的、一个话题挤了太多行的），一条一条用一句话问用户；用户说清掉的 `fin memory tidy --remove <id…>`，说留着的 `fin memory edit <id> --keep`，挤太多行的帮着并成两三行；过完 `fin memory tidy --done`。规矩和标成「重要」的不会列出来，也不要主动建议删。

**工资、房租、每月固定开销**（「我工资多少」「每月固定要扣多少」）
`fin regulars`（MCP：`regulars`）：从最近 12 个月流水现算，给出每月哪天、大约多少、哪几个月多发一份。不要把这些数字记进记忆，涨薪、搬家后它自己会变。

**AI 意见（app 的总览和「夏夏建议」页会显示）**
写之前先 `fin insight list`（MCP：`list_insights`）看这个月已经有什么，别重复。
- **本月点评**：每个月月初（或用户问起这个月怎么样时）跑完 `fin report` 后写一条：`fin insight add review "这个月花钱比上月慢 8%，月底大概能剩 1.150 €" --body "两三句原因和要留意的" [--book shop] --author Claude`（MCP：`add_insight`，kind=review）。同月同账本只留一条，新的会替换旧的。
- **发现异常就写 alert**：某类支出比平时多很多、重复扣款、余额对不上、借款过期等，写 `fin insight add alert "…" --body "…" [--metric category:超市]`。要用户动手处理的用 `action`，建议用 `tip`，好消息用 `good`。title 一句话结论，body 两三句解释。
- **用户说「知道了」「不用再提醒」**：`fin insight dismiss <编号>`（MCP：`dismiss_insight`）。
- 想知道最近哪个 AI 动过账本：MCP `ai_status`。

**管理账本、账户、分类**
- 新账本：`fin book add 家庭 --kind personal`（生意用 `--kind business`）；改名：`fin book rename <账本id> 新名字`。
- **删账本先预演**：`fin book rm <账本id> --move-to <另一个账本id> --dry-run`（MCP：`remove_book` 带 `dry_run`），把会挪走多少笔流水、借款、分期、目标原样告诉用户，同意后再去掉 `--dry-run`。里面有东西时必须指定 `--move-to`，不要自己猜挪到哪。
- 改账户名字、类型、机构、是否私房钱：MCP `edit_account`；删账户：MCP `remove_account`（有流水的删不了）。
- 分类整体改名或并进另一个分类：MCP `rename_category`（`from`、`to`），先 `dry_run`。

**写错了**：`fin history` 找到那条改动，`fin undo <编号>`。
"""#),
        ("references/commands.md", #"""
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
| 目标和储蓄 | `fin goals` | `goals` |
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
| 目标 | `fin goal add 名称 金额 [--savings-account] [--locked] [--deadline]`；`fin goal deposit 名称 金额 --from 账户`；`fin goal withdraw 名称 金额 --to 账户` | `add_goal`、`goal_deposit`、`goal_withdraw` |
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
"""#),
        ("PROMPT.md", #"""
# 夏夏账本 · 通用提示词

给没有 skill 机制的 AI 工具用（Codex 的 AGENTS.md、Gemini 的 GEMINI.md、DeepSeek / Qwen / Kimi 的全局指令等）：把下面「---」之间整段贴进去。`scripts/install-global.sh` 会自动把它写进已装工具的全局指令文件。

---

## 夏夏账本（用户的记账软件）

用户的个人财务（有的还有店或副业）记在「夏夏账本」里：位置用 `fin where` 看（一般是 iCloud 云盘「夏夏账本/ledger.sqlite」），Mac app、命令行 `fin`（`~/.local/bin/fin`）和 MCP 服务 `xiaxia-ledger`（`fin mcp`）读写同一份。有哪些账本、账户以 `fin context` 为准。

**夏夏账本是用户记账的唯一入口。** 不管在聊什么，用户提到自己花了钱、收了钱（哪怕是顺口一句「刚打车花了 15」「今天发工资了」），都当作要记进夏夏账本：信息够就记，然后用一句话说记了什么；缺哪个账户、哪个账本这种关键信息，就先问一句再记。别人的钱、假设的、计划要花的不记。

用户说到记一笔、花了多少、收支、余额、月报、对账、导入对账单、分类、店里还是个人、谁欠我钱、还款、分期、订阅、存钱目标、私房钱、「记住这件事」，或者提到自己的银行卡、账户名，或者发来小票、发票、账单的照片或截图时：

1. 先跑 `fin context`（或 MCP 工具 `context`），按里面的账户 id 和统计口径来；命令不熟就看 `fin --help`、`fin <命令> --help`。完整说明在 `~/.agents/skills/fin/SKILL.md`。
2. 拿不准的（哪个账户、个人还是店里、什么分类、是不是自己账户互转）先在对话里问用户，确认后再写。
3. 导入和批量修改先加 `--dry-run` 预演给用户看，同意后再正式写；写入加 `--author 你的名字`，写完告诉用户改动编号，写错用 `fin undo <编号>` 撤销。
4. 只用 fin / MCP 写，不直接改账本文件。选项里的负数写等号，如 `fin edit <编号> --amount=-12,50`。
5. 不算收支的：借款和还款、存取目标、自己账户之间转钱、分期每期还款；分期买的那天按全额算支出；退款冲减原分类的支出。
6. 私房钱账户只在用户本人问时提，给店里或会计的报表不算进去。
7. 拍的小票、单子、账单截图：读出商户、日期、金额、币种，一张小票一般记成一笔，一份账单有很多笔就用 `import_rows` 先预演。写之前先给用户看读到了什么（例：「读到 Mercadona，11 月 20 日，−23,40 €，餐饮·个人，记吗？」），确认后再写。看不清的数字问用户，不要猜。也先查一下同一天、同一金额是不是已经有了（比如已经从银行导进来了），有就不要重复记。
8. 要用户选的时候（哪个账户、哪个账本、什么分类、记不记），如果你有提问工具或选项卡（比如 Claude Code 的 AskUserQuestion），就用它把选项列出来让用户点。没有这种工具，就用文字问，并给选项编上号。
9. 用户要「定时问我记账」：用你自己的定时功能，比如定时任务、cron 或提醒，按用户选的「每天」或「每周」，到点问一句「今天（这周）有没有没记的开销？直接说或者拍小票都行」，同时说一下这段时间已经记了多少。你没有定时功能就直接说明，建议用户在手机上设个提醒。
10. 记忆：`fin context` 里有用户定的规矩（照着做）和记得的事的标题（相关的先 `fin memory show <话题>` 读全文）。用户说「记住」「以后都这样」时先 `fin memory search` 看有没有，再 `fin memory add 话题 "一句话" --kind rule｜topic｜lesson`；时间写具体（「明年 3 月」写成「2027 年 3 月」）；自己看出来的规律先问用户再记；金额不记，工资和固定开销用 `fin regulars` 现算。
11. 金额按 `fin context` 里的主币种显示（欧元写成 1.234,56 €）。真实数字不贴到公开地方、不提交进 git。连不上 fin 时直接说，不要编数字。

---
"""#),
    ]
}
