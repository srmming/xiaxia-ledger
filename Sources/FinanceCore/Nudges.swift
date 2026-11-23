import Foundation

// 总览最上面夏夏的「一张一张的卡」（ming 2026-11-23：「能不能做成卡片形式可以左右拖动下一条」）。
// 每张只说一件看图看不出来、又能马上去做的事，一句结论加一句建议，不重复总览上已经有的数字。
// 按这个顺序：离目标还差多少 → 哪里不对劲 → 马上要扣的钱 → 都没有就夸一句。
// 只读账本算，不写任何东西；AI 写的「夏夏点评」另算一张，由界面放在这些后面。

public struct Nudge: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case goal, unusual, upcoming, praise, info }
    public var kind: Kind
    /// 同一件事的标识（比如分类名、订阅名），「知道了」按它当天藏起来。
    public var key: String
    /// 一句结论。
    public var title: String
    /// 一句建议。
    public var advice: String
    /// 「接着问」时问 AI 的具体问题。
    public var question: String
    public var id: String { "\(kind.rawValue)-\(key)" }

    public init(kind: Kind, key: String, title: String, advice: String, question: String) {
        self.kind = kind; self.key = key; self.title = title; self.advice = advice; self.question = question
    }

    public var label: String {
        switch kind {
        case .goal: "离目标"
        case .unusual: "留意"
        case .upcoming: "快要扣钱"
        case .praise: "做得好"
        case .info: "花在哪"
        }
    }
}

public enum Nudges {
    /// 引导里定的「每个月存下 300 €」→ 300 €。别的目标返回 nil。
    public static func monthlySavingTarget(aim: String?) -> Money? {
        guard let aim, aim.hasPrefix("每个月存下") else { return nil }
        let digits = String(aim.dropFirst("每个月存下".count).filter { $0.isNumber || $0 == "," || $0 == "." })
        guard let m = Money(parsing: digits), m.cents > 0 else { return nil }
        return m
    }

    /// 一句话里的金额：不带小数（「80 €」「1.150 €」）。
    static func short(_ m: Money, _ currency: String) -> String {
        let units = (m.magnitude.cents + 50) / 100
        return Money(cents: units * 100).formatted(in: currency).replacingOccurrences(of: ",00 ", with: " ")
    }

    public static func dayWord(_ days: Int) -> String {
        switch days { case 0: "今天"; case 1: "明天"; case 2: "后天"; default: "\(days) 天后" }
    }

    /// 能省的花销：不算房租、工资、税这些固定开销，也不算订阅。
    static func flexible(_ tx: Transaction) -> Bool {
        tx.amount.cents < 0 && !Subscriptions.fixedCostCategories.contains(tx.category ?? "") && tx.category != "订阅"
    }

    /// - expenses: 主币种的、已经按账本和私房钱筛好的支出流水（至少包括今天往前 9 周）。
    /// - projectedEnd: 照现在的速度这个月底大概剩多少（只有看的是本月才有）。
    /// - subscriptions: 订阅现状；balance: 某个账户现在有多少（账户自己的币种），不知道就 nil。
    public static func overview(expenses: [Transaction], today: LocalDate, currency: String,
                                aim: String?, projectedEnd: Money?, spentSoFar: Money, lastMonthSameDaySpent: Money,
                                subscriptions: [SubscriptionStatus], installments: [UpcomingCharge] = [],
                                accountName: (String) -> String, balance: (String) -> Money?) -> [Nudge] {
        var out: [Nudge] = []
        if let n = goal(expenses: expenses, today: today, currency: currency, aim: aim, projectedEnd: projectedEnd) { out.append(n) }
        if let n = unusual(expenses: expenses, today: today, currency: currency) { out.append(n) }
        let subs = subscriptions.compactMap { s -> UpcomingCharge? in
            guard s.cancelledOn == nil, let left = s.daysLeft else { return nil }
            return UpcomingCharge(id: s.id, name: s.name, amount: s.amount, currency: s.currency, daysLeft: left,
                                  accountID: s.accountID, bookID: s.bookID, isInstallment: false)
        }
        if let n = upcoming(subs + installments, accountName: accountName, balance: balance) { out.append(n) }
        if out.isEmpty {
            let calm = lastMonthSameDaySpent.cents > 0 && spentSoFar.cents <= lastMonthSameDaySpent.cents
            out.append(Nudge(kind: .praise, key: today.description,
                             title: calm ? "这个月花钱比上个月同期稳。" : "这个月没什么要操心的。",
                             advice: "照这样过就好，有事我会先提醒你。",
                             question: "还有哪里能再省一点？"))
        }
        return out
    }

    // MARK: 花销页

    /// 花销页最上面的夏夏卡：只讲花销，给意见再加一句说明（哪类花多了、主要花在哪、怎么省）。最多 4 张。
    /// - current / previous: 分类 → 花掉多少（正数）。previous 是上个月（看本月时是上月同期）。
    /// - previousName:「上月同期」或「10 月」。transactions: 这个月的支出流水，用来找「主要花在哪家」。
    public static func spending(month: Int, current: [(name: String, amount: Money)], previous: [String: Money],
                                previousName: String, transactions: [Transaction], currency: String) -> [Nudge] {
        let now = current.filter { $0.amount.cents > 0 }.sorted { $0.amount > $1.amount }
        guard let top = now.first else { return [] }
        let total = now.reduce(Int64(0)) { $0 + $1.amount.cents }
        let before = previous.filter { $0.value.cents > 0 }
        let prevTotal = before.values.reduce(Int64(0)) { $0 + $1.cents }
        func m(_ cents: Int64) -> String { short(Money(cents: cents), currency) }
        func canSave(_ name: String) -> Bool { !Subscriptions.fixedCostCategories.contains(name) && name != "订阅" }
        // 每类比上个月多（正）还是少（负）。
        var names = Set(now.map(\.name)); names.formUnion(before.keys)
        let nowBy = Dictionary(now.map { ($0.name, $0.amount.cents) }, uniquingKeysWith: +)
        let diffs = names.map { (name: $0, diff: (nowBy[$0] ?? 0) - (before[$0]?.cents ?? 0)) }
        let ups = diffs.filter { $0.diff >= 1000 }.sorted { $0.diff > $1.diff }
        let downs = diffs.filter { $0.diff <= -1000 && before[$0.name] != nil }.sorted { $0.diff < $1.diff }
        /// 这一类这个月主要花在哪：花得最多的那个名字、几笔、一共多少，还有最大的一笔。
        func detail(_ cat: String) -> (name: String, count: Int, sum: Int64, all: Int, biggest: Int64)? {
            let txs = transactions.filter { ($0.category ?? "其他") == cat && $0.amount.cents < 0 }
            guard !txs.isEmpty else { return nil }
            var by: [String: (count: Int, sum: Int64)] = [:]
            for t in txs {
                by[t.description, default: (0, 0)].count += 1
                by[t.description, default: (0, 0)].sum += t.amount.magnitude.cents
            }
            guard let best = by.max(by: { ($0.value.sum, $1.key) < ($1.value.sum, $0.key) }) else { return nil }
            return (best.key, best.value.count, best.value.sum, txs.count, txs.map { $0.amount.magnitude.cents }.max() ?? 0)
        }

        var out: [Nudge] = []
        // 1. 总数比上个月。
        if prevTotal == 0 {
            out.append(Nudge(kind: .info, key: "spend-total",
                             title: "\(month) 月到现在花了 \(m(total))，最大的一块是「\(top.name)」。",
                             advice: "\(previousName)还没有记录，记满两个月我就能帮你对比哪类花多了。",
                             question: "\(month) 月钱主要花在哪了？哪些可以省？"))
        } else if total - prevTotal >= 1000 {
            let where_ = ups.prefix(2).map { "「\($0.name)」（多 \(m($0.diff))）" }.joined(separator: "和")
            out.append(Nudge(kind: .unusual, key: "spend-total",
                             title: "这个月比\(previousName)多花了 \(m(total - prevTotal))。",
                             advice: where_.isEmpty ? "各类都多了一点，没有哪一类特别突出。" : "多出来的主要在\(where_)。",
                             question: "为什么比\(previousName)多花了？怎么花回去？"))
        } else if prevTotal - total >= 1000 {
            let where_ = downs.first.map { "省得最多的是「\($0.name)」，少花了 \(m(-$0.diff))。" } ?? "各类都少了一点，照这样保持就好。"
            out.append(Nudge(kind: .praise, key: "spend-total",
                             title: "这个月比\(previousName)少花了 \(m(prevTotal - total))。",
                             advice: where_,
                             question: "省下来的钱放哪儿最好？"))
        } else {
            out.append(Nudge(kind: .info, key: "spend-total",
                             title: "这个月和\(previousName)花得差不多，都是 \(m(total)) 上下。",
                             advice: "最大的一块是「\(top.name)」，\(m(top.amount.cents))，占 \(Int((Double(top.amount.cents) / Double(max(total, 1)) * 100).rounded()))%。",
                             question: "\(month) 月哪些开销可以省？"))
        }
        // 2. 涨得最多的、能省的那一类：主要花在哪，少花几次能回到上个月。
        if prevTotal > 0, let up = ups.first(where: { canSave($0.name) }) {
            var advice = before[up.name] == nil ? "\(previousName)没有这一类，看看是不是偶尔一次。" : "看看这一类的流水，挑能少的先少。"
            if let d = detail(up.name) {
                let avg = d.sum / Int64(max(1, d.count))
                let times = avg > 0 ? Int((up.diff + avg - 1) / avg) : 0
                advice = "主要花在「\(d.name)」，\(d.count) 笔共 \(m(d.sum))。"
                    + (d.count >= 2 && times >= 1 && times < d.count ? "少花 \(times) 次就回到\(previousName)的水平。"
                       : d.all == 1 ? "只有这一笔，偶尔一次不用太在意。" : "")
            }
            out.append(Nudge(kind: .unusual, key: "spend-up-\(up.name)",
                             title: "「\(up.name)」比\(previousName)多花了 \(m(up.diff))，是涨得最多的一类。",
                             advice: advice,
                             question: "「\(up.name)」怎么省回来？"))
        }
        // 3. 一类占了大半：是一笔大件还是很多笔小的。
        let share = Double(top.amount.cents) / Double(max(total, 1))
        if share >= 0.4, canSave(top.name), !out.contains(where: { $0.key == "spend-up-\(top.name)" }), let d = detail(top.name) {
            let pct = Int((share * 100).rounded())
            let advice = Double(d.biggest) >= Double(top.amount.cents) * 0.7
                ? "主要是一笔 \(m(d.biggest)) 的大件。偶尔一次不用担心，只是别让它变成每个月都有。"
                : "一共 \(d.all) 笔，平均一笔 \(m(top.amount.cents / Int64(max(1, d.all))))，花得最多的是「\(d.name)」。"
            out.append(Nudge(kind: .info, key: "spend-share-\(top.name)",
                             title: "「\(top.name)」占了这个月花销的 \(pct)%，\(m(top.amount.cents))。",
                             advice: advice,
                             question: "「\(top.name)」这笔花得值不值？"))
        }
        // 4. 少花得最多的一类：夸一句。
        if let down = downs.first(where: { canSave($0.name) }), out.first?.kind != .praise || downs.count > 1 {
            let d = out.first?.kind == .praise ? downs.dropFirst().first(where: { canSave($0.name) }) : down
            if let d {
                out.append(Nudge(kind: .praise, key: "spend-down-\(d.name)",
                                 title: "「\(d.name)」比\(previousName)少花了 \(m(-d.diff))。",
                                 advice: "照这样保持，一年能多留下大约 \(m(-d.diff * 12))。",
                                 question: "还有哪一类能像「\(d.name)」这样省下来？"))
            }
        }
        return Array(out.prefix(4))
    }

    /// 离「每个月存下多少」还差多少；差的话说从哪儿省最快。
    static func goal(expenses: [Transaction], today: LocalDate, currency: String, aim: String?, projectedEnd: Money?) -> Nudge? {
        guard let target = monthlySavingTarget(aim: aim), let end = projectedEnd else { return nil }
        let gap = target - end
        if gap.cents <= 0 {
            return Nudge(kind: .goal, key: "save-ok",
                         title: "照这个速度，月底能存 \(short(end, currency))，比目标多 \(short(gap, currency))。",
                         advice: "多出来的可以先放进存钱目标，免得月底又花掉。",
                         question: "多出来的 \(short(gap, currency)) 放哪儿最好？")
        }
        let title = end.cents >= 0
            ? "照这个速度，月底能存 \(short(end, currency))，离 \(short(target, currency)) 还差 \(short(gap, currency))。"
            : "照这个速度，月底会超支 \(short(end, currency))，离每月存 \(short(target, currency)) 还差 \(short(gap, currency))。"
        // 这个月花得最多的「能省的」分类：平均一笔多少，少花几次就够。
        let month = expenses.filter { $0.date.yearMonth == today.yearMonth && flexible($0) }
        var byCategory: [String: [Transaction]] = [:]
        for t in month { byCategory[t.category ?? "其他", default: []].append(t) }
        var advice = "先看看这个月花得最多的几类，挑一类少花一点。"
        if let top = byCategory.max(by: { a, b in
            a.value.reduce(Int64(0)) { $0 + $1.amount.magnitude.cents } < b.value.reduce(Int64(0)) { $0 + $1.amount.magnitude.cents }
        }) {
            let cat = top.key, txs = top.value
            let total = txs.reduce(Int64(0)) { $0 + $1.amount.magnitude.cents }
            let avg = total / Int64(max(1, txs.count))
            let times = avg > 0 ? Int((gap.cents + avg - 1) / avg) : 0
            advice = times > 0 && times <= 6 && txs.count >= times
                ? "「\(cat)」平均一次 \(short(Money(cents: avg), currency))，少花 \(times) 次就够。"
                : "「\(cat)」这个月花得最多，先从它省起。"
        }
        return Nudge(kind: .goal, key: "save-gap", title: title, advice: advice,
                     question: "怎么省出这 \(short(gap, currency))？")
    }

    /// 最近 7 天哪一类比前 8 周平均每周多出很多。
    static func unusual(expenses: [Transaction], today: LocalDate, currency: String) -> Nudge? {
        let weekStart = today.adding(days: -6)
        let before = today.adding(days: -62)
        var now: [String: Int64] = [:], past: [String: Int64] = [:], weeksSeen: [String: Set<Int>] = [:]
        var biggest: [String: Transaction] = [:]
        for t in expenses where flexible(t) {
            let c = t.category ?? "其他"
            let cents = t.amount.magnitude.cents
            if weekStart <= t.date && t.date <= today {
                now[c, default: 0] += cents
                if (biggest[c]?.amount.magnitude.cents ?? 0) < cents { biggest[c] = t }
            } else if before < t.date && t.date < weekStart {
                past[c, default: 0] += cents
                weeksSeen[c, default: []].insert(t.date.days(until: weekStart) / 7)
            }
        }
        var best: (cat: String, pct: Int, extra: Int64)?
        for (c, cents) in now {
            guard let p = past[c], (weeksSeen[c]?.count ?? 0) >= 3 else { continue }
            let avg = p / 8
            guard avg > 0 else { continue }
            let extra = cents - avg
            let pct = Int(extra * 100 / avg)
            guard pct >= 40, extra >= 2000 else { continue }
            if best == nil || extra > best!.extra { best = (c, pct, extra) }
        }
        guard let b = best else { return nil }
        var advice = "回头看看这几天是不是有一笔特别大的。"
        if let t = biggest[b.cat] {
            advice = "最大一笔是 \(t.date.month) 月 \(t.date.day) 日「\(Merchant.display(t.description))」\(short(t.amount, currency))。"
        }
        return Nudge(kind: .unusual, key: b.cat,
                     title: "最近 7 天「\(b.cat)」比平时多 \(b.pct)%，多花了 \(short(Money(cents: b.extra), currency))。",
                     advice: advice,
                     question: "最近 7 天「\(b.cat)」为什么花得多？")
    }

    /// 3 天内要扣的订阅和分期；扣款账户里的钱不够就提醒。
    static func upcoming(_ charges: [UpcomingCharge], accountName: (String) -> String, balance: (String) -> Money?) -> Nudge? {
        let soon = charges.filter { $0.daysLeft <= 3 }.sorted { $0.daysLeft < $1.daysLeft }
        guard let first = soon.first else { return nil }
        let names = soon.prefix(3).map { "「\($0.name)」" + ($0.isInstallment ? "分期" : "") }.joined(separator: "、") + (soon.count > 3 ? " 等 \(soon.count) 笔" : "")
        // 同一种币的才加起来；混着币种就不报总数。
        let currencies = Set(soon.map(\.currency))
        let spread = soon.contains(where: { $0.daysLeft != first.daysLeft })
        var title = dayWord(first.daysLeft) + (spread ? "起" : "") + "扣\(names)"
        if currencies.count == 1, let c = currencies.first {
            title += "，一共 \(short(soon.reduce(Money.zero) { $0 + $1.amount }, c))。"
        } else {
            title += "。"
        }
        var lacking: [String] = []
        var byAccount: [String: [UpcomingCharge]] = [:]
        for s in soon { if let a = s.accountID { byAccount[a, default: []].append(s) } }
        for (a, list) in byAccount.sorted(by: { $0.key < $1.key }) {
            guard let have = balance(a), Set(list.map(\.currency)).count == 1 else { continue }
            let need = list.reduce(Money.zero) { $0 + $1.amount }
            if have.cents < need.cents { lacking.append("「\(accountName(a))」") }
        }
        let advice = lacking.isEmpty ? (byAccount.isEmpty ? "到时候留意一下扣款账户。" : "扣款账户里的钱够。")
            : "\(lacking.joined(separator: "、"))里的钱不够扣，记得先转一点进去。"
        let onlyInstallments = soon.allSatisfy(\.isInstallment)
        return Nudge(kind: .upcoming, key: soon.map(\.name).joined(separator: "+"), title: title, advice: advice,
                     question: onlyInstallments ? "这几笔分期还要还多久？" : "这几个订阅里有哪些可以停掉？")
    }
}
