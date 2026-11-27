import Foundation

/// 引导里「先看清你现在有多少」那张单子：还没进账本之前，先填几个账户、各有多少。
/// 哪些算「我有的」、哪些算「我欠的」、合计怎么算，都在这里；界面只管显示和收字。
public struct StartingAccounts: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case daily, cash, savings, jar, lent
        case credit, installment, borrowed
        case custom

        /// 按钮上的名字。
        public var title: String {
            switch self {
            case .daily: "日常卡"
            case .cash: "现金"
            case .savings: "储蓄"
            case .jar: "存钱罐"
            case .lent: "别人欠我的"
            case .credit: "信用卡"
            case .installment: "分期"
            case .borrowed: "我欠别人的"
            case .custom: "自己起名"
            }
        }

        /// 这一种默认算欠的钱吗（自己起名的可以再改）。
        public var owes: Bool { self == .credit || self == .installment || self == .borrowed }
        /// 名字要自己填的（谁欠我、我欠谁、自己起名）。
        public var asksName: Bool { self == .lent || self == .borrowed || self == .custom }
        public var namePrompt: String { self == .custom ? "叫什么" : asksName ? "谁？比如 小王" : title }
        public var emoji: String {
            switch self {
            case .daily, .credit: "💳"
            case .cash: "💶"
            case .savings: "🏦"
            case .jar: "⭐"
            case .lent: "🧑"
            case .installment: "📱"
            case .borrowed: "🤝"
            case .custom: "🏷"
            }
        }

        public static let have: [Kind] = [.daily, .cash, .savings, .jar, .lent]
        public static let owe: [Kind] = [.credit, .installment, .borrowed]
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var kind: Kind
        public var name: String
        /// 金额框里打的字，原样留着。
        public var text: String
        public var owes: Bool

        /// 读得懂就是一个不小于 0 的数；空着算 0；读不懂是 nil（先不算进合计）。
        public var amount: Money? {
            if text.trimmingCharacters(in: .whitespaces).isEmpty { return .zero }
            guard let m = Money(parsing: text), m >= .zero else { return nil }
            return m
        }

        /// 给人看的名字：没填就用这一种的叫法。
        public var displayName: String {
            let n = name.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? (kind == .custom ? "没起名的" : kind.title) : n
        }
    }

    public static let limit = 12
    public private(set) var rows: [Row]

    public init(rows: [Row] = []) { self.rows = rows }

    /// 一开始放的三行（示例）。
    public static var sample: StartingAccounts {
        StartingAccounts(rows: [
            Row(kind: .daily, name: "日常卡", text: "1.500", owes: false),
            Row(kind: .cash, name: "现金", text: "85", owes: false),
            Row(kind: .credit, name: "信用卡", text: "640", owes: true),
        ])
    }

    /// 加一行。同一种可以加好几个：第二个自动叫「日常卡 2」。返回新行的 id。
    @discardableResult
    public mutating func add(_ kind: Kind) throws -> UUID {
        guard rows.count < Self.limit else { throw TrialError("这里最多放 \(Self.limit) 个，进去以后在「家底」里还能加") }
        var name = ""
        if !kind.asksName {
            let used = Set(rows.map(\.name))
            name = kind.title
            var n = 2
            while used.contains(name) { name = "\(kind.title) \(n)"; n += 1 }
        }
        let row = Row(kind: kind, name: name, text: "", owes: kind.owes)
        rows.append(row)
        return row.id
    }

    public mutating func rename(_ id: UUID, to name: String) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].name = String(name.prefix(20))
    }

    public mutating func setText(_ id: UUID, _ text: String) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].text = text
    }

    /// 自己起名的那种：是我有的钱，还是我欠的钱。
    public mutating func setOwes(_ id: UUID, _ owes: Bool) {
        guard let i = rows.firstIndex(where: { $0.id == id }), rows[i].kind == .custom else { return }
        rows[i].owes = owes
    }

    /// 删一行。返回删掉的那行和它原来排第几（撤销时放回去用）。
    @discardableResult
    public mutating func remove(_ id: UUID) -> (row: Row, index: Int)? {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
        return (rows.remove(at: i), i)
    }

    /// 撤销删除：放回原来的位置。
    public mutating func restore(_ row: Row, at index: Int) {
        guard !rows.contains(where: { $0.id == row.id }) else { return }
        rows.insert(row, at: min(max(index, 0), rows.count))
    }

    /// 有一格的数读不懂。
    public var hasUnreadable: Bool { rows.contains { $0.amount == nil } }

    /// 一共有、欠别人、净剩。读不懂的那格先不算。
    public var totals: HouseholdTotals {
        HouseholdTotals(holdings: rows.filter { !$0.owes }.compactMap(\.amount), debts: rows.filter(\.owes).compactMap(\.amount))
    }
}
