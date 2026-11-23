import Foundation

// 总览最上面夏夏的「一张一张的卡」（ming 2026-11-23：「能不能做成卡片形式可以左右拖动下一条」）。
// 每张只说一件看图看不出来、又能马上去做的事，一句结论加一句建议，不重复总览上已经有的数字。
// 按这个顺序：离目标还差多少 → 哪里不对劲 → 马上要扣的钱 → 都没有就夸一句。
// 只读账本算，不写任何东西；AI 写的「夏夏点评」另算一张，由界面放在这些后面。

public struct Nudge: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case goal, unusual, upcoming, praise }
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

    static func dayWord(_ days: Int) -> String {
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
                                subscriptions: [SubscriptionStatus], accountName: (String) -> String,
                                balance: (String) -> Money?) -> [Nudge] {
        var out: [Nudge] = []
        if let n = goal(expenses: expenses, today: today, currency: currency, aim: aim, projectedEnd: projectedEnd) { out.append(n) }
        if let n = unusual(expenses: expenses, today: today, currency: currency) { out.append(n) }
        if let n = upcoming(subscriptions, accountName: accountName, balance: balance) { out.append(n) }
        if out.isEmpty {
            let calm = lastMonthSameDaySpent.cents > 0 && spentSoFar.cents <= lastMonthSameDaySpent.cents
            out.append(Nudge(kind: .praise, key: today.description,
                             title: calm ? "这个月花钱比上个月同期稳。" : "这个月没什么要操心的。",
                             advice: "照这样过就好，有事我会先提醒你。",
                             question: "还有哪里能再省一点？"))
        }
        return out
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

    /// 3 天内要扣的订阅；扣款账户里的钱不够就提醒。
    static func upcoming(_ subs: [SubscriptionStatus], accountName: (String) -> String, balance: (String) -> Money?) -> Nudge? {
        let soon = subs.filter { $0.cancelledOn == nil && ($0.daysLeft ?? 99) <= 3 }
            .sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }
        guard let first = soon.first else { return nil }
        let names = soon.prefix(3).map { "「\($0.name)」" }.joined(separator: "、") + (soon.count > 3 ? " 等 \(soon.count) 个" : "")
        // 同一种币的才加起来；混着币种就不报总数。
        let currencies = Set(soon.map(\.currency))
        let spread = soon.contains(where: { $0.daysLeft != first.daysLeft })
        var title = dayWord(first.daysLeft ?? 0) + (spread ? "起" : "") + "扣\(names)"
        if currencies.count == 1, let c = currencies.first {
            title += "，一共 \(short(soon.reduce(Money.zero) { $0 + $1.amount }, c))。"
        } else {
            title += "。"
        }
        var lacking: [String] = []
        var byAccount: [String: [SubscriptionStatus]] = [:]
        for s in soon { if let a = s.accountID { byAccount[a, default: []].append(s) } }
        for (a, list) in byAccount {
            guard let have = balance(a), Set(list.map(\.currency)).count == 1 else { continue }
            let need = list.reduce(Money.zero) { $0 + $1.amount }
            if have.cents < need.cents { lacking.append("「\(accountName(a))」") }
        }
        let advice = lacking.isEmpty ? (byAccount.isEmpty ? "到时候留意一下扣款账户。" : "扣款账户里的钱够。")
            : "\(lacking.joined(separator: "、"))里的钱不够扣，记得先转一点进去。"
        return Nudge(kind: .upcoming, key: soon.map(\.name).joined(separator: "+"), title: title, advice: advice,
                     question: "这几个订阅里有哪些可以停掉？")
    }
}
