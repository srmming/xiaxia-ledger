import Foundation

/// 每月固定进出：工资、房租、话费这类「每个月差不多同一天、差不多同样多」的钱。
/// 每次从流水现算，不存进记忆：涨薪了、搬家了，它自己跟着变，不会过时。
/// 记忆里只记流水看不出来的事（「明年要涨」「这笔是帮朋友垫的」）。
public struct Regular: Identifiable, Codable, Sendable, Equatable {
    /// 归一化后的付款方 / 商户名，前面带 + 或 -。
    public var id: String
    /// 给人看的名字（最近一笔的商户名）。
    public var name: String
    public var category: String?
    public var bookID: String?
    public var income: Bool
    /// 通常每次多少（主币种，正数）。
    public var typical: Money
    /// 通常每月哪天。
    public var day: Int
    /// 最近一年里有几个月出现过（最多 12）。
    public var months: Int
    public var last: LocalDate
    /// 多来一份的月份（1–12），比如 6 月、12 月的双薪。
    public var extraMonths: [Int]

    /// 一句话：「工资：每月 27 号前后进，约 1.380,00 €（最近一年每个月都有；6、12 月多一份）」。
    public func line(currency: String) -> String {
        var s = "\(name)：每月 \(day) 号前后\(income ? "进" : "扣")，约 \(typical.formatted(in: currency))（"
            + (months >= 12 ? "最近一年每个月都有" : "最近一年里有 \(months) 个月")
        if !extraMonths.isEmpty { s += "；\(extraMonths.map(String.init).joined(separator: "、")) 月多一份" }
        return s + "）"
    }
}

public enum Regulars {
    /// 从最近 12 个月的流水里找固定进出。条件：
    /// - 同一个付款方 / 商户，至少 3 个月出现过，而且从第一次到最近一次，大部分月份（七成以上）都有；
    /// - 最近 45 天内还出现过（停了的不算）；
    /// - 一个月基本只有一笔（一周去好几次的超市不算）；
    /// - 最近几次的金额差不多（收入上下 25% 以内，支出 20% 以内）。
    /// 借款、存目标、自己账户间转账、退款不算。`hidden` 里的账户（私房钱）不看。
    public static func detect(_ ledger: Ledger, today: LocalDate = .today, hidden: Set<String> = []) -> [Regular] {
        let start = today.yearMonth.adding(months: -12)
        var groups: [String: [Transaction]] = [:]
        for tx in ledger.baseTransactions {
            guard tx.flow == nil, !tx.isTransfer, tx.amount.cents != 0, tx.category != Transaction.refundCategory else { continue }
            guard tx.date.yearMonth >= start, tx.date <= today, !hidden.contains(tx.accountID) else { continue }
            let k = key(tx.description)
            guard !k.isEmpty else { continue }
            groups[(tx.amount.isIncome ? "+" : "-") + k, default: []].append(tx)
        }

        var out: [Regular] = []
        var used = Set<UUID>()
        for (gk, txs) in groups {
            var byMonth: [YearMonth: [Transaction]] = [:]
            for t in txs { byMonth[t.date.yearMonth, default: []].append(t) }
            let monthList = byMonth.keys.sorted()
            guard monthList.count >= 3, let first = monthList.first, let lastMonth = monthList.last else { continue }
            guard let latest = txs.max(by: { $0.date < $1.date }), latest.date.days(until: today) <= 45 else { continue }
            let span = (lastMonth.year * 12 + lastMonth.month) - (first.year * 12 + first.month) + 1
            guard Double(monthList.count) >= Double(span) * 0.7 else { continue }
            guard Double(txs.count) / Double(monthList.count) <= 1.5 else { continue }

            // 每个月挑最「像平常」的那一笔：金额最接近全部金额的中位数。
            let all = txs.map { $0.amount.magnitude.cents }.sorted()
            let mid = all[all.count / 2]
            var primary: [(month: YearMonth, tx: Transaction)] = []
            for m in monthList {
                if let best = byMonth[m]?.min(by: { abs($0.amount.magnitude.cents - mid) < abs($1.amount.magnitude.cents - mid) }) {
                    primary.append((m, best))
                }
            }
            // 看最近 6 次：金额差不多才算固定。
            let recent = primary.suffix(6)
            let recentAmounts = recent.map { $0.tx.amount.magnitude.cents }.sorted()
            let typical = recentAmounts[recentAmounts.count / 2]
            guard typical >= 300 else { continue }
            let income = gk.hasPrefix("+")
            let tolerance = max(200, Int64(Double(typical) * (income ? 0.25 : 0.20)))
            let steady = recent.filter { abs($0.tx.amount.magnitude.cents - typical) <= tolerance }.count
            guard steady >= max(3, Int((Double(recent.count) * 0.6).rounded(.up))) else { continue }

            let days = primary.map { $0.tx.date.day }.sorted()
            // 同一个月来了两笔差不多的：多来一份。
            var extra = Set<Int>()
            for (m, list) in byMonth where list.filter({ abs($0.amount.magnitude.cents - typical) <= tolerance }).count >= 2 { extra.insert(m.month) }
            for t in txs { used.insert(t.id) }
            out.append(Regular(id: gk, name: Merchant.display(latest.description), category: mostCommon(txs.compactMap(\.category)),
                               bookID: mostCommon(txs.compactMap(\.bookID)), income: income, typical: Money(cents: typical),
                               day: days[days.count / 2], months: min(12, monthList.count), last: latest.date, extraMonths: extra.sorted()))
        }

        // 同一个分类里、不在上面那几笔里、金额差不多的收入（「年中双薪」这种另起名字的）：也算多来一份。
        for i in out.indices where out[i].income {
            guard let c = out[i].category else { continue }
            let typical = out[i].typical.cents
            let tolerance = max(200, Int64(Double(typical) * 0.3))
            var extra = Set(out[i].extraMonths)
            for tx in ledger.baseTransactions where tx.category == c && tx.amount.isIncome && tx.flow == nil && !used.contains(tx.id) {
                guard tx.date.yearMonth >= start, tx.date <= today, !hidden.contains(tx.accountID) else { continue }
                if abs(tx.amount.cents - typical) <= tolerance { extra.insert(tx.date.month) }
            }
            out[i].extraMonths = extra.sorted()
        }

        return out.sorted { a, b in
            if a.income != b.income { return a.income }
            if a.typical.cents != b.typical.cents { return a.typical.cents > b.typical.cents }
            return a.name < b.name
        }
    }

    /// 给 AI 看的几行字（最多 12 行）。
    public static func lines(_ ledger: Ledger, today: LocalDate = .today, hidden: Set<String>? = nil) -> [String] {
        detect(ledger, today: today, hidden: hidden ?? ledger.privateAccountIDs).prefix(12).map { $0.line(currency: ledger.baseCurrency) }
    }

    /// 付款方 / 商户的归一化名字：去掉带数字的词，只留前两个词；全是数字或单个字的就用整句。
    static func key(_ description: String) -> String {
        let n = Dedup.normalize(description)
        let loose = Suggester.looseKey(n)
        return loose.isEmpty ? n : loose
    }

    static func mostCommon(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }
}
