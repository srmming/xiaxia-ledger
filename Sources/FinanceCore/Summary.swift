import Foundation

/// 某个月、某个账本（或全部）的收支汇总。
public struct MonthlySummary: Equatable, Sendable {
    public var month: YearMonth
    public var bookID: String?        // nil = 全部
    public var income: Money
    public var expense: Money         // 负数
    public var byCategory: [String: Money]
    /// 和别的账本之间挪的钱（只在看单个账本时有）：这个账本名下「自己账户间转账」加起来的净额。
    /// 正数 = 从别的账本拿进来的（个人账本：从店里拿回家的），负数 = 拿去别的账本的（店账本：老板拿走的）。
    /// 不算收入也不算支出，单独列出来；同一个账本内部的互转一进一出正好抵消，不会出现在这里。
    public var betweenBooks: Money = .zero

    public var net: Money { income + expense }
    /// 把和别的账本之间挪的钱也算上之后，实际剩下多少。
    public var netWithBetweenBooks: Money { net + betweenBooks }
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
        let moved = betweenBooks(txs, months: [month], bookID: bookID, hiddenAccounts: hiddenAccounts)[month] ?? .zero
        return MonthlySummary(month: month, bookID: bookID, income: income, expense: expense, byCategory: byCategory,
                              betweenBooks: moved)
    }

    /// 每个月这个账本和别的账本之间净挪了多少钱（看「全部」时永远是空的）。
    /// 例子：从店里的 Caixa 转 400 € 到自己的 imagin。店账本这个月 −400（老板拿走的），个人账本 +400（从店里拿的）。
    /// 只做计算，不改流水。
    public static func betweenBooks(_ txs: [Transaction], months: [YearMonth], bookID: String?,
                                    hiddenAccounts: Set<String> = []) -> [YearMonth: Money] {
        guard let bookID else { return [:] }
        let wanted = Set(months)
        var out: [YearMonth: Money] = [:]
        for tx in txs where tx.flow == .internal && tx.bookID == bookID && !hiddenAccounts.contains(tx.accountID) {
            let m = tx.date.yearMonth
            guard wanted.contains(m) else { continue }
            out[m, default: .zero] = out[m, default: .zero] + tx.amount
        }
        return out.filter { $0.value.cents != 0 }
    }

    /// 这几个月里「自己账户间转账」没对上的差额：所有账本的互转加起来本该是 0（一边出、一边进）。
    /// 不是 0 说明有的转账只记了一边，或者两边分属的账本标错了，「从店里拿的」那个数就不完全可信，要提醒。
    /// 月底转出、下月初才到账的那种会在两个月各差一次，所以最好按整年来看。
    public static func unmatchedInternal(_ txs: [Transaction], months: [YearMonth]) -> Money {
        let wanted = Set(months)
        return txs.reduce(Money.zero) { sum, tx in
            tx.flow == .internal && wanted.contains(tx.date.yearMonth) ? sum + tx.amount : sum
        }
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
