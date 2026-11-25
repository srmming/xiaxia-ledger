import Foundation

/// 键是流水 UUID，值是首次收到删除的 Unix 时间。旧格式只有 UUID，没有时间。
struct PhoneDeletionReceipts: Codable, Equatable, Sendable {
    static let lifetime: TimeInterval = 30 * 86400
    var received: [String: TimeInterval] = [:]
    var count: Int { received.count }

    init() {}
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let dated = try? value.decode([String: TimeInterval].self) {
            received = dated
        } else {
            for id in try value.decode([UUID].self) { received[id.uuidString] = -1 }
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(received)
    }

    mutating func prune(at now: Date) {
        let time = now.timeIntervalSince1970
        // 没有时间的旧凭据，从本次首次读取开始计算保留期限。
        received = received.mapValues { $0 == -1 ? time : $0 }.filter { time - $0.value < Self.lifetime }
    }
}

extension Ledger {
    mutating func prunePhoneDeletes(at now: Date) {
        guard var receipts = pendingPhoneDeletes else { return }
        receipts.prune(at: now)
        let updated = receipts.received.isEmpty ? nil : receipts
        if updated != pendingPhoneDeletes { pendingPhoneDeletes = updated }
    }

    mutating func clearPhoneDeletes(_ ids: [UUID]) {
        guard var receipts = pendingPhoneDeletes else { return }
        for id in ids { receipts.received[id.uuidString] = nil }
        pendingPhoneDeletes = receipts.received.isEmpty ? nil : receipts
    }
}
