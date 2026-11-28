import Foundation

public enum Side: String, Codable, Sendable {
    case life, business
    public init(from decoder: Decoder) throws {
        self = Side(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .life
    }
}

public struct Capital: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable {
        public var name: String
        public var amount: Money
        public var txIDs: [UUID]?
        public init(name: String, amount: Money, txIDs: [UUID]? = nil) {
            self.name = name; self.amount = amount; self.txIDs = txIDs
        }
    }
    public var total: Money
    public init(items: [Item], openedOn: LocalDate? = nil, recoveredBefore: Money = .zero) {
        self.init(total: items.reduce(.zero) { $0 + $1.amount }, openedOn: openedOn, recoveredBefore: recoveredBefore, items: items)
    }
    public var openedOn: LocalDate?
    public var recoveredBefore: Money
    public var items: [Item]
    public init(total: Money, openedOn: LocalDate? = nil, recoveredBefore: Money = .zero, items: [Item] = []) {
        self.total = total; self.openedOn = openedOn; self.recoveredBefore = recoveredBefore; self.items = items
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(total: try c.decode(Money.self, forKey: .total), openedOn: try c.decodeIfPresent(LocalDate.self, forKey: .openedOn),
                  recoveredBefore: try c.decodeIfPresent(Money.self, forKey: .recoveredBefore) ?? .zero,
                  items: try c.decodeIfPresent([Item].self, forKey: .items) ?? [])
    }
}

public struct BusinessSettings: Codable, Hashable, Sendable {
    public struct DebtExtra: Codable, Hashable, Sendable {
        public var kind: String
        public var annualRate: Decimal?
        public init(kind: String, annualRate: Decimal? = nil) { self.kind = kind; self.annualRate = annualRate }
    }
    public var enabled = false
    public var startSide: Side?
    public var businessBookID: String?
    public var capital: Capital?
    public var debtExtras: [String: DebtExtra]?
    /// 账户算哪一边（ming 2026-11-25：在哪边加就属哪边，可以挪边）。没写的按流水猜（只在生意账本里用的算生意）。
    public var accountSides: [String: Side]?
    /// 每天记账的收款方式（现金、刷卡之外还能加 Bizum、外卖平台……）。没设过就用默认两种。
    public var paymentMethods: [PaymentMethod]?
    /// 休息的日子（店那天没开门）。回本、不亏线、开门天数都按它算。老账本没有这个字段，就是一天都没标过。
    public var restDays: [LocalDate]?
    /// 估的货值：哪天估的、店里的货大概值多少。新的在后。老账本没有这个字段。
    public var stockEstimates: [StockEstimate]?
    /// 管哪边（只生活 / 只生意 / 都管）。没选过就是 nil：生意模式开着算两边都管。老账本没有这个字段。
    public var manages: ManagedSides?
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        startSide = try c.decodeIfPresent(Side.self, forKey: .startSide)
        businessBookID = try c.decodeIfPresent(String.self, forKey: .businessBookID)
        capital = try c.decodeIfPresent(Capital.self, forKey: .capital)
        debtExtras = try c.decodeIfPresent([String: DebtExtra].self, forKey: .debtExtras)
        accountSides = try c.decodeIfPresent([String: Side].self, forKey: .accountSides)
        paymentMethods = try c.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods)
        restDays = try c.decodeIfPresent([LocalDate].self, forKey: .restDays)
        stockEstimates = try c.decodeIfPresent([StockEstimate].self, forKey: .stockEstimates)
        manages = (try? c.decodeIfPresent(String.self, forKey: .manages)).flatMap { $0 }.flatMap(ManagedSides.init(rawValue:))
    }
}
/// 估一次货值：店里还没卖掉的货大概值多少。
public struct StockEstimate: Codable, Hashable, Sendable {
    public var date: LocalDate
    public var value: Money
    public var note: String?
    public init(date: LocalDate, value: Money, note: String? = nil) { self.date = date; self.value = value; self.note = note }
}
public struct Receivable: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var amount: Money
    public init(id: UUID = UUID(), name: String, amount: Money) { self.id = id; self.name = name; self.amount = amount }
}
public enum EnableResult { case enabled(ChangeRecord), needsChoice([Book]) }
public struct BusinessError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
extension Ledger {
    public var businessBook: Book? { books.first { $0.isBusiness && $0.id == business?.businessBookID } }
    public var lifeBookIDs: [String] { books.filter { !$0.isBusiness }.map(\.id) }
    public func side(of tx: Transaction) -> Side { tx.bookID != nil && tx.bookID == businessBook?.id ? .business : .life }
    public func bookID(for side: Side) -> String? {
        if side == .business { return businessBook?.id }
        let ids = Set(lifeBookIDs)
        return transactions.reversed().compactMap(\.bookID).first(where: ids.contains) ?? lifeBookIDs.first
    }
    private mutating func changeBusiness(_ settings: BusinessSettings, added: [String] = [], summary: String, author: String) -> ChangeRecord {
        var snapshot = PlanSnapshot(addedBookIDs: added)
        snapshot.changedBusiness = true
        snapshot.business = business
        let change = snapshotChange(.edit, summary, before: snapshot, author: author)
        business = settings
        minReaderVersion = max(minReaderVersion, 2)
        changes.append(change)
        return change
    }
    /// 给同一个模块里别的文件用：改生意设置并记一条能撤销的改动。
    mutating func changeBusinessSettings(_ settings: BusinessSettings, summary: String, author: String) -> ChangeRecord {
        changeBusiness(settings, summary: summary, author: author)
    }
    public mutating func enableBusinessMode(choose bookID: String? = nil, newBookName: String = "我的生意", author: String) throws -> EnableResult {
        var settings = business ?? BusinessSettings()
        let candidates = books.filter(\.isBusiness)
        var added: [String] = []
        if settings.capital != nil, let bound = settings.businessBookID,
           (bookID != nil && bookID != bound || !candidates.contains(where: { $0.id == bound })) {
            throw BusinessError(message: "换生意账本前，请先清掉原账本的本钱")
        }
        if let id = bookID {
            guard candidates.contains(where: { $0.id == id }) else { throw BusinessError(message: "请选择生意账本") }
            settings.businessBookID = id
        } else if let selected = businessBook ?? (candidates.count == 1 ? candidates.first : nil) {
            settings.businessBookID = selected.id
        } else if candidates.isEmpty {
            guard !newBookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ManageError.emptyName }
            let id = books.contains { $0.id == "business" } ? UUID().uuidString : "business"
            books.append(Book(id: id, name: newBookName, currency: currency.base, kind: .business))
            settings.businessBookID = id; added.append(id)
        } else { return .needsChoice(candidates) }
        settings.enabled = true
        return .enabled(changeBusiness(settings, added: added, summary: "打开生意模式", author: author))
    }
    public mutating func disableBusinessMode(author: String) -> ChangeRecord {
        var settings = business ?? BusinessSettings()
        settings.enabled = false
        return changeBusiness(settings, summary: "关闭生意模式", author: author)
    }
    public mutating func setCapital(_ capital: Capital, author: String) throws -> ChangeRecord {
        guard var settings = business, businessBook != nil, capital.total > .zero, capital.recoveredBefore >= .zero,
              capital.items.allSatisfy({ $0.amount >= .zero }) else { throw BusinessError(message: "请选择生意账本并填写有效本钱") }
        settings.capital = capital
        return changeBusiness(settings, summary: "设置生意本钱", author: author)
    }
    public mutating func startWithBusiness(capital: Money?, author: String) throws -> ChangeRecord {
        guard transactions.isEmpty, business == nil, books.allSatisfy({ !$0.isBusiness }), capital.map({ $0 > .zero }) ?? true else {
            throw BusinessError(message: "请在新账本中设置开店本钱")
        }
        var added: [String] = []
        if books.isEmpty { books = Ledger.fresh.books; added += lifeBookIDs }
        let id = books.contains { $0.id == "business" } ? UUID().uuidString : "business"
        books.append(Book(id: id, name: "我的生意", currency: currency.base, kind: .business))
        var settings = BusinessSettings()
        settings.enabled = true; settings.startSide = .business; settings.businessBookID = id
        settings.capital = capital.map { Capital(total: $0) }
        return changeBusiness(settings, added: added + [id], summary: "从生意开始记账", author: author)
    }
    public mutating func moveToSide(_ txID: UUID, side: Side, author: String = "夏夏") throws -> ChangeRecord {
        guard let id = bookID(for: side) else { throw BusinessError(message: "请先选择账本") }
        return try assignBook([txID], bookID: id, author: author)
    }
}

extension Ledger {
    func checkBusinessVersion() throws {
        guard minReaderVersion <= 2 else { throw BusinessError(message: "账本是新版夏夏写的，请先升级") }
    }
    func versionForSave(stored: Int) throws -> Int {
        try checkBusinessVersion()
        guard stored <= 2 else { throw BusinessError(message: "账本是新版夏夏写的，请先升级") }
        return max(stored, minReaderVersion, business != nil || !receivables.isEmpty ? 2 : 1)
    }
}
