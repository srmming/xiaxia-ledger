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
1. 读出商户、日期、总金额和币种；一张小票默认记成**一笔**（按主要用途分类，比如超市小票算「餐饮」或「日用」），用户说要拆再拆成几笔。小票上有运费、服务费这类和主要东西不一样的项，给用户看的时候顺便问一句要不要分开记。
   **日期一定用小票上印的日期**，写入时把它填进 `date`（`fin add … --date 2022-08-31`），不要用今天。小票日期离今天超过两个月（比如几年前的旧小票），先问一句「这张是 2022 年 8 月 31 日的，记成那天对吗？」。小票上看不到日期才问用户，不要默认今天。
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

**存钱目标（小金猪）**：目标是把「想要的东西」变成「哪天能到手」。规矩和 app 一样：同时最多 **1 个大目标 + 3 个小目标**，目标不在多，在于坚持。
- 先跑 `fin goals`（MCP：`goals`）：看大目标、小目标、每月大约剩多少、还能加几个（`slots_left`），以及 `ask` 里要问用户的事。
- **设目标一律用选项框（提问框）问，一次只问一个**，按这个顺序：① 想要什么（给几个常见的：换新电脑、旅行、应急金、给家人的礼物，也能自己写）→ ② 要多少钱 → ③ 哪天要（3 个月 / 半年 / 一年 / 不定）→ 先 `fin goal plan 金额 --deadline …`（MCP：`plan_goal`）算一下，把「每天存 2,30 €，差不多每 2 天少一杯咖啡」这句原样告诉用户；超出每月剩的钱时，选项给「晚一点更轻松（改到 X 月）」和「就按原来的」→ ④ 钱真的存在哪（储蓄罐 / 一张银行卡 / 一个固定的地方）→ ⑤ 是大目标还是小目标（已经有大目标时说清楚原来的会变成小目标）。问完再 `fin goal add 换新电脑 1400 --deadline 2027-05-31 --stash jar --stash-note 书桌上的小猪 [--main]`（MCP：`add_goal`）。
- 已经有 4 个在存（满了）：别硬建，用选项框问「先完成或删掉哪一个？」把现有的列出来，再加一个选项「先不加了」。
- 建好后提醒一句：每次真的存了钱都记一笔，小小的一步也能实现大大的目标。
- 存钱：`fin goal deposit 换新电脑 20 --from daily`（MCP：`goal_deposit`），忍住没买咖啡这类把钱存起来的加 `--held-back 咖啡`（MCP：`held_back`）。返回里的「提前了 N 天到手」原样告诉用户，app 里小猪显示的是同一个数。
- 取钱：`fin goal withdraw 换新电脑 100 --to daily`（MCP：`goal_withdraw`）。用钱很正常，不责怪；锁定的不能取，也不要建议取。
- `ask` 里有「很久没存了」的目标：用选项框问「这个目标你很久没动了，它对你还重要吗？」选项「还重要，继续」「先放一放」「删掉」，选了再 `fin goal check 名字 keep|pause`（MCP：`goal_check`）或删掉 `fin goal rm 名字`（MCP：`remove_goal`）。换大目标：`fin goal main 名字`（MCP：`set_main_goal`）。

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

生意模式下，先看 context 的 businessBookID 和 lifeBookIDs。已确认的生活或生意收支用 side=life 或 business；归属拿不准先问。profit 查利润，capital 查本钱和回本进度。
