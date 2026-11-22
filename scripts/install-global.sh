#!/usr/bin/env bash
# 把夏夏账本装进这台 Mac 上各 AI 工具的「全局」：任何目录、任何对话里 AI 都知道怎么用 fin 和 MCP。
#
#   bash scripts/install-global.sh            # 安装 / 更新（可以反复跑，结果一样）
#   bash scripts/install-global.sh --dry-run  # 只列出会改哪些文件，不动
#
# 做的事：
#   1. 装了夏夏账本 app 就把 ~/.local/bin/fin 链到 app 里的 fin；没装就编译 release 版 fin 复制过去
#   2. 跑 fin setup：给装了的 AI 工具接上 MCP、装好 skill（~/.agents/skills/fin，打包在 fin 里）和全局提示词，最后自检
# 第一次改已有文件前会在旁边留一份 .bak-xiaxia（装之前的原样，以后再跑不覆盖）。只改「夏夏账本」自己的那一段，别的配置不碰。
# 改了 skills/fin 里的说明要先跑 python3 scripts/gen-skill-bundle.py 再编译，fin 里带的才会更新。
set -euo pipefail

DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "不认识的参数：$arg" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
FIN="$BIN_DIR/fin"

say() { echo "• $*"; }
doit() { if [ $DRY = 1 ]; then echo "  （预演）$*"; else "$@"; fi; }

# ---------- 1. fin ----------
# 装了夏夏账本 app 就用 app 里自带的 fin：~/.local/bin/fin 只是指向它的软链，MCP 配置直接写 app 里的路径。只留一份，app 更新 fin 跟着更新。
APP_FIN=""
for app in "$HOME/Applications/夏夏账本.app" "/Applications/夏夏账本.app"; do
  [ -x "$app/Contents/MacOS/fin" ] && { APP_FIN="$app/Contents/MacOS/fin"; break; }
done
if [ -n "$APP_FIN" ] && [ "${XIAXIA_SKIP_BUILD:-0}" != 1 ]; then
  say "fin：用 app 自带的 $APP_FIN，$FIN 链到它"
  doit mkdir -p "$BIN_DIR"
  doit ln -sfn "$APP_FIN" "$FIN"
  FIN="$APP_FIN"
elif [ "${XIAXIA_SKIP_BUILD:-0}" = 1 ]; then
  say "fin → $FIN"
  BUILT="${XIAXIA_FIN_BINARY:?XIAXIA_SKIP_BUILD=1 时要用 XIAXIA_FIN_BINARY 指定 fin}"
else
  say "fin → $FIN（没找到夏夏账本 app，从源码编译）"
  doit swift build -c release --package-path "$REPO" --product fin
  BUILT="$REPO/.build/release/fin"
fi
if [ -z "$APP_FIN" ] || [ "${XIAXIA_SKIP_BUILD:-0}" = 1 ]; then
  doit mkdir -p "$BIN_DIR"
  # 先复制成临时文件再 mv 替换：直接 cp 覆盖正在用的文件，macOS 会拿旧签名缓存校验新文件，fin 一跑就被杀掉（退出码 137）
  doit cp -f "$BUILT" "$FIN.new"
  doit mv -f "$FIN.new" "$FIN"
fi
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "注意：$BIN_DIR 不在 PATH 里，命令行里要写全路径（MCP 配置已用全路径）";; esac

# ---------- 2. MCP、skill、提示词：交给 fin setup（和 app、「复制配置提示词」用的是同一份逻辑） ----------
if [ $DRY = 1 ]; then
  if [ -x "$FIN" ]; then "$FIN" setup --dry-run; else say "（预演）fin 还没装好，装好后会跑 fin setup"; fi
else
  "$FIN" setup
fi
