#!/bin/bash
# 用示例数据（全是编的）给 Mac 版和 iPhone 版每一页截图。先要编译好（App/build 下）。
# 用法：bash scripts/screenshots.sh <输出目录>
set -u
OUT="${1:-screenshots}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_APP="$(find "$ROOT/App/build/Build/Products" -path '*iphonesimulator*' -name '*.app' -maxdepth 2 | head -1)"
MAC_APP="$(find "$ROOT/App/build/Build/Products/Debug" -name '*.app' -maxdepth 1 | head -1)"
BUNDLE=com.srmming.xiaxia-ledger

if [ -n "$IOS_APP" ]; then
  DEVICE="$(xcrun simctl list devices available | grep -E 'iPhone 1[5-9]( Pro)? \(' | head -1 | grep -oE '[0-9A-F-]{36}')"
  echo "模拟器：$DEVICE"
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null
  xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 2>/dev/null || true
  xcrun simctl install "$DEVICE" "$IOS_APP"
  ios() {
    local name="$1"; shift
    xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$DEVICE" "$BUNDLE" "$@" -AppleLanguages "(zh-Hans)" -AppleLocale es_ES >/dev/null
    sleep 9
    xcrun simctl io "$DEVICE" screenshot "$OUT/ios-$name.png" >/dev/null 2>&1
  }
  ios 1-overview -XiaxiaDemo
  ios 2-spending -XiaxiaDemo -XiaxiaSection spending
  ios 3-trends -XiaxiaDemo -XiaxiaSection trends
  ios 4-wealth -XiaxiaDemo -XiaxiaSection wealth
  ios 5-plans -XiaxiaDemo -XiaxiaSection plans
  ios 6-ai -XiaxiaDemo -XiaxiaSection insights
  ios 7-add -XiaxiaDemo -XiaxiaSheet add
  xcrun simctl ui "$DEVICE" appearance dark 2>/dev/null || true
  ios 20-add-dark -XiaxiaDemo -XiaxiaSheet add
  xcrun simctl ui "$DEVICE" appearance light 2>/dev/null || true
  xcrun simctl ui "$DEVICE" appearance dark 2>/dev/null || true
  ios 8-dark -XiaxiaDemo
  xcrun simctl ui "$DEVICE" appearance light 2>/dev/null || true
  ios 9-empty -XiaxiaEmpty
  ios 10-books -XiaxiaDemo -XiaxiaSheet books
  ios 11-accounts -XiaxiaDemo -XiaxiaSheet accounts
  ios 12-categories -XiaxiaDemo -XiaxiaSheet categories
  ios 13-empty-wealth -XiaxiaEmpty -XiaxiaSection wealth
  ios 14-empty-add -XiaxiaEmpty -XiaxiaSheet add
  ios 15-new-plan -XiaxiaDemo -XiaxiaSheet plan
  ios 16-empty-plans -XiaxiaEmpty -XiaxiaSection plans
  ios 17-new-category -XiaxiaDemo -XiaxiaSheet newCategory
  xcrun simctl ui "$DEVICE" appearance dark 2>/dev/null || true
  ios 18-categories-dark -XiaxiaDemo -XiaxiaSheet categories
  ios 19-spending-dark -XiaxiaDemo -XiaxiaSection spending
  xcrun simctl ui "$DEVICE" appearance light 2>/dev/null || true
fi

# GitHub 的机器上 screencapture 只有黑屏，改让 app 自己把窗口画成图（-XiaxiaSnapshot），不用屏幕录制权限。
if [ -n "$MAC_APP" ] && [ -n "${CI:-}" ]; then
  BIN="$MAC_APP/Contents/MacOS/$(basename "$MAC_APP" .app)"
  snap() {
    local name="$1"; shift
    # 用 open 启动，让 app 被激活。系统参数（-AppleLanguages 这种成对的）放前面：
    # 开关都带上值（-XiaxiaDemo 1）：参数凑不成「-键 值」对时，多出来的那个词会被 macOS 当成要打开的文件，
    # app 就不开主窗口了（只有个数凑成双数的那次截到了）。
    open -n -a "$MAC_APP" --stdout "$OUT/mac-$name.log" --stderr "$OUT/mac-$name.log" \
      --args -AppleLanguages "(zh-Hans)" -AppleLocale es_ES -XiaxiaSnapshot "$OUT/mac-$name.png" "$@"
    for _ in $(seq 1 45); do [ -f "$OUT/mac-$name.png" ] && break; pgrep -f "$BIN" >/dev/null || break; sleep 1; done
    sleep 1
    pkill -9 -f "$BIN" 2>/dev/null
    if [ -f "$OUT/mac-$name.png" ]; then echo "mac-$name 截好了"; rm -f "$OUT/mac-$name.log"
    else echo "mac-$name 没截到"; tail -5 "$OUT/mac-$name.log" 2>/dev/null; fi
  }
  snap 1-overview -XiaxiaDemo 1
  snap 6-ai -XiaxiaDemo 1 -XiaxiaSection insights
  snap 9-settings -XiaxiaDemo 1 -XiaxiaSection settings
  snap 11-empty-ai -XiaxiaEmpty 1 -XiaxiaSection insights
  snap 20-connect-ai -XiaxiaEmpty 1 -XiaxiaSheet connectAI
  snap 21-connect-ai-no-tools -XiaxiaEmpty 1 -XiaxiaNoTools 1 -XiaxiaSheet connectAI
  snap 23-new-category -XiaxiaDemo 1 -XiaxiaSheet newCategory
  snap 24-spending -XiaxiaDemo 1 -XiaxiaSection spending
  snap 25-add -XiaxiaDemo 1 -XiaxiaSheet add
  snap 26-add-empty -XiaxiaEmpty 1 -XiaxiaSheet add
  snap 22-connect-ai-dark -XiaxiaEmpty 1 -XiaxiaSheet connectAI -AppleInterfaceStyle Dark
fi

# 在自己的 Mac 上跑会用 screencapture 截整屏。
if [ -n "$MAC_APP" ] && [ -z "${CI:-}" ]; then
  BIN="$MAC_APP/Contents/MacOS/$(basename "$MAC_APP" .app)"
  mac() {
    local name="$1"; shift
    # 用 open 启动，窗口才会到最前面
    open -n -a "$MAC_APP" --args "$@" -AppleLanguages "(zh-Hans)" -AppleLocale es_ES
    sleep 8
    osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is '"$(pgrep -n -f "$BIN" || echo 0)"') to true' 2>/dev/null || true
    sleep 1
    if pgrep -f "$BIN" >/dev/null; then echo "mac-${name} 在运行"; else echo "mac-${name} 已经退出了（可能崩溃）"; fi
    # 截图限时，卡住了也不拖住后面几页
    screencapture -x "$OUT/mac-$name.png" 2>/dev/null &
    local sp=$!
    for _ in 1 2 3 4 5 6 7 8; do kill -0 $sp 2>/dev/null || break; sleep 1; done
    kill -9 $sp 2>/dev/null
    pkill -9 -f "$BIN" 2>/dev/null
    sleep 1
  }
  mac 1-overview -XiaxiaDemo 1
  mac 2-spending -XiaxiaDemo 1 -XiaxiaSection spending
  mac 3-trends -XiaxiaDemo 1 -XiaxiaSection trends
  mac 4-wealth -XiaxiaDemo 1 -XiaxiaSection wealth
  mac 5-plans -XiaxiaDemo 1 -XiaxiaSection plans
  mac 6-ai -XiaxiaDemo 1 -XiaxiaSection insights
  mac 7-changes -XiaxiaDemo 1 -XiaxiaSection changes
  mac 8-transactions -XiaxiaDemo 1 -XiaxiaSection transactions
  mac 9-settings -XiaxiaDemo 1 -XiaxiaSection settings
  mac 10-add -XiaxiaDemo 1 -XiaxiaSheet add
  mac 11-empty -XiaxiaEmpty 1
  mac 12-books -XiaxiaDemo 1 -XiaxiaSheet books
  mac 13-accounts -XiaxiaDemo 1 -XiaxiaSheet accounts
  mac 20-connect-ai -XiaxiaEmpty 1 -XiaxiaSheet connectAI
  mac 14-new-plan -XiaxiaDemo 1 -XiaxiaSheet plan
fi
ls -la "$OUT"
