import Foundation

/// 删除数据（ming 2026-11-23：「增一个东西,就是演示数据,以及删除数据」）。
/// 设置 → 数据 里用：全部清空从头开始，或者只清空某一个账本。
/// 清空不能用「撤销」退回去（东西太多），所以 app 在清空前先把账本文件复制一份（见 `LedgerBackup`），要后悔就从备份恢复。
public enum WipeScope: Hashable, Sendable {
    /// 流水、账户、账本、目标、订阅、欠款、分期、重复记账、夏夏的意见和记忆全清掉，回到刚装好的样子。
    /// 夏夏的名字、性格、对你的称呼、主币种这些偏好留着。
    case everything
    /// 只清这个账本里的流水、目标、订阅、欠款、分期、重复记账；账本本身和账户留着。
    case book(String)
}

/// 要删掉多少东西，删之前给人看。
public struct WipeCount: Equatable, Sendable {
    public var transactions = 0
    public var accounts = 0
    public var goals = 0
    public var subscriptions = 0
    /// 欠款和分期。
    public var debts = 0
    public var recurring = 0

    public var isEmpty: Bool { transactions + accounts + goals + subscriptions + debts + recurring == 0 }

    /// 「1.528 笔流水、6 个账户、1 个目标」这样一句；什么都没有就是「没有东西」。
    public var text: String {
        let parts: [(Int, String)] = [
            (transactions, "笔流水"), (accounts, "个账户"), (goals, "个目标"),
            (subscriptions, "个订阅"), (debts, "笔欠款和分期"), (recurring, "个重复记账"),
        ]
        let shown = parts.filter { $0.0 > 0 }.map { "\(WipeCount.grouped($0.0)) \($0.1)" }
        return shown.isEmpty ? "没有东西" : shown.joined(separator: "、")
    }

    static func grouped(_ n: Int) -> String {
        var digits = Array(String(n))
        var i = digits.count - 3
        while i > 0 { digits.insert(".", at: i); i -= 3 }
        return String(digits)
    }
}

extension Ledger {
    /// 这个范围里现在有多少东西。
    public func wipeCount(_ scope: WipeScope) -> WipeCount {
        switch scope {
        case .everything:
            return WipeCount(transactions: transactions.count, accounts: accounts.count, goals: goals.count,
                             subscriptions: subscriptions.count, debts: debts.count + installments.count, recurring: recurring.count)
        case .book(let id):
            return WipeCount(transactions: transactions.filter { $0.bookID == id }.count, accounts: 0,
                             goals: goals.filter { $0.bookID == id }.count,
                             subscriptions: subscriptions.filter { $0.bookID == id }.count,
                             debts: debts.filter { $0.bookID == id }.count + installments.filter { $0.bookID == id }.count,
                             recurring: recurring.filter { $0.template.bookID == id }.count)
        }
    }

    /// 清空。改动记录里留一条说明（全部清空时以前的改动记录也一起清掉，只剩这一条）。
    /// - backupNote: 清空前的备份放在哪，写进说明里，方便以后找。
    @discardableResult
    public mutating func wipe(_ scope: WipeScope, author: String, backupNote: String? = nil, now: Date = Date()) throws -> ChangeRecord {
        let count = wipeCount(scope)
        let tail = backupNote.map { "。清空前的备份：\($0)" } ?? ""
        switch scope {
        case .everything:
            var fresh = Ledger.fresh
            fresh.schemaVersion = schemaVersion
            fresh.minReaderVersion = minReaderVersion
            fresh.profile = profile
            // 自己加的分类是跟着账本内容走的，一起清；名字、性格、称呼留着。
            fresh.profile.categories = []
            fresh.currency = currency
            // 收过的手机纸条编号留着，免得清空后把「已收」里的旧纸条又收回来。
            fresh.appliedNotes = appliedNotes
            fresh.pendingPhoneDeletes = pendingPhoneDeletes
            let change = ChangeRecord(kind: .delete, summary: "清空了全部数据（\(count.text)）\(tail)", transactionIDs: [],
                                      author: author, createdAt: now)
            fresh.changes = [change]
            self = fresh.replacingContents(of: self)
            return change
        case .book(let id):
            guard let book = books.first(where: { $0.id == id }) else { throw EditError.unknownBook(id) }
            let gone = Set(transactions.filter { $0.bookID == id }.map(\.id))
            transactions.removeAll { $0.bookID == id }
            goals.removeAll { $0.bookID == id }
            subscriptions.removeAll { $0.bookID == id }
            debts.removeAll { $0.bookID == id }
            installments.removeAll { $0.bookID == id }
            recurring.removeAll { $0.template.bookID == id }
            insights.removeAll { $0.bookID == id }
            // 别的账本里的目标、欠款、分期如果引用了被删的流水，把引用去掉。
            for k in goals.indices { goals[k].contributionIDs.removeAll { gone.contains($0) } }
            for k in debts.indices { debts[k].repaymentIDs.removeAll { gone.contains($0) } }
            for k in installments.indices {
                installments[k].paidIDs.removeAll { gone.contains($0) }
                if let p = installments[k].purchaseID, gone.contains(p) { installments[k].purchaseID = nil }
            }
            let change = ChangeRecord(kind: .delete, summary: "清空了「\(book.name)」账本（\(count.text)）\(tail)", transactionIDs: [],
                                      author: author, createdAt: now)
            changes.append(change)
            return change
        }
    }
}

/// 账本文件的备份：复制一份放在账本旁边的文件夹里。删除数据前、从备份恢复前都先做一次。
public enum LedgerBackup {
    public static let folderName = "删除前备份"

    public struct Item: Identifiable, Hashable, Sendable {
        public var url: URL
        public var date: Date
        public var id: URL { url }
    }

    /// 这个存储对应的账本文件；内存账本没有文件。
    public static func fileURL(of store: any LedgerStore) -> URL? {
        ledgerFileURL(store)
    }

    public static func folder(for file: URL) -> URL { file.deletingLastPathComponent().appendingPathComponent(folderName) }

    /// 复制一份。账本文件还不存在（从没记过）返回 nil；复制失败抛错，调用方就不要往下删了。
    /// 只留最近 `keep` 份。
    @discardableResult
    public static func make(of file: URL, label: String, keep: Int = 10, now: Date = Date()) throws -> URL? {
        try make(of: file, label: label, keep: keep, now: now) { destination in
            #if canImport(SQLite3)
            if file.pathExtension.lowercased() == "sqlite" {
                let source = try SQLiteDB.reader(url: file)
                try source.exec("BEGIN")
                _ = try source.minimumVersion() // 固定读快照，复制 DELETE 主文件期间不允许提交。
                if try source.query("PRAGMA journal_mode").first == "wal" {
                    try source.exec("COMMIT")
                    try source.writeSnapshot(to: destination)
                } else {
                    try FileManager.default.copyItem(at: file, to: destination)
                    try source.exec("COMMIT")
                }
                return
            }
            #endif
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }

    static func make(of file: URL, label: String, keep: Int = 10, now: Date = Date(),
                     writeSnapshot: (URL) throws -> Void) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return nil }
        let dir = folder(for: file)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let ext = file.pathExtension.isEmpty ? "sqlite" : file.pathExtension
        var dest = dir.appendingPathComponent("ledger-\(f.string(from: now))-\(label).\(ext)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("ledger-\(f.string(from: now))-\(label)-\(n).\(ext)"); n += 1
        }
        let staging = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: staging) }
        try writeSnapshot(staging)
        try fm.moveItem(at: staging, to: dest)
        // 复制会带上原文件的修改时间；列表显示的是「什么时候备份的」，改成现在。
        try? fm.setAttributes([.modificationDate: now], ofItemAtPath: dest.path)
        for old in list(for: file).dropFirst(keep) { try? fm.removeItem(at: old.url) }
        return dest
    }

    /// 这个账本的备份，从新到旧。
    public static func list(for file: URL) -> [Item] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: folder(for: file), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("ledger-") && ["sqlite", "json"].contains($0.pathExtension) }
            .map { u in
                let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return Item(url: u, date: d)
            }
            .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    /// 读出备份里的账本（恢复前先看看里面有多少东西，恢复时把它存回去）。
    public static func load(_ backup: URL) throws -> Ledger {
        #if canImport(SQLite3)
        if backup.pathExtension != "json" { return try SQLiteLedgerStore(url: backup).load() }
        #endif
        return try JSONFileLedgerStore(url: backup).load()
    }

    public static func load(_ backup: URL, replacing target: Ledger) throws -> Ledger {
        var restored = try load(backup)
        var seen = Set(restored.appliedNotes)
        let archived = try target.revision.ledgerFolder.map(SyncNotes.archivedIDs(in:)) ?? []
        restored.appliedNotes += (target.appliedNotes + archived).filter { seen.insert($0).inserted }
        let deletes = Set(target.pendingPhoneDeletes ?? []).union(restored.pendingPhoneDeletes ?? [])
        restored.pendingPhoneDeletes = deletes.isEmpty ? nil : deletes.sorted()
        return restored.replacingContents(of: target)
    }

}
