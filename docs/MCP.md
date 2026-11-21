# 用 MCP 连上夏夏账本

`fin mcp` 是一个 stdio MCP 服务，给 Claude 桌面版、Claude Code、Codex、DeepSeek 等 AI 工具用。规则和命令行一样：写入都记改动记录（作者默认是 AI 工具自己报的名字），能撤销；拿不准的事先在对话里问 ming。

## 装

```bash
swift build -c release
cp .build/release/fin /usr/local/bin/fin
```

## 配置

Claude 桌面版（`~/Library/Application Support/Claude/claude_desktop_config.json`）：

```json
{ "mcpServers": { "xiaxia-ledger": { "command": "/usr/local/bin/fin", "args": ["mcp"] } } }
```

Claude Code：`claude mcp add xiaxia-ledger -- /usr/local/bin/fin mcp`

Codex（`~/.codex/config.toml`）：

```toml
[mcp_servers.xiaxia-ledger]
command = "/usr/local/bin/fin"
args = ["mcp"]
```

## 工具

只读：`context`、`list_transactions`、`summary`、`debts`、`installments`、`goals`、`history`。

写入（都能 `dry_run`）：`add_transaction`、`add_debt`、`repay_debt`、`categorize`、`assign_book`、`import_statement`、`undo`。

私房钱账户默认不出现在 `list_transactions` 和 `summary` 里，要 `include_private: true`，只有 ming 本人问时才用。
