# 用 MCP 连上夏夏账本

`fin mcp` 是一个 stdio MCP 服务，给 Claude 桌面版、Claude Code、Codex、DeepSeek 等 AI 工具用。规则和命令行一样：写入都记改动记录（作者默认是 AI 工具自己报的名字），能撤销；拿不准的事先在对话里问 ming。

## 装

一条命令装好 fin、skill、通用提示词和 MCP（各 AI 工具的全局配置，可以反复跑）：

```bash
bash scripts/install-global.sh --dry-run   # 先看会改哪些文件
bash scripts/install-global.sh
```

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

只读：`context`、`accounts`、`list_transactions`、`summary`、`monthly_report`、`reconcile`、`debts`、`installments`、`goals`、`history`。

写入（都能 `dry_run`）：`add_account`、`set_opening_balance`、`add_transaction`、`edit_transaction`、`delete_transactions`、`account_transfer`、`mark_account_transfer`、`add_debt`、`repay_debt`、`categorize`、`assign_book`、`import_statement`、`add_installment`、`pay_installment`、`add_goal`、`goal_deposit`、`undo`。

私房钱账户默认不出现在 `list_transactions` 和 `summary` 里，要 `include_private: true`，只有 ming 本人问时才用。
