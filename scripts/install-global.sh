#!/usr/bin/env bash
# 把夏夏账本装进这台 Mac 上各 AI 工具的「全局」：任何目录、任何对话里 AI 都知道怎么用 fin 和 MCP。
#
#   bash scripts/install-global.sh            # 安装 / 更新（可以反复跑，结果一样）
#   bash scripts/install-global.sh --dry-run  # 只列出会改哪些文件，不动
#
# 做的事：
#   1. 编译 release 版 fin，复制到 ~/.local/bin/fin
#   2. skill：~/.agents/skills/fin 链到仓库的 skills/fin；~/.claude/skills/fin、~/.codex/skills/fin 链到它
#   3. 通用提示词（skills/fin/PROMPT.md）写进已装工具的全局指令文件，用标记包起来，再跑只会替换不会重复
#   4. 把 MCP 服务 xiaxia-ledger（fin mcp）注册到已装的工具
# 第一次改已有文件前会在旁边留一份 .bak-xiaxia（装之前的原样，以后再跑不覆盖）。只改「夏夏账本」自己的那一段，别的配置不碰。
set -euo pipefail

DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "不认识的参数：$arg" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_SRC="$REPO/skills/fin"
PROMPT_SRC="$SKILL_SRC/PROMPT.md"
BIN_DIR="$HOME/.local/bin"
FIN="$BIN_DIR/fin"
MCP_NAME="xiaxia-ledger"
START="<!-- xiaxia-ledger:start（由 xiaxia-ledger/scripts/install-global.sh 维护，改动请改仓库里的 skills/fin/PROMPT.md）-->"
END="<!-- xiaxia-ledger:end -->"

say() { echo "• $*"; }
doit() { if [ $DRY = 1 ]; then echo "  （预演）$*"; else "$@"; fi; }
# 只在第一次装的时候留备份：.bak-xiaxia 是装之前的原样，以后再跑不覆盖它
backup() { [ -f "$1" ] && [ ! -e "$1.bak-xiaxia" ] && [ $DRY = 0 ] && cp -p "$1" "$1.bak-xiaxia" || true; }
has() { command -v "$1" >/dev/null 2>&1; }

# ---------- 1. fin ----------
say "fin → $FIN"
if [ "${XIAXIA_SKIP_BUILD:-0}" = 1 ]; then
  BUILT="${XIAXIA_FIN_BINARY:?XIAXIA_SKIP_BUILD=1 时要用 XIAXIA_FIN_BINARY 指定 fin}"
else
  doit swift build -c release --package-path "$REPO" --product fin
  BUILT="$REPO/.build/release/fin"
fi
doit mkdir -p "$BIN_DIR"
# 先复制成临时文件再 mv 替换：直接 cp 覆盖正在用的文件，macOS 会拿旧签名缓存校验新文件，fin 一跑就被杀掉（退出码 137）
doit cp -f "$BUILT" "$FIN.new"
doit mv -f "$FIN.new" "$FIN"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "注意：$BIN_DIR 不在 PATH 里，命令行里要写全路径（MCP 配置已用全路径）";; esac

# ---------- 2. skill ----------
link() {  # link <目标> <链接位置>
  local target="$1" at="$2"
  if [ -L "$at" ] && [ "$(readlink "$at")" = "$target" ]; then say "skill 已链好：$at"; return; fi
  if [ -e "$at" ] && [ ! -L "$at" ]; then
    say "跳过 $at：已经有一个不是链接的同名目录，请自己看一下"; return
  fi
  say "skill：$at → $target"
  doit mkdir -p "$(dirname "$at")"
  doit ln -sfn "$target" "$at"
}
link "$SKILL_SRC" "$HOME/.agents/skills/fin"
[ -d "$HOME/.claude" ] && link "$HOME/.agents/skills/fin" "$HOME/.claude/skills/fin"
[ -d "$HOME/.codex" ] && link "$HOME/.agents/skills/fin" "$HOME/.codex/skills/fin"
[ -d "$HOME/.qwen/skills" ] && link "$HOME/.agents/skills/fin" "$HOME/.qwen/skills/fin"

# ---------- 3. 通用提示词 ----------
# 取 PROMPT.md 里两条 --- 之间的那段
BLOCK="$(awk '/^---$/{n++; next} n==1' "$PROMPT_SRC")"
put_block() {  # put_block <文件>
  local file="$1"
  say "提示词 → $file"
  [ $DRY = 1 ] && return
  mkdir -p "$(dirname "$file")"; touch "$file"; backup "$file"
  python3 - "$file" "$START" "$END" "$BLOCK" <<'PY'
import sys, re
path, start, end, block = sys.argv[1:5]
text = open(path, encoding="utf-8").read()
new = f"{start}\n{block.strip()}\n{end}"
pat = re.compile(re.escape(start.split("（")[0]) + r".*?" + re.escape(end), re.S)
if pat.search(text):
    text = pat.sub(lambda _: new, text)
else:
    text = (text.rstrip() + "\n\n" if text.strip() else "") + new + "\n"
open(path, "w", encoding="utf-8").write(text)
PY
}
[ -d "$HOME/.claude" ] && put_block "$HOME/.claude/CLAUDE.md"
[ -d "$HOME/.codex" ]  && put_block "$HOME/.codex/AGENTS.md"
[ -d "$HOME/.gemini" ] && put_block "$HOME/.gemini/GEMINI.md"
[ -d "$HOME/.qwen" ]   && put_block "$HOME/.qwen/QWEN.md"

# ---------- 4. MCP ----------
json_mcp() {  # json_mcp <文件>：在 mcpServers 里加 / 更新 xiaxia-ledger，别的不动
  local file="$1"
  say "MCP → $file"
  [ $DRY = 1 ] && return
  mkdir -p "$(dirname "$file")"; backup "$file"
  python3 - "$file" "$MCP_NAME" "$FIN" <<'PY'
import sys, json, os
path, name, fin = sys.argv[1:4]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, encoding="utf-8") as f: data = json.load(f)
data.setdefault("mcpServers", {})[name] = {"command": fin, "args": ["mcp"]}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2); f.write("\n")
PY
}

if has claude; then
  say "MCP → Claude Code（用户级）"
  if [ $DRY = 0 ]; then
    claude mcp remove -s user "$MCP_NAME" >/dev/null 2>&1 || true
    claude mcp add -s user "$MCP_NAME" -- "$FIN" mcp
  fi
fi
DESKTOP="$HOME/Library/Application Support/Claude"
[ -d "$DESKTOP" ] && json_mcp "$DESKTOP/claude_desktop_config.json"

if [ -d "$HOME/.codex" ]; then
  CODEX="$HOME/.codex/config.toml"
  say "MCP → $CODEX"
  if [ $DRY = 0 ]; then
    touch "$CODEX"; backup "$CODEX"
    python3 - "$CODEX" "$MCP_NAME" "$FIN" <<'PY'
import sys, re
path, name, fin = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
section = f'[mcp_servers.{name}]\ncommand = "{fin}"\nargs = ["mcp"]\n'
pat = re.compile(r'^\[mcp_servers\.' + re.escape(name) + r'\]\n(?:(?!\[).*\n?)*', re.M)
if pat.search(text):
    text = pat.sub(lambda _: section + "\n", text).rstrip() + "\n"
else:
    text = (text.rstrip() + "\n\n" if text.strip() else "") + section
open(path, "w", encoding="utf-8").write(text)
PY
  fi
fi
[ -d "$HOME/.gemini" ] && json_mcp "$HOME/.gemini/settings.json"
[ -d "$HOME/.qwen" ]   && json_mcp "$HOME/.qwen/settings.json"
[ -d "$HOME/.cursor" ] && json_mcp "$HOME/.cursor/mcp.json"

echo
if [ $DRY = 1 ]; then echo "预演完，什么都没改。"; else
  echo "装好了。试试：$FIN context"
  echo "已经开着的 Claude 桌面版、Codex 等要重开一次才会连上 MCP。"
fi
