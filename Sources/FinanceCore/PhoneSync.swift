import Foundation

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
// 纸条里是整条记录（新的样子）和要删的编号，收的时候按编号覆盖 / 删除，所以先收后收、收几遍结果都一样。
// 两边改了同一条，后收的那张纸条说了算（很少见：手机上改的一般是刚记的那几笔）。

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

private func upsert<T, K: Hashable>(_ rows: inout [T], _ incoming: [T]?, _ removed: [String]?, key: (T) -> K, name: (K) -> String) {
    if let removed, !removed.isEmpty {
        let gone = Set(removed)
        rows.removeAll { gone.contains(name(key($0))) }
    }
    for r in incoming ?? [] {
        if let i = rows.firstIndex(where: { key($0) == key(r) }) { rows[i] = r } else { rows.append(r) }
    }
}

extension Ledger {
    /// 从 old 改成 self 改了哪些：写成一张纸条。没改返回 nil。
    public func syncNote(since old: Ledger, device: String, now: Date = Date()) -> SyncNote? {
        var n = SyncNote(id: SyncNote.newID(now), device: device, createdAt: now, summary: "")
        var deletes: [String: [String]] = [:]
        func take<T: Equatable, K: Hashable>(_ table: String, _ o: [T], _ c: [T], key: (T) -> K, name: (K) -> String) -> [T]? {
            let d = rowDiff(o, c, key: key)
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
        if profile != old.profile { n.profile = profile }
        if currency != old.currency { n.currency = currency }
        if lastStatementDate != old.lastStatementDate { n.lastStatementDate = lastStatementDate }
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
    public mutating func apply(_ note: SyncNote) -> Bool {
        guard !appliedNotes.contains(note.id) else { return false }
        let d = note.deletes ?? [:]
        upsert(&books, note.books, d["books"], key: \.id, name: { $0 })
        upsert(&accounts, note.accounts, d["accounts"], key: \.id, name: { $0 })
        upsert(&transactions, note.transactions, d["transactions"], key: \.id, name: \.uuidString)
        upsert(&changes, note.changes, d["changes"], key: \.id, name: \.uuidString)
        upsert(&debts, note.debts, d["debts"], key: \.id, name: \.uuidString)
        upsert(&installments, note.installments, d["installments"], key: \.id, name: \.uuidString)
        upsert(&goals, note.goals, d["goals"], key: \.id, name: \.uuidString)
        upsert(&insights, note.insights, d["insights"], key: \.id, name: \.uuidString)
        upsert(&subscriptions, note.subscriptions, d["subscriptions"], key: \.id, name: \.uuidString)
        upsert(&recurring, note.recurring, d["recurring"], key: \.id, name: \.uuidString)
        upsert(&memories, note.memories, d["memories"], key: \.id, name: \.uuidString)
        upsert(&captures, note.captures, d["captures"], key: \.id, name: \.uuidString)
        upsert(&paperwork, note.paperwork, d["paperwork"], key: \.id, name: \.uuidString)
        upsert(&receivables, note.receivables, d["receivables"], key: \.id, name: \.uuidString)
        if note.changedBusiness == true { business = note.business }
        if let p = note.profile { profile = p }
        if let c = note.currency { currency = c; Money.defaultCurrency = c.base }
        if let l = note.lastStatementDate { lastStatementDate = l }
        appliedNotes.append(note.id)
        if appliedNotes.count > 3000 { appliedNotes.removeFirst(appliedNotes.count - 3000) }
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
        let dir = inbox(ledgerFolder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try LedgerFiles.coordinatedWrite(try enc.encode(note), to: dir.appendingPathComponent("\(note.id).json"))
    }

    /// 文件夹里的纸条文件（.json），按名字排序。iCloud 还没下载下来的（.xxx.json.icloud）顺便请系统下载，这次先不算。
    public static func files(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var out: [URL] = []
        for name in names.sorted() {
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                #if canImport(Darwin)
                let real = String(name.dropFirst().dropLast(".icloud".count))
                try? fm.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(real))
                #endif
                continue
            }
            if name.hasSuffix(".json") { out.append(dir.appendingPathComponent(name)) }
        }
        return out
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
    public static func pendingCount(ledgerFolder: URL) -> Int { files(in: inbox(ledgerFolder)).count }

    /// Mac 收完纸条后：挪进「已收」，删掉 30 天前的。
    public static func archive(_ urls: [URL], ledgerFolder: URL, now: Date = Date()) {
        let fm = FileManager.default
        let doneDir = done(ledgerFolder)
        try? fm.createDirectory(at: doneDir, withIntermediateDirectories: true)
        for u in urls where u.deletingLastPathComponent().lastPathComponent != doneFolderName {
            let target = doneDir.appendingPathComponent(u.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: u, to: target)
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

    public init(primary: any LedgerStore, folder: URL) { self.primary = primary; self.folder = folder }

    public func load() throws -> Ledger {
        lock.lock(); defer { lock.unlock() }
        var ledger = try primary.load()
        if ledger.minReaderVersion > 2 { return ledger }
        let fm = FileManager.default
        guard fm.fileExists(atPath: SyncNotes.inbox(folder).path) else { return ledger }
        let pending = SyncNotes.unapplied(ledgerFolder: folder, ledger: ledger)
        var applied: [SyncNote] = []
        for item in pending where ledger.apply(item.note) { applied.append(item.note) }
        if !applied.isEmpty {
            try primary.save(ledger)
            lastApplied = applied
        }
        // 收过的（包括以前收过、文件还在「手机记的」里的）挪走。
        let done = Set(ledger.appliedNotes)
        SyncNotes.archive(SyncNotes.files(in: SyncNotes.inbox(folder)).filter { done.contains($0.deletingPathExtension().lastPathComponent) },
                          ledgerFolder: folder)
        return ledger
    }

    public func save(_ ledger: Ledger) throws {
        lock.lock(); defer { lock.unlock() }
        try primary.save(ledger)
    }

    public func changeStamp() -> String? {
        let notes = SyncNotes.files(in: SyncNotes.inbox(folder)).map(\.lastPathComponent).joined(separator: ",")
        let base = primary.changeStamp()
        return notes.isEmpty ? base : "\(base ?? "")|notes:\(notes)"
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
        try ledger.checkBusinessVersion()
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try withLedgerFileLock(at: cache) {
            let current = try readCurrent()
            try current.checkBusinessVersion()
            try ledger.revision.check(ledgerURL, current: current.contentDigest())
            guard ledger.business == current.business, ledger.receivables == current.receivables else {
                throw BusinessError(message: "生意设置和应收请在 Mac 上修改")
            }
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
