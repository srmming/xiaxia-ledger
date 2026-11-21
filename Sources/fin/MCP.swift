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
                result = [
                    "protocolVersion": (params["protocolVersion"] as? String) ?? protocolVersion,
                    "capabilities": ["tools": [:] as [String: Any]],
                    "serverInfo": ["name": "xiaxia-ledger", "version": "0.1.0"],
                    "instructions": "夏夏账本：ming 的个人和 Miora 美甲店财务。先调用 context 了解账本、账户和统计口径。拿不准的事先在对话里问 ming，确认后再写；写入前可以先用 dry_run 预演。每次写入都会记进改动记录，可以 undo。",
                ] as [String: Any]
            case "ping":
                result = [:] as [String: Any]
            case "tools/list":
                result = ["tools": MCPTools.list]
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
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
    static let author = prop("string", "谁在改，不填就用 AI 工具自己的名字")
    static let dryRun = prop("boolean", "预演：只返回会改什么，不写进账本")

    static func tool(_ name: String, _ desc: String, _ props: [String: [String: Any]], required: [String] = [],
                     readOnly: Bool) -> [String: Any] {
        ["name": name, "description": desc,
         "inputSchema": ["type": "object", "properties": props, "required": required] as [String: Any],
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": false] as [String: Any]]
    }

    static let list: [[String: Any]] = [
        tool("context", "说明书：账本、账户和余额、数据覆盖日期、借款合计、最近改动、统计口径。先调这个。", [:], readOnly: true),
        tool("list_transactions", "查流水。", [
            "book": prop("string", "账本 id，如 personal、miora；不填 = 全部"),
            "account": prop("string", "账户 id"),
            "month": prop("string", "月份，如 2026-11"),
            "category": prop("string", "分类"),
            "query": prop("string", "在说明里搜索"),
            "limit": prop("integer", "最多几条，默认 50"),
            "include_private": prop("boolean", "包括私房钱账户。只有 ming 本人问时才用"),
        ], readOnly: true),
        tool("summary", "月度收支和分类汇总。不填 book 是「全部」，账本间转账已抵消。", [
            "month": prop("string", "月份，如 2026-11（必填）"),
            "book": prop("string", "账本 id"),
            "include_private": prop("boolean", "算上私房钱"),
        ], required: ["month"], readOnly: true),
        tool("accounts", "每个账户现在的余额。私房钱账户默认不列。", ["include_private": prop("boolean", "包括私房钱账户。只有 ming 本人问时才用")], readOnly: true),
        tool("monthly_report", "月报：进多少、花多少、花在哪、和上个月比、要留意什么。一份能直接读给 ming 的文字。", [
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
        tool("goals", "目标和储蓄进度。", [:], readOnly: true),
        tool("history", "改动记录：谁、什么时候、改了什么。", ["limit": prop("integer", "最多几条，默认 20")], readOnly: true),
        tool("add_transaction", "记一笔收支。amount 负数是支出、正数是收入。", [
            "amount": prop("string", "金额，如 -12,50 或 300"),
            "description": prop("string", "说明"),
            "account": prop("string", "账户 id"),
            "book": prop("string", "账本 id"),
            "category": prop("string", "分类"),
            "date": prop("string", "日期 2026-11-21，默认今天"),
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
        tool("repay_debt", "记一笔还款。对方名字要能唯一对上一笔没还清的借款。", [
            "counterparty": prop("string", "对方"),
            "amount": prop("string", "还了多少，正数"),
            "account": prop("string", "钱进 / 出的账户 id"),
            "date": prop("string", "日期，默认今天"),
            "author": author, "dry_run": dryRun,
        ], required: ["counterparty", "amount", "account"], readOnly: false),
        tool("edit_transaction", "改一笔流水，只填要改的那几项。转账、借款、分期、目标里的流水不能直接改，先 undo 再重新记。", [
            "id": prop("string", "流水 id（前 8 位也行）"),
            "amount": prop("string", "新金额，负数是支出"), "description": prop("string", "新说明"),
            "date": prop("string", "新日期"), "account": prop("string", "换到哪个账户"),
            "book": prop("string", "换到哪个账本"), "category": prop("string", "新分类"),
            "author": author, "dry_run": dryRun,
        ], required: ["id"], readOnly: false),
        tool("delete_transactions", "删流水（能 undo 放回来）。先 dry_run 给 ming 看要删哪几笔，确认后再删。", [
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
        tool("import_statement", "导入对账单文件（CSV），自动去重。先 dry_run 给 ming 看，确认后再正式导入。", [
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
        tool("add_goal", "建一个存钱目标。有专门储蓄账户就填 savings_account，没有就在现有账户里划出。", [
            "name": prop("string", "名称"), "target": prop("string", "目标金额"), "book": prop("string", "账本 id，默认 personal"),
            "deadline": prop("string", "截止日期"), "savings_account": prop("string", "专门的储蓄账户 id"),
            "locked": prop("boolean", "锁定：到期前不能取"), "author": author, "dry_run": dryRun,
        ], required: ["name", "target"], readOnly: false),
        tool("goal_deposit", "往目标里存钱（不算支出）。", [
            "name": prop("string", "目标名称"), "amount": prop("string", "金额"), "from_account": prop("string", "钱从哪个账户来"),
            "date": prop("string", "日期，默认今天"), "author": author, "dry_run": dryRun,
        ], required: ["name", "amount", "from_account"], readOnly: false),
        tool("undo", "撤销一条改动（history 里的 id，前 8 位也行）。", [
            "change_id": prop("string", "改动 id"), "author": author,
        ], required: ["change_id"], readOnly: false),
    ]

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
        let who = s("author") ?? clientName
        var ledger = try loadLedger()

        /// 写入收尾：预演不保存。
        func commit(_ change: ChangeRecord) throws -> String {
            if flag("dry_run") { return "预演（没有写入）：\(change.summary)" }
            try saveLedger(ledger)
            return "已记：\(change.summary)\n改动 id：\(change.id.uuidString.prefix(8).lowercased())（写错了用 undo 撤销）"
        }

        switch name {
        case "context":
            return try json(LedgerContext(ledger: ledger))
        case "list_transactions":
            let ym = try s("month").map { m -> YearMonth in
                guard let v = YearMonth(m) else { throw ToolError(message: "月份要写成 2026-11") }
                return v
            }
            let hidden = flag("include_private") ? [] : ledger.privateAccountIDs
            let q = s("query").map(Dedup.normalize)
            let txs = ledger.transactions
                .filter { !hidden.contains($0.accountID) }
                .filter { s("book") == nil || $0.bookID == s("book") }
                .filter { s("account") == nil || $0.accountID == s("account") }
                .filter { ym == nil || $0.date.yearMonth == ym }
                .filter { s("category") == nil || $0.category == s("category") }
                .filter { q == nil || Dedup.normalize($0.description).contains(q!) }
                .sorted { $0.date > $1.date }
                .prefix(int("limit", 50))
            return try json(Array(txs))
        case "summary":
            guard let ym = YearMonth(try req("month")) else { throw ToolError(message: "月份要写成 2026-11") }
            let hidden = flag("include_private") ? [] : ledger.privateAccountIDs
            let sum = Summaries.monthly(ledger.transactions, month: ym, bookID: s("book"), hiddenAccounts: hidden)
            var lines = ["\(ym) \(s("book") ?? "全部")", "收入 \(sum.income.formatted)", "支出 \(sum.expense.formatted)", "结余 \(sum.net.formatted)"]
            if let rate = Plans.savingsRate(sum) { lines.append("储蓄率 \(rate)%") }
            lines.append("分类：")
            lines += sum.byCategory.sorted { $0.value < $1.value }.map { "  \($0.key) \($0.value.formatted)" }
            return lines.joined(separator: "\n")
        case "accounts":
            let hidden = flag("include_private") ? [] : ledger.privateAccountIDs
            let balances = Summaries.balances(ledger.transactions)
            return ledger.accounts.filter { !hidden.contains($0.id) }
                .map { "\($0.id)\t\($0.name)\t\((balances[$0.id] ?? .zero).formatted)" }.joined(separator: "\n")
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
            guard ["amount", "description", "date", "account", "book", "category"].contains(where: { s($0) != nil }) else {
                throw ToolError(message: "没写要改什么")
            }
            if s("amount") != nil { t.amount = try money("amount") }
            if let v = s("description") { t.description = v }
            if let v = try date("date") { t.date = v }
            if let v = s("account") { t.accountID = v }
            if let v = s("book") { t.bookID = v }
            if let v = s("category") { t.category = v }
            return try commit(try ledger.editTransaction(t, author: who))
        case "delete_transactions":
            guard let ids = a["ids"] as? [String], !ids.isEmpty else { throw ToolError(message: "ids 要是非空的字符串数组") }
            let txs = try ledger.findTransactions(ids)
            let listing = txs.map { "  \($0.date) \($0.amount.formatted) \($0.description)" }.joined(separator: "\n")
            return try commit(try ledger.removeTransactions(txs.map(\.id), author: who)) + "\n" + listing
        case "account_transfer":
            return try commit(try ledger.addAccountTransfer(amount: try money("amount").magnitude, from: try req("from_account"),
                                                            to: try req("to_account"), date: try date("date") ?? .today,
                                                            note: s("note"), author: who))
        case "mark_account_transfer":
            guard let ids = a["ids"] as? [String], !ids.isEmpty else { throw ToolError(message: "ids 要是非空的字符串数组") }
            let txs = try ledger.findTransactions(ids).map(\.id)
            return try commit(try ledger.markAsAccountTransfer(txs, counterAccount: s("counter_account"), author: who))
        case "debts":
            return try json(Plans.debts(ledger, today: .today, includeClosed: flag("include_closed")))
        case "installments":
            return try json(Plans.installments(ledger))
        case "goals":
            return try json(Plans.goals(ledger))
        case "history":
            return try json(Array(ledger.changes.suffix(int("limit", 20)).reversed()))
        case "add_transaction":
            let tx = Transaction(date: try date("date") ?? .today, amount: try money("amount"), description: try req("description"),
                                 accountID: try req("account"), bookID: try req("book"), category: s("category"), source: "手记（\(who)）")
            return try commit(try ledger.addTransaction(tx, author: who))
        case "add_debt":
            let dir: Debt.Direction
            switch try req("direction") {
            case "they_owe_me": dir = .theyOweMe
            case "i_owe": dir = .iOweThem
            default: throw ToolError(message: "direction 只能是 they_owe_me 或 i_owe")
            }
            let (_, change) = try ledger.addDebt(counterparty: try req("counterparty"), direction: dir, amount: try money("amount").magnitude,
                                                 bookID: s("book") ?? "personal", date: try date("date") ?? .today,
                                                 accountID: s("account"), dueDate: try date("due"), note: s("note"), author: who)
            return try commit(change)
        case "repay_debt":
            let matches = ledger.openDebts(named: try req("counterparty"))
            guard matches.count == 1 else {
                throw ToolError(message: matches.isEmpty ? "没找到和这个名字有关的没还清借款，先调 debts 看看"
                                                         : "这个名字对上了 \(matches.count) 笔借款，写完整一点")
            }
            return try commit(try ledger.repay(debtID: matches[0].id, amount: try money("amount").magnitude,
                                               date: try date("date") ?? .today, accountID: try req("account"), author: who))
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
        case "add_goal":
            let (_, change) = try ledger.addGoal(name: try req("name"), bookID: s("book") ?? "personal", target: try money("target").magnitude,
                                                 deadline: try date("deadline"), savingsAccountID: s("savings_account"),
                                                 locked: flag("locked"), author: who)
            return try commit(change)
        case "goal_deposit":
            let hits = ledger.findGoals(named: try req("name"))
            guard hits.count == 1 else { throw ToolError(message: hits.isEmpty ? "没有这个目标" : "对上了 \(hits.count) 个目标，写完整一点") }
            return try commit(try ledger.deposit(goalID: hits[0].id, amount: try money("amount").magnitude,
                                                 fromAccount: try req("from_account"), date: try date("date") ?? .today, author: who))
        case "undo":
            let key = try req("change_id").lowercased()
            let hits = ledger.changes.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
            guard hits.count == 1 else { throw ToolError(message: hits.isEmpty ? "没有这条改动" : "对上了好几条，多写几位") }
            return try commit(try ledger.undo(changeID: hits[0].id, author: who))
        default:
            throw ToolError(message: "没有这个工具：\(name)")
        }
    }
}
