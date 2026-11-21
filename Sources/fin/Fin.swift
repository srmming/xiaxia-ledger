import ArgumentParser
import FinanceCore
import Foundation

@main
struct Fin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fin",
        abstract: "夏夏账本命令行：给 AI 和人查看、整理财务。",
        discussion: "数据位置默认 ~/Library/Application Support/XiaxiaLedger/ledger.json，可用 XIAXIA_LEDGER_PATH 覆盖。",
        subcommands: [ContextCommand.self, BooksCommand.self, AccountsCommand.self, TxCommand.self, SummaryCommand.self, DebtsCommand.self, InstallmentsCommand.self, GoalsCommand.self]
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
