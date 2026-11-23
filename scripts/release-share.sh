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

cd "$REPO/App"
xcodegen generate >/dev/null
COMMON=(-project XiaxiaLedger.xcodeproj -scheme XiaxiaLedger-macOS -configuration Release
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD/dd"
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILDNO" XIAXIA_ICLOUD=NO)
[ -n "${XIAXIA_SPARKLE_PUBLIC_KEY:-}" ] && COMMON+=(XIAXIA_SPARKLE_PUBLIC_KEY="$XIAXIA_SPARKLE_PUBLIC_KEY")

if [ $ADHOC = 1 ]; then
  echo "• 编译 Release $VERSION（$BUILDNO，不带 iCloud，临时签名）"
  rm -rf "$BUILD/dd/Build/Products"
  xcodebuild "${COMMON[@]}" CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build | grep -E "error:|BUILD" || true
  APP="$BUILD/dd/Build/Products/Release/夏夏账本.app"
  test -x "$APP/Contents/MacOS/fin" || { echo "编译失败"; exit 1; }
  echo "• 临时签名：从里到外，Sparkle 的小程序也要签"
  # 临时签名不能开 hardened runtime：库校验会把临时签名的 Sparkle.framework 当成别家团队的，app 一打开就闪退。
  SIGN=(codesign --force --sign -)
  SP="$APP/Contents/Frameworks/Sparkle.framework"
  if [ -d "$SP" ]; then
    for x in "$SP"/Versions/B/XPCServices/Installer.xpc "$SP"/Versions/B/XPCServices/Downloader.xpc "$SP"/Versions/B/Autoupdate "$SP"/Versions/B/Updater.app; do
      [ -e "$x" ] && "${SIGN[@]}" --preserve-metadata=entitlements "$x"
    done
    "${SIGN[@]}" "$SP"
  fi
  "${SIGN[@]}" "$APP/Contents/MacOS/fin"
  "${SIGN[@]}" "$APP"
else
  # Developer ID：Xcode 用 ming 登录的开发者账号（团队 $TEAM）里云端管理的 Developer ID 证书签名，
  # 本机钥匙串不需要有证书，也不会弹窗（2026-11-23 在 ming 的 Mac 上实测）。Sparkle 和 fin 一起签好。
  echo "• 归档 Release $VERSION（$BUILDNO，不带 iCloud）"
  rm -rf "$BUILD/XiaxiaLedger.xcarchive" "$BUILD/export"
  xcodebuild "${COMMON[@]}" -archivePath "$BUILD/XiaxiaLedger.xcarchive" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic archive | grep -E "error:|ARCHIVE" || true
  test -d "$BUILD/XiaxiaLedger.xcarchive" || { echo "归档失败"; exit 1; }
  echo "• 导出 Developer ID 版"
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
  xcodebuild -exportArchive -archivePath "$BUILD/XiaxiaLedger.xcarchive" -exportPath "$BUILD/export" \
    -exportOptionsPlist "$OPTS" -allowProvisioningUpdates | grep -E "error:|EXPORT" || true
  APP="$BUILD/export/夏夏账本.app"
  test -x "$APP/Contents/MacOS/fin" || { echo "导出失败"; exit 1; }
  # codesign -dv 不打 Authority，要 -dvv；用 grep -c 免得 pipefail 下 grep -q 提前关管道误判。
  codesign -dvv "$APP" 2>&1 | grep -c "Developer ID Application" >/dev/null || { echo "没签上 Developer ID"; exit 1; }
fi
KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ -n "$KEY" ] || echo "⚠︎ 还没填更新签名公钥（App/project.yml 的 XIAXIA_SPARKLE_PUBLIC_KEY），这个包不会自动更新"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "iCloud"; then echo "包里不该有 iCloud 权限"; exit 1; fi

echo "• 做 dmg"
mkdir -p "$REPO/dist"; DMG="$REPO/dist/XiaxiaLedger-$VERSION.dmg"
STAGE="$(mktemp -d)"; ditto "$APP" "$STAGE/夏夏账本.app"; ln -s /Applications "$STAGE/应用程序"
[ $ADHOC = 1 ] && cp "$REPO/App/DMG/打不开看这里.txt" "$STAGE/"
rm -f "$DMG"; hdiutil create -volname "夏夏账本" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [ $ADHOC = 0 ]; then
  echo "• 交给苹果公证（几分钟）"
  if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  elif command -v asc >/dev/null; then
    # ming 的 Mac 上 asc 命令行存着一把 App Store Connect API 密钥（在钥匙串里），能直接公证，不用 app 专用密码。
    asc notarization submit --file "$DMG" --wait
  else
    echo "没有公证凭据：按 docs/DISTRIBUTE.md 存一个 notarytool 的 $PROFILE"; exit 1
  fi
  xcrun stapler staple "$DMG"
  # dmg 本身没签名（本机没有 Developer ID 证书，只有 Xcode 云端证书给 app 签），spctl 查 dmg 一定是 rejected；
  # 改查公证票据钉上了没有、里面的 app 过不过 Gatekeeper。
  xcrun stapler validate "$DMG"
  spctl -a -vv "$APP"
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
  # 不出增量包：generate_appcast 在临时目录里生成 .delta，跑完就删了不会上传，appcast 却会指向它（线上 404）。
  "$GEN" --maximum-deltas 0 --download-url-prefix "$BASE/download/" -o "$REPO/dist/appcast.xml" "$ARCH"
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
    [ -f "$REPO/site/deploy.sh" ] || { echo "更新网址是 $BASE，但没有 site/deploy.sh"; exit 1; }
    # 只传 dist/appcast.xml、dist/download/、dist/release-notes/；服务器设置在 site/deploy.env（不进仓库）或环境变量 XIAXIA_SSH / XIAXIA_DIR / XIAXIA_DOMAIN。
    (cd "$REPO" && bash site/deploy.sh --release) ;;
esac
echo "发布好了：别人的 app 一天内左下角会提醒更新到 $VERSION"
