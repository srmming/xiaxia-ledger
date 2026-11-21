import Foundation

/// 账本：个人、Miora 美甲店……每个账本有自己的分类和报表。
public struct Book: Identifiable, Hashable, Codable, Sendable {
    public var id: String          // 短 id，如 "personal"、"miora"
    public var name: String        // 显示名，如「个人」
    public var currency: String

    public init(id: String, name: String, currency: String = "EUR") {
        self.id = id; self.name = name; self.currency = currency
    }
}

public enum AccountKind: String, Codable, Sendable, CaseIterable {
    case bank, credit, cash, wallet
}

/// 账户：银行卡、信用卡、现金、Revolut……不固定属于某个账本（可能混用）。
public struct Account: Identifiable, Hashable, Codable, Sendable {
    public var id: String          // 如 "caixabank"、"imagin"、"revolut"、"cash"
    public var name: String
    public var kind: AccountKind
    public var institution: String?

    public init(id: String, name: String, kind: AccountKind, institution: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.institution = institution
    }
}

/// 一笔流水。每一笔单独决定属于哪个账本。
public struct Transaction: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var date: LocalDate
    public var amount: Money
    public var description: String
    public var accountID: String
    public var bookID: String?     // nil = 还没分账本
    public var category: String?
    /// 账本间转账（如店里取钱给个人）：两边各一笔，用同一个 transferID 关联，汇总「全部」时互相抵消。
    public var transferID: UUID?
    /// 来源：导入文件名或「手记」，方便追溯。
    public var source: String?

    public init(id: UUID = UUID(), date: LocalDate, amount: Money, description: String,
                accountID: String, bookID: String? = nil, category: String? = nil,
                transferID: UUID? = nil, source: String? = nil) {
        self.id = id; self.date = date; self.amount = amount; self.description = description
        self.accountID = accountID; self.bookID = bookID; self.category = category
        self.transferID = transferID; self.source = source
    }

    public var isTransfer: Bool { transferID != nil }
}

/// 不带时区的日期（对账单只有日期）。格式 yyyy-MM-dd。
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

    public init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var yearMonth: YearMonth { YearMonth(year: year, month: month) }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = LocalDate(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

public struct YearMonth: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public init(year: Int, month: Int) { self.year = year; self.month = month }
    public init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return nil }
        self.init(year: parts[0], month: parts[1])
    }
    public var description: String { String(format: "%04d-%02d", year, month) }
    public static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
}

/// 改动记录：每次写入（导入、记一笔、改分类、分账本、转账）记一条，写明是谁改的，能撤销。
/// 不设「待确认」队列：要确认的事，AI 在对话里先和 ming 说清楚，确认后再写。
public struct ChangeRecord: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case add, edit, categorize, assignBook, transfer, importBatch }

    public var id: UUID
    public var kind: Kind
    public var summary: String          // 一句话说明，如「导入 Revolut 11 月对账单 37 笔」
    public var transactionIDs: [UUID]
    public var author: String           // 谁改的：「ming」「Claude」「Codex」「DeepSeek」……
    public var createdAt: Date
    public var undone: Bool

    public init(id: UUID = UUID(), kind: Kind, summary: String, transactionIDs: [UUID],
                author: String, createdAt: Date = Date(), undone: Bool = false) {
        self.id = id; self.kind = kind; self.summary = summary; self.transactionIDs = transactionIDs
        self.author = author; self.createdAt = createdAt; self.undone = undone
    }
}

/// 整份账本数据。
public struct Ledger: Codable, Sendable, Equatable {
    public var schemaVersion: Int = 1
    public var books: [Book] = []
    public var accounts: [Account] = []
    public var transactions: [Transaction] = []
    public var changes: [ChangeRecord] = []
    /// 上次导入/对账截止到哪天，按账户记。
    public var lastStatementDate: [String: LocalDate] = [:]

    public init(books: [Book] = [], accounts: [Account] = [], transactions: [Transaction] = [],
                changes: [ChangeRecord] = []) {
        self.books = books; self.accounts = accounts; self.transactions = transactions; self.changes = changes
    }

    /// 新建账本时的默认结构：两个账本，没有任何流水。
    public static var starter: Ledger {
        Ledger(books: [Book(id: "personal", name: "个人"), Book(id: "miora", name: "Miora 美甲店")])
    }
}
