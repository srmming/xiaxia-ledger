#if canImport(SQLite3)
import Foundation
import SQLite3
import CryptoKit

/// 正式存储：一个 SQLite 文件，app 和 fin 共用（2026-11-21 ming 定）。
///
/// - 每张表一行一条记录，`json` 列是完整内容（和 JSON 文件版同一套 Codable，加字段不用改表）；
///   流水表另外拆出日期、金额、账户、账本、分类几列，方便直接用 sqlite3 查。
/// - 保存时在一个事务里整体替换，app 和 CLI 同时写也不会写坏（busy_timeout 等对方写完）。
/// - 放在 iCloud 云盘里同步，所以用 DELETE 日志模式（不用 WAL：-wal 文件被 iCloud 单独同步会出问题）。
///   同一时间只在一台设备上写；iPhone 版接 iCloud 时再换成 CloudKit 同步。
public struct SQLiteLedgerStore: LedgerStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func changeStamp() -> String? {
        fileStamp([url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-journal")])
    }

    static let tables = ["books", "accounts", "transactions", "changes", "debts", "installments", "goals", "insights", "subscriptions", "memories", "captures", "paperwork", "receivables"]

    private func requireDownloadedFile() throws {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        if !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: placeholder.path) {
            #if canImport(Darwin)
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            #endif
            throw BusinessError(message: "账本还在从 iCloud 下载，请稍后再试")
        }
    }

    public func load() throws -> Ledger {
        try requireDownloadedFile()
        guard FileManager.default.fileExists(atPath: url.path) else {
            let fresh = Ledger.fresh
            fresh.revision.record(url, digest: nil)
            return fresh
        }
        let db = try SQLiteDB.reader(url: url)
        try db.exec("BEGIN")
        let ledger = try read(from: db)
        ledger.revision.record(url, digest: try db.storageDigest())
        try db.exec("COMMIT")
        return ledger
    }

    func read(from db: SQLiteDB) throws -> Ledger {
        let existing = Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table'"))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        func rows<T: Decodable>(_ table: String, _ type: T.Type) throws -> [T] {
            guard existing.contains(table) else { return [] }
            return try db.query("SELECT json FROM \(table) ORDER BY seq").enumerated().map { i, json in
                do { return try dec.decode(T.self, from: Data(json.utf8)) }
                catch { throw LedgerReadError(table: table, row: i + 1, underlying: error) }
            }
        }
        var ledger = Ledger(books: try rows("books", Book.self), accounts: try rows("accounts", Account.self),
                            transactions: try rows("transactions", Transaction.self), changes: try rows("changes", ChangeRecord.self))
        ledger.receivables = try rows("receivables", Receivable.self)
        if existing.contains("meta") {
            ledger.minReaderVersion = try db.minimumVersion()
            if let value = try db.query("SELECT value FROM meta WHERE key = 'business'").first {
                let data = Data(value.utf8)
                ledger.business = try dec.decode(BusinessSettings.self, from: data)
                let history = try dec.decode(BusinessUndoIndex.self, from: data)
                for i in ledger.changes.indices {
                    if let prior = history.undo?[ledger.changes[i].id.uuidString] {
                        ledger.changes[i].before?.changedBusiness = true
                        ledger.changes[i].before?.business = prior.settings
                    }
                }
            }
        }
        ledger.debts = try rows("debts", Debt.self)
        ledger.installments = try rows("installments", Installment.self)
        ledger.goals = try rows("goals", Goal.self)
        ledger.insights = try rows("insights", Insight.self)
        ledger.subscriptions = try rows("subscriptions", Subscription.self)
        // 夏夏的记忆（2026-11-23 加）：单独一张表，一条一行；旧版本不认识这张表，会原样留着。
        ledger.memories = try rows("memories", Memory.self)
        // 待记录、小票发票和报销（2026-11-23 加）：各一张表；旧版本不认识，会原样留着。
        ledger.captures = try rows("captures", Capture.self)
        ledger.paperwork = try rows("paperwork", Paperwork.self)
        guard existing.contains("meta") else { return ledger }
        if let v = try db.query("SELECT value FROM meta WHERE key = 'appliedNotes'").first {
            ledger.appliedNotes = (try? dec.decode([String].self, from: Data(v.utf8))) ?? []
        }
        if let v = try db.query("SELECT value FROM meta WHERE key = 'schemaVersion'").first, let n = Int(v) { ledger.schemaVersion = n }
        if let v = try db.query("SELECT value FROM meta WHERE key = 'lastStatementDate'").first {
            ledger.lastStatementDate = try dec.decode([String: LocalDate].self, from: Data(v.utf8))
        }
        // 夏夏性格、目标、自己加的分类：放在 meta 里（旧版本不认识这个键，会原样留着）。
        if let v = try db.query("SELECT value FROM meta WHERE key = 'profile'").first {
            ledger.profile = (try? dec.decode(Profile.self, from: Data(v.utf8))) ?? Profile()
        }
        // 重复记账：也放在 meta 里，不加新表，旧版本 app 读同一个文件不受影响。
        if let v = try db.query("SELECT value FROM meta WHERE key = 'recurring'").first {
            ledger.recurring = try dec.decode([Recurring].self, from: Data(v.utf8))
        }
        // 主币种和汇率表（2026-11-22 加）。没有就是欧元。
        if let v = try db.query("SELECT value FROM meta WHERE key = 'currency'").first {
            ledger.currency = (try? dec.decode(CurrencySettings.self, from: Data(v.utf8))) ?? CurrencySettings()
        }
        Money.defaultCurrency = ledger.currency.base
        return ledger
    }

    private func checkRevision(_ ledger: Ledger, db: SQLiteDB) throws {
        if url.lastPathComponent == "ledger.sqlite", LedgerFiles.hasMoved(url.deletingLastPathComponent()) {
            throw LedgerRevision.conflict
        }
        try ledger.revision.check(url, current: db.storageDigest())
    }

    public func save(_ ledger: Ledger) throws {
        try save(ledger, writeWALSnapshot: { try $0.writeSnapshot(to: $1) })
    }

    func save(_ ledger: Ledger, writeWALSnapshot: (SQLiteDB, URL) throws -> Void) throws {
        try requireDownloadedFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ledger.checkBusinessVersion()
        // WAL 写连接失败退出时，由只读连接最后关闭，避免自动 checkpoint 改动原文件。
        var keepWAL: SQLiteDB?
        defer { withExtendedLifetime(keepWAL) {} }
        let mayCreate = ledger.revision.expected(at: url) == nil
        let db = try SQLiteDB(url: url, allowCreate: mayCreate)
        let isWAL = try db.query("PRAGMA journal_mode").first == "wal"
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        func js<T: Encodable>(_ v: T) throws -> String { String(decoding: try enc.encode(v), as: UTF8.self) }

        do {
            if isWAL {
                // 先以普通模式读取 WAL 索引，再启用独占模式。这样 SQLite 在空事务结束后
                // 仍持有同一把文件锁，可以在事务外做 VACUUM INTO 和切换日志模式。
                _ = try db.minimumVersion()
                try db.exec("PRAGMA locking_mode = EXCLUSIVE")
                try db.exec("BEGIN EXCLUSIVE")
                let stored = try db.minimumVersion()
                let version = try ledger.versionForSave(stored: stored)
                let upgrade = try version > stored && db.hasLedger()
                try checkRevision(ledger, db: db)
                try db.exec("COMMIT")
                if upgrade {
                    _ = try LedgerBackup.make(of: url, label: "开生意模式前") { destination in
                        try writeWALSnapshot(db, destination)
                    }
                }
                try db.exec("PRAGMA journal_mode = DELETE")
            }
            try db.exec("BEGIN IMMEDIATE")
            let stored = try db.minimumVersion()
            let version = try ledger.versionForSave(stored: stored)
            if !isWAL { try checkRevision(ledger, db: db) }
            guard try db.query("PRAGMA journal_mode").first != "wal" else { throw LedgerRevision.conflict }
            if try !isWAL && version > stored && db.hasLedger() {
                _ = try LedgerBackup.make(of: url, label: "开生意模式前")
            }
            try db.migrate()
            try db.run("INSERT OR REPLACE INTO meta (key,value) VALUES ('minReaderVersion',?)", [version])
            if let settings = ledger.business {
                // 旧 Codable 会删掉 changes 里不认识的撤销字段；随设置留一份。
                var fields = try JSONSerialization.jsonObject(with: enc.encode(settings)) as? [String: Any] ?? [:]
                var undo: [String: BusinessUndoIndex.Prior] = [:]
                for change in ledger.changes where !change.undone && change.before?.changedBusiness == true {
                    undo[change.id.uuidString] = .init(settings: change.before?.business)
                }
                fields["undo"] = try JSONSerialization.jsonObject(with: enc.encode(undo))
                let data = try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
                try db.run("INSERT OR REPLACE INTO meta (key,value) VALUES ('business',?)", [String(decoding: data, as: UTF8.self)])
            } else { try db.exec("DELETE FROM meta WHERE key='business'") }
            for t in Self.tables { try db.exec("DELETE FROM \(t)") }
            for (i, row) in ledger.receivables.enumerated() {
                try db.run("INSERT INTO receivables (id,seq,json) VALUES (?,?,?)", [row.id.uuidString, i, js(row)])
            }
            for (i, b) in ledger.books.enumerated() { try db.run("INSERT INTO books (id, seq, json) VALUES (?, ?, ?)", [b.id, i, js(b)]) }
            for (i, a) in ledger.accounts.enumerated() { try db.run("INSERT INTO accounts (id, seq, json) VALUES (?, ?, ?)", [a.id, i, js(a)]) }
            for (i, t) in ledger.transactions.enumerated() {
                try db.run("""
                    INSERT INTO transactions (id, seq, date, amount_cents, account_id, book_id, category, flow, description, json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [t.id.uuidString, i, t.date.description, t.amount.cents, t.accountID, t.bookID, t.category,
                          t.flow?.rawValue, t.description, js(t)])
            }
            for (i, c) in ledger.changes.enumerated() {
                try db.run("INSERT INTO changes (id, seq, author, summary, json) VALUES (?, ?, ?, ?, ?)",
                           [c.id.uuidString, i, c.author, c.summary, js(c)])
            }
            for (i, d) in ledger.debts.enumerated() { try db.run("INSERT INTO debts (id, seq, json) VALUES (?, ?, ?)", [d.id.uuidString, i, js(d)]) }
            for (i, x) in ledger.installments.enumerated() { try db.run("INSERT INTO installments (id, seq, json) VALUES (?, ?, ?)", [x.id.uuidString, i, js(x)]) }
            for (i, g) in ledger.goals.enumerated() { try db.run("INSERT INTO goals (id, seq, json) VALUES (?, ?, ?)", [g.id.uuidString, i, js(g)]) }
            for (i, x) in ledger.insights.enumerated() { try db.run("INSERT INTO insights (id, seq, json) VALUES (?, ?, ?)", [x.id.uuidString, i, js(x)]) }
            for (i, x) in ledger.subscriptions.enumerated() { try db.run("INSERT INTO subscriptions (id, seq, json) VALUES (?, ?, ?)", [x.id.uuidString, i, js(x)]) }
            for (i, m) in ledger.memories.enumerated() {
                try db.run("INSERT INTO memories (id, seq, kind, title, lines, updated_at, json) VALUES (?, ?, ?, ?, ?, ?, ?)",
                           [m.id.uuidString, i, m.kind.rawValue, m.title, m.notes.count,
                            ISO8601DateFormatter().string(from: m.updatedAt), js(m)])
            }
            for (i, x) in ledger.captures.enumerated() {
                try db.run("INSERT INTO captures (id, seq, status, created_at, text, json) VALUES (?, ?, ?, ?, ?, ?)",
                           [x.id.uuidString, i, x.status.rawValue, ISO8601DateFormatter().string(from: x.createdAt), x.text, js(x)])
            }
            for (i, x) in ledger.paperwork.enumerated() {
                try db.run("INSERT INTO paperwork (id, seq, reimburse, files, json) VALUES (?, ?, ?, ?, ?)",
                           [x.id.uuidString, i, x.reimburse.rawValue, x.attachments.count, js(x)])
            }
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('appliedNotes', ?)", [js(ledger.appliedNotes)])
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('schemaVersion', ?)", [String(ledger.schemaVersion)])
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('lastStatementDate', ?)", [js(ledger.lastStatementDate)])
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('profile', ?)", [js(ledger.profile)])
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('recurring', ?)", [js(ledger.recurring)])
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('currency', ?)", [js(ledger.currency)])
            let committed = try db.storageDigest()
            try db.exec("COMMIT")
            ledger.revision.record(url, digest: committed)
        } catch {
            try? db.exec("ROLLBACK")
            if isWAL {
                try? db.exec("PRAGMA locking_mode = NORMAL")
                _ = try? db.minimumVersion() // 完成释放独占锁，再交给只读连接。
                keepWAL = try? SQLiteDB(url: url, readOnly: true)
                _ = try? keepWAL?.minimumVersion()
            }
            if let sqlite = error as? SQLiteError, sqlite.isBusy { throw LedgerRevision.conflict }
            throw error
        }
    }
}

private struct BusinessUndoIndex: Decodable {
    struct Prior: Codable { let settings: BusinessSettings? }
    let undo: [String: Prior]?
}

/// 账本里某一条读不出来：说清楚是哪张表的第几条、哪个字段，方便修，而不是只说「格式不正确」。
public struct LedgerReadError: Error, LocalizedError {
    public let table: String
    public let row: Int
    public let underlying: Error

    public var errorDescription: String? {
        let names = ["books": "账本", "accounts": "账户", "transactions": "流水", "changes": "改动记录",
                     "debts": "借款", "installments": "分期", "goals": "存钱目标", "insights": "AI 意见", "subscriptions": "订阅", "memories": "夏夏的记忆",
                     "captures": "待记录", "paperwork": "小票发票和报销"]
        var detail = underlying.localizedDescription
        if let e = underlying as? DecodingError {
            switch e {
            case .dataCorrupted(let c): detail = "字段 \(Self.path(c.codingPath)) 的值不认识：\(c.debugDescription)"
            case .keyNotFound(let k, _): detail = "缺少字段 \(k.stringValue)"
            case .typeMismatch(_, let c): detail = "字段 \(Self.path(c.codingPath)) 的类型不对"
            case .valueNotFound(_, let c): detail = "字段 \(Self.path(c.codingPath)) 是空的"
            @unknown default: break
            }
        }
        return "「\(names[table] ?? table)」里第 \(row) 条读不出来（\(detail)）。账本文件没有被改动。"
    }

    private static func path(_ p: [CodingKey]) -> String { p.isEmpty ? "（整条）" : p.map(\.stringValue).joined(separator: ".") }
}

public struct SQLiteError: Error, LocalizedError {
    public let message: String
    var isBusy = false
    public var errorDescription: String? { "账本数据库出错：\(message)" }
}

/// 很薄的一层 SQLite 封装，只够账本用。
final class SQLiteDB {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, readOnly: Bool = false, allowCreate: Bool = true) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | (allowCreate ? SQLITE_OPEN_CREATE : 0)
        guard sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "打不开 \(url.path)"
            sqlite3_close(handle)
            if !allowCreate && !FileManager.default.fileExists(atPath: url.path) { throw LedgerRevision.conflict }
            throw SQLiteError(message: msg)
        }
        sqlite3_busy_timeout(handle, 5000)
        try exec("PRAGMA foreign_keys = OFF")
    }

    deinit { sqlite3_close(handle) }

    static func reader(url: URL) throws -> SQLiteDB {
        // 有回滚日志时允许 SQLite 恢复中断的事务；读取 WAL 不触发 checkpoint。
        let fm = FileManager.default
        let pendingWAL = fm.fileExists(atPath: url.path + "-wal")
        let rollback = fm.fileExists(atPath: url.path + "-journal")
        return try SQLiteDB(url: url, readOnly: pendingWAL && !rollback)
    }

    /// 对即将整体写回的表取一致快照。包含每列的类型、长度、值，能识别
    /// 行数没变的编辑以及没有写 ChangeRecord 的旧版本。
    func storageDigest() throws -> Data? {
        let existing = Set(try query("SELECT name FROM sqlite_master WHERE type='table'"))
        let tables = (["meta"] + SQLiteLedgerStore.tables).filter(existing.contains)
        guard !tables.isEmpty else { return nil }
        var hash = SHA256()
        for table in tables {
            hash.update(data: Data([0xff]))
            hash.update(data: Data(table.utf8))
            let order = table == "meta" ? "key" : "seq, id"
            let stmt = try prepare("SELECT * FROM \(table) ORDER BY \(order)", [])
            defer { sqlite3_finalize(stmt) }
            var rc = sqlite3_step(stmt)
            while rc == SQLITE_ROW {
                hash.update(data: Data([0xfe]))
                for col in 0..<sqlite3_column_count(stmt) {
                    let type = UInt8(sqlite3_column_type(stmt, col))
                    let bytes = sqlite3_column_blob(stmt, col)
                    let count = Int(sqlite3_column_bytes(stmt, col))
                    var length = UInt64(count).bigEndian
                    hash.update(data: Data([type]))
                    withUnsafeBytes(of: &length) { hash.update(bufferPointer: $0) }
                    if let bytes { hash.update(bufferPointer: UnsafeRawBufferPointer(start: bytes, count: count)) }
                }
                rc = sqlite3_step(stmt)
            }
            guard rc == SQLITE_DONE else { throw SQLiteError(message: String(cString: sqlite3_errmsg(handle))) }
        }
        return Data(hash.finalize())
    }

    func hasLedger() throws -> Bool {
        try !query("SELECT name FROM sqlite_master WHERE type='table' LIMIT 1").isEmpty
    }

    /// 空事务结束后 SQLite 的独占模式仍持锁，直到连接关闭。
    func holdExclusiveLock() throws {
        try exec("PRAGMA locking_mode = EXCLUSIVE")
        try exec("BEGIN EXCLUSIVE")
        try exec("COMMIT")
    }

    func copyDatabase(to destination: SQLiteDB) throws {
        guard let backup = sqlite3_backup_init(destination.handle, "main", handle, "main") else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(destination.handle)))
        }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE, finish == SQLITE_OK else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(destination.handle)))
        }
    }

    func writeSnapshot(to destination: URL) throws {
        try run("VACUUM INTO ?", [destination.path])
    }

    func minimumVersion() throws -> Int {
        guard !(try query("SELECT name FROM sqlite_master WHERE name='meta'")).isEmpty,
              let raw = try query("SELECT value FROM meta WHERE key='minReaderVersion'").first else { return 1 }
        guard let version = Int(raw) else { throw BusinessError(message: "账本的格式版本无效") }
        return version
    }

    func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS receivables (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS books (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS transactions (
                id TEXT PRIMARY KEY, seq INTEGER NOT NULL, date TEXT NOT NULL, amount_cents INTEGER NOT NULL,
                account_id TEXT NOT NULL, book_id TEXT, category TEXT, flow TEXT, description TEXT NOT NULL, json TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS transactions_date ON transactions (date);
            CREATE TABLE IF NOT EXISTS changes (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, author TEXT NOT NULL, summary TEXT NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS debts (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS installments (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS goals (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS insights (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS subscriptions (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY, seq INTEGER NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL,
                lines INTEGER NOT NULL, updated_at TEXT NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS captures (
                id TEXT PRIMARY KEY, seq INTEGER NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, text TEXT NOT NULL, json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS paperwork (
                id TEXT PRIMARY KEY, seq INTEGER NOT NULL, reimburse TEXT NOT NULL, files INTEGER NOT NULL, json TEXT NOT NULL);
            """)
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(err)
            let code = sqlite3_errcode(handle)
            throw SQLiteError(message: msg, isBusy: code == SQLITE_BUSY || code == SQLITE_LOCKED)
        }
    }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(handle)))
        }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, Self.transient)
            default: sqlite3_bind_text(stmt, idx, "\(arg!)", -1, Self.transient)
            }
        }
        return stmt
    }

    func run(_ sql: String, _ args: [Any?]) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SQLiteError(message: String(cString: sqlite3_errmsg(handle))) }
    }

    /// 只取第一列文字。
    func query(_ sql: String, _ arguments: [Any?] = []) throws -> [String] {
        let stmt = try prepare(sql, arguments)
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append(sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "")
            } else if rc == SQLITE_DONE {
                return out
            } else {
                throw SQLiteError(message: String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
}
#endif
