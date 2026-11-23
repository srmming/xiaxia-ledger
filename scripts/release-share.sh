#!/usr/bin/env bash
# 做给别人用的 Mac 安装包（不带 iCloud 权限、不带任何账本数据），并发布自动更新。
# 在 ming 的 Mac 上跑。证书、公证密码、更新签名私钥都只在这台 Mac 的钥匙串里。
#
#   bash scripts/release-share.sh 0.2.0              # Developer ID 签名 + 公证 + 发布更新（推荐）
#   bash scripts/release-share.sh 0.2.0 --adhoc      # 临时签名，别人第一次打开要去「隐私与安全性」点「仍要打开」
#   加 --no-publish：只做 dmg，不推到更新仓库
#
# 产物：dist/appcast.xml 和 dist/download/；发布时由 site/deploy.sh 传到官网（网址前缀见 App/project.yml 的 XIAXIA_UPDATE_BASE）。别人的 app 每天看一次 appcast，有新版就在左下角提醒。
set -euo pipefail
VERSION="${1:?用法：release-share.sh <版本号，比如 0.2.0> [--adhoc] [--no-publish]}"; shift
ADHOC=0; PUBLISH=1
for a in "$@"; do case "$a" in --adhoc) ADHOC=1 ;; --no-publish) PUBLISH=0 ;; *) echo "不认识的参数 $a"; exit 1 ;; esac; done
TEAM="${XIAXIA_TEAM:-U33A8DX2JT}"
PROFILE="${XIAXIA_NOTARY_PROFILE:-xiaxia-notary}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/xiaxia-share"
RELEASES="${XIAXIA_RELEASES_DIR:-$HOME/xiaxia-ledger-releases}"
BUILDNO="$(date +%Y%m%d%H%M)"

if [ $ADHOC = 1 ]; then ID="-"; else
  ID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "$TEAM" | head -1 | grep -oE '[0-9A-F]{40}' || true)"
  [ -n "$ID" ] || { echo "钥匙串里没有 Developer ID Application 证书：按 docs/DISTRIBUTE.md「要 ming 本人做的」建一个，或者先加 --adhoc"; exit 1; }
fi

cd "$REPO/App"
xcodegen generate >/dev/null
echo "• 编译 Release $VERSION（$BUILDNO，不带 iCloud）"
rm -rf "$BUILD/dd/Build/Products"
xcodebuild -project XiaxiaLedger.xcodeproj -scheme XiaxiaLedger-macOS -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD/dd" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILDNO" XIAXIA_ICLOUD=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ${XIAXIA_SPARKLE_PUBLIC_KEY:+XIAXIA_SPARKLE_PUBLIC_KEY="$XIAXIA_SPARKLE_PUBLIC_KEY"} \
  build | grep -E "error:|BUILD" || true
APP="$BUILD/dd/Build/Products/Release/夏夏账本.app"
test -x "$APP/Contents/MacOS/fin" || { echo "编译失败"; exit 1; }
KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ -n "$KEY" ] || echo "⚠︎ 还没填更新签名公钥（App/project.yml 的 XIAXIA_SPARKLE_PUBLIC_KEY），这个包不会自动更新"

echo "• 签名（$([ $ADHOC = 1 ] && echo 临时签名 || echo Developer ID)）：从里到外，Sparkle 的小程序也要签"
# 临时签名不能开 hardened runtime：库校验会把临时签名的 Sparkle.framework 当成别家团队的，app 一打开就闪退。
SIGN=(codesign --force --sign "$ID")
[ $ADHOC = 1 ] || SIGN+=(--options runtime --timestamp)
SP="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SP" ]; then
  for x in "$SP"/Versions/B/XPCServices/Installer.xpc "$SP"/Versions/B/Autoupdate "$SP"/Versions/B/Updater.app; do
    [ -e "$x" ] && "${SIGN[@]}" "$x"
  done
  [ -e "$SP/Versions/B/XPCServices/Downloader.xpc" ] && "${SIGN[@]}" --preserve-metadata=entitlements "$SP/Versions/B/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$SP"
fi
"${SIGN[@]}" "$APP/Contents/MacOS/fin"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "iCloud"; then echo "包里不该有 iCloud 权限"; exit 1; fi

echo "• 做 dmg"
mkdir -p "$REPO/dist"; DMG="$REPO/dist/XiaxiaLedger-$VERSION.dmg"
STAGE="$(mktemp -d)"; ditto "$APP" "$STAGE/夏夏账本.app"; ln -s /Applications "$STAGE/应用程序"
cp "$REPO/App/DMG/打不开看这里.txt" "$STAGE/"
rm -f "$DMG"; hdiutil create -volname "夏夏账本" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [ $ADHOC = 0 ]; then
  codesign --force --timestamp --sign "$ID" "$DMG"
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || { echo "钥匙串里还没有公证密码（$PROFILE），见 docs/DISTRIBUTE.md"; exit 1; }
  echo "• 交给苹果公证（几分钟）"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -vv -t install "$DMG"
fi
echo "dmg：$DMG"

# 更新清单和安装包统一放在 dist/：dist/appcast.xml、dist/download/xiaxia-ledger-<版本>.dmg、dist/download/xiaxia-ledger.dmg（最新版）。
BASE="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" | sed 's|/appcast.xml$||')"
mkdir -p "$REPO/dist/download"
cp "$DMG" "$REPO/dist/download/xiaxia-ledger-$VERSION.dmg"
cp "$DMG" "$REPO/dist/download/xiaxia-ledger.dmg"
# 只留最近 3 个版本
ls -t "$REPO"/dist/download/xiaxia-ledger-*.dmg | tail -n +4 | while read -r old; do rm -f "$old"; done
if [ -n "$KEY" ]; then
  GEN="$(find "$BUILD/dd/SourcePackages/artifacts" -path '*/bin/generate_appcast' -type f | head -1)"
  [ -x "$GEN" ] || { echo "没找到 Sparkle 的 generate_appcast"; exit 1; }
  ARCH="$(mktemp -d)"; cp "$REPO"/dist/download/xiaxia-ledger-*.dmg "$ARCH/"
  "$GEN" --download-url-prefix "$BASE/download/" -o "$REPO/dist/appcast.xml" "$ARCH"
  rm -rf "$ARCH"
fi
echo "更新清单：$REPO/dist/appcast.xml（网址前缀 $BASE）"

[ $PUBLISH = 1 ] || exit 0
[ -n "$KEY" ] || { echo "没有更新公钥，不发布"; exit 1; }
case "$BASE" in
  https://raw.githubusercontent.com/srmming/xiaxia-ledger-releases/*)
    [ -d "$RELEASES/.git" ] || { echo "没找到更新仓库 $RELEASES：先 git clone https://github.com/srmming/xiaxia-ledger-releases ~/xiaxia-ledger-releases"; exit 1; }
    echo "• 推到 xiaxia-ledger-releases"
    git -C "$RELEASES" pull -q --ff-only
    rm -rf "$RELEASES/download"; mkdir -p "$RELEASES/download"
    cp "$REPO"/dist/download/*.dmg "$RELEASES/download/"
    cp "$REPO/dist/appcast.xml" "$RELEASES/appcast.xml"
    cat > "$RELEASES/README.md" <<MD
# 夏夏账本 · 下载

最新版 $VERSION：[下载](https://raw.githubusercontent.com/srmming/xiaxia-ledger-releases/main/download/xiaxia-ledger.dmg)

打开 dmg，把「夏夏账本」拖进「应用程序」，再双击打开。以后有新版，app 左下角会提醒，点一下就更新。

本仓库只放安装包和更新信息，不含源代码。© srmming，保留所有权利。
MD
    git -C "$RELEASES" add -A
    git -C "$RELEASES" commit -qm "夏夏账本 $VERSION（$BUILDNO）"
    git -C "$RELEASES" push -q ;;
  *)
    # 官网（自己的服务器）：site/deploy.sh 把 dist/ 里的 dmg 和 appcast.xml 一起传上去。
    [ -x "$REPO/site/deploy.sh" ] || { echo "更新网址是 $BASE，但没有 site/deploy.sh"; exit 1; }
    bash "$REPO/site/deploy.sh" ;;
esac
echo "发布好了：别人的 app 一天内左下角会提醒更新到 $VERSION"
