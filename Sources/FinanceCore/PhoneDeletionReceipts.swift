import Foundation

/// 尚未看到入账的删除凭据按收件时间过期，已看到入账的保留至处理完成。
struct PhoneDeletionReceipts: Codable, Equatable, Sendable {
    static let lifetime: TimeInterval = 30 * 86400
    enum State: Codable, Equatable, Sendable {
        case waitingSince(TimeInterval)
        case bookingSeen

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let time = try? value.decode(TimeInterval.self) { self = .waitingSince(time) }
            else if try value.decode(String.self) == "bookingSeen" { self = .bookingSeen }
            else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "未知的删除凭据状态") }
        }

        func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self {
            case .waitingSince(let time): try value.encode(time)
            case .bookingSeen: try value.encode("bookingSeen")
            }
        }
    }

    var received: [String: State] = [:]
    var earliestWaitingTime: TimeInterval? {
        received.values.compactMap { state in
            guard case .waitingSince(let time) = state else { return nil }
            return time
        }.min()
    }
    var count: Int { received.count }

    init() {}
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let dated = try? value.decode([String: State].self) {
            received = dated
        } else {
            for id in try value.decode([UUID].self) { received[id.uuidString] = .waitingSince(-1) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(received)
    }

    mutating func prune(at now: Date, observed: Set<UUID>) {
        let time = now.timeIntervalSince1970
        // 没有时间的旧凭据，从本次首次读取开始计算保留期限。
        for id in observed where received[id.uuidString] != nil { received[id.uuidString] = .bookingSeen }
        for (id, state) in received {
            guard case .waitingSince(let start) = state else { continue }
            if start == -1 { received[id] = .waitingSince(time) }
            else if time - start >= Self.lifetime { received[id] = nil }
        }
    }
}

extension Ledger {
    mutating func prunePhoneDeletes(at now: Date, observed: Set<UUID> = []) {
        guard var receipts = pendingPhoneDeletes else { return }
        receipts.prune(at: now, observed: observed)
        let updated = receipts.received.isEmpty ? nil : receipts
        if updated != pendingPhoneDeletes { pendingPhoneDeletes = updated }
    }

    mutating func clearPhoneDeletes(_ ids: [UUID]) {
        guard var receipts = pendingPhoneDeletes else { return }
        for id in ids { receipts.received[id.uuidString] = nil }
        pendingPhoneDeletes = receipts.received.isEmpty ? nil : receipts
    }
}
