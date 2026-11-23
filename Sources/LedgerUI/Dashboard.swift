import FinanceCore
import Foundation

/// 看板页面用的派生数字。只做计算、不改账本；口径和 FinanceCore 的 Summaries 一致。
extension YearMonth {
    var dayCount: Int {
        let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        return Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    }
    var previous: YearMonth { adding(months: -1) }
}

/// 花钱速度线上的一个点：第几天、到这天为止一共花了多少（正数，欧元）。
struct PacePoint: Identifiable {
    var day: Int
    var amount: Double
    var series: String
    var id: String { "\(series)-\(day)" }
}

struct NetWorthPoint: Identifiable {
    var month: YearMonth
    var value: Money
    var id: YearMonth { month }
}

struct MerchantTotal: Identifiable {
    var name: String
    var category: String?
    var count: Int
    var amount: Money
    var id: String { name }
}

/// 某个月的「总览」数字：剩多少、比上月同期怎样、照这样月底剩多少。
struct MonthStatus {
    var month: YearMonth
    var summary: MonthlySummary
    /// 这个月过到第几天（看的是以前的月份就是整月）。
    var dayOfMonth: Int
    var isCurrent: Bool
    /// 上个月同一天为止剩下的。
    var lastMonthSameDayNet: Money
    var spentSoFar: Money          // 正数
    var lastMonthSameDaySpent: Money
    var projectedEnd: Money?       // 照上个月剩下那段的收支，月底大概剩多少（只有本月才有）
    var pace: [PacePoint]
    var lastPace: [PacePoint]

    var net: Money { summary.net }
    var deltaVsLastMonth: Money { net - lastMonthSameDayNet }

    /// 花钱速度：和上月同一天比，差 10% 以内算正常。
    var paceWord: String {
        let now = Double(spentSoFar.cents), before = Double(lastMonthSameDaySpent.cents)
        guard before > 0 else { return "正常" }
        let r = now / before
        if r > 1.1 { return "偏快" }
        if r < 0.9 { return "偏慢" }
        return "正常"
    }
}

extension LedgerModel {
    /// 和 Summaries.monthly 一样的范围：普通收支、没藏起来的账户、选中的账本（全部时不算账本间转账）。
    func scopedTransactions(_ month: YearMonth, bookID: String?) -> [Transaction] {
        let hidden = hiddenAccounts
        return baseTransactions.filter { tx in
            guard tx.date.yearMonth == month, tx.countsAsIncomeOrExpense, !hidden.contains(tx.accountID) else { return false }
            if let bookID { return tx.bookID == bookID }
            return !tx.isTransfer
        }
    }

    /// 某个月某个账本里「花掉」的流水（退款冲减的那些也在里面，金额是正的）。
    func expenseTransactions(_ month: YearMonth, bookID: String?) -> [Transaction] {
        let spending = Summaries.expenseCategories(ledger.transactions)
        return scopedTransactions(month, bookID: bookID).filter { !Summaries.countsAsIncome($0, expenseCategories: spending) }
    }

    private func cumulative(_ month: YearMonth, bookID: String?, upTo day: Int, series: String) -> [PacePoint] {
        var perDay = [Int64](repeating: 0, count: month.dayCount + 1)
        for t in expenseTransactions(month, bookID: bookID) where t.date.day <= day {
            perDay[t.date.day] -= t.amount.cents
        }
        var total: Int64 = 0
        var points = [PacePoint(day: 0, amount: 0, series: series)]
        for d in 1...max(1, min(day, month.dayCount)) {
            total += perDay[d]
            points.append(PacePoint(day: d, amount: Double(total) / 100, series: series))
        }
        return points
    }

    private func net(_ month: YearMonth, bookID: String?, upTo day: Int) -> Money {
        scopedTransactions(month, bookID: bookID).filter { $0.date.day <= day }.reduce(Money.zero) { $0 + $1.amount }
    }

    func status(_ month: YearMonth, bookID: String? = nil, useSelectedBook: Bool = true) -> MonthStatus {
        let book = useSelectedBook ? selectedBookID : bookID
        let today = LocalDate.today
        let isCurrent = month == today.yearMonth
        let day = isCurrent ? today.day : month.dayCount
        let summary = Summaries.monthly(baseTransactions, month: month, bookID: book, hiddenAccounts: hiddenAccounts)
        let prev = month.previous
        let prevDay = min(day, prev.dayCount)
        let pace = cumulative(month, bookID: book, upTo: day, series: "本月")
        let lastPace = cumulative(prev, bookID: book, upTo: prev.dayCount, series: "上月")
        let spent = Money(cents: Int64(((pace.last?.amount ?? 0) * 100).rounded()))
        let lastSpent = Money(cents: Int64(((lastPace.first { $0.day == prevDay }?.amount ?? 0) * 100).rounded()))
        var projected: Money? = nil
        if isCurrent, day >= 3, day < month.dayCount {
            // 月底剩多少 = 到今天剩的 + 剩下这些天还会进出的钱。
            // 剩下这些天照上个月同一段的收支估：月底发工资、交社保、收房租这种一来一去都算进去，
            // 不然只按「每天花多少」往后推，会漏掉月底的进账，出现「比上月多剩，却说月底超支」的矛盾。
            if !scopedTransactions(prev, bookID: book).isEmpty {
                projected = summary.net + (net(prev, bookID: book, upTo: prev.dayCount) - net(prev, bookID: book, upTo: prevDay))
            } else {
                let perDay = Double(spent.cents) / Double(day)
                projected = summary.net - Money(cents: Int64(perDay * Double(month.dayCount - day)))
            }
        }
        return MonthStatus(month: month, summary: summary, dayOfMonth: day, isCurrent: isCurrent,
                           lastMonthSameDayNet: net(prev, bookID: book, upTo: prevDay),
                           spentSoFar: spent, lastMonthSameDaySpent: lastSpent, projectedEnd: projected,
                           pace: pace, lastPace: lastPace)
    }

    /// 这个月花得最多的商户（按商户名合并）。
    func topMerchants(_ month: YearMonth, limit: Int = 5) -> [MerchantTotal] {
        var map: [String: MerchantTotal] = [:]
        for t in expenseTransactions(month, bookID: selectedBookID) {
            let name = Merchant.display(t.description)
            var m = map[name] ?? MerchantTotal(name: name, category: t.category, count: 0, amount: .zero)
            m.count += 1
            m.amount = m.amount + t.amount.magnitude
            map[name] = m
        }
        return map.values.sorted { $0.amount > $1.amount }.prefix(limit).map { $0 }
    }

    /// 每个月底的家底（所有看得见的账户余额加起来，信用卡是负的）。
    func netWorthSeries(months: [YearMonth]) -> [NetWorthPoint] {
        let hidden = hiddenAccounts
        let txs = baseTransactions.filter { !hidden.contains($0.accountID) }.sorted { $0.date < $1.date }
        var result: [NetWorthPoint] = []
        var i = 0
        var running = Money.zero
        for m in months.sorted() {
            let end = LocalDate(year: m.year, month: m.month, day: m.dayCount)
            while i < txs.count, txs[i].date <= end { running = running + txs[i].amount; i += 1 }
            // 别人欠我的算进来、我还欠的（借款、分期没还完）减掉（ming 2026-11-23）。
            let owed = Plans.obligations(ledger, asOf: min(end, LocalDate.today)).net
            // 本月这个点用现在的账户余额（外币按今天的汇率），和家底页的大数字是同一个数。
            result.append(NetWorthPoint(month: m, value: (end >= LocalDate.today ? totalBalance : running) + owed))
        }
        return result
    }

    /// 钱在哪：到这个月底为止，能随时用的 / 存着的 / 店里的 / 别人欠我的 / 欠款。口径和 netWorthSeries 一样，net 就是那条曲线的最后一个点。
    func wealthBreakdown(_ month: YearMonth) -> WealthBreakdown {
        let end = LocalDate(year: month.year, month: month.month, day: month.dayCount)
        // 看本月：用和下面账户列表一样的余额（外币按今天的汇率），分项加起来才和列表对得上。看以前的月份：按到那个月底的流水算。
        var balances = self.balances
        if end < LocalDate.today {
            balances = [:]
            for t in baseTransactions where t.date <= end { balances[t.accountID, default: .zero] = balances[t.accountID, default: .zero] + t.amount }
        }
        let saved = Dictionary(Plans.goals(ledger).map { ($0.id, $0.saved) }, uniquingKeysWith: { a, _ in a })
        return WealthBreakdown.make(accounts: visibleAccounts, balances: balances,
                                    goals: ledger.goals.map { (goal: $0, saved: saved[$0.id] ?? .zero) },
                                    businessAccounts: WealthBreakdown.businessAccounts(ledger),
                                    obligations: Plans.obligations(ledger, asOf: min(end, LocalDate.today)))
    }

    /// 最近 3 个过完的、有花销的月平均每月花多少（正数）。没有过完的月就用这个月到现在的。
    func averageMonthlySpend() -> Money {
        let today = LocalDate.today.yearMonth
        let months = Reports.months(endingAt: today, count: 7)
        let list = summaries(months, bookID: nil).filter { $0.expense.cents != 0 }
        let full = Array(list.filter { $0.month < today }.suffix(3))
        let basis = full.isEmpty ? list : full
        guard !basis.isEmpty else { return .zero }
        return Money(cents: basis.reduce(Int64(0)) { $0 + $1.expense.magnitude.cents } / Int64(basis.count))
    }

    // MARK: 谁记的

    /// 每一笔流水最后是谁写的（改动记录里最后一条没撤销的）。
    var authors: [UUID: String] {
        if let c = authorCache, c.count == ledger.changes.count { return c.map }
        var map: [UUID: String] = [:]
        for change in ledger.changes.sorted(by: { $0.createdAt < $1.createdAt }) where !change.undone {
            for id in change.transactionIDs { map[id] = change.author }
        }
        authorCache = (ledger.changes.count, map)
        return map
    }

    /// 改动是 app 的使用者自己做的（不是 AI）。
    func isMe(_ author: String) -> Bool { author == self.author || author == "示例" || author == "你" }

    /// 最近一次 AI 写账本：谁、什么时候。
    var lastAIChange: ChangeRecord? {
        ledger.changes.filter { !isMe($0.author) && !$0.undone }.max { $0.createdAt < $1.createdAt }
    }

    /// 用过账本的 AI 工具（按名字），给 AI 页和设置页显示「已连上」。
    var aiTools: [AITool] {
        var map: [String: Date] = [:]
        for c in ledger.changes where !isMe(c.author) { map[c.author] = max(map[c.author] ?? .distantPast, c.createdAt) }
        return map.map { AITool(name: $0.key, last: $0.value) }.sorted { $0.last > $1.last }
    }
}

struct AITool: Identifiable {
    var name: String
    var last: Date
    var id: String { name }
}

extension Date {
    /// 「今天 09:12」「昨天 22:40」「11 月 18 日」
    var friendly: String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        if cal.isDateInToday(self) { return "今天 " + f.string(from: self) }
        if cal.isDateInYesterday(self) { return "昨天 " + f.string(from: self) }
        let d = LocalDate(self)
        return d.friendly
    }
    var clock: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }
}
