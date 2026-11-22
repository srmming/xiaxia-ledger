import ArgumentParser
import FinanceCore
import Foundation

/// 「50 USD」「50,00 usd」「USD 50」→ 外币金额。sign 决定正负（跟着那笔流水）。
func parseForeign(_ text: String, sign: Int64 = 1) throws -> ForeignAmount {
    let parts = text.split(separator: " ").map(String.init)
    guard parts.count == 2 else { throw ValidationError("原价写成「50 USD」这样：金额、空格、三个字母的币种") }
    let (a, c) = Money(parsing: parts[0]) != nil ? (parts[0], parts[1]) : (parts[1], parts[0])
    guard let m = Money(parsing: a) else { throw ValidationError("原价金额看不懂：\(a)") }
    guard Currencies.isKnown(c) else { throw ValidationError(CurrencyError.unknownCurrency(c).localizedDescription) }
    return ForeignAmount(amount: Money(cents: m.magnitude.cents * sign), currency: c)
}

/// 取欧洲央行汇率并存进账本。fin 和 MCP 共用。
func refreshRates(_ ledger: inout Ledger) throws -> String {
    let since = ledger.earliestForeignDate
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<[String: [RatePoint]], Error> = .failure(CurrencyError.network("没开始"))
    Task {
        do { result = .success(try await ECBRates.fetch(since: since)) } catch { result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    let table = try result.get()
    ledger.applyRates(table)
    let day = ledger.currency.latestRateDate.map(\.description) ?? "?"
    let used = ledger.foreignCurrencies.sorted()
    return "汇率已更新（欧洲央行，最新是 \(day) 的）" + (used.isEmpty ? "" : "，用到的外币：\(used.joined(separator: "、"))")
}

func fxText(_ ledger: Ledger) -> String {
    var lines = ["主币种：\(Currencies.label(ledger.baseCurrency))"]
    let foreign = ledger.accounts.filter { ledger.currency(ofAccount: $0.id) != ledger.baseCurrency }
    if foreign.isEmpty { lines.append("外币账户：没有（所有账户都是主币种）") }
    let balances = ledger.accountBalances()
    for a in foreign {
        let code = ledger.currency(ofAccount: a.id)
        let b = balances[a.id] ?? (.zero, .zero)
        var line = "  \(a.id)\t\(a.name)\t\(Currencies.label(code))\t余额 \(b.native.formatted(in: code))，约 \(b.base.formatted(in: ledger.baseCurrency))"
        if let r = ledger.rateToBase(code, on: .today) { line += "（1 \(code) = \(String(format: "%.4f", r.rate)) \(ledger.baseCurrency)，\(r.date) 的汇率）" }
        lines.append(line)
    }
    if let at = ledger.currency.updatedAt {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        lines.append("汇率：欧洲央行，\(f.string(from: at)) 取的")
    } else if !ledger.foreignCurrencies.isEmpty {
        lines.append("汇率：还没取过。运行 fin fx update")
    }
    let missing = ledger.missingRateCurrencies
    if !missing.isEmpty { lines.append("缺汇率：\(missing.joined(separator: "、"))，现在先按 1:1 算") }
    return lines.joined(separator: "\n")
}

struct FXCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fx", abstract: "多币种：看主币种和外币账户、更新汇率、改主币种、改账户币种、改某笔的汇率。",
        discussion: """
        fin fx                              看主币种、外币账户和汇率
        fin fx update                       从欧洲央行取汇率（只下载公开汇率表，不发出任何账目）
        fin fx base USD                     主币种改成美元（流水金额不变，只是汇总换成美元）
        fin fx account wise-usd USD         这个账户是美元账户
        fin fx set-rate 1a2b3c4d --bank 46,12   这笔美元流水银行实际扣了 46,12（主币种）
        """,
        subcommands: [FXShow.self, FXUpdate.self, FXBase.self, FXAccount.self, FXSetRate.self],
        defaultSubcommand: FXShow.self)

    struct FXShow: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "看主币种、外币账户和汇率。")
        @Flag(name: .long, help: "输出 JSON。") var json = false
        func run() throws {
            let ledger = try loadLedger()
            if json { return try Output.json(ledger.currency) }
            print(fxText(ledger))
        }
    }

    struct FXUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "update", abstract: "从欧洲央行取汇率，补上外币流水缺的汇率。")
        func run() throws {
            var ledger = try loadLedger()
            let msg = try refreshRates(&ledger)
            try saveLedger(ledger)
            print(msg)
        }
    }

    struct FXBase: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "base", abstract: "改主币种。已有流水金额不变。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "三个字母，如 EUR、USD、CNY。") var code: String
        func run() throws {
            var ledger = try loadLedger()
            let change = try ledger.setBaseCurrency(code, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct FXAccount: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "account", abstract: "给账户定币种。账户里的流水金额不变。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "账户 id。") var account: String
        @Argument(help: "三个字母，如 USD。") var code: String
        func run() throws {
            var ledger = try loadLedger()
            let change = try ledger.setAccountCurrency(account, code, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct FXSetRate: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set-rate", abstract: "改一笔外币流水的汇率：按银行实际扣的主币种（--bank），或直接填汇率（--rate）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "流水编号（前几位）。") var id: String
        @Option(help: "银行实际扣了多少主币种，如 46,12。") var bank: String?
        @Option(help: "1 个外币 = 多少主币种，如 0,925。") var rate: String?
        func run() throws {
            var ledger = try loadLedger()
            let tx = try ledger.findTransactions([id]).first!
            let r = try rate.map { s -> Double in
                guard let v = Double(s.replacingOccurrences(of: ",", with: ".")) else { throw ValidationError("汇率看不懂：\(s)") }
                return v
            }
            let change = try ledger.setRate(tx.id, rate: r, bankAmount: try bank.map(parseMoney), author: w.who)
            try finish(ledger, change, w)
        }
    }
}

// MARK: 订阅

func subscriptionsText(_ ledger: Ledger, all: Bool, book: String?) -> String {
    let list = Subscriptions.status(ledger).filter { (all || $0.cancelledOn == nil) && (book == nil || $0.bookID == nil || $0.bookID == book) }
    let t = Subscriptions.totals(list, bookID: book)
    if list.isEmpty { return "还没有登记订阅。可以用 fin subscription find 从流水里找可能是订阅的。" }
    var lines = ["在续 \(t.activeCount) 个，每月约 \(t.monthly.formatted(in: ledger.baseCurrency))，一年约 \(t.yearly.formatted(in: ledger.baseCurrency))"
                 + (t.dueSoon > 0 ? "；7 天内要扣 \(t.dueSoon) 个" : "")]
    for s in list {
        var line = "  \(s.id.uuidString.prefix(8).lowercased())\t\(s.name)\t\(s.cycle.label) \(s.amount.formatted(in: s.currency))"
        if let c = s.cancelledOn { line += "\t已停（\(c)）" }
        else if let n = s.nextDate, let d = s.daysLeft { line += "\t下次 \(n)" + (d <= 14 ? "（\(d == 0 ? "今天" : "\(d) 天后")）" : "") }
        if s.priceChanged, let last = s.lastChargeAmount { line += "\t最近一次扣了 \(last.formatted(in: s.currency))，可能涨价了" }
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}

func candidatesText(_ ledger: Ledger) -> String {
    let found = Subscriptions.detect(ledger)
    if found.isEmpty { return "流水里没认出新的订阅（已经登记的不再列）。" }
    var lines = ["流水里认出 \(found.count) 个可能是订阅的（先问用户哪些是，确认后再 fin subscription add）："]
    for c in found {
        lines.append("  \(c.name)\t\(c.cycle.label) \(c.amount.formatted(in: c.currency))\t扣过 \(c.count) 次，最近 \(c.lastDate)，下次约 \(c.nextDate)\t账户 \(c.accountID)\t关键词 \(c.key)")
    }
    return lines.joined(separator: "\n")
}

struct SubscriptionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "subscriptions", abstract: "列出订阅：每月 / 每年合计，按下次扣款排。")
    @OptionGroup var options: GlobalOptions
    @Flag(help: "停了的也列出来。") var all = false
    func run() throws {
        let ledger = try loadLedger()
        if options.json {
            struct Out: Encodable { var totals: SubscriptionTotals; var baseCurrency: String; var subscriptions: [SubscriptionStatus] }
            let list = Subscriptions.status(ledger).filter { all || $0.cancelledOn == nil }
            return try Output.json(Out(totals: Subscriptions.totals(list, bookID: options.book), baseCurrency: ledger.baseCurrency, subscriptions: list))
        }
        print(subscriptionsText(ledger, all: all, book: options.book))
    }
}

struct SubscriptionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscription", abstract: "登记、改、停、删订阅；从流水里找可能是订阅的。",
        discussion: """
        fin subscription find
        fin subscription add 视频会员 13,99 --cycle monthly --next 2026-12-03 --account revolut --match netflix
        fin subscription edit 视频会员 --amount 15,99
        fin subscription cancel 视频会员
        """,
        subcommands: [SubFind.self, SubAdd.self, SubEdit.self, SubCancel.self, SubRemove.self])

    struct SubFind: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "find", abstract: "从流水里认出可能是订阅的（只列出来，不写入）。")
        @Flag(name: .long, help: "输出 JSON。") var json = false
        func run() throws {
            let ledger = try loadLedger()
            if json { return try Output.json(Subscriptions.detect(ledger)) }
            print(candidatesText(ledger))
        }
    }

    struct SubAdd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "登记一个订阅。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "名字，如「视频会员」。") var name: String
        @Argument(help: "每次扣多少，如 13,99。") var amount: String
        @Option(help: "周期：weekly、monthly、quarterly、yearly。") var cycle: String = "monthly"
        @Option(help: "下次扣款日，如 2026-12-03。") var next: String
        @Option(help: "从哪个账户扣。") var account: String?
        @Option(help: "账本 id。") var book: String?
        @Option(help: "分类，如「娱乐」。") var category: String?
        @Option(help: "币种（和扣款账户不一样时才填），如 USD。") var currency: String?
        @Option(help: "在流水里认它的关键词（商户名），如 netflix。") var match: String?
        @Option(help: "备注。") var note: String?
        func run() throws {
            guard let c = Subscription.Cycle(text: cycle) else { throw ValidationError("周期只能是 weekly、monthly、quarterly、yearly") }
            var ledger = try loadLedger()
            let s = Subscription(name: name, amount: try parseMoney(amount), currency: currency, cycle: c, nextDate: try parseDate(next),
                                 accountID: account, bookID: book, category: category, match: match, note: note)
            let change = try ledger.addSubscription(s, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct SubEdit: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "edit", abstract: "改订阅：涨价了、换了扣款日、换了账户……只改写了的。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "订阅名字或编号。") var key: String
        @Option(help: "新名字。") var name: String?
        @Option(help: "新金额。") var amount: String?
        @Option(help: "周期。") var cycle: String?
        @Option(help: "下次扣款日。") var next: String?
        @Option(help: "账户。") var account: String?
        @Option(help: "账本。") var book: String?
        @Option(help: "分类。") var category: String?
        @Option(help: "关键词。") var match: String?
        @Option(help: "备注。") var note: String?
        @Flag(help: "停了的又续上。") var resume = false
        func run() throws {
            var ledger = try loadLedger()
            var s = try ledger.findSubscription(key)
            if let name { s.name = name }
            if let amount { s.amount = try parseMoney(amount).magnitude }
            if let cycle {
                guard let c = Subscription.Cycle(text: cycle) else { throw ValidationError("周期只能是 weekly、monthly、quarterly、yearly") }
                s.cycle = c
            }
            if let next { s.nextDate = try parseDate(next) }
            if let account { s.accountID = account }
            if let book { s.bookID = book }
            if let category { s.category = category }
            if let match { s.match = match }
            if let note { s.note = note }
            if resume { s.cancelledOn = nil }
            let change = try ledger.editSubscription(s, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct SubCancel: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "cancel", abstract: "不续了（留着记录，不算进合计）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "订阅名字或编号。") var key: String
        @Option(help: "哪天停的，默认今天。") var date: String?
        func run() throws {
            var ledger = try loadLedger()
            let s = try ledger.findSubscription(key)
            let change = try ledger.cancelSubscription(s.id, on: try parseDate(date), author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct SubRemove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "remove", abstract: "删掉登记错的订阅（能撤销）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "订阅名字或编号。") var key: String
        func run() throws {
            var ledger = try loadLedger()
            let s = try ledger.findSubscription(key)
            let change = try ledger.removeSubscription(s.id, author: w.who)
            try finish(ledger, change, w)
        }
    }
}

// MARK: MCP 工具（多币种、订阅）

extension MCPTools {
    static let currencySubsTools: [[String: Any]] = [
        tool("currency", "多币种：主币种、外币账户和余额（原币 + 约合主币种）、汇率是哪天的、缺哪些汇率。", [:], readOnly: true),
        tool("update_rates", "从欧洲央行取最新汇率（公开汇率表，不发出账目），补上外币流水缺的汇率。", [:], readOnly: false),
        tool("set_base_currency", "改主币种（汇总、月报都换成它）。已有流水金额不变。", [
            "currency": prop("string", "三个字母，如 EUR、USD、CNY"), "author": author, "dry_run": dryRun,
        ], required: ["currency"], readOnly: false),
        tool("set_account_currency", "给账户定币种（美元卡、人民币账户）。账户里的流水金额不变。", [
            "account": prop("string", "账户 id"), "currency": prop("string", "三个字母，如 USD"), "author": author, "dry_run": dryRun,
        ], required: ["account", "currency"], readOnly: false),
        tool("set_rate", "改一笔外币流水换成主币种的汇率：bank_amount = 银行实际扣了多少主币种（推荐），或 rate = 1 外币等于多少主币种。", [
            "id": prop("string", "流水 id（前 8 位也行）"), "bank_amount": prop("string", "银行实际扣的主币种金额，如 46,12"),
            "rate": prop("number", "汇率，如 0.925"), "author": author, "dry_run": dryRun,
        ], required: ["id"], readOnly: false),
        tool("subscriptions", "订阅：每月和一年合计（主币种）、每个订阅下次哪天扣、7 天内要扣的、可能涨价的。", [
            "include_cancelled": prop("boolean", "停了的也列出"), "book": prop("string", "账本 id"),
        ], readOnly: true),
        tool("find_subscriptions", "从流水里认出可能是订阅的（同一商户、金额差不多、每周/每月/每季/每年扣一次）。只列出来不写入：先问用户哪些是，再 add_subscription。", [:], readOnly: true),
        tool("add_subscription", "登记一个订阅。", [
            "name": prop("string", "名字"), "amount": prop("string", "每次扣多少，如 13,99"),
            "cycle": ["type": "string", "enum": ["weekly", "monthly", "quarterly", "yearly"], "description": "周期，默认 monthly"],
            "next_date": prop("string", "下次扣款日 2026-12-03"), "account": prop("string", "从哪个账户扣"),
            "book": prop("string", "账本 id"), "category": prop("string", "分类"),
            "currency": prop("string", "币种（和账户不一样时才填）"), "match": prop("string", "在流水里认它的关键词（find_subscriptions 给的 key）"),
            "note": prop("string", "备注"), "author": author, "dry_run": dryRun,
        ], required: ["name", "amount", "next_date"], readOnly: false),
        tool("edit_subscription", "改订阅（涨价、换扣款日、换账户），只改填了的；cancel=true 表示不续了，resume=true 恢复。", [
            "subscription": prop("string", "订阅名字或 id"), "name": prop("string", "新名字"), "amount": prop("string", "新金额"),
            "cycle": prop("string", "周期"), "next_date": prop("string", "下次扣款日"), "account": prop("string", "账户"),
            "book": prop("string", "账本"), "category": prop("string", "分类"), "match": prop("string", "关键词"), "note": prop("string", "备注"),
            "cancel": prop("boolean", "不续了"), "resume": prop("boolean", "停了的又续上"), "author": author, "dry_run": dryRun,
        ], required: ["subscription"], readOnly: false),
        tool("remove_subscription", "删掉登记错的订阅（能撤销）。不续了请用 edit_subscription cancel=true。", [
            "subscription": prop("string", "订阅名字或 id"), "author": author, "dry_run": dryRun,
        ], required: ["subscription"], readOnly: false),
    ]

    /// 处理上面这些工具；不是它们就返回 nil。
    static func callCurrencySubs(_ name: String, _ a: [String: Any], who: String) throws -> String? {
        func s(_ k: String) -> String? { (a[k] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (a[k] as? NSNumber).map { "\($0)" } }
        func req(_ k: String) throws -> String { guard let v = s(k) else { throw ToolError(message: "缺少参数 \(k)") }; return v }
        func flag(_ k: String) -> Bool { (a[k] as? Bool) ?? false }
        func money(_ k: String) throws -> Money {
            guard let m = Money(parsing: try req(k)) else { throw ToolError(message: "金额看不懂：\(a[k] ?? "")") }
            return m
        }
        func date(_ k: String) throws -> LocalDate {
            let v = try req(k)
            guard let d = LocalDate(v) else { throw ToolError(message: "日期要写成 2026-11-21：\(v)") }
            return d
        }
        func cycle(_ k: String) throws -> Subscription.Cycle? {
            guard let v = s(k) else { return nil }
            guard let c = Subscription.Cycle(text: v) else { throw ToolError(message: "cycle 只能是 weekly、monthly、quarterly、yearly") }
            return c
        }
        let names: Set<String> = ["currency", "update_rates", "set_base_currency", "set_account_currency", "set_rate",
                                  "subscriptions", "find_subscriptions", "add_subscription", "edit_subscription", "remove_subscription"]
        guard names.contains(name) else { return nil }
        var ledger = try loadLedger()
        func commit(_ change: ChangeRecord) throws -> String {
            if flag("dry_run") { return "预演（没有写入）：\(change.summary)" }
            try saveLedger(ledger)
            return "已记：\(change.summary)\n改动 id：\(change.id.uuidString.prefix(8).lowercased())（写错了用 undo 撤销）"
        }
        switch name {
        case "currency":
            return fxText(ledger)
        case "update_rates":
            let msg = try refreshRates(&ledger)
            try saveLedger(ledger)
            return msg
        case "set_base_currency":
            return try commit(try ledger.setBaseCurrency(try req("currency"), author: who))
        case "set_account_currency":
            return try commit(try ledger.setAccountCurrency(try req("account"), try req("currency"), author: who))
        case "set_rate":
            let tx = try ledger.findTransactions([try req("id")])[0]
            let bank: Money? = s("bank_amount") == nil ? nil : try money("bank_amount")
            let rate = (a["rate"] as? NSNumber)?.doubleValue ?? s("rate").flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            return try commit(try ledger.setRate(tx.id, rate: rate, bankAmount: bank, author: who))
        case "subscriptions":
            return subscriptionsText(ledger, all: flag("include_cancelled"), book: s("book"))
        case "find_subscriptions":
            return candidatesText(ledger)
        case "add_subscription":
            let sub = Subscription(name: try req("name"), amount: try money("amount"), currency: s("currency"),
                                   cycle: try cycle("cycle") ?? .monthly, nextDate: try date("next_date"),
                                   accountID: s("account"), bookID: s("book"), category: s("category"), match: s("match"), note: s("note"))
            return try commit(try ledger.addSubscription(sub, author: who))
        case "edit_subscription":
            var sub = try ledger.findSubscription(try req("subscription"))
            if let v = s("name") { sub.name = v }
            if s("amount") != nil { sub.amount = try money("amount").magnitude }
            if let c = try cycle("cycle") { sub.cycle = c }
            if s("next_date") != nil { sub.nextDate = try date("next_date") }
            if let v = s("account") { sub.accountID = v }
            if let v = s("book") { sub.bookID = v }
            if let v = s("category") { sub.category = v }
            if let v = s("match") { sub.match = v }
            if let v = s("note") { sub.note = v }
            if flag("cancel") { sub.cancelledOn = sub.cancelledOn ?? .today }
            if flag("resume") { sub.cancelledOn = nil }
            return try commit(try ledger.editSubscription(sub, author: who))
        case "remove_subscription":
            let sub = try ledger.findSubscription(try req("subscription"))
            return try commit(try ledger.removeSubscription(sub.id, author: who))
        default:
            return nil
        }
    }
}
