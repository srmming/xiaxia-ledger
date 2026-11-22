#if canImport(SQLite3)
import Foundation
import SQLite3

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

    static let tables = ["books", "accounts", "transactions", "changes", "debts", "installments", "goals", "insights"]

    public func load() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: url.path) else { return .fresh }
        let db = try SQLiteDB(url: url)
        try db.migrate()
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        func rows<T: Decodable>(_ table: String, _ type: T.Type) throws -> [T] {
            try db.query("SELECT json FROM \(table) ORDER BY seq").enumerated().map { i, json in
                do { return try dec.decode(T.self, from: Data(json.utf8)) }
                catch { throw LedgerReadError(table: table, row: i + 1, underlying: error) }
            }
        }
        var ledger = Ledger(books: try rows("books", Book.self), accounts: try rows("accounts", Account.self),
                            transactions: try rows("transactions", Transaction.self), changes: try rows("changes", ChangeRecord.self))
        ledger.debts = try rows("debts", Debt.self)
        ledger.installments = try rows("installments", Installment.self)
        ledger.goals = try rows("goals", Goal.self)
        ledger.insights = try rows("insights", Insight.self)
        if let v = try db.query("SELECT value FROM meta WHERE key = 'schemaVersion'").first, let n = Int(v) { ledger.schemaVersion = n }
        if let v = try db.query("SELECT value FROM meta WHERE key = 'lastStatementDate'").first {
            ledger.lastStatementDate = try dec.decode([String: LocalDate].self, from: Data(v.utf8))
        }
        // 夏夏性格、目标、自己加的分类：放在 meta 里（旧版本不认识这个键，会原样留着）。
        if let v = try db.query("SELECT value FROM meta WHERE key = 'profile'").first {
            ledger.profile = (try? dec.decode(Profile.self, from: Data(v.utf8))) ?? Profile()
        }
        return ledger
    }

    public func save(_ ledger: Ledger) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try SQLiteDB(url: url)
        try db.migrate()
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        func js<T: Encodable>(_ v: T) throws -> String { String(decoding: try enc.encode(v), as: UTF8.self) }

        try db.exec("BEGIN IMMEDIATE")
        do {
            for t in Self.tables { try db.exec("DELETE FROM \(t)") }
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
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('schemaVersion', ?)", [String(ledger.schemaVersion)])
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('lastStatementDate', ?)", [js(ledger.lastStatementDate)])
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('profile', ?)", [js(ledger.profile)])
            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }
}

/// 账本里某一条读不出来：说清楚是哪张表的第几条、哪个字段，方便修，而不是只说「格式不正确」。
public struct LedgerReadError: Error, LocalizedError {
    public let table: String
    public let row: Int
    public let underlying: Error

    public var errorDescription: String? {
        let names = ["books": "账本", "accounts": "账户", "transactions": "流水", "changes": "改动记录",
                     "debts": "借款", "installments": "分期", "goals": "存钱目标", "insights": "AI 意见"]
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
    public var errorDescription: String? { "账本数据库出错：\(message)" }
}

/// 很薄的一层 SQLite 封装，只够账本用。
final class SQLiteDB {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "打不开 \(url.path)"
            sqlite3_close(handle)
            throw SQLiteError(message: msg)
        }
        sqlite3_busy_timeout(handle, 5000)
        try exec("PRAGMA journal_mode = DELETE")
        try exec("PRAGMA foreign_keys = OFF")
    }

    deinit { sqlite3_close(handle) }

    func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
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
            """)
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(err)
            throw SQLiteError(message: msg)
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
    func query(_ sql: String) throws -> [String] {
        let stmt = try prepare(sql, [])
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
