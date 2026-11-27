#!/bin/bash
# 做一个能双击的「夏夏账本 v3 试用.app」（不签名、只用编的示例数字，不读不写任何账本）。
# 用法：bash scripts/v3-app.sh <放到哪个文件夹>
set -euo pipefail
DEST="${1:?要说放到哪个文件夹}"
cd "$(dirname "$0")/.."
swift build -c release --product XiaxiaLedgerApp
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$DEST/夏夏账本 v3 试用.app"
STAGE="$(mktemp -d)/夏夏账本 v3 试用.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN_DIR/XiaxiaLedgerApp" "$STAGE/Contents/MacOS/XiaxiaV3Demo"
# 图片这些资源：放两处，哪种找法都找得到
for b in "$BIN_DIR"/*.bundle; do
  [ -e "$b" ] || continue
  cp -R "$b" "$STAGE/Contents/Resources/"
  cp -R "$b" "$STAGE/"
done
cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>XiaxiaV3Demo</string>
  <key>CFBundleIdentifier</key><string>com.srmming.xiaxia-ledger.v3demo</string>
  <key>CFBundleName</key><string>夏夏账本 v3 试用</string>
  <key>CFBundleDisplayName</key><string>夏夏账本 v3 试用</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>v3 试用</string>
  <key>CFBundleVersion</key><string>$(git rev-parse --short HEAD)</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>XiaxiaV3</key><true/>
</dict></plist>
PLIST
mkdir -p "$DEST"
if [ -e "$APP" ]; then mv "$APP" "$(dirname "$STAGE")/旧的.app"; fi
mv "$STAGE" "$APP"
echo "做好了：$APP"
