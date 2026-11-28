import Foundation

// 目标走完收起来：目标留在账本里，记下哪天走完的。走完的不再算「在走的目标」。

extension Ledger {
    /// 走完的目标，最近走完的在前。
    public var finishedGoals: [Goal] { goals.filter(\.isFinished).sorted { ($0.finishedOn ?? .today) > ($1.finishedOn ?? .today) } }

    /// 把一个目标标成走完。里面的钱要先挪走（用账户间转账），这里只管标记。能撤销。
    @discardableResult
    public mutating func finishGoal(_ id: UUID, today: LocalDate = .today, author: String) throws -> ChangeRecord {
        guard let i = goals.firstIndex(where: { $0.id == id }) else { throw EditError.unknownGoal }
        let old = goals[i]
        guard !old.isFinished else { throw ManageError.nothingToChange }
        goals[i].finishedOn = today
        let change = snapshotChange(.goal, "目标「\(old.name)」走完了，收起来", before: PlanSnapshot(goals: [old]), author: author)
        changes.append(change)
        return change
    }
}
