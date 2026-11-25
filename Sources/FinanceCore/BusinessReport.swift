import Foundation

public struct BusinessReport: Codable, Sendable {
    public struct Cost: Codable, Sendable { public let category: String; public let amount: Money }
    public let income, cost, profit, changeFromPrevious, takenHome, todayIncome, todayCost: Money
    public let topCosts: [Cost]
    public let fixed: [Recurring]
    public let fixedTotal, fixedUpcoming: Money
}
public enum RecoveryEstimate: Codable, Equatable, Sendable { case tooEarly, notRecovering, done, months(Int) }
public struct CapitalProgress: Codable, Sendable {
    public let recovered, remaining: Money
    public let fraction: Double
    public let estimate: RecoveryEstimate
}
extension Ledger {
    private func businessEntries(through today: LocalDate) -> [Transaction] {
        let excluded = Set(business?.capital?.items.flatMap { $0.txIDs ?? [] } ?? [])
        let hidden = privateAccountIDs
        return baseTransactions.filter { $0.date <= today && $0.bookID == businessBook?.id && !hidden.contains($0.accountID)
            && !excluded.contains($0.id) && !$0.isTransfer && $0.countsAsIncomeOrExpense }
    }
    public func businessReport(month: YearMonth, today: LocalDate) throws -> BusinessReport {
        guard let book = businessBook else { throw BusinessError(message: "请先选择生意账本") }
        let entries = businessEntries(through: today)
        let previous = month.adding(months: -1)
        let sums = Reports.summaries(entries, months: [previous, month], bookID: book.id)
        let spending = Summaries.expenseCategories(entries)
        var dayIncome = Money.zero, dayCost = Money.zero
        var costs: [String: Money] = [:]
        for tx in entries {
            let income = Summaries.countsAsIncome(tx, expenseCategories: spending)
            if tx.date == today {
                if income { dayIncome = dayIncome + tx.amount } else { dayCost = dayCost - tx.amount }
            }
            if !income && tx.date.yearMonth == month { costs[tx.category ?? "未分类", default: .zero] = costs[tx.category ?? "未分类", default: .zero] - tx.amount }
        }
        let ranked = costs.filter { $0.value > .zero }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let hidden = privateAccountIDs
        let visible = baseTransactions.filter { !hidden.contains($0.accountID) && $0.date <= today }
        let life = Set(lifeBookIDs)
        let eligible = visible.filter { $0.bookID == book.id || life.contains($0.bookID ?? "") }
        let paired = Summaries.pairInternal(eligible).crossBook.filter { $0.bookID == book.id && $0.amount < .zero && $0.date.yearMonth == month }
        let lifeIncoming = Set(eligible.filter { life.contains($0.bookID ?? "") && $0.amount > .zero }.compactMap(\.transferID))
        let explicit = eligible.filter { $0.flow != .internal && $0.bookID == book.id && $0.date.yearMonth == month && $0.amount < .zero && $0.transferID.map(lifeIncoming.contains) == true }
        let home = (paired + explicit).reduce(Money.zero) { $0 - $1.amount }
        let fixed = recurring.filter { !$0.paused && $0.template.bookID == book.id && $0.template.amount < .zero
            && !hidden.contains($0.template.accountID) && $0.start.yearMonth <= month && ($0.until?.yearMonth ?? month) >= month }
        var fixedTotal = Money.zero, upcoming = Money.zero
        for rule in fixed {
            var i = 0, date = rule.start
            let amount = baseAmount(rule.template).magnitude
            while date.yearMonth <= month && date <= (rule.until ?? date) {
                if date.yearMonth == month {
                    fixedTotal = fixedTotal + amount
                    if date > today { upcoming = upcoming + amount }
                }
                i += 1; date = rule.date(after: i)
            }
        }
        return BusinessReport(income: sums[1].income, cost: -sums[1].expense, profit: sums[1].net,
                              changeFromPrevious: sums[1].net - sums[0].net, takenHome: home, todayIncome: dayIncome, todayCost: dayCost,
                              topCosts: ranked.prefix(5).map { .init(category: $0.key, amount: $0.value) },
                              fixed: fixed, fixedTotal: fixedTotal, fixedUpcoming: upcoming)
    }
    public func capitalProgress(today: LocalDate) -> CapitalProgress? {
        guard let capital = business?.capital, capital.total > .zero, let book = businessBook else { return nil }
        let hidden = privateAccountIDs
        let start = capital.openedOn ?? transactions.filter { $0.bookID == book.id && !hidden.contains($0.accountID) }.map(\.date).min() ?? today
        let entries = businessEntries(through: today).filter { $0.date >= start }
        let recovered = entries.reduce(capital.recoveredBefore) { $0 + $1.amount }
        let remaining = max(.zero, capital.total - recovered)
        let months = Reports.months(endingAt: today.yearMonth.adding(months: -1), count: 3)
        let net = entries.filter { months.contains($0.date.yearMonth) }.reduce(Money.zero) { $0 + $1.amount }
        let estimate: RecoveryEstimate
        if remaining == .zero { estimate = .done }
        else if start.adding(months: 1) > today { estimate = .tooEarly }
        else if net <= .zero { estimate = .notRecovering }
        else {
            let duration = ceil(Double(remaining.cents) * Double(months.count) / Double(net.cents))
            estimate = .months(Int(exactly: duration) ?? Int.max)
        }
        return CapitalProgress(recovered: recovered, remaining: remaining,
                               fraction: min(1, max(0, Double(recovered.cents) / Double(capital.total.cents))), estimate: estimate)
    }
}
