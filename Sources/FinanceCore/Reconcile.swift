import Foundation

/// 对账结果：账本算出来的余额和银行对账单上的余额差多少、可能差在哪几笔。
public struct Reconciliation: Codable, Sendable, Equatable {
    public var accountID: String
    public var accountName: String
    public var asOf: LocalDate
    public var ledgerBalance: Money
    public var statementBalance: Money
    /// 对账单 − 账本。正数 = 账本少记了钱，负数 = 账本多记了钱。
    public var difference: Money
    /// 这个账户到这一天为止有几笔、最后一笔是哪天。
    public var count: Int
    public var lastDate: LocalDate?
    /// 可能的原因，一句一条，大白话。
    public var hints: [String]
    /// 可疑的流水（重复的、金额正好等于差额的）。
    public var suspects: [Transaction]

    public var matches: Bool { difference.cents == 0 }
}

public enum Reconcile {
    /// 拿银行那边某一天的余额，和账本里这个账户到那天为止的余额比。只看不改。
    public static func check(_ ledger: Ledger, accountID: String, statementBalance: Money, asOf: LocalDate) throws -> Reconciliation {
        guard let account = ledger.accounts.first(where: { $0.id == accountID }) else { throw EditError.unknownAccount(accountID) }
        let txs = ledger.transactions.filter { $0.accountID == accountID && $0.date <= asOf }
        let balance = txs.reduce(Money.zero) { $0 + $1.amount }
        let diff = statementBalance - balance
        var hints: [String] = []
        var suspects: [Transaction] = []

        if diff.cents != 0 {
            if !txs.contains(where: { $0.flow == .opening }) {
                hints.append("这个账户还没有期初余额。如果开始记账前账户里就有钱，差额 \(diff.formatted) 可能就是期初余额。")
            }
            // 账本里多了一笔：去掉它正好对上。
            let extra = txs.filter { $0.amount == -diff }
            if !extra.isEmpty {
                hints.append("有 \(extra.count) 笔金额正好是 \((-diff).formatted)：可能是多记或重复的一笔。")
                suspects += extra
            }
            // 正负号记反了：改过来正好对上。
            if diff.cents % 2 == 0 {
                let flipped = txs.filter { $0.amount.cents * -2 == diff.cents }
                if !flipped.isEmpty {
                    hints.append("有 \(flipped.count) 笔金额是差额的一半：可能把收入和支出记反了。")
                    suspects += flipped
                }
            }
            // 同一天、同金额、同说明的重复。
            var seen: [String: Transaction] = [:]
            var dupes: [Transaction] = []
            for t in txs {
                let key = "\(t.date)|\(t.amount.cents)|\(Dedup.normalize(t.description))"
                if seen[key] != nil { dupes.append(t) } else { seen[key] = t }
            }
            if !dupes.isEmpty {
                hints.append("有 \(dupes.count) 笔看起来重复（同一天、同金额、同说明），合计 \(dupes.reduce(Money.zero) { $0 + $1.amount }.formatted)。")
                suspects += dupes
            }
            if hints.isEmpty {
                hints.append(diff.cents > 0 ? "账本比银行少 \(diff.formatted)：可能有收入没导入，或多记了支出。"
                                            : "账本比银行多 \((-diff).formatted)：可能有支出没导入，或多记了收入。")
            }
        }
        var unique: [Transaction] = []
        for t in suspects where !unique.contains(where: { $0.id == t.id }) { unique.append(t) }
        return Reconciliation(accountID: accountID, accountName: account.name, asOf: asOf, ledgerBalance: balance,
                              statementBalance: statementBalance, difference: diff, count: txs.count,
                              lastDate: txs.map(\.date).max(), hints: hints, suspects: Array(unique.prefix(20)))
    }

    public static func text(_ r: Reconciliation) -> String {
        var lines = ["对账：\(r.accountName)，截至 \(r.asOf)",
                     "银行余额 \(r.statementBalance.formatted)",
                     "账本余额 \(r.ledgerBalance.formatted)（\(r.count) 笔" + (r.lastDate.map { "，最后一笔 \($0)" } ?? "") + "）"]
        if r.matches {
            lines.append("对上了，一分不差。")
        } else {
            lines.append("差 \(r.difference.formatted)（银行 − 账本）")
            lines += r.hints.map { "· \($0)" }
            if !r.suspects.isEmpty {
                lines.append("可疑的流水：")
                lines += r.suspects.map { "  \($0.id.uuidString.prefix(8).lowercased())  \($0.date)  \($0.amount.formatted)  \($0.description)" }
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// 月报：一份能直接读的文字，给 ming 看，也给 AI 转述。
public enum MonthlyReport {
    public static func text(_ ledger: Ledger, month: YearMonth, bookID: String?, hiddenAccounts: Set<String> = [],
                            today: LocalDate = .today) -> String {
        let txs = ledger.transactions
        let now = Summaries.monthly(txs, month: month, bookID: bookID, hiddenAccounts: hiddenAccounts)
        let before = Summaries.monthly(txs, month: month.adding(months: -1), bookID: bookID, hiddenAccounts: hiddenAccounts)
        let bookName = bookID.flatMap { id in ledger.books.first { $0.id == id }?.name } ?? "全部账本"
        var lines = ["# \(month.year) 年 \(month.month) 月 · \(bookName)", ""]

        lines.append("进账 \(now.income.formatted)，花掉 \(now.expense.magnitude.formatted)，剩下 \(now.net.formatted)。")
        if before.income.cents != 0 || before.expense.cents != 0 {
            let d = now.expense.magnitude - before.expense.magnitude
            let word = d.cents == 0 ? "和上个月花得一样多" : (d.cents > 0 ? "比上个月多花 \(d.formatted)" : "比上个月少花 \(d.magnitude.formatted)")
            lines.append("\(word)（上个月花掉 \(before.expense.magnitude.formatted)）。")
        }
        if let rate = Plans.savingsRate(now) { lines.append("存下 \(rate)%。") }
        if let bookID, now.betweenBooks.cents != 0 {
            let label = Reports.betweenBooksLabel(now.betweenBooks, bookID: bookID, books: ledger.books)
            lines.append("\(label) \(now.betweenBooks.magnitude.formatted)（自己账户之间挪的钱，不算收入也不算支出）。算上它实际剩下 \(now.netWithBetweenBooks.formatted)。")
        }

        let spending = Reports.categoryTotals([now], expense: true)
        if !spending.isEmpty {
            lines += ["", "## 钱花在哪"]
            let total = max(now.expense.magnitude.cents, 1)
            for c in spending.prefix(8) {
                let share = Int((Double(c.amount.cents) / Double(total) * 100).rounded())
                var line = "- \(c.name) \(c.amount.formatted)（\(share)%）"
                let old = (before.byCategory[c.name] ?? .zero)
                if old.isExpense {
                    let d = c.amount - old.magnitude
                    if abs(d.cents) >= 1000 { line += d.cents > 0 ? "，比上个月多 \(d.formatted)" : "，比上个月少 \(d.magnitude.formatted)" }
                } else if before.expense.cents != 0 {
                    line += "，上个月没有"
                }
                lines.append(line)
            }
            if spending.count > 8 {
                let rest = spending.dropFirst(8).reduce(Money.zero) { $0 + $1.amount }
                lines.append("- 其余 \(spending.count - 8) 类 \(rest.formatted)")
            }
        }

        let earning = Reports.categoryTotals([now], expense: false)
        if !earning.isEmpty {
            lines += ["", "## 钱从哪来"]
            lines += earning.prefix(6).map { "- \($0.name) \($0.amount.formatted)" }
        }

        let inMonth = txs.filter { t in
            guard t.date.yearMonth == month, t.countsAsIncomeOrExpense, !hiddenAccounts.contains(t.accountID) else { return false }
            if let bookID { return t.bookID == bookID }
            return !t.isTransfer
        }
        let biggest = inMonth.filter { $0.amount.isExpense }.sorted { $0.amount < $1.amount }.prefix(5)
        if !biggest.isEmpty {
            lines += ["", "## 最大的几笔"]
            lines += biggest.map { "- \($0.date) \($0.description) \($0.amount.magnitude.formatted)（\($0.category ?? "没分类")）" }
        }

        var todo: [String] = []
        let untidy = txs.filter { $0.date.yearMonth == month && $0.flow == nil && !$0.isTransfer && ($0.category == nil || $0.bookID == nil)
                                  && !hiddenAccounts.contains($0.accountID) }
        if !untidy.isEmpty { todo.append("\(untidy.count) 笔流水还没分类或没分账本，上面的数字会不准。") }
        for d in Plans.debts(ledger, today: today) where d.overdue {
            todo.append(d.direction == .theyOweMe ? "\(d.counterparty) 还欠你 \(d.outstanding.formatted)，已经过了约定的日子。"
                                                  : "你还欠 \(d.counterparty) \(d.outstanding.formatted)，已经过了约定的日子。")
        }
        for i in Plans.installments(ledger) where i.remaining.cents > 0 {
            if let next = i.nextDate { todo.append("分期「\(i.name)」下次 \(next) 扣 \(i.perPayment.formatted)，还剩 \(i.remaining.formatted)。") }
        }
        for g in Plans.goals(ledger) where g.percent < 100 {
            todo.append("目标「\(g.name)」存了 \(g.saved.formatted) / \(g.target.formatted)（\(g.percent)%）。")
        }
        if !todo.isEmpty {
            lines += ["", "## 要留意"]
            lines += todo.map { "- \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}
