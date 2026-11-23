# 用 MCP 连上夏夏账本

`fin mcp` 是一个 stdio MCP 服务，给 Claude 桌面版、Claude Code、Codex、DeepSeek 等 AI 工具用。规则和命令行一样：写入都记改动记录（作者默认是 AI 工具自己报的名字），能撤销；拿不准的事先在对话里问 ming。

## 装

一条命令装好 MCP、skill 和通用提示词（各 AI 工具的全局配置，可以反复跑；skill 打包在 fin 里，不需要这个仓库）：

```bash
fin setup --dry-run   # 先看会改哪些文件
fin setup             # 给这台 Mac 上装了的 AI 工具都装好，最后自己读一次账本确认
fin setup --check     # 不改，只检查
fin setup --remove    # 全部拿掉
```

最省事的办法：在 app 的「设置」或「连上你的 AI」里点「一键复制配置提示词」，粘给任何一个 AI。能执行命令的 AI 会自己跑上面这几条；不能执行命令的会告诉你把配置粘到哪儿。

开发时用 `bash scripts/install-global.sh`：先把 `~/.local/bin/fin` 链到 app 里的 fin（没装 app 就从源码编译），再跑 `fin setup`。改了 `skills/fin` 里的说明，要先跑 `python3 scripts/gen-skill-bundle.py` 再编译。

下面是手动配置的写法（`/Users/你的用户名` 换成自己的主目录，终端里 `echo ~` 可以看到）。

## 配置

Claude 桌面版（`~/Library/Application Support/Claude/claude_desktop_config.json`）：

```json
{ "mcpServers": { "xiaxia-ledger": { "command": "/Users/你的用户名/.local/bin/fin", "args": ["mcp"] } } }
```

Claude Code：`claude mcp add xiaxia-ledger -- ~/.local/bin/fin mcp`

Codex（`~/.codex/config.toml`）：

```toml
[mcp_servers.xiaxia-ledger]
command = "/Users/你的用户名/.local/bin/fin"
args = ["mcp"]
```

## 工具

只读：`context`、`accounts`、`list_transactions`、`summary`、`monthly_report`、`reconcile`、`debts`、`installments`、`goals`、`history`、`currency`、`subscriptions`、`find_subscriptions`、`memory`、`regulars`。

写入（都能 `dry_run`）：`add_account`、`set_opening_balance`、`add_transaction`、`edit_transaction`、`delete_transactions`、`account_transfer`、`book_transfer`、`goal_withdraw`、`mark_account_transfer`、`add_debt`、`repay_debt`、`plan_debt`、`edit_debt_plan`、`skip_debt_payment`、`categorize`、`assign_book`、`import_statement`、`add_installment`、`pay_installment`、`add_goal`、`goal_deposit`、`set_main_goal`、`goal_check`、`set_goal_stash`、`remove_goal`、`split_transaction`、`duplicate_transaction`、`add_refund`、`tag_transactions`、`set_recurring`、`update_recurring`、`run_recurring`、`set_base_currency`、`set_account_currency`、`set_rate`、`update_rates`、`add_subscription`、`edit_subscription`、`remove_subscription`、`remember`、`update_memory`、`forget_memory`、`tidy_memory`、`undo`。只读另有 `list_recurring`、`plan_goal`（建目标前算每天存多少、超不超出每月剩的）。

### 夏夏的记忆

账本里有一份「记忆」：用户定的规矩（rule）、记得的事（topic，一件事一条）、做事经验（lesson）。`context` 里的 `memory` 带着规矩全文、其他记忆的标题目录和用法。

- `memory`：不带参数给规矩全文 + 目录；`id` 看一条全文；`query` 按关键词搜。回答和某件事有关的问题前，先看目录里有没有相关的标题，有就读全文。
- `remember`：记一条（`title` 这件事叫什么、`text` 一句话、`kind`、`source`、`quote` 用户原话、`story` 当时出了什么事、`review_on` 哪天回头看、`links` 挂在哪个分类 / 账户 / 借款上）。同名话题自动并在一起；有相近话题会先提示，确实是另一件事再带 `new_topic: true`。
- `update_memory`：改某一行、改话题名、挪到另一类、标成重要、整理时说「留着」。
- `forget_memory`：删掉（能撤销）；`forever: true` 是彻底忘掉，连改动记录里的痕迹一起抹掉，不能撤销，用户明确说「忘掉」才用。
- `tidy_memory`：每月整理。不带参数列出可能该清掉的（到期的、半年没用上的、挂的东西没了的、一个话题挤太多行的）；用户点头后带 `remove` 清掉，过完一遍带 `done: true`。规矩和标成重要的不会列出来。
- `regulars`：工资、房租这类每月固定进出，从最近 12 个月流水现算。

什么该记：用户明说的规矩和纠正（`source: said / corrected`）、流水里看不出来的事实（「明年要涨薪」「这笔是帮朋友垫的」）、做错过一次以后要避开的做法。**AI 自己看出来的规律先问用户，点头了再记**（`source: confirmed`）。

什么不记：金额、余额、每月花多少这类能从流水算出来的数（要用时现算，用 `regulars`、`summary`）；卡号、密码、验证码（会被拒绝）；闲聊。

**时间写具体**：用户说「明年 3 月」「下个月」「下周三」，记的时候写成「2027 年 3 月」这样的具体时间。`text` 和 `story` 里常见的相对说法会按当天日期自动换掉，`quote` 里的原话照原样保留；「月底」「年底」这类不会自动换，要自己写清楚是哪年哪月。

私房钱账户默认不出现在 `list_transactions` 和 `summary` 里，要 `include_private: true`，只有 ming 本人问时才用。
