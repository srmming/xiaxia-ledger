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

    /// 一项钱是从哪来的：哪个账户（或哪笔欠款）、多少。金额是主币种、正数。
    public struct Source: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var amount: Money
        public init(id: String, name: String, amount: Money) { self.id = id; self.name = name; self.amount = amount }
    }

    /// 每一步的来源清单（家底页点开看「这个数是哪几个账户加起来的」）。
    public struct Sources: Equatable, Sendable {
        /// 总存款：每个有钱的账户。
        public var total: [Source] = []
        /// 店里要用：只在生意账本里用的账户。
        public var shop: [Source] = []
        /// 存着不动：储蓄账户、目标专用账户、划给目标的钱。
        public var saved: [Source] = []
        /// 要还的：信用卡刷的、透支的、借的钱、分期没还完的。
        public var owed: [Source] = []
        public init() {}
    }
    public var sources = Sources()

    /// 总存款：所有账户里的钱加起来（不减欠款，不算别人欠我的）。
    public var total: Money { liquid + saved + shop }
    /// 能随便花的：总存款 − 店里要用 − 存着不动 − 要还的。不够还时是负数。
    public var spendable: Money { liquid - owed }
    /// 能随便花的钱够花几个月（按每月花 monthlySpend 算）；没有开销记录或没钱可花就是 nil。
    public func months(monthlySpend: Money) -> Double? {
        guard monthlySpend.cents > 0, spendable.cents > 0 else { return nil }
        return Double(spendable.cents) / Double(monthlySpend.cents)
    }
    /// 「2,5」「12」这样的月数写法。
    public static func monthsText(_ months: Double) -> String {
        months >= 10 ? "\(Int(months.rounded()))"
            : String(format: "%.1f", months).replacingOccurrences(of: ".", with: ",").replacingOccurrences(of: ",0", with: "")
    }

    /// 我有的（不减欠款）。
    public var assets: Money { liquid + saved + shop + owedToMe }
    /// 真家底：所有账户 − 信用卡 − 我欠的 − 分期未还 + 欠我的。
    public var net: Money { assets - owed }

    /// - accounts: 算进来的账户（私房钱藏着时不传）；balances: 每个账户换成主币种的余额。
    /// - goals: 存钱目标和已经存了多少；有专门账户的目标，那个账户整个算「存着的」；没有的，从「能随时用的」里划出来。
    /// - businessAccounts: 只在生意账本里用的账户。
    /// - owedItems: 借的钱、分期没还完的，一笔一行（只用来列清单；合计以 obligations.iOwe 为准）。
    public static func make(accounts: [Account], balances: [String: Money], goals: [(goal: Goal, saved: Money)],
                            businessAccounts: Set<String>, obligations: Obligations, owedItems: [Source] = []) -> WealthBreakdown {
        let goalAccounts = Set(goals.compactMap(\.goal.savingsAccountID))
        var liquid: Int64 = 0, saved: Int64 = 0, shop: Int64 = 0, owed: Int64 = 0
        var src = Sources()
        for a in accounts {
            let b = balances[a.id]?.cents ?? 0
            if b < 0 {                                  // 信用卡欠的、透支的
                owed += -b
                src.owed.append(Source(id: a.id, name: a.kind == .credit ? "\(a.name)（已刷）" : "\(a.name)（透支）", amount: Money(cents: -b)))
                continue
            }
            if b > 0 { src.total.append(Source(id: a.id, name: a.name, amount: Money(cents: b))) }
            if a.kind == .credit { liquid += b; continue }   // 信用卡里多还的钱
            if a.kind == .savings || goalAccounts.contains(a.id) {
                saved += b
                if b > 0 { src.saved.append(Source(id: a.id, name: a.name, amount: Money(cents: b))) }
            } else if businessAccounts.contains(a.id) {
                shop += b
                if b > 0 { src.shop.append(Source(id: a.id, name: a.name, amount: Money(cents: b))) }
            } else { liquid += b }
        }
        // 没有专门账户的目标：钱还在银行卡里，但已经说好是存着的。最多划走「能随时用的」那么多。
        let loose = goals.filter { $0.goal.savingsAccountID == nil && $0.saved.cents > 0 }
        let wanted = loose.reduce(Int64(0)) { $0 + $1.saved.cents }
        let earmarked = min(liquid, wanted)
        liquid -= earmarked; saved += earmarked
        if earmarked > 0 {
            if earmarked == wanted {
                for g in loose { src.saved.append(Source(id: "goal-\(g.goal.id)", name: "给「\(g.goal.name)」留的", amount: g.saved)) }
            } else {
                src.saved.append(Source(id: "goal-earmarked", name: "给存钱目标留的", amount: Money(cents: earmarked)))
            }
        }
        // 借的钱、分期：给了明细而且加起来对得上就一笔一行，否则只写一行合计。
        if obligations.iOwe.cents > 0 {
            if owedItems.reduce(Int64(0), { $0 + $1.amount.cents }) == obligations.iOwe.cents {
                src.owed += owedItems
            } else {
                src.owed.append(Source(id: "obligations", name: "借的钱和分期", amount: obligations.iOwe))
            }
        }
        for k in [\Sources.total, \Sources.shop, \Sources.saved, \Sources.owed] { src[keyPath: k].sort { $0.amount.cents > $1.amount.cents } }
        var w = WealthBreakdown(liquid: Money(cents: liquid), saved: Money(cents: saved), shop: Money(cents: shop),
                                owedToMe: obligations.owedToMe, owed: Money(cents: owed) + obligations.iOwe, earmarked: Money(cents: earmarked))
        w.sources = src
        return w
    }

    /// 「店里要用」那一步叫什么：只有一个生意账本就用它的名字（「Miora 美甲店要用」），几个就叫「店里要用」。
    public static func shopLabel(_ ledger: Ledger) -> String {
        let business = ledger.books.filter(\.isBusiness)
        return business.count == 1 ? "\(business[0].name)要用" : "店里要用"
    }

    /// 借的钱、分期没还完的，一笔一行（给 make 的 owedItems）。
    public static func owedItems(_ ledger: Ledger, asOf date: LocalDate) -> [Source] {
        let debts = Plans.debts(ledger, today: date).filter { $0.direction == .iOweThem && $0.outstanding.cents > 0 }
            .map { Source(id: "debt-\($0.id)", name: "欠\($0.counterparty)", amount: $0.outstanding) }
        let inst = Plans.installments(ledger).filter { $0.remaining.cents > 0 }
            .map { Source(id: "inst-\($0.id)", name: "\($0.name)（分期）", amount: $0.remaining) }
        return debts + inst
    }

    /// 店里的账户：流水大多记在生意账本上的（偶尔用店里现金买了点自己的东西，不改它算店里的）。
    public static func businessAccounts(_ ledger: Ledger) -> Set<String> {
        let business = Set(ledger.books.filter(\.isBusiness).map(\.id))
        guard !business.isEmpty else { return [] }
        var shop: [String: Int] = [:], other: [String: Int] = [:]
        for t in ledger.transactions where t.flow == nil && t.transferID == nil {
            guard let b = t.bookID else { continue }
            if business.contains(b) { shop[t.accountID, default: 0] += 1 } else { other[t.accountID, default: 0] += 1 }
        }
        var set = Set(shop.filter { $0.value > other[$0.key, default: 0] * 4 }.keys)
        // 自己说过算哪边的，以说的为准（加账户时在哪边、后来挪过边）。
        for (id, side) in ledger.business?.accountSides ?? [:] {
            if side == .business { set.insert(id) } else { set.remove(id) }
        }
        return set
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
        // 和页面大数字同一个口径：能随便花的 = 总存款 − 店里要用 − 存着不动 − 要还的。
        if monthlySpend.cents > 0 {
            if let months = w.months(monthlySpend: monthlySpend) {
                let text = WealthBreakdown.monthsText(months)
                out.append(Nudge(kind: months < 1 ? .unusual : months >= 3 ? .praise : .info, key: "wealth-runway",
                                 title: "能随便花的钱够你过 \(text) 个月。",
                                 advice: months < 1 ? "不到一个月的开销，手头偏紧。先别动存着的钱，这个月能少花就少花。"
                                    : months < 3 ? "一般留够 3 个月的开销比较安心，还差 \(m(Money(cents: monthlySpend.cents * 3 - w.spendable.cents)))。"
                                    : "按每月花 \(m(monthlySpend)) 算。超过 3 个月的部分可以挪去存着，别躺在卡里。",
                                 question: "我手头的钱够不够？该留多少应急？"))
            } else {
                out.append(Nudge(kind: .unusual, key: "wealth-runway",
                                 title: "现在没有能随便花的钱：手头的钱还不够还欠的。",
                                 advice: "还差 \(m(w.spendable.magnitude))。先别动存着的钱，这个月能少花就少花，先还最快到期的。",
                                 question: "我手头的钱够不够？该留多少应急？"))
            }
        }
        if w.owed.cents > 0 {
            let enough = w.liquid.cents >= w.owed.cents
            out.append(Nudge(kind: enough ? .info : .upcoming, key: "wealth-owed",
                             title: "一共要还 \(m(w.owed))（信用卡、借款、分期）。",
                             advice: enough ? "手头的钱够一次还清，上面「能随便花」的数已经把它减掉了。"
                                : "手头的钱不够一次还清，还差 \(m(w.owed - w.liquid))，先还最快到期的。",
                             question: "我的欠款先还哪一笔最划算？"))
        }
        if let before = threeMonthsAgo, before.cents != 0 {
            let diff = w.net - before
            if diff.magnitude.cents >= 1000 {
                out.append(Nudge(kind: diff.isExpense ? .unusual : .praise, key: "wealth-change",
                                 title: "算上欠的和别人欠你的，家底比 3 个月前\(diff.isExpense ? "少" : "多")了 \(m(diff))。",
                                 advice: diff.isExpense ? "去趋势页看看是哪几个月花得比挣得多。" : "平均每个月多出 \(m(Money(cents: diff.cents / 3)))，照这样保持。",
                                 question: "我的家底为什么\(diff.isExpense ? "变少" : "变多")了？"))
            }
        }
        if out.isEmpty {
            out.append(Nudge(kind: .info, key: "wealth-net",
                             title: "总存款 \(m(w.total))。",
                             advice: "记满一个月的开销，我就能告诉你这些钱够过几个月。",
                             question: "看看我的家底：钱放得合不合理？"))
        }
        return out
    }
}
