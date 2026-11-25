import Foundation

public struct SyncRowKey: Hashable, Codable, Comparable, Sendable {
    public let table: String
    public let id: String
    init(_ table: String, _ id: String) { self.table = table; self.id = id }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.table, lhs.id) < (rhs.table, rhs.id) }
}

/// 同一组里所有手机提议；nil 表示手机删除了这一行。
public struct LinkedSyncMember: Codable, Sendable {
    public let row: SyncRowKey
    public let proposed: Data?
}

private struct FinancialLinks {
    var edges: [SyncRowKey: Set<SyncRowKey>] = [:]
    var incoming: [SyncRowKey: LinkedSyncMember] = [:]
    var problems = Set<SyncRowKey>()

    mutating func plans<T: Codable & Identifiable>(_ table: String, local: [T], requested: [T]?, merged: [T],
                                                   note: SyncNote, missing: Set<UUID>, removed: Set<UUID>,
                                                   references: (T) -> [UUID]) where T.ID == UUID {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let originals = (note.originalRows?[table] ?? [:]).values.compactMap { try? decoder.decode(T.self, from: $0) }
        for plan in local + originals + (requested ?? []) {
            let key = SyncRowKey(table, plan.id.uuidString)
            for id in references(plan) {
                let tx = SyncRowKey("transactions", id.uuidString)
                edges[key, default: []].insert(tx)
                edges[tx, default: []].insert(key)
            }
        }
        let prior = Dictionary(uniqueKeysWithValues: local.map { ($0.id, Set(references($0))) })
        for plan in merged {
            let refs = Set(references(plan))
            if !refs.isDisjoint(with: removed) || !refs.subtracting(prior[plan.id] ?? []).isDisjoint(with: missing) {
                problems.insert(.init(table, plan.id.uuidString))
            }
        }
        proposals(table, rows: requested, note: note)
    }

    mutating func proposals<T: Codable & Identifiable>(_ table: String, rows: [T]?, note: SyncNote) where T.ID == UUID {
        for row in rows ?? [] {
            let key = SyncRowKey(table, row.id.uuidString)
            incoming[key] = LinkedSyncMember(row: key, proposed: try? FieldMerge.encode(row))
        }
        for id in note.deletes?[table] ?? [] {
            let key = SyncRowKey(table, id)
            incoming[key] = LinkedSyncMember(row: key, proposed: nil)
        }
    }
}

private extension ChangeRecord {
    var planRows: [SyncRowKey] {
        var keys: [SyncRowKey] = []
        if let debtID { keys.append(.init("debts", debtID.uuidString)) }
        if let installmentID { keys.append(.init("installments", installmentID.uuidString)) }
        if let goalID { keys.append(.init("goals", goalID.uuidString)) }
        keys += (before?.debts ?? []).map { .init("debts", $0.id.uuidString) }
        keys += (before?.installments ?? []).map { .init("installments", $0.id.uuidString) }
        keys += (before?.goals ?? []).map { .init("goals", $0.id.uuidString) }
        return keys
    }
}

extension Ledger {
    /// 先在副本试合并，找出失败的流水和引用它们的计划。无关的行仍可正常接收。
    func linkedConflicts(in note: SyncNote, ignoring skipped: Set<SyncRowKey> = []) -> (blocked: Set<SyncRowKey>, conflicts: [SyncConflict]) {
        let planTables = ["debts", "installments", "goals"]
        guard note.debts != nil || note.installments != nil || note.goals != nil ||
                (planTables + ["transactions"]).contains(where: { !(note.deletes?[$0] ?? []).isEmpty }) else { return ([], []) }

        var tx = transactions, d = debts, ins = installments, g = goals
        var trial = NoteMerger(note: note, skipped: skipped)
        trial.rows(&tx, note.transactions, "transactions", key: \.id, name: \.uuidString)
        trial.rows(&d, note.debts, "debts", key: \.id, name: \.uuidString)
        trial.rows(&ins, note.installments, "installments", key: \.id, name: \.uuidString)
        trial.rows(&g, note.goals, "goals", key: \.id, name: \.uuidString)
        let live = Set(tx.map(\.id))
        let removed = Set(transactions.map(\.id)).subtracting(live)
        let referenced = Set(d.flatMap(\.repaymentIDs) + ins.flatMap { $0.paidIDs + [$0.purchaseID].compactMap { $0 } } + g.flatMap(\.contributionIDs))
        let missing = referenced.subtracting(live)
        var graph = FinancialLinks()
        graph.proposals("transactions", rows: note.transactions, note: note)
        graph.plans("debts", local: debts, requested: note.debts, merged: d, note: note, missing: missing, removed: removed, references: \.repaymentIDs)
        graph.plans("installments", local: installments, requested: note.installments, merged: ins, note: note, missing: missing, removed: removed) {
            $0.paidIDs + [$0.purchaseID].compactMap { $0 }
        }
        graph.plans("goals", local: goals, requested: note.goals, merged: g, note: note, missing: missing, removed: removed, references: \.contributionIDs)
        // 借款本金等通过改动记录关联，不一定出现在计划的还款编号中。
        for change in note.changes ?? [] {
            for plan in change.planRows where graph.incoming[plan] != nil {
                for id in change.transactionIDs {
                    let tx = SyncRowKey("transactions", id.uuidString)
                    if graph.incoming[tx] != nil {
                        graph.edges[plan, default: []].insert(tx)
                        graph.edges[tx, default: []].insert(plan)
                    }
                }
            }
        }
        let seeds = skipped.union(graph.problems).union(trial.conflicts.map { SyncRowKey($0.table, $0.rowID) })
        var visited = Set<SyncRowKey>(), blocked = Set<SyncRowKey>(), conflicts: [SyncConflict] = []
        for seed in seeds.sorted() where !visited.contains(seed) {
            var component = Set<SyncRowKey>(), queue = [seed]
            while let next = queue.popLast() {
                guard component.insert(next).inserted else { continue }
                queue.append(contentsOf: graph.edges[next] ?? [])
            }
            visited.formUnion(component)
            let proposals = component.sorted().compactMap { graph.incoming[$0] }
            let coupled = proposals.contains { $0.row.table == "transactions" } && proposals.contains { $0.row.table != "transactions" }
            guard coupled || !component.isDisjoint(with: graph.problems) else { continue }
            blocked.formUnion(proposals.map(\.row))
            conflicts.append(.init(table: "relatedRecords", rowID: seed.id, fields: ["流水与计划引用"], phoneValue: try? FieldMerge.encode(proposals)))
        }
        // 被拒的流水/计划操作不能在 Mac 留下一条仿佛已经生效、可以撤销的历史。
        for change in note.changes ?? [] {
            let affected = change.planRows + change.transactionIDs.map { SyncRowKey("transactions", $0.uuidString) }
            if !blocked.isDisjoint(with: affected) { blocked.insert(.init("changes", change.id.uuidString)) }
        }
        return (blocked, conflicts)
    }
}
