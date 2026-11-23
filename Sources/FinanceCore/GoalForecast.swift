import Foundation

// 目标页只回答一个问题（ming 2026-11-23）：「我离想要的还差多远、来得及吗？」
// 每个目标：还差多少、照最近的存法每月存多少、哪个月能到；定了日子的，赶不赶得上、晚几个月、每月再多存多少就能按时到。

public struct GoalForecast: Identifiable, Equatable, Sendable {
    public enum Pace: Equatable, Sendable {
        /// 已经存够了。
        case done
        /// 赶得上（或者没定日子、照现在的存法能存到）。
        case onTrack
        /// 赶不上：照现在的存法比定的日子晚。
        case behind
        /// 最近没在存，算不出哪天能到。
        case stalled
    }

    public var id: UUID
    public var name: String
    public var target: Money
    public var saved: Money
    public var left: Money
    public var percent: Int
    public var deadline: LocalDate?
    public var locked: Bool
    public var pinned: Bool
    public var rank: Int?
    /// 最近（最多三个月）平均每月存多少。
    public var monthlyPace: Money
    /// 照现在的存法哪个月能到；存够了是这个月，最近没存是 nil。
    public var eta: YearMonth?
    /// 定了日子的：要按时到每月得存多少。
    public var neededPerMonth: Money?
    /// 要按时到，每月还得再多存多少（够了是 nil）。
    public var extraPerMonth: Money?
    /// 比定的日子晚几个月（赶得上是 nil）。
    public var monthsLate: Int?
    /// 离定的日子还有几个月（这个月算 1）。
    public var monthsToDeadline: Int?
    public var pace: Pace

    public var isDone: Bool { pace == .done }
}

extension Plans {
    /// 每个目标的预测。today 只影响「最近三个月」和离截止还有几个月。
    public static func goalForecasts(_ ledger: Ledger, today: LocalDate = .today) -> [GoalForecast] {
        let status = Dictionary(goals(ledger).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let windowStart = today.adding(days: -91)
        return ledger.goals.compactMap { g in
            guard let s = status[g.id] else { return nil }
            // 最近存了多少：目标的存取记录，或者专门存钱的那个账户的进出（不算期初余额）。
            let recent: [Transaction]
            if let acct = g.savingsAccountID {
                recent = ledger.transactions.filter { $0.accountID == acct && $0.flow != .opening && $0.date > windowStart && $0.date <= today }
            } else {
                let ids = Set(g.contributionIDs)
                recent = ledger.transactions.filter { ids.contains($0.id) && $0.date > windowStart && $0.date <= today }
            }
            let sum = recent.reduce(Int64(0)) { $0 + $1.amount.cents }
            // 刚开始存没多久的，按开始存到今天的天数平均（至少按一个月算），免得被三个月摊薄。
            let first = recent.map(\.date).min() ?? today
            let days = max(30, min(91, first.days(until: today) + 1))
            let pace = Money(cents: max(0, sum * 30 / Int64(days)))

            let left = Money(cents: max(0, s.target.cents - s.saved.cents))
            var f = GoalForecast(id: g.id, name: g.name, target: s.target, saved: s.saved, left: left, percent: s.percent,
                                 deadline: g.deadline, locked: g.locked, pinned: g.pinned, rank: g.rank,
                                 monthlyPace: pace, eta: nil, neededPerMonth: nil, extraPerMonth: nil,
                                 monthsLate: nil, monthsToDeadline: nil, pace: .onTrack)
            if left.cents == 0 {
                f.pace = .done
                f.eta = today.yearMonth
                return f
            }
            if pace.cents > 0 {
                let n = Int((left.cents + pace.cents - 1) / pace.cents)
                // 下个月开始每月存一次，存 n 次存够（和下面「离截止还能存几次」同一个算法）。
                f.eta = today.yearMonth.adding(months: n)
            }
            if let due = g.deadline {
                // 这个月到截止那个月，一共还能存几次（截止就在这个月 = 1 次）。
                let months = max(1, (due.year - today.year) * 12 + due.month - today.month)
                f.monthsToDeadline = months
                let need = Money(cents: (left.cents + Int64(months) - 1) / Int64(months))
                f.neededPerMonth = need
                if need > pace { f.extraPerMonth = need - pace }
                if let eta = f.eta {
                    let late = (eta.year - due.year) * 12 + eta.month - due.month
                    if late > 0 { f.monthsLate = late; f.pace = .behind }
                } else {
                    f.pace = .stalled
                }
                if due < today { f.pace = .behind; f.monthsLate = f.monthsLate ?? 0 }
            } else if pace.cents == 0 {
                f.pace = .stalled
            }
            return f
        }
    }

    /// 目标页的顺序：钉住的最前；用户拖过顺序的按拖的排；没拖过的，最急的在前
    /// （赶不上的 → 定了日子的按日子 → 没日子的按完成度）。存够了的放最后。
    public static func sortedGoals(_ list: [GoalForecast]) -> [GoalForecast] {
        let never = LocalDate(year: 9999, month: 12, day: 31)
        func urgency(_ g: GoalForecast) -> (Int, LocalDate, Int) {
            switch g.pace {
            case .done: (4, never, 0)
            case .behind: (0, g.deadline ?? never, -g.percent)
            case .stalled where g.deadline != nil: (1, g.deadline!, -g.percent)
            default: (g.deadline == nil ? 3 : 2, g.deadline ?? never, -g.percent)
            }
        }
        return list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.isDone != b.isDone { return !a.isDone }
            switch (a.rank, b.rank) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                let ua = urgency(a), ub = urgency(b)
                if ua.0 != ub.0 { return ua.0 < ub.0 }
                if ua.1 != ub.1 { return ua.1 < ub.1 }
                if ua.2 != ub.2 { return ua.2 < ub.2 }
                return a.name < b.name
            }
        }
    }
}

extension Ledger {
    /// 钉到目标页最上面（同时只钉一个）；pinned = false 取消。
    @discardableResult
    public mutating func pinGoal(_ id: UUID, pinned: Bool = true, author: String) throws -> ChangeRecord {
        guard let g = goals.first(where: { $0.id == id }) else { throw EditError.unknownGoal }
        guard g.pinned != pinned else { throw ManageError.nothingToChange }
        let old = goals
        for i in goals.indices { goals[i].pinned = pinned && goals[i].id == id }
        let change = snapshotChange(.goal, pinned ? "把目标「\(g.name)」钉到最上面" : "取消钉住目标「\(g.name)」",
                                    before: PlanSnapshot(goals: old), author: author)
        changes.append(change)
        return change
    }

    /// 按给的顺序排目标（拖动排序以后存下来）。没写到的目标排在后面、保持原来的先后。
    @discardableResult
    public mutating func reorderGoals(_ ids: [UUID], author: String) throws -> ChangeRecord {
        let old = goals
        var order = ids.filter { id in goals.contains { $0.id == id } }
        for g in goals where !order.contains(g.id) { order.append(g.id) }
        for (n, id) in order.enumerated() {
            if let i = goals.firstIndex(where: { $0.id == id }) { goals[i].rank = n }
        }
        guard goals != old else { throw ManageError.nothingToChange }
        let first = goals.first { $0.id == order.first }?.name ?? ""
        let change = snapshotChange(.goal, "调了目标的顺序（「\(first)」排第一）", before: PlanSnapshot(goals: old), author: author)
        changes.append(change)
        return change
    }

    /// 不要自己拖的顺序了，改回按急不急排。
    @discardableResult
    public mutating func resetGoalOrder(author: String) throws -> ChangeRecord {
        guard goals.contains(where: { $0.rank != nil }) else { throw ManageError.nothingToChange }
        let old = goals
        for i in goals.indices { goals[i].rank = nil }
        let change = snapshotChange(.goal, "目标顺序改回按急不急排", before: PlanSnapshot(goals: old), author: author)
        changes.append(change)
        return change
    }
}
