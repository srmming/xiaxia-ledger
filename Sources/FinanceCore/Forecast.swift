import Foundation

/// 趋势页（ming 2026-11-23）：照现在这样花下去，月底、年底大概还剩多少钱。
/// 「剩多少」和家底页的大数字是同一个口径：能随便花的钱（总存款 − 店里要用 − 存着不动 − 要还的）。
/// 有生意账本时只看自己过日子的进出（店里的钱本来就不算在能随便花里），从店里拿回家的钱算进账。
public enum CashForecast {
    /// 一个月的进出，都是正数。
    public struct Flow: Equatable, Sendable {
        public var income: Money
        public var spent: Money
        /// 每个分类花掉多少（退款已冲减），正数。
        public var byCategory: [String: Money]
        public var net: Money { income - spent }
        public var isEmpty: Bool { income.cents == 0 && spent.cents == 0 }
        public init(income: Money = .zero, spent: Money = .zero, byCategory: [String: Money] = [:]) {
            self.income = income; self.spent = spent; self.byCategory = byCategory
        }
    }

    /// 线上的一个点：那天能随便花多少。
    public struct Point: Equatable, Sendable, Identifiable {
        public var date: LocalDate
        public var value: Money
        public var id: String { date.description }
        public init(date: LocalDate, value: Money) { self.date = date; self.value = value }
    }

    /// 能少花的一样开销：平均每月花多少，少花一半到年底能多剩多少。
    public struct Lever: Equatable, Sendable, Identifiable {
        public var category: String
        public var monthly: Money
        public var halfSaves: Money
        /// 这一类连着几个月在涨（悄悄变多）。
        public var rising: Bool
        public var id: String { category }
    }

    public struct Result: Equatable, Sendable {
        public var today: LocalDate
        /// 现在能随便花多少。
        public var now: Money
        public var monthEnd: Money
        public var yearEnd: Money
        /// 「年底」是哪天：一般是今年 12 月 31 日；12 月里看就是明年 12 月 31 日。
        public var yearEndDate: LocalDate
        /// 按哪几个整月算的平均：每月进多少、花多少。
        public var monthlyIncome: Money
        public var monthlySpend: Money
        public var basisMonths: Int
        /// 本月剩下的日子还会进多少、花多少（估的）。
        public var restIncome: Money
        public var restSpend: Money
        /// 已经发生的：前几个月月底 + 今天。
        public var past: [Point]
        /// 照这样花：今天、本月底、之后每个月底，一直到年底。
        public var ahead: [Point]
        /// 每月少花 10% 的话。
        public var thrifty: [Point]
        /// 能少花的几样开销（最多 3 样，花得多的在前）。
        public var levers: [Lever]
        /// 到年底还有几个月（本月剩下的天数折成零点几个月）。
        public var monthsLeft: Double

        public var monthlyNet: Money { monthlyIncome - monthlySpend }
        public var thriftyYearEnd: Money { thrifty.last?.value ?? yearEnd }
        public var isNextYear: Bool { yearEndDate.year > today.year }
        /// 年底比现在多（正）还是少（负）。
        public var change: Money { yearEnd - now }
    }

    /// 「少花一点」那条线：每月少花多少。
    public static let thriftyRate = 0.1

    /// - today: 今天；now: 现在能随便花多少（家底页的大数字）。
    /// - thisMonth: 这个月到今天为止的进出。
    /// - fullMonths: 过完的整月，从早到晚；只用最近 3 个有进出的月算平均。
    /// - history: 前几个月月底能随便花多少（画实线用），今天这个点不用传。
    /// - rising: 连着几个月在涨的分类（Trends.creeping）。
    /// 没有过完的整月就算不出来，返回 nil。
    public static func make(today: LocalDate, now: Money, thisMonth: Flow, fullMonths: [Flow],
                            history: [Point] = [], rising: Set<String> = []) -> Result? {
        let basis = Array(fullMonths.filter { !$0.isEmpty }.suffix(3))
        guard !basis.isEmpty else { return nil }
        let n = Int64(basis.count)
        let avgIncome = basis.reduce(Int64(0)) { $0 + $1.income.cents } / n
        let avgSpend = basis.reduce(Int64(0)) { $0 + $1.spent.cents } / n

        // 这个月剩下的日子：
        // - 花：平时一个月花的减掉已经花的；已经花超了，剩下的日子也照平时每天的速度继续花。
        // - 进：平时一个月进的减掉已经进的（工资已经到了就不再算）。
        let days = dayCount(today.year, today.month)
        let restDays = max(0, days - today.day)
        let pace = avgSpend * Int64(restDays) / Int64(days)
        // 这个月最后一天就不再估了。
        let restSpend = restDays == 0 ? 0 : max(avgSpend - thisMonth.spent.cents, pace)
        let restIncome = restDays == 0 ? 0 : max(0, avgIncome - thisMonth.income.cents)

        let target = today.month == 12 ? today.year + 1 : today.year
        let yearEndDate = LocalDate(year: target, month: 12, day: 31)
        let monthEndDate = LocalDate(year: today.year, month: today.month, day: days)
        // 本月之后到年底还有几个整月。
        let laterMonths = (target - today.year) * 12 + 12 - today.month

        func line(cut: Double) -> [Point] {
            let spendRest = Int64((Double(restSpend) * (1 - cut)).rounded())
            let spendMonth = Int64((Double(avgSpend) * (1 - cut)).rounded())
            var v = now.cents + restIncome - spendRest
            var out = [Point(date: today, value: now)]
            if monthEndDate != today { out.append(Point(date: monthEndDate, value: Money(cents: v))) }
            var ym = YearMonth(year: today.year, month: today.month)
            for _ in 0..<laterMonths {
                ym = ym.adding(months: 1)
                v += avgIncome - spendMonth
                out.append(Point(date: LocalDate(year: ym.year, month: ym.month, day: dayCount(ym.year, ym.month)), value: Money(cents: v)))
            }
            return out
        }
        let ahead = line(cut: 0)
        let thrifty = line(cut: thriftyRate)
        let monthsLeft = Double(restDays) / Double(days) + Double(laterMonths)

        // 能少花的：固定开销（房租、税、还款……）不算，按平均每月花多少排，最多 3 样。
        var cats: [String: Int64] = [:]
        for f in basis { for (k, v) in f.byCategory where v.cents > 0 { cats[k, default: 0] += v.cents } }
        let fixed = Subscriptions.fixedCostCategories
        var picked: [(name: String, monthly: Int64)] = []
        for (name, total) in cats where !fixed.contains(name) && !fixed.contains(name.lowercased()) {
            let monthly: Int64 = total / n
            if monthly > 0 { picked.append((name: name, monthly: monthly)) }
        }
        picked.sort { a, b in a.monthly == b.monthly ? a.name < b.name : a.monthly > b.monthly }
        var levers: [Lever] = []
        for p in picked.prefix(3) {
            let saves = Int64((Double(p.monthly) / 2 * monthsLeft).rounded())
            levers.append(Lever(category: p.name, monthly: Money(cents: p.monthly), halfSaves: Money(cents: saves),
                                rising: rising.contains(p.name)))
        }

        let monthEnd = now.cents + restIncome - restSpend
        return Result(today: today, now: now, monthEnd: Money(cents: monthEnd), yearEnd: ahead.last?.value ?? now,
                      yearEndDate: yearEndDate, monthlyIncome: Money(cents: avgIncome), monthlySpend: Money(cents: avgSpend),
                      basisMonths: basis.count, restIncome: Money(cents: restIncome), restSpend: Money(cents: restSpend),
                      past: history.filter { $0.date < today } + [Point(date: today, value: now)],
                      ahead: ahead, thrifty: thrifty, levers: levers, monthsLeft: monthsLeft)
    }

    /// 直接从流水算（app 和 fin 共用）：最近 12 个整月的进出、哪几类在悄悄变多。
    /// - now: 现在能随便花多少；history: 前几个月月底能随便花多少（画实线用）。
    public static func make(_ txs: [Transaction], books: [Book], hiddenAccounts: Set<String> = [], today: LocalDate,
                            now: Money, history: [Point] = []) -> Result? {
        let ym = today.yearMonth
        let months = Reports.months(endingAt: ym, count: 13)
        let byMonth = Self.flows(txs, books: books, months: months, hiddenAccounts: hiddenAccounts)
        let full = months.filter { $0 < ym }
        let summaries = full.compactMap { m -> MonthlySummary? in
            guard let f = byMonth[m], !f.isEmpty else { return nil }
            return MonthlySummary(month: m, bookID: nil, income: f.income, expense: Money(cents: -f.spent.cents),
                                  byCategory: f.byCategory.mapValues { Money(cents: -$0.cents) })
        }
        let rising = Set(Trends.creeping(summaries).map(\.category))
        return make(today: today, now: now, thisMonth: byMonth[ym] ?? Flow(), fullMonths: full.map { byMonth[$0] ?? Flow() },
                    history: history, rising: rising)
    }

    /// 每个月的进出（给 make 用）。
    /// 有生意账本时只算自己的账本（个人账本可能不止一个），和别的账本之间挪的钱：拿进来的算进、拿出去的算花；
    /// 没有生意账本就是全部账本（账本间转账两边抵消）。hiddenAccounts：不算进来的账户（私房钱藏着时）。
    public static func flows(_ txs: [Transaction], books: [Book], months: [YearMonth],
                             hiddenAccounts: Set<String> = []) -> [YearMonth: Flow] {
        let personal = books.filter { !$0.isBusiness }.map(\.id)
        let scopes: [String?] = (!personal.isEmpty && personal.count < books.count) ? personal : [nil]
        var out: [YearMonth: Flow] = [:]
        for scope in scopes {
            for s in Reports.summaries(txs, months: months, bookID: scope, hiddenAccounts: hiddenAccounts) {
                var f = out[s.month] ?? Flow()
                f.income = f.income + s.income
                f.spent = f.spent + s.expense.magnitude
                if scope != nil {
                    if s.betweenBooks.cents > 0 { f.income = f.income + s.betweenBooks } else { f.spent = f.spent + s.betweenBooks.magnitude }
                }
                for (k, v) in s.byCategory where v.isExpense { f.byCategory[k, default: .zero] = f.byCategory[k, default: .zero] + v.magnitude }
                out[s.month] = f
            }
        }
        return out
    }

    static func dayCount(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

extension Nudges {
    /// 趋势页最上面的夏夏卡：照这样花年底剩多少、哪一样最拖后腿、月底会不会不够。
    public static func forecast(_ f: CashForecast.Result, currency: String) -> [Nudge] {
        func m(_ x: Money) -> String { short(x, currency) }
        let year = f.isNextYear ? "明年年底" : "年底"
        var out: [Nudge] = []
        let change = f.change
        if f.yearEnd.cents < 0 {
            out.append(Nudge(kind: .unusual, key: "forecast-year",
                             title: "照这样花，到\(year)钱会不够，还差 \(m(f.yearEnd))。",
                             advice: "平均每月花 \(m(f.monthlySpend))，进 \(m(f.monthlyIncome))，每月差 \(m(f.monthlyNet))。得先把花销压下来。",
                             question: "照我现在这样花，到\(year)会不够用吗？该从哪里省？"))
        } else if change.isExpense, change.magnitude.cents >= 1000 {
            out.append(Nudge(kind: .unusual, key: "forecast-year",
                             title: "照这样花，\(year)能随便花的钱比现在少 \(m(change))，剩 \(m(f.yearEnd))。",
                             advice: "平均每月花 \(m(f.monthlySpend))，比进的 \(m(f.monthlyIncome)) 多。每月少花 10%，\(year)能剩 \(m(f.thriftyYearEnd))。",
                             question: "我每个月都在花老本吗？怎么扭过来？"))
        } else {
            out.append(Nudge(kind: change.cents >= 1000 ? .praise : .info, key: "forecast-year",
                             title: change.cents >= 1000 ? "照这样花，\(year)能剩 \(m(f.yearEnd))，比现在多 \(m(change))。"
                                : "照这样花，\(year)还剩 \(m(f.yearEnd))，和现在差不多。",
                             advice: "按最近 \(f.basisMonths) 个月平均：每月进 \(m(f.monthlyIncome))、花 \(m(f.monthlySpend))。"
                                + (change.cents >= 1000 ? "多出来的可以挪一部分去存着。" : "想多剩一点，看看右边那几样。"),
                             question: "照我现在这样，\(year)能攒下多少？还能怎么多攒点？"))
        }
        if let top = f.levers.first, top.halfSaves.cents >= 1000 {
            out.append(Nudge(kind: top.rising ? .unusual : .info, key: "forecast-lever-\(top.category)",
                             title: "「\(top.category)」最拖后腿：平均每月 \(m(top.monthly))\(top.rising ? "，还在涨" : "")。",
                             advice: "少花一半，\(year)能多剩 \(m(top.halfSaves))。",
                             question: "「\(top.category)」每月花 \(m(top.monthly))，怎么少花一点？"))
        }
        if f.monthEnd.cents < 0 {
            out.append(Nudge(kind: .upcoming, key: "forecast-month",
                             title: "照这样花，这个月底钱会不够，还差 \(m(f.monthEnd))。",
                             advice: "剩下这些天大概还要花 \(m(f.restSpend))。先别动存着的钱，能推的开销往后推。",
                             question: "这个月底钱不够了，先省哪里？"))
        }
        return out
    }
}
