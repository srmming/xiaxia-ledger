import ArgumentParser
import FinanceCore
import Foundation

struct EditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "edit", abstract: "改一笔流水：金额、说明、日期、账户、账本、分类。只写要改的那几项。")
    @OptionGroup var w: WriteOptions
    @Argument(help: "流水编号（fin tx 里的 8 位）。") var id: String
    @Option(help: "新金额，如 -12,50（支出）或 300（收入）。写成 --amount=-12,50。") var amount: String?
    @Option(help: "新说明。") var text: String?
    @Option(help: "新日期，如 2026-11-21。") var date: String?
    @Option(help: "换到哪个账户（id）。") var account: String?
    @Option(help: "换到哪个账本（id）。") var book: String?
    @Option(help: "新分类。") var category: String?

    func run() throws {
        var ledger = try loadLedger()
        var t = try ledger.findTransactions([id])[0]
        guard t.flow == nil, !t.isTransfer else {
            throw ValidationError("这笔是转账、借款、分期或目标的一部分，不能直接改。先 fin undo 撤销原来那条改动，再重新记。")
        }
        guard amount != nil || text != nil || date != nil || account != nil || book != nil || category != nil else {
            throw ValidationError("没写要改什么。比如：fin edit \(id) --amount=-12,50")
        }
        if let amount { t.amount = try parseMoney(amount) }
        if let text { t.description = text }
        if let date { t.date = try parseDate(date) }
        if let account { t.accountID = account }
        if let book { t.bookID = book }
        if let category { t.category = category }
        let change = try ledger.editTransaction(t, author: w.who)
        try finish(ledger, change, w)
    }
}

struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rm", abstract: "删流水（能用 fin undo 放回来）。先 --dry-run 给用户 看要删哪几笔。")
    @OptionGroup var w: WriteOptions
    @Argument(help: "流水编号，可以一次写多个。") var ids: [String]

    func run() throws {
        var ledger = try loadLedger()
        let txs = try ledger.findTransactions(ids)
        if w.dryRun && !w.json {
            for t in txs { print("会删：\(t.date)  \(t.amount.formatted)  \(t.description)") }
        }
        let change = try ledger.removeTransactions(txs.map(\.id), author: w.who)
        try finish(ledger, change, w)
    }
}

struct ReconcileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reconcile", abstract: "对账：拿银行某一天的余额和账本比，差多少、可能差在哪几笔。只看不改。")
    @Flag(name: .long, help: "输出 JSON。") var json = false
    @Option(help: "账户 id。") var account: String
    @Option(help: "银行那边的余额，如 382,64。负数写成 --balance=-100。") var balance: String
    @Option(help: "这个余额是哪天的，默认今天。") var date: String?

    func run() throws {
        let r = try Reconcile.check(try loadLedger(), accountID: account, statementBalance: try parseMoney(balance), asOf: try parseDate(date))
        if json { return try Output.json(r) }
        print(Reconcile.text(r))
    }
}

struct ReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "report", abstract: "月报：这个月进多少、花多少、花在哪、和上个月比、要留意什么。直接能读。")
    @Option(help: "月份，如 2026-11。不填 = 这个月。") var month: String?
    @Option(help: "账本 id。不填 = 全部。") var book: String?
    @Flag(name: .long, help: "算上私房钱账户。只有 用户本人问时才用。") var includePrivate = false

    func run() throws {
        let ym: YearMonth
        if let month {
            guard let v = YearMonth(month) else { throw ValidationError("月份格式要像 2026-11") }
            ym = v
        } else { ym = LocalDate.today.yearMonth }
        let ledger = try loadLedger()
        if let book, !ledger.books.contains(where: { $0.id == book }) { throw ValidationError("没有这个账本：\(book)。用 fin books 看有哪些。") }
        print(MonthlyReport.text(ledger, month: ym, bookID: book, hiddenAccounts: includePrivate ? [] : ledger.privateAccountIDs))
    }
}
