import Foundation
import CryptoKit

/// 冲突时保存手机提议的完整行（JSON）；nil 表示手机想删除它。
public struct SyncConflict: Codable, Hashable, Sendable {
    public let table: String
    public let rowID: String
    public let fields: [String]
    public let phoneValue: Data?
}

enum FieldMerge {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func fields(_ data: Data) throws -> [String: NSObject] {
        guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: NSObject] else {
            throw BusinessError(message: "记录格式无法比较")
        }
        return fields
    }

    static func delta(_ before: Data, _ after: Data) throws -> Set<String> {
        let a = try fields(before), b = try fields(after)
        return Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }
    }

    /// 仅应用提议实际改过的顶层字段。数组、金额、嵌套对象均作为一个完整字段。
    static func merge<T: Codable>(base: Data, proposed: T, current: T) throws -> (T, [String]) {
        let from = try fields(base)
        let wanted = try fields(encode(proposed))
        var merged = try fields(encode(current))
        var conflicts: [String] = []
        for key in Set(from.keys).union(wanted.keys) where from[key] != wanted[key] {
            if merged[key] == from[key] || merged[key] == wanted[key] { merged[key] = wanted[key] }
            else { conflicts.append(key) }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: merged)), conflicts.sorted())
    }
}

extension Ledger {
    /// 预先算好整批流水的逆操作；任何一笔有冲突，就在改账本前报错。
    func transactionReversals(for change: ChangeRecord, later: ArraySlice<ChangeRecord>) throws -> [UUID: Transaction] {
        let conflict = BusinessError(message: "这次改过的字段后来又被修改，无法撤销；请先核对后续改动")
        let before = Dictionary(uniqueKeysWithValues: (change.previous ?? []).map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: (change.resultingTransactions ?? []).map { ($0.id, $0) })
        let ids = Set(change.transactionIDs)
        guard !ids.isEmpty else { return [:] }
        let currentRows = Dictionary(uniqueKeysWithValues: transactions.filter { ids.contains($0.id) }.map { ($0.id, $0) })
        var laterByID: [UUID: [ChangeRecord]] = [:]
        for item in later where !item.undone {
            for id in item.transactionIDs where ids.contains(id) { laterByID[id, default: []].append(item) }
        }
        var result: [UUID: Transaction] = [:]
        for id in ids {
            let current = currentRows[id]
            let subsequent = laterByID[id] ?? []
            if change.kind == .remove {
                guard current == nil && subsequent.isEmpty else { throw conflict }
                continue
            }
            guard let old = before[id] else {
                guard subsequent.isEmpty else { throw conflict }
                if let expected = after[id], current != expected { throw conflict }
                continue
            }
            // 旧版未记录修改结果时，下一次改这行之前的快照也能证明当时的值。
            guard let current, let written = after[id] ?? subsequent.first?.previous?.first(where: { $0.id == id }) else {
                throw conflict
            }
            let base = try FieldMerge.encode(written)
            let fields = try FieldMerge.delta(base, FieldMerge.encode(old))
            if try !fields.isDisjoint(with: FieldMerge.delta(base, FieldMerge.encode(current))) { throw conflict }
            for (index, next) in subsequent.enumerated() {
                let following = subsequent.dropFirst(index + 1).first?.previous?.first { $0.id == id }
                guard next.kind != .remove, let a = next.previous?.first(where: { $0.id == id }),
                      next.resultingTransactions?.contains(where: { $0.id == id }) == true || following != nil || index == subsequent.count - 1 else { throw conflict }
                let b = next.resultingTransactions?.first(where: { $0.id == id }) ?? following ?? current
                if try !fields.isDisjoint(with: FieldMerge.delta(FieldMerge.encode(a), FieldMerge.encode(b))) { throw conflict }
            }
            result[id] = try FieldMerge.merge(base: base, proposed: old, current: current).0
        }
        return result
    }
}
