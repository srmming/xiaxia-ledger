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
    case bank, credit, cash, wallet, savings
}

/// 账户：银行卡、信用卡、现金、Revolut……不固定属于某个账本（可能混用）。
public struct Account: Identifiable, Hashable, Codable, Sendable {
    public var id: String          // 如 "caixabank"、"imagin"、"revolut"、"cash"
    public var name: String
    public var kind: AccountKind
    public var institution: String?
    /// 私房钱：只有自己看。app 默认不显示、不算进总览；AI 给别人看的报表里也不提。
    public var isPrivate: Bool

    public init(id: String, name: String, kind: AccountKind, institution: String? = nil, isPrivate: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.institution = institution; self.isPrivate = isPrivate
    }

    enum CodingKeys: String, CodingKey { case id, name, kind, institution, isPrivate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(AccountKind.self, forKey: .kind)
        institution = try c.decodeIfPresent(String.self, forKey: .institution)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
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
    /// 不算收支的流水：借出 / 借入 / 还款（往来）、存进目标（储蓄）、开账时的期初余额、
    /// 自己账户之间转钱（互转：转去 Revolut 充值、还信用卡、主账户转 imagin）。nil = 普通收支。
    public var flow: Flow?

    public enum Flow: String, Codable, Sendable { case debt, saving, opening, `internal` }

    public init(id: UUID = UUID(), date: LocalDate, amount: Money, description: String,
                accountID: String, bookID: String? = nil, category: String? = nil,
                transferID: UUID? = nil, source: String? = nil, flow: Flow? = nil) {
        self.id = id; self.date = date; self.amount = amount; self.description = description
        self.accountID = accountID; self.bookID = bookID; self.category = category
        self.transferID = transferID; self.source = source; self.flow = flow
    }

    enum CodingKeys: String, CodingKey { case id, date, amount, description, accountID, bookID, category, transferID, source, flow }

    /// 自己写解码：flow 遇到不认识的值（比如更新版本写的）不让整本账打不开，当成普通收支读进来。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(LocalDate.self, forKey: .date)
        amount = try c.decode(Money.self, forKey: .amount)
        description = try c.decode(String.self, forKey: .description)
        accountID = try c.decode(String.self, forKey: .accountID)
        bookID = try c.decodeIfPresent(String.self, forKey: .bookID)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        transferID = try c.decodeIfPresent(UUID.self, forKey: .transferID)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        let raw = try c.decodeIfPresent(String.self, forKey: .flow)
        flow = raw.flatMap { Flow(rawValue: $0 == "move" ? "internal" : $0) }
    }

    public var isTransfer: Bool { transferID != nil }
    /// 是否计入收支统计。借款往来和存进目标的钱不算。
    public var countsAsIncomeOrExpense: Bool { flow == nil }
    public static let refundCategory = "退款"
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

    /// 本机时区的今天。
    public static var today: LocalDate {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return LocalDate(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1)
    }

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
    public enum Kind: String, Codable, Sendable { case add, edit, categorize, assignBook, transfer, importBatch, debt, repay, account, delete, installment, installmentPayment, goal, goalDeposit, remove, opening }

    public var id: UUID
    public var kind: Kind
    public var summary: String          // 一句话说明，如「导入 Revolut 11 月对账单 37 笔」
    public var transactionIDs: [UUID]
    public var author: String           // 谁改的：「ming」「Claude」「Codex」「DeepSeek」……
    public var createdAt: Date
    public var undone: Bool
    /// 记欠款的改动指向那笔借款，撤销时一起删。
    public var debtID: UUID?
    /// 建目标、存钱的改动指向那个目标，撤销时用。
    public var goalID: UUID?
    /// 建分期、记分期还款的改动指向那个分期，撤销时用。
    public var installmentID: UUID?
    /// 改分类、分账本、标转账这类「改已有流水」的改动：改之前的样子。撤销时换回去。
    public var previous: [Transaction]?
    /// 改或删账户、账本、借款、分期、目标的改动：改之前的样子。撤销时放回去。
    public var before: PlanSnapshot?

    /// 这条改动能不能撤销（「撤销」本身不能再撤销）。
    public var canUndo: Bool {
        !undone && kind != .delete
            && (!transactionIDs.isEmpty || debtID != nil || goalID != nil || installmentID != nil || before != nil)
    }

    public init(id: UUID = UUID(), kind: Kind, summary: String, transactionIDs: [UUID],
                author: String, createdAt: Date = Date(), undone: Bool = false) {
        self.id = id; self.kind = kind; self.summary = summary; self.transactionIDs = transactionIDs
        self.author = author; self.createdAt = createdAt; self.undone = undone
    }
}

/// 账户、账本、借款、分期、目标在某次改动之前的样子，只存被动到的那几个。
public struct PlanSnapshot: Hashable, Codable, Sendable {
    public var accounts: [Account]?
    public var books: [Book]?
    public var debts: [Debt]?
    public var installments: [Installment]?
    public var goals: [Goal]?
    /// AI 意见改之前的样子（被替换的点评、点「知道了」之前的那条）。
    public var insights: [Insight]?
    /// 这次改动新写的意见：撤销时删掉。
    public var addedInsightIDs: [UUID]?
    /// 这次改动新加的账户、账本：撤销时删掉。
    public var addedAccountIDs: [String]?
    public var addedBookIDs: [String]?

    public init(accounts: [Account]? = nil, books: [Book]? = nil, debts: [Debt]? = nil,
                installments: [Installment]? = nil, goals: [Goal]? = nil,
                addedAccountIDs: [String]? = nil, addedBookIDs: [String]? = nil) {
        self.accounts = accounts; self.books = books; self.debts = debts
        self.installments = installments; self.goals = goals
        self.addedAccountIDs = addedAccountIDs; self.addedBookIDs = addedBookIDs
    }
}

/// 整份账本数据。
public struct Ledger: Codable, Sendable, Equatable {
    public var schemaVersion: Int = 1
    public var books: [Book] = []
    public var accounts: [Account] = []
    public var transactions: [Transaction] = []
    public var changes: [ChangeRecord] = []
    public var debts: [Debt] = []
    public var installments: [Installment] = []
    public var goals: [Goal] = []
    /// AI 写进来的意见（本月点评、提醒）。
    public var insights: [Insight] = []
    /// 上次导入/对账截止到哪天，按账户记。
    public var lastStatementDate: [String: LocalDate] = [:]

    public init(books: [Book] = [], accounts: [Account] = [], transactions: [Transaction] = [],
                changes: [ChangeRecord] = []) {
        self.books = books; self.accounts = accounts; self.transactions = transactions; self.changes = changes
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, books, accounts, transactions, changes, lastStatementDate, debts, installments, goals, insights
    }

    /// 字段缺了就用默认值，旧版本的账本文件也能读。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        books = try c.decodeIfPresent([Book].self, forKey: .books) ?? []
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        transactions = try c.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        changes = try c.decodeIfPresent([ChangeRecord].self, forKey: .changes) ?? []
        lastStatementDate = try c.decodeIfPresent([String: LocalDate].self, forKey: .lastStatementDate) ?? [:]
        debts = try c.decodeIfPresent([Debt].self, forKey: .debts) ?? []
        installments = try c.decodeIfPresent([Installment].self, forKey: .installments) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        insights = try c.decodeIfPresent([Insight].self, forKey: .insights) ?? []
    }

    /// 新建账本时的默认结构：两个账本，没有任何流水。
    public static var starter: Ledger {
        Ledger(books: [Book(id: "personal", name: "个人"), Book(id: "miora", name: "Miora 美甲店")])
    }
}
