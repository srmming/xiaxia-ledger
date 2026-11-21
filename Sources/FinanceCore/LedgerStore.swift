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
        guard FileManager.default.fileExists(atPath: url.path) else { return .starter }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Ledger.self, from: data)
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
