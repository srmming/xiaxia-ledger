import Foundation

/// 「说明书」：给 AI 一次读懂财务背景。`fin context` 输出的就是它。
public struct LedgerContext: Codable, Sendable {
    public struct BookInfo: Codable, Sendable { public var id: String; public var name: String; public var transactions: Int }
    public struct AccountInfo: Codable, Sendable {
        public var id: String; public var name: String; public var kind: String
        public var balance: String; public var lastStatementDate: String?
    }

    public var books: [BookInfo]
    public var accounts: [AccountInfo]
    public var transactionCount: Int
    public var firstDate: String?
    public var lastDate: String?
    public var recentChanges: [String]
    public var unassignedCount: Int
    public var rules: [String]

    public static let rules: [String] = [
        "金额：正数是收入，负数是支出；显示用西班牙格式 1.234,56 €。",
        "每笔流水单独归一个账本；账户（银行卡、现金等）不固定属于某个账本。",
        "账本间转账两边各记一笔、共用 transferID；单个账本照常统计，「全部」汇总时抵消。",
        "去重：同账户 + 同日期 + 同金额 + 描述归一化后相同 = 同一笔。",
        "拿不准的事（属于哪个账本、怎么分类）先在对话里问 ming，确认后再写；不要猜着写。",
        "每次写入都记进改动记录（谁改的、改了什么），可以用 fin undo 撤销。",
        "不动钱、不碰银行密码；银行数据只读。",
    ]

    public init(ledger: Ledger) {
        let balances = Summaries.balances(ledger.transactions)
        books = ledger.books.map { b in
            BookInfo(id: b.id, name: b.name, transactions: ledger.transactions.filter { $0.bookID == b.id }.count)
        }
        accounts = ledger.accounts.map { a in
            AccountInfo(id: a.id, name: a.name, kind: a.kind.rawValue,
                        balance: (balances[a.id] ?? .zero).formatted,
                        lastStatementDate: ledger.lastStatementDate[a.id]?.description)
        }
        transactionCount = ledger.transactions.count
        let dates = ledger.transactions.map(\.date).sorted()
        firstDate = dates.first?.description
        lastDate = dates.last?.description
        recentChanges = ledger.changes.filter { !$0.undone }.suffix(5).reversed().map { "\($0.author)：\($0.summary)" }
        unassignedCount = ledger.transactions.filter { $0.bookID == nil }.count
        rules = Self.rules
    }
}
