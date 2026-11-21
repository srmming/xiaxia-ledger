import ArgumentParser
import FinanceCore
import Foundation

@main
struct Fin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fin",
        abstract: "夏夏账本命令行：给 AI 和人查看、整理财务。",
        discussion: "数据位置默认 ~/Library/Application Support/XiaxiaLedger/ledger.json，可用 XIAXIA_LEDGER_PATH 覆盖。",
        subcommands: [ContextCommand.self, BooksCommand.self, AccountsCommand.self, TxCommand.self, SummaryCommand.self, DebtsCommand.self, InstallmentsCommand.self, GoalsCommand.self,
                      AddCommand.self, DebtCommand.self, AccountCommand.self, HistoryCommand.self, UndoCommand.self]
    )
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "输出 JSON，方便 AI 读。")
    var json = false

    @Option(name: .long, help: "账本 id，如 personal、miora。不填 = 全部。")
    var book: String?
}

enum Output {
    static func json<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        print(String(decoding: data, as: UTF8.self))
    }
}

func loadLedger() throws -> Ledger { try JSONFileLedgerStore.defaultStore().load() }
func saveLedger(_ ledger: Ledger) throws { try JSONFileLedgerStore.defaultStore().save(ledger) }

/// 写入类命令共用：谁在改、日期、金额。
struct WriteOptions: ParsableArguments {
    @Option(help: "谁在改：ming、Claude、Codex、DeepSeek……不填就读环境变量 XIAXIA_AUTHOR，再没有就是「AI」。")
    var author: String?
    @Flag(name: .long, help: "输出 JSON。") var json = false

    var who: String { author ?? ProcessInfo.processInfo.environment["XIAXIA_AUTHOR"] ?? "AI" }
}

func parseMoney(_ s: String) throws -> Money {
    guard let m = Money(parsing: s) else { throw ValidationError("金额看不懂：\(s)，写成 12,50 或 12.50") }
    return m
}

func parseDate(_ s: String?) throws -> LocalDate {
    guard let s else { return .today }
    guard let d = LocalDate(s) else { throw ValidationError("日期格式要像 2026-11-21") }
    return d
}

func report(_ change: ChangeRecord, json: Bool) throws {
    if json { return try Output.json(change) }
    print("已记：\(change.summary)（改动 \(change.id.uuidString.prefix(8))，写错了用 fin undo \(change.id.uuidString.prefix(8)) 撤销）")
}

struct ContextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "context", abstract: "说明书：账本、账户、口径、截止日、最近改动。")
    @OptionGroup var options: GlobalOptions

    func run() throws {
        let ctx = LedgerContext(ledger: try loadLedger())
        if options.json { return try Output.json(ctx) }
        print("账本：")
        for b in ctx.books { print("  \(b.id)\t\(b.name)\t\(b.transactions) 笔") }
        print("账户：")
        if ctx.accounts.isEmpty { print("  （还没有账户）") }
        for a in ctx.accounts { print("  \(a.id)\t\(a.name)\t余额 \(a.balance)\t截止 \(a.lastStatementDate ?? "—")") }
        print("流水：\(ctx.transactionCount) 笔（\(ctx.firstDate ?? "—") 到 \(ctx.lastDate ?? "—")），未分账本 \(ctx.unassignedCount) 笔")
        print("往来：别人欠我 \(ctx.owedToMe)，我欠别人 \(ctx.iOwe)（\(ctx.openDebts) 笔未结清）")
        print("分期：\(ctx.activeInstallments) 个进行中；目标：\(ctx.goals) 个")
        print("最近改动：")
        if ctx.recentChanges.isEmpty { print("  （还没有）") }
        for c in ctx.recentChanges { print("  · \(c)") }
        print("口径：")
        for r in ctx.rules { print("  · \(r)") }
    }
}

struct BooksCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "books", abstract: "列出账本。")
    @OptionGroup var options: GlobalOptions
    func run() throws {
        let books = try loadLedger().books
        if options.json { return try Output.json(books) }
        for b in books { print("\(b.id)\t\(b.name)\t\(b.currency)") }
    }
}

struct AccountsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "accounts", abstract: "列出账户和余额。")
    @OptionGroup var options: GlobalOptions
    func run() throws {
        let ledger = try loadLedger()
        let balances = Summaries.balances(ledger.transactions)
        if options.json {
            struct Row: Encodable { var account: Account; var balance: String }
            return try Output.json(ledger.accounts.map { Row(account: $0, balance: (balances[$0.id] ?? .zero).decimalString) })
        }
        for a in ledger.accounts { print("\(a.id)\t\(a.name)\t\((balances[a.id] ?? .zero).formatted)") }
    }
}

struct TxCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tx", abstract: "查流水。")
    @OptionGroup var options: GlobalOptions
    @Option(help: "账户 id。") var account: String?
    @Option(help: "月份，如 2026-11。") var month: String?
    @Option(help: "分类。") var category: String?
    @Option(help: "最多显示几条。") var limit: Int = 50

    func run() throws {
        let ym: YearMonth?
        if let month {
            guard let parsed = YearMonth(month) else { throw ValidationError("月份格式要像 2026-11") }
            ym = parsed
        } else { ym = nil }
        let txs = try loadLedger().transactions
            .filter { options.book == nil || $0.bookID == options.book }
            .filter { account == nil || $0.accountID == account }
            .filter { ym == nil || $0.date.yearMonth == ym }
            .filter { category == nil || $0.category == category }
            .sorted { $0.date > $1.date }
            .prefix(limit)
        if options.json { return try Output.json(Array(txs)) }
        if txs.isEmpty { print("没有符合条件的流水。") }
        for t in txs {
            print("\(t.date)\t\(t.amount.formatted)\t\(t.bookID ?? "未分")\t\(t.category ?? "未分类")\t\(t.description)")
        }
    }
}

struct SummaryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "summary", abstract: "月度收支和分类汇总。")
    @OptionGroup var options: GlobalOptions
    @Option(help: "月份，如 2026-11。") var month: String

    func run() throws {
        guard let ym = YearMonth(month) else { throw ValidationError("月份格式要像 2026-11") }
        let s = Summaries.monthly(try loadLedger().transactions, month: ym, bookID: options.book)
        if options.json {
            struct Out: Encodable { var month: String; var book: String?; var income: String; var expense: String; var net: String; var byCategory: [String: String] }
            return try Output.json(Out(month: s.month.description, book: s.bookID, income: s.income.decimalString,
                                       expense: s.expense.decimalString, net: s.net.decimalString,
                                       byCategory: s.byCategory.mapValues(\.decimalString)))
        }
        print("\(s.month)  \(options.book ?? "全部")")
        print("收入 \(s.income.formatted)  支出 \(s.expense.formatted)  结余 \(s.net.formatted)")
        for (cat, amount) in s.byCategory.sorted(by: { $0.value < $1.value }) { print("  \(cat)\t\(amount.formatted)") }
    }
}

struct DebtsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "debts", abstract: "借款往来：谁欠我钱、我欠谁（默认只列没还清的）。")
    @OptionGroup var options: GlobalOptions
    @Flag(help: "连已结清的也列出来。") var all = false

    func run() throws {
        let list = Plans.debts(try loadLedger(), today: .today, includeClosed: all)
        if options.json { return try Output.json(list) }
        let owed = list.filter { $0.direction == .theyOweMe }, owe = list.filter { $0.direction == .iOweThem }
        print("别人欠我：")
        if owed.isEmpty { print("  （没有）") }
        for d in owed { print("  \(d.counterparty)\t还欠 \(d.outstanding.formatted)（借出 \(d.principal.formatted)）\(d.overdue ? "\t已过期" : "")") }
        print("我欠别人：")
        if owe.isEmpty { print("  （没有）") }
        for d in owe { print("  \(d.counterparty)\t还欠 \(d.outstanding.formatted)\(d.dueDate.map { "\t\($0) 前还" } ?? "")") }
    }
}

struct InstallmentsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "installments", abstract: "分期：还了几期、还剩多少、下次扣款日。")
    @OptionGroup var options: GlobalOptions
    func run() throws {
        let list = Plans.installments(try loadLedger())
        if options.json { return try Output.json(list) }
        if list.isEmpty { print("没有分期。") }
        for i in list {
            print("\(i.name)\t\(i.paidCount)/\(i.count) 期\t每期 \(i.perPayment.formatted)\t还剩 \(i.remaining.formatted)\t下次 \(i.nextDate?.description ?? "已还清")")
        }
    }
}

struct GoalsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "goals", abstract: "目标和储蓄进度。")
    @OptionGroup var options: GlobalOptions
    func run() throws {
        let list = Plans.goals(try loadLedger())
        if options.json { return try Output.json(list) }
        if list.isEmpty { print("还没有目标。") }
        for g in list {
            print("\(g.name)\t\(g.saved.formatted) / \(g.target.formatted)（\(g.percent)%）\(g.deadline.map { "\t目标日 \($0)" } ?? "")")
        }
    }
}

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "记一笔收支。负数是支出，正数是收入。")
    @OptionGroup var w: WriteOptions
    @Argument(help: "金额，如 -12,50（支出）或 300（收入）。") var amount: String
    @Argument(help: "说明，如「超市」。") var text: String
    @Option(help: "账户 id。") var account: String
    @Option(help: "账本 id。") var book: String
    @Option(help: "分类。") var category: String?
    @Option(help: "日期，默认今天。") var date: String?

    func run() throws {
        var ledger = try loadLedger()
        let tx = Transaction(date: try parseDate(date), amount: try parseMoney(amount), description: text,
                             accountID: account, bookID: book, category: category, source: "手记")
        let change = try ledger.addTransaction(tx, author: w.who)
        try saveLedger(ledger)
        try report(change, json: w.json)
    }
}

struct DebtCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "debt", abstract: "记欠款、记还款。",
                                                    subcommands: [DebtAdd.self, DebtRepay.self])

    struct DebtAdd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "记一笔欠款：别人欠我（--they-owe-me）或我欠别人（--i-owe）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "对方，如「阿华」。") var who: String
        @Argument(help: "金额，正数。") var amount: String
        @Flag(help: "我借出去的，对方欠我。") var theyOweMe = false
        @Flag(help: "我借来的，我欠对方。") var iOwe = false
        @Option(help: "账本 id。") var book: String = "personal"
        @Option(help: "钱从哪个账户出/进。很早的旧账没有对应流水就不填。") var account: String?
        @Option(help: "借的日期，默认今天。") var date: String?
        @Option(help: "约定哪天还。") var due: String?
        @Option(help: "备注。") var note: String?

        func validate() throws {
            guard theyOweMe != iOwe else { throw ValidationError("要写清方向：--they-owe-me 或 --i-owe，二选一") }
        }

        func run() throws {
            var ledger = try loadLedger()
            let (_, change) = try ledger.addDebt(counterparty: who, direction: theyOweMe ? .theyOweMe : .iOweThem,
                                                 amount: try parseMoney(amount).magnitude, bookID: book,
                                                 date: try parseDate(date), accountID: account,
                                                 dueDate: try due.map { try parseDate($0) }, note: note, author: w.who)
            try saveLedger(ledger)
            try report(change, json: w.json)
        }
    }

    struct DebtRepay: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "repay", abstract: "记一笔还款。对方名字只要能唯一对上一笔没结清的借款就行。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "对方，如「阿华」。") var who: String
        @Argument(help: "还了多少，正数。") var amount: String
        @Option(help: "钱进/出的账户 id。") var account: String
        @Option(help: "日期，默认今天。") var date: String?

        func run() throws {
            var ledger = try loadLedger()
            let matches = ledger.openDebts(named: who)
            guard matches.count == 1, let debt = matches.first else {
                throw ValidationError(matches.isEmpty ? "没找到和「\(who)」有关的没结清借款，先用 fin debts 看看"
                                                      : "「\(who)」对上了 \(matches.count) 笔借款，名字写完整一点")
            }
            let change = try ledger.repay(debtID: debt.id, amount: try parseMoney(amount).magnitude,
                                          date: try parseDate(date), accountID: account, author: w.who)
            try saveLedger(ledger)
            try report(change, json: w.json)
        }
    }
}

struct AccountCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "account", abstract: "管理账户。", subcommands: [AccountAdd.self])

    struct AccountAdd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "加一个账户。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "账户 id，如 revolut。") var id: String
        @Argument(help: "显示名，如「Revolut」。") var name: String
        @Option(help: "类型：bank、credit、cash、wallet、savings。") var kind: String = "bank"
        @Flag(help: "私房钱：app 默认不显示、不算进总览。") var `private` = false

        func run() throws {
            guard let k = AccountKind(rawValue: kind) else { throw ValidationError("类型只能是 bank、credit、cash、wallet、savings") }
            var ledger = try loadLedger()
            guard !ledger.accounts.contains(where: { $0.id == id }) else { throw ValidationError("已经有 \(id) 这个账户了") }
            let change = ledger.addAccount(Account(id: id, name: name, kind: k, isPrivate: `private`), author: w.who)
            try saveLedger(ledger)
            try report(change, json: w.json)
        }
    }
}

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "history", abstract: "改动记录：谁、什么时候、改了什么。")
    @Flag(name: .long, help: "输出 JSON。") var json = false
    @Option(help: "最多几条。") var limit: Int = 20

    func run() throws {
        let list = Array(try loadLedger().changes.suffix(limit).reversed())
        if json { return try Output.json(list) }
        if list.isEmpty { print("还没有改动。") }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        for c in list {
            print("\(c.id.uuidString.prefix(8))\t\(f.string(from: c.createdAt))\t\(c.author)\t\(c.summary)\(c.undone ? "\t（已撤销）" : "")")
        }
    }
}

struct UndoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "undo", abstract: "撤销一条改动。填 fin history 里的编号（前 8 位就行）。")
    @OptionGroup var w: WriteOptions
    @Argument(help: "改动编号。") var id: String

    func run() throws {
        var ledger = try loadLedger()
        let key = id.lowercased()
        let hits = ledger.changes.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
        guard hits.count == 1, let target = hits.first else {
            throw ValidationError(hits.isEmpty ? "没有编号是 \(id) 的改动" : "编号 \(id) 对上了好几条，多写几位")
        }
        let change = try ledger.undo(changeID: target.id, author: w.who)
        try saveLedger(ledger)
        try report(change, json: w.json)
    }
}
