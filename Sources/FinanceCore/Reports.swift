import Foundation

/// 报表：一段时间里每个月的收支、分类排行、导出。
public enum Reports {
    /// 某一年的 12 个月。
    public static func months(of year: Int) -> [YearMonth] { (1...12).map { YearMonth(year: year, month: $0) } }

    /// 以 end 结尾的连续 n 个月，从早到晚。
    public static func months(endingAt end: YearMonth, count n: Int) -> [YearMonth] {
        (0..<max(n, 0)).reversed().map { end.adding(months: -$0) }
    }

    /// 一次算好多个月的汇总（只扫一遍流水）。口径和 Summaries.monthly 一样。
    public static func summaries(_ txs: [Transaction], months: [YearMonth], bookID: String?,
                                 hiddenAccounts: Set<String> = []) -> [MonthlySummary] {
        var income: [YearMonth: Money] = [:], expense: [YearMonth: Money] = [:]
        var cats: [YearMonth: [String: Money]] = [:]
        let wanted = Set(months)
        let spending = Summaries.expenseCategories(txs)
        for tx in txs {
            let m = tx.date.yearMonth
            guard wanted.contains(m), tx.countsAsIncomeOrExpense, !hiddenAccounts.contains(tx.accountID) else { continue }
            if let bookID { guard tx.bookID == bookID else { continue } } else if tx.isTransfer { continue }
            if Summaries.countsAsIncome(tx, expenseCategories: spending) { income[m, default: .zero] = income[m, default: .zero] + tx.amount }
            else { expense[m, default: .zero] = expense[m, default: .zero] + tx.amount }
            let c = tx.category ?? "未分类"
            cats[m, default: [:]][c, default: .zero] = cats[m, default: [:]][c, default: .zero] + tx.amount
        }
        let moved = Summaries.betweenBooks(txs, months: months, bookID: bookID, hiddenAccounts: hiddenAccounts)
        return months.map {
            MonthlySummary(month: $0, bookID: bookID, income: income[$0] ?? .zero, expense: expense[$0] ?? .zero,
                           byCategory: cats[$0] ?? [:], betweenBooks: moved[$0] ?? .zero)
        }
    }

    /// 「和别的账本之间挪的钱」该怎么叫：进来的叫「从别的账本拿的」，出去的叫「拿去别的账本的」。
    /// 只有两个账本时直接说对方的名字，比如个人账本里显示「从 Miora 美甲店拿的」。
    public static func betweenBooksLabel(_ amount: Money, bookID: String, books: [Book]) -> String {
        let others = books.filter { $0.id != bookID }
        let other = others.count == 1 ? others[0].name : "别的账本"
        return amount.cents >= 0 ? "从\(other)拿的" : "拿去\(other)的"
    }

    /// 把几个月的分类加起来。expense = true 只要花钱的分类（按花得多排），false 只要进钱的。
    public static func categoryTotals(_ list: [MonthlySummary], expense: Bool) -> [(name: String, amount: Money)] {
        var total: [String: Money] = [:]
        for s in list { for (k, v) in s.byCategory { total[k, default: .zero] = total[k, default: .zero] + v } }
        return total.filter { expense ? $0.value.isExpense : ($0.value.isIncome && $0.key != Transaction.refundCategory) }
            .map { (name: $0.key, amount: $0.value.magnitude) }
            .sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }

    /// 导出成 CSV（给 gestoría、Excel、Numbers 用）。列：日期、金额、说明、分类、账户、账本、性质。
    public static func csv(_ txs: [Transaction], ledger: Ledger) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let accounts = Dictionary(ledger.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let books = Dictionary(ledger.books.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var lines = ["日期,金额,说明,分类,账户,账本,性质"]
        for t in txs.sorted(by: { $0.date < $1.date }) {
            let nature: String
            switch t.flow {
            case .debt: nature = "借款往来"
            case .saving: nature = "储蓄"
            case .opening: nature = "期初余额"
            case .internal: nature = "账户间转账"
            case nil: nature = t.isTransfer ? "账本间转账" : (t.amount.isIncome ? "收入" : "支出")
            }
            lines.append([t.date.description, t.amount.decimalString, q(t.description), q(t.category ?? ""),
                          q(accounts[t.accountID] ?? t.accountID), q(t.bookID.flatMap { books[$0] } ?? ""), nature]
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension YearMonth {
    /// 往后（正数）或往前（负数）挪几个月。
    public func adding(months delta: Int) -> YearMonth {
        let k = year * 12 + (month - 1) + delta
        return YearMonth(year: Int((Double(k) / 12).rounded(.down)), month: ((k % 12) + 12) % 12 + 1)
    }
}
