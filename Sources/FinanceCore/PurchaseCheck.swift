import Foundation

/// 「这个要不要买」：买之前算三件事，再给一句固定说法的意见。问夏夏时用。
public struct PurchaseCheck: Equatable, Sendable {
    public enum Verdict: String, Sendable { case ok, wait, no }

    public var name: String
    public var price: Money
    /// 买了以后，这个月还能随便花多少（可能是负的）。
    public var leftAfter: Money
    /// 等于平时几天的花销（不知道平时花多少就是 nil）。
    public var days: Int?
    /// 如果从目标里拿，目标晚几周（没有目标或没定每月存多少就是 nil）。
    public var weeksLate: Int?
    /// 日常的钱够不够付（不够就得动应急钱）。
    public var fitsDaily: Bool
    public var verdict: Verdict

    /// 夏夏的那一句意见：固定几种说法，不批评人。
    public var line: String {
        switch verdict {
        case .ok: "买得起，不耽误事。"
        case .wait: leftAfter >= .zero ? "买得起，这个月会紧一点。先放两天？" : "这个月随便花的不够了，等下个月？"
        case .no: "现在买得动应急钱，先别买。"
        }
    }

    /// 从一句话里认出想买什么、多少钱：「想买个降噪耳机 279」→ 降噪耳机 279 €。没有数字就认不出。
    public static func parseWant(_ text: String) -> (name: String, price: Money)? {
        guard let q = QuickPhrase.parse(text) else { return nil }
        var name = q.name
        for f in ["这个值得买吗", "值得买吗", "要不要买", "能不能买", "买得起吗", "我想买", "想买", "要买", "想要", "买个", "买一个", "一个", "个", "？", "?", "吗"] {
            name = name.replacingOccurrences(of: f, with: "")
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty || name == "一笔开销" ? "这样东西" : name, q.amount)
    }
}

extension TrialBook {
    /// 买之前算一算。规则：
    /// - 日常账户里的钱不够付 → 别买（要动应急钱）
    /// - 买完这个月随便花的变成负的 → 先等等
    /// - 一下花掉这个月剩下随便花的三成以上 → 买得起，但先放两天
    /// - 其余 → 买得起
    public func checkPurchase(name: String, price: Money) throws -> PurchaseCheck {
        guard price > .zero else { throw TrialError("价钱要比 0 大") }
        let left = month.left
        let after = left - price
        let fits = price <= sum(.daily)
        let days = usualDailySpend > .zero ? Int((price.cents + usualDailySpend.cents - 1) / usualDailySpend.cents) : nil
        let weeks = journey.total > .zero && journey.monthlyPlan > .zero
            ? Int((Double(price.cents) / Double(journey.monthlyPlan.cents) * 4.33).rounded()) : nil
        let verdict: PurchaseCheck.Verdict
        if !fits { verdict = .no }
        else if after < .zero { verdict = .wait }
        else if price.cents * 10 > left.cents * 3 { verdict = .wait }
        else { verdict = .ok }
        return PurchaseCheck(name: name, price: price, leftAfter: after, days: days, weeksLate: weeks, fitsDaily: fits, verdict: verdict)
    }
}
