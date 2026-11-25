import Foundation

/// 尚未看到入账的删除凭据按收件时间过期，已看到入账的保留至处理完成。
struct PhoneDeletionReceipts: Codable, Equatable, Sendable {
    static let lifetime: TimeInterval = 30 * 86400
    enum State: Codable, Equatable, Sendable {
        case waitingSince(TimeInterval)
        case bookingSeen
        case bookingHandled

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let time = try? value.decode(TimeInterval.self) { self = .waitingSince(time) }
            else if (try? value.decode(String.self)) == "bookingHandled" { self = .bookingHandled }
            else if try value.decode(String.self) == "bookingSeen" { self = .bookingSeen }
            else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "未知的删除凭据状态") }
        }

        func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self {
            case .waitingSince(let time): try value.encode(time)
            case .bookingHandled: try value.encode("bookingHandled")
            case .bookingSeen: try value.encode("bookingSeen")
            }
        }
    }

    var received: [String: State] = [:]
    // 流水 → 等待持久提交的纸条。iCloud 一时看不到文件也不能解除保护。
    var queued: [String: [String]] = [:]
    private enum CodingKeys: String, CodingKey { case received, queued }

    mutating func track(_ index: [String: Set<String>]) {
        for id in received.keys {
            guard let notes = index[id], !notes.isEmpty else { continue }
            queued[id] = notes.union(queued[id] ?? []).sorted()
        }
    }

    mutating func finish(_ applied: Set<String>) {
        for (id, notes) in queued {
            let remaining = notes.filter { !applied.contains($0) }
            queued[id] = remaining.isEmpty || received[id] == nil ? nil : remaining
        }
        for (id, state) in received where state == .bookingHandled && queued[id] == nil { received[id] = nil }
    }

    var earliestWaitingTime: TimeInterval? {
        received.compactMap { id, state in
            guard queued[id] == nil else { return nil }
            guard case .waitingSince(let time) = state else { return nil }
            return time
        }.min()
    }
    var count: Int { received.count }

    init() {}
    init(from decoder: Decoder) throws {
        if let fields = try? decoder.container(keyedBy: CodingKeys.self), fields.contains(.received) {
            received = try fields.decode([String: State].self, forKey: .received)
            queued = try fields.decode([String: [String]].self, forKey: .queued)
            return
        }
        let value = try decoder.singleValueContainer()
        if let dated = try? value.decode([String: State].self) {
            received = dated
        } else {
            for id in try value.decode([UUID].self) { received[id.uuidString] = .waitingSince(-1) }
        }
    }

    func encode(to encoder: Encoder) throws {
        if queued.isEmpty {
            var value = encoder.singleValueContainer()
            try value.encode(received)
        } else {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(received, forKey: .received)
            try fields.encode(queued, forKey: .queued)
        }
    }

    mutating func prune(at now: Date, observed: Set<UUID>) {
        let time = now.timeIntervalSince1970
        // 没有时间的旧凭据，从本次首次读取开始计算保留期限。
        for id in observed where received[id.uuidString] != nil && received[id.uuidString] != .bookingHandled { received[id.uuidString] = .bookingSeen }
        for (id, state) in received {
            guard case .waitingSince(let start) = state else { continue }
            if start == -1 { received[id] = .waitingSince(time) }
            else if queued[id] == nil && time - start >= Self.lifetime { received[id] = nil }
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
        for id in ids {
            receipts.received[id.uuidString] = nil
            receipts.queued[id.uuidString] = nil
        }
        pendingPhoneDeletes = receipts.received.isEmpty ? nil : receipts
    }
}
