import Foundation

// 欠款改分期（ming 2026-11-23）：给一笔欠款（我欠的、欠我的都行）排个还款计划，填每月还多少或分几期，
// 自动算出每期日期和金额，某一期可以手动改。
// 多还：问多出来的是「抵最后几期」（早点还清）还是「之后每期变少」；少还或晚还：问差的「补到下期」还是「顺延一期」。
// 计划的改动都记进改动记录，能撤销。
//
// 口径：计划里每期的金额加起来 = 排计划那时还欠的钱。排计划那时已经还了多少记在 planBase，
// 之后的还款从第一期开始依次「填」：累计还到第几期的合计，就算还完了第几期。
// 多还 / 少还要调整时，只改这一期之后的金额和期数，前面的不动，所以「第 3 / 12 期」一直数得对。

/// 还款计划里的一期。
public struct PlannedPayment: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var amount: Money
    public init(date: LocalDate, amount: Money) { self.date = date; self.amount = amount }
}

/// 计划现在还到哪了。
public struct DebtPlanProgress: Equatable, Sendable {
    /// 共几期。
    public var count: Int
    /// 已经还完几期。
    public var paidCount: Int
    /// 正在还的这一期是第几期（从 0 数），还完了是 nil。
    public var currentIndex: Int?
    /// 这一期哪天到期。
    public var nextDate: LocalDate?
    /// 这一期还差多少（这一期已经还了一部分时，只算差的）。
    public var nextAmount: Money
    /// 这一期过了日子还没还够。
    public var overdue: Bool
    /// 最后一期的日期：按计划哪天还清。
    public var finish: LocalDate?
    public var remainingCount: Int { count - paidCount }
}

/// 多还 / 少还时怎么调计划。
public enum RepayAdjust: String, Codable, Sendable, CaseIterable {
    /// 多还：多出来的抵最后几期，期数变少、早点还清。
    case shortenPlan = "shorten"
    /// 多还：期数不变，之后每期变少。
    case lowerPayments = "lower"
    /// 少还（或这期没还）：差的补到下一期。
    case addToNext = "next"
    /// 少还（或这期没还）：差的放到最后，多加一期（顺延一期）。
    case extendPlan = "extend"

    public var label: String {
        switch self {
        case .shortenPlan: "抵最后几期，早点还清"
        case .lowerPayments: "之后每期少还一点"
        case .addToNext: "差的补到下一期"
        case .extendPlan: "顺延一期，差的放到最后"
        }
    }

    public var isForOverpay: Bool { self == .shortenPlan || self == .lowerPayments }

    /// 「shorten」「抵最后几期」「lower」「next」「extend」「顺延」都认。
    public init?(text: String) {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let x = RepayAdjust(rawValue: t) { self = x; return }
        switch t {
        case "shorten_plan", "抵最后几期", "早点还清", "提前还清": self = .shortenPlan
        case "lower_payments", "每期变少", "之后每期变少", "每期少还": self = .lowerPayments
        case "add_to_next", "补到下期", "补到下一期": self = .addToNext
        case "extend_plan", "顺延", "顺延一期": self = .extendPlan
        default: return nil
        }
    }
}

/// 记还款之前先看看：这笔比这期该还的多还是少、每种调法调完哪天还清。app 弹选项、AI 问用户都用它。
public struct RepayPreview: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public var adjust: RepayAdjust
        /// 调完以后哪天还清。
        public var finish: LocalDate?
        /// 比原来早几个月还清（负数 = 晚几个月）。
        public var monthsEarlier: Int
        /// 调完以后下一期还多少。
        public var nextAmount: Money?
        /// 一句大白话，比如「之后每期还 40,00 €，还是 2027-03 还清」。
        public var detail: String
    }
    /// 这期该还多少。
    public var due: Money
    /// 这笔减这期该还的：正数 = 多还，负数 = 少还。
    public var difference: Money
    /// 有计划、而且多还或少还了才有选项；还清了或刚好就是空的。
    public var options: [Option]
    public var paysOff: Bool
}

public enum DebtPlanError: Error, LocalizedError, Equatable {
    case nothingOwed
    case badSchedule(String)
    case noPlan(String)
    case periodPaid(Int)

    public var errorDescription: String? {
        switch self {
        case .nothingOwed: "这笔已经还清了，不用排计划"
        case .badSchedule(let s): s
        case .noPlan(let who): "和「\(who)」的这笔还没排还款计划"
        case .periodPaid(let n): "第 \(n) 期已经还完了，只能改还没还的期"
        }
    }
}

public enum DebtPlans {
    /// 按每月还多少排：从 start 开始每月一期，最后一期吃掉零头。
    public static func schedule(outstanding: Money, start: LocalDate, perMonth: Money) -> [PlannedPayment] {
        guard outstanding.cents > 0, perMonth.cents > 0 else { return [] }
        var left = outstanding.cents
        var out: [PlannedPayment] = []
        var i = 0
        while left > 0 && i < 600 {
            let a = min(perMonth.cents, left)
            out.append(PlannedPayment(date: start.adding(months: i), amount: Money(cents: a)))
            left -= a; i += 1
        }
        return out
    }

    /// 按分几期排：每期一样多，除不尽的零头放在最后一期。
    public static func schedule(outstanding: Money, start: LocalDate, count: Int) -> [PlannedPayment] {
        guard outstanding.cents > 0, count > 0 else { return [] }
        let per = outstanding.cents / Int64(count)
        return (0..<count).map { i in
            let a = i == count - 1 ? outstanding.cents - per * Int64(count - 1) : per
            return PlannedPayment(date: start.adding(months: i), amount: Money(cents: a))
        }.filter { $0.amount.cents > 0 }
    }

    /// 计划还到哪了：paid = 排计划之后一共还了多少。
    public static func progress(_ plan: [PlannedPayment], paid: Money, today: LocalDate) -> DebtPlanProgress {
        var cum: Int64 = 0
        var p = DebtPlanProgress(count: plan.count, paidCount: plan.count, currentIndex: nil, nextDate: nil,
                                 nextAmount: .zero, overdue: false, finish: plan.last?.date)
        for (i, x) in plan.enumerated() {
            cum += x.amount.cents
            if cum > paid.cents {
                p.paidCount = i
                p.currentIndex = i
                p.nextDate = x.date
                p.nextAmount = Money(cents: cum - paid.cents)
                p.overdue = x.date < today
                break
            }
        }
        return p
    }

    /// 按某种调法调计划。payment 是这次还的钱，paid 是这次之前（排计划之后）已经还了多少。
    /// 返回调好的计划；不用调（没多没少、或者还清了）返回 nil。
    static func adjusted(_ plan: [PlannedPayment], paid: Money, payment: Money, adjust: RepayAdjust,
                         today: LocalDate) -> [PlannedPayment]? {
        let before = progress(plan, paid: paid, today: today)
        guard let k = before.currentIndex else { return nil }
        let total = plan.reduce(Int64(0)) { $0 + $1.amount.cents }
        guard paid.cents + payment.cents < total else { return nil }   // 这次就还清了
        let diff = payment.cents - before.nextAmount.cents
        var p = plan
        if diff > 0 {
            guard adjust.isForOverpay else { return nil }
            // 这一期算多还了 diff，后面一共少 diff。
            p[k].amount = Money(cents: p[k].amount.cents + diff)
            var future = Array(p[(k + 1)...])
            let futureSum = future.reduce(Int64(0)) { $0 + $1.amount.cents } - diff
            switch adjust {
            case .shortenPlan:
                var cut = diff
                while cut > 0, let last = future.last {
                    if last.amount.cents <= cut { cut -= last.amount.cents; future.removeLast() }
                    else { future[future.count - 1].amount = Money(cents: last.amount.cents - cut); cut = 0 }
                }
            default:
                let n = Int64(future.count)
                guard n > 0 else { return nil }
                let per = futureSum / n
                for j in future.indices {
                    future[j].amount = Money(cents: j == future.count - 1 ? futureSum - per * (n - 1) : per)
                }
                future.removeAll { $0.amount.cents <= 0 }
            }
            return Array(p[...k]) + future
        } else if diff < 0 {
            guard !adjust.isForOverpay else { return nil }
            let short = -diff
            if adjust == .extendPlan && p[k].amount.cents - short <= 0 {
                // 这一期一分没还：从这一期起每期都往后挪一个月（顺延一期），金额不变。
                for j in k..<p.count { p[j].date = p[j].date.adding(months: 1) }
                return p
            }
            // 这一期就按这次还的算完，差的挪走：补到下一期，或者放到最后多加一期。
            p[k].amount = Money(cents: p[k].amount.cents - short)
            if adjust == .addToNext && k + 1 < p.count {
                p[k + 1].amount = Money(cents: p[k + 1].amount.cents + short)
            } else {
                let lastDate = p.last?.date ?? today
                p.append(PlannedPayment(date: lastDate.adding(months: 1), amount: Money(cents: short)))
            }
            p.removeAll { $0.amount.cents <= 0 }
            return p
        }
        return nil
    }

    /// 改其中一期（index 从 0 数）的金额：合计不变，差出来的从后面几期找补——
    /// 改多了，后面按原来的金额从前往后填、填不满的砍掉；改少了，多出来的加到最后一期（改的是最后一期就新加一期）。
    /// 这一期改得比合计还多时返回 nil。
    public static func rebalanced(_ plan: [PlannedPayment], index: Int, amount: Money, date: LocalDate? = nil) -> [PlannedPayment]? {
        guard plan.indices.contains(index), amount.cents > 0 else { return nil }
        var p = plan
        let total = p.reduce(Int64(0)) { $0 + $1.amount.cents }
        p[index].amount = amount.magnitude
        if let date { p[index].date = date }
        let head = p[...index].reduce(Int64(0)) { $0 + $1.amount.cents }
        guard head <= total else { return nil }
        var rest = total - head
        var tail: [PlannedPayment] = []
        for t in p[(index + 1)...] where rest > 0 {
            let a = min(t.amount.cents, rest)
            tail.append(PlannedPayment(date: t.date, amount: Money(cents: a)))
            rest -= a
        }
        if rest > 0 {
            if tail.isEmpty { tail.append(PlannedPayment(date: p[index].date.adding(months: 1), amount: Money(cents: rest))) }
            else { tail[tail.count - 1].amount = Money(cents: tail[tail.count - 1].amount.cents + rest) }
        }
        return Array(p[...index]) + tail
    }

    /// 两个日子差几个月（b 比 a 晚是正数）。
    static func months(from a: LocalDate, to b: LocalDate) -> Int { (b.year - a.year) * 12 + b.month - a.month }

    /// 还清时间线上的一笔：这笔哪天还清。
    public struct Payoff: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var outstanding: Money
        /// nil = 没约日子。
        public var finish: LocalDate?
        public var isInstallment: Bool
    }

    /// 「欠款与分期」页顶上的几个数。
    public struct Overview: Equatable, Sendable {
        public var iOwe: Money
        public var owedToMe: Money
        /// 这个月（到月底）我要还多少：分期这一期 + 借来的钱按计划这月该还的（没计划就看约定日子在不在这个月）。
        public var dueThisMonth: Money
        /// 这个月该收回来的。
        public var incomingThisMonth: Money
        /// 我欠的每一笔哪天还清（按日子排，没约的放最后）。
        public var payoffs: [Payoff]
        /// 照现在的还法，我欠的全部还清的那天；有没约日子的就是 nil。
        public var allClear: LocalDate? {
            guard !payoffs.isEmpty, payoffs.allSatisfy({ $0.finish != nil }) else { return nil }
            return payoffs.compactMap(\.finish).max()
        }
        public var undatedCount: Int { payoffs.filter { $0.finish == nil }.count }
    }
}

extension Ledger {
    /// 这笔欠款排计划之后已经还了多少。
    func paidSincePlan(_ d: Debt) -> Money {
        let repaid = Plans.amounts(d.repaymentIDs, in: transactions)
        return Money(cents: max(0, repaid.cents - (d.planBase?.cents ?? 0)))
    }

    /// 这笔欠款的计划进度；没计划是 nil。
    public func planProgress(_ debtID: UUID, today: LocalDate = .today) -> DebtPlanProgress? {
        guard let d = debts.first(where: { $0.id == debtID }), let plan = d.plan, !plan.isEmpty else { return nil }
        return DebtPlans.progress(plan, paid: paidSincePlan(d), today: today)
    }

    func outstanding(_ d: Debt) -> Money {
        Money(cents: max(0, d.principal.cents - Plans.amounts(d.repaymentIDs, in: transactions).cents))
    }

    /// 给一笔欠款排还款计划（或者重排）：perMonth 和 count 填一个。start 是第一期哪天。
    @discardableResult
    public mutating func planDebt(_ debtID: UUID, perMonth: Money? = nil, count: Int? = nil, start: LocalDate,
                                  author: String) throws -> ChangeRecord {
        guard let i = debts.firstIndex(where: { $0.id == debtID }) else { throw EditError.unknownDebt }
        let d = debts[i]
        let left = outstanding(d)
        guard !d.closed, left.cents > 0 else { throw DebtPlanError.nothingOwed }
        let plan: [PlannedPayment]
        if let perMonth {
            guard perMonth.cents > 0 else { throw EditError.amountMustBePositive }
            plan = DebtPlans.schedule(outstanding: left, start: start, perMonth: perMonth.magnitude)
            guard plan.count <= 120 else { throw DebtPlanError.badSchedule("每月 \(perMonth.formatted) 要还 \(plan.count) 个月，太久了，多还一点或者改成分几期") }
        } else if let count {
            guard (1...120).contains(count) else { throw DebtPlanError.badSchedule("分期要在 1 到 120 期之间") }
            plan = DebtPlans.schedule(outstanding: left, start: start, count: count)
        } else {
            throw DebtPlanError.badSchedule("填每月还多少，或者分几期")
        }
        return try setDebtPlan(debtID, plan: plan, author: author)
    }

    /// 直接写一份计划（app 里每期改过金额以后保存）。每期加起来要等于还欠的钱。
    @discardableResult
    public mutating func setDebtPlan(_ debtID: UUID, plan: [PlannedPayment], author: String) throws -> ChangeRecord {
        guard let i = debts.firstIndex(where: { $0.id == debtID }) else { throw EditError.unknownDebt }
        let old = debts[i]
        let left = outstanding(old)
        guard !old.closed, left.cents > 0 else { throw DebtPlanError.nothingOwed }
        let clean = plan.filter { $0.amount.cents > 0 }.sorted { $0.date < $1.date }
        guard !clean.isEmpty else { throw DebtPlanError.badSchedule("计划里至少要有一期") }
        let sum = clean.reduce(Money.zero) { $0 + $1.amount }
        guard sum == left else {
            throw DebtPlanError.badSchedule("每期加起来是 \(sum.formatted)，还欠 \(left.formatted)，要一样才行")
        }
        if let oldPlan = old.plan, !oldPlan.isEmpty {
            // 重排：已经还完的期留着（「第几期」还数得对），这一期还了一部分的，把还了的那部分记成一期。
            let paid = paidSincePlan(old)
            let prog = DebtPlans.progress(oldPlan, paid: paid, today: .today)
            let k = prog.currentIndex ?? oldPlan.count
            var prefix = Array(oldPlan[..<k])
            let partial = paid.cents - prefix.reduce(Int64(0)) { $0 + $1.amount.cents }
            if partial > 0, k < oldPlan.count { prefix.append(PlannedPayment(date: oldPlan[k].date, amount: Money(cents: partial))) }
            debts[i].plan = prefix + clean
        } else {
            debts[i].plan = clean
            debts[i].planBase = Plans.amounts(old.repaymentIDs, in: transactions)
        }
        let who = old.direction == .theyOweMe ? "\(old.counterparty)还我" : "还\(old.counterparty)"
        let per = Set(clean.dropLast().map(\.amount)).count <= 1 ? "，每期 \(clean[0].amount.formatted)" : ""
        let text = (old.plan == nil ? "排还款计划：" : "重排还款计划：") + "\(who) \(left.formatted)，分 \(clean.count) 期\(per)，\(clean.last!.date) 还清"
        let change = snapshotChange(.debt, text, before: PlanSnapshot(debts: [old]), author: author)
        changes.append(change)
        return change
    }

    /// 只改其中一期（index 从 0 数）：差出来的钱从最后几期找补（改多了，最后几期少还；改少了，多加到最后一期）。
    @discardableResult
    public mutating func editPlannedPayment(_ debtID: UUID, index: Int, amount: Money, date: LocalDate? = nil,
                                            author: String) throws -> ChangeRecord {
        guard let d = debts.first(where: { $0.id == debtID }) else { throw EditError.unknownDebt }
        guard let plan = d.plan, plan.indices.contains(index) else { throw DebtPlanError.noPlan(d.counterparty) }
        let prog = DebtPlans.progress(plan, paid: paidSincePlan(d), today: .today)
        guard index >= (prog.currentIndex ?? plan.count) else { throw DebtPlanError.periodPaid(index + 1) }
        guard amount.cents > 0 else { throw EditError.amountMustBePositive }
        guard let result = DebtPlans.rebalanced(plan, index: index, amount: amount, date: date) else {
            throw DebtPlanError.badSchedule("这一期改成 \(amount.formatted) 就超过还欠的钱了")
        }
        // 已经还完的期留着、planBase 不变，这样「第几期」还数得对。
        guard let i = debts.firstIndex(where: { $0.id == debtID }) else { throw EditError.unknownDebt }
        let old = debts[i]
        debts[i].plan = result
        let change = snapshotChange(.debt, "改还款计划：和\(d.counterparty)的第 \(index + 1) 期改成 \(amount.formatted)，\(debts[i].plan!.last!.date) 还清",
                                    before: PlanSnapshot(debts: [old]), author: author)
        changes.append(change)
        return change
    }

    /// 不要计划了（还是一笔欠款，只是不分期）。
    @discardableResult
    public mutating func clearDebtPlan(_ debtID: UUID, author: String) throws -> ChangeRecord {
        guard let i = debts.firstIndex(where: { $0.id == debtID }) else { throw EditError.unknownDebt }
        let old = debts[i]
        guard old.plan != nil else { throw DebtPlanError.noPlan(old.counterparty) }
        debts[i].plan = nil
        debts[i].planBase = nil
        let change = snapshotChange(.debt, "取消和\(old.counterparty)的还款计划", before: PlanSnapshot(debts: [old]), author: author)
        changes.append(change)
        return change
    }

    /// 记还款之前看看：多还 / 少还了多少，每种调法调完哪天还清。
    public func repayPreview(_ debtID: UUID, amount: Money, today: LocalDate = .today) -> RepayPreview? {
        guard let d = debts.first(where: { $0.id == debtID }), let plan = d.plan, !plan.isEmpty else { return nil }
        let paid = paidSincePlan(d)
        let prog = DebtPlans.progress(plan, paid: paid, today: today)
        let pay = amount.magnitude
        let total = plan.reduce(Money.zero) { $0 + $1.amount }
        let paysOff = paid.cents + pay.cents >= total.cents
        let diff = Money(cents: pay.cents - prog.nextAmount.cents)
        var options: [RepayPreview.Option] = []
        if !paysOff && diff.cents != 0 {
            let kinds: [RepayAdjust] = diff.cents > 0 ? [.shortenPlan, .lowerPayments] : [.addToNext, .extendPlan]
            for k in kinds {
                guard let p = DebtPlans.adjusted(plan, paid: paid, payment: pay, adjust: k, today: today) else { continue }
                let after = DebtPlans.progress(p, paid: paid + pay, today: today)
                let earlier = prog.finish.flatMap { f in after.finish.map { DebtPlans.months(from: $0, to: f) } } ?? 0
                var detail: String
                switch k {
                case .shortenPlan:
                    detail = earlier > 0 ? "\(after.finish.map { "\($0.year) 年 \($0.month) 月" } ?? "")还清，提前 \(earlier) 个月" : "最后一期少还一点"
                case .lowerPayments:
                    detail = "之后每期还 \(after.nextAmount.formatted)，还是 \(after.finish.map { "\($0.year) 年 \($0.month) 月" } ?? "")还清"
                case .addToNext:
                    detail = "下一期还 \(after.nextAmount.formatted)，还清日子不变"
                case .extendPlan:
                    detail = "多一期，\(after.finish.map { "\($0.year) 年 \($0.month) 月" } ?? "")还清" + (earlier < 0 ? "，晚 \(-earlier) 个月" : "")
                }
                options.append(.init(adjust: k, finish: after.finish, monthsEarlier: earlier, nextAmount: after.currentIndex == nil ? nil : after.nextAmount, detail: detail))
            }
        }
        return RepayPreview(due: prog.nextAmount, difference: diff, options: options, paysOff: paysOff)
    }

    /// 记一笔还款，顺便按 adjust 调计划（一条改动，撤销时还款和计划一起回去）。
    /// 没计划、没多没少或 adjust 是 nil 时就是普通的记还款。
    @discardableResult
    public mutating func repay(debtID: UUID, amount: Money, date: LocalDate, accountID: String,
                               adjust: RepayAdjust?, author: String) throws -> ChangeRecord {
        guard let old = debts.first(where: { $0.id == debtID }) else { throw EditError.unknownDebt }
        var newPlan: [PlannedPayment]? = nil
        if let adjust, let plan = old.plan {
            newPlan = DebtPlans.adjusted(plan, paid: paidSincePlan(old), payment: amount.magnitude, adjust: adjust, today: date)
        }
        var change = try repay(debtID: debtID, amount: amount, date: date, accountID: accountID, author: author)
        guard let newPlan, let i = debts.firstIndex(where: { $0.id == debtID }) else { return change }
        let finishBefore = old.plan?.last?.date
        debts[i].plan = newPlan
        change.before = PlanSnapshot(debts: [old])
        var note = "；" + adjust!.label
        if let f = newPlan.last?.date { note += "，\(f.year) 年 \(f.month) 月还清" }
        if let a = finishBefore, let b = newPlan.last?.date, DebtPlans.months(from: b, to: a) > 0 { note += "（提前 \(DebtPlans.months(from: b, to: a)) 个月）" }
        change.summary += note
        changes[changes.count - 1] = change
        return change
    }

    /// 这一期没还（晚还了）：整期补到下一期，或者顺延（后面每期往后挪一个月）。
    @discardableResult
    public mutating func skipPlannedPayment(_ debtID: UUID, adjust: RepayAdjust, today: LocalDate = .today,
                                            author: String) throws -> ChangeRecord {
        guard let i = debts.firstIndex(where: { $0.id == debtID }) else { throw EditError.unknownDebt }
        let old = debts[i]
        guard let plan = old.plan else { throw DebtPlanError.noPlan(old.counterparty) }
        guard !adjust.isForOverpay else { throw DebtPlanError.badSchedule("这期没还只能选「补到下一期」或「顺延一期」") }
        guard let p = DebtPlans.adjusted(plan, paid: paidSincePlan(old), payment: .zero, adjust: adjust, today: today) else {
            throw DebtPlanError.nothingOwed
        }
        debts[i].plan = p
        let text = "和\(old.counterparty)的这一期先不还：\(adjust.label)，\(p.last!.date.year) 年 \(p.last!.date.month) 月还清"
        let change = snapshotChange(.debt, text, before: PlanSnapshot(debts: [old]), author: author)
        changes.append(change)
        return change
    }
}

extension Plans {
    /// 「欠款与分期」页顶上：我欠的、欠我的、这个月要还多少、哪天全部还清。
    public static func debtOverview(_ ledger: Ledger, today: LocalDate, bookID: String? = nil) -> DebtPlans.Overview {
        let o = obligations(ledger, asOf: today, bookID: bookID)
        let monthEnd = LocalDate(year: today.year, month: today.month, day: LocalDate.daysIn(today.yearMonth))
        var due: Int64 = 0, incoming: Int64 = 0
        var payoffs: [DebtPlans.Payoff] = []
        let instStatus = Dictionary(installments(ledger).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in ledger.installments where bookID == nil || i.bookID == bookID {
            guard let s = instStatus[i.id], s.remaining.cents > 0 else { continue }
            if let n = s.nextDate, n <= monthEnd { due += min(s.perPayment.cents, s.remaining.cents) }
            let lastMonth = i.firstDate.adding(months: i.count - 1)
            payoffs.append(.init(id: i.id, name: i.name, outstanding: s.remaining,
                                 finish: LocalDate(year: lastMonth.year, month: lastMonth.month, day: min(i.firstDate.day, 28)),
                                 isInstallment: true))
        }
        for d in ledger.debts where !d.closed && (bookID == nil || d.bookID == bookID) {
            let left = ledger.outstanding(d)
            guard left.cents > 0 else { continue }
            var thisMonth: Int64 = 0
            var finish: LocalDate? = d.dueDate
            if let plan = d.plan, !plan.isEmpty {
                let paid = ledger.paidSincePlan(d)
                let scheduled = plan.filter { $0.date <= monthEnd }.reduce(Int64(0)) { $0 + $1.amount.cents }
                thisMonth = max(0, scheduled - paid.cents)
                finish = plan.last?.date
            } else if let dd = d.dueDate, dd <= monthEnd {
                thisMonth = left.cents
            }
            if d.direction == .iOweThem {
                due += thisMonth
                payoffs.append(.init(id: d.id, name: "欠\(d.counterparty)", outstanding: left, finish: finish, isInstallment: false))
            } else {
                incoming += thisMonth
            }
        }
        payoffs.sort { a, b in
            switch (a.finish, b.finish) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.name < b.name
            }
        }
        return .init(iOwe: o.iOwe, owedToMe: o.owedToMe, dueThisMonth: Money(cents: due), incomingThisMonth: Money(cents: incoming), payoffs: payoffs)
    }
}
