import Foundation
import CryptoKit

/// 只留改动后各字段的散列，避免在历史里再复制一份记忆或备注。
private struct PlanUndo {
    typealias Hashes = [String: [String: Data]]
    let expected: Hashes?
    var observed: Hashes = [:]
    var touched = Set<String>()
    private var conflict: BusinessError { BusinessError(message: "这次改过的字段后来又被修改，无法撤销") }

    static func hashes(_ fields: [String: NSObject]) throws -> [String: Data] {
        try fields.mapValues { value in
            let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            return Data(SHA256.hash(data: bytes))
        }
    }

    mutating func row<T: Codable>(_ original: T?, _ current: T?, key: String) throws -> T? {
        touched.insert(key)
        let fields = try current.map { try FieldMerge.fields(FieldMerge.encode($0)) }
        let now = try fields.map(Self.hashes)
        observed[key] = now
        guard let expected else { return original }
        let after = expected[key]
        guard let original, let after else {
            guard after == now else { throw conflict }
            return original
        }
        guard var fields, let now else { throw conflict }
        let old = try FieldMerge.fields(FieldMerge.encode(original))
        let prior = try Self.hashes(old)
        for k in Set(prior.keys).union(after.keys) where prior[k] != after[k] {
            guard now[k] == after[k] else { throw conflict }
            fields[k] = old[k]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    mutating func rows<T: Identifiable & Codable>(_ original: [T]?, added: [T.ID]? = nil,
                                                   current: [T], table: String) throws -> [T]? {
        guard original != nil || added != nil else { return nil }
        for id in added ?? [] {
            _ = try row(nil, current.first { $0.id == id }, key: "\(table)/\(id)")
        }
        return try original?.map { old in
            try row(old, current.first { $0.id == old.id }, key: "\(table)/\(old.id)") ?? old
        }
    }
}

extension PlanSnapshot {
    /// 同一字段被改过又改回时，单凭当前值无法发现；撤销时也核对后续活动记录。
    func affectedFields(after: [String: [String: Data]]) throws -> [String: Set<String>] {
        var prior = Ledger()
        prior.accounts = accounts ?? []; prior.books = books ?? []; prior.debts = debts ?? []
        prior.installments = installments ?? []; prior.goals = goals ?? []; prior.insights = insights ?? []
        prior.subscriptions = subscriptions ?? []; prior.recurring = recurring ?? []; prior.memories = memories ?? []
        prior.captures = captures ?? []; prior.paperwork = paperwork ?? []
        if let profile { prior.profile = profile }
        if let currency { prior.currency = currency }
        let before = try checked(in: prior, hashes: nil).hashes
        var fields: [String: Set<String>] = [:]
        for row in Set(before.keys).union(after.keys) {
            guard let old = before[row], let new = after[row] else { fields[row] = ["*"]; continue }
            let changed = Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }
            if !changed.isEmpty { fields[row] = changed }
        }
        return fields
    }

    func checked(in ledger: Ledger, hashes: [String: [String: Data]]?) throws -> (snapshot: PlanSnapshot, hashes: [String: [String: Data]], touched: Set<String>) {
        var check = PlanUndo(expected: hashes)
        var result = self
        result.accounts = try check.rows(accounts, added: addedAccountIDs, current: ledger.accounts, table: "accounts")
        result.books = try check.rows(books, added: addedBookIDs, current: ledger.books, table: "books")
        result.debts = try check.rows(debts, current: ledger.debts, table: "debts")
        result.installments = try check.rows(installments, current: ledger.installments, table: "installments")
        result.goals = try check.rows(goals, current: ledger.goals, table: "goals")
        result.insights = try check.rows(insights, added: addedInsightIDs, current: ledger.insights, table: "insights")
        result.subscriptions = try check.rows(subscriptions, added: addedSubscriptionIDs, current: ledger.subscriptions, table: "subscriptions")
        result.recurring = try check.rows(recurring, added: addedRecurringIDs, current: ledger.recurring, table: "recurring")
        result.memories = try check.rows(memories, added: addedMemoryIDs, current: ledger.memories, table: "memories")
        result.captures = try check.rows(captures, added: addedCaptureIDs, current: ledger.captures, table: "captures")
        result.paperwork = try check.rows(paperwork, added: addedPaperworkIDs, current: ledger.paperwork, table: "paperwork")
        if profile != nil { result.profile = try check.row(profile, ledger.profile, key: "profile") }
        if currency != nil { result.currency = try check.row(currency, ledger.currency, key: "currency") }
        if changedBusiness == true { check.touched.insert("business") }
        return (result, check.observed, check.touched)
    }
}

extension ChangeRecord {
    mutating func saveBefore(_ snapshot: PlanSnapshot, in ledger: Ledger) {
        before = snapshot
        planFieldHashes = try? snapshot.checked(in: ledger, hashes: nil).hashes
    }
}

extension ChangeRecord {
    /// 指定遗忘一行时同步更新仍匹配的撤销凭据。其余字段以及更早的冲突保持原状。
    mutating func redactMemoryEvidence(old: Memory, current: Memory?) {
        let key = "memories/\(old.id)"
        guard var evidence = planFieldHashes?[key] else { return }
        guard let current else { planFieldHashes?[key] = nil; return }
        guard let before = try? PlanUndo.hashes(FieldMerge.fields(FieldMerge.encode(old))),
              let after = try? PlanUndo.hashes(FieldMerge.fields(FieldMerge.encode(current))) else { return }
        for field in ["notes", "updatedAt"] where evidence[field] == before[field] { evidence[field] = after[field] }
        planFieldHashes?[key] = evidence
    }
}
