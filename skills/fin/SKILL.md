---
name: fin
description: 夏夏账本：ming 的个人和 Miora 美甲店财务（西班牙，欧元）。用户说记一笔、花了多少、收支、余额、月报、对账、导入对账单/银行流水、分类、店里还是个人、谁欠我钱、还款、分期、存钱目标、私房钱，或提到 Caixa、imagin、Revolut、MyCard 时使用。通过 fin 命令行或 xiaxia-ledger MCP 查账和记账。
---

# 夏夏账本（fin / MCP）

ming 的财务都在一份本地账本里（iCloud 云盘「夏夏账本/ledger.sqlite」），Mac app、`fin` 命令行和 MCP 服务读写同一份。两个账本：`personal`（个人）、`miora`（Miora 美甲店）。钱是欧元，显示成 `1.234,56 €`。

## 用哪个入口

- 有 `xiaxia-ledger` 的 MCP 工具（如 `context`、`summary`、`add_transaction`）就用 MCP。
- 没有就用命令行 `fin`（装在 `~/.local/bin/fin`；找不到就试 `~/.local/bin/fin` 全路径）。命令和参数见 [references/commands.md](references/commands.md)，以 `fin <命令> --help` 为准。
- 两个都没有（比如在云端、不在 ming 的 Mac 上）：直接告诉 ming 这里连不上账本，不要编数字。

## 每次先做

1. 跑 `fin context`（MCP：`context`）。它给出账本、账户 id 和余额、数据覆盖到哪天、借款合计、最近改动和**统计口径**。按口径回答，不要自己另定规则。
2. 账户 id、账本 id 只用 context 里出现的，别猜。

## 规矩（最重要）

- **拿不准就问，问清楚再写**：哪个账户、哪个账本（个人还是店里）、什么分类、是不是自己账户之间转钱，有一样不确定就在对话里问 ming。app 里没有「待确认」，确认只发生在对话里。
- **批量先预演**：导入、一次改多笔，先加 `--dry-run`（MCP：`"dry_run": true`），把会改什么用几行列给 ming，他说可以再正式写。单笔且信息齐全可以直接写。
- **写明是谁**：命令行写入加 `--author Claude`（或 Codex、DeepSeek，写你自己）；MCP 自动用工具名。
- **写完报结果和改动编号**：比如「已记：超市 −12,50 €（现金，个人）。写错了说一声，我用改动 3fa2c1d0 撤销」。
- **只通过 fin / MCP 写**，不要直接改 ledger.sqlite，也不要自己算余额再写回去。
- **私房钱**（context 里 `isPrivate: true` 的账户）：只在 ming 本人问时提；给店里、合伙人、gestoría 的报表不算进去。命令行 `fin tx`、`fin summary` 目前**不会**自动隐藏它，做报表时自己排除；MCP 默认隐藏。
- **隐私**：真实金额和流水不贴到公开地方、不提交进 git、不发给外部服务。
- 不动钱、不碰银行密码；银行数据只读。

## 命令行的坑

- **负数金额**：`fin add --account cash --book personal -- -12,50 超市`。不写 `--` 会报错「Missing expected argument」。
- 看帮助用 `fin debt add --help`（`fin help debt add` 只会打出顶层帮助）。
- 导入 Revolut 要写 `--format revolut`，默认按通用 CSV。
- 账户是不是私房钱只在 `--json` 里看得到（`isPrivate`），文字输出没有标记。
- `fin debt repay` 按名字包含匹配，名字有重叠（「阿华」「阿华2」）时会对上多笔而失败，先 `fin debts` 看清楚。多还了不会拦，自己先核对还欠多少。
- `fin transfer move` 记出来的两笔没有账本，记完按情况 `fin assign`。

## 口径速记

- 正数收入、负数支出。
- 不算收支的：借出/借入/还款（往来）、存进或取出目标（储蓄）、自己账户之间转钱（互转：取现、充值 Revolut、还信用卡、主账户和 imagin 互转）、分期的每期还款。
- 分期：买的那天按全额算支出；手续费、利息单独算支出。
- 退款：用原来那笔的分类、记正数，冲减这类支出，不算收入。
- 账本间转账（店里的钱拿回家）：单个账本照算，「全部」里抵消。

## 常见任务怎么做

**回答财务问题**（「这个月花了多少」「店里 10 月赚了吗」「餐饮比上月多吗」）
`context` → `fin summary --month 2026-10 --book miora` → 需要明细再 `fin tx --month … --category …`。回答先给数字，再说一两句为什么，金额用 `1.234,56 €`。没说账本时分别给个人、店里和合计。

**记一笔**（「刚才超市花了 23,40，用的现金」）
从话里取金额、说明、日期（默认今天）；账户和账本说不清就问。分类可以按以前同一个商户的分类猜，但要在回复里说出来。
`fin add --account cash --book personal --category 餐饮 --author Claude -- -23,40 超市`

⚠️ 负数金额前面一定要有 `--`（选项写在前面，`--` 后面是金额和说明），不然会被当成选项，报「Missing expected argument」。

**借钱和还钱**（「借给阿华 500」「阿华还了 100」）
先 `fin debts` 看有没有这个人的账。借出：`fin debt add 阿华 500 --they-owe-me --account cash`；借入用 `--i-owe`；以前的旧账没有对应流水就不填 `--account`。还款：`fin debt repay 阿华 100 --account cash`。

**自己账户之间转钱 / 取现**（「从 Caixa 取了 50 现金」）
新记：`fin transfer move 50 --from-account caixa --to-account cash`。对账单里已经有的那笔：`fin transfer mark <编号> [--counter-account cash]`。店里的钱拿回家（同一账户、换账本）：`fin transfer new 200 --from miora --to personal --account caixa`。

**导入对账单**（「把这个 Revolut 的 CSV 导进去」）
1. 认格式：Revolut 导出用 `--format revolut`；其他银行看表头，用通用 CSV 指定列（`--date-col --amount-col --desc-col`，收支分两列用 `--debit-col --credit-col`）。只支持 CSV，PDF 先说明需要转成 CSV。
2. 预演：`fin import 文件.csv --account revolut --format revolut --dry-run`，告诉 ming「读到 N 笔，新的 M 笔，重复的 K 笔已跳过」，列前几笔。
3. ming 同意后去掉 `--dry-run` 正式导入（整批是一条改动，能一次撤销）。
4. 导完接着整理：没分类、没分账本的按商户分组，一组一句话问 ming（例：「Mercadona 3 笔共 −67,20 €，都算个人·餐饮？」），确认后用 `fin categorize` / `fin assign` 一次写。

**整理没分类 / 分店里还是个人**
`fin tx --json` 里 `category` 为空、`bookID` 为空的就是没整理的（`fin context` 里有「未分账本」数量）。按商户分组提建议，一次问完，确认后批量写：`fin categorize --category 材料 <编号…>`、`fin assign --book miora <编号…>`。编号是 `fin tx` 第一列的 8 位。

**对余额**（「Revolut 网银显示 105,84」）
`fin accounts` 看账本里的余额，对不上就看那个账户最近的流水，找漏记或重复的，告诉 ming 差在哪几笔，确认后再补记或撤销。

**分期**：`fin installment add 美甲灯 329,40 --count 6 --account caixa --book miora`；扣了一期 `fin installment pay 美甲灯`，对账单里已有的扣款用 `--tx <编号>` 认领。`fin installments` 看还剩几期。

**存钱目标**：`fin goal add 应急金 6000 [--savings-account pot] [--locked]`；`fin goal deposit 应急金 300 --from caixa`；`fin goal withdraw …`（锁定的不能取，也不要建议取）。`fin goals` 看进度。

**出月报**（「出一份 11 月月报」）
按账本分别跑 `fin summary --month 2026-11 --book personal` / `--book miora` 和不加 `--book` 的合计，再跑上个月做对比；加上 `fin debts`、`fin installments`、`fin goals`。写成：一句话结论 → 收入/支出/结余（和上月比）→ 支出前 5 类 → 店里单独一段 → 借款、分期、目标 → 需要 ming 处理的事（没分类的笔数、过期的借款）。给店里或 gestoría 的版本不含私房钱。

**写错了**：`fin history` 找到那条改动，`fin undo <编号>`。
