import Foundation

/// D1「要不要提醒」：状态卡怎么拼、固定规则怎么判断、一天最多说几句、同一件事多久不重复。
/// 数字都是 app 算好的；模型只回答「现在值得主动提醒一句吗」。
public struct ReminderSituation: Equatable, Sendable {
    public struct Charge: Equatable, Sendable {
        public var name: String
        public var amount: Money
        public var account: String
        public var balance: Money
        public var inDays: Int
        public init(name: String, amount: Money, account: String, balance: Money, inDays: Int) {
            self.name = name; self.amount = amount; self.account = account; self.balance = balance; self.inDays = inDays
        }
        public var short: Bool { balance < amount }
    }
    public struct Category: Equatable, Sendable {
        public var name: String
        public var amount: Money
        /// 前 3 个月平均。
        public var usual: Money
        public init(name: String, amount: Money, usual: Money) { self.name = name; self.amount = amount; self.usual = usual }
        /// 超过平常一倍（平常太小的不算，免得 2 € 变 5 € 也叫）。
        public var doubled: Bool { usual.cents >= 20_00 && amount.cents >= usual.cents * 2 }
    }

    /// 新记的几笔（一句一笔）。
    public var newEntries: [String] = []
    /// 这个月还能随便花多少、到月底还有几天、平时一天花多少。
    public var left: Money
    public var daysLeft: Int
    public var usualDaily: Money
    public var categories: [Category] = []
    /// 7 天内要扣的钱和对应账户的余额。
    public var charges: [Charge] = []
    /// 重复扣的款（名字）。
    public var duplicates: [String] = []
    /// 涨价的订阅（名字）。
    public var raised: [String] = []
    /// 目标：叫什么、这一站会晚几周（0 是不晚）。
    public var goal: String = ""
    public var goalWeeksLate: Int = 0
    /// 最近 7 天提醒过什么：哪件事、几天前。
    public var recent: [(key: String, daysAgo: Int)] = []
    /// 用户关掉过的那几类。
    public var muted: Set<String> = []
    /// 夏夏记住的偏好（几句话）。
    public var prefs: [String] = []

    public init(left: Money, daysLeft: Int, usualDaily: Money) { self.left = left; self.daysLeft = daysLeft; self.usualDaily = usualDaily }

    public static func == (a: ReminderSituation, b: ReminderSituation) -> Bool { a.card == b.card }

    /// 照现在的速度，月底前钱够不够。
    public var runsShort: Bool { left < Money(cents: usualDaily.cents * Int64(max(daysLeft, 0))) && daysLeft > 0 }

    /// 给模型看的状态卡：纯文字，一行一件事。
    public var card: String {
        var lines: [String] = []
        lines.append("新记的：" + (newEntries.isEmpty ? "没有" : newEntries.joined(separator: "；")))
        let need = Money(cents: usualDaily.cents * Int64(max(daysLeft, 0)))
        lines.append("本月还能随便花 \(left.formatted)，到月底还有 \(daysLeft) 天；平时一天花 \(usualDaily.formatted)，照这样到月底要 \(need.formatted)，\(runsShort ? "不够" : "够")。")
        if !categories.isEmpty {
            lines.append("各类这个月 / 前 3 个月平均：" + categories.map { "\($0.name) \($0.amount.formatted) / \($0.usual.formatted)\($0.doubled ? "（超过一倍）" : "")" }.joined(separator: "；"))
        }
        lines.append("7 天内要扣的：" + (charges.isEmpty ? "没有" : charges.map {
            "\($0.name) \($0.amount.formatted)，\($0.inDays) 天后从\($0.account)扣，\($0.account)现在有 \($0.balance.formatted)\($0.short ? "（不够）" : "")"
        }.joined(separator: "；")))
        if !duplicates.isEmpty { lines.append("重复扣款：" + duplicates.joined(separator: "、")) }
        if !raised.isEmpty { lines.append("涨价的订阅：" + raised.joined(separator: "、")) }
        if !goal.isEmpty { lines.append("目标「\(goal)」：" + (goalWeeksLate > 0 ? "照现在会晚 \(goalWeeksLate) 周" : "按计划在走")) }
        lines.append("最近 7 天提醒过：" + (recent.isEmpty ? "没有" : recent.map { "\(Topic.Kind(rawValue: $0.key.split(separator: ":").first.map(String.init) ?? "")?.title ?? $0.key)（\($0.daysAgo) 天前）" }.joined(separator: "；")))
        if !muted.isEmpty { lines.append("用户关掉了这几类提醒：" + muted.sorted().compactMap { Topic.Kind(rawValue: $0)?.title }.joined(separator: "、")) }
        if !prefs.isEmpty { lines.append("用户的偏好：" + prefs.joined(separator: "；")) }
        return lines.joined(separator: "\n")
    }

    /// 可以提醒的一件事。
    public struct Topic: Equatable, Sendable {
        public enum Kind: String, CaseIterable, Sendable {
            case shortBalance, duplicate, doubled, runsShort, goalLate, raised
            public var title: String {
                switch self {
                case .shortBalance: "余额不够扣款"
                case .duplicate: "重复扣款"
                case .doubled: "某类花销超平常一倍"
                case .runsShort: "钱月底前会不够"
                case .goalLate: "目标推迟"
                case .raised: "订阅涨价"
                }
            }
        }
        public var kind: Kind
        /// 同一件事的记号（「shortBalance:房租」），用来不重复说。
        public var key: String
        /// 用固定说法拼的那一句（没连大模型时就说这句）。
        public var sentence: String
    }

    /// 现在有哪些事值得说，要紧的在前。关掉过的那几类不在里面。
    public var topics: [Topic] {
        var out: [Topic] = []
        for c in charges where c.short {
            out.append(Topic(kind: .shortBalance, key: "shortBalance:\(c.name)", sentence: "\(c.inDays) 天后要扣\(c.name) \(c.amount.formatted)，\(c.account)里只有 \(c.balance.formatted)，还差 \((c.amount - c.balance).formatted)。"))
        }
        for d in duplicates { out.append(Topic(kind: .duplicate, key: "duplicate:\(d)", sentence: "\(d)好像扣了两次，看一眼？")) }
        for c in categories where c.doubled {
            out.append(Topic(kind: .doubled, key: "doubled:\(c.name)", sentence: "这个月\(c.name)花了 \(c.amount.formatted)，平常是 \(c.usual.formatted)，多了一倍多。"))
        }
        if runsShort { out.append(Topic(kind: .runsShort, key: "runsShort", sentence: "照这样花，到月底前能随便花的 \(left.formatted) 不够，后面几天省着点。")) }
        if goalWeeksLate >= 2 { out.append(Topic(kind: .goalLate, key: "goalLate:\(goal)", sentence: "「\(goal)」照现在的速度会晚 \(goalWeeksLate) 周。")) }
        for r in raised { out.append(Topic(kind: .raised, key: "raised:\(r)", sentence: "\(r)涨价了，看看还要不要留着。")) }
        return out.filter { !muted.contains($0.kind.rawValue) }
    }

    /// 3 天内说过的同一件事不算。
    public var freshTopics: [Topic] {
        topics.filter { t in !recent.contains { $0.key == t.key && $0.daysAgo < ReminderRules.repeatDays } }
    }

    /// 固定规则（没密钥或调用失败时用）：只提醒余额不够扣款和重复扣款。
    public var fallbackTopic: Topic? { freshTopics.first { $0.kind == .shortBalance || $0.kind == .duplicate } }
}

public enum ReminderRules {
    /// 一天最多主动说几句。
    public static let maxPerDay = 1
    /// 同一件事几天内不重复。
    public static let repeatDays = 3
}

/// D1 跑完以后怎么办。
public enum ReminderResult: Equatable, Sendable {
    /// 出一张夏夏消息卡，说这件事。
    case show(ReminderSituation.Topic, DecisionOutcome)
    /// 值得说，但今天已经说过一句了：存着，并进晚间小结。
    case later(ReminderSituation.Topic, DecisionOutcome)
    /// 不说。
    case quiet(DecisionOutcome)
}

public enum ReminderDecision {
    /// 拿模型给的概率（没有就是 nil）决定要不要提醒、说哪件事。
    /// - 有概率：到了临界点，而且确实有一件 3 天内没说过、用户没关掉的事，才说；说最要紧的那件。
    /// - 没概率：按固定规则，只说余额不够扣款和重复扣款。
    /// - 今天已经说过一句：不出卡，存到晚上。
    public static func resolve(_ s: ReminderSituation, probability: Double?, threshold: Double, saidToday: Int, fallbackReason: String = "没连决策模型") -> ReminderResult {
        let fallback = s.fallbackTopic
        let outcome = DecisionMath.decide(probability: probability, threshold: threshold, fallbackYes: fallback != nil, fallbackReason: fallbackReason)
        let topic = outcome.source == .model ? s.freshTopics.first : fallback
        guard outcome.yes, let topic else { return .quiet(outcome) }
        return saidToday >= ReminderRules.maxPerDay ? .later(topic, outcome) : .show(topic, outcome)
    }

    /// 三组示例：明显该说、明显不用说、擦边。全是编的数。
    public static func sample(_ which: Sample) -> ReminderSituation {
        func eur(_ c: Int64) -> Money { Money(cents: c) }
        switch which {
        case .yes:
            var s = ReminderSituation(left: eur(96_00), daysLeft: 12, usualDaily: eur(31_00))
            s.newEntries = ["餐饮 48,00 €（Bar Luna，日常卡）"]
            s.categories = [.init(name: "餐饮", amount: eur(212_00), usual: eur(92_00)), .init(name: "超市", amount: eur(142_19), usual: eur(160_00))]
            s.charges = [.init(name: "房租", amount: eur(650_00), account: "日常卡", balance: eur(412_60), inDays: 3)]
            s.goal = "换新电脑"; s.goalWeeksLate = 3
            return s
        case .no:
            var s = ReminderSituation(left: eur(976_61), daysLeft: 12, usualDaily: eur(31_00))
            s.newEntries = ["咖啡 3,20 €（Café Nube，现金）"]
            s.categories = [.init(name: "咖啡", amount: eur(28_80), usual: eur(41_00)), .init(name: "超市", amount: eur(142_19), usual: eur(160_00))]
            s.charges = [.init(name: "房租", amount: eur(650_00), account: "日常卡", balance: eur(1496_61), inDays: 13)]
            s.goal = "换新电脑"
            return s
        case .edge:
            var s = ReminderSituation(left: eur(402_00), daysLeft: 12, usualDaily: eur(31_00))
            s.newEntries = ["衣服 89,00 €（Tienda Azul，日常卡）"]
            s.categories = [.init(name: "衣服", amount: eur(89_00), usual: eur(57_00)), .init(name: "餐饮", amount: eur(118_00), usual: eur(92_00))]
            s.charges = [.init(name: "手机分期", amount: eur(200_00), account: "日常卡", balance: eur(260_00), inDays: 6)]
            s.goal = "换新电脑"; s.goalWeeksLate = 1
            s.recent = [(key: "doubled:餐饮", daysAgo: 2)]
            return s
        }
    }
    public enum Sample: String, CaseIterable, Sendable { case yes, no, edge }
}

extension TrialBook {
    public struct ReminderEntry: Equatable, Sendable {
        public var key: String
        public var daysAgo: Int
        /// true 是出了消息卡；false 是当天已经说过一句，存着并进晚间小结的。
        public var shown: Bool
        public var text: String
        public init(key: String, daysAgo: Int, shown: Bool, text: String) { self.key = key; self.daysAgo = daysAgo; self.shown = shown; self.text = text }
    }

    /// 拼「今天的情况」：数都从账本里现算。
    public func reminderSituation(newEntries: [String] = [], prefs: [String] = []) -> ReminderSituation {
        var s = ReminderSituation(left: month.left, daysLeft: month.daysLeft, usualDaily: usualDailySpend)
        s.newEntries = newEntries
        // 各类：这个月 / 前几个月存下来的平均（没有就用上个月）
        s.categories = spendByCategory.map { c in
            let past = pastMonths.compactMap { m in m.slices.first { $0.name == c.name }?.amount }
            let usual = past.isEmpty ? c.lastMonth : Money(cents: past.map(\.cents).reduce(0, +) / Int64(past.count))
            return .init(name: c.name, amount: c.amount, usual: usual)
        }
        // 7 天内要扣的：账户记在这一行上就用它，没记就是第一个日常能用的
        let daily = accounts.first { $0.side == .life && $0.kind == .own && $0.block == .daily }
        s.charges = upcoming.compactMap { u in
            guard let days = Self.daysUntil(u.meta, today: todayDay), days <= 7 else { return nil }
            let acc = account(u.account) ?? daily
            return .init(name: u.name, amount: u.amount.magnitude, account: acc?.name ?? "", balance: acc?.balance ?? .zero, inDays: days)
        }
        // 重复扣款：同一天、同一家、同样的钱记了两笔
        var seen: Set<String> = [], dup: [String] = []
        for e in entries where e.side == .life && e.amount < .zero && !e.place.isEmpty {
            let k = "\(e.daysAgo)|\(e.place)|\(e.amount.cents)"
            if !seen.insert(k).inserted, !dup.contains(e.place) { dup.append(e.place) }
        }
        s.duplicates = dup
        s.goal = journey.total > .zero && !journey.isFinished ? journey.name : ""
        s.recent = reminderLog.filter { $0.daysAgo <= 7 }.map { (key: $0.key, daysAgo: $0.daysAgo) }
        s.muted = mutedReminders
        s.prefs = prefs
        return s
    }

    /// 「12 月 5 日 · …」这样的一行里，离今天还有几天（示例账本的今天是 11 月的 `today` 号；认不出返回 nil）。
    static func daysUntil(_ meta: String, today: Int) -> Int? {
        let parts = meta.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        let (m, d) = (parts[0], parts[1])
        if m == 11 { return d >= today ? d - today : nil }
        if m == 12 { return 30 - today + d }
        return nil
    }

    /// 给聊天模型带上的那几个数（app 算好的；不是账本原文）。
    public var numbersCard: String {
        var lines = ["这个月还能随便花 \(month.left.formatted)，到月底还有 \(month.daysLeft) 天。",
                     "这个月进账 \(month.income.formatted)，固定要付 \(month.fixed.formatted)，留给目标 \(month.forGoals.formatted)，平时已经花了 \(month.spent.formatted)。",
                     "一共有 \(totals.have.formatted)，欠 \(totals.owe.formatted)，净剩 \(totals.net.formatted)。"]
        let top = spendSlices(limit: 5).map { "\($0.name) \($0.amount.formatted)" }.joined(separator: "、")
        if !top.isEmpty { lines.append("这个月花得最多的：\(top)。") }
        if journey.total > .zero { lines.append("大目标「\(journey.name)」：存了 \(journey.saved.formatted)，一共要 \(journey.total.formatted)。") }
        return lines.joined(separator: "\n")
    }
}
