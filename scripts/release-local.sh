#!/usr/bin/env bash
# 在 ming 的 Mac 上打正式版：用钥匙串里的 Developer ID 证书签名、带 iCloud 同步权限、交给苹果公证，做成 dmg。
# 证书和公证密码都只在这台 Mac 的钥匙串里，不上传到任何地方。
#
#   bash scripts/release-local.sh            # 打包到 dist/
#   bash scripts/release-local.sh --install  # 打包后顺便装到 ~/Applications（先退出正在开的夏夏账本，旧版挪到废纸篓）
#   bash scripts/release-local.sh --iphone   # 打 iPhone 版直接传到 App Store Connect，几分钟后出现在 TestFlight
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
  echo "• 归档 iPhone 版 $VERSION（$BUILDNO，带 iCloud）"
  xcodebuild -project XiaxiaLedger.xcodeproj -scheme XiaxiaLedger-iOS -configuration Release \
    -archivePath "$BUILD/XiaxiaLedger-iOS.xcarchive" -destination 'generic/platform=iOS' -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic XIAXIA_ICLOUD=YES CURRENT_PROJECT_VERSION="$BUILDNO" \
    archive | grep -E "error|ARCHIVE" || true
  test -d "$BUILD/XiaxiaLedger-iOS.xcarchive"
  OPTS="$(mktemp).plist"
  cat > "$OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
  echo "• 上传到 App Store Connect（要先在网页上建好 App，见 docs/DISTRIBUTE.md）"
  xcodebuild -exportArchive -archivePath "$BUILD/XiaxiaLedger-iOS.xcarchive" -exportPath "$BUILD/export-ios" \
    -exportOptionsPlist "$OPTS" -allowProvisioningUpdates
  echo "传好了。苹果处理 5–15 分钟后，iPhone 上的 TestFlight app 里就能装。"
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
echo "• 交给苹果公证（几分钟）"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -vv -t install "$DMG"
echo "做好了：$DMG"
if [ "${1:-}" = "--install" ]; then
  osascript -e 'tell application "夏夏账本" to quit' 2>/dev/null || true; sleep 2
  DEST="$HOME/Applications/夏夏账本.app"
  [ -e "$DEST" ] && osascript -e "tell application \"Finder\" to delete POSIX file \"$DEST\"" >/dev/null
  ditto "$APP" "$DEST"
  echo "已装到 $DEST（旧版在废纸篓）"
fi
