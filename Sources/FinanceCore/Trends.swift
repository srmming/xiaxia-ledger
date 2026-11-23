import Foundation

/// 趋势页和家底页的算法：悄悄变多的开销、钱在哪（能随时用的 / 存着的 / 店里的 / 欠款）。
public enum Trends {
    /// 一类开销连着几个月在涨。
    public struct Creep: Equatable, Sendable, Identifiable {
        public var category: String
        /// 连着涨了几个月（至少 2）。
        public var months: Int
        /// 开始涨之前那个月花了多少、最近一个整月花了多少。
        public var before: Money
        public var now: Money
        public var since: YearMonth
        public var extra: Money { now - before }
        public var id: String { category }
    }

    /// 找连续几个月在涨的分类，最多 3 条，按多出来的钱从多到少。
    /// - months: 只传过完的整月，从早到晚（正在过的这个月还没花完，不能比）。
    /// - 固定开销（房租、工资、税……）和订阅不算；每次至少涨 3 €，一共至少多出 20 € 才算。
    public static func creeping(_ months: [MonthlySummary], limit: Int = 3) -> [Creep] {
        let list = months.sorted { $0.month < $1.month }
        guard list.count >= 3 else { return [] }
        var names = Set<String>()
        for s in list { for (k, v) in s.byCategory where v.isExpense { names.insert(k) } }
        var out: [Creep] = []
        for name in names where !Subscriptions.fixedCostCategories.contains(name) && name != "订阅" {
            let series = list.map { max(0, -($0.byCategory[name]?.cents ?? 0)) }
            var rises = 0
            var i = series.count - 1
            while i > 0, series[i] - series[i - 1] >= 300 { rises += 1; i -= 1 }
            guard rises >= 2, let last = series.last, last - series[i] >= 2000 else { continue }
            out.append(Creep(category: name, months: rises, before: Money(cents: series[i]), now: Money(cents: last), since: list[i].month))
        }
        return Array(out.sorted { ($0.extra.cents, $1.category) > ($1.extra.cents, $0.category) }.prefix(limit))
    }

    /// 平均每月存下多少（进账减花掉）。没有月份就是 0。
    public static func averageSaved(_ months: [MonthlySummary]) -> Money {
        guard !months.isEmpty else { return .zero }
        return Money(cents: months.reduce(Int64(0)) { $0 + $1.net.cents } / Int64(months.count))
    }
}

/// 家底拆开看：钱在哪、真正属于我的有多少。金额都是主币种、正数；net 是真家底。
public struct WealthBreakdown: Equatable, Sendable {
    /// 能随时用的：银行卡、现金、钱包里的（不含划给存钱目标的）。
    public var liquid: Money
    /// 存着的：储蓄账户、存钱目标里的钱。
    public var saved: Money
    /// 店里的：只在生意账本里用的账户。
    public var shop: Money
    /// 别人欠我的。
    public var owedToMe: Money
    /// 欠款：信用卡欠的、账户透支的、我借的、分期没还完的。
    public var owed: Money
    /// saved 里有多少是「钱还在银行卡里、但已经划给存钱目标」的（所以「能随时用的」比账户余额加起来少这么多）。
    public var earmarked: Money

    public init(liquid: Money, saved: Money, shop: Money, owedToMe: Money, owed: Money, earmarked: Money = .zero) {
        self.liquid = liquid; self.saved = saved; self.shop = shop; self.owedToMe = owedToMe; self.owed = owed
        self.earmarked = earmarked
    }

    /// 我有的（不减欠款）。
    public var assets: Money { liquid + saved + shop + owedToMe }
    /// 真家底：所有账户 − 信用卡 − 我欠的 − 分期未还 + 欠我的。
    public var net: Money { assets - owed }

    /// - accounts: 算进来的账户（私房钱藏着时不传）；balances: 每个账户换成主币种的余额。
    /// - goals: 存钱目标和已经存了多少；有专门账户的目标，那个账户整个算「存着的」；没有的，从「能随时用的」里划出来。
    /// - businessAccounts: 只在生意账本里用的账户。
    public static func make(accounts: [Account], balances: [String: Money], goals: [(goal: Goal, saved: Money)],
                            businessAccounts: Set<String>, obligations: Obligations) -> WealthBreakdown {
        let goalAccounts = Set(goals.compactMap(\.goal.savingsAccountID))
        var liquid: Int64 = 0, saved: Int64 = 0, shop: Int64 = 0, owed: Int64 = 0
        for a in accounts {
            let b = balances[a.id]?.cents ?? 0
            if b < 0 { owed += -b; continue }          // 信用卡欠的、透支的
            if a.kind == .credit { liquid += b; continue }   // 信用卡里多还的钱
            if a.kind == .savings || goalAccounts.contains(a.id) { saved += b }
            else if businessAccounts.contains(a.id) { shop += b }
            else { liquid += b }
        }
        // 没有专门账户的目标：钱还在银行卡里，但已经说好是存着的。最多划走「能随时用的」那么多。
        let earmarked = min(liquid, goals.filter { $0.goal.savingsAccountID == nil }.reduce(Int64(0)) { $0 + max(0, $1.saved.cents) })
        liquid -= earmarked; saved += earmarked
        return WealthBreakdown(liquid: Money(cents: liquid), saved: Money(cents: saved), shop: Money(cents: shop),
                               owedToMe: obligations.owedToMe, owed: Money(cents: owed) + obligations.iOwe, earmarked: Money(cents: earmarked))
    }

    /// 只在生意账本里用的账户（有流水、而且全都记在生意账本上）。
    public static func businessAccounts(_ ledger: Ledger) -> Set<String> {
        let business = Set(ledger.books.filter(\.isBusiness).map(\.id))
        guard !business.isEmpty else { return [] }
        var seen: [String: Bool] = [:]
        for t in ledger.transactions where t.flow == nil {
            guard let b = t.bookID else { continue }
            seen[t.accountID] = (seen[t.accountID] ?? true) && business.contains(b)
        }
        return Set(seen.filter(\.value).keys)
    }
}

extension Nudges {
    /// 趋势页最上面的夏夏卡：这几个月是越过越好还是越差，再说悄悄变多的开销。
    /// - months: 过完的整月，从早到晚。
    public static func trends(months: [MonthlySummary], creeping: [Trends.Creep], currency: String) -> [Nudge] {
        let list = months.sorted { $0.month < $1.month }
        guard !list.isEmpty else { return [] }
        func m(_ x: Money) -> String { short(x, currency) }
        let avg = Trends.averageSaved(list)
        let n = list.count
        let recent = Array(list.suffix(3)), earlier = Array(list.dropLast(3))
        var title = avg.isExpense ? "这 \(n) 个月平均每月超支 \(m(avg))。" : "这 \(n) 个月平均每月存下 \(m(avg))。"
        var advice = "\(list.filter { !$0.net.isExpense }.count) 个月是存下钱的，\(list.filter { $0.net.isExpense }.count) 个月花得比挣得多。"
        var kind: Nudge.Kind = avg.isExpense ? .unusual : .info
        if earlier.count >= 2 {
            let diff = Trends.averageSaved(recent) - Trends.averageSaved(earlier)
            if diff.cents >= 5000 {
                title = "越过越好：最近 3 个月平均每月比之前多存 \(m(diff))。"; kind = .praise
            } else if diff.cents <= -5000 {
                title = "最近 3 个月平均每月比之前少存 \(m(diff))，在变差。"; kind = .unusual
            } else {
                title = "这 \(n) 个月过得差不多，平均每月\(avg.isExpense ? "超支" : "存下") \(m(avg))。"
            }
            advice = "这 \(n) 个月平均每月\(avg.isExpense ? "超支" : "存下") \(m(avg))。" + (creeping.first.map { "「\($0.category)」在悄悄变多。" } ?? "没有哪类开销在悄悄变多。")
        }
        var out = [Nudge(kind: kind, key: "trend-saved", title: title, advice: advice,
                         question: "我这几个月是越过越好还是越差？为什么？")]
        for c in creeping.prefix(2) {
            out.append(Nudge(kind: .unusual, key: "trend-creep-\(c.category)",
                             title: "「\(c.category)」连涨 \(c.months) 个月，比 \(c.since.month) 月多 \(m(c.extra))。",
                             advice: "每个月涨一点不容易发现。现在一个月 \(m(c.now))，回到 \(c.since.month) 月的水平一年能多留下 \(m(Money(cents: c.extra.cents * 12)))。",
                             question: "「\(c.category)」为什么一直在涨？怎么压回去？"))
        }
        return out
    }

    /// 家底页最上面的夏夏卡：能随时用的钱够过几个月、欠款还不还得上、比 3 个月前多了还是少了。
    /// - monthlySpend: 最近几个整月平均每月花多少（正数）；threeMonthsAgo: 3 个月前的真家底（不知道就 nil）。
    public static func wealth(_ w: WealthBreakdown, monthlySpend: Money, threeMonthsAgo: Money?, currency: String) -> [Nudge] {
        func m(_ x: Money) -> String { short(x, currency) }
        var out: [Nudge] = []
        if monthlySpend.cents > 0 {
            let months = Double(w.liquid.cents) / Double(monthlySpend.cents)
            let text = months >= 10 ? "\(Int(months.rounded()))" : String(format: "%.1f", months).replacingOccurrences(of: ".", with: ",").replacingOccurrences(of: ",0", with: "")
            out.append(Nudge(kind: months < 1 ? .unusual : months >= 3 ? .praise : .info, key: "wealth-runway",
                             title: "能随时用的钱有 \(m(w.liquid))，够你过 \(text) 个月。",
                             advice: months < 1 ? "不到一个月的开销，手头偏紧。先别动存着的钱，这个月能少花就少花。"
                                : months < 3 ? "一般留够 3 个月的开销比较安心，还差 \(m(Money(cents: monthlySpend.cents * 3 - w.liquid.cents)))。"
                                : "按每月花 \(m(monthlySpend)) 算。超过 3 个月的部分可以挪去存着，别躺在卡里。",
                             question: "我手头的钱够不够？该留多少应急？"))
        }
        if w.owed.cents > 0 {
            let enough = w.liquid.cents >= w.owed.cents
            out.append(Nudge(kind: enough ? .info : .upcoming, key: "wealth-owed",
                             title: "一共欠着 \(m(w.owed))（信用卡、借款、分期）。",
                             advice: enough ? "能随时用的钱够一次还清，还完还剩 \(m(w.liquid - w.owed))。"
                                : "能随时用的钱不够一次还清，还差 \(m(w.owed - w.liquid))，先还最快到期的。",
                             question: "我的欠款先还哪一笔最划算？"))
        }
        if let before = threeMonthsAgo, before.cents != 0 {
            let diff = w.net - before
            if diff.magnitude.cents >= 1000 {
                out.append(Nudge(kind: diff.isExpense ? .unusual : .praise, key: "wealth-change",
                                 title: "真家底 \(m(w.net))，比 3 个月前\(diff.isExpense ? "少" : "多")了 \(m(diff))。",
                                 advice: diff.isExpense ? "去趋势页看看是哪几个月花得比挣得多。" : "平均每个月多出 \(m(Money(cents: diff.cents / 3)))，照这样保持。",
                                 question: "我的家底为什么\(diff.isExpense ? "变少" : "变多")了？"))
            }
        }
        if out.isEmpty {
            out.append(Nudge(kind: .info, key: "wealth-net",
                             title: "现在真正属于你的有 \(m(w.net))。",
                             advice: "记满一个月的开销，我就能告诉你这些钱够过几个月。",
                             question: "看看我的家底：钱放得合不合理？"))
        }
        return out
    }
}
