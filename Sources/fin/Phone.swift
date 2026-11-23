import ArgumentParser
import FinanceCore
import Foundation

// 手机随手记（待记录）、小票发票、报销：MCP 工具和 `fin phone` / `fin receipt` / `fin reimburse`。
// 规则都在 FinanceCore/PhoneCapture.swift，这里只接参数。

/// 附件文件夹（账本旁边的「附件」）。
func attachmentsFolder() -> URL? { LedgerFiles.attachmentsFolder(of: LedgerStores.defaultStore()) }

extension MCPTools {
    static let reimburseStatus: [String: Any] = ["type": "string", "enum": ["none", "toSubmit", "submitted", "paid"],
                                                 "description": "none = 不报销；toSubmit = 待提交；submitted = 已提交；paid = 已到账"]

    static let phoneTools: [[String: Any]] = [
        tool("phone_notes", "手机上记的「待记录」：用户在 iPhone 上说的一句话、拍的小票，还没入账。用户说「同步今天的」「把手机上记的入账」时先调这个。每条有手机先猜的金额日期、小票照片路径（能看图就打开看）和可能重复的已有流水。", [
            "all": prop("boolean", "连已经处理过的也列出来（默认只列没入账的）"),
        ], readOnly: true),
        tool("resolve_phone_note", "把一条待记录入账：记一笔新流水，小票照片自动挂到这笔账上当凭证。日期用小票 / 那句话里的日期（超过两个月先问用户）；拿不准账户、账本、分类先问用户。一张小票能拆明细就先 resolve 再用 split_transaction 拆。", [
            "id": prop("string", "待记录 id（前 8 位）"),
            "amount": prop("string", "金额，支出写负数，如 -12,50"),
            "description": prop("string", "说明 / 商户"),
            "account": prop("string", "账户 id"), "book": prop("string", "账本 id"),
            "date": prop("string", "日期，如 2026-11-21；不填 = 记下那天"),
            "category": prop("string", "分类"), "note": prop("string", "备注"),
            "tags": ["type": "array", "items": ["type": "string"], "description": "标签"],
            "author": author, "dry_run": dryRun,
        ], required: ["id", "amount", "description", "account", "book"], readOnly: false),
        tool("link_phone_note", "这条待记录就是已经在账本里的那笔（比如银行流水已经导进来了）：不新记，标成已处理，小票照片挂到那笔账上。", [
            "id": prop("string", "待记录 id"), "transaction": prop("string", "已有流水的 id（前 8 位）"), "author": author,
        ], required: ["id", "transaction"], readOnly: false),
        tool("dismiss_phone_note", "这条待记录不记了（记重了、记错了、用户说不要）。", [
            "id": prop("string", "待记录 id"), "reason": prop("string", "为什么不记"), "author": author,
        ], required: ["id"], readOnly: false),
        tool("attach_receipt", "给一笔账挂小票 / 发票（图片或 PDF）：把文件复制进账本旁边的「附件」文件夹。", [
            "transaction": prop("string", "流水 id（前 8 位）"),
            "file": prop("string", "文件的完整路径"),
            "kind": ["type": "string", "enum": ["receipt", "invoice", "other"], "description": "receipt = 小票（默认）；invoice = 发票"],
            "author": author,
        ], required: ["transaction", "file"], readOnly: false),
        tool("reimbursements", "报销清单：待提交 / 已提交 / 已到账各多少钱、哪几笔、找谁报、挂了几张凭证。", [
            "status": reimburseStatus,
        ], readOnly: true),
        tool("set_reimbursement", "改报销状态：要报销（toSubmit）、交上去了（submitted）、钱到账了（paid）、不报销（none）。可一次改几笔。", [
            "ids": ["type": "array", "items": ["type": "string"], "description": "流水 id（前 8 位）"],
            "status": reimburseStatus,
            "to": prop("string", "找谁报销：公司名、店名、朋友名字"),
            "date": prop("string", "提交 / 到账日期，默认今天"),
            "paid_transaction": prop("string", "报销到账的那笔收入 id（标 paid 时可以关联上）"),
            "author": author, "dry_run": dryRun,
        ], required: ["ids", "status"], readOnly: false),
        tool("export_reimbursements", "把报销清单导出成一个文件夹：报销清单.csv（Excel 能开）+ 所有小票发票复制一份，方便发给公司。", [
            "status": reimburseStatus,
            "folder": prop("string", "放到哪个文件夹；不填 = 下载文件夹"),
        ], readOnly: false),
    ]

    static func callPhone(_ name: String, _ a: [String: Any], who: String) throws -> String? {
        guard phoneTools.contains(where: { ($0["name"] as? String) == name }) else { return nil }
        func s(_ k: String) -> String? { (a[k] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (a[k] as? NSNumber).map { "\($0)" } }
        func req(_ k: String) throws -> String { guard let v = s(k) else { throw ToolError(message: "缺少参数 \(k)") }; return v }
        func flag(_ k: String) -> Bool { (a[k] as? Bool) ?? false }
        func day(_ k: String) throws -> LocalDate? {
            guard let v = s(k) else { return nil }
            guard let d = LocalDate(v) else { throw ToolError(message: "日期要写成 2026-11-21：\(v)") }
            return d
        }
        func status() throws -> ReimburseStatus? {
            guard let v = s("status") else { return nil }
            guard let st = ReimburseStatus(rawValue: v) else { throw ToolError(message: "status 只能是 none / toSubmit / submitted / paid") }
            return st
        }
        var ledger = try loadLedger()
        func commit(_ change: ChangeRecord) throws -> String {
            if flag("dry_run") { return "预演（没有写入）：\(change.summary)" }
            try saveLedger(ledger)
            return "已记：\(change.summary)\n改动 id：\(change.id.uuidString.prefix(8).lowercased())（写错了用 undo 撤销）"
        }

        switch name {
        case "phone_notes":
            let list = flag("all") ? ledger.captures.sorted { $0.createdAt < $1.createdAt } : ledger.pendingCaptures
            if list.isEmpty { return "手机上没有待入账的。" }
            let folder = attachmentsFolder()
            return try json(list.map { CaptureBrief($0, ledger: ledger, attachmentsFolder: folder) })
        case "resolve_phone_note":
            let c = try ledger.findCapture(try req("id"))
            guard let amount = Money.evaluate(try req("amount")) else { throw ToolError(message: "金额看不懂：\(a["amount"] ?? "")") }
            let tags = Tags.clean(a["tags"] as? [String] ?? [])
            let tx = Transaction(date: try day("date") ?? c.guess?.date ?? c.day, amount: amount, description: try req("description"),
                                 accountID: try req("account"), bookID: try req("book"), category: s("category"),
                                 source: "\(c.device) 待记录（\(who)）", note: s("note"), tags: tags.isEmpty ? nil : tags)
            return try commit(try ledger.resolveCapture(c.id, as: tx, author: who))
        case "link_phone_note":
            let c = try ledger.findCapture(try req("id"))
            let t = try ledger.findTransactions([try req("transaction")])[0]
            return try commit(try ledger.linkCapture(c.id, to: t.id, author: who))
        case "dismiss_phone_note":
            let c = try ledger.findCapture(try req("id"))
            return try commit(try ledger.dismissCapture(c.id, reason: s("reason"), author: who))
        case "attach_receipt":
            let t = try ledger.findTransactions([try req("transaction")])[0]
            guard let folder = attachmentsFolder() else { throw ToolError(message: "这本账不在文件里，挂不了附件") }
            let src = URL(fileURLWithPath: (try req("file") as NSString).expandingTildeInPath)
            let kind = s("kind").flatMap(Attachment.Kind.init(rawValue:)) ?? .receipt
            let file = try LedgerFiles.importAttachment(from: src, into: folder)
            return try commit(try ledger.attach(Attachment(kind: kind, file: file, name: src.lastPathComponent, addedBy: who), to: t.id, author: who))
        case "reimbursements":
            return reimbursementText(ledger, try status())
        case "set_reimbursement":
            guard let ids = a["ids"] as? [String], !ids.isEmpty else { throw ToolError(message: "ids 要是非空的字符串数组") }
            guard let st = try status() else { throw ToolError(message: "缺少参数 status") }
            let txs = try ledger.findTransactions(ids)
            let paid = try s("paid_transaction").map { try ledger.findTransactions([$0])[0].id }
            return try commit(try ledger.setReimbursement(txs.map(\.id), status: st, to: s("to"), on: try day("date") ?? .today,
                                                          paidTransactionID: paid, author: who))
        case "export_reimbursements":
            let out = s("folder").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            return try exportReimbursements(ledger, status: try status(), into: out)
        default:
            return nil
        }
    }
}

func reimbursementText(_ ledger: Ledger, _ status: ReimburseStatus?) -> String {
    let s = ledger.reimbursementSummary
    var lines = ["待提交 \(s.toSubmit.formatted)（\(s.counts[.toSubmit] ?? 0) 笔）· 已提交 \(s.submitted.formatted)（\(s.counts[.submitted] ?? 0) 笔）· 已到账 \(s.paid.formatted)（\(s.counts[.paid] ?? 0) 笔）"]
    let items = ledger.reimbursements(status)
    if items.isEmpty { lines.append(status == nil ? "还没有标报销的账。" : "「\(status!.label)」里没有。") }
    for i in items {
        let t = i.transaction, p = i.paperwork
        lines.append("  \(t.id.uuidString.prefix(8).lowercased()) \(t.date) \(t.amount.magnitude.formatted) \(t.description) · \(p.reimburse.label)"
                     + (p.reimburseTo.map { " · 找\($0)" } ?? "") + (p.attachments.isEmpty ? " · 没挂凭证" : " · \(p.attachments.count) 张凭证"))
    }
    return lines.joined(separator: "\n")
}

/// 导出报销清单：一个文件夹，里面是 CSV 和凭证副本。返回给人看的一句话。
func exportReimbursements(_ ledger: Ledger, status: ReimburseStatus?, into folder: URL?) throws -> String {
    let items = ledger.reimbursements(status ?? .toSubmit)
    guard !items.isEmpty else { return "「\((status ?? .toSubmit).label)」里没有要导出的。" }
    let base = folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory())
    let r = try LedgerFiles.exportReimbursements(items, ledger: ledger, attachments: attachmentsFolder(), into: base)
    let total = items.reduce(Money.zero) { $0 + $1.transaction.amount.magnitude }
    return "已导出 \(items.count) 笔、合计 \(total.formatted)、\(r.files.count - 1) 张凭证到：\(r.folder.path)"
}

// MARK: - 命令行

struct PhoneCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "phone", abstract: "手机上记的「待记录」：看、入账、对上已有的、不记。",
        subcommands: [List.self, Resolve.self, Link.self, Dismiss.self], defaultSubcommand: List.self)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "没入账的待记录。")
        @Flag(help: "输出 JSON。") var json = false
        func run() throws {
            let ledger = try loadLedger()
            let briefs = ledger.pendingCaptures.map { CaptureBrief($0, ledger: ledger, attachmentsFolder: attachmentsFolder()) }
            if json { try Output.json(briefs); return }
            if briefs.isEmpty { print("手机上没有待入账的。"); return }
            for b in briefs {
                print("\(b.id) \(b.recordedAt) [\(b.kind)] \(b.text)" + (b.guessAmount.map { " · 猜 \($0)" } ?? "") + (b.guessDate.map { " · \($0)" } ?? ""))
                if let p = b.photoPath { print("    照片：\(p)") }
                for d in b.possibleDuplicates { print("    可能重复：\(d)") }
            }
        }
    }

    struct Resolve: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "resolve", abstract: "把一条待记录入账（小票照片挂到这笔上）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "待记录 id（前 8 位）。") var id: String
        @Argument(help: "金额，支出写负数。") var amount: String
        @Argument(help: "说明 / 商户。") var description: String
        @Option(help: "账户 id。") var account: String
        @Option(help: "账本 id。") var book: String
        @Option(help: "日期，默认记下那天。") var date: String?
        @Option(help: "分类。") var category: String?
        func run() throws {
            var ledger = try loadLedger()
            let c = try ledger.findCapture(id)
            let d = try date.map { try parseDate($0) } ?? c.guess?.date ?? c.day
            let tx = Transaction(date: d, amount: try parseMoney(amount), description: description, accountID: account, bookID: book,
                                 category: category, source: "\(c.device) 待记录（\(w.who)）")
            let change = try ledger.resolveCapture(c.id, as: tx, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "link", abstract: "这条就是已有的那笔：标成已处理，照片挂上去。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "待记录 id。") var id: String
        @Argument(help: "已有流水 id。") var transaction: String
        func run() throws {
            var ledger = try loadLedger()
            let c = try ledger.findCapture(id)
            let t = try ledger.findTransactions([transaction])[0]
            let change = try ledger.linkCapture(c.id, to: t.id, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Dismiss: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dismiss", abstract: "不记了。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "待记录 id。") var id: String
        @Option(help: "为什么。") var reason: String?
        func run() throws {
            var ledger = try loadLedger()
            let c = try ledger.findCapture(id)
            let change = try ledger.dismissCapture(c.id, reason: reason, author: w.who)
            try finish(ledger, change, w)
        }
    }
}

struct ReceiptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "receipt", abstract: "给一笔账挂小票 / 发票（图片或 PDF）。")
    @OptionGroup var w: WriteOptions
    @Argument(help: "流水 id（前 8 位）。") var transaction: String
    @Argument(help: "文件路径。") var file: String
    @Flag(help: "是发票（默认是小票）。") var invoice = false
    func run() throws {
        var ledger = try loadLedger()
        let t = try ledger.findTransactions([transaction])[0]
        guard let folder = attachmentsFolder() else { throw ValidationError("这本账不在文件里，挂不了附件") }
        let src = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        let name = try LedgerFiles.importAttachment(from: src, into: folder)
        let a = Attachment(kind: invoice ? .invoice : .receipt, file: name, name: src.lastPathComponent, addedBy: w.who)
        let change = try ledger.attach(a, to: t.id, author: w.who)
            try finish(ledger, change, w)
    }
}

struct ReimburseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reimburse", abstract: "报销：看清单、改状态、导出给公司。",
        subcommands: [List.self, SetStatus.self, Export.self], defaultSubcommand: List.self)

    static func status(_ s: String?) throws -> ReimburseStatus? {
        guard let s else { return nil }
        guard let st = ReimburseStatus(rawValue: s) else { throw ValidationError("状态只能是 none / toSubmit / submitted / paid") }
        return st
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "报销清单。")
        @Option(help: "只看一种：toSubmit / submitted / paid。") var status: String?
        func run() throws { print(reimbursementText(try loadLedger(), try ReimburseCommand.status(status))) }
    }

    struct SetStatus: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "改报销状态。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "状态：none / toSubmit / submitted / paid。") var status: String
        @Argument(help: "流水 id（可以几个）。") var ids: [String]
        @Option(help: "找谁报销。") var to: String?
        @Option(help: "日期，默认今天。") var date: String?
        func run() throws {
            var ledger = try loadLedger()
            guard let st = try ReimburseCommand.status(status) else { return }
            let txs = try ledger.findTransactions(ids)
            let change = try ledger.setReimbursement(txs.map(\.id), status: st, to: to, on: try date.map { try parseDate($0) } ?? .today,
                                                     author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "export", abstract: "导出成文件夹：CSV + 凭证副本。")
        @Option(help: "哪种，默认 toSubmit（待提交）。") var status: String?
        @Option(help: "放到哪，默认下载文件夹。") var folder: String?
        func run() throws {
            print(try exportReimbursements(try loadLedger(), status: try ReimburseCommand.status(status),
                                           into: folder.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }))
        }
    }
}
