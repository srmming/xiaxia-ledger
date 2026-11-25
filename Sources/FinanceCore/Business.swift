import Foundation
import CryptoKit

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
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        startSide = try c.decodeIfPresent(Side.self, forKey: .startSide)
        businessBookID = try c.decodeIfPresent(String.self, forKey: .businessBookID)
        capital = try c.decodeIfPresent(Capital.self, forKey: .capital)
        debtExtras = try c.decodeIfPresent([String: DebtExtra].self, forKey: .debtExtras)
    }
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
        let firstBusinessChange = minReaderVersion < 2 && business == nil
        if firstBusinessChange {
            var prior = self
            prior.books.removeAll { added.contains($0.id) }
            upgradeBaseline.beforeBusiness = try? prior.upgradeFingerprint()
        }
        var snapshot = PlanSnapshot(addedBookIDs: added)
        snapshot.changedBusiness = true
        snapshot.business = business
        let change = snapshotChange(.edit, summary, before: snapshot, author: author)
        if firstBusinessChange { upgradeBaseline.changeID = change.id }
        business = settings
        minReaderVersion = max(minReaderVersion, 2)
        changes.append(change)
        return change
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

/// 两份指纹分别覆盖「读后一次改多项」以及「app 已保存过其他改动，再开启生意」。
/// 指纹属于存储来源，不参与账本内容的相等比较。
struct UpgradeBaseline: Equatable, Sendable {
    var readVersion: Int?
    var read: Data?
    var beforeBusiness: Data?
    var changeID: UUID?
    static func == (_ lhs: Self, _ rhs: Self) -> Bool { true }
}

extension Ledger {
    func upgradeFingerprint() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return Data(SHA256.hash(data: try encoder.encode(self)))
    }
}
