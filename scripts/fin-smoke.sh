#!/usr/bin/env bash
# 用一份临时的示例账本（全是编的）把 fin 的每个命令和 MCP 服务实际跑一遍，输出给人和 AI 看。
# 用法：bash scripts/fin-smoke.sh [fin 的路径]   不填就用 .build/debug/fin
# 绝不碰真实账本：XIAXIA_LEDGER_PATH 一定指向临时目录。
set -u
FIN="${1:-.build/debug/fin}"
FIN="$(cd "$(dirname "$FIN")" && pwd)/$(basename "$FIN")"
WORK="$(mktemp -d)"
export XIAXIA_LEDGER_PATH="$WORK/ledger.json"
export XIAXIA_AUTHOR="smoke"
FAILS=0

run() {
  echo
  echo "\$ fin $*"
  "$FIN" "$@" 2>&1
  local code=$?
  [ $code -ne 0 ] && { echo "↳ 退出码 $code"; FAILS=$((FAILS + 1)); }
  return 0
}
# 预期会失败的命令（比如锁定目标不能取钱）
expect_fail() {
  echo
  echo "\$ fin $*   （预期失败）"
  if "$FIN" "$@" 2>&1; then echo "↳ 没有失败，不对"; FAILS=$((FAILS + 1)); fi
  return 0
}
first_id() { "$FIN" tx "$@" --limit 1 | head -1 | cut -f1; }

echo "临时账本：$XIAXIA_LEDGER_PATH"

echo; echo "===== 空账本：新用户只有「个人」，自己加账本 ====="
run books
run book add Shop --kind business
run book add "家庭" --kind personal
run books
expect_fail book add "家庭"
run book rename shop "小店" --dry-run
run context
run context --json
run books
run accounts

echo; echo "===== 建账户 ====="
run account add cash 现金 --kind cash --dry-run
run account add cash 现金 --kind cash
run account add caixa Caixa
run account add revolut Revolut
run account add pot 储蓄罐 --kind savings
run account add stash 私房钱 --kind cash --private
run accounts --json

echo; echo "===== 记一笔 ====="
run add --account cash --book personal --category 餐饮 --date 2026-11-03 --dry-run -- -12,50 超市
run add --account cash --book personal --category 餐饮 --date 2026-11-03 --author Claude -- -12,50 超市
run add --account caixa --book shop --date 2026-11-04 -- 300 客人付款
run add --account caixa --book shop --category 材料 --date 2026-11-05 --json -- -45.90 指甲油
run add --account caixa --book personal --category 工资 --date 2026-11-01 -- 1.234,56 工资
run add -20 私房零花 --account stash --book personal --date 2026-11-06
expect_fail add --account cash --book personal -- abc 坏金额
expect_fail add --account cash --book personal --date 21/11/2026 -- -5 坏日期
expect_fail add --account cash --book nobook -- -5 没这个账本
expect_fail add --account nope --book personal -- -5 没这个账户

echo; echo "===== 查 ====="
run tx
run tx --book shop --json
run tx --month 2026-11 --category 餐饮
run summary --month 2026-11
run summary --month 2026-11 --book shop --json

echo; echo "===== 整理：分类、分账本 ====="
ID_PAY=$(first_id --book shop --category "" 2>/dev/null)
ID_PAY=$("$FIN" tx --book shop | grep 客人付款 | cut -f1)
run categorize --category 服务收入 "$ID_PAY" --dry-run
run categorize --category 服务收入 "$ID_PAY"
ID_SUPER=$("$FIN" tx | grep 超市 | cut -f1)
run assign --book shop "$ID_SUPER" --dry-run
run assign --book personal "$ID_SUPER"

echo; echo "===== 借款往来 ====="
run debt add 阿华 500 --they-owe-me --account cash --date 2026-11-02 --due 2026-12-01 --dry-run
run debt add 阿华 500 --they-owe-me --account cash --date 2026-11-02 --due 2026-12-01
run debt add 小李 200 --i-owe --note 旧账
run debts
run debt repay 阿华 100 --account cash --date 2026-11-10
run debts --json

echo; echo "===== 转账 ====="
run transfer new 200 --from shop --to personal --account caixa --date 2026-11-12 --dry-run
run transfer new 200 --from shop --to personal --account caixa --date 2026-11-12
run transfer move 50 --from-account caixa --to-account cash --date 2026-11-13 --note 取现
run add --account caixa --book personal --date 2026-11-14 -- -100 转到Revolut
ID_TOPUP=$("$FIN" tx | grep 转到Revolut | cut -f1)
run transfer mark "$ID_TOPUP" --counter-account revolut
run summary --month 2026-11

echo; echo "===== 分期 ====="
run installment add 美甲灯 329,40 --count 6 --account caixa --book shop --date 2026-11-08 --category 设备 --dry-run
run installment add 美甲灯 329,40 --count 6 --account caixa --book shop --date 2026-11-08 --category 设备
run installment pay 美甲灯 --date 2026-11-20
run installments
run installments --json

echo; echo "===== 目标 ====="
run goal add 应急金 6000 --deadline 2027-06-30
run goal add 旅行 1000 --savings-account pot --locked
run goal deposit 应急金 300 --from caixa --date 2026-11-15
run goal withdraw 应急金 100 --to caixa --date 2026-11-16
run goal deposit 旅行 50 --from caixa
expect_fail goal withdraw 旅行 10 --to caixa
run goals
run goals --json

echo; echo "===== 导入对账单 ====="
cat > "$WORK/revolut.csv" <<'CSV'
Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
CARD_PAYMENT,Current,2026-11-17 10:00:00,2026-11-17 10:01:00,Mercadona,-23.40,0.00,EUR,COMPLETED,100.00
CARD_PAYMENT,Current,2026-11-18 12:00:00,2026-11-18 12:01:00,Zara,-39.95,0.00,EUR,COMPLETED,60.05
TOPUP,Current,2026-11-19 09:00:00,2026-11-19 09:00:00,Top-Up by *1234,50.00,0.00,EUR,COMPLETED,110.05
CSV
run import "$WORK/revolut.csv" --account revolut --dry-run
run import "$WORK/revolut.csv" --account revolut --format revolut
run import "$WORK/revolut.csv" --account revolut --format revolut
cat > "$WORK/caixa.csv" <<'CSV'
Fecha;Concepto;Importe
19/11/2026;BAZAR CHINO;-8,20
20/11/2026;BIZUM DE CLIENTA;35,00
CSV
run import "$WORK/caixa.csv" --account caixa --date-col Fecha --amount-col Importe --desc-col Concepto --book shop --dry-run
run import "$WORK/caixa.csv" --account caixa --date-col Fecha --amount-col Importe --desc-col Concepto --book shop

echo; echo "===== 改、删、对账、月报、开账余额 ====="
ID_SALARY=$("$FIN" tx | grep 工资 | cut -f1)
run edit "$ID_SALARY" --amount=1.300,00 --dry-run
run edit "$ID_SALARY" --amount=1.300,00 --category 工资
ID_BAZAR=$("$FIN" tx | grep -i bazar | cut -f1)
run rm "$ID_BAZAR" --dry-run
run rm "$ID_BAZAR"
run account opening revolut 100 --date 2026-11-01
run reconcile --account revolut --balance 110,05 --date 2026-11-19
run reconcile --account cash --balance=-1
run report --month 2026-11
run report --month 2026-11 --book shop

echo; echo "===== 改动记录、撤销 ====="
run history
LAST=$("$FIN" history --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"][:8])')
run undo "$LAST" --dry-run
run undo "$LAST"
run history --limit 3

echo; echo "===== 说明书（有数据后） ====="
run context

echo; echo "===== 私房钱是否隐藏 ====="
echo "（stash 账户里有一笔 -20 私房零花）"
"$FIN" tx | grep -q 私房零花 && echo "fin tx：显示了私房钱" || echo "fin tx：没显示私房钱"

echo; echo "===== MCP ====="
mcp() { printf '%s\n' "$@" | "$FIN" mcp 2>&1; }
mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"smoke-client","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | python3 -c '
import json, sys
for line in sys.stdin:
    m = json.loads(line)
    r = m.get("result", {})
    if "tools" in r:
        print("tools/list：", ", ".join(t["name"] for t in r["tools"]))
    else:
        print(json.dumps(m, ensure_ascii=False)[:600])
'
call() { mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"smoke-client"}}}' \
             "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
         | tail -1 | python3 -c 'import json,sys; r=json.load(sys.stdin); res=r.get("result") or r; print(("出错 " if res.get("isError") else "") + "\n".join(c["text"] for c in res.get("content",[])) if "content" in res else json.dumps(r, ensure_ascii=False))'; }
for spec in \
  'context|{}' \
  'list_transactions|{"month":"2026-11","limit":3}' \
  'list_transactions|{"query":"mercadona"}' \
  'list_transactions|{"include_private":true,"account":"stash"}' \
  'summary|{"month":"2026-11"}' \
  'summary|{"month":"2026-11","book":"shop"}' \
  'accounts|{}' \
  'monthly_report|{"month":"2026-11"}' \
  'reconcile|{"account":"revolut","balance":"110,05"}' \
  'account_transfer|{"amount":"10","from_account":"caixa","to_account":"cash","dry_run":true}' \
  'add_account|{"id":"n26","name":"N26","opening_balance":"200","dry_run":true}' \
  'debts|{}' 'installments|{}' 'goals|{}' 'history|{"limit":3}' \
  'add_transaction|{"amount":"-9,99","description":"MCP 测试","account":"cash","book":"personal","dry_run":true}' \
  'add_transaction|{"amount":"-9,99","description":"MCP 测试","account":"cash","book":"personal","category":"餐饮"}' \
  'add_transaction|{"amount":"-1","description":"坏账本","account":"cash","book":"nobook"}' \
  'add_debt|{"counterparty":"阿梅","direction":"they_owe_me","amount":"80","account":"cash","dry_run":true}' \
  'repay_debt|{"counterparty":"阿华","amount":"50","account":"cash","dry_run":true}' \
  'goal_deposit|{"name":"应急金","amount":"20","from_account":"caixa","dry_run":true}' \
  "import_statement|{\"file\":\"$WORK/revolut.csv\",\"account\":\"revolut\",\"format\":\"revolut\",\"dry_run\":true}" \
  'add_book|{"name":"家庭","kind":"personal"}' \
  'rename_book|{"book":"shop","name":"小店","dry_run":true}' \
  'remove_book|{"book":"shop","dry_run":true}' \
  'remove_book|{"book":"shop","move_to":"personal","dry_run":true}' \
  'edit_account|{"account":"cash","name":"钱包现金","dry_run":true}' \
  'remove_account|{"account":"caixa","dry_run":true}' \
  'rename_category|{"from":"餐饮","to":"吃饭","dry_run":true}' \
  'add_insight|{"kind":"tip","title":"测试提醒","body":"编的"}' \
  'add_insight|{"kind":"alert","title":"花销页提醒","page":"spending"}' \
  'add_insight|{"kind":"alert","title":"坏页面","page":"nopage"}' \
  'add_category|{"name":"宠物"}' \
  'add_category|{"name":"宠物"}' \
  'set_profile|{"persona":"sharp","aim":"每个月存下 500 €"}' \
  'set_profile|{"persona":"pirate"}' \
  'list_insights|{}' 'ai_status|{}' \
  'nope|{}' ; do
  echo; echo "MCP › ${spec%%|*} ${spec#*|}"
  call "${spec%%|*}" "${spec#*|}"
done

echo; echo "===== 历史里的作者 ====="
"$FIN" history --limit 4

echo; echo "===== 删账本：有流水的要先挪 ====="
expect_fail book rm shop
run book rm shop --move-to personal --dry-run
expect_fail book rm personal --move-to personal

rm -rf "$WORK"
echo; echo "意外失败：$FAILS 处"
[ "$FAILS" -eq 0 ]
