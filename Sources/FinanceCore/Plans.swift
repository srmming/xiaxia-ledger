import Foundation

// 借款往来、分期、目标和储蓄。
// 口径：借出 / 借入 / 还款都是「往来」，不算收入也不算支出；
// 分期：买的那天按全额记支出，之后每期还款是还债（往来，不进收支），手续费和利息单独记支出（2026-11-21 ming 定）；
// 存进目标的钱是「转进储蓄」，也不算支出。

/// 借款往来：谁欠我钱、我欠谁。
public struct Debt: Identifiable, Hashable, Codable, Sendable {
    public enum Direction: String, Codable, Sendable {
        case theyOweMe   // 我借出去的，对方欠我
        case iOweThem    // 我借来的，我欠对方
    }

    public var id: UUID
    public var counterparty: String       // 对方，如「阿华」
    public var direction: Direction
    public var principal: Money           // 借了多少（正数）
    public var bookID: String
    public var startDate: LocalDate
    public var dueDate: LocalDate?
    public var note: String?
    /// 还款流水（借出的话是对方还给我的入账；借入的话是我还出去的支出）。金额取绝对值累加。
    public var repaymentIDs: [UUID]
    public var closed: Bool               // 手动结清（比如对方不用还了）

    public init(id: UUID = UUID(), counterparty: String, direction: Direction, principal: Money,
                bookID: String, startDate: LocalDate, dueDate: LocalDate? = nil, note: String? = nil,
                repaymentIDs: [UUID] = [], closed: Bool = false) {
        self.id = id; self.counterparty = counterparty; self.direction = direction; self.principal = principal
        self.bookID = bookID; self.startDate = startDate; self.dueDate = dueDate; self.note = note
        self.repaymentIDs = repaymentIDs; self.closed = closed
    }
}

/// 分期：手机、家电、店里设备……按月还。
public struct Installment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String               // 如「美甲灯分期」
    public var bookID: String
    public var accountID: String          // 从哪个账户扣
    public var total: Money               // 总额（正数）
    public var count: Int                 // 共几期
    public var firstDate: LocalDate       // 第一期扣款日
    public var paidIDs: [UUID]            // 已扣款的流水（往来，不算支出）
    /// 买的那天记的全额支出那笔。
    public var purchaseID: UUID?

    public init(id: UUID = UUID(), name: String, bookID: String, accountID: String, total: Money,
                count: Int, firstDate: LocalDate, paidIDs: [UUID] = []) {
        self.id = id; self.name = name; self.bookID = bookID; self.accountID = accountID
        self.total = total; self.count = count; self.firstDate = firstDate; self.paidIDs = paidIDs
    }

    enum CodingKeys: String, CodingKey { case id, name, bookID, accountID, total, count, firstDate, paidIDs, purchaseID }

    /// 每期金额（最后一期吃掉除不尽的零头）。
    public var perPayment: Money { Money(cents: total.cents / Int64(max(count, 1))) }
}

/// 目标：为某件事存钱（应急金、店铺装修、回国机票……）。
public struct Goal: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var bookID: String
    public var target: Money
    public var deadline: LocalDate?
    /// 专门存这笔钱的账户（如 Revolut 储蓄罐）。有它时进度 = 这个账户余额；没有就按 contributionIDs 累加。
    public var savingsAccountID: String?
    public var contributionIDs: [UUID]
    /// 锁定：存进去就不能动，到期（或达成）前不许取。给以后的「宝宝存钱」小游戏和强制储蓄用。
    public var locked: Bool

    public init(id: UUID = UUID(), name: String, bookID: String, target: Money, deadline: LocalDate? = nil,
                savingsAccountID: String? = nil, contributionIDs: [UUID] = [], locked: Bool = false) {
        self.id = id; self.name = name; self.bookID = bookID; self.target = target; self.deadline = deadline
        self.savingsAccountID = savingsAccountID; self.contributionIDs = contributionIDs; self.locked = locked
    }

    enum CodingKeys: String, CodingKey { case id, name, bookID, target, deadline, savingsAccountID, contributionIDs, locked }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        bookID = try c.decode(String.self, forKey: .bookID)
        target = try c.decode(Money.self, forKey: .target)
        deadline = try c.decodeIfPresent(LocalDate.self, forKey: .deadline)
        savingsAccountID = try c.decodeIfPresent(String.self, forKey: .savingsAccountID)
        contributionIDs = try c.decodeIfPresent([UUID].self, forKey: .contributionIDs) ?? []
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }
}

public struct DebtStatus: Codable, Sendable, Equatable {
    public var id: UUID
    public var counterparty: String
    public var direction: Debt.Direction
    public var principal: Money
    public var repaid: Money
    public var outstanding: Money
    public var dueDate: LocalDate?
    public var overdue: Bool
}

/// 快要扣的一笔：订阅或者分期的下一期。总览「快要扣钱」和订阅页「7 天内要扣」都用它。
public struct UpcomingCharge: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var amount: Money
    public var currency: String
    public var daysLeft: Int
    public var accountID: String?
    public var bookID: String?
    public var isInstallment: Bool
    public init(id: UUID, name: String, amount: Money, currency: String, daysLeft: Int, accountID: String?, bookID: String?, isInstallment: Bool) {
        self.id = id; self.name = name; self.amount = amount; self.currency = currency; self.daysLeft = daysLeft
        self.accountID = accountID; self.bookID = bookID; self.isInstallment = isInstallment
    }
}

/// 别人欠我多少、我还欠多少（借来的没还完 + 分期没还完）。
public struct Obligations: Equatable, Sendable {
    public var owedToMe: Money
    public var iOwe: Money
    public init(owedToMe: Money, iOwe: Money) { self.owedToMe = owedToMe; self.iOwe = iOwe }
    /// 算进家底的那部分：正数是净的别人欠我，负数是净的我欠别人。
    public var net: Money { owedToMe - iOwe }
    public var isEmpty: Bool { owedToMe.cents == 0 && iOwe.cents == 0 }
}

public struct InstallmentStatus: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var paidCount: Int
    public var count: Int
    public var perPayment: Money
    public var remaining: Money
    public var nextDate: LocalDate?
}

public struct GoalStatus: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var target: Money
    public var saved: Money
    public var percent: Int
    public var deadline: LocalDate?
    public var locked: Bool
}

public enum Plans {
    static func amounts(_ ids: [UUID], in txs: [Transaction]) -> Money {
        let set = Set(ids)
        return txs.filter { set.contains($0.id) }.reduce(.zero) { $0 + $1.amount.magnitude }
    }

    /// 几天内要扣的分期（下一期），金额按账户的币种。
    public static func installmentsDue(_ ledger: Ledger, today: LocalDate, within days: Int) -> [UpcomingCharge] {
        let status = Dictionary(installments(ledger).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ledger.installments.compactMap { i in
            guard let s = status[i.id], let next = s.nextDate, s.remaining.cents > 0 else { return nil }
            let left = today.days(until: next)
            guard left >= 0, left <= days else { return nil }
            let currency = ledger.accounts.first { $0.id == i.accountID }?.currency ?? ledger.baseCurrency
            return UpcomingCharge(id: i.id, name: i.name, amount: Money(cents: min(s.perPayment.cents, s.remaining.cents)), currency: currency,
                                  daysLeft: left, accountID: i.accountID, bookID: i.bookID, isInstallment: true)
        }
        .sorted { $0.daysLeft < $1.daysLeft }
    }

    /// 某一天还没了结的欠款和分期（「欠款与分期」页顶上那一行，也算进家底）。
    /// 借出去、借进来、分期买东西时，账户里的钱已经跟着进出了，这里补上「还欠着/还没收回」的那部分：
    /// 家底 = 账户余额 + 别人欠我 − 我还欠（借来的没还完 + 分期没还完）。
    /// - bookID: 只算某个账本；nil 是全部。
    public static func obligations(_ ledger: Ledger, asOf date: LocalDate, bookID: String? = nil) -> Obligations {
        let byID = Dictionary(ledger.transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func paid(_ ids: [UUID]) -> Int64 {
            ids.compactMap { byID[$0] }.filter { $0.date <= date }.reduce(Int64(0)) { $0 + $1.amount.magnitude.cents }
        }
        var owedToMe: Int64 = 0, iOwe: Int64 = 0
        for d in ledger.debts where !d.closed && d.startDate <= date && (bookID == nil || d.bookID == bookID) {
            let left = max(0, d.principal.cents - paid(d.repaymentIDs))
            if d.direction == .theyOweMe { owedToMe += left } else { iOwe += left }
        }
        for i in ledger.installments where bookID == nil || i.bookID == bookID {
            let start = i.purchaseID.flatMap { byID[$0]?.date } ?? i.firstDate
            guard start <= date else { continue }
            iOwe += max(0, i.total.cents - paid(i.paidIDs))
        }
        return Obligations(owedToMe: Money(cents: owedToMe), iOwe: Money(cents: iOwe))
    }

    public static func debts(_ ledger: Ledger, today: LocalDate, includeClosed: Bool = false) -> [DebtStatus] {
        ledger.debts.compactMap { d in
            let repaid = amounts(d.repaymentIDs, in: ledger.transactions)
            let left = Money(cents: max(0, d.principal.cents - repaid.cents))
            let open = !d.closed && left.cents > 0
            guard open || includeClosed else { return nil }
            return DebtStatus(id: d.id, counterparty: d.counterparty, direction: d.direction, principal: d.principal,
                              repaid: repaid, outstanding: d.closed ? .zero : left, dueDate: d.dueDate,
                              overdue: open && (d.dueDate.map { $0 < today } ?? false))
        }
    }

    public static func installments(_ ledger: Ledger) -> [InstallmentStatus] {
        ledger.installments.map { i in
            let paid = min(i.paidIDs.count, i.count)
            let paidAmount = amounts(i.paidIDs, in: ledger.transactions)
            let remaining = Money(cents: max(0, i.total.cents - paidAmount.cents))
            var next: LocalDate? = nil
            if paid < i.count {
                let m = i.firstDate.month - 1 + paid
                next = LocalDate(year: i.firstDate.year + m / 12, month: m % 12 + 1, day: min(i.firstDate.day, 28))
            }
            return InstallmentStatus(id: i.id, name: i.name, paidCount: paid, count: i.count,
                                     perPayment: i.perPayment, remaining: remaining, nextDate: next)
        }
    }

    public static func goals(_ ledger: Ledger) -> [GoalStatus] {
        let balances = ledger.accountBalances().mapValues(\.base)
        return ledger.goals.map { g in
            let saved: Money
            if let acct = g.savingsAccountID { saved = Money(cents: max(0, (balances[acct] ?? .zero).cents)) }
            else {
                // 存入是正数那笔、取出是负数那笔，按正负累加。
                let ids = Set(g.contributionIDs)
                let sum = ledger.transactions.filter { ids.contains($0.id) }.reduce(Money.zero) { $0 + $1.amount }
                saved = Money(cents: max(0, sum.cents))
            }
            let pct = g.target.cents > 0 ? Int(min(100, saved.cents * 100 / g.target.cents)) : 0
            return GoalStatus(id: g.id, name: g.name, target: g.target, saved: saved, percent: pct, deadline: g.deadline, locked: g.locked)
        }
    }

    /// 储蓄率 = 结余 / 收入（某月某账本）。
    public static func savingsRate(_ s: MonthlySummary) -> Int? {
        guard s.income.cents > 0 else { return nil }
        return Int(s.net.cents * 100 / s.income.cents)
    }
}
