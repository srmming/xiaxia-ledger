#!/usr/bin/env bash
# 在 ming 的 Mac 上打正式版：用钥匙串里的 Developer ID 证书签名、带 iCloud 同步权限、交给苹果公证，做成 dmg。
# 证书和公证密码都只在这台 Mac 的钥匙串里，不上传到任何地方。
#
#   bash scripts/release-local.sh            # 打包到 dist/
#   bash scripts/release-local.sh --install  # 打包后顺便装到 ~/Applications（先退出正在开的夏夏账本，旧版挪到废纸篓）
#   bash scripts/release-local.sh --iphone   # 装到用线连着这台 Mac 的 iPhone（不上架、不走 TestFlight，开发者账号签名，一年内有效）
#
# 第一次用前要做一次（见 docs/DISTRIBUTE.md「明早要点的」）：
#   - Xcode → 设置 → 账户 登录开发者 Apple ID，在「管理证书」里加 Developer ID Application
#   - xcrun notarytool store-credentials xiaxia-notary --apple-id <Apple ID> --team-id U33A8DX2JT
set -euo pipefail
TEAM="${XIAXIA_TEAM:-U33A8DX2JT}"
PROFILE="${XIAXIA_NOTARY_PROFILE:-xiaxia-notary}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/xiaxia-release"
cd "$REPO/App"
xcodegen generate >/dev/null
VERSION="$(grep MARKETING_VERSION project.yml | grep -oE '[0-9.]+' | head -1)"
# 每次上传 TestFlight 的构建号要比上次大：用时间当构建号。
BUILDNO="$(date +%Y%m%d%H%M)"

if [ "${1:-}" = "--iphone" ]; then
  # iPhone 第一次要：用线连 Mac、点「信任这台电脑」、设置 → 隐私与安全性 → 开发者模式 打开（会重启一次）。
  echo "• 编译 iPhone 版 $VERSION（$BUILDNO，带 iCloud）"
  xcodebuild -project XiaxiaLedger.xcodeproj -scheme XiaxiaLedger-iOS -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$BUILD/ios" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic XIAXIA_ICLOUD=YES CURRENT_PROJECT_VERSION="$BUILDNO" \
    build | grep -E "error|BUILD" || true
  IPA_APP="$BUILD/ios/Build/Products/Release-iphoneos/夏夏账本.app"
  test -d "$IPA_APP"
  DEV="$(xcrun devicectl list devices 2>/dev/null | grep -iE "connected|available \(paired\)" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)"
  [ -n "$DEV" ] || { echo "没找到连着的 iPhone：用线连上、解锁、点「信任」，再跑一次"; exit 1; }
  echo "• 装到 iPhone（$DEV）"
  xcrun devicectl device install app --device "$DEV" "$IPA_APP"
  echo "装好了。iPhone 上打开夏夏账本，用和 Mac 同一个 Apple ID 的 iCloud，就是同一本账。"
  exit 0
fi
echo "• 归档 Release $VERSION（团队 $TEAM，带 iCloud）"
xcodebuild -project XiaxiaLedger.xcodeproj -scheme XiaxiaLedger-macOS -configuration Release \
  -archivePath "$BUILD/XiaxiaLedger.xcarchive" -destination 'generic/platform=macOS' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" XIAXIA_ICLOUD=YES CURRENT_PROJECT_VERSION="$BUILDNO" \
  archive | grep -E "error|ARCHIVE" || true
test -d "$BUILD/XiaxiaLedger.xcarchive"
echo "• 导出 Developer ID 版（Xcode 自动申请带 iCloud 的 Developer ID 描述文件，签好 app 和里面的 fin）"
OPTS="$(mktemp).plist"
cat > "$OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
rm -rf "$BUILD/export"
xcodebuild -exportArchive -archivePath "$BUILD/XiaxiaLedger.xcarchive" -exportPath "$BUILD/export" \
  -exportOptionsPlist "$OPTS" -allowProvisioningUpdates | grep -E "error|EXPORT" || true
APP="$BUILD/export/夏夏账本.app"
test -x "$APP/Contents/MacOS/fin"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "iCloud.com.srmming.xiaxia-ledger" || { echo "app 没带上 iCloud 权限"; exit 1; }
ID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "$TEAM" | head -1 | grep -oE '[0-9A-F]{40}')"
[ -n "$ID" ] || { echo "钥匙串里没有 Developer ID Application 证书，先按 docs/DISTRIBUTE.md 建一个"; exit 1; }
mkdir -p "$REPO/dist"; DMG="$REPO/dist/夏夏账本-$VERSION.dmg"
STAGE="$(mktemp -d)"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/应用程序"
hdiutil create -volname "夏夏账本" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$ID" "$DMG"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "• 交给苹果公证（几分钟）"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -vv -t install "$DMG"
  echo "做好了：$DMG"
else
  # 自己这台 Mac 用不需要公证；发给别人前要先 store-credentials（见 docs/DISTRIBUTE.md）。
  echo "⚠︎ 钥匙串里还没有公证密码（$PROFILE），dmg 没公证，只适合自己用：$DMG"
fi
if [ "${1:-}" = "--install" ]; then
  osascript -e 'tell application "夏夏账本" to quit' 2>/dev/null || true; sleep 2
  DEST="$HOME/Applications/夏夏账本.app"
  [ -e "$DEST" ] && osascript -e "tell application \"Finder\" to delete POSIX file \"$DEST\"" >/dev/null
  ditto "$APP" "$DEST"
  echo "已装到 $DEST（旧版在废纸篓）"
fi
