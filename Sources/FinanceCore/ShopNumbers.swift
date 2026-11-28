import Foundation

/// 店里的几个大数，每个数只有这一处算法。Mac 和手机的生意首页、流水、回本、体检、固定开销都从这里拿，记一笔以后一起变。
extension TrialBook {
    /// 这个月店里的账。
    public struct ShopMonth: Equatable, Sendable {
        /// 收的（营业额）。
        public var income: Money
        /// 开销（房租、水电、工资、广告…），不含进货。
        public var costs: Money
        /// 进的货。
        public var purchases: Money
        /// 这个月还的贷款。
        public var loanPaid: Money
        /// 真正赚了 = 收的 − 开销。进货不算（货还在店里，卖掉才算）；还贷款不算（那是还钱，不是花掉）。
        public var earned: Money { income - costs }
        /// 手里实际多了 = 真正赚了 − 进的货 − 还的贷款。
        public var cashChange: Money { earned - purchases - loanPaid }
        /// 花出去的一共（开销 + 进货），流水页「花了」用。
        public var out: Money { costs + purchases }
    }

    /// 某个月店里的账：从流水里现算。这个月的贷款月供按 `shopLoanMonthly` 算。
    public func shopMonth(_ key: MonthKey? = nil) -> ShopMonth {
        let k = key.map(clampMonth) ?? thisMonth
        guard k == thisMonth else {
            let d = monthData(k)
            return ShopMonth(income: d.shopIn, costs: d.shopOut, purchases: .zero, loanPaid: .zero)
        }
        let rows = shopFlow
        let income = rows.filter { $0.amount > .zero }.map(\.amount).reduce(.zero, +)
        let purchases = rows.filter { $0.amount < .zero && $0.title == Self.purchaseCategory }.map(\.amount).reduce(.zero, +).magnitude
        let out = rows.filter { $0.amount < .zero }.map(\.amount).reduce(.zero, +).magnitude
        return ShopMonth(income: income, costs: out - purchases, purchases: purchases, loanPaid: shopLoanMonthly)
    }
    public static let purchaseCategory = "进货"

    /// 这个月进的货，一笔一行（货值页用；和流水是同一份）。
    public var purchasesThisMonth: [ShopFlowRow] { shopFlow.filter { $0.amount < .zero && $0.title == Self.purchaseCategory } }

    /// 这个月打算开门几天：照到今天为止「开门的日子占几成」推到月底（休息的那几天不算）。
    public var plannedOpenDays: Int {
        let past = shopDays.filter { $0.day <= todayDay }
        let rest = past.filter { $0.state == .rest }.count
        guard !past.isEmpty, !shopDays.isEmpty else { return 0 }
        return max(Int((Double(past.count - rest) / Double(past.count) * Double(shopDays.count)).rounded()), 1)
    }

    /// 每个开门的日子要收多少才不亏：这个月固定要付的 + 贷款月供 + 这个月进的货，除以打算开门的天数（休息日不算）。往上凑到整欧元。
    public var dailyBreakEven: Money {
        let days = plannedOpenDays
        guard days > 0 else { return .zero }
        let need = fixedTotal + shopLoanMonthly + shopMonth().purchases
        return Money(cents: (need.cents / Int64(days) + 99) / 100 * 100)
    }

    /// 开店本钱已经赚回来多少 = 以前赚回来的 + 这个月真正赚的（亏了不往回扣）。
    public var shopBack: Money { shopBackBefore + max(shopMonth().earned, .zero) }
    public var paybackLeft: Money { max(capitalTotal - shopBack, .zero) }
    public var paybackFraction: Double { capitalTotal > .zero ? min(Double(shopBack.cents) / Double(capitalTotal.cents), 1) : 0 }
    /// 一期一期还的欠款带的记号（从正式账本整理过来时打上）。
    public static let paidMonthlyTags: Set<String> = ["分期", "按月还"]

    /// 回本按多快算：前三个整月平均每月真正赚的（和旧界面一个口径，月初也稳）。没有满三个月的数，就用这个月到今天赚的。
    public var paybackSpeed: (perMonth: Money, fromLastThree: Bool) {
        let keys = [thisMonth.previous, thisMonth.previous.previous, thisMonth.previous.previous.previous]
        // 有「每个月底一共赚回来多少」的数：三个月里多赚回来的 ÷ 3，和回本进度是同一本账
        func back(_ k: MonthKey) -> Money? { pastMonths.first { $0.key == k }?.shopBack }
        if let end = back(keys[0]), let start = back(keys[2].previous) { return (Money(cents: (end - start).cents / 3), true) }
        let past = keys.compactMap { k in pastMonths.first { $0.key == k && ($0.shopIn > .zero || $0.shopOut > .zero) } }
        guard past.count == 3 else { return (shopMonth().earned, false) }
        let sum = past.map { $0.shopIn - $0.shopOut }.reduce(.zero, +)
        return (Money(cents: sum.cents / 3), true)
    }
    /// 回本速度是怎么来的，一句话。
    public var paybackSpeedNote: String { paybackSpeed.fromLastThree ? "照前三个月平均赚的速度" : "照这个月赚的速度" }

    /// 回本那条线：过去每个月底一共赚回来多少，最后一个是今天。月份从早到晚。
    public var paybackCurve: [(key: MonthKey, back: Money)] {
        pastMonths.filter { $0.shopBack != nil }.sorted { $0.key < $1.key }.map { ($0.key, $0.shopBack ?? .zero) } + [(thisMonth, shopBack)]
    }

    /// 还要几个月回本（速度见 `paybackSpeed`）。没赚到钱就算不出来（nil）。`extra` 是「每月多赚这么多」时的情况。
    public func paybackMonths(extra: Money = .zero) -> Int? {
        let speed = paybackSpeed.perMonth + extra
        guard speed > .zero else { return nil }
        return Int((Double(paybackLeft.cents) / Double(speed.cents)).rounded(.up))
    }

    /// 照这个月赚的速度，哪个月回本（「2027 年 9 月」）。已经回本了是「已经回本」；算不出来是 nil。
    /// 生意首页、回本页都用这一个，两处写的日子一定一样。
    public func paybackDateLabel(extra: Money = .zero) -> String? {
        guard capitalTotal > .zero else { return nil }
        if paybackLeft == .zero { return "已经回本" }
        guard let n = paybackMonths(extra: extra), n < 1200 else { return nil }
        let cal = Calendar(identifier: .gregorian)
        guard let d = cal.date(byAdding: .month, value: n, to: todayDate) else { return nil }
        let c = cal.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0) 年 \(c.month ?? 0) 月"
    }

    /// 不亏线是怎么算出来的，一句话（鼠标移上去才看）：实际算进去的几样和各是多少。
    public var breakEvenNote: String {
        let parts = [("每月固定要付的", fixedTotal), ("每月要还的", shopLoanMonthly), ("这个月进的货", shopMonth().purchases)].filter { $0.1 > .zero }
        guard !parts.isEmpty, plannedOpenDays > 0 else { return "还没有要付的，所以不亏线是 0" }
        return parts.map { "\($0.0) \($0.1.formatted)" }.joined(separator: " + ") + "，除以这个月打算开门的 \(plannedOpenDays) 天（休息的日子不算）"
    }

    /// 营业额每 100 € 去哪了：房租、进货、别的开销、剩下的。四个数加起来是 100。没有营业额就是空的。
    public var shopPer100: [(name: String, euros: Int)] {
        let m = shopMonth()
        guard m.income > .zero else { return [] }
        let rent = shopFlow.filter { $0.amount < .zero && ($0.title == "房租" || $0.title == "店租") }.map(\.amount).reduce(.zero, +).magnitude
        func part(_ x: Money) -> Int { Int((Double(x.cents) / Double(m.income.cents) * 100).rounded()) }
        let a = part(rent), b = part(m.purchases), c = part(m.costs - rent)
        return [("房租", a), ("进货", b), ("别的开销", c), ("剩下的", 100 - a - b - c)]
    }

    /// 一周里每天平均收多少（周一到周日）。没开过门的那天是 0。
    public var shopWeekdayAverages: [Money] {
        let cal = Calendar(identifier: .gregorian)
        var sums = [Int64](repeating: 0, count: 7), counts = [Int](repeating: 0, count: 7)
        for d in shopDays where d.state == .open {
            guard let date = cal.date(byAdding: .day, value: d.day - todayDay, to: todayDate) else { continue }
            let w = (cal.component(.weekday, from: date) + 5) % 7   // 周一 = 0
            sums[w] += d.total.cents; counts[w] += 1
        }
        return (0..<7).map { counts[$0] > 0 ? Money(cents: sums[$0] / Int64(counts[$0])) : .zero }
    }

    /// 店一共欠多少：欠款账户（贷款、店的信用卡）+ 赊着没还的。Mac 和手机都用这一个数。
    public var shopOwesTotal: Money { shopOwedAccounts.map(\.balance).reduce(.zero, +) + shopDebts.filter { !$0.flag && !$0.off }.map(\.amount).reduce(.zero, +) }
    /// 下个月店里要还的：贷款月供 + 店的信用卡 + 赊着没还的。
    public var shopDueNext: Money {
        shopLoanMonthly + shopOwedAccounts.filter(\.isCreditCard).map(\.balance).reduce(.zero, +)
            // 一期一期还的（分期、排了计划的贷款）这个月该还的那一期已经在「每月要还的」里了，不再把整笔算进来
            + shopDebts.filter { !$0.flag && !$0.off && !Self.paidMonthlyTags.contains($0.tag) }.map(\.amount).reduce(.zero, +)
    }
}
