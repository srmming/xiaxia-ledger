import Foundation
import CryptoKit

// iPhone 和 Mac 通过 iCloud 云盘同一个「夏夏账本」文件夹看同一本账（2026-11-23 ming：「记得支持iclud」）。
//
// 难点是两边同时改：账本是一个 SQLite 文件，两台设备都直接写的话，iCloud 只能留一份，另一边记的就丢了。
// 做法是「手机写小纸条，电脑记总账」：
// - 账本文件只有 Mac（app 和 fin）写。
// - iPhone 每改一次（记一笔、说一句、拍小票、挂发票、改报销状态……），把「改了哪几条」写成一张小纸条，
//   放进文件夹里的「手机记的」子文件夹。一张纸条一个新文件，iCloud 同步新文件从来不会冲突。
// - iPhone 显示的是「账本 + 自己还没被收走的纸条」，所以手机上记完马上就能看到。
// - Mac 读账本时，把还没收过的纸条按时间顺序收进账本、存盘，纸条挪进「手机记的/已收」（30 天后删）。
//   收过的纸条编号记在账本里（appliedNotes），重复看到也不会收两次。
// 新纸条附带被改行的原值，按字段合并。同一字段发生冲突时保留电脑值，留下手机版本供核对。

/// 一张小纸条：手机上的一次改动。
public struct SyncNote: Codable, Sendable, Equatable {
    /// 文件名（不带 .json），按时间排序。
    public var id: String
    public var device: String
    public var createdAt: Date
    /// 一句话说明（「记一笔 −10,00 € 午饭」），Mac 上「手机记的」里显示。
    public var summary: String

    public var books: [Book]?
    public var accounts: [Account]?
    public var transactions: [Transaction]?
    public var changes: [ChangeRecord]?
    public var debts: [Debt]?
    public var installments: [Installment]?
    public var goals: [Goal]?
    public var insights: [Insight]?
    public var subscriptions: [Subscription]?
    public var recurring: [Recurring]?
    public var memories: [Memory]?
    public var captures: [Capture]?
    public var paperwork: [Paperwork]?
    public var receivables: [Receivable]?
    public var changedBusiness: Bool?
    public var business: BusinessSettings?
    public var profile: Profile?
    public var currency: CurrencySettings?
    public var lastStatementDate: [String: LocalDate]?
    /// 要删的：表名 → 编号。
    public var deletes: [String: [String]]?
    public var originalRows: [String: [String: Data]]?

    public init(id: String, device: String, createdAt: Date, summary: String) {
        self.id = id; self.device = device; self.createdAt = createdAt; self.summary = summary
    }

    /// 什么都没改。
    public var isEmpty: Bool {
        books == nil && accounts == nil && transactions == nil && changes == nil && debts == nil && installments == nil
            && goals == nil && insights == nil && subscriptions == nil && recurring == nil && memories == nil
            && receivables == nil && changedBusiness != true && captures == nil && paperwork == nil && profile == nil && currency == nil && lastStatementDate == nil
            && (deletes ?? [:]).isEmpty
    }

    /// 新纸条的编号：时间在前，方便按顺序收。
    public static func newID(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "\(f.string(from: date))-\(UUID().uuidString.prefix(8))"
    }
}

// MARK: - 比较和收纸条

private func rowDiff<T: Equatable, K: Hashable>(_ old: [T], _ new: [T], key: (T) -> K) -> (changed: [T]?, removed: [K]) {
    var before: [K: T] = [:]
    for r in old { before[key(r)] = r }
    let newKeys = Set(new.map(key))
    let changed = new.filter { before[key($0)] != $0 }
    let removed = old.map(key).filter { !newKeys.contains($0) }
    return (changed.isEmpty ? nil : changed, removed)
}

extension SyncNote {
    func originalValues(in table: String) -> [String: Data] {
        var before = originalRows?[table] ?? [:]
        // 旧纸条没有行级凭据；旧版 edit 的改动记录有时保留了原流水。
        if originalRows == nil && table == "transactions" {
            for change in changes ?? [] where !(change.kind == .remove && change.undone) {
                for old in change.previous ?? [] where before[old.id.uuidString] == nil {
                    before[old.id.uuidString] = try? FieldMerge.encode(old)
                }
            }
        }
        // 旧手机撤销只翻转删除记录上的 undone。它的 previous 是待恢复的流水。
        if originalRows == nil && table == "changes" {
            for var change in changes ?? [] where change.kind == .remove && change.undone {
                change.undone = false
                before[change.id.uuidString] = try? FieldMerge.encode(change)
            }
        }
        return before
    }

    /// 流水既可能是操作对象，也可能只出现在撤销、拆分、凭证或计划的关联中。
    func indexRelatedTransactions(in index: inout [String: Set<String>]) {
        var ids = Set((transactions ?? []).map(\.id))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func originals<T: Decodable>(_ type: T.Type, in table: String) -> [T] {
            (originalRows?[table] ?? [:]).values.compactMap { try? decoder.decode(type, from: $0) }
        }
        for table in ["transactions", "paperwork"] {
            ids.formUnion((deletes?[table] ?? []).compactMap(UUID.init(uuidString:)))
            ids.formUnion((originalRows?[table] ?? [:]).keys.compactMap(UUID.init(uuidString:)))
        }
        let history = (changes ?? []) + originals(ChangeRecord.self, in: "changes")
        let snapshots = history.compactMap(\.before)
        for c in history {
            ids.formUnion(c.transactionIDs)
            ids.formUnion((c.previous ?? []).map(\.id))
            ids.formUnion((c.resultingTransactions ?? []).map(\.id))
        }
        let allCaptures = (captures ?? []) + originals(Capture.self, in: "captures") + snapshots.flatMap { $0.captures ?? [] }
        for capture in allCaptures { ids.formUnion(capture.transactionIDs ?? []) }
        let pages = (paperwork ?? []) + originals(Paperwork.self, in: "paperwork") + snapshots.flatMap { $0.paperwork ?? [] }
        for page in pages {
            ids.insert(page.id)
            if let paid = page.paidTransactionID { ids.insert(paid) }
        }
        for snapshot in snapshots { ids.formUnion(snapshot.addedPaperworkIDs ?? []) }
        let allDebts = (debts ?? []) + originals(Debt.self, in: "debts") + snapshots.flatMap { $0.debts ?? [] }
        for debt in allDebts { ids.formUnion(debt.repaymentIDs) }
        let allGoals = (goals ?? []) + originals(Goal.self, in: "goals") + snapshots.flatMap { $0.goals ?? [] }
        for goal in allGoals { ids.formUnion(goal.contributionIDs) }
        let plans = (installments ?? []) + originals(Installment.self, in: "installments") + snapshots.flatMap { $0.installments ?? [] }
        for plan in plans {
            ids.formUnion(plan.paidIDs)
            if let purchase = plan.purchaseID { ids.insert(purchase) }
        }
        let settings = [business].compactMap { $0 } + snapshots.compactMap(\.business)
        for item in settings.flatMap({ $0.capital?.items ?? [] }) { ids.formUnion(item.txIDs ?? []) }
        for uuid in ids { index[uuid.uuidString, default: []].insert(id) }
    }

    var addedTransactionIDs: Set<UUID> {
        guard let transactions, !transactions.isEmpty else { return [] }
        let before = originalValues(in: "transactions")
        let undoIDs = Set((changes ?? []).filter { $0.kind == .remove && $0.undone }.flatMap(\.transactionIDs))
        return Set(transactions.map(\.id).filter { before[$0.uuidString] == nil && !undoIDs.contains($0) })
    }
}

struct NoteMerger {
    let note: SyncNote
    var conflicts: [SyncConflict] = []
    var skipped = Set<SyncRowKey>()

    mutating func rows<T: Codable & Equatable, K: Hashable>(_ local: inout [T], _ incoming: [T]?, _ table: String,
                                                             key: (T) -> K, name: (K) -> String) {
        let before = note.originalValues(in: table)
        for id in note.deletes?[table] ?? [] {
            guard !skipped.contains(.init(table, id)), let i = local.firstIndex(where: { name(key($0)) == id }) else { continue }
            if let base = before[id], (try? FieldMerge.encode(local[i])) == base { local.remove(at: i) }
            else { conflict(table, id, ["删除"], nil) }
        }
        for row in incoming ?? [] {
            let id = name(key(row))
            if skipped.contains(.init(table, id)) { continue }
            let offered = try? FieldMerge.encode(row)
            guard let i = local.firstIndex(where: { key($0) == key(row) }) else {
                if before[id] == nil { local.append(row) } else { conflict(table, id, ["电脑已删除"], offered) }
                continue
            }
            guard local[i] != row else { continue }
            guard let base = before[id], let result = try? FieldMerge.merge(base: base, proposed: row, current: local[i]) else {
                conflict(table, id, ["缺少原值"], offered)
                continue
            }
            local[i] = result.0
            if !result.1.isEmpty { conflict(table, id, result.1, offered) }
        }
    }

    mutating func setting<T: Codable & Equatable>(_ current: inout T, _ proposed: T?, _ name: String) {
        guard let proposed, current != proposed else { return }
        guard let base = note.originalRows?["meta"]?[name],
              let result = try? FieldMerge.merge(base: base, proposed: proposed, current: current) else {
            conflict("meta", name, ["缺少原值"], try? FieldMerge.encode(proposed))
            return
        }
        current = result.0
        if !result.1.isEmpty { conflict("meta", name, result.1, try? FieldMerge.encode(proposed)) }
    }

    private mutating func conflict(_ table: String, _ id: String, _ fields: [String], _ value: Data?) {
        conflicts.append(SyncConflict(table: table, rowID: id, fields: fields, phoneValue: value))
    }
}

extension Ledger {
    /// 从 old 改成 self 改了哪些：写成一张纸条。没改返回 nil。
    public func syncNote(since old: Ledger, device: String, now: Date = Date()) -> SyncNote? {
        var n = SyncNote(id: SyncNote.newID(now), device: device, createdAt: now, summary: "")
        var deletes: [String: [String]] = [:]
        var originals: [String: [String: Data]] = [:]
        func take<T: Codable & Equatable, K: Hashable>(_ table: String, _ o: [T], _ c: [T], key: (T) -> K, name: (K) -> String) -> [T]? {
            let d = rowDiff(o, c, key: key)
            let affected = Set((d.changed ?? []).map(key)).union(d.removed)
            for row in o where affected.contains(key(row)) {
                originals[table, default: [:]][name(key(row))] = try? FieldMerge.encode(row)
            }
            if !d.removed.isEmpty { deletes[table] = d.removed.map(name) }
            return d.changed
        }
        n.books = take("books", old.books, books, key: \.id, name: { $0 })
        n.accounts = take("accounts", old.accounts, accounts, key: \.id, name: { $0 })
        n.transactions = take("transactions", old.transactions, transactions, key: \.id, name: \.uuidString)
        n.changes = take("changes", old.changes, changes, key: \.id, name: \.uuidString)
        n.debts = take("debts", old.debts, debts, key: \.id, name: \.uuidString)
        n.installments = take("installments", old.installments, installments, key: \.id, name: \.uuidString)
        n.goals = take("goals", old.goals, goals, key: \.id, name: \.uuidString)
        n.insights = take("insights", old.insights, insights, key: \.id, name: \.uuidString)
        n.subscriptions = take("subscriptions", old.subscriptions, subscriptions, key: \.id, name: \.uuidString)
        n.recurring = take("recurring", old.recurring, recurring, key: \.id, name: \.uuidString)
        n.memories = take("memories", old.memories, memories, key: \.id, name: \.uuidString)
        n.captures = take("captures", old.captures, captures, key: \.id, name: \.uuidString)
        n.paperwork = take("paperwork", old.paperwork, paperwork, key: \.id, name: \.uuidString)
        // 旧界面记的客人欠款
        n.receivables = take("receivables", old.receivables, receivables, key: \.id, name: \.uuidString)
        // 生意设置（开没开生意、管哪边、本钱、估的货值、休息日、收款方式、账户算哪边）：整份带上，附原值，收的那边按字段合并
        if business != old.business {
            n.changedBusiness = true
            n.business = business
            if let was = old.business { originals["meta", default: [:]]["business"] = try? FieldMerge.encode(was) }
        }
        if profile != old.profile {
            n.profile = profile
            originals["meta", default: [:]]["profile"] = try? FieldMerge.encode(old.profile)
        }
        if currency != old.currency {
            n.currency = currency
            originals["meta", default: [:]]["currency"] = try? FieldMerge.encode(old.currency)
        }
        if lastStatementDate != old.lastStatementDate {
            n.lastStatementDate = lastStatementDate
            originals["meta", default: [:]]["lastStatementDate"] = try? FieldMerge.encode(old.lastStatementDate)
        }
        n.originalRows = originals
        n.deletes = deletes.isEmpty ? nil : deletes
        guard !n.isEmpty else { return nil }
        // 说明：用这次新记的改动记录那句话；没有就笼统说一句。
        let newChanges = (n.changes ?? []).filter { c in !old.changes.contains { $0.id == c.id } }
        n.summary = newChanges.map(\.summary).joined(separator: "；")
        if n.summary.isEmpty { n.summary = "在\(device)上改了账本" }
        return n
    }

    /// 收一张纸条。收过的不再收。返回收了没有。
    @discardableResult
    public mutating func apply(_ note: SyncNote, receivedAt: Date? = nil) -> Bool {
        apply(note, receivedAt: receivedAt, queued: [:])
    }

    @discardableResult
    fileprivate mutating func apply(_ note: SyncNote, receivedAt: Date?, queued: [String: Set<String>]) -> Bool {
        guard !appliedNotes.contains(note.id) else { return false }
        let timestamp = receivedAt ?? note.createdAt
        var awaiting = pendingPhoneDeletes ?? PhoneDeletionReceipts()
        let proposedIDs = Set((note.transactions ?? []).map(\.id))
        // 撤销比原删除先到时，从撤销纸条的原值重建那条历史，再走相同的合并。
        let originalChanges = note.originalValues(in: "changes")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var undoOwners: [UUID: Set<UUID>] = [:]
        for change in note.changes ?? [] where change.undone && change.kind == .remove {
            if !changes.contains(where: { $0.id == change.id }),
               let data = originalChanges[change.id.uuidString],
               let original = try? decoder.decode(ChangeRecord.self, from: data),
               original.id == change.id && original.kind == .remove && !original.undone {
                changes.append(original)
            }
            if let original = changes.first(where: { $0.id == change.id && !$0.undone && $0.kind == .remove }) {
                for id in original.transactionIDs where proposedIDs.contains(id) {
                    undoOwners[id, default: []].insert(change.id)
                    awaiting.undo(change.id, for: id, existing: changes)
                }
            }
        }
        var suppressed = proposedIDs.filter { awaiting.received[$0.uuidString] != nil }
        // 即使新增已收、临时凭据已清，撤销也只解除同一个删除事件。
        if !undoOwners.isEmpty {
            for removal in changes where removal.kind == .remove && !removal.undone {
                for id in removal.transactionIDs {
                    if let owners = undoOwners[id], !owners.contains(removal.id) { suppressed.insert(id) }
                }
            }
        }
        // 等待期已结束、入账才首次出现时，账本也可能仍有明确的删除原件。
        // 只检查当前缺失的初次新增。撤销、正常编辑和现在仍存在的流水不走这里。
        let firstAdds = note.addedTransactionIDs
        if !firstAdds.isEmpty {
            let absent = firstAdds.subtracting(transactions.map(\.id)).subtracting(suppressed)
            if !absent.isEmpty {
                for removal in changes where removal.kind == .remove && !removal.undone {
                    for row in removal.previous ?? [] where absent.contains(row.id) { suppressed.insert(row.id) }
                }
            }
        }
        var skipped = Set(suppressed.map { SyncRowKey("transactions", $0.uuidString) })
        for deletion in note.changes ?? [] where deletion.kind == .remove && !deletion.undone {
            if let undone = changes.first(where: { $0.id == deletion.id && $0.undone && $0.kind == .remove }) {
                skipped.insert(.init("changes", deletion.id.uuidString))
                for id in undone.transactionIDs { skipped.insert(.init("transactions", id.uuidString)) }
            }
        }
        let groups = linkedConflicts(in: note, ignoring: skipped)
        var merger = NoteMerger(note: note, conflicts: groups.conflicts, skipped: groups.blocked.union(skipped))
        for id in suppressed { merger.skipped.insert(.init("paperwork", id.uuidString)) }
        for change in note.changes ?? [] where !(change.kind == .remove && change.undone) && !suppressed.isDisjoint(with: change.transactionIDs) {
            merger.skipped.insert(.init("changes", change.id.uuidString))
        }
        // 已有行的删除仍须比较旧值；关联计划被拒时也不能偷偷保留删除意图。
        let absentDeletes = (note.deletes?["transactions"] ?? []).compactMap(UUID.init(uuidString:)).filter { id in
            !transactions.contains { $0.id == id } && !merger.skipped.contains(.init("transactions", id.uuidString))
        }
        for id in absentDeletes {
            if awaiting.received[id.uuidString] == nil { awaiting.received[id.uuidString] = .waitingSince(floor(timestamp.timeIntervalSince1970)) }
            let events = (note.changes ?? []).filter { $0.kind == .remove && !$0.undone && $0.transactionIDs.contains(id) }
            awaiting.bind(events.isEmpty ? [note.id] : events.map { $0.id.uuidString }, to: id)
        }
        if !absentDeletes.isEmpty { awaiting.track(queued) }
        let lateAdds = suppressed.intersection(firstAdds).filter { awaiting.received[$0.uuidString] != .bookingHandled }
        if !lateAdds.isEmpty {
            for id in lateAdds { awaiting.received[id.uuidString] = .bookingHandled }
            let bytes = Array(SHA256.hash(data: Data(("late-deleted:" + note.id).utf8)).prefix(16))
            let id = bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
            changes.append(ChangeRecord(id: id, kind: .edit, summary: "手机已删除这笔流水，晚到的入账没有重复记入",
                                        transactionIDs: [], author: note.device, createdAt: note.createdAt))
        }
        awaiting.finish([note.id])
        let updated = awaiting.received.isEmpty ? nil : awaiting
        if updated != pendingPhoneDeletes { pendingPhoneDeletes = updated }
        merger.rows(&books, note.books, "books", key: \.id, name: { $0 })
        merger.rows(&accounts, note.accounts, "accounts", key: \.id, name: { $0 })
        merger.rows(&transactions, note.transactions, "transactions", key: \.id, name: \.uuidString)
        // 对已不存在的流水，整次编辑都没落地。留下冲突说明即可，否则假的编辑历史会挡住撤销删除。
        let missingRows = Set(merger.conflicts.filter { $0.table == "transactions" && $0.fields == ["电脑已删除"] }.map(\.rowID))
        if !missingRows.isEmpty {
            for change in note.changes ?? [] where change.kind == .edit && !change.transactionIDs.isEmpty &&
                change.transactionIDs.allSatisfy({ missingRows.contains($0.uuidString) }) {
                merger.skipped.insert(.init("changes", change.id.uuidString))
            }
        }
        merger.rows(&changes, note.changes, "changes", key: \.id, name: \.uuidString)
        merger.rows(&debts, note.debts, "debts", key: \.id, name: \.uuidString)
        merger.rows(&installments, note.installments, "installments", key: \.id, name: \.uuidString)
        merger.rows(&goals, note.goals, "goals", key: \.id, name: \.uuidString)
        merger.rows(&insights, note.insights, "insights", key: \.id, name: \.uuidString)
        merger.rows(&subscriptions, note.subscriptions, "subscriptions", key: \.id, name: \.uuidString)
        merger.rows(&recurring, note.recurring, "recurring", key: \.id, name: \.uuidString)
        merger.rows(&memories, note.memories, "memories", key: \.id, name: \.uuidString)
        merger.rows(&captures, note.captures, "captures", key: \.id, name: \.uuidString)
        merger.rows(&paperwork, note.paperwork, "paperwork", key: \.id, name: \.uuidString)
        merger.rows(&receivables, note.receivables, "receivables", key: \.id, name: \.uuidString)
        if note.changedBusiness == true && business != note.business {
            let offered = try? FieldMerge.encode(note.business)
            if let proposed = note.business, var mine = business {
                // 两边都有：按字段合并（手机只改了「管哪边」，电脑改了本钱，两个都留）；同一项都改了，留电脑的，记一条冲突
                merger.setting(&mine, proposed, "business")
                if mine != business { business = mine }
            } else if let proposed = note.business, note.originalRows?["meta"]?["business"] == nil {
                // 电脑上还没有生意设置，手机那边原来也没有：手机新开的，直接收下
                business = proposed
            } else {
                merger.conflicts.append(.init(table: "meta", rowID: "business", fields: ["生意设置"], phoneValue: offered))
            }
            if business != nil || !receivables.isEmpty { minReaderVersion = max(minReaderVersion, 2) }
        }
        merger.setting(&profile, note.profile, "profile")
        merger.setting(&currency, note.currency, "currency")
        merger.setting(&lastStatementDate, note.lastStatementDate, "lastStatementDate")
        if note.currency != nil { Money.defaultCurrency = currency.base }
        if !merger.conflicts.isEmpty {
            // 手机预览和 Mac 收件生成同一条记录，再次打开或重放不会生成不同编号。
            let bytes = Array(SHA256.hash(data: Data(("sync-conflict:" + note.id).utf8)).prefix(16))
            let id = bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
            var change = ChangeRecord(id: id, kind: .edit, summary: "手机同步有冲突，保留电脑上的值；请核对手机记录",
                                      transactionIDs: [], author: note.device, createdAt: note.createdAt)
            change.syncConflicts = merger.conflicts
            changes.append(change)
        }
        appliedNotes.append(note.id)
        return true
    }
}

// MARK: - 纸条文件夹

/// 账本文件夹里的「手机记的」：还没收的纸条放这里，收过的挪进「已收」。
public enum SyncNotes {
    public static let folderName = "手机记的"
    public static let doneFolderName = "已收"
    /// 已收的纸条留多久（天）。
    public static let keepDays = 30

    public static func inbox(_ ledgerFolder: URL) -> URL { ledgerFolder.appendingPathComponent(folderName, isDirectory: true) }
    public static func done(_ ledgerFolder: URL) -> URL { inbox(ledgerFolder).appendingPathComponent(doneFolderName, isDirectory: true) }

    /// 写一张纸条。
    public static func write(_ note: SyncNote, ledgerFolder: URL) throws {
        try LedgerFiles.withActiveFolder(ledgerFolder) { try writeInActiveFolder(note, ledgerFolder: ledgerFolder) }
    }

    private static func writeInActiveFolder(_ note: SyncNote, ledgerFolder: URL) throws {
        let dir = inbox(ledgerFolder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        // 旧 Mac 只扫描 .json，含编辑/删除的新版纸条留给能检查原值的版本处理。
        let needsMerge = !(note.originalRows ?? [:]).isEmpty || !(note.deletes ?? [:]).isEmpty
        let ext = needsMerge ? "sync2" : "json"
        try LedgerFiles.coordinatedWrite(try enc.encode(note), to: dir.appendingPathComponent("\(note.id).\(ext)"))
    }

    /// 两代纸条都可能先以 iCloud 占位文件出现。只把已经下载的文件交给解码器。
    public static func files(in dir: URL) -> [URL] {
        files(in: dir, requestDownload: LedgerFiles.requestDownload)
    }

    static func files(in dir: URL, includeUndownloaded: Bool = false, requestDownload: (URL) -> Void) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().compactMap { name in
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                if real.hasSuffix(".json") || real.hasSuffix(".sync2") {
                    let url = dir.appendingPathComponent(real)
                    requestDownload(url)
                    if includeUndownloaded { return url }
                }
                return nil
            }
            guard name.hasSuffix(".json") || name.hasSuffix(".sync2") else { return nil }
            return dir.appendingPathComponent(name)
        }
    }

    public static func read(_ url: URL) -> SyncNote? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = coordinatedRead(url) else { return nil }
        return try? dec.decode(SyncNote.self, from: data)
    }

    /// 还没收进这本账的纸条（「手机记的」和「已收」里都看：万一 Mac 收完又被旧的一份覆盖了，还能补回来），按时间排。
    public static func unapplied(ledgerFolder: URL, ledger: Ledger) -> [(url: URL, note: SyncNote)] {
        let applied = Set(ledger.appliedNotes)
        let all = files(in: inbox(ledgerFolder)) + files(in: done(ledgerFolder))
        return all.filter { !applied.contains($0.deletingPathExtension().lastPathComponent) }
            .compactMap { u in read(u).map { (u, $0) } }
            .sorted { $0.note.id < $1.note.id }
    }

    /// 「手机记的」里还没收的纸条有几张（不读内容，很快）。
    /// 显式恢复时只认「已收」里的编号。旧账本可能已经裁掉较早的 appliedNotes。
    static func archivedIDs(in folder: URL) throws -> [String] {
        let archive = done(folder)
        guard FileManager.default.fileExists(atPath: archive.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: archive.path).sorted().compactMap { filename in
            var name = filename
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
            }
            guard name.hasSuffix(".json") || name.hasSuffix(".sync2") else { return nil }
            return (name as NSString).deletingPathExtension
        }
    }

    public static func pendingCount(ledgerFolder: URL) -> Int { files(in: inbox(ledgerFolder)).count }

    /// Mac 收完纸条后：挪进「已收」，删掉 30 天前的。
    public static func archive(_ urls: [URL], ledgerFolder: URL, now: Date = Date()) {
        let fm = FileManager.default
        let doneDir = done(ledgerFolder)
        try? fm.createDirectory(at: doneDir, withIntermediateDirectories: true)
        for u in urls where u.deletingLastPathComponent().lastPathComponent != doneFolderName {
            let target = doneDir.appendingPathComponent(u.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                guard let original = read(u), read(target) == original else { continue }
                try? fm.removeItem(at: u)
            } else {
                do { try fm.moveItem(at: u, to: target) } catch { continue }
            }
            try? fm.setAttributes([.modificationDate: now], ofItemAtPath: target.path)
        }
        for u in files(in: doneDir) {
            if let d = (try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date,
               now.timeIntervalSince(d) > Double(keepDays) * 86400 {
                try? fm.removeItem(at: u)
            }
        }
    }

    static func coordinatedRead(_ url: URL) -> Data? {
        #if canImport(Darwin)
        var out: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in out = try? Data(contentsOf: u) }
        return out
        #else
        return try? Data(contentsOf: url)
        #endif
    }
}

// MARK: - Mac：读账本时顺便收纸条

/// Mac 上的账本：每次读的时候看一眼「手机记的」，有没收的纸条就收进来、存盘、挪进「已收」。
/// app 和 fin 都用它，谁先读到谁收（收几遍结果一样）。
public final class InboxApplyingStore: LedgerStore, @unchecked Sendable {
    public let primary: any LedgerStore
    public let folder: URL
    private let lock = NSLock()
    /// 上次收进来的纸条（app 用来提示「收到手机记的 N 条」）。
    public private(set) var lastApplied: [SyncNote] = []

    private var nextDeleteExpiry: Date?
    private var waitingForPhotos: [String] = []
    private let now: () -> Date
    private let relocatedFrom: URL?

    public init(primary: any LedgerStore, folder: URL, relocatedFrom: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.primary = primary; self.folder = folder; self.relocatedFrom = relocatedFrom
    }

    private var retiredFolder: URL? { relocatedFrom.flatMap { LedgerFiles.hasMoved($0) ? $0 : nil } }

    public func load() throws -> Ledger {
        lock.lock(); defer { lock.unlock() }
        if let old = retiredFolder {
            return try withLedgerFileLock(at: folder.appendingPathComponent(".旧目录补收")) {
                try collectNotes(from: old)
            }
        }
        return try collectNotes(from: nil)
    }

    private func collectNotes(from retired: URL?) throws -> Ledger {
        var ledger = try primary.load()
        if ledger.minReaderVersion > 2 { return ledger }
        let time = now()
        let previousDeletes = ledger.pendingPhoneDeletes
        let late = try retired.map { try LatePhoneDelivery.stage(from: $0, to: folder, applied: Set(ledger.appliedNotes), now: time) }
        let pending = SyncNotes.unapplied(ledgerFolder: folder, ledger: ledger)
        let previousPhotos = ledger.changes.compactMap(\.pendingPhonePhoto)
        for photo in previousPhotos { photo.restoreReferences(in: &ledger) }
        var queued = late?.relatedNotes ?? [:]
        for item in pending { item.note.indexRelatedTransactions(in: &queued) }
        ledger.pendingPhoneDeletes?.track(queued)
        var applied: [SyncNote] = []
        for item in pending where late?.allows(item.note) != false && ledger.apply(item.note, receivedAt: time, queued: queued) { applied.append(item.note) }
        let done = Set(ledger.appliedNotes)
        ledger.pendingPhoneDeletes?.finish(done)
        if ledger.pendingPhoneDeletes != nil {
            var observed = late?.observedBookings ?? []
            for item in pending { observed.formUnion(item.note.addedTransactionIDs) }
            ledger.prunePhoneDeletes(at: time, observed: observed)
        }
        var missing = late?.timedOutFiles ?? []
        if let old = retired {
            for photo in previousPhotos where !photo.available(from: old, in: folder) { missing.insert(photo.file) }
        } else {
            missing.formUnion(previousPhotos.map(\.file))
        }
        ledger.updatePendingPhotos(missing, now: now())
        if !applied.isEmpty || previousDeletes != ledger.pendingPhoneDeletes || previousPhotos != ledger.changes.compactMap(\.pendingPhonePhoto) {
            try primary.save(ledger)
            lastApplied = applied
        }
        // 收过的（包括以前收过、文件还在「手机记的」里的）挪走。
        if FileManager.default.fileExists(atPath: SyncNotes.inbox(folder).path) {
            SyncNotes.archive(SyncNotes.files(in: SyncNotes.inbox(folder)).filter { done.contains($0.deletingPathExtension().lastPathComponent) }, ledgerFolder: folder)
        }
        if let old = retired, let late { LatePhoneDelivery.archive(late.ready, from: old, to: folder, applied: done) }
        nextDeleteExpiry = ledger.pendingPhoneDeletes?.earliestWaitingTime.map { Date(timeIntervalSince1970: $0 + PhoneDeletionReceipts.lifetime) }
        waitingForPhotos = ledger.changes.compactMap { $0.pendingPhonePhoto?.file }
        return ledger
    }

    public func save(_ ledger: Ledger) throws {
        lock.lock(); defer { lock.unlock() }
        try primary.save(ledger)
    }

    public func changeStamp() -> String? {
        lock.lock(); defer { lock.unlock() }
        let notes = SyncNotes.files(in: SyncNotes.inbox(folder)).map(\.lastPathComponent).joined(separator: ",")
        let base = primary.changeStamp()
        let late = retiredFolder.flatMap { LatePhoneDelivery.stamp($0, waitingFor: waitingForPhotos) }
        if let expiry = nextDeleteExpiry, now() >= expiry { return "\(base ?? "")|删除凭据到期" }
        if notes.isEmpty && late == nil { return base }
        let due = retiredFolder == nil ? [] : PhotoWaitTimes(folder: folder).expired(at: now())
        return "\(base ?? "")|notes:\(notes)|late:\(late ?? "")|due:\(due.joined(separator: ","))"
    }
}

// MARK: - iPhone：只写纸条

/// iPhone 接上 iCloud 云盘「夏夏账本」文件夹后用的账本：读 Mac 写的账本（先复制一份到手机本地再读），
/// 加上自己还没被收走的纸条；保存时不碰账本文件，只写一张纸条。
public final class PhoneSyncStore: LedgerStore, @unchecked Sendable {
    public let folder: URL
    public let device: String
    /// 账本在手机本地的副本（最后一次成功下载的），没网时照样能看。
    public let cache: URL
    private let lock = NSLock()
    /// 账本文件还没从 iCloud 下载下来（先显示上次的副本）。
    public private(set) var waitingForDownload = false
    /// 文件夹里还没有账本（Mac 还没开过）。
    public private(set) var noLedgerYet = false

    public init(folder: URL, device: String = "iPhone", cache: URL) {
        self.folder = folder; self.device = device; self.cache = cache
    }

    public var ledgerURL: URL { folder.appendingPathComponent("ledger.sqlite") }

    public func load() throws -> Ledger {
        lock.lock(); defer { lock.unlock() }
        return try readCurrent()
    }

    private func readCurrent() throws -> Ledger {
        refreshCache()
        var ledger: Ledger
        #if canImport(SQLite3)
        ledger = FileManager.default.fileExists(atPath: cache.path) ? try SQLiteLedgerStore(url: cache).load() : .fresh
        #else
        ledger = .fresh
        #endif
        for item in SyncNotes.unapplied(ledgerFolder: folder, ledger: ledger) { ledger.apply(item.note) }
        ledger.revision.record(ledgerURL, digest: try ledger.contentDigest())
        return ledger
    }

    public func save(_ ledger: Ledger) throws {
        lock.lock(); defer { lock.unlock() }
        try LedgerFiles.requireActive(folder)
        try ledger.checkBusinessVersion()
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try withLedgerFileLock(at: cache) {
            let current = try readCurrent()
            try current.checkBusinessVersion()
            try ledger.revision.check(ledgerURL, current: current.contentDigest())
            guard let note = ledger.syncNote(since: current, device: device) else { return }
            var next = current
            next.apply(note)
            let digest = try next.contentDigest()
            try SyncNotes.write(note, ledgerFolder: folder)
            ledger.revision.record(ledgerURL, digest: digest)
        }
    }

    public func changeStamp() -> String? {
        #if canImport(Darwin)
        try? FileManager.default.startDownloadingUbiquitousItem(at: ledgerURL)
        #endif
        let notes = (SyncNotes.files(in: SyncNotes.inbox(folder)) + SyncNotes.files(in: SyncNotes.done(folder)))
            .map(\.lastPathComponent).sorted().joined(separator: ",")
        return "\(fileStamp([ledgerURL]) ?? "none")|\(notes)"
    }

    /// 账本已经下载到手机：复制一份到本地（复制时和 iCloud 协调，不会读到写了一半的）。没下载好就先请系统下载，用上次的副本。
    private func refreshCache() {
        let fm = FileManager.default
        noLedgerYet = false
        waitingForDownload = false
        #if canImport(Darwin)
        let placeholder = folder.appendingPathComponent(".ledger.sqlite.icloud")
        if !fm.fileExists(atPath: ledgerURL.path) {
            if fm.fileExists(atPath: placeholder.path) {
                try? fm.startDownloadingUbiquitousItem(at: ledgerURL)
                // 第一次（手机上还没有副本）多等一会儿，免得一打开是空的；以后有副本就不等。
                let waitRounds = fm.fileExists(atPath: cache.path) ? 0 : 30
                for _ in 0..<waitRounds where !fm.fileExists(atPath: ledgerURL.path) { Thread.sleep(forTimeInterval: 0.5) }
                if !fm.fileExists(atPath: ledgerURL.path) { waitingForDownload = true; return }
            } else {
                noLedgerYet = true
                return
            }
        }
        if let v = try? ledgerURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let status = v.ubiquitousItemDownloadingStatus, status != .current {
            try? fm.startDownloadingUbiquitousItem(at: ledgerURL)
            if fm.fileExists(atPath: cache.path) { waitingForDownload = true; return }
        }
        // 和本地副本一样新就不用再复制。
        let remote = fileStamp([ledgerURL])
        let stampFile = cache.appendingPathExtension("stamp")
        if let remote, fm.fileExists(atPath: cache.path),
           (try? String(contentsOf: stampFile, encoding: .utf8)) == remote { return }
        try? fm.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = cache.deletingLastPathComponent().appendingPathComponent("ledger-copy-\(UUID().uuidString).sqlite")
        var err: NSError?
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: ledgerURL, options: [], error: &err) { u in
            copied = (try? fm.copyItem(at: u, to: tmp)) != nil
        }
        guard copied else { try? fm.removeItem(at: tmp); return }
        _ = try? fm.replaceItemAt(cache, withItemAt: tmp)
        if !fm.fileExists(atPath: cache.path) { try? fm.moveItem(at: tmp, to: cache) }
        if let remote { try? remote.write(to: stampFile, atomically: true, encoding: .utf8) }
        #else
        if fm.fileExists(atPath: ledgerURL.path) {
            try? fm.removeItem(at: cache)
            try? fm.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: ledgerURL, to: cache)
        } else {
            noLedgerYet = true
        }
        #endif
    }

    /// 还没被 Mac 收走的纸条有几张（设置页「同步」里显示）。
    public var waitingNotes: Int { SyncNotes.pendingCount(ledgerFolder: folder) }
}

// MARK: - iPhone 记住选过的文件夹

/// iPhone 上选过的 iCloud 云盘「夏夏账本」文件夹：存成书签，下次打开不用再选。
public enum PhoneFolderLink {
    static let key = "xiaxia.phoneFolderBookmark"

    #if canImport(Darwin)
    /// 用户在「文件」里选了文件夹后调用：记住它。
    public static func remember(_ url: URL, defaults: UserDefaults = .standard) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: key)
    }

    /// 选过的文件夹（已经开始访问，app 一直用到退出）。没选过或找不到了返回 nil。
    public static func resolve(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: key)
        }
        return url
    }

    public static func forget(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }

    public static var isLinked: Bool { UserDefaults.standard.data(forKey: key) != nil }
    #endif

    /// 选的文件夹对不对：里面要有 ledger.sqlite（或者它的 iCloud 占位文件），或者至少名字是「夏夏账本」。
    public static func looksLikeLedgerFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("ledger.sqlite").path)
            || fm.fileExists(atPath: url.appendingPathComponent(".ledger.sqlite.icloud").path)
            || url.lastPathComponent == "夏夏账本"
    }
}

/// 账本文件在哪（备份、删除数据、恢复用）。iPhone 接 iCloud 文件夹时不在手机上动账本文件，返回 nil。
public func ledgerFileURL(_ store: any LedgerStore) -> URL? {
    if let s = store as? InboxApplyingStore { return ledgerFileURL(s.primary) }
    if store is PhoneSyncStore { return nil }
    #if canImport(SQLite3)
    if let m = store as? MigratingStore { return m.primary.url }
    if let s = store as? SQLiteLedgerStore { return s.url }
    #endif
    if let s = store as? JSONFileLedgerStore { return s.url }
    return nil
}
