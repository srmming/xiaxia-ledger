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
        /// 到那个月底，大目标一共存了多少（小结里「过了哪一站」用）。没存就是 nil。
        public var goalSavedEnd: Money?
        /// 那个月店里一笔笔的流水（从正式账本整理过来时带上）。只有合计、没有逐笔的月份是空的。
        public var shopRows: [ShopFlowRow] = []
        /// 到那个月底，开店本钱一共赚回来多少（回本页那条线用）。没存就是 nil。
        public var shopBack: Money?
        /// 那个月每天花了多少（第 1 天…）。没存就是空的。
        public var daily: [Money] = []

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

    /// 照这样花，月底大概一共花掉多少：已经花掉的 + 平时一天花的 × 到月底还有几天。
    public var projectedMonthSpend: Money { month.spentTotal + Money(cents: usualDailySpend.cents * Int64(max(month.daysLeft, 0))) }
    /// 接下来要付的那几笔加起来（总览「接下来要付的」同一份）。
    public var upcomingTotal: Money { upcoming.map(\.amount.magnitude).reduce(.zero, +) }

    /// 花钱的速度：这个月到今天、上个月整月，一天天累计花了多少；每周平时花的。趋势页的折线和柱子都从这里来。
    public struct SpendPace: Equatable, Sendable {
        /// 这个月一共几天、今天几号。
        public var days: Int
        public var today: Int
        /// 这个月到每一天为止一共花掉多少（第 1 天…今天），最后一个数 = 这个月一共花掉。
        public var soFar: [Money]
        /// 上个月到每一天为止一共花掉多少。上个月没数就是空的。
        public var last: [Money]
        /// 照这样花到月底大概多少。
        public var projected: Money
        /// 每周平时花的（7 天一周）：这个月的（只到今天所在那周）、上个月的。
        public var weeks: [Money]
        public var lastWeeks: [Money]
        /// 画图时纵轴的顶：几条线里最大的那个数。
        public var top: Money { max(max(soFar.last ?? .zero, last.last ?? .zero), projected) }
        /// 和上个月同一天比，这个月花得慢（true）、快（false），比不了是 nil。
        public var slower: Bool? {
            guard let now = soFar.last, last.count >= 1 else { return nil }
            return now <= last[min(today, last.count) - 1]
        }
    }

    public var spendPace: SpendPace {
        let cal = Calendar(identifier: .gregorian)
        let days = cal.range(of: .day, in: .month, for: todayDate)?.count ?? 30
        let today = min(max(todayDay, 1), days)
        // 这个月：一笔笔按日子加；账本里记的总数（含没有逐笔流水的固定开销）比逐笔的多，多的算在 1 号
        var perDay = [Int64](repeating: 0, count: today), usual = [Int64](repeating: 0, count: today)
        for e in entries where e.side == .life && e.amount < .zero && e.daysAgo >= 0 && e.daysAgo < today {
            let i = today - 1 - e.daysAgo
            perDay[i] += e.amount.magnitude.cents
            usual[i] += max(e.amount.magnitude.cents - e.fixedPart.cents, 0)
        }
        // 账本里记的总数比逐笔流水多的那部分（没有逐笔流水的）：固定要付的算在 1 号，平时花的摊到每一天
        let usualGap = max(month.spent.cents - usual.reduce(0, +), 0)
        let fixedGap = max(month.spentTotal.cents - perDay.reduce(0, +) - usualGap, 0)
        perDay[0] += fixedGap
        if usualGap > 0 {
            for i in 0..<today {
                let share = usualGap * Int64(i + 1) / Int64(today) - usualGap * Int64(i) / Int64(today)
                perDay[i] += share; usual[i] += share
            }
        }
        func running(_ a: [Int64]) -> [Money] { var t: Int64 = 0; return a.map { t += $0; return Money(cents: t) } }
        func weekly(_ a: [Int64]) -> [Money] { stride(from: 0, to: a.count, by: 7).map { Money(cents: a[$0..<min($0 + 7, a.count)].reduce(0, +)) } }
        // 上个月：有每天的数就用；没有就照「同期花到多少、整月花了多少」连成线
        var last: [Money] = [], lastWeeks: [Money] = []
        if let p = previousMonthData {
            if !p.daily.isEmpty {
                last = running(p.daily.map(\.cents))
                lastWeeks = p.weekly.isEmpty ? weekly(p.daily.map(\.cents)) : p.weekly
            } else if p.spentTotal > .zero {
                let n = cal.range(of: .day, in: .month, for: cal.date(byAdding: .month, value: -1, to: todayDate) ?? todayDate)?.count ?? 30
                let mid = min(today, n), at = p.sameDaySpent ?? Money(cents: p.spentTotal.cents * Int64(mid) / Int64(n))
                last = (1...n).map { d in
                    d <= mid ? Money(cents: at.cents * Int64(d) / Int64(mid))
                             : Money(cents: at.cents + (p.spentTotal.cents - at.cents) * Int64(d - mid) / Int64(max(n - mid, 1)))
                }
                lastWeeks = p.weekly
            }
        }
        return SpendPace(days: days, today: today, soFar: running(perDay), last: last, projected: projectedMonthSpend,
                         weeks: weekly(usual), lastWeeks: lastWeeks)
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

    /// 过去某个月的生意流水：那个月存了逐笔的就是那些笔；没存的，只有补记进去的那几笔（按日子落在那个月里的）。这个月的用 `shopFlow`。
    public func shopFlow(in key: MonthKey) -> [ShopFlowRow] {
        guard key != thisMonth else { return shopFlow }
        if let rows = pastMonths.first(where: { $0.key == key })?.shopRows, !rows.isEmpty {
            return rows.sorted { ($0.day, $0.amount.cents) > ($1.day, $1.amount.cents) }
        }
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

    // MARK: 每月小结里的那几句话（都从那个月的数现算，没有的就不写）

    /// 小结里的一行：图标、一句话、下面的说明、右边的数（可以空着）。
    public struct MonthNote: Equatable, Sendable {
        public var emoji: String
        public var title: String
        public var detail: String
        public var amount: String
    }

    /// 那个月做得好的（最多 3 件）：净剩多了、比上个月少花、存进了目标、进账够花、哪一样少花得最多。
    public func monthGood(_ key: MonthKey) -> [MonthNote] {
        let d = monthData(key)
        let prev = pastMonths.first { $0.key == clampMonth(key).previous }
        var out: [MonthNote] = []
        let net = clampMonth(key) == thisMonth ? netMoreThanLastMonth : netChange(in: key)
        if let net, net > .zero { out.append(.init(emoji: "⭐", title: "家底多了", detail: "月底的净剩比上个月多", amount: "+" + net.formatted)) }
        // 过了哪一站：那个月里大目标存的钱跨过了路上的哪几站（站的位置是目标金额算出来的，不用另存）
        let end: Money? = clampMonth(key) == thisMonth ? journey.saved : pastMonths.first { $0.key == clampMonth(key) }?.goalSavedEnd
        if let end, let start = prev?.goalSavedEnd, end > start {
            let passed = journey.stations.filter { $0.target > start && $0.target <= end }
            if let last = passed.last {
                out.append(.init(emoji: "⭐", title: passed.count > 1 ? "过了 \(passed.count) 站" : "过了一站",
                                 detail: "「\(journey.name)」存到 \(last.target.formatted)" + (last.title.isEmpty ? "" : " · \(last.title)"), amount: ""))
            }
        }
        if d.forGoals > .zero { out.append(.init(emoji: "⭐", title: "存进了目标", detail: "先存下来，再花剩下的", amount: d.forGoals.formatted)) }
        if let prev, prev.spentTotal > d.spentTotal, d.spentTotal > .zero {
            out.append(.init(emoji: "⭐", title: "比上个月少花了", detail: "一共花掉 \(d.spentTotal.formatted)", amount: "−" + (prev.spentTotal - d.spentTotal).formatted))
        }
        if let best = d.slices.filter({ $0.lastMonth > $0.amount && $0.lastMonth > .zero }).max(by: { ($0.lastMonth - $0.amount) < ($1.lastMonth - $1.amount) }) {
            out.append(.init(emoji: "⭐", title: "\(best.name)少花了", detail: "上个月 \(best.lastMonth.formatted)", amount: "−" + (best.lastMonth - best.amount).formatted))
        }
        if d.income > .zero, d.left >= .zero, out.count < 3 {
            out.append(.init(emoji: "⭐", title: "进账够花", detail: "付完固定的、存完目标、花完平时的", amount: "还剩 " + d.left.formatted))
        }
        return Array(out.prefix(3))
    }

    /// 那个月要留意的（最多 1 件）：比上个月多花得最多的那一样；进账不够花也算。没有就是空的。
    public func monthWatch(_ key: MonthKey) -> [MonthNote] {
        let d = monthData(key)
        if d.income > .zero, d.left < .zero {
            return [.init(emoji: "👀", title: "花的比进的多", detail: "进账 \(d.income.formatted)", amount: "多花 " + d.left.magnitude.formatted)]
        }
        // 多花不到 10 € 的不提，免得大惊小怪
        guard let worst = d.slices.filter({ $0.amount > $0.lastMonth && $0.lastMonth > .zero && ($0.amount - $0.lastMonth).cents >= 10_00 })
            .max(by: { ($0.amount - $0.lastMonth) < ($1.amount - $1.lastMonth) }) else { return [] }
        return [.init(emoji: "👀", title: worst.name, detail: "上个月 \(worst.lastMonth.formatted)", amount: "+" + (worst.amount - worst.lastMonth).formatted)]
    }

    /// 那个月的生意流水是不是只有合计、没有一笔笔的：店里有收有花，但列不出逐笔。Mac 和手机都用这一个来判断。
    public func shopFlowIsTotalsOnly(in key: MonthKey) -> Bool {
        guard key != thisMonth, let d = pastMonths.first(where: { $0.key == key }) else { return false }
        return (d.shopIn > .zero || d.shopOut > .zero) && shopFlow(in: key).isEmpty
    }
    /// 只有合计的月份，流水那里就写这一行（Mac 和手机一样）。不是这种月份返回 nil。
    public func shopFlowTotalsLine(in key: MonthKey) -> String? {
        guard shopFlowIsTotalsOnly(in: key), let d = pastMonths.first(where: { $0.key == key }) else { return nil }
        return "\(key.label(thisYear: thisMonth.year))只有合计：收了 \(d.shopIn.formatted)，花了 \(d.shopOut.formatted)。一笔笔的没有存"
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
