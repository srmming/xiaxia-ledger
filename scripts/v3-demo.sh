#!/bin/bash
# 打开「Mac 界面 v3」开发版（不签名、只用编的示例数字，不读不写任何账本）。
# 用法：bash scripts/v3-demo.sh            从引导第一步开始
#       bash scripts/v3-demo.sh overview   直接进某一页：overview / goals / wealth / ob1…ob5 / firststep / smallerstep / letter
set -e
cd "$(dirname "$0")/.."
swift build --product XiaxiaLedgerApp
BIN="$(swift build --show-bin-path)/XiaxiaLedgerApp"
if [ -n "$1" ]; then exec "$BIN" -XiaxiaV3 1 -XiaxiaV3Page "$1"; else exec "$BIN" -XiaxiaV3 1; fi
