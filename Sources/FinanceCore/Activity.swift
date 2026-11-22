import Foundation

/// 别人（AI 或另一台设备）刚刚对账本做的事：app 发现账本被改过时，拿新旧两份比一比得出来，
/// 用来弹「Claude 刚记了 12 笔」，点一下看那几笔，或者一键全部撤销。
public struct ExternalActivity: Hashable, Sendable {
    /// 新出现的改动（按时间先后），不含自己做的。
    public var changes: [ChangeRecord]
    /// 这些改动碰到的、现在还在账本里的流水。
    public var transactionIDs: [UUID]

    public var authors: [String] {
        var seen: [String] = []
        for c in changes where !seen.contains(c.author) { seen.append(c.author) }
        return seen
    }

    /// 能撤销的那些改动（从新到旧撤）。
    public var undoableIDs: [UUID] { changes.filter(\.canUndo).map(\.id).reversed() }

    /// 一句话：「Claude 刚记了 12 笔」「Claude 刚改了账本：建目标「旅行」」。
    public var headline: String {
        let who = authors.count == 1 ? authors[0] : authors.joined(separator: "、")
        let added = changes.filter { [.add, .importBatch, .transfer, .debt, .repay, .goalDeposit, .installmentPayment, .opening].contains($0.kind) }
        let addedCount = Set(added.flatMap(\.transactionIDs)).intersection(transactionIDs).count
        if addedCount > 0, addedCount == transactionIDs.count {
            return "\(who) 刚记了 \(addedCount) 笔"
        }
        if !transactionIDs.isEmpty {
            return "\(who) 刚动了 \(transactionIDs.count) 笔流水"
        }
        if changes.count == 1 { return "\(who) 刚改了账本：\(changes[0].summary)" }
        return "\(who) 刚改了账本 \(changes.count) 处"
    }

    /// 比较改之前和改之后：找出不是 `me` 做的新改动。没有就返回 nil。
    public static func between(_ old: Ledger, _ new: Ledger, me: String) -> ExternalActivity? {
        let known = Set(old.changes.map(\.id))
        let fresh = new.changes.filter { !known.contains($0.id) && $0.author != me && !$0.undone }
        guard !fresh.isEmpty else { return nil }
        let alive = Set(new.transactions.map(\.id))
        var ids: [UUID] = []
        for c in fresh { for id in c.transactionIDs where alive.contains(id) && !ids.contains(id) { ids.append(id) } }
        return ExternalActivity(changes: fresh, transactionIDs: ids)
    }

    /// 按账本现在的样子重算：已经被撤销的改动、连同撤销它的那条，一起拿掉；不在账本里的流水也拿掉。
    /// 比如 AI 记了一笔又自己撤了，提示就该消失，而不是还说「刚记了 1 笔」。全拿掉了返回 nil。
    public func current(in ledger: Ledger) -> ExternalActivity? {
        let latest = Dictionary(ledger.changes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = changes.compactMap { latest[$0.id] ?? $0 }
        let undone = now.filter(\.undone)
        let kept = now.filter { c in
            if c.undone { return false }
            // 撤销时记下的那条「撤销：……」（kind == .delete），撤的正是这一批里的：一起拿掉。
            if c.kind == .delete, undone.contains(where: { c.summary == "撤销：\($0.summary)" }) { return false }
            return true
        }
        guard !kept.isEmpty else { return nil }
        let alive = Set(ledger.transactions.map(\.id))
        return ExternalActivity(changes: kept, transactionIDs: transactionIDs.filter { alive.contains($0) })
    }

    /// 合并两次（上一条提示还没看完，又来了新的）。
    public func merged(with other: ExternalActivity) -> ExternalActivity {
        var ids = transactionIDs
        for id in other.transactionIDs where !ids.contains(id) { ids.append(id) }
        return ExternalActivity(changes: changes + other.changes.filter { c in !changes.contains { $0.id == c.id } }, transactionIDs: ids)
    }
}
