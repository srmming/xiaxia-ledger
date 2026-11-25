import ArgumentParser
import FinanceCore
import Foundation

struct DemoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "demo",
        abstract: "生成一本示例账本（人、店、银行、商户、金额全是编的），给演示、截图、试用和开发自测用。不碰真实账本。",
        discussion: """
        例子：
          fin demo --out ~/Desktop/示例账本.sqlite
          XIAXIA_LEDGER_PATH=~/Desktop/示例账本.sqlite fin report
        只能写到新文件；要覆盖以前生成的示例账本加 --force。真实账本所在的位置一律不写。
        """)

    @Option(help: "写到哪个文件，.sqlite 结尾。") var out: String
    @Option(help: "示例账本里的「今天」，如 2026-11-20。不填 = 今天。流水从 12 个月前的 1 号到这天。") var end: String?
    @Option(help: "随机种子。同一个种子、同一个「今天」生成的账本一模一样。") var seed: UInt64 = DemoData.defaultSeed
    @Flag(help: "文件已经在了也覆盖（只肯覆盖以前生成的示例账本）。") var force = false
    @Flag(name: .long, help: "输出 JSON。") var json = false

    func run() throws {
        let url = URL(fileURLWithPath: (out as NSString).expandingTildeInPath).standardizedFileURL
        let ext = url.pathExtension.lowercased()
        guard ext == "sqlite" else { throw ValidationError("生意模式需要 SQLite 账本，请用 .sqlite 结尾的文件名") }
        let target = url.resolvingSymlinksInPath().path
        if LedgerStores.standardLocations.contains(where: { $0.resolvingSymlinksInPath().path == target }) {
            throw ValidationError("这里是真实账本的位置，不能写示例数据：\(url.path)")
        }
        let store = Self.store(url)
        var ledger = DemoData.make(endingOn: try parseDate(end), seed: seed)
        if FileManager.default.fileExists(atPath: url.path) {
            guard force else { throw ValidationError("文件已经在了：\(url.path)。要覆盖以前生成的示例账本，加 --force") }
            guard let old = try? store.load(), DemoData.isDemo(old) else {
                throw ValidationError("这个文件不是示例账本，不覆盖：\(url.path)")
            }
            ledger = ledger.replacingContents(of: old)
        }
        try store.save(ledger)

        let info = DemoInfo(ledger, path: url.path)
        if json { return try Output.json(info) }
        print("""
        已生成示例账本（全是编的）：\(info.path)
          时间：\(info.from) 到 \(info.to)，\(info.transactions) 笔流水
          账本：\(info.books.joined(separator: "、"))；账户 \(info.accounts) 个（含私房钱）
          借款 \(info.debts) 笔、分期 \(info.installments) 个、目标 \(info.goals) 个、夏夏建议 \(info.insights) 条、改动记录 \(info.changes) 条
        用它：XIAXIA_LEDGER_PATH="\(info.path)" fin report
        """)
    }

    static func store(_ url: URL) -> any LedgerStore {
        #if canImport(SQLite3)
        if url.pathExtension.lowercased() == "sqlite" { return SQLiteLedgerStore(url: url) }
        #endif
        return JSONFileLedgerStore(url: url)
    }
}

struct DemoInfo: Encodable {
    var path: String
    var from: String
    var to: String
    var transactions: Int
    var books: [String]
    var accounts: Int
    var debts: Int
    var installments: Int
    var goals: Int
    var insights: Int
    var changes: Int

    init(_ l: Ledger, path: String) {
        self.path = path
        from = l.transactions.map(\.date).min()?.description ?? ""
        to = l.transactions.map(\.date).max()?.description ?? ""
        transactions = l.transactions.count
        books = l.books.map(\.name)
        accounts = l.accounts.count
        debts = l.debts.count
        installments = l.installments.count
        goals = l.goals.count
        insights = l.insights.count
        changes = l.changes.count
    }
}
