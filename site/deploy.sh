#!/usr/bin/env bash
# 把官网和安装包传到 VPS。从仓库根目录或 site/ 里跑都行。
#
#   bash site/deploy.sh            # 网页 + 安装包（dist/ 里有就传）
#   bash site/deploy.sh --site     # 只传网页
#   bash site/deploy.sh --release  # 传 dist/appcast.xml、dist/download/，再加更新日志页（changelog.html 和它的截图）
#
# 连哪台服务器写在 site/deploy.env（不进仓库），照 site/deploy.env.example 填。
# 用的是这台 Mac 上已有的 ssh 配置（~/.ssh/config 里的别名），脚本不碰密码和私钥。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$ROOT/site"
[ -f "$SITE/deploy.env" ] && . "$SITE/deploy.env"
: "${XIAXIA_SSH:?请在 site/deploy.env 里写 XIAXIA_SSH=ssh 别名（比如 vps）}"
DIR="${XIAXIA_DIR:-/var/www/xiaxia}"
MODE="${1:-all}"

ssh "$XIAXIA_SSH" "mkdir -p '$DIR/download' '$DIR/release-notes'"

if [ "$MODE" = all ] || [ "$MODE" = --site ]; then
  echo "▸ 上传网页"
  rsync -az --delete \
    --exclude download/ --exclude release-notes/ --exclude appcast.xml \
    --exclude deploy.sh --exclude 'deploy.env*' --exclude server/ --exclude README.md \
    "$SITE/" "$XIAXIA_SSH:$DIR/"
fi

if [ "$MODE" = all ] || [ "$MODE" = --release ]; then
  DIST="$ROOT/dist"
  if [ -f "$DIST/appcast.xml" ]; then
    echo "▸ 上传安装包（先传 dmg，最后传 appcast.xml，免得 app 看到还没传完的新版本）"
    rsync -az --partial "$DIST/download/" "$XIAXIA_SSH:$DIR/download/"
    [ -d "$DIST/release-notes" ] && rsync -az "$DIST/release-notes/" "$XIAXIA_SSH:$DIR/release-notes/"
    if [ "$MODE" = --release ] && [ -f "$SITE/changelog.html" ]; then
      echo "▸ 上传更新日志页"
      ssh "$XIAXIA_SSH" "mkdir -p '$DIR/assets/changelog'"
      rsync -az "$SITE/assets/changelog/" "$XIAXIA_SSH:$DIR/assets/changelog/"
      rsync -az "$SITE/changelog.html" "$XIAXIA_SSH:$DIR/changelog.html"
    fi
    rsync -az "$DIST/appcast.xml" "$XIAXIA_SSH:$DIR/appcast.xml.new"
    ssh "$XIAXIA_SSH" "mv '$DIR/appcast.xml.new' '$DIR/appcast.xml'"
  elif [ "$MODE" = --release ]; then
    echo "✗ 没找到 dist/appcast.xml，先跑 scripts/release-share.sh" >&2; exit 1
  fi
fi

if [ -n "${XIAXIA_DOMAIN:-}" ]; then
  echo "▸ 检查"
  curl -fsSI "https://$XIAXIA_DOMAIN/" | head -1
  curl -fsSI "https://$XIAXIA_DOMAIN/changelog.html" | head -1 || echo "（还没有更新日志页）"
  curl -fsSI "https://$XIAXIA_DOMAIN/appcast.xml" | head -1 || echo "（还没有 appcast.xml）"
  curl -fsSI "https://$XIAXIA_DOMAIN/download/xiaxia-ledger.dmg" | head -1 || echo "（还没有安装包）"
fi
echo "✓ 好了"
