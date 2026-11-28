import Foundation

/// 按月取数：总览、花销、趋势、小结、生意那几页切到哪个月，就从这里拿那个月的数。
/// 这个月的数是账本里现算的；过去的月份是存下来的那一份。最早到有数据的那个月，不能选还没到的月份。
extension TrialBook {
    public struct MonthKey: Hashable, Comparable, Sendable {
        public var year: Int
        public var month: Int
        public init(_ year: Int, _ month: Int) { self.year = year; self.month = month }
        public static func < (a: MonthKey, b: MonthKey) -> Bool { (a.year, a.month) < (b.year, b.month) }
        /// 「11 月」；不是今年的带上年份「2025 年 12 月」。
        public func label(thisYear: Int) -> String { year == thisYear ? "\(month) 月" : "\(year) 年 \(month) 月" }
        public var previous: MonthKey { month == 1 ? MonthKey(year - 1, 12) : MonthKey(year, month - 1) }
        public var next: MonthKey { month == 12 ? MonthKey(year + 1, 1) : MonthKey(year, month + 1) }
    }

    /// 一个月的数。
    public struct MonthData: Equatable, Sendable {
        public var key: MonthKey
        public var income: Money
        public var fixed: Money
        public var forGoals: Money
        /// 平时花的（不含固定要付的）。
        public var spent: Money
        public var slices: [SpendSlice]
        /// 这个月记的几笔（过去的月份只留几笔代表性的）。
        public var entries: [Entry]
        /// 每周平时花了多少（第 1 周…）。
        public var weekly: [Money]
        /// 店里这个月收的、花的。
        public var shopIn: Money
        public var shopOut: Money
        /// 月底的家底净剩。
        public var net: Money
        /// 月底一共有多少、欠多少（净剩 = 有 − 欠）。
        public var have: Money = .zero
        public var owe: Money = .zero
        /// 那个月花到「和今天同一天」时花了多少（「比上月同期」用）。没存就是 nil。
        public var sameDaySpent: Money?

        public init(key: MonthKey, income: Money, fixed: Money, forGoals: Money, spent: Money, slices: [SpendSlice] = [], entries: [Entry] = [],
                    weekly: [Money] = [], shopIn: Money = .zero, shopOut: Money = .zero, net: Money = .zero) {
            self.key = key; self.income = income; self.fixed = fixed; self.forGoals = forGoals; self.spent = spent
            self.slices = slices; self.entries = entries; self.weekly = weekly; self.shopIn = shopIn; self.shopOut = shopOut; self.net = net
        }

        /// 这个月一共花掉 = 固定的 + 平时的。
        public var spentTotal: Money { fixed + spent }
        /// 最后剩下（这个月还没过完时，就是现在还能随便花的）。
        public var left: Money { income - fixed - forGoals - spent }
        public var sliceTotal: Money { slices.map(\.amount).reduce(.zero, +) }
        /// 圆环上的几段：按花得多少排，最多 `limit` 段，多出来的合成「其他」。
        public func topSlices(limit: Int = 8) -> [SpendSlice] {
            let sorted = slices.filter { $0.amount > .zero }.sorted { $0.amount > $1.amount }
            guard sorted.count > limit, limit > 1 else { return sorted }
            let rest = sorted[(limit - 1)...]
            return Array(sorted[..<(limit - 1)]) + [SpendSlice(emoji: "❓", name: "其他", amount: rest.map(\.amount).reduce(.zero, +), lastMonth: rest.map(\.lastMonth).reduce(.zero, +))]
        }
    }

    /// 上个月的数（没有就是 nil）。
    public var previousMonthData: MonthData? { pastMonths.first { $0.key == thisMonth.previous } }
    /// 比上个月同一天少花了多少（负数是多花了）。上个月没存同期的数就是 nil，界面上就不写这一句。
    public var spentLessThanLastMonthSameDay: Money? { previousMonthData?.sameDaySpent.map { $0 - month.spentTotal } }
    /// 家底净剩比上个月底多了多少（负数是少了）。
    public var netMoreThanLastMonth: Money? { previousMonthData.flatMap { $0.have > .zero || $0.owe > .zero ? totals.net - $0.net : nil } }
    /// 某个月底的净剩比再前一个月底多了多少。
    public func netChange(in key: MonthKey) -> Money? {
        guard let a = pastMonths.first(where: { $0.key == key }), let b = pastMonths.first(where: { $0.key == key.previous }),
              a.have > .zero || a.owe > .zero, b.have > .zero || b.owe > .zero else { return nil }
        return a.net - b.net
    }

    /// 今天在哪个月。
    public var thisMonth: MonthKey {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: todayDate)
        return MonthKey(c.year ?? 2026, c.month ?? 1)
    }

    /// 能选的月份，从最早有数据的那个月到这个月，一个不漏（中间没数据的月份也在，数是 0）。
    public var months: [MonthKey] {
        var out: [MonthKey] = []
        var k = pastMonths.map(\.key).min() ?? thisMonth
        while k <= thisMonth { out.append(k); k = k.next }
        return out
    }

    /// 把一个月份拉回到能选的范围里：比最早的还早就是最早的那个月，还没到的就是这个月。
    public func clampMonth(_ key: MonthKey) -> MonthKey {
        let all = months
        return min(max(key, all.first ?? thisMonth), thisMonth)
    }

    /// 某个月的数。这个月是现算的；过去的月份拿存下来的；中间没数据的月份全是 0。
    public func monthData(_ key: MonthKey) -> MonthData {
        let k = clampMonth(key)
        if k == thisMonth {
            return MonthData(key: k, income: month.income, fixed: month.fixed, forGoals: month.forGoals, spent: month.spent,
                             slices: spendByCategory, entries: entries.filter { $0.side == .life && $0.daysAgo < todayDay },
                             weekly: [], shopIn: shopFlowIn, shopOut: shopFlowOut, net: totals.net)
        }
        return pastMonths.first { $0.key == k } ?? MonthData(key: k, income: .zero, fixed: .zero, forGoals: .zero, spent: .zero)
    }

    /// 过去某个月的生意流水：只有补记进去的那些笔（按日子落在那个月里的）。这个月的用 `shopFlow`。
    public func shopFlow(in key: MonthKey) -> [ShopFlowRow] {
        guard key != thisMonth else { return shopFlow }
        let cal = Calendar(identifier: .gregorian)
        return entries.compactMap { e -> ShopFlowRow? in
            guard e.side == .biz, let date = cal.date(byAdding: .day, value: -e.daysAgo, to: todayDate) else { return nil }
            let c = cal.dateComponents([.year, .month, .day], from: date)
            guard c.year == key.year, c.month == key.month else { return nil }
            return ShopFlowRow(id: e.id.uuidString, emoji: e.emoji, title: e.name, detail: [e.place, e.account].filter { !$0.isEmpty }.joined(separator: " · "),
                               amount: e.amount, day: c.day ?? 1, entryID: e.id)
        }
        .sorted { ($0.day, $0.amount.cents) > ($1.day, $1.amount.cents) }
    }

    // MARK: 意外开销（用的是正式账本那条「一次性开销」规则，见 Outlook.isUnusual）

    /// 这个月的意外开销：这个月记的每一笔支出里，手动标过的按标的；没标的按规则（比同类平常贵 3 倍多，或者一笔占这个月花销一成以上）。固定要付的不算。贵的在前。
    public func surprises(in key: MonthKey) -> [Entry] {
        let d = monthData(key)
        let fixedNames: Set<String> = ["房租", "手机分期", "订阅"]
        // 同类以前记过的：账本里更早的 + 以前月份存下来的
        let older = entries.filter { $0.side == .life } + pastMonths.filter { $0.key < d.key }.flatMap(\.entries)
        return d.entries.filter { e in
            guard e.side == .life, e.amount < .zero else { return false }
            if let mark = surpriseMarks[e.id] { return mark }
            guard !fixedNames.contains(e.name) else { return false }
            let same = older.filter { $0.id != e.id && $0.name == e.name && $0.daysAgo > e.daysAgo }.map { $0.amount.magnitude.cents }
            return Outlook.isUnusual(amount: e.amount.magnitude.cents, sameCategory: same, monthly: d.spentTotal.cents)
        }
        .sorted { $0.amount < $1.amount }
    }

    /// 手动改：这笔算 / 不算意外开销。
    public mutating func markSurprise(_ id: UUID, _ on: Bool) throws {
        guard entries.contains(where: { $0.id == id }) || pastMonths.contains(where: { $0.entries.contains { $0.id == id } }) else { throw TrialError("这一笔已经不在了") }
        surpriseMarks[id] = on
    }
}
