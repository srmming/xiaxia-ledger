import Foundation

/// 某个月、某个账本（或全部）的收支汇总。
public struct MonthlySummary: Equatable, Sendable {
    public var month: YearMonth
    public var bookID: String?        // nil = 全部
    public var income: Money
    public var expense: Money         // 负数
    public var byCategory: [String: Money]

    public var net: Money { income + expense }
}

public enum Summaries {
    /// 统计口径：
    /// - 单个账本：账本间转账照常算（店记「老板提款」支出，个人记收入）。
    /// - 全部：账本间转账两边抵消，不重复算。
    /// - 退款（花钱的分类里出现的进账，比如「购物」里退回来 20 €）冲减这个分类的支出，不算收入。
    /// hiddenAccounts：不算进来的账户（app 默认把私房钱藏起来）。
    public static func monthly(_ txs: [Transaction], month: YearMonth, bookID: String?,
                               hiddenAccounts: Set<String> = []) -> MonthlySummary {
        let inScope = txs.filter { tx in
            guard tx.date.yearMonth == month, tx.countsAsIncomeOrExpense, !hiddenAccounts.contains(tx.accountID) else { return false }
            if let bookID { return tx.bookID == bookID }
            return !tx.isTransfer
        }
        let spending = expenseCategories(txs)
        var income = Money.zero, expense = Money.zero
        var byCategory: [String: Money] = [:]
        for tx in inScope {
            if countsAsIncome(tx, expenseCategories: spending) { income = income + tx.amount } else { expense = expense + tx.amount }
            byCategory[tx.category ?? "未分类", default: .zero] = byCategory[tx.category ?? "未分类", default: .zero] + tx.amount
        }
        return MonthlySummary(month: month, bookID: bookID, income: income, expense: expense, byCategory: byCategory)
    }

    /// 哪些分类是「花钱的分类」：这个分类下所有收支加起来是负的。另外「退款」这个分类名永远算。
    /// 用整本账来判断，别只拿一个月的流水（某个月可能只有退款）。
    public static func expenseCategories(_ txs: [Transaction]) -> Set<String> {
        var net: [String: Int64] = [:]
        for tx in txs where tx.countsAsIncomeOrExpense {
            if let c = tx.category { net[c, default: 0] += tx.amount.cents }
        }
        var out = Set(net.filter { $0.value < 0 }.keys)
        out.insert(Transaction.refundCategory)
        return out
    }

    /// 这笔进账算不算收入。花钱的分类里的进账是退款，不算。
    public static func countsAsIncome(_ tx: Transaction, expenseCategories: Set<String>) -> Bool {
        guard tx.amount.cents > 0 else { return false }
        if let c = tx.category, expenseCategories.contains(c) { return false }
        return true
    }

    /// 每个账户的余额（流水累加，不分账本）。
    public static func balances(_ txs: [Transaction]) -> [String: Money] {
        txs.reduce(into: [:]) { acc, tx in acc[tx.accountID, default: .zero] = acc[tx.accountID, default: .zero] + tx.amount }
    }
}
