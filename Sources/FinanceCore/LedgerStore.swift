import Foundation

/// 存储接口。app 和 CLI 都通过它读写同一份账本。
/// 第一版先用一个 JSON 文件（简单、好查、AI 也读得懂）；正式存储方案（SQLite / iCloud 同步）另定，换实现不改调用方。
public protocol LedgerStore: Sendable {
    func load() throws -> Ledger
    func save(_ ledger: Ledger) throws
}

public struct JSONFileLedgerStore: LedgerStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// 默认位置：~/Library/Application Support/XiaxiaLedger/ledger.json，可用环境变量 XIAXIA_LEDGER_PATH 覆盖。
    public static func defaultStore() -> JSONFileLedgerStore {
        if let override = ProcessInfo.processInfo.environment["XIAXIA_LEDGER_PATH"], !override.isEmpty {
            return JSONFileLedgerStore(url: URL(fileURLWithPath: override))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return JSONFileLedgerStore(url: base.appendingPathComponent("XiaxiaLedger/ledger.json"))
    }

    public func load() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: url.path) else { return .fresh }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ledger = try decoder.decode(Ledger.self, from: data)
        Money.defaultCurrency = ledger.currency.base
        return ledger
    }

    public func save(_ ledger: Ledger) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ledger).write(to: url, options: .atomic)
    }
}

/// 测试和界面预览用。
public final class InMemoryLedgerStore: LedgerStore, @unchecked Sendable {
    private var ledger: Ledger
    private let lock = NSLock()
    public init(_ ledger: Ledger = .starter) { self.ledger = ledger }
    public func load() throws -> Ledger { lock.lock(); defer { lock.unlock() }; return ledger }
    public func save(_ ledger: Ledger) throws { lock.lock(); defer { lock.unlock() }; self.ledger = ledger }
}

/// 选用哪个存储、放在哪。app 和 fin 都从这里拿，保证读同一份账本。
public enum LedgerStores {
    /// iCloud 云盘里的「夏夏账本」文件夹（Mac）。
    public static var iCloudFolder: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/夏夏账本")
    }

    static var appSupportFolder: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("XiaxiaLedger")
    }

    /// 默认账本位置：
    /// - XIAXIA_LEDGER_PATH 指定了就用它（.json 结尾用 JSON 文件，其他用 SQLite）；
    /// - Mac 上开了 iCloud 云盘：~/Library/Mobile Documents/com~apple~CloudDocs/夏夏账本/ledger.sqlite；
    /// - 否则放在 Application Support/XiaxiaLedger/ledger.sqlite（iPhone 版现在也在这里，接 iCloud 时再改）。
    /// 第一次用 SQLite 时，如果旧的 ledger.json 还在，会先把它读进来，下次保存就存进 SQLite。
    public static func defaultStore() -> any LedgerStore {
        if let override = ProcessInfo.processInfo.environment["XIAXIA_LEDGER_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return url.pathExtension.lowercased() == "json" ? JSONFileLedgerStore(url: url) : sqlite(url)
        }
        #if os(macOS)
        let iCloudDrive = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloudDrive.path) {
            return sqlite(iCloudFolder.appendingPathComponent("ledger.sqlite"))
        }
        #endif
        return sqlite(appSupportFolder.appendingPathComponent("ledger.sqlite"))
    }

    static func sqlite(_ url: URL) -> any LedgerStore {
        #if canImport(SQLite3)
        let legacy = JSONFileLedgerStore(url: appSupportFolder.appendingPathComponent("ledger.json"))
        return MigratingStore(primary: SQLiteLedgerStore(url: url), legacy: legacy)
        #else
        return JSONFileLedgerStore(url: url.deletingPathExtension().appendingPathExtension("json"))
        #endif
    }
}

#if canImport(SQLite3)
/// SQLite 文件还没有、但旧的 JSON 账本在：先读 JSON，保存时写进 SQLite。旧文件留着不删，当备份。
public struct MigratingStore: LedgerStore {
    public let primary: SQLiteLedgerStore
    public let legacy: JSONFileLedgerStore

    public init(primary: SQLiteLedgerStore, legacy: JSONFileLedgerStore) { self.primary = primary; self.legacy = legacy }

    public func load() throws -> Ledger {
        if !FileManager.default.fileExists(atPath: primary.url.path), FileManager.default.fileExists(atPath: legacy.url.path) {
            return try legacy.load()
        }
        return try primary.load()
    }

    public func save(_ ledger: Ledger) throws { try primary.save(ledger) }
}
#endif

/// 账本在哪（设置页、fin context 里显示）。
public func ledgerLocation(_ store: any LedgerStore) -> String {
    #if canImport(SQLite3)
    if let s = store as? MigratingStore { return s.primary.url.path }
    if let s = store as? SQLiteLedgerStore { return s.url.path }
    #endif
    if let s = store as? JSONFileLedgerStore { return s.url.path }
    return "示例数据（不会保存）"
}
