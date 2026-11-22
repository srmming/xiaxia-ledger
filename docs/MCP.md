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

下面是手动配置的写法。

## 配置

Claude 桌面版（`~/Library/Application Support/Claude/claude_desktop_config.json`）：

```json
{ "mcpServers": { "xiaxia-ledger": { "command": "/Users/ming/.local/bin/fin", "args": ["mcp"] } } }
```

Claude Code：`claude mcp add xiaxia-ledger -- ~/.local/bin/fin mcp`

Codex（`~/.codex/config.toml`）：

```toml
[mcp_servers.xiaxia-ledger]
command = "/Users/ming/.local/bin/fin"
args = ["mcp"]
```

## 工具

只读：`context`、`accounts`、`list_transactions`、`summary`、`monthly_report`、`reconcile`、`debts`、`installments`、`goals`、`history`、`currency`、`subscriptions`、`find_subscriptions`。

写入（都能 `dry_run`）：`add_account`、`set_opening_balance`、`add_transaction`、`edit_transaction`、`delete_transactions`、`account_transfer`、`book_transfer`、`goal_withdraw`、`mark_account_transfer`、`add_debt`、`repay_debt`、`categorize`、`assign_book`、`import_statement`、`add_installment`、`pay_installment`、`add_goal`、`goal_deposit`、`split_transaction`、`duplicate_transaction`、`add_refund`、`tag_transactions`、`set_recurring`、`update_recurring`、`run_recurring`、`set_base_currency`、`set_account_currency`、`set_rate`、`update_rates`、`add_subscription`、`edit_subscription`、`remove_subscription`、`undo`。只读另有 `list_recurring`。

私房钱账户默认不出现在 `list_transactions` 和 `summary` 里，要 `include_private: true`，只有 ming 本人问时才用。
