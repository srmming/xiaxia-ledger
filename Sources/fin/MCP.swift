import ArgumentParser
import FinanceCore
import Foundation

/// `fin mcp`：MCP 服务（stdio，一行一个 JSON-RPC 消息）。给 Claude 桌面版、Codex、DeepSeek 这类 AI 工具用，
/// 和命令行是同一套规则：写入都记改动记录，作者默认取 AI 工具报上来的名字，能撤销。
struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "启动 MCP 服务（stdio），让 AI 工具查账、记账。",
        discussion: """
        Claude 桌面版 / Claude Code 配置示例：
          { "mcpServers": { "xiaxia-ledger": { "command": "/usr/local/bin/fin", "args": ["mcp"] } } }
        """)

    func run() throws {
        let server = MCPServer()
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let reply = server.handle(line) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
    }
}

final class MCPServer {
    var clientName = "AI"

    /// 握手时告诉 AI 怎么用这本账。所有接上的 AI 工具都能看到，所以只写通用规矩，不写某个人的账户和店名。
    static let instructions = """
    夏夏账本：用户自己的记账本（Mac 上的本地文件，app 和这个 MCP 读写同一份），可以有好几个账本（个人、家庭、店……）。app 里的 AI 叫「夏夏」。
    用户说到记一笔、花了多少、收支、余额、月报、对账、导入对账单、分类、谁欠我钱、还款、分期、存钱目标时用这些工具。
    1. 先调用 context：账本、账户 id、余额、数据覆盖到哪天、统计口径、夏夏的说话方式（voice）和用户的目标（aim）都在里面。账户 id、账本 id 只用 context 里有的，别猜。context 里还有夏夏的记忆（memory：用户定的规矩照做，目录里有相关话题就用 memory 工具读出来）、每月固定进出（regulars）和问什么用哪个工具（toolGuide）。用户说「记住……」「以后都……」用 remember 记下来。
    2. 拿不准的（哪个账户、哪个账本、什么分类、是不是自己账户之间转钱）先在对话里问用户，确认后再写。
    3. 导入和一次改多笔先用 dry_run 预演，把会改什么列给用户，同意后再正式写。单笔且信息齐全可以直接写。用户发来银行 Excel / PDF、支付宝或微信账单、别的记账 App 导出的文件：你自己读懂，整理成 rows 用 import_rows 导入（标准 CSV 文件路径也可以用 import_statement）。
    4. 写完告诉用户记了什么和改动编号；写错用 undo 撤销。
    5. 不算收支的：借款和还款、存取目标、自己账户之间转钱、分期每期还款；分期买的那天按全额算支出；退款冲减原分类的支出。
    6. 私房钱账户（isPrivate）只在用户本人问时提。金额按账本的格式显示（如 1.234,56 €）。连不上账本就直说，不要编数字。
    7. 用户说「这笔」「这个月」「我在看的这个」时，先用 current_view 看用户在 app 里停在哪、选中了哪一笔。答完想让用户在 app 里看到，用 open_in_app 让 app 跳过去、圈出那几笔。
    8. 用户说刚装好夏夏账本、「带我记下第一笔」「开始记账」时：先调用 welcome，照它返回的步骤带用户走。
    9. 用用户说话的语言回答（用户说中文就用中文）。不要主动报账本里有几笔、有哪些账户，用户问了再说。
    10. 用户说「同步今天的」「把手机上记的入账」：用 phone_notes 看手机上记的待记录，逐条理解金额、日期、账户、分类，和已有流水去重（重复的用 link_phone_note），能确定的用 resolve_phone_note 入账，拿不准的先问用户；小票用小票上的日期，超过两个月先问。做完说记了几笔、还剩几条没处理。报销用 reimbursements / set_reimbursement。
    """
    let protocolVersion = "2025-06-18"

    /// 处理一条消息；通知（没有 id）不用回复，返回 nil。
    func handle(_ line: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "JSON 读不懂"] as [String: Any]])
        }
        let id = obj["id"]
        let method = obj["method"] as? String ?? ""
        let params = obj["params"] as? [String: Any] ?? [:]
        guard let id else { return nil }   // 通知，比如 notifications/initialized
        let result: Any
            switch method {
            case "initialize":
                if let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String, !name.isEmpty {
                    clientName = name
                }
                // 记下这个 AI 工具连上过（app 的「连 AI」引导据此显示「连上了」）。只记名字和时间。
                AIConnections.record(client: clientName)
                result = [
                    "protocolVersion": (params["protocolVersion"] as? String) ?? protocolVersion,
                    "capabilities": ["tools": [:] as [String: Any]],
                    "serverInfo": ["name": "xiaxia-ledger", "version": "0.2.5"],
                    "instructions": MCPServer.instructions,
                ] as [String: Any]
            case "ping":
                result = [:] as [String: Any]
            case "tools/list":
                result = ["tools": MCPTools.list]
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                // 每次用工具都记一下：有的 AI（Claude 桌面版）一直开着同一个连接，只在握手时记的话，app 等不到「刚刚来过」。
                AIConnections.record(client: clientName)
                do {
                    let text = try MCPTools.call(name, args, author: clientName)
                    result = ["content": [["type": "text", "text": text]], "isError": false] as [String: Any]
                } catch {
                    // 工具本身出错（比如找不到账户）按 MCP 约定放进结果里，让 AI 看到原因。
                    let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    result = ["content": [["type": "text", "text": "出错了：\(message)"]], "isError": true] as [String: Any]
                }
            default:
                return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "没有这个方法：\(method)"] as [String: Any]])
            }
        return encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    func encode(_ obj: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

struct ToolError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum MCPTools {
    static func prop(_ type: String, _ desc: String) -> [String: Any] { ["type": type, "description": desc] }
    static let author = prop("string", "不用填：会自动记成你这个 AI 工具的名字")
    static let dryRun = prop("boolean", "预演：只返回会改什么，不写进账本")

    static func tool(_ name: String, _ desc: String, _ props: [String: [String: Any]], required: [String] = [],
                     readOnly: Bool) -> [String: Any] {
        ["name": name, "description": desc,
         "inputSchema": ["type": "object", "properties": props, "required": required] as [String: Any],
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": false] as [String: Any]]
    }

    static let list: [[String: Any]] = [
        tool("context", "说明书：账本、账户和余额、数据覆盖日期、借款合计、最近改动、统计口径。先调这个。", [:], readOnly: true),
        tool("welcome", "新用户第一次记账的带路步骤。用户说刚装好夏夏账本、「带我记下第一笔」「开始记账」时先调这个，照返回的步骤做。", [:], readOnly: true),
        tool("list_transactions", "查流水。", [
            "book": prop("string", "账本 id，如 personal（fin books 能看到全部）；不填 = 全部"),
            "account": prop("string", "账户 id"),
            "month": prop("string", "月份，如 2026-11"),
            "category": prop("string", "分类"),
            "query": prop("string", "搜索：说明、商户、备注、标签、金额都搜；以 # 开头只按标签找"),
            "tag": prop("string", "只看带这个标签的"),
            "kind": ["type": "string", "enum": ["expense", "income"], "description": "只看支出或只看收入"],
            "limit": prop("integer", "最多几条，默认 50"),
            "include_private": prop("boolean", "包括私房钱账户。只有 用户本人问时才用"),
        ], readOnly: true),
        tool("summary", "收支和分类汇总：一个月（month）、一整年（year），或一段时间（from + to）。不填 book 是「全部」，账本间转账已抵消。", [
            "month": prop("string", "月份，如 2026-11"),
            "year": prop("integer", "整年，如 2026"),
            "from": prop("string", "从哪个月开始，如 2026-01"),
            "to": prop("string", "到哪个月为止，如 2026-06"),
            "book": prop("string", "账本 id"),
            "include_private": prop("boolean", "算上私房钱"),
        ], readOnly: true),
        tool("accounts", "每个账户现在的余额。私房钱账户默认不列。", ["include_private": prop("boolean", "包括私房钱账户。只有 用户本人问时才用")], readOnly: true),
        tool("monthly_report", "月报：进多少、花多少、花在哪、和上个月比、要留意什么。一份能直接读给用户 的文字。", [
            "month": prop("string", "月份，如 2026-11；不填 = 这个月"),
            "book": prop("string", "账本 id；不填 = 全部"),
            "include_private": prop("boolean", "算上私房钱"),
        ], readOnly: true),
        tool("reconcile", "对账：拿银行某一天的余额和账本比，返回差多少、可能差在哪几笔。只看不改。", [
            "account": prop("string", "账户 id"),
            "balance": prop("string", "银行那边的余额，如 382,64"),
            "date": prop("string", "这个余额是哪天的，默认今天"),
        ], required: ["account", "balance"], readOnly: true),
        tool("debts", "谁欠我钱、我欠谁：还欠多少、有没有过期。", ["include_closed": prop("boolean", "连已还清的也列出")], readOnly: true),
        tool("installments", "分期：第几期、每期多少、还剩多少、下次扣款日。", [:], readOnly: true),
        tool("history", "改动记录：谁、什么时候、改了什么。", ["limit": prop("integer", "最多几条，默认 20")], readOnly: true),
        tool("add_transaction", "记一笔收支。amount 负数是支出、正数是收入。repeat 填了就设成重复记账，以后到日子自动记。", [
            "amount": prop("string", "金额，如 -12,50 或 300；也可以是算式 -12,50-3,20"),
            "description": prop("string", "名称：买了什么、在哪花的"),
            "account": prop("string", "账户 id"),
            "book": prop("string", "账本 id"),
            "category": prop("string", "分类"),
            "date": prop("string", "日期 2026-11-21，默认今天。照小票、截图、账单记的，一定填上面印的日期，不要用今天"),
            "note": prop("string", "备注（可不填）"),
            "tags": ["type": "array", "items": ["type": "string"], "description": "标签，如 [\"旅行\"]，不带 #"],
            "repeat": ["type": "string", "enum": ["weekly", "monthly", "yearly"], "description": "重复：每周 / 每月 / 每年（可不填）"],
            "until": prop("string", "重复到哪天为止（可不填）"),
            "original": prop("string", "用别的币种付的原价，如「50 USD」（欧元卡在国外刷卡时）。amount 填银行扣的数"),
            "author": author, "dry_run": dryRun,
        ], required: ["amount", "description", "account", "book"], readOnly: false),
        tool("add_debt", "记一笔欠款。direction：they_owe_me（我借出去）或 i_owe（我借来的）。", [
            "counterparty": prop("string", "对方"),
            "direction": ["type": "string", "enum": ["they_owe_me", "i_owe"], "description": "方向"],
            "amount": prop("string", "金额，正数"),
            "book": prop("string", "账本 id，默认 personal"),
            "account": prop("string", "钱从哪个账户出 / 进；以前的旧账不填"),
            "date": prop("string", "借的日期，默认今天"),
            "due": prop("string", "约定哪天还"),
            "note": prop("string", "备注"),
            "author": author, "dry_run": dryRun,
        ], required: ["counterparty", "direction", "amount"], readOnly: false),
        tool("repay_debt", "记一笔还款。对方名字要能唯一对上一笔没还清的借款。这笔有还款计划、又比这期该还的多或少时，先不填 adjust 调一次（会告诉你差多少、每种调法哪天还清，不会写入），用选项框问用户选哪种，再带 adjust 调。", [
            "counterparty": prop("string", "对方"),
            "amount": prop("string", "还了多少，正数"),
            "account": prop("string", "钱进 / 出的账户 id"),
            "date": prop("string", "日期，默认今天"),
            "adjust": ["type": "string", "enum": ["shorten", "lower", "next", "extend", "none"],
                       "description": "有计划时多还 / 少还怎么调：多还 shorten = 抵最后几期（早点还清）、lower = 之后每期少还；少还 next = 差的补到下一期、extend = 顺延一期（差的放到最后）；none = 计划不动"],
            "author": author, "dry_run": dryRun,
        ], required: ["counterparty", "amount", "account"], readOnly: false),
        tool("plan_debt", "给一笔欠款排还款计划（欠款改分期，我欠的、欠我的都行）：填每月还多少（per_month）或分几期（count），自动算每期日期和金额。已经有计划的会重排。", [
            "counterparty": prop("string", "对方"),
            "per_month": prop("string", "每月还多少，如 125"),
            "count": prop("integer", "分几期"),
            "start": prop("string", "第一期哪天，如 2026-12-20；默认下个月今天"),
            "clear": prop("boolean", "true = 不要计划了"),
            "author": author, "dry_run": dryRun,
        ], required: ["counterparty"], readOnly: false),
        tool("edit_debt_plan", "改还款计划里的一期（第几期从 1 数）：差出来的钱从最后几期找补。只能改还没还完的期。", [
            "counterparty": prop("string", "对方"),
            "period": prop("integer", "第几期，从 1 数"),
            "amount": prop("string", "这一期改成多少"),
            "date": prop("string", "这一期改到哪天（可不填）"),
            "author": author, "dry_run": dryRun,
        ], required: ["counterparty", "period", "amount"], readOnly: false),
        tool("skip_debt_payment", "这一期没还（晚还）：adjust = next（这期的钱补到下一期）或 extend（顺延：这期起每期往后挪一个月）。先问用户选哪个。", [
            "counterparty": prop("string", "对方"),
            "adjust": ["type": "string", "enum": ["next", "extend"], "description": "next = 补到下期，extend = 顺延一期"],
            "author": author, "dry_run": dryRun,
        ], required: ["counterparty", "adjust"], readOnly: false),
        tool("edit_transaction", "改一笔流水，只填要改的那几项。转账、借款、分期、目标里的流水不能直接改，先 undo 再重新记。", [
            "id": prop("string", "流水 id（前 8 位也行）"),
            "amount": prop("string", "新金额，负数是支出"), "description": prop("string", "新说明"),
            "date": prop("string", "新日期"), "account": prop("string", "换到哪个账户"),
            "book": prop("string", "换到哪个账本"), "category": prop("string", "新分类"),
            "note": prop("string", "新备注；空字符串 = 清掉"),
            "tags": ["type": "array", "items": ["type": "string"], "description": "标签整个换成这些；空数组 = 清掉"],
            "author": author, "dry_run": dryRun,
        ], required: ["id"], readOnly: false),
        tool("split_transaction", "把一笔拆成几笔不同分类（超市小票里有吃的也有日用品）。每份金额写正数，合计要等于原来那笔。", [
            "id": prop("string", "流水 id（前 8 位也行）"),
            "parts": ["type": "array", "description": "每份：{amount: \"30\", category: \"超市\", description: 可不填}",
                      "items": ["type": "object", "properties": ["amount": prop("string", "金额，正数"), "category": prop("string", "分类"),
                                                                 "description": prop("string", "新说明（可不填）")] as [String: Any],
                                "required": ["amount"]] as [String: Any]],
            "author": author, "dry_run": dryRun,
        ], required: ["id", "parts"], readOnly: false),
        tool("duplicate_transaction", "照着一笔再记一笔（日期默认今天）。", [
            "id": prop("string", "流水 id"), "date": prop("string", "新日期，默认今天"), "author": author, "dry_run": dryRun,
        ], required: ["id"], readOnly: false),
        tool("add_refund", "给一笔支出记退款：钱回到同一个账户，分类「退款」，冲减支出。", [
            "id": prop("string", "原来那笔支出的 id"), "amount": prop("string", "退了多少，不填 = 全额"),
            "date": prop("string", "退款日期，默认今天"), "author": author, "dry_run": dryRun,
        ], required: ["id"], readOnly: false),
        tool("tag_transactions", "给几笔流水加 / 去标签。", [
            "ids": ["type": "array", "items": ["type": "string"], "description": "流水 id"],
            "add": ["type": "array", "items": ["type": "string"], "description": "要加的标签"],
            "remove": ["type": "array", "items": ["type": "string"], "description": "要去掉的标签"],
            "author": author, "dry_run": dryRun,
        ], required: ["ids"], readOnly: false),
        tool("list_recurring", "重复记账（房租、话费这种到日子自动记的）：多久一次、下次哪天、是否暂停。", [:], readOnly: true),
        tool("set_recurring", "把已有的一笔设成重复，从它的下一期开始自动记。", [
            "id": prop("string", "流水 id"),
            "frequency": ["type": "string", "enum": ["weekly", "monthly", "yearly"], "description": "每周 / 每月 / 每年"],
            "until": prop("string", "到哪天为止（可不填）"), "author": author, "dry_run": dryRun,
        ], required: ["id", "frequency"], readOnly: false),
        tool("update_recurring", "暂停、继续或停掉一条重复记账（已经记上的流水不动）。", [
            "key": prop("string", "list_recurring 里的 id 前 8 位，或说明里的字"),
            "action": ["type": "string", "enum": ["pause", "resume", "remove"], "description": "暂停 / 继续 / 停掉"],
            "author": author, "dry_run": dryRun,
        ], required: ["key", "action"], readOnly: false),
        tool("run_recurring", "把到日子的重复记账记上（app 打开时也会自动做）。", ["author": author, "dry_run": dryRun], readOnly: false),
        tool("delete_transactions", "删流水（能 undo 放回来）。先 dry_run 给用户 看要删哪几笔，确认后再删。", [
            "ids": ["type": "array", "items": ["type": "string"], "description": "流水 id"],
            "author": author, "dry_run": dryRun,
        ], required: ["ids"], readOnly: false),
        tool("account_transfer", "自己账户之间挪钱（取现、转到 Revolut、还信用卡）：记两笔，不算收入也不算支出。", [
            "amount": prop("string", "金额，正数"), "from_account": prop("string", "从哪个账户出"),
            "to_account": prop("string", "进哪个账户"), "date": prop("string", "日期，默认今天"),
            "note": prop("string", "说明"), "author": author, "dry_run": dryRun,
        ], required: ["amount", "from_account", "to_account"], readOnly: false),
        tool("mark_account_transfer", "把已导入的流水标成自己账户间转账，不再算收支。", [
            "ids": ["type": "array", "items": ["type": "string"], "description": "流水 id"],
            "counter_account": prop("string", "在这个账户补上另一半（如取现补到现金账户）；另一半已经导入过就不填"),
            "author": author, "dry_run": dryRun,
        ], required: ["ids"], readOnly: false),
        tool("add_account", "加一个账户，可以同时记开账余额。", [
            "id": prop("string", "账户 id，小写英文，如 revolut"), "name": prop("string", "显示名"),
            "kind": ["type": "string", "enum": ["bank", "credit", "cash", "wallet", "savings"], "description": "类型，默认 bank"],
            "private": prop("boolean", "私房钱：app 默认不显示、不算进总览"),
            "opening_balance": prop("string", "开账余额（可选）"), "date": prop("string", "开账余额是哪天的，默认今天"),
            "currency": prop("string", "账户币种，三个字母如 USD、CNY；不填 = 主币种"),
            "author": author, "dry_run": dryRun,
        ], required: ["id", "name"], readOnly: false),
        tool("add_book", "新建一个账本（比如家庭、第二家店）。kind：personal = 生活，business = 生意。", [
            "name": prop("string", "账本名字"),
            "kind": ["type": "string", "enum": ["personal", "business"], "description": "生活还是生意，默认 personal"],
            "author": author, "dry_run": dryRun,
        ], required: ["name"], readOnly: false),
        tool("rename_book", "给账本改名。", [
            "book": prop("string", "账本 id"), "name": prop("string", "新名字"), "author": author, "dry_run": dryRun,
        ], required: ["book", "name"], readOnly: false),
        tool("remove_book", "删账本。里面有流水、借款、分期或目标时，必须用 move_to 指定挪到哪个账本。先 dry_run 给用户看后果。", [
            "book": prop("string", "要删的账本 id"), "move_to": prop("string", "里面的东西挪到哪个账本（有东西时必填）"),
            "author": author, "dry_run": dryRun,
        ], required: ["book"], readOnly: false),
        tool("edit_account", "改账户：名字、类型、机构、是不是私房钱。只填要改的。", [
            "account": prop("string", "账户 id"), "name": prop("string", "新名字"),
            "kind": ["type": "string", "enum": ["bank", "credit", "cash", "wallet", "savings"], "description": "类型"],
            "institution": prop("string", "银行或机构"), "private": prop("boolean", "私房钱"),
            "author": author, "dry_run": dryRun,
        ], required: ["account"], readOnly: false),
        tool("remove_account", "删账户。里面有流水（期初余额不算）时不让删。", [
            "account": prop("string", "账户 id"), "author": author, "dry_run": dryRun,
        ], required: ["account"], readOnly: false),
        tool("rename_category", "把一个分类整体改名，或并进另一个已有分类。", [
            "from": prop("string", "原分类"), "to": prop("string", "新分类"), "author": author, "dry_run": dryRun,
        ], required: ["from", "to"], readOnly: false),
        tool("add_category", "加一个新分类（还没有流水用它也行），app 记一笔时就能选。重名会提示。icon 可以挑一个图标（名字见 list_category_icons），不填按名字自动配。", [
            "name": prop("string", "分类名，如「宠物」"), "income": prop("boolean", "是收入分类就填 true，默认支出"),
            "icon": prop("string", "图标名，如 pets、coffee（见 list_category_icons）"),
            "author": author, "dry_run": dryRun,
        ], required: ["name"], readOnly: false),
        tool("set_category_icon", "给一个分类换图标（已有流水的分类也行）。icon 留空 = 改回按名字自动配。", [
            "name": prop("string", "分类名"), "icon": prop("string", "图标名（见 list_category_icons），留空改回自动"),
            "author": author, "dry_run": dryRun,
        ], required: ["name"], readOnly: false),
        tool("list_category_icons", "分类能用的图标：按分组列出图标名和中文名，以及哪些分类已经挑过图标。", [:], readOnly: true),
        tool("set_profile", "改夏夏的说话方式或用户的目标。persona：gentle 温和直说 / sharp 毒舌 / calm 文静 / cheer 打气。aim：用户想让夏夏帮他做到什么（空字符串 = 清掉）。只在用户要求时改。", [
            "persona": prop("string", "gentle / sharp / calm / cheer"), "aim": prop("string", "用户的目标，如「每个月存下 500 €」"),
            "author": author, "dry_run": dryRun,
        ], readOnly: false),
        tool("set_opening_balance", "记开账余额：开始记账那天账户里已经有多少钱（不算收入）。已经记过就改成新的。", [
            "account": prop("string", "账户 id"), "amount": prop("string", "余额，信用卡欠款写负数"),
            "date": prop("string", "哪天的余额，默认今天"), "author": author, "dry_run": dryRun,
        ], required: ["account", "amount"], readOnly: false),
        tool("book_transfer", "账本之间挪钱（同一个账户里，如店里的钱拿回家用）：两边各记一笔，看「全部」时互相抵消。", [
            "amount": prop("string", "金额，正数"), "from_book": prop("string", "从哪个账本"), "to_book": prop("string", "到哪个账本"),
            "account": prop("string", "哪个账户"), "date": prop("string", "日期，默认今天"), "note": prop("string", "说明"),
            "author": author, "dry_run": dryRun,
        ], required: ["amount", "from_book", "to_book", "account"], readOnly: false),
        tool("categorize", "改分类。ids 用 list_transactions 返回的 id（前 8 位也行）。", [
            "ids": ["type": "array", "items": ["type": "string"], "description": "流水 id"],
            "category": prop("string", "分类"),
            "author": author, "dry_run": dryRun,
        ], required: ["ids", "category"], readOnly: false),
        tool("assign_book", "分账本：这几笔属于个人还是店里。", [
            "ids": ["type": "array", "items": ["type": "string"], "description": "流水 id"],
            "book": prop("string", "账本 id"),
            "author": author, "dry_run": dryRun,
        ], required: ["ids", "book"], readOnly: false),
        tool("import_rows", "批量导入你自己从文件里读出来的流水：银行的 Excel / PDF 对账单、支付宝 / 微信账单、别的记账 App 导出的数据，或用户直接发给你的附件。你先读懂文件，把每一笔整理成 rows（支出写负数，收入写正数），一次最多 500 行，多的分批。自动去重，整批是一条改动、能一次撤销。先 dry_run 给用户看读到几笔、新的几笔，确认后再正式导入。转给自己的钱、还信用卡、支付宝的「不计收支」、充值提现先问用户或不要导。", [
            "account": prop("string", "导进哪个账户（context 里的账户 id）"),
            "rows": ["type": "array", "description": "每一笔：date（2026-11-03）、amount（-23,40 或 -23.40）、description（商户或说明），可选 category、book、note",
                     "items": ["type": "object", "properties": [
                        "date": prop("string", "日期 2026-11-03"), "amount": prop("string", "金额，支出是负数"),
                        "description": prop("string", "商户或说明"), "category": prop("string", "分类（可不填）"),
                        "book": prop("string", "账本 id（可不填，默认用外面的 book）"), "note": prop("string", "备注（可不填）"),
                     ] as [String: Any], "required": ["date", "amount", "description"]] as [String: Any]] as [String: Any],
            "book": prop("string", "这批默认归哪个账本"),
            "source": prop("string", "数据从哪来，比如「支付宝账单 2026-10」，记进每笔流水的来源"),
            "author": author, "dry_run": dryRun,
        ], required: ["account", "rows"], readOnly: false),
        tool("import_statement", "导入对账单文件（CSV），自动去重。先 dry_run 给用户 看，确认后再正式导入。Excel、PDF、支付宝 / 微信账单这些不是标准 CSV 的，用 import_rows。", [
            "file": prop("string", "文件路径"),
            "account": prop("string", "导进哪个账户"),
            "format": ["type": "string", "enum": ["revolut", "csv"], "description": "格式"],
            "date_col": prop("string", "通用 CSV：日期列（列名或从 1 开始的列号）"),
            "amount_col": prop("string", "通用 CSV：金额列"),
            "debit_col": prop("string", "通用 CSV：支出列"),
            "credit_col": prop("string", "通用 CSV：收入列"),
            "desc_col": prop("string", "通用 CSV：说明列"),
            "skip_rows": prop("integer", "表头前跳过几行"),
            "book": prop("string", "这批默认归哪个账本"),
            "author": author, "dry_run": dryRun,
        ], required: ["file", "account", "format"], readOnly: false),
        tool("add_installment", "记分期：买的那天按全额算支出，之后每期还款算还债。", [
            "name": prop("string", "名称"), "total": prop("string", "总额（不含手续费）"), "count": prop("integer", "共几期"),
            "account": prop("string", "从哪个账户扣"), "book": prop("string", "账本 id"),
            "date": prop("string", "买的日期，默认今天"), "first": prop("string", "第一期扣款日"),
            "category": prop("string", "分类"), "fee": prop("string", "手续费或利息"),
            "author": author, "dry_run": dryRun,
        ], required: ["name", "total", "count", "account", "book"], readOnly: false),
        tool("pay_installment", "记一期分期还款；导入的银行扣款用 transaction_id 认领。", [
            "name": prop("string", "分期名称"), "transaction_id": prop("string", "已导入的扣款流水 id"),
            "amount": prop("string", "金额，默认每期金额"), "date": prop("string", "日期，默认今天"),
            "author": author, "dry_run": dryRun,
        ], required: ["name"], readOnly: false),
        tool("add_insight", "以「夏夏」的身份把你对用户财务的看法写进账本，显示在 app 对应页面的「夏夏说」和「夏夏建议」页。口吻照 context 里的 voice，围着 aim（用户的目标）说。kind：review = 本月点评（每月每账本一条，新的替换旧的，月初或被问到时写），alert = 留意，tip = 建议，good = 好消息，action = 要处理（超支、信用卡快到期）。title 一句话结论，body 两三句解释，数字用 1.234,56 € 写法。", [
            "kind": prop("string", "review / alert / tip / good / action"),
            "title": prop("string", "一句话结论，如「这个月花钱比上月慢 8%，月底大概能剩 1.150 €」"),
            "body": prop("string", "两三句解释：原因、要留意什么"),
            "month": prop("string", "哪个月，如 2026-11；默认这个月"),
            "book": prop("string", "账本 id；不填 = 全部"),
            "metric": prop("string", "关联的东西，如 category:超市、account:银行卡（可不填）"),
            "page": prop("string", "写给哪一页：overview 总览 / spending 花销 / trends 趋势 / wealth 家底 / plans 目标；默认 overview"),
            "author": author, "dry_run": dryRun,
        ], required: ["kind", "title"], readOnly: false),
        tool("list_insights", "列出写进账本的 AI 意见（默认这个月、没点「知道了」的）。写新意见前先看看，别重复。", [
            "month": prop("string", "月份，如 2026-11；不填 = 全部月份"),
            "book": prop("string", "账本 id"),
            "include_dismissed": prop("boolean", "连用户点过「知道了」的也列出"),
        ], readOnly: true),
        tool("dismiss_insight", "把一条意见标成「知道了」（用户说不用再提醒时用）。", [
            "id": prop("string", "意见 id（前 8 位也行）"), "author": author,
        ], required: ["id"], readOnly: false),
        tool("ai_status", "最近谁写过账本：每个作者最后一次写入的时间和内容。", [:], readOnly: true),
        tool("current_view", "用户现在在 app 里看什么：哪一页、哪个月、哪个账本、选中了哪一笔。用户说「这笔」「这个月」「这里」又没说清时先调这个，不用让用户复制粘贴。", [:], readOnly: true),
        tool("open_in_app", "让夏夏账本 app 跳到某一页给用户看，可以圈出几笔流水。回答完想让用户在 app 里看到结果时用，比如「看看这 5 笔」「打开 10 月的花销」。", [
            "page": prop("string", "overview 总览 / spending 花销 / trends 趋势 / wealth 家底 / plans 目标 / subscriptions 订阅 / debts 欠款与分期 / insights 夏夏建议 / changes 改动记录 / transactions 流水"),
            "month": prop("string", "哪个月，如 2026-10；不填 = 不换月份"),
            "book": prop("string", "账本 id；不填 = 不换"),
            "ids": ["type": "array", "items": ["type": "string"], "description": "要圈出来的流水 id（前 8 位也行）；填了就打开流水页只列这几笔"],
            "category": prop("string", "打开流水页并按这个分类筛选"),
            "note": prop("string", "一句话，显示在 app 顶上，比如「这 3 笔可能重复了」"),
            "author": author,
        ], required: ["page"], readOnly: false),
        tool("undo", "撤销一条改动（history 里的 id，前 8 位也行）。", [
            "change_id": prop("string", "改动 id"), "author": author,
        ], required: ["change_id"], readOnly: false),
    ] + goalTools + currencySubsTools + memoryTools + phoneTools

    static func json<T: Encodable>(_ v: T) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return String(decoding: try e.encode(v), as: UTF8.self)
    }

    static func call(_ name: String, _ a: [String: Any], author clientName: String) throws -> String {
        func s(_ k: String) -> String? { (a[k] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (a[k] as? NSNumber).map { "\($0)" } }
        func req(_ k: String) throws -> String { guard let v = s(k) else { throw ToolError(message: "缺少参数 \(k)") }; return v }
        func flag(_ k: String) -> Bool { (a[k] as? Bool) ?? false }
        func int(_ k: String, _ d: Int) -> Int { (a[k] as? Int) ?? (a[k] as? NSNumber)?.intValue ?? d }
        func money(_ k: String) throws -> Money {
            guard let m = Money(parsing: try req(k)) else { throw ToolError(message: "金额看不懂：\(a[k] ?? "")") }
            return m
        }
        func date(_ k: String) throws -> LocalDate? {
            guard let v = s(k) else { return nil }
            guard let d = LocalDate(v) else { throw ToolError(message: "日期要写成 2026-11-21：\(v)") }
            return d
        }
        // 经 MCP 来的改动一律记成这个 AI 工具的名字：有的 AI 会把 author 填成用户的名字，
        // app 就认不出「这是 AI 记的」（不弹提醒、引导也不撒花）。
        let who = clientName
        var ledger = try loadLedger()

        /// 写入收尾：预演不保存。
        func commit(_ change: ChangeRecord) throws -> String {
            if flag("dry_run") { return "预演（没有写入）：\(change.summary)" }
            try saveLedger(ledger)
            return "已记：\(change.summary)\n改动 id：\(change.id.uuidString.prefix(8).lowercased())（写错了用 undo 撤销）"
        }

        switch name {
        case "current_view":
            guard let view = AppBridge.readView() else { return "app 还没打开过，或者是旧版本，不知道用户在看什么。直接问用户。" }
            return view.describe()
        case "open_in_app":
            guard let page = AppBridge.pageName(try req("page")) else { throw ToolError(message: "page 只能是 overview / spending / trends / wealth / plans / subscriptions / debts / insights / changes / transactions") }
            if let m = s("month"), YearMonth(m) == nil { throw ToolError(message: "月份要写成 2026-11") }
            if let b = s("book"), !ledger.books.contains(where: { $0.id == b }) { throw ToolError(message: "没有这个账本：\(b)") }
            let ids = try (a["ids"] as? [String]).map { try ledger.findTransactions($0).map(\.id) } ?? []
            let request = AppBridge.OpenRequest(page: ids.isEmpty && s("category") == nil ? page : "流水", month: s("month"), bookID: s("book"),
                                                transactionIDs: ids, category: s("category"), note: s("note"), author: who)
            try AppBridge.requestOpen(request)
            #if os(macOS)
            // 把 app 叫到前面来（没开就打开）。自动检查里设了 XIAXIA_NO_OPEN 就不开。
            if ProcessInfo.processInfo.environment["XIAXIA_NO_OPEN"] == nil {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-b", "com.srmming.xiaxia-ledger.mac"]
            try? open.run()
            }
            #endif
            return "已让 app 打开「\(request.page)」" + (ids.isEmpty ? "" : "，圈出 \(ids.count) 笔") + "。如果 app 没开，打开后 10 分钟内还会跳过去。"
        case "context":
            return try json(LedgerContext(ledger: ledger))
        case "welcome":
            return AIConnector.welcomeGuide
        case "list_transactions":
            let ym = try s("month").map { m -> YearMonth in
                guard let v = YearMonth(m) else { throw ToolError(message: "月份要写成 2026-11") }
                return v
            }
            let hidden = flag("include_private") ? [] : ledger.privateAccountIDs
            let q = s("query").map(Dedup.normalize)
            let rawQuery = s("query"), tagQuery = s("tag").map { "#" + Tags.clean([$0]).joined() }, kind = s("kind")
            let extra: (Transaction) -> Bool = { (t: Transaction) -> Bool in
                if let q, let rawQuery, !Dedup.normalize(t.description).contains(q), !t.matches(rawQuery) { return false }
                if let tagQuery, !t.matches(tagQuery) { return false }
                if let kind { return kind == "income" ? t.amount.isIncome : t.amount.isExpense }
                return true
            }
            let txs = ledger.transactions
                .filter { !hidden.contains($0.accountID) }
                .filter { s("book") == nil || $0.bookID == s("book") }
                .filter { s("account") == nil || $0.accountID == s("account") }
                .filter { ym == nil || $0.date.yearMonth == ym }
                .filter { s("category") == nil || $0.category == s("category") }
                .filter(extra)
                .sorted { $0.date > $1.date }
                .prefix(int("limit", 50))
            return try json(Array(txs))
        case "summary":
            let year: Int? = a["year"] == nil ? nil : int("year", 0)
            let months: [YearMonth]
            do { months = try SummaryCommand.months(month: s("month"), year: year, from: s("from"), to: s("to")) }
            catch { throw ToolError(message: "要看哪段时间？填 month（2026-11）、year（2026），或 from + to（2026-01、2026-06）") }
            let hidden = flag("include_private") ? [] : ledger.privateAccountIDs
            let list = Reports.summaries(ledger.baseTransactions, months: months, bookID: s("book"), hiddenAccounts: hidden)
            return SummaryCommand.text(list, months: months, book: s("book"), ledger: ledger, hidden: hidden)
        case "accounts":
            let hidden = flag("include_private") ? [] : ledger.privateAccountIDs
            let balances = ledger.accountBalances()
            return ledger.accounts.filter { !hidden.contains($0.id) }.map { acct -> String in
                let code = ledger.currency(ofAccount: acct.id)
                let b = balances[acct.id] ?? (.zero, .zero)
                let approx = code == ledger.baseCurrency ? "" : "（约 \(b.base.formatted(in: ledger.baseCurrency))）"
                return "\(acct.id)\t\(acct.name)\(acct.isPrivate ? "（私房钱）" : "")\t\(b.native.formatted(in: code))\(approx)"
            }.joined(separator: "\n")
        case "monthly_report":
            let ym: YearMonth
            if let m = s("month") {
                guard let v = YearMonth(m) else { throw ToolError(message: "月份要写成 2026-11") }
                ym = v
            } else { ym = LocalDate.today.yearMonth }
            if let b = s("book"), !ledger.books.contains(where: { $0.id == b }) { throw ToolError(message: "没有这个账本：\(b)") }
            return MonthlyReport.text(ledger, month: ym, bookID: s("book"),
                                      hiddenAccounts: flag("include_private") ? [] : ledger.privateAccountIDs)
        case "reconcile":
            return Reconcile.text(try Reconcile.check(ledger, accountID: try req("account"), statementBalance: try money("balance"),
                                                      asOf: try date("date") ?? .today))
        case "edit_transaction":
            var t = try ledger.findTransactions([try req("id")])[0]
            guard t.flow == nil, !t.isTransfer else {
                throw ToolError(message: "这笔是转账、借款、分期或目标的一部分，不能直接改。先 undo 原来那条改动，再重新记。")
            }
            guard ["amount", "description", "date", "account", "book", "category"].contains(where: { s($0) != nil })
                    || a["note"] != nil || a["tags"] != nil else {
                throw ToolError(message: "没写要改什么")
            }
            if s("amount") != nil { t.amount = try money("amount") }
            if let v = s("description") { t.description = v }
            if let v = try date("date") { t.date = v }
            if let v = s("account") { t.accountID = v }
            if let v = s("book") { t.bookID = v }
            if let v = s("category") { t.category = v }
            if a["note"] != nil { t.note = s("note") }
            if let v = a["tags"] as? [String] { t.tags = Tags.clean(v).isEmpty ? nil : Tags.clean(v) }
            return try commit(try ledger.editTransaction(t, author: who))
        case "delete_transactions":
            guard let ids = a["ids"] as? [String], !ids.isEmpty else { throw ToolError(message: "ids 要是非空的字符串数组") }
            let txs = try ledger.findTransactions(ids)
            let listing = txs.map { "  \($0.date) \(ledger.formatted($0)) \($0.description)" }.joined(separator: "\n")
            return try commit(try ledger.removeTransactions(txs.map(\.id), author: who)) + "\n" + listing
        case "add_account":
            let id = try req("id")
            guard !ledger.accounts.contains(where: { $0.id == id }) else { throw ToolError(message: "已经有 \(id) 这个账户了") }
            guard let kind = AccountKind(rawValue: s("kind") ?? "bank") else { throw ToolError(message: "kind 只能是 bank、credit、cash、wallet、savings") }
            let opening: Money? = s("opening_balance") == nil ? nil : try money("opening_balance")
            if let c = s("currency"), !Currencies.isKnown(c) { throw CurrencyError.unknownCurrency(c) }
            let code = s("currency")?.uppercased()
            return try commit(try ledger.createAccount(Account(id: id, name: try req("name"), kind: kind, isPrivate: flag("private"),
                                                               currency: code == ledger.baseCurrency ? nil : code),
                                                       openingBalance: opening, date: try date("date") ?? .today, author: who))
        case "add_book":
            guard let kind = BookKind(rawValue: s("kind") ?? "personal") else { throw ToolError(message: "kind 只能是 personal 或 business") }
            return try commit(try ledger.addBook(name: try req("name"), kind: kind, author: who))
        case "rename_book":
            return try commit(try ledger.renameBook(try req("book"), to: try req("name"), author: who))
        case "remove_book":
            return try commit(try ledger.removeBook(try req("book"), moveTo: s("move_to"), author: who))
        case "edit_account":
            let id = try req("account")
            guard var acct = ledger.accounts.first(where: { $0.id == id }) else { throw ToolError(message: "没有这个账户：\(id)") }
            if let n = s("name") { acct.name = n }
            if let k = s("kind") {
                guard let kind = AccountKind(rawValue: k) else { throw ToolError(message: "kind 只能是 bank、credit、cash、wallet、savings") }
                acct.kind = kind
            }
            if let i = s("institution") { acct.institution = i }
            if a["private"] != nil { acct.isPrivate = flag("private") }
            return try commit(try ledger.updateAccount(acct, author: who))
        case "remove_account":
            return try commit(try ledger.removeAccount(try req("account"), author: who))
        case "rename_category":
            return try commit(try ledger.renameCategory(try req("from"), to: try req("to"), author: who))
        case "add_category":
            return try commit(try ledger.addCategory(try req("name"), income: flag("income"), icon: s("icon").flatMap { $0.isEmpty ? nil : $0 }, author: who))
        case "set_category_icon":
            let icon = s("icon").flatMap { $0.isEmpty ? nil : $0 }
            return try commit(try ledger.setCategoryIcon(try req("name"), icon: icon, author: who))
        case "list_category_icons":
            var out = CategoryIcons.sections.map { sec in
                "\(sec.label)：" + sec.icons.map { n in "\(n)（\(CategoryIcons.label(n) ?? n)）" }.joined(separator: " ")
            }
            let picked = ledger.categoryIcons.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value)" }
            out.append(picked.isEmpty ? "还没有分类挑过图标（都按名字自动配）。" : "已挑过图标的分类：" + picked.joined(separator: "，"))
            return out.joined(separator: "\n")
        case "set_profile":
            var last: ChangeRecord?
            if let p = s("persona") {
                guard let persona = Persona(rawValue: p.lowercased()) else { throw ToolError(message: "persona 只能是 gentle / sharp / calm / cheer") }
                if persona != ledger.profile.persona { last = try ledger.setPersona(persona, author: who) }
            }
            if let aim = a["aim"] as? String, (aim.isEmpty ? nil : aim) != ledger.profile.aim {
                last = try ledger.setAim(aim, author: who)
            }
            guard let last else { throw ToolError(message: "没有要改的：persona 和 aim 都和现在一样") }
            return try commit(last)
        case "set_opening_balance":
            return try commit(try ledger.setOpeningBalance(accountID: try req("account"), amount: try money("amount"),
                                                           date: try date("date") ?? .today, author: who))
        case "account_transfer":
            return try commit(try ledger.addAccountTransfer(amount: try money("amount").magnitude, from: try req("from_account"),
                                                            to: try req("to_account"), date: try date("date") ?? .today,
                                                            note: s("note"), author: who))
        case "mark_account_transfer":
            guard let ids = a["ids"] as? [String], !ids.isEmpty else { throw ToolError(message: "ids 要是非空的字符串数组") }
            let txs = try ledger.findTransactions(ids).map(\.id)
            return try commit(try ledger.markAsAccountTransfer(txs, counterAccount: s("counter_account"), author: who))
        case "debts":
            return try json(Plans.debts(ledger, today: .today, includeClosed: flag("include_closed"))) + debtPlansText(ledger)
        case "installments":
            return try json(Plans.installments(ledger))
        case "history":
            return try json(Array(ledger.changes.suffix(int("limit", 20)).reversed()))
        case "add_transaction":
            guard let amount = Money.evaluate(try req("amount")) else { throw ToolError(message: "金额看不懂：\(a["amount"] ?? "")") }
            let tags = Tags.clean(a["tags"] as? [String] ?? [])
            var tx = Transaction(date: try date("date") ?? .today, amount: amount, description: try req("description"),
                                 accountID: try req("account"), bookID: try req("book"), category: s("category"), source: "手记（\(who)）",
                                 note: s("note"), tags: tags.isEmpty ? nil : tags)
            tx.fx = ledger.fxNote(accountID: tx.accountID, date: tx.date)
            if let o = s("original") {
                do { tx.original = try parseForeign(o, sign: tx.amount.cents < 0 ? -1 : 1) }
                catch { throw ToolError(message: "original 写成「50 USD」这样") }
            }
            if let r = s("repeat") {
                guard let f = Recurring.Frequency(rawValue: r) else { throw ToolError(message: "repeat 要写 weekly、monthly 或 yearly") }
                return try commit(try ledger.addRecurring(tx, frequency: f, until: try date("until"), author: who))
            }
            return try commit(try ledger.addTransaction(tx, author: who))
        case "split_transaction":
            let t = try ledger.findTransactions([try req("id")])[0]
            guard let raw = a["parts"] as? [[String: Any]], raw.count >= 2 else { throw ToolError(message: "parts 至少要两份") }
            let parts = try raw.map { p -> SplitPart in
                let text = (p["amount"] as? String) ?? (p["amount"] as? NSNumber).map { "\($0)" } ?? ""
                guard let m = Money.evaluate(text), m.cents != 0 else { throw ToolError(message: "金额看不懂：\(text)") }
                return SplitPart(amount: m.magnitude, category: p["category"] as? String, description: p["description"] as? String)
            }
            return try commit(try ledger.splitTransaction(t.id, parts: parts, author: who))
        case "duplicate_transaction":
            let t = try ledger.findTransactions([try req("id")])[0]
            return try commit(try ledger.duplicateTransaction(t.id, date: try date("date") ?? .today, author: who))
        case "add_refund":
            let t = try ledger.findTransactions([try req("id")])[0]
            let amount = try s("amount").map { v -> Money in
                guard let m = Money.evaluate(v) else { throw ToolError(message: "金额看不懂：\(v)") }
                return m.magnitude
            }
            return try commit(try ledger.addRefund(of: t.id, amount: amount, date: try date("date") ?? .today, author: who))
        case "tag_transactions":
            guard let ids = a["ids"] as? [String], !ids.isEmpty else { throw ToolError(message: "ids 要是非空的字符串数组") }
            let txs = try ledger.findTransactions(ids)
            return try commit(try ledger.tagTransactions(txs.map(\.id), add: a["add"] as? [String] ?? [],
                                                         remove: a["remove"] as? [String] ?? [], author: who))
        case "list_recurring":
            struct Row: Encodable { var id: String; var summary: String; var frequency: String; var next: String; var until: String?; var paused: Bool; var account: String; var book: String?; var category: String? }
            return try json(ledger.recurring.map {
                Row(id: String($0.id.uuidString.prefix(8)).lowercased(), summary: $0.summary, frequency: $0.frequency.rawValue,
                    next: $0.nextDate.description, until: $0.until?.description, paused: $0.paused, account: $0.template.accountID,
                    book: $0.template.bookID, category: $0.template.category)
            })
        case "set_recurring":
            let t = try ledger.findTransactions([try req("id")])[0]
            guard let f = Recurring.Frequency(rawValue: try req("frequency")) else { throw ToolError(message: "frequency 要写 weekly、monthly 或 yearly") }
            return try commit(try ledger.makeRecurring(t.id, frequency: f, until: try date("until"), author: who))
        case "update_recurring":
            let hits = ledger.findRecurring(try req("key"))
            guard hits.count == 1 else { throw ToolError(message: hits.isEmpty ? "找不到这条重复记账" : "对上了 \(hits.count) 条，写 id") }
            var r = hits[0]
            switch try req("action") {
            case "pause": r.paused = true
            case "resume": r.paused = false
            case "remove": return try commit(try ledger.removeRecurring(r.id, author: who))
            default: throw ToolError(message: "action 要写 pause、resume 或 remove")
            }
            return try commit(try ledger.updateRecurring(r, author: who))
        case "run_recurring":
            guard let change = ledger.postDueRecurring(author: who) else { return "没有到日子的重复记账。" }
            return try commit(change)
        case "add_debt":
            let dir: Debt.Direction
            switch try req("direction") {
            case "they_owe_me": dir = .theyOweMe
            case "i_owe": dir = .iOweThem
            default: throw ToolError(message: "direction 只能是 they_owe_me 或 i_owe")
            }
            let (_, change) = try ledger.addDebt(counterparty: try req("counterparty"), direction: dir, amount: try money("amount").magnitude,
                                                 bookID: s("book") ?? ledger.books.first?.id ?? "personal", date: try date("date") ?? .today,
                                                 accountID: s("account"), dueDate: try date("due"), note: s("note"), author: who)
            return try commit(change)
        case "repay_debt":
            let matches = ledger.openDebts(named: try req("counterparty"))
            guard matches.count == 1 else {
                throw ToolError(message: matches.isEmpty ? "没找到和这个名字有关的没还清借款，先调 debts 看看"
                                                         : "这个名字对上了 \(matches.count) 笔借款，写完整一点")
            }
            let debtID = matches[0].id
            let amount = try money("amount").magnitude
            let day = try date("date") ?? .today
            var adjust: RepayAdjust? = nil
            if let t = s("adjust"), t != "none" {
                guard let x = RepayAdjust(text: t) else { throw ToolError(message: "adjust 只能是 shorten / lower / next / extend / none") }
                adjust = x
            }
            if s("adjust") == nil, let p = ledger.repayPreview(debtID, amount: amount, today: day), !p.options.isEmpty {
                let more = p.difference.cents > 0
                let lines = p.options.map { "- \($0.adjust.rawValue)：\($0.adjust.label)（\($0.detail)）" }
                return "还没写入。这笔有还款计划，这期该还 \(p.due.formatted)，这次\(more ? "多" : "少")还了 \(p.difference.magnitude.formatted)。"
                    + "用选项框问用户怎么调，再带 adjust 调 repay_debt：\n" + lines.joined(separator: "\n") + "\n- none：计划不动"
            }
            if let adjust, adjust.isForOverpay != ((ledger.repayPreview(debtID, amount: amount, today: day)?.difference.cents ?? 0) > 0) {
                throw ToolError(message: adjust.isForOverpay ? "这笔没有多还，shorten / lower 用不上" : "这笔没有少还，next / extend 用不上")
            }
            return try commit(try ledger.repay(debtID: debtID, amount: amount, date: day, accountID: try req("account"),
                                               adjust: adjust, author: who))
        case "plan_debt", "edit_debt_plan", "skip_debt_payment":
            let matches = ledger.openDebts(named: try req("counterparty"))
            guard matches.count == 1 else {
                throw ToolError(message: matches.isEmpty ? "没找到和这个名字有关的没还清借款，先调 debts 看看"
                                                         : "这个名字对上了 \(matches.count) 笔借款，写完整一点")
            }
            let id = matches[0].id
            if name == "edit_debt_plan" {
                return try commit(try ledger.editPlannedPayment(id, index: int("period", 1) - 1, amount: try money("amount").magnitude,
                                                                date: try date("date"), author: who))
            }
            if name == "skip_debt_payment" {
                guard let x = RepayAdjust(text: try req("adjust")), !x.isForOverpay else { throw ToolError(message: "adjust 只能是 next 或 extend") }
                return try commit(try ledger.skipPlannedPayment(id, adjust: x, author: who))
            }
            if flag("clear") { return try commit(try ledger.clearDebtPlan(id, author: who)) }
            let start = try date("start") ?? LocalDate.today.adding(months: 1)
            if s("per_month") != nil {
                return try commit(try ledger.planDebt(id, perMonth: try money("per_month").magnitude, start: start, author: who))
            }
            guard a["count"] != nil else { throw ToolError(message: "填 per_month（每月还多少）或 count（分几期）") }
            return try commit(try ledger.planDebt(id, count: int("count", 0), start: start, author: who))
        case "categorize", "assign_book":
            guard let ids = a["ids"] as? [String], !ids.isEmpty else { throw ToolError(message: "ids 要是非空的字符串数组") }
            let txs = try ledger.findTransactions(ids).map(\.id)
            let change: ChangeRecord
            if name == "categorize" {
                change = ledger.categorize(txs, category: try req("category"), author: who)
            } else {
                change = try ledger.assignBook(txs, bookID: try req("book"), author: who)
            }
            return try commit(change)
        case "import_rows":
            guard let rows = a["rows"] as? [[String: Any]], !rows.isEmpty else { throw ToolError(message: "rows 要是非空的数组") }
            guard rows.count <= 500 else { throw ToolError(message: "一次最多 500 行，这次有 \(rows.count) 行，请分批") }
            let account = try req("account")
            guard ledger.accounts.contains(where: { $0.id == account }) else {
                throw ToolError(message: "找不到账户：\(account)。先用 context 看有哪些账户，没有就先 add_account")
            }
            let source = s("source") ?? "AI 整理导入"
            var txs: [Transaction] = []
            var skipped: [String] = []
            for (i, r) in rows.enumerated() {
                func field(_ k: String) -> String? {
                    if let v = r[k] as? String { let t = v.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
                    if let n = r[k] as? NSNumber { return n.stringValue }
                    return nil
                }
                let n = i + 1
                guard let d = field("date"), let day = LocalDate(String(d.prefix(10))) else { skipped.append("第 \(n) 行：日期看不懂（要 2026-11-03）"); continue }
                guard let a = field("amount"), let amount = Money(parsing: a), amount.cents != 0 else { skipped.append("第 \(n) 行：金额看不懂或是 0"); continue }
                guard let desc = field("description") else { skipped.append("第 \(n) 行：没有说明"); continue }
                txs.append(Transaction(date: day, amount: amount, description: desc, accountID: account,
                                       bookID: field("book") ?? s("book"), category: field("category"), source: source, note: field("note")))
            }
            let skippedText = skipped.isEmpty ? "" : "\n跳过：\n" + skipped.map { "  \($0)" }.joined(separator: "\n")
            guard !txs.isEmpty else { return "一笔都没读进来。\(skippedText)" }
            if flag("dry_run") {
                let fresh = Dedup.newTransactions(txs, existing: ledger.transactions)
                let preview = fresh.prefix(40).map { "  \($0.date) \($0.amount.formatted) \($0.description)" }.joined(separator: "\n")
                return "预演（没有写入）：读到 \(txs.count) 笔，新的 \(fresh.count) 笔\n\(preview)\(skippedText)"
            }
            let (_, dupes, change) = try ledger.importTransactions(txs, accountID: account, source: source, author: who)
            guard let change else { return "没有新流水（\(dupes) 笔都已经有了）。\(skippedText)" }
            return try commit(change) + skippedText
        case "import_statement":
            let url = URL(fileURLWithPath: (try req("file") as NSString).expandingTildeInPath)
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let account = try req("account")
            var result: ImportResult
            switch try req("format") {
            case "revolut": result = try Importers.revolutCSV(text, accountID: account, source: url.lastPathComponent)
            case "csv":
                result = try Importers.genericCSV(text, map: .init(date: try req("date_col"), amount: s("amount_col"), debit: s("debit_col"),
                                                                   credit: s("credit_col"), description: try req("desc_col"),
                                                                   skipRows: int("skip_rows", 0)),
                                                  accountID: account, source: url.lastPathComponent)
            default: throw ToolError(message: "format 只能是 revolut 或 csv")
            }
            if let book = s("book") { result.transactions = result.transactions.map { var t = $0; t.bookID = book; return t } }
            let skipped = result.skipped.isEmpty ? "" : "\n跳过：\n" + result.skipped.map { "  \($0)" }.joined(separator: "\n")
            if flag("dry_run") {
                let fresh = Dedup.newTransactions(result.transactions, existing: ledger.transactions)
                let preview = fresh.prefix(40).map { "  \($0.date) \($0.amount.formatted) \($0.description)" }.joined(separator: "\n")
                return "预演（没有写入）：读到 \(result.transactions.count) 笔，新的 \(fresh.count) 笔\n\(preview)\(skipped)"
            }
            let (_, dupes, change) = try ledger.importTransactions(result.transactions, accountID: account,
                                                                    source: url.lastPathComponent, author: who)
            guard let change else { return "没有新流水（\(dupes) 笔都已经有了）。\(skipped)" }
            return try commit(change) + skipped
        case "add_installment":
            let buy = try date("date") ?? .today
            let firstDate = try date("first") ?? LocalDate(year: buy.month == 12 ? buy.year + 1 : buy.year,
                                                           month: buy.month == 12 ? 1 : buy.month + 1, day: min(buy.day, 28))
            let fee: Money? = s("fee").flatMap { Money(parsing: $0) }
            let (_, change) = try ledger.addInstallment(name: try req("name"), bookID: try req("book"), accountID: try req("account"),
                                                        total: try money("total").magnitude, count: int("count", 0),
                                                        purchaseDate: buy, firstPayment: firstDate, category: s("category"),
                                                        fee: fee, author: who)
            return try commit(change)
        case "pay_installment":
            let hits = ledger.findInstallments(named: try req("name"))
            guard hits.count == 1 else { throw ToolError(message: hits.isEmpty ? "没有这个分期" : "对上了 \(hits.count) 个分期，写完整一点") }
            if let key = s("transaction_id") {
                let t = try ledger.findTransactions([key])[0]
                return try commit(try ledger.linkInstallmentPayment(hits[0].id, transactionID: t.id, author: who))
            }
            let amount: Money? = s("amount").flatMap { Money(parsing: $0) }
            return try commit(try ledger.payInstallment(hits[0].id, amount: amount, date: try date("date") ?? .today, author: who))
        case "book_transfer":
            return try commit(try ledger.addTransfer(amount: try money("amount").magnitude, fromBook: try req("from_book"),
                                                     toBook: try req("to_book"), accountID: try req("account"),
                                                     date: try date("date") ?? .today, note: s("note"), author: who))
        case "add_insight":
            let kinds: [String: Insight.Kind] = ["review": .monthlyReview, "monthly_review": .monthlyReview, "alert": .alert,
                                                 "tip": .tip, "good": .goodNews, "good_news": .goodNews, "action": .action]
            guard let kind = kinds[try req("kind").lowercased()] else { throw ToolError(message: "kind 只能是 review / alert / tip / good / action") }
            let month = try s("month").map { m -> YearMonth in
                guard let v = YearMonth(m) else { throw ToolError(message: "月份要写成 2026-11") }
                return v
            } ?? LocalDate.today.yearMonth
            if let b = s("book"), !ledger.books.contains(where: { $0.id == b }) { throw ToolError(message: "没有这个账本：\(b)") }
            if let p = s("page"), !Insight.pages.contains(p) { throw ToolError(message: "page 只能是 overview / spending / trends / wealth / plans / debts") }
            let insight = Insight(month: month, bookID: s("book"), kind: kind, title: try req("title"), body: s("body") ?? "",
                                  metric: s("metric"), page: s("page"), author: who)
            return try commit(try ledger.addInsight(insight, author: who))
        case "list_insights":
            let month = try s("month").map { m -> YearMonth in
                guard let v = YearMonth(m) else { throw ToolError(message: "月份要写成 2026-11") }
                return v
            }
            return try json(ledger.insights(month: month, bookID: s("book"), includeDismissed: flag("include_dismissed")))
        case "dismiss_insight":
            guard let hit = ledger.findInsight(try req("id")) else { throw ToolError(message: "没有这条意见，先用 list_insights 看 id") }
            return try commit(try ledger.dismissInsight(hit.id, author: who))
        case "ai_status":
            struct Row: Encodable { var author: String; var last: Date; var summary: String }
            var latest: [String: ChangeRecord] = [:]
            for c in ledger.changes where latest[c.author].map({ $0.createdAt < c.createdAt }) ?? true { latest[c.author] = c }
            return try json(latest.values.sorted { $0.createdAt > $1.createdAt }.map { Row(author: $0.author, last: $0.createdAt, summary: $0.summary) })
        case "undo":
            let key = try req("change_id").lowercased()
            let hits = ledger.changes.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
            guard hits.count == 1 else { throw ToolError(message: hits.isEmpty ? "没有这条改动" : "对上了好几条，多写几位") }
            return try commit(try ledger.undo(changeID: hits[0].id, author: who))
        default:
            if let text = try MCPTools.callGoals(name, a, who: who) { return text }
            if let text = try MCPTools.callCurrencySubs(name, a, who: who) { return text }
            if let text = try MCPTools.callMemory(name, a, who: who) { return text }
            if let text = try MCPTools.callPhone(name, a, who: who) { return text }
            throw ToolError(message: "没有这个工具：\(name)")
        }
    }
}
