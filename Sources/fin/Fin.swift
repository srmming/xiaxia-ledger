import ArgumentParser
import FinanceCore
import Foundation

@main
struct Fin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fin",
        abstract: "夏夏账本命令行：给 AI 和人查看、整理财务。",
        discussion: "账本在哪：跑 fin where。一般在 iCloud 云盘「夏夏账本/ledger.sqlite」；签名正式版搬家后在 app 的 iCloud 容器里；没开 iCloud 云盘就在 ~/Library/Application Support/XiaxiaLedger/。可用 XIAXIA_LEDGER_PATH 覆盖（.json 结尾用 JSON 文件）。",
        subcommands: [ContextCommand.self, WhereCommand.self, BooksCommand.self, BookCommand.self, AccountsCommand.self, TxCommand.self, SummaryCommand.self, DebtsCommand.self, InstallmentsCommand.self, GoalsCommand.self,
                      AddCommand.self, DebtCommand.self, AccountCommand.self, ImportCommand.self, FXCommand.self, SubscriptionsCommand.self, SubscriptionCommand.self, CategorizeCommand.self,
                      AssignCommand.self, EditCommand.self, RemoveCommand.self, ReconcileCommand.self, ReportCommand.self, TransferCommand.self, InstallmentCommand.self, GoalCommand.self, HistoryCommand.self, UndoCommand.self, InsightCommand.self, SplitCommand.self, CopyCommand.self, RefundCommand.self, TagCommand.self, RepeatCommand.self, MCPCommand.self, ConnectCommand.self, SetupCommand.self, DemoCommand.self, MemoryCommand.self, RegularsCommand.self]
    )

    /// 负数金额（-12,50）会被当成选项，报「缺少参数」。这里先把开头的减号换成全角减号「−」，金额解析认得它。
    static func main() {
        let args = CommandLine.arguments.dropFirst().map { a -> String in
            a.range(of: #"^-\d"#, options: .regularExpression) != nil ? "\u{2212}" + a.dropFirst() : a
        }
        Self.main(Array(args))
    }
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "输出 JSON，方便 AI 读。")
    var json = false

    @Option(name: .long, help: "账本 id，如 personal（fin books 能看到全部）。不填 = 全部。")
    var book: String?

    @Flag(name: .long, help: "算上私房钱账户。默认不显示、不算进汇总，只有 用户本人问时才用。")
    var includePrivate = false
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

func loadLedger() throws -> Ledger { try LedgerStores.defaultStore().load() }
func saveLedger(_ ledger: Ledger) throws { try LedgerStores.defaultStore().save(ledger) }

/// 写入类命令共用：谁在改、日期、金额。
struct WriteOptions: ParsableArguments {
    @Option(help: "谁在改：你的名字、Claude、Codex、DeepSeek……不填就读环境变量 XIAXIA_AUTHOR，再没有就是「AI」。")
    var author: String?
    @Flag(name: .long, help: "输出 JSON。") var json = false
    @Flag(name: .long, help: "预演：显示会改什么，但不写进账本。拿不准时先预演给用户 看。") var dryRun = false

    var who: String { author ?? ProcessInfo.processInfo.environment["XIAXIA_AUTHOR"] ?? "AI" }
}

func parseMoney(_ s: String) throws -> Money {
    guard let m = Money(parsing: s) else { throw ValidationError("金额看不懂：\(s)，写成 12,50 或 12.50") }
    return m
}

/// 金额，也认算式：「12,50+3,20」。
func parseAmount(_ s: String) throws -> Money {
    guard let m = Money.evaluate(s) else { throw ValidationError("金额看不懂：\(s)，写成 12,50、12.50 或 12,50+3,20") }
    return m
}

func parseDate(_ s: String?) throws -> LocalDate {
    guard let s else { return .today }
    guard let d = LocalDate(s) else { throw ValidationError("日期格式要像 2026-11-21") }
    return d
}

/// 写入命令的收尾：预演就只显示，不保存。
func finish(_ ledger: Ledger, _ change: ChangeRecord, _ w: WriteOptions) throws {
    if w.dryRun {
        if w.json { return try Output.json(change) }
        print("预演（没有写入）：\(change.summary)")
        return
    }
    try saveLedger(ledger)
    try report(change, json: w.json)
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

struct BookCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "book", abstract: "管理账本：新建、改名、删除。",
                                                    subcommands: [Add.self, Rename.self, Remove.self])

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "新建一个账本。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "账本名字，如「家庭」。") var name: String
        @Option(help: "personal（生活）或 business（生意）。") var kind: String = "personal"
        func run() throws {
            guard let k = BookKind(rawValue: kind) else { throw ValidationError("kind 只能是 personal 或 business") }
            var ledger = try loadLedger()
            let change = try ledger.addBook(name: name, kind: k, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rename", abstract: "给账本改名。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "账本 id。") var book: String
        @Argument(help: "新名字。") var name: String
        func run() throws {
            var ledger = try loadLedger()
            let change = try ledger.renameBook(book, to: name, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "删账本。里面有东西时要用 --move-to 指定挪到哪个账本。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "账本 id。") var book: String
        @Option(help: "里面的流水、借款、分期、目标挪到哪个账本。") var moveTo: String?
        func run() throws {
            var ledger = try loadLedger()
            let change = try ledger.removeBook(book, moveTo: moveTo, author: w.who)
            try finish(ledger, change, w)
        }
    }
}

struct AccountsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "accounts", abstract: "列出账户和余额。")
    @OptionGroup var options: GlobalOptions
    func run() throws {
        let ledger = try loadLedger()
        let balances = ledger.accountBalances()
        if options.json {
            struct Row: Encodable { var account: Account; var currency: String; var balance: String; var balanceInBase: String }
            return try Output.json(ledger.accounts.map { Row(account: $0, currency: ledger.currency(ofAccount: $0.id),
                                                               balance: (balances[$0.id]?.native ?? .zero).decimalString,
                                                               balanceInBase: (balances[$0.id]?.base ?? .zero).decimalString) })
        }
        for a in ledger.accounts {
            let code = ledger.currency(ofAccount: a.id)
            let b = balances[a.id] ?? (.zero, .zero)
            let approx = code == ledger.baseCurrency ? "" : "（约 \(b.base.formatted(in: ledger.baseCurrency))）"
            print("\(a.id)\t\(a.name)\(a.isPrivate ? "（私房钱）" : "")\t\(b.native.formatted(in: code))\(approx)")
        }
    }
}

struct TxCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tx", abstract: "查流水。")
    @OptionGroup var options: GlobalOptions
    @Option(help: "账户 id。") var account: String?
    @Option(help: "月份，如 2026-11。") var month: String?
    @Option(help: "分类。") var category: String?
    @Option(help: "搜索：说明、商户、备注、标签、金额都搜。以 # 开头只按标签找。") var query: String?
    @Option(help: "只看带这个标签的。") var tag: String?
    @Option(help: "expense 只看支出，income 只看收入。") var kind: String?
    @Option(help: "最多显示几条。") var limit: Int = 50

    func run() throws {
        let ym: YearMonth?
        if let month {
            guard let parsed = YearMonth(month) else { throw ValidationError("月份格式要像 2026-11") }
            ym = parsed
        } else { ym = nil }
        let ledger = try loadLedger()
        let hidden = options.includePrivate ? [] : ledger.privateAccountIDs
        let tagQuery: String? = tag.map { "#" + Tags.clean([$0]).joined() }
        let extra: (Transaction) -> Bool = { (t: Transaction) -> Bool in
            if let query, !t.matches(query) { return false }
            if let tagQuery, !t.matches(tagQuery) { return false }
            if let kind { return kind == "income" ? t.amount.isIncome : t.amount.isExpense }
            return true
        }
        let txs = ledger.transactions
            .filter { !hidden.contains($0.accountID) }
            .filter { options.book == nil || $0.bookID == options.book }
            .filter { account == nil || $0.accountID == account }
            .filter { ym == nil || $0.date.yearMonth == ym }
            .filter { category == nil || $0.category == category }
            .filter(extra)
            .sorted { $0.date > $1.date }
            .prefix(limit)
        if options.json { return try Output.json(Array(txs)) }
        if txs.isEmpty { print("没有符合条件的流水。") }
        for t in txs {
            let extra = (t.note.map { "（\($0)）" } ?? "") + t.tagList.map { " #\($0)" }.joined()
            print("\(t.id.uuidString.prefix(8).lowercased())\t\(t.date)\t\(ledger.formatted(t))\(t.original.map { "（原价 \($0.formatted)）" } ?? "")\t\(t.bookID ?? (t.flow != nil ? "—" : "未分"))\t\(t.category ?? "未分类")\t\(t.description)\(extra)")
        }
    }
}

struct SummaryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "summary", abstract: "收支和分类汇总：一个月、一整年，或一段时间。",
        discussion: """
        fin summary --month 2026-11
        fin summary --year 2026
        fin summary --from 2026-01 --to 2026-06
        """)
    @OptionGroup var options: GlobalOptions
    @Option(help: "月份，如 2026-11。") var month: String?
    @Option(help: "整年，如 2026。") var year: Int?
    @Option(help: "从哪个月开始，如 2026-01（和 --to 一起用）。") var from: String?
    @Option(help: "到哪个月为止，如 2026-06。") var to: String?

    func run() throws {
        let ledger = try loadLedger()
        let hidden = options.includePrivate ? [] : ledger.privateAccountIDs
        let months = try SummaryCommand.months(month: month, year: year, from: from, to: to)
        let list = Reports.summaries(ledger.baseTransactions, months: months, bookID: options.book, hiddenAccounts: hidden)
        if options.json {
            struct Row: Encodable { var month: String; var income: String; var expense: String; var net: String }
            struct Out: Encodable {
                var period: String; var book: String?; var income: String; var expense: String; var net: String
                var byCategory: [String: String]; var months: [Row]
            }
            let t = SummaryCommand.total(list)
            return try Output.json(Out(period: SummaryCommand.label(months), book: options.book, income: t.income.decimalString,
                                       expense: t.expense.decimalString, net: (t.income + t.expense).decimalString,
                                       byCategory: t.byCategory.mapValues(\.decimalString),
                                       months: list.map { Row(month: $0.month.description, income: $0.income.decimalString,
                                                              expense: $0.expense.decimalString, net: $0.net.decimalString) }))
        }
        print(SummaryCommand.text(list, months: months, book: options.book, ledger: ledger, hidden: hidden))
    }

    /// 把 --month / --year / --from --to 变成一串月份。
    static func months(month: String?, year: Int?, from: String?, to: String?) throws -> [YearMonth] {
        if let month {
            guard let ym = YearMonth(month) else { throw ValidationError("月份格式要像 2026-11") }
            return [ym]
        }
        if let year { return Reports.months(of: year) }
        if let from, let to {
            guard let a = YearMonth(from), let b = YearMonth(to), a <= b else { throw ValidationError("--from 和 --to 要写成 2026-01 这样，而且 from 不能晚于 to") }
            var out: [YearMonth] = [], m = a
            while m <= b, out.count < 120 { out.append(m); m = m.adding(months: 1) }
            return out
        }
        throw ValidationError("要看哪段时间？写 --month 2026-11、--year 2026，或 --from 2026-01 --to 2026-06")
    }

    static func label(_ months: [YearMonth]) -> String {
        guard let a = months.first, let b = months.last else { return "" }
        return a == b ? a.description : "\(a) 到 \(b)"
    }

    static func total(_ list: [MonthlySummary]) -> (income: Money, expense: Money, byCategory: [String: Money]) {
        var cats: [String: Money] = [:]
        for s in list { for (k, v) in s.byCategory { cats[k, default: .zero] = cats[k, default: .zero] + v } }
        return (list.reduce(Money.zero) { $0 + $1.income }, list.reduce(Money.zero) { $0 + $1.expense }, cats)
    }

    /// 给 fin summary 和 MCP 用：算好「从哪个账本拿的」那行的叫法，和只记了一边的互转。
    static func text(_ list: [MonthlySummary], months: [YearMonth], book: String?, ledger: Ledger, hidden: Set<String>) -> String {
        guard let book else { return text(list, months: months, book: nil) }
        let moved = list.reduce(Money.zero) { $0 + $1.betweenBooks }
        return text(list, months: months, book: book,
                    movedLabel: Reports.betweenBooksLabel(moved, bookID: book, books: ledger.books),
                    unmatched: Summaries.unmatchedInternal(ledger.transactions, months: months, hiddenAccounts: hidden))
    }

    static func text(_ list: [MonthlySummary], months: [YearMonth], book: String?, movedLabel: String? = nil,
                     unmatched: (count: Int, total: Money)? = nil) -> String {
        let t = total(list)
        var lines = ["\(label(months))  \(book ?? "全部")",
                     "收入 \(t.income.formatted)  支出 \(t.expense.formatted)  结余 \((t.income + t.expense).formatted)"]
        let moved = list.reduce(Money.zero) { $0 + $1.betweenBooks }
        if moved.cents != 0 {
            let word = movedLabel ?? (moved.cents > 0 ? "从别的账本拿的" : "拿去别的账本的")
            lines.append("\(word) \(moved.magnitude.formatted)（自己账户间转账，不算收支）  算上它结余 \((t.income + t.expense + moved).formatted)")
        }
        if let unmatched, unmatched.count > 0 {
            lines.append("另有 \(unmatched.count) 笔转账只记了一边（共 \(unmatched.total.formatted)），多半也是两个账本之间的，没算进上面这行")
        }
        if list.count > 1 {
            lines.append("按月：")
            for s in list where s.income.cents != 0 || s.expense.cents != 0 {
                lines.append("  \(s.month)\t收入 \(s.income.formatted)\t支出 \(s.expense.formatted)\t结余 \(s.net.formatted)")
            }
            lines.append("分类：")
        }
        lines += t.byCategory.sorted { $0.value < $1.value }.map { "  \($0.key)\t\($0.value.formatted)" }
        return lines.joined(separator: "\n")
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
    @Option(help: "备注。") var note: String?
    @Option(help: "标签，可以写几次：--tag 旅行 --tag 报销。") var tag: [String] = []
    @Option(help: "重复：weekly 每周、monthly 每月、yearly 每年。以后到日子自动记（app 打开时或 fin repeat run）。") var `repeat`: String?
    @Option(help: "重复到哪天为止（可不填）。") var until: String?
    @Option(help: "原价（用别的币种付的），如 \"50 USD\"。只做备注，金额以银行扣的为准。") var original: String?

    func run() throws {
        var ledger = try loadLedger()
        let d = try parseDate(date)
        var tx = Transaction(date: d, amount: try parseAmount(amount), description: text,
                             accountID: account, bookID: book, category: category, source: "手记",
                             note: note.flatMap { $0.isEmpty ? nil : $0 }, tags: Tags.clean(tag).isEmpty ? nil : Tags.clean(tag))
        tx.fx = ledger.fxNote(accountID: account, date: d)
        if let original { tx.original = try parseForeign(original, sign: tx.amount.cents < 0 ? -1 : 1) }
        let change: ChangeRecord
        if let r = `repeat` {
            guard let f = Recurring.Frequency(rawValue: r) else { throw ValidationError("--repeat 要写 weekly、monthly 或 yearly") }
            change = try ledger.addRecurring(tx, frequency: f, until: try until.map { try parseDate($0) }, author: w.who)
        } else {
            change = try ledger.addTransaction(tx, author: w.who)
        }
        try finish(ledger, change, w)
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
            try finish(ledger, change, w)
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
            try finish(ledger, change, w)
        }
    }
}

struct AccountCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "account", abstract: "管理账户。", subcommands: [AccountAdd.self, AccountOpening.self])

    struct AccountOpening: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "opening", abstract: "记开账余额：开始记账那天账户里已经有多少钱（不算收入）。已经记过就改成新的。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "账户 id。") var account: String
        @Argument(help: "余额。信用卡欠款写负数。") var amount: String
        @Option(help: "哪天的余额，默认今天。") var date: String?

        func run() throws {
            var ledger = try loadLedger()
            let change = try ledger.setOpeningBalance(accountID: account, amount: try parseMoney(amount), date: try parseDate(date), author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct AccountAdd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "加一个账户。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "账户 id，如 revolut。") var id: String
        @Argument(help: "显示名，如「Revolut」。") var name: String
        @Option(help: "类型：bank、credit、cash、wallet、savings。") var kind: String = "bank"
        @Flag(help: "私房钱：app 默认不显示、不算进总览。") var `private` = false
        @Option(help: "币种，三个字母，如 USD、CNY。不填 = 主币种。") var currency: String?

        func run() throws {
            guard let k = AccountKind(rawValue: kind) else { throw ValidationError("类型只能是 bank、credit、cash、wallet、savings") }
            var ledger = try loadLedger()
            guard !ledger.accounts.contains(where: { $0.id == id }) else { throw ValidationError("已经有 \(id) 这个账户了") }
            if let currency, !Currencies.isKnown(currency) { throw ValidationError(CurrencyError.unknownCurrency(currency).localizedDescription) }
            let code = currency?.uppercased()
            let change = ledger.addAccount(Account(id: id, name: name, kind: k, isPrivate: `private`,
                                                   currency: code == ledger.baseCurrency ? nil : code), author: w.who)
            try finish(ledger, change, w)
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
        try finish(ledger, change, w)
    }
}

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "导入对账单，自动去重。先加 --dry-run 看会导入什么，跟用户确认后再正式导入。",
        discussion: """
        Revolut：fin import 文件.csv --account revolut（自动认出 Revolut 格式）
        其他银行（CSV）：fin import 文件.csv --account caixa --date-col Fecha --amount-col Importe --desc-col Concepto
        收支分两列：用 --debit-col / --credit-col 代替 --amount-col。列名或列号（从 1 开始）都行。
        """)
    @OptionGroup var w: WriteOptions
    @Argument(help: "对账单文件（CSV）。") var file: String
    @Option(help: "导进哪个账户。") var account: String
    @Option(help: "格式：revolut 或 csv。不填就自己认（Revolut 的 CSV 认得出）。") var format: String?
    @Option(help: "通用 CSV：日期列。") var dateCol: String?
    @Option(help: "通用 CSV：金额列（正收入负支出）。") var amountCol: String?
    @Option(help: "通用 CSV：支出列。") var debitCol: String?
    @Option(help: "通用 CSV：收入列。") var creditCol: String?
    @Option(help: "通用 CSV：说明列。") var descCol: String?
    @Option(help: "通用 CSV：表头前要跳过几行。") var skipRows: Int = 0
    @Option(help: "通用 CSV（可选）：分类列。") var categoryCol: String?
    @Option(help: "通用 CSV（可选）：账本列，写账本 id，如 personal。") var bookCol: String?
    @Option(help: "通用 CSV（可选）：性质列，debt / saving / opening / internal（自己账户互转），空着是普通收支。") var flowCol: String?
    @Option(help: "这批默认归哪个账本（不填就先不分，之后用 fin assign）。") var book: String?
    func run() throws {
        let url = URL(fileURLWithPath: file)
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let source = url.lastPathComponent
        var result: ImportResult
        let kind = format ?? (ImportGuess.detect(text).format == .revolut ? "revolut" : "csv")
        switch kind {
        case "revolut": result = try Importers.revolutCSV(text, accountID: account, source: source)
        case "csv":
            guard let dateCol, let descCol else { throw ValidationError("通用 CSV 要写 --date-col 和 --desc-col") }
            result = try Importers.genericCSV(text, map: .init(date: dateCol, amount: amountCol, debit: debitCol, credit: creditCol,
                                                               description: descCol, skipRows: skipRows,
                                                               category: categoryCol, book: bookCol, flow: flowCol),
                                              accountID: account, source: source)
        default: throw ValidationError("格式只能是 revolut 或 csv")
        }
        if let book { result.transactions = result.transactions.map { var t = $0; if t.bookID == nil { t.bookID = book }; return t } }
        var ledger = try loadLedger()
        let unknownBooks = Set(result.transactions.compactMap(\.bookID)).subtracting(ledger.books.map(\.id))
        if !unknownBooks.isEmpty { throw ValidationError("没有这些账本：\(unknownBooks.sorted().joined(separator: "、"))") }
        if w.dryRun {
            let fresh = Dedup.newTransactions(result.transactions, existing: ledger.transactions)
            if w.json { return try Output.json(fresh) }
            print("读到 \(result.transactions.count) 笔，新的 \(fresh.count) 笔，重复 \(result.transactions.count - fresh.count) 笔（没有写入）")
            for t in fresh.prefix(30) { print("  \(t.date)\t\(t.amount.formatted)\t\(t.description)") }
            if fresh.count > 30 { print("  …还有 \(fresh.count - 30) 笔") }
            for s in result.skipped { print("  跳过：\(s)") }
            return
        }
        let (_, dupes, change) = try ledger.importTransactions(result.transactions, accountID: account, source: source, author: w.who)
        if let change { try finish(ledger, change, w) } else { print("没有新流水（\(dupes) 笔都已经有了）。") }
        for s in result.skipped { print("跳过：\(s)") }
    }
}

struct CategorizeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "categorize", abstract: "改分类。流水编号用 fin tx 里的 8 位。")
    @OptionGroup var w: WriteOptions
    @Option(help: "分类，如「餐饮」。") var category: String
    @Argument(help: "流水编号，可以一次写多个。") var ids: [String]

    func run() throws {
        var ledger = try loadLedger()
        let txs = try ledger.findTransactions(ids)
        let change = ledger.categorize(txs.map(\.id), category: category, author: w.who)
        try finish(ledger, change, w)
    }
}

struct AssignCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "assign", abstract: "分账本：这几笔属于个人还是店里。")
    @OptionGroup var w: WriteOptions
    @Option(help: "账本 id，如 personal（fin books 能看到全部）。") var book: String
    @Argument(help: "流水编号，可以一次写多个。") var ids: [String]

    func run() throws {
        var ledger = try loadLedger()
        let txs = try ledger.findTransactions(ids)
        let change = try ledger.assignBook(txs.map(\.id), bookID: book, author: w.who)
        try finish(ledger, change, w)
    }
}

struct TransferCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "transfer", abstract: "转账：账本之间（店里取钱给个人），或自己账户之间（取现、转到另一张卡，不算收支）。",
                                                    subcommands: [Link.self, New.self, Move.self, Mark.self])

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "move", abstract: "自己账户之间挪钱（取现、转到 Revolut、还信用卡）：两笔，不算收入也不算支出。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "金额，正数。") var amount: String
        @Option(name: .customLong("from-account"), help: "从哪个账户出。") var from: String
        @Option(name: .customLong("to-account"), help: "进哪个账户。") var to: String
        @Option(help: "日期，默认今天。") var date: String?
        @Option(help: "说明。") var note: String?

        func run() throws {
            var ledger = try loadLedger()
            let change = try ledger.addAccountTransfer(amount: try parseMoney(amount).magnitude, from: from, to: to,
                                                       date: try parseDate(date), note: note, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Mark: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mark", abstract: "把已导入的流水标成自己账户间转账，不再算收支（如对账单里的取现、转到 Revolut）。",
                                                        discussion: "注意：写了 --counter-account 会在那个账户新记一笔相反金额的流水（比如银行卡取现 -100，现金账户就多一笔 +100）。另一半已经导入过就不要写，改用 fin transfer link。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "流水编号（fin tx 里的 8 位），可以多个。") var ids: [String]
        @Option(name: .customLong("counter-account"), help: "在这个账户补上另一半（如取现补到 cash）。另一半已经导入过就不填。") var counter: String?

        func run() throws {
            var ledger = try loadLedger()
            let txs = try ledger.findTransactions(ids)
            let change = try ledger.markAsAccountTransfer(txs.map(\.id), counterAccount: counter, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "link", abstract: "把已有的一笔转出、一笔转入标成转账。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "转出那笔（支出）的编号。") var out: String
        @Argument(help: "转入那笔（收入）的编号。") var into: String

        func run() throws {
            var ledger = try loadLedger()
            let txs = try ledger.findTransactions([out, into])
            let change = try ledger.linkTransfer(out: txs[0].id, into: txs[1].id, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "new", abstract: "同一个账户里，钱从一个账本挪到另一个（如店里现金拿回家）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "金额，正数。") var amount: String
        @Option(help: "从哪个账本。") var from: String
        @Option(help: "到哪个账本。") var to: String
        @Option(help: "哪个账户。") var account: String
        @Option(help: "日期，默认今天。") var date: String?
        @Option(help: "说明。") var note: String?

        func run() throws {
            var ledger = try loadLedger()
            let change = try ledger.addTransfer(amount: try parseMoney(amount).magnitude, fromBook: from, toBook: to,
                                                accountID: account, date: try parseDate(date), note: note, author: w.who)
            try finish(ledger, change, w)
        }
    }
}

struct InstallmentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "installment", abstract: "记分期：买的那天算全额支出，之后每期是还债。",
                                                    subcommands: [Add.self, Pay.self])

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "建一个分期，同时记买的那天的全额支出。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "名称，如「美甲灯」。") var name: String
        @Argument(help: "总额（不含手续费）。") var total: String
        @Option(help: "共几期。") var count: Int
        @Option(help: "从哪个账户扣。") var account: String
        @Option(help: "账本 id。") var book: String
        @Option(help: "买的日期，默认今天。") var date: String?
        @Option(help: "第一期扣款日，默认买的日期下个月同一天。") var first: String?
        @Option(help: "分类，如「设备」。") var category: String?
        @Option(help: "手续费或利息（单独记一笔支出）。") var fee: String?

        func run() throws {
            var ledger = try loadLedger()
            let buy = try parseDate(date)
            let firstDate = try first.map { try parseDate($0) } ?? {
                let m = buy.month == 12 ? 1 : buy.month + 1
                return LocalDate(year: buy.month == 12 ? buy.year + 1 : buy.year, month: m, day: min(buy.day, 28))
            }()
            let (_, change) = try ledger.addInstallment(name: name, bookID: book, accountID: account, total: try parseMoney(total).magnitude,
                                                        count: count, purchaseDate: buy, firstPayment: firstDate, category: category,
                                                        fee: try fee.map { try parseMoney($0) }, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Pay: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "pay", abstract: "记一期还款；导入的银行扣款用 --tx 认领。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "分期名称（能唯一对上就行）。") var name: String
        @Option(help: "已导入的扣款流水编号；不填就新记一笔。") var tx: String?
        @Option(help: "金额，默认每期金额。") var amount: String?
        @Option(help: "日期，默认今天。") var date: String?

        func run() throws {
            var ledger = try loadLedger()
            let hits = ledger.findInstallments(named: name)
            guard hits.count == 1, let inst = hits.first else {
                throw ValidationError(hits.isEmpty ? "没有叫「\(name)」的分期" : "「\(name)」对上了 \(hits.count) 个分期")
            }
            let change: ChangeRecord
            if let tx {
                let t = try ledger.findTransactions([tx])[0]
                change = try ledger.linkInstallmentPayment(inst.id, transactionID: t.id, author: w.who)
            } else {
                change = try ledger.payInstallment(inst.id, amount: try amount.map { try parseMoney($0) }, date: try parseDate(date), author: w.who)
            }
            try finish(ledger, change, w)
        }
    }
}

struct GoalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "goal", abstract: "目标和储蓄：建目标、存钱、取钱。存取都不算收支。",
                                                    subcommands: [Add.self, Deposit.self, Withdraw.self])

    static func find(_ ledger: Ledger, _ name: String) throws -> Goal {
        let hits = ledger.findGoals(named: name)
        guard hits.count == 1 else { throw ValidationError(hits.isEmpty ? "没有叫「\(name)」的目标" : "「\(name)」对上了 \(hits.count) 个目标") }
        return hits[0]
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "建一个目标。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "名称，如「应急金」。") var name: String
        @Argument(help: "目标金额。") var target: String
        @Option(help: "账本 id。") var book: String = "personal"
        @Option(help: "截止日期。") var deadline: String?
        @Option(help: "专门的储蓄账户 id（如 Revolut 储蓄罐）；不填就在现有账户里划出。") var savingsAccount: String?
        @Flag(help: "锁定：存进去到期前不能取。") var locked = false

        func run() throws {
            var ledger = try loadLedger()
            let (_, change) = try ledger.addGoal(name: name, bookID: book, target: try parseMoney(target).magnitude,
                                                 deadline: try deadline.map { try parseDate($0) }, savingsAccountID: savingsAccount,
                                                 locked: locked, author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Deposit: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "deposit", abstract: "往目标里存钱。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "目标名称。") var name: String
        @Argument(help: "金额。") var amount: String
        @Option(help: "钱从哪个账户来。") var from: String
        @Option(help: "日期，默认今天。") var date: String?

        func run() throws {
            var ledger = try loadLedger()
            let g = try GoalCommand.find(ledger, name)
            let change = try ledger.deposit(goalID: g.id, amount: try parseMoney(amount).magnitude, fromAccount: from,
                                            date: try parseDate(date), author: w.who)
            try finish(ledger, change, w)
        }
    }

    struct Withdraw: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "withdraw", abstract: "从目标里取钱（锁定的不能取）。")
        @OptionGroup var w: WriteOptions
        @Argument(help: "目标名称。") var name: String
        @Argument(help: "金额。") var amount: String
        @Option(help: "取到哪个账户。") var to: String
        @Option(help: "日期，默认今天。") var date: String?

        func run() throws {
            var ledger = try loadLedger()
            let g = try GoalCommand.find(ledger, name)
            let change = try ledger.withdraw(goalID: g.id, amount: try parseMoney(amount).magnitude, toAccount: to,
                                             date: try parseDate(date), author: w.who)
            try finish(ledger, change, w)
        }
    }
}

struct WhereCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "where", abstract: "账本文件在哪（fin、MCP 和 app 读的是这一份）。")
    func run() throws { print(ledgerLocation(LedgerStores.defaultStore())) }
}
