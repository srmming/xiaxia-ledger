#!/bin/bash
# 用示例数据（全是编的）给 Mac 版和 iPhone 版每一页截图。先要编译好（App/build 下）。
# 用法：bash scripts/screenshots.sh <输出目录>
set -u
OUT="${1:-screenshots}"
mkdir -p "$OUT"
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
  ios 8-dark -XiaxiaDemo
  xcrun simctl ui "$DEVICE" appearance light 2>/dev/null || true
  ios 9-empty -XiaxiaEmpty
fi

# GitHub 的机器截不到 Mac 窗口（只有黑屏），所以 CI 上跳过 Mac 部分；在自己的 Mac 上跑会截。
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
  mac 1-overview -XiaxiaDemo
  mac 2-spending -XiaxiaDemo -XiaxiaSection spending
  mac 3-trends -XiaxiaDemo -XiaxiaSection trends
  mac 4-wealth -XiaxiaDemo -XiaxiaSection wealth
  mac 5-plans -XiaxiaDemo -XiaxiaSection plans
  mac 6-ai -XiaxiaDemo -XiaxiaSection insights
  mac 7-changes -XiaxiaDemo -XiaxiaSection changes
  mac 8-transactions -XiaxiaDemo -XiaxiaSection transactions
  mac 9-settings -XiaxiaDemo -XiaxiaSection settings
  mac 10-add -XiaxiaDemo -XiaxiaSheet add
  mac 11-empty -XiaxiaEmpty
fi
ls -la "$OUT"
