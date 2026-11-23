import Foundation

// 目标页「小金猪存钱罐」（ming 2026-11-23）：
// 目标 = 把「我想要的东西」变成「哪天能到手」，让人感到小小坚持就有改变。全部 app 自己算，不靠 AI；
// app、fin、MCP 用的是这里同一套规则，所以 AI 说「提前了 3 天」和 app 上小猪旁边写的是同一个数。
//
// 规则：
// - 同时最多 1 个大目标 + 3 个小目标（存够了的不算）。想加第 5 个：「目标不在多，在于坚持」，先完成或删掉一个。
//   大目标 = 钉住的那个（pinned）；老账本没钉过，就按急不急排第一的当大目标。超出 1+3 的老目标不删，只提示用户挑。
// - 每个目标记下真的存在哪：储蓄罐 / 一张银行卡 / 一个固定的地方。每次真的存了钱，都要在这里记一笔。
// - 钱能取出来：猪变轻，到手日子往后推，不责怪。
// - 一个目标 30 天没投币，问「它对你还重要吗」：还重要，继续（30 天内不再问）/ 先放一放（90 天内不再问）/ 删掉。
// - 「忍住了」：用最常买的小东西（比如咖啡）的钱，点一下存进去；记在流水的标签「忍住了」里，月底能数出来。

/// 钱真的放在哪。
public enum GoalStash: String, Codable, Sendable, CaseIterable, Identifiable {
    case jar, card, spot
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .jar: "储蓄罐"
        case .card: "一张银行卡"
        case .spot: "一个固定的地方"
        }
    }
    public var example: String {
        switch self {
        case .jar: "家里的小猪储蓄罐、一个铁盒子"
        case .card: "一张平时不用的卡，或者银行 app 里的储蓄罐"
        case .spot: "抽屉里的信封、书架上的盒子"
        }
    }
    /// 认得出的写法（AI 可能写中文）。
    public init?(loose text: String) {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let v = GoalStash(rawValue: t) { self = v; return }
        if t.contains("罐") || t.contains("猪") { self = .jar }
        else if t.contains("卡") || t.contains("银行") || t.contains("账户") { self = .card }
        else if t.contains("地方") || t.contains("位置") || t.contains("抽屉") || t.contains("信封") { self = .spot }
        else { return nil }
    }
}

public extension Plans {
    /// 小目标最多几个（大目标只有 1 个）。
    static let maxSmallGoals = 3
    /// 同时在存的目标最多几个。
    static var maxActiveGoals: Int { maxSmallGoals + 1 }
    /// 多少天没投币就问「还重要吗」。
    static let goalIdleDays = 30
    /// 「忍住了」存进去的流水带这个标签。
    static let heldBackTag = "忍住了"
    /// 「目标不在多，在于坚持」：给 app、fin、MCP 共用的一句话。
    static let goalLimitSentence = "目标不在多，在于坚持。同时最多 1 个大目标、3 个小目标。"
}

/// 最常买的小东西（比如咖啡）：拿来换算「每天存 2,30 € ≈ 每 2 天少一杯咖啡」，也是「忍住了」按钮的金额。
public struct SmallHabit: Equatable, Sendable, Codable {
    public var name: String
    /// 一般一次花多少（中位数）。
    public var typical: Money
    /// 最近 60 天买了几次。
    public var count60: Int
    /// 上周（周一到周日）几次、这周到今天几次。
    public var lastWeek: Int
    public var thisWeek: Int
    /// 流水里没找到时用的「一杯咖啡 3 €」。
    public var isGuess: Bool

    public static let fallback = SmallHabit(name: "一杯咖啡", typical: Money(cents: 300), count60: 0, lastWeek: 0, thisWeek: 0, isGuess: true)

    /// 「每 2 天少一次 Café Nube」「每天少一次一杯咖啡」：把每天要存的钱说成人话。
    public func phrase(perDay: Money) -> String {
        guard perDay.cents > 0, typical.cents > 0 else { return "" }
        let what = isGuess ? name : "「\(name)」"
        let ratio = Double(typical.cents) / Double(perDay.cents)
        if ratio >= 1.5 { return "每 \(Int(ratio.rounded())) 天少一次\(what)" }
        if ratio >= 0.75 { return "每天少一次\(what)" }
        let n = Int((1 / ratio).rounded())
        return n <= 3 ? "每天少 \(n) 次\(what)" : "差不多每天 \(n) 次\(what)的钱"
    }

    /// 每周小挑战：上周买了几次，这周少一次。上周不到 2 次就不挑战。
    public var challengeLimit: Int? { lastWeek >= 2 ? lastWeek - 1 : nil }
}

/// 一个目标在目标页上要的全部数字。
public struct PiggyGoal: Identifiable, Equatable, Sendable {
    public var forecast: GoalForecast
    public var id: UUID { forecast.id }
    public var name: String { forecast.name }
    public var icon: String?
    public var stash: GoalStash?
    public var stashNote: String?
    public var isMain: Bool
    /// 每天存多少：定了日子 = 按时到要的；没定 = 照最近的速度。
    public var perDay: Money?
    /// 哪天能到手：照最近的速度算；最近没存但定了日子，就是定的日子（按时存的话）。
    public var arrival: LocalDate?
    /// 最近一次投币是哪天（建目标那天也算）。
    public var lastDeposit: LocalDate?
    public var idleDays: Int
    /// 该问「它对你还重要吗」了。
    public var needsCheck: Bool
    /// 这个月「忍住了」几次、一共存了多少、因此提前了几天。
    public var heldBackCount: Int
    public var heldBackSaved: Money
    public var heldBackDays: Int
    /// 这个月哪几天投过币（日子）。
    public var depositDays: Set<Int>
}

/// 目标页一整页：1 个大目标、最多 3 个小目标、超出的、存够了的，加上「每月大约剩多少能存」和小习惯。
public struct GoalBoard: Equatable, Sendable {
    public var main: PiggyGoal?
    public var small: [PiggyGoal]
    /// 老账本里超出 1+3 的（不删，提示用户挑）。
    public var extra: [PiggyGoal]
    public var done: [PiggyGoal]
    /// 最近三个整月平均每月剩多少（收入 − 支出）；没记录是 nil。
    public var monthlyRoom: Money?
    public var habit: SmallHabit
    public var today: LocalDate

    public var active: [PiggyGoal] { (main.map { [$0] } ?? []) + small + extra }
    public var isEmpty: Bool { main == nil && done.isEmpty }
    /// 还能再加几个。
    public var slotsLeft: Int { max(0, Plans.maxActiveGoals - active.count) }
    /// 第一个该问「还重要吗」的。
    public var needsCheck: PiggyGoal? { active.first(where: \.needsCheck) }
    /// 这个月所有目标一共投币的日子。
    public var monthDepositDays: Set<Int> { active.reduce(into: Set<Int>()) { $0.formUnion($1.depositDays) }.union(done.reduce(into: Set<Int>()) { $0.formUnion($1.depositDays) }) }
    public var monthHeldBack: (count: Int, saved: Money) {
        let all = active + done
        return (all.reduce(0) { $0 + $1.heldBackCount }, all.reduce(Money.zero) { $0 + $1.heldBackSaved })
    }
}

/// 建目标前算一算（引导里第 4 步、MCP 的 plan_goal）：每天存多少、换成人话、超不超出每月剩的钱。
public struct GoalAdvice: Equatable, Sendable, Codable {
    public var perDay: Money
    public var perMonth: Money
    /// 「每 2 天少一次「Café Nube」」
    public var phrase: String
    public var monthlyRoom: Money?
    /// 每月要存的比平均每月剩的还多。
    public var tooTight: Bool
    /// 「晚一点更轻松」：只用每月剩的一半，哪天能存够。
    public var easierDeadline: LocalDate?
}

extension Plans {
    // MARK: 一整页

    public static func goalBoard(_ ledger: Ledger, today: LocalDate = .today) -> GoalBoard {
        let forecasts = sortedGoals(goalForecasts(ledger, today: today))
        let byID = Dictionary(ledger.goals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let open = forecasts.filter { !$0.isDone }
        let mainID = open.first(where: \.pinned)?.id ?? open.first?.id
        let created = goalStartDates(ledger)
        let piggies = forecasts.compactMap { f -> PiggyGoal? in
            guard let g = byID[f.id] else { return nil }
            return piggy(g, f, ledger: ledger, isMain: f.id == mainID, started: created[f.id], today: today)
        }
        let active = piggies.filter { !$0.forecast.isDone }
        let main = active.first(where: \.isMain)
        let rest = active.filter { !$0.isMain }
        return GoalBoard(main: main, small: Array(rest.prefix(maxSmallGoals)), extra: Array(rest.dropFirst(maxSmallGoals)),
                         done: piggies.filter(\.forecast.isDone), monthlyRoom: monthlyRoom(ledger, today: today),
                         habit: smallHabit(ledger, today: today), today: today)
    }

    /// 建目标那天：看建目标的改动记录；找不到（很老的账本）就是第一笔存入那天。
    static func goalStartDates(_ ledger: Ledger) -> [UUID: LocalDate] {
        var out: [UUID: LocalDate] = [:]
        for c in ledger.changes where c.kind == .goal && !c.undone {
            guard let id = c.goalID, out[id] == nil else { continue }
            out[id] = LocalDate(utc: c.createdAt)
        }
        for g in ledger.goals { if let s = g.startedOn { out[g.id] = s } }
        return out
    }

    /// 往目标里存进去的那些笔（正数）：划出的看 contributionIDs，挂了储蓄账户的看那个账户的进账。
    public static func goalDeposits(_ g: Goal, in ledger: Ledger) -> [Transaction] {
        if let acct = g.savingsAccountID {
            return ledger.transactions.filter { $0.accountID == acct && $0.amount.cents > 0 && $0.flow != .opening }
        }
        let ids = Set(g.contributionIDs)
        return ledger.transactions.filter { ids.contains($0.id) && $0.amount.cents > 0 }
    }

    /// 每天存多少才行：定了日子（还没过）按时到要的；没定就照最近的速度。都没有是 nil。
    static func dailyRate(_ f: GoalForecast, today: LocalDate) -> Money? {
        if f.monthlyPace.cents > 0 { return Money(cents: max(1, (f.monthlyPace.cents + 15) / 30)) }
        if let due = f.deadline, due > today, f.left.cents > 0 {
            let days = Int64(max(1, today.days(until: due)))
            return Money(cents: max(1, (f.left.cents + days - 1) / days))
        }
        return nil
    }

    static func piggy(_ g: Goal, _ f: GoalForecast, ledger: Ledger, isMain: Bool, started: LocalDate?, today: LocalDate) -> PiggyGoal {
        let deposits = goalDeposits(g, in: ledger).filter { $0.date <= today }
        let last = ([started].compactMap { $0 } + deposits.map(\.date)).max()
        let idle = last.map { max(0, $0.days(until: today)) } ?? 0
        let quiet = g.quietUntil.map { $0 > today } ?? false
        let month = deposits.filter { $0.date.yearMonth == today.yearMonth }
        let held = month.filter { $0.tags?.contains(heldBackTag) == true }
        let heldSum = held.reduce(Money.zero) { $0 + $1.amount }
        let rate = dailyRate(f, today: today)
        // 每天要存多少：定了日子的看按时到要多少（比照现在的速度更有用）；没定看现在的速度。
        var perDay = rate
        if let due = f.deadline, due > today, f.left.cents > 0 {
            let days = Int64(max(1, today.days(until: due)))
            perDay = Money(cents: max(1, (f.left.cents + days - 1) / days))
        }
        var arrival: LocalDate?
        if f.isDone { arrival = today }
        else if f.monthlyPace.cents > 0, let r = rate { arrival = today.adding(days: Int((f.left.cents + r.cents - 1) / r.cents)) }
        else if let due = f.deadline, due >= today { arrival = due }
        return PiggyGoal(forecast: f, icon: g.icon, stash: g.stash, stashNote: g.stashNote, isMain: isMain,
                         perDay: f.isDone ? nil : perDay, arrival: arrival, lastDeposit: last, idleDays: idle,
                         needsCheck: !f.isDone && !quiet && idle >= goalIdleDays,
                         heldBackCount: held.count, heldBackSaved: heldSum,
                         heldBackDays: rate.map { r in Int(heldSum.cents / max(1, r.cents)) } ?? 0,
                         depositDays: Set(month.map { $0.date.day }))
    }

    // MARK: 提前几天

    /// 往这个目标存 amount，到手日子能提前几天（取出就是往后推几天）。算法：amount ÷ 每天要存的钱，四舍五入，至少 1 天。
    /// app 小猪旁边的「提前 N 天」、MCP 存钱后回的那句话都用它。算不出（没日子、最近也没存）是 nil。
    public static func daysEarlier(_ ledger: Ledger, goalID: UUID, amount: Money, today: LocalDate = .today) -> Int? {
        guard amount.cents > 0, let f = goalForecasts(ledger, today: today).first(where: { $0.id == goalID }),
              !f.isDone, let r = dailyRate(f, today: today) else { return nil }
        return max(1, Int((Double(amount.cents) / Double(r.cents)).rounded()))
    }

    // MARK: 每月剩多少、小习惯

    /// 最近三个整月平均每月剩多少（全部账本，不算私房钱）。一笔都没有是 nil。
    public static func monthlyRoom(_ ledger: Ledger, today: LocalDate = .today) -> Money? {
        let hidden = Set(ledger.accounts.filter(\.isPrivate).map(\.id))
        let months = (1...3).map { today.yearMonth.adding(months: -$0) }
        let sums = months.map { Summaries.monthly(ledger.transactions, month: $0, bookID: nil, hiddenAccounts: hidden) }
        let used = sums.filter { $0.income.cents != 0 || $0.expense.cents != 0 }
        guard !used.isEmpty else { return nil }
        return Money(cents: used.reduce(Int64(0)) { $0 + $1.net.cents } / Int64(used.count))
    }

    /// 最近 60 天里买得最多的小东西（一次 0,50–15 €，至少 3 次）。没找到用「一杯咖啡 3 €」。
    public static func smallHabit(_ ledger: Ledger, today: LocalDate = .today) -> SmallHabit {
        let from = today.adding(days: -60)
        let small = ledger.transactions.filter {
            $0.countsAsIncomeOrExpense && !$0.isTransfer && $0.date > from && $0.date <= today
                && $0.amount.cents <= -50 && $0.amount.cents >= -1500
        }
        let groups = Dictionary(grouping: small) { Merchant.display($0.description) }
        guard let best = groups.filter({ $0.value.count >= 3 })
            .max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }) else { return .fallback }
        let amounts = best.value.map { -$0.amount.cents }.sorted()
        let typical = Money(cents: amounts[amounts.count / 2])
        // 这周一、上周一
        let monday = today.adding(days: -today.weekdayIndex)
        let lastMonday = monday.adding(days: -7)
        let lastWeek = best.value.filter { $0.date >= lastMonday && $0.date < monday }.count
        let thisWeek = best.value.filter { $0.date >= monday }.count
        return SmallHabit(name: best.key, typical: typical, count60: best.value.count, lastWeek: lastWeek, thisWeek: thisWeek, isGuess: false)
    }

    // MARK: 建目标前算一算

    /// 想存 target，deadline 前到手（不定日子按一年算）：每天、每月存多少，换成人话，超不超出每月剩的。
    public static func goalAdvice(_ ledger: Ledger, target: Money, saved: Money = .zero, deadline: LocalDate?,
                                  today: LocalDate = .today) -> GoalAdvice {
        let left = max(0, target.cents - saved.cents)
        let due = deadline.flatMap { $0 > today ? $0 : nil } ?? today.adding(months: 12)
        let days = Int64(max(1, today.days(until: due)))
        let perDay = Money(cents: max(1, (left + days - 1) / days))
        let months = Int64(max(1, (due.year - today.year) * 12 + due.month - today.month))
        let perMonth = Money(cents: (left + months - 1) / months)
        let room = monthlyRoom(ledger, today: today)
        // 已经在存的目标每月要的钱先扣掉。
        let busy = goalForecasts(ledger, today: today).filter { !$0.isDone }
            .reduce(Int64(0)) { $0 + max($1.monthlyPace.cents, $1.neededPerMonth?.cents ?? 0) }
        let free = room.map { $0.cents - busy }
        let tight = free.map { perMonth.cents > $0 } ?? false
        var easier: LocalDate?
        if tight, let free, free > 1 {
            let half = max(1, free / 2)
            easier = today.adding(months: Int((left + half - 1) / half))
        }
        return GoalAdvice(perDay: perDay, perMonth: perMonth, phrase: smallHabit(ledger, today: today).phrase(perDay: perDay),
                          monthlyRoom: room, tooTight: tight, easierDeadline: easier)
    }
}

// MARK: - 写入

extension Ledger {
    /// 现在在存的（没存够的）目标。
    public func activeGoalIDs() -> [UUID] {
        Plans.goals(self).filter { $0.saved < $0.target }.map(\.id)
    }

    /// 设成大目标（同时只有一个）。就是钉住。
    @discardableResult
    public mutating func setMainGoal(_ id: UUID, author: String) throws -> ChangeRecord {
        guard let g = goals.first(where: { $0.id == id }) else { throw EditError.unknownGoal }
        guard !g.pinned else { throw ManageError.nothingToChange }
        let old = goals
        for i in goals.indices { goals[i].pinned = goals[i].id == id }
        let change = snapshotChange(.goal, "把「\(g.name)」设成大目标", before: PlanSnapshot(goals: old), author: author)
        changes.append(change)
        return change
    }

    /// 久没存的目标：还重要，继续（30 天内不再问）/ 先放一放（90 天内不再问）。删掉用 removeGoal。
    @discardableResult
    public mutating func keepGoal(_ id: UUID, pause: Bool, today: LocalDate = .today, author: String) throws -> ChangeRecord {
        guard let i = goals.firstIndex(where: { $0.id == id }) else { throw EditError.unknownGoal }
        let old = goals[i]
        goals[i].quietUntil = today.adding(days: pause ? 90 : Plans.goalIdleDays)
        let change = snapshotChange(.goal, pause ? "「\(old.name)」先放一放（90 天内不再问）" : "「\(old.name)」还重要，继续存",
                                    before: PlanSnapshot(goals: [old]), author: author)
        changes.append(change)
        return change
    }

    /// 记下钱真的存在哪。
    @discardableResult
    public mutating func setGoalStash(_ id: UUID, stash: GoalStash?, note: String?, author: String) throws -> ChangeRecord {
        guard let i = goals.firstIndex(where: { $0.id == id }) else { throw EditError.unknownGoal }
        var g = goals[i]
        g.stash = stash
        g.stashNote = note.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return try updateGoal(g, author: author)
    }
}
