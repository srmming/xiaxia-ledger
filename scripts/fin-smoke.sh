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
export XIAXIA_NO_OPEN=1
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
run where
[ "$("$FIN" where)" = "$XIAXIA_LEDGER_PATH" ] || { echo "↳ fin where 和 XIAXIA_LEDGER_PATH 对不上"; FAILS=$((FAILS + 1)); }

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
# 生意模式关闭时，命令行和 MCP 的返回文字、落盘改动说明均沿用原文。
python3 - "$FIN" "$WORK/旧版记账文案.json" <<'CHECK_ADD' || FAILS=$((FAILS + 1))
import json, os, subprocess, sys
fin, path = sys.argv[1:]
env = dict(os.environ, XIAXIA_LEDGER_PATH=path)
def run(*args, input=None):
    return subprocess.check_output([fin, *args], input=input, env=env, text=True)
def last_change():
    with open(path, encoding="utf-8") as f:
        return json.load(f)["changes"][-1]

run("account", "add", "cash", "测试现金", "--kind", "cash")
summary = "记一笔 1,00 € 测试收款"
out = run("add", "1", "测试收款", "--account", "cash", "--book", "personal")
change = last_change()
short_id = change["id"][:8]
assert change["summary"] == summary
assert out == f"已记：{summary}（改动 {short_id}，写错了用 fin undo {short_id} 撤销）\n"
args = {"amount":"1", "description":"测试收款", "account":"cash", "book":"personal"}
request = {"jsonrpc":"2.0", "id":1, "method":"tools/call", "params":{"name":"add_transaction", "arguments":args}}
response = json.loads(run("mcp", input=json.dumps(request) + "\n"))["result"]
change = last_change()
assert not response["isError"] and change["summary"] == summary
assert response["content"][0]["text"] == f"已记：{summary}\n改动 id：{change['id'][:8].lower()}（写错了用 undo 撤销）"
CHECK_ADD
run business on --book shop --json
run business status --json
run capital set --total 1000 --recovered-before 10 --json
run capital --json
run add --side business --account cash --dry-run -- -5 花材
run profit --month 2026-11 --json
run business off --json
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
run goal deposit 应急金 3,20 --from caixa --held-back 咖啡
run goal plan 1200 --deadline 2027-06-30
run goal main 旅行
run goal check 应急金 keep
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

echo; echo "===== 自己动手记账：算式、备注、标签、复制、拆开、退款、重复 ====="
run add --account cash --book personal --category 餐饮 --date 2026-11-20 --note 和小王AA --tag 聚餐 --tag 周末 -- -12,50-3,20 火锅
ID_HOTPOT=$("$FIN" tx --query 火锅 | cut -f1)
"$FIN" tx --query 火锅 | grep -q -- "-15,70" && echo "算式 -12,50-3,20 记成了 -15,70" || { echo "↳ 算式金额不对"; FAILS=$((FAILS + 1)); }
run tx --tag 聚餐
run tx --query "#周末" --kind expense
run tx --query 小王
run edit "$ID_HOTPOT" --note 改过的备注 --tags "聚餐,朋友"
run tag "$ID_HOTPOT" --add 报销 --remove 朋友
run copy "$ID_HOTPOT" --date 2026-11-21
run add --account caixa --book personal --category 超市 --date 2026-11-21 -- -48,30 大超市
ID_BIG=$("$FIN" tx --query 大超市 | cut -f1)
expect_fail split "$ID_BIG" 30:超市 10:日用品
run split "$ID_BIG" 30:超市 18,30:日用品:洗衣液
"$FIN" tx --query 洗衣液 | grep -q 日用品 && echo "拆开存进账本了" || { echo "↳ 拆开没存进账本"; FAILS=$((FAILS + 1)); }
run add --account caixa --book personal --category 购物 --date 2026-11-15 -- -60 鞋子
ID_SHOES=$("$FIN" tx --query 鞋子 | cut -f1)
expect_fail refund "$ID_SHOES" --amount 70
run refund "$ID_SHOES" --amount 20 --date 2026-11-18
run add --account caixa --book personal --category 住房 --date 2026-09-01 --repeat monthly -- -650 房租
run repeat list
run repeat run --date 2026-11-22
run repeat run --date 2026-11-22
"$FIN" tx --query 房租 | wc -l | grep -q 3 && echo "房租 9、10、11 月各一笔" || { echo "↳ 房租笔数不对"; "$FIN" tx --query 房租; FAILS=$((FAILS + 1)); }
run repeat pause 房租
"$FIN" repeat list | grep -q 暂停中 && echo "暂停存进账本了" || { echo "↳ 暂停没存进账本"; FAILS=$((FAILS + 1)); }
run repeat resume 房租
run repeat set "$ID_SHOES" yearly --dry-run
run repeat rm 房租
"$FIN" repeat list | grep -q 房租 && { echo "↳ 停掉没存进账本"; FAILS=$((FAILS + 1)); } || echo "停掉存进账本了"

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

echo; echo "===== 多币种（不联网：没取过汇率时外币先按 1:1 算） ====="
run account add usdcard 美元卡 --currency USD
expect_fail account add bad 坏币种 --currency XYZ
run add --account usdcard --book personal --category 软件 --date 2026-11-02 -- -20 OpenAI
run add --account caixa --book personal --category 旅行 --date 2026-11-05 --original "50 USD" -- -46,12 Hotel
run fx
run accounts
run tx --limit 3
ID_USD=$("$FIN" tx --account usdcard | head -1 | cut -f1)
run fx set-rate "$ID_USD" --bank 18,40
run fx set-rate "$ID_USD" --rate 0,9 --dry-run
run summary --month 2026-11
run fx base USD --dry-run

echo; echo "===== 订阅 ====="
for m in 07 08 09 10 11; do "$FIN" add --account caixa --book personal --category 娱乐 --date 2026-$m-03 -- -12,99 "NETFLIX.COM 866" >/dev/null; done
run subscription find
run subscription add 视频会员 12,99 --next 2026-12-03 --account caixa --match netflix --category 娱乐
run subscription add 云盘 29,99 --cycle yearly --next 2027-02-01
expect_fail subscription add 坏周期 5 --cycle biweekly --next 2027-01-01
run subscriptions
run subscription edit 视频 --amount 13,99
run subscription cancel 云盘
run subscriptions --all --json
run subscription find

echo; echo "===== 夏夏的记忆 ====="
run memory
run memory add 转给妈妈的钱 "转给妈妈的钱不算支出，算家里往来。" --kind rule --quote "给我妈的钱别算花销" --author Claude
run memory add 工资 "明年 1 月起涨一点。" --review-on 2027-01-31 --link category:工资
run memory add 工资 "6 月和 12 月多发一份。" --source confirmed
expect_fail memory add 工资 "6 月和 12 月多发一份。"
expect_fail memory add 我的工资 "同一件事换个名字再记一遍"
expect_fail memory add 银行卡 "卡号 4111 1111 1111 1111"
expect_fail memory add 坏挂法 "挂在不存在的账户上" --link account:nosuch
run memory add 导入对账单 "还信用卡是账户互转，别记成支出。" --kind lesson --source corrected --story "第一次导入时算成了支出"
run memory add 旧打算 "去年说过想换手机。" --review-on 2026-01-31
run memory
run memory list --kind rule
run memory list --json
run memory show 工资
run memory search 妈妈
run memory edit 工资 --pin
run memory edit 转给妈妈的钱 --text "转给妈妈的钱算家里往来，不算支出。" --dry-run
expect_fail memory edit 工资 --text "两行的话题不说改哪一行"
run memory tidy
run memory tidy --json
run memory edit 旧打算 --keep --dry-run
run memory tidy --remove 旧打算
run memory forget 导入对账单 --dry-run
run memory forget 导入对账单
run memory forget 转给妈妈的钱 --forever
run history --limit 6
run memory
run regulars
run regulars --json

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
echo; echo "MCP 握手后记下连上的 AI 工具（app 的连 AI 引导靠它显示「连上了」）："
if grep -q smoke-client "$WORK/ai-connections.json" 2>/dev/null; then cat "$WORK/ai-connections.json"; else echo "↳ 没记下 ai-connections.json"; FAILS=$((FAILS + 1)); fi
call() { mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"smoke-client"}}}' \
             "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
         | tail -1 | python3 -c 'import json,sys; r=json.load(sys.stdin); res=r.get("result") or r; print(("出错 " if res.get("isError") else "") + "\n".join(c["text"] for c in res.get("content",[])) if "content" in res else json.dumps(r, ensure_ascii=False))'; }
for spec in \
  'context|{}' \
  'welcome|{}' \
  'import_rows|{"account":"cash","rows":[{"date":"2026-11-03","amount":"-12,50","description":"烟测超市"},{"date":"bad","amount":"1","description":"x"}],"dry_run":true}' \
  'list_transactions|{"month":"2026-11","limit":3}' \
  'list_transactions|{"query":"mercadona"}' \
  'list_transactions|{"include_private":true,"account":"stash"}' \
  'summary|{"month":"2026-11"}' \
  'summary|{"month":"2026-11","book":"shop"}' \
  'accounts|{}' \
  'monthly_report|{"month":"2026-11"}' \
  'reconcile|{"account":"revolut","balance":"110,05"}' \
  'business_status|{}' \
  'business_on|{"book":"shop","dry_run":true}' \
  'business_off|{"dry_run":true}' \
  'profit|{"month":"2026-11"}' \
  'capital|{}' \
  'capital_set|{"total":"1200","dry_run":true}' \
  'add_transaction|{"amount":"12","description":"测试收款","account":"cash","side":"business","dry_run":true}' \
  'account_transfer|{"amount":"10","from_account":"caixa","to_account":"cash","dry_run":true}' \
  'add_account|{"id":"n26","name":"N26","opening_balance":"200","dry_run":true}' \
  'debts|{}' 'installments|{}' 'goals|{}' 'history|{"limit":3}' \
  'add_transaction|{"amount":"-9,99","description":"MCP 测试","account":"cash","book":"personal","dry_run":true}' \
  'add_transaction|{"amount":"-9,99","description":"MCP 测试","account":"cash","book":"personal","category":"餐饮"}' \
  'add_transaction|{"amount":"-1","description":"坏账本","account":"cash","book":"nobook"}' \
  'add_debt|{"counterparty":"阿梅","direction":"they_owe_me","amount":"80","account":"cash","dry_run":true}' \
  'repay_debt|{"counterparty":"阿华","amount":"50","account":"cash","dry_run":true}' \
  'plan_debt|{"counterparty":"阿华","count":3,"start":"2026-12-20","dry_run":true}' \
  'goal_deposit|{"name":"应急金","amount":"20","from_account":"caixa","dry_run":true}' \
  'goal_deposit|{"name":"应急金","amount":"3,20","from_account":"caixa","held_back":"咖啡"}' \
  'plan_goal|{"target":"1500","deadline":"2027-06-30"}' \
  'goal_check|{"name":"应急金","choice":"pause","dry_run":true}' \
  'set_goal_stash|{"name":"应急金","stash":"jar","stash_note":"书桌上的小猪"}' \
  "import_statement|{\"file\":\"$WORK/revolut.csv\",\"account\":\"revolut\",\"format\":\"revolut\",\"dry_run\":true}" \
  'add_book|{"name":"家庭","kind":"personal"}' \
  'add_transaction|{"amount":"-2,20*3","description":"MCP 咖啡","account":"cash","book":"personal","category":"餐饮","note":"三杯","tags":["上班"]}' \
  'list_transactions|{"tag":"上班"}' \
  'list_transactions|{"query":"三杯","kind":"expense"}' \
  'add_transaction|{"amount":"-9","description":"MCP 话费","account":"cash","book":"personal","category":"通讯","repeat":"monthly"}' \
  'list_recurring|{}' \
  'update_recurring|{"key":"MCP 话费","action":"pause"}' \
  'run_recurring|{}' \
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
  'add_category|{"name":"奶茶","icon":"bubbletea"}' \
  'add_category|{"name":"坏图标","icon":"nosuchicon"}' \
  'set_category_icon|{"name":"餐饮","icon":"hotpot"}' \
  'set_category_icon|{"name":"餐饮","icon":""}' \
  'list_category_icons|{}' \
  'set_profile|{"persona":"sharp","aim":"每个月存下 500 €"}' \
  'set_profile|{"persona":"pirate"}' \
  'list_insights|{}' 'ai_status|{}' \
  'currency|{}' \
  'set_account_currency|{"account":"pot","currency":"CNY","dry_run":true}' \
  'set_base_currency|{"currency":"XYZ"}' \
  'add_transaction|{"amount":"-30","description":"国外刷卡","account":"cash","book":"personal","original":"35 USD","dry_run":true}' \
  'subscriptions|{}' 'find_subscriptions|{}' \
  'add_subscription|{"name":"音乐会员","amount":"10,99","cycle":"monthly","next_date":"2026-12-10","account":"caixa"}' \
  'edit_subscription|{"subscription":"音乐会员","amount":"11,99"}' \
  'edit_subscription|{"subscription":"音乐会员","cancel":true,"dry_run":true}' \
  'remove_subscription|{"subscription":"没有这个"}' \
  'memory|{}' \
  'remember|{"title":"房租","text":"合同签到明年 8 月底。","links":["category:房租"],"review_on":"2027-08-31"}' \
  'remember|{"text":"房东说到期可能要涨。","topic":"房租","quote":"到期再说吧"}' \
  'remember|{"title":"房租合同","text":"换个名字再记一遍"}' \
  'remember|{"title":"网银","text":"网银密码 123456"}' \
  'remember|{"title":"收益","text":"我说收益是指店里赚的，不算工资。","kind":"rule","source":"corrected","story":"问收益时答成了工资加店里收入","dry_run":true}' \
  'memory|{"query":"房租"}' \
  'memory|{"link":"category:房租"}' \
  'memory|{"kind":"topic"}' \
  'update_memory|{"id":"房租","pinned":true}' \
  'update_memory|{"id":"房租","text":"两行的话题不说改哪一行"}' \
  'tidy_memory|{}' \
  'tidy_memory|{"done":true,"dry_run":true}' \
  'forget_memory|{"id":"房租","dry_run":true}' \
  'forget_memory|{"id":"房租","forever":true,"dry_run":true}' \
  'forget_memory|{"id":"没有这条"}' \
  'regulars|{}' \
  'current_view|{}' \
  'open_in_app|{"page":"spending","month":"2026-10","note":"看看 10 月"}' \
  'open_in_app|{"page":"nopage"}' \
  'nope|{}' ; do
  echo; echo "MCP › ${spec%%|*} ${spec#*|}"
  call "${spec%%|*}" "${spec#*|}"
done

echo; echo "import_rows 预演（AI 读懂 Excel / PDF / 支付宝账单后批量导入）："
if call import_rows '{"account":"cash","rows":[{"date":"2026-11-03","amount":"-12,50","description":"烟测超市"},{"date":"bad","amount":"1","description":"x"}],"dry_run":true}' | grep -q "读到 1 笔"; then
  echo "读到 1 笔，坏的那行跳过了"
else echo "↳ import_rows 预演不对"; FAILS=$((FAILS + 1)); fi

echo; echo "open_in_app 留给 app 的纸条："
if grep -q '"花销"' "$WORK/open.json" 2>/dev/null; then cat "$WORK/open.json"; else echo "↳ 没写出 open.json"; FAILS=$((FAILS + 1)); fi

echo; echo "===== fin connect：让 AI 自己把夏夏账本连上（在假的主目录里试） ====="
FAKEHOME="$WORK/home"; mkdir -p "$FAKEHOME/.codex" "$FAKEHOME/.hermes"
printf 'model:\n  provider: "deepseek"\n' > "$FAKEHOME/.hermes/config.yaml"
HOME="$FAKEHOME" run connect --list
HOME="$FAKEHOME" run connect codex
HOME="$FAKEHOME" run connect --all --dry-run
expect_fail connect nosuchtool
HOME="$FAKEHOME" run connect hermes
grep -q "provider: \"deepseek\"" "$FAKEHOME/.hermes/config.yaml" && grep -q "xiaxia-ledger:" "$FAKEHOME/.hermes/config.yaml" && cat "$FAKEHOME/.hermes/config.yaml" || { echo "↳ Hermes 配置不对"; FAILS=$((FAILS + 1)); }
grep -q "mcp_servers.xiaxia-ledger" "$FAKEHOME/.codex/config.toml" && cat "$FAKEHOME/.codex/config.toml" || { echo "↳ Codex 配置没写进去"; FAILS=$((FAILS + 1)); }

echo; echo "===== fin setup：粘一段话给 AI，它跑这条把 MCP、skill、提示词都装好（假的主目录） ====="
SETHOME="$WORK/sethome"; mkdir -p "$SETHOME/.codex" "$SETHOME/.claude"
printf '# 我自己的规矩\n' > "$SETHOME/.claude/CLAUDE.md"
HOME="$SETHOME" run setup --dry-run
[ -e "$SETHOME/.agents/skills/fin" ] && { echo "↳ 预演却装了 skill"; FAILS=$((FAILS + 1)); }
HOME="$SETHOME" run setup
HOME="$SETHOME" "$FIN" setup | tee "$WORK/setup2.txt"
grep -q "没有要改的" "$WORK/setup2.txt" || { echo "↳ 第二次跑还在改东西"; FAILS=$((FAILS + 1)); }
grep -q "✓	账本自检" "$WORK/setup2.txt" || { echo "↳ 自检没过"; FAILS=$((FAILS + 1)); }
for f in "$SETHOME/.agents/skills/fin/SKILL.md" "$SETHOME/.claude/skills/fin/SKILL.md" "$SETHOME/.codex/skills/fin/references/commands.md"; do
  [ -f "$f" ] || { echo "↳ 没有 $f"; FAILS=$((FAILS + 1)); }
done
[ "$(grep -c xiaxia-ledger:start "$SETHOME/.claude/CLAUDE.md")" = 1 ] && grep -q "我自己的规矩" "$SETHOME/.claude/CLAUDE.md" || { echo "↳ CLAUDE.md 不对"; FAILS=$((FAILS + 1)); }
grep -q "mcp_servers.xiaxia-ledger" "$SETHOME/.codex/config.toml" && grep -q xiaxia-ledger "$SETHOME/.claude.json" || { echo "↳ MCP 没写进去"; FAILS=$((FAILS + 1)); }
HOME="$SETHOME" run setup --check --json
HOME="$SETHOME" run setup --remove
[ -e "$SETHOME/.agents/skills/fin" ] && { echo "↳ --remove 没拿掉 skill"; FAILS=$((FAILS + 1)); }
grep -q xiaxia-ledger "$SETHOME/.claude/CLAUDE.md" && { echo "↳ --remove 没拿掉提示词"; FAILS=$((FAILS + 1)); }
expect_fail setup nosuchtool
"$FIN" setup --prompt | grep -q "setup --check" || { echo "↳ setup --prompt 不对"; FAILS=$((FAILS + 1)); }

echo; echo "===== 历史里的作者 ====="
"$FIN" history --limit 4

echo; echo "===== 删账本：有流水的要先挪 ====="
expect_fail book rm shop
run book rm shop --move-to personal --dry-run
expect_fail book rm personal --move-to personal

echo; echo "===== fin demo：一键生成示例账本（全是编的），读出来看看 ====="
DEMO="$WORK/demo/示例账本.sqlite"
run demo --out "$DEMO" --end 2026-11-20
expect_fail demo --out "$DEMO" --end 2026-11-20
run demo --out "$DEMO" --end 2026-11-20 --force --json
expect_fail demo --out "$WORK/demo/x.txt"
echo '{"schemaVersion":1}' > "$WORK/demo/real.json"
expect_fail demo --out "$WORK/demo/real.json" --force
REAL_TMP="$XIAXIA_LEDGER_PATH"
export XIAXIA_LEDGER_PATH="$DEMO"
  run context
  run accounts
  run summary --month 2026-10
  run summary --month 2026-10 --book shop
  run report --month 2026-11
  run debts
  run installments
  run goals
  run insight list
  run memory
  run memory tidy
  run regulars
  run history --limit 8
  run tx --limit 8
  run reconcile --account daily --balance 1000
export XIAXIA_LEDGER_PATH="$REAL_TMP"
# 同一天、同一个种子，两次生成的账本一模一样。
"$FIN" demo --out "$WORK/demo/a.json" --end 2026-11-20 >/dev/null && "$FIN" demo --out "$WORK/demo/b.json" --end 2026-11-20 >/dev/null
cmp -s "$WORK/demo/a.json" "$WORK/demo/b.json" && echo "两次生成一模一样" || { echo "↳ 两次生成不一样"; FAILS=$((FAILS + 1)); }

echo; echo "===== 手机记的：小纸条收进账本、入账、挂小票、报销（SQLite 账本在临时「夏夏账本」文件夹） ====="
JSON_TMP="$XIAXIA_LEDGER_PATH"
PHONE_DIR="$WORK/夏夏账本"; mkdir -p "$PHONE_DIR/手机记的"
export XIAXIA_LEDGER_PATH="$PHONE_DIR/ledger.sqlite"
run account add card "示例卡" --kind bank
CARD=card
# 假装 iPhone 写了一张纸条：说了一句、拍了一张小票
printf 'fake-jpeg' > "$WORK/receipt.jpg"
mkdir -p "$PHONE_DIR/附件"; cp "$WORK/receipt.jpg" "$PHONE_DIR/附件/smoke-photo.jpg"
cat > "$PHONE_DIR/手机记的/20261123-120000-000-smoke.json" <<'NOTE'
{"id":"20261123-120000-000-smoke","device":"iPhone","createdAt":"2026-11-23T12:00:00Z","summary":"待记录：午饭 10 欧",
 "captures":[{"id":"11111111-2222-3333-4444-555555555555","kind":"text","text":"午饭 10 欧","guess":{"amount":{"cents":-1000}},
   "createdAt":"2026-11-23T12:00:00Z","device":"iPhone","status":"pending"},
  {"id":"66666666-2222-3333-4444-555555555555","kind":"photo","text":"","photo":"smoke-photo.jpg",
   "createdAt":"2026-11-23T12:01:00Z","device":"iPhone","status":"pending"}]}
NOTE
run phone
[ -f "$PHONE_DIR/手机记的/已收/20261123-120000-000-smoke.json" ] || { echo "↳ 纸条没挪进「已收」"; FAILS=$((FAILS + 1)); }
run phone resolve 11111111 -10 "午饭" --account "$CARD" --book personal --category 餐饮 --date 2026-11-23
run phone resolve 66666666 -5,50 "咖啡小票" --account "$CARD" --book personal
expect_fail phone resolve 11111111 -10 "午饭" --account "$CARD" --book personal
TXID="$(first_id --query 咖啡小票)"
run receipt "$TXID" "$WORK/receipt.jpg" --invoice
run reimburse set toSubmit "$TXID" --to "示例公司"
run reimburse
run reimburse export --folder "$WORK/export"
ls "$WORK/export"/报销清单-*/报销清单.csv >/dev/null 2>&1 || { echo "↳ 没导出 CSV"; FAILS=$((FAILS + 1)); }
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"phone_notes","arguments":{"all":true}}}' | "$FIN" mcp | head -c 400; echo
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reimbursements","arguments":{}}}' | "$FIN" mcp | grep -q "待提交" || { echo "↳ MCP reimbursements 不对"; FAILS=$((FAILS + 1)); }
export XIAXIA_LEDGER_PATH="$JSON_TMP"

rm -rf "$WORK"
echo; echo "意外失败：$FAILS 处"
[ "$FAILS" -eq 0 ]
