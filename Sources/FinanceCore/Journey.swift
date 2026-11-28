import Foundation

// 界面 v3 用的几条算账规则（2026-11-27 设计稿「夏夏账本 Mac 界面 v3」）。
// 都是加减乘除，不用 AI；界面只调用这里，不自己算。

/// 目标的路：一个大目标拆成几站，第一站很小。
public struct Journey: Equatable, Sendable {
    public struct Station: Equatable, Sendable, Identifiable {
        public var id: Int
        /// 存到多少算到这一站。出发那一站是 0。
        public var target: Money
        /// 站名：「出发」「第一步」「电脑到手」；可以空着。
        public var title: String
        public init(id: Int, target: Money, title: String = "") {
            self.id = id; self.target = target; self.title = title
        }
    }

    public var name: String
    /// 为了什么（「为了剪自己的片子」）。
    public var why: String
    /// 从出发（0）到终点，按金额从小到大。
    public var stations: [Station]
    public var saved: Money
    /// 每月打算存多少。
    public var monthlyPlan: Money
    public var savedThisMonth: Money
    /// 忍住没买的次数。
    public var resisted: Int

    public init(name: String, why: String = "", stations: [Station], saved: Money = .zero,
                monthlyPlan: Money = .zero, savedThisMonth: Money = .zero, resisted: Int = 0) {
        self.name = name; self.why = why
        self.stations = stations.sorted { $0.target < $1.target }
        self.saved = saved; self.monthlyPlan = monthlyPlan; self.savedThisMonth = savedThisMonth; self.resisted = resisted
    }

    /// 用几个金额直接搭一条路：`[50, 200, 700, 1050, 1400]`，前面自动加「出发」。
    public init(name: String, why: String = "", stops: [Money], saved: Money = .zero, monthlyPlan: Money = .zero) {
        var list = [Station(id: 0, target: .zero, title: "出发")]
        for (i, m) in stops.sorted().enumerated() where m > .zero { list.append(Station(id: i + 1, target: m)) }
        self.init(name: name, why: why, stations: list, saved: saved, monthlyPlan: monthlyPlan)
    }

    public var total: Money { stations.last?.target ?? .zero }
    public var isFinished: Bool { saved >= total }

    /// 正在走向哪一站（下标）。全走完了是最后一站。
    public var nextIndex: Int {
        stations.firstIndex { $0.target > saved } ?? max(stations.count - 1, 0)
    }
    public var nextStation: Station? { stations.indices.contains(nextIndex) ? stations[nextIndex] : nil }

    /// 到下一站还差多少（到了就是 0）。
    public var remainingToNext: Money {
        guard let next = nextStation else { return .zero }
        return max(next.target - saved, .zero)
    }
    public var remainingToEnd: Money { max(total - saved, .zero) }

    /// 路上走到哪了：已经过了第几站（下标），往下一站走了几成（0…1）。
    public var position: (passed: Int, fraction: Double) {
        guard stations.count > 1 else { return (0, 0) }
        if isFinished { return (stations.count - 1, 0) }
        let next = nextIndex
        let from = stations[max(next - 1, 0)].target
        let span = stations[next].target - from
        guard span > .zero else { return (max(next - 1, 0), 0) }
        let f = Double((saved - from).cents) / Double(span.cents)
        return (max(next - 1, 0), min(max(f, 0), 1))
    }

    /// 整条路走了几成（按金额）。
    public var overallFraction: Double {
        total > .zero ? min(max(Double(saved.cents) / Double(total.cents), 0), 1) : 0
    }

    /// 存一笔。返回这一笔刚到的站（可能一次过好几站）。
    @discardableResult
    public mutating func deposit(_ amount: Money) -> [Station] {
        guard amount > .zero else { return [] }
        let before = saved
        saved = saved + amount
        savedThisMonth = savedThisMonth + amount
        return stations.filter { $0.target > before && $0.target <= saved }
    }

    /// 步子减半的选项：200 → 100、50。不到 1 块就不再减。
    public static func smallerSteps(from plan: Money, count: Int = 2) -> [Money] {
        var out: [Money] = []
        var cur = plan
        for _ in 0..<count {
            cur = Money(cents: cur.cents / 2)
            guard cur.cents >= 100 else { break }
            out.append(cur)
        }
        return out
    }

    /// 从下个月起每月存 `monthly`（其中第一个月只存 `firstMonth`），还要几个月走完。走不完返回 nil。
    public func monthsToFinish(monthly: Money? = nil, firstMonth: Money? = nil) -> Int? {
        let plan = monthly ?? monthlyPlan
        var left = remainingToEnd
        if left <= .zero { return 0 }
        var months = 0
        if let firstMonth {
            left = left - firstMonth
            months = 1
            if left <= .zero { return months }
        }
        guard plan > .zero else { return nil }
        months += Int((left.cents + plan.cents - 1) / plan.cents)
        return months
    }

    /// 下个月只存 `smaller`、之后照旧，终点晚几个月（0 = 不变）。
    public func delayMonths(ifNextMonthIs smaller: Money) -> Int? {
        guard let base = monthsToFinish(), let changed = monthsToFinish(firstMonth: smaller) else { return nil }
        return max(changed - base, 0)
    }
}

/// 家底三个数：一共有、欠别人、净剩。
public struct HouseholdTotals: Equatable, Sendable {
    public var have: Money
    public var owe: Money
    public var net: Money { have - owe }

    public init(have: Money, owe: Money) { self.have = have; self.owe = owe }

    /// `holdings` 是手里的钱（余额），`debts` 是欠别人的（都写正数）。借给别人的不算进「有」。
    public init(holdings: [Money], debts: [Money]) {
        self.init(have: holdings.reduce(.zero, +), owe: debts.reduce(.zero) { $0 + $1.magnitude })
    }
}

/// 这个月还能随便花多少 = 进账 − 固定要付的 − 留给目标的 − 已经花掉的。
public struct FreeToSpend: Equatable, Sendable {
    public var income: Money
    public var fixed: Money
    public var forGoals: Money
    public var spent: Money
    public var daysLeft: Int
    /// 固定要付的里面，这个月还没到日子、还没付的那部分。「还能随便花」照样先给它留着，但它还不算「花掉」。
    public var fixedLeft: Money = .zero

    public init(income: Money, fixed: Money, forGoals: Money, spent: Money, daysLeft: Int, fixedLeft: Money = .zero) {
        self.income = income; self.fixed = fixed; self.forGoals = forGoals; self.spent = spent; self.daysLeft = daysLeft
        self.fixedLeft = fixedLeft
    }

    public var left: Money { income - fixed - forGoals - spent }
    /// 平均每天能花（到月底还有几天就除以几；花超了是 0）。
    public var perDay: Money {
        guard daysLeft > 0, left > .zero else { return .zero }
        return Money(cents: left.cents / Int64(daysLeft))
    }
    /// 固定要付的里已经付掉的。
    public var fixedPaid: Money { max(fixed - fixedLeft, .zero) }
    /// 这个月到今天一共花掉 = 固定的里已经付的 + 平时的。还没到日子的固定开销不算（它在「接下来要付的」里）。
    public var spentTotal: Money { fixedPaid + spent }
}

/// 应急钱：万一没了收入能撑几个月。
public struct EmergencyRunway: Equatable, Sendable {
    public var fund: Money
    /// 每月必须花的（房租、吃饭、分期、话费）。
    public var monthlyMust: Money

    public init(fund: Money, monthlyMust: Money) { self.fund = fund; self.monthlyMust = monthlyMust }

    public var months: Double {
        monthlyMust > .zero ? Double(fund.cents) / Double(monthlyMust.cents) : 0
    }
    /// 「2,8」这样的一位小数（逗号小数点）。
    public var monthsText: String {
        let tenths = Int((months * 10).rounded())
        return "\(tenths / 10),\(tenths % 10)"
    }
    /// 进度条：按 6 个月算满。
    public func fraction(of goalMonths: Double = 6) -> Double {
        goalMonths > 0 ? min(max(months / goalMonths, 0), 1) : 0
    }
}
