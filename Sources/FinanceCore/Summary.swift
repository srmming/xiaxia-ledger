import Foundation

/// 某个月、某个账本（或全部）的收支汇总。
public struct MonthlySummary: Equatable, Sendable {
    public var month: YearMonth
    public var bookID: String?        // nil = 全部
    public var income: Money
    public var expense: Money         // 负数
    public var byCategory: [String: Money]
    /// 和别的账本之间挪的钱（只在看单个账本时有）：配上对、另一边在别的账本的「自己账户间转账」净额。
    /// 正数 = 从别的账本拿进来的（个人账本：从店里拿回家的），负数 = 拿去别的账本的（店账本：老板拿走的）。
    /// 不算收入也不算支出，单独列出来；同一个账本内部的互转、只记了一边的互转都不算在这里。
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

    /// 「自己账户间转账」两边配对的结果。
    public struct InternalPairing: Sendable {
        /// 配上对、而且两边分属不同账本的那些流水（从店里拿回家的钱就在这里）。
        public var crossBook: [Transaction] = []
        /// 没配上对的：只记了转出或只记了转入的那一边。
        public var unpaired: [Transaction] = []
    }

    /// 把「自己账户间转账」一出一进配成对：金额相同、方向相反、不是同一个账户、日期相差 4 天以内，取日期最近的。
    /// 例子：3 号 Caixa −400、4 号 imagin +400 配成一对。Caixa 记在店账本、imagin 记在个人账本，这一对就是「从店里拿回家 400」。
    /// 配对是推出来的，不是账单上写的，所以没配上的要单独标出来，不能悄悄算进去。只做计算，不改流水。
    public static func pairInternal(_ txs: [Transaction]) -> InternalPairing {
        var groups: [Int64: (out: [Transaction], into: [Transaction])] = [:]
        for tx in txs where tx.flow == .internal && tx.amount.cents != 0 {
            let key = abs(tx.amount.cents)
            if tx.amount.cents < 0 { groups[key, default: ([], [])].out.append(tx) } else { groups[key, default: ([], [])].into.append(tx) }
        }
        var result = InternalPairing()
        for (_, g) in groups {
            var into = g.into.sorted { $0.date < $1.date }
            for out in g.out.sorted(by: { $0.date < $1.date }) {
                var best: (index: Int, gap: Int)?
                for (k, cand) in into.enumerated() where cand.accountID != out.accountID {
                    let gap = abs(dayNumber(cand.date) - dayNumber(out.date))
                    if gap <= 4, best == nil || gap < best!.gap { best = (k, gap) }
                }
                if let best {
                    let other = into.remove(at: best.index)
                    if out.bookID != other.bookID { result.crossBook += [out, other] }
                } else {
                    result.unpaired.append(out)
                }
            }
            result.unpaired += into
        }
        result.unpaired.sort { $0.date < $1.date }
        return result
    }

    /// 从某个固定日子数起的第几天，只用来算两个日期差几天。
    private static func dayNumber(_ d: LocalDate) -> Int {
        let a = (14 - d.month) / 12, y = d.year + 4800 - a, m = d.month + 12 * a - 3
        return d.day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400
    }

    /// 每个月这个账本和别的账本之间净挪了多少钱（看「全部」时永远是空的）。
    /// 只算配上对、两边分属不同账本的转账，所以两个账本看到的数正好一正一负。
    /// 例子：从店里的 Caixa 转 400 € 到自己的 imagin。店账本这个月 −400（拿去个人的），个人账本 +400（从店里拿的）。
    public static func betweenBooks(_ txs: [Transaction], months: [YearMonth], bookID: String?,
                                    hiddenAccounts: Set<String> = []) -> [YearMonth: Money] {
        guard let bookID else { return [:] }
        let wanted = Set(months)
        var out: [YearMonth: Money] = [:]
        for tx in pairInternal(txs).crossBook where tx.bookID == bookID && !hiddenAccounts.contains(tx.accountID) {
            let m = tx.date.yearMonth
            guard wanted.contains(m) else { continue }
            out[m, default: .zero] = out[m, default: .zero] + tx.amount
        }
        return out.filter { $0.value.cents != 0 }
    }

    /// 这几个月里只记了一边的「自己账户间转账」：几笔、金额加起来多少（不分正负）。bookID 不填就是所有账本。
    /// 比如还信用卡只记了银行卡扣款、信用卡那边没记进账。这些钱没法确定去了哪个账本，所以不算进「从店里拿的」，单独提醒。
    public static func unmatchedInternal(_ txs: [Transaction], months: [YearMonth], bookID: String? = nil,
                                         hiddenAccounts: Set<String> = []) -> (count: Int, total: Money) {
        let wanted = Set(months)
        let list = pairInternal(txs).unpaired.filter {
            wanted.contains($0.date.yearMonth) && (bookID == nil || $0.bookID == bookID) && !hiddenAccounts.contains($0.accountID)
        }
        return (list.count, list.reduce(Money.zero) { $0 + $1.amount.magnitude })
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
