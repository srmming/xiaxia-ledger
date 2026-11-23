import Foundation
#if os(macOS)
import Security
#endif

/// 存储接口。app 和 CLI 都通过它读写同一份账本。
/// 第一版先用一个 JSON 文件（简单、好查、AI 也读得懂）；正式存储方案（SQLite / iCloud 同步）另定，换实现不改调用方。
public protocol LedgerStore: Sendable {
    func load() throws -> Ledger
    func save(_ ledger: Ledger) throws
    /// 账本文件现在的「指纹」（修改时间 + 大小）。app 隔几秒看一眼，变了才重新读，用来发现 AI 用 fin / MCP 刚写过。
    /// 不在文件里的（内存账本）返回 nil，就不去看。
    func changeStamp() -> String?
}

extension LedgerStore {
    public func changeStamp() -> String? { nil }
}

/// 几个文件的修改时间和大小拼在一起。文件不在就跳过。
func fileStamp(_ urls: [URL]) -> String? {
    let parts = urls.compactMap { url -> String? in
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let t = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let n = (a[.size] as? NSNumber)?.int64Value ?? 0
        return "\(url.lastPathComponent):\(t):\(n)"
    }
    return parts.isEmpty ? nil : parts.joined(separator: "|")
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

    public func changeStamp() -> String? { fileStamp([url]) }
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
    /// app 自己的 iCloud 容器（Mac 和 iPhone 同步用）。正式签名的 app 带着这个容器的权限；
    /// iCloud 云盘里显示成「夏夏账本」文件夹。没签名的开发版、fin 不能直接问系统要容器，但 Mac 上可以按路径读写。
    public static let containerID = "iCloud.com.srmming.xiaxia-ledger"

    /// Mac 上容器在磁盘上的位置：~/Library/Mobile Documents/iCloud~com~srmming~xiaxia-ledger/Documents
    public static var containerDocumentsOnDisk: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents")
            .appendingPathComponent(containerID.replacingOccurrences(of: ".", with: "~"))
            .appendingPathComponent("Documents")
    }

    /// 问系统要 iCloud 容器（只有带 iCloud 权限的正式版 app 能拿到；第一次会建好文件夹）。
    /// 会访问磁盘、可能慢一点，只在启动时调一次。
    public static func ubiquityDocuments() -> URL? {
        #if canImport(Darwin)
        FileManager.default.url(forUbiquityContainerIdentifier: containerID)?.appendingPathComponent("Documents")
        #else
        nil  // Linux 上只为了编译和跑核心测试
        #endif
    }

    /// 这个 app 签名时带没带 iCloud 容器权限。Mac 上没签名的开发版也能从系统拿到容器文件夹，
    /// 但苹果不会同步它（2026-11-22 在 ming 的 Mac 上遇到过：账本被搬进了一个不同步的文件夹），所以要先看权限。
    /// iPhone 上没权限时系统本来就不给容器，这里直接算有。
    public static var hasICloudEntitlement: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-container-identifiers" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains(containerID) == true
        #else
        return true
        #endif
    }

    /// 从旧位置（iCloud 云盘根目录下「夏夏账本」文件夹）搬到 app 的 iCloud 容器：只复制，旧文件留着当备份。
    /// 容器里已经有账本就什么都不做。返回搬了没有。
    @discardableResult
    public static func migrateToContainer(_ container: URL, from old: URL = iCloudFolder) -> Bool {
        let fm = FileManager.default
        let target = container.appendingPathComponent("ledger.sqlite")
        let source = old.appendingPathComponent("ledger.sqlite")
        let marker = old.appendingPathComponent(movedMarker)
        guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: marker.path) else { return false }
        if fm.fileExists(atPath: target.path) {
            // 容器里已经有账本：一般是 iPhone 先开过、建了个空账本。空的就挪开当备份、换成 Mac 上的老账本；
            // 里面已经有流水就不动（可能是另一台 Mac 搬过来的），免得覆盖。
            guard (try? sqlite(target).load().transactions.isEmpty) == true else { return false }
            let aside = container.appendingPathComponent("ledger.sqlite.空账本-\(Int(Date().timeIntervalSince1970))")
            do { try fm.moveItem(at: target, to: aside) } catch { return false }
        }
        do {
            try fm.createDirectory(at: container, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
            try? Data("账本已经搬到 app 的 iCloud 容器（iCloud 云盘里的「夏夏账本」app 文件夹），这里的 ledger.sqlite 是搬家前的备份，不再更新。\n".utf8)
                .write(to: marker)
            return true
        } catch { return false }
    }

    /// 老位置搬完后放的说明文件；有它才说明容器里的账本是从这里搬过去的。
    static let movedMarker = "已搬家-请看这里.txt"

    /// iCloud 云盘里的「夏夏账本」文件夹（Mac，旧位置）。
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
    /// - app 的 iCloud 容器里已经有账本（正式签名版用过）：用它，Mac 和 iPhone 同一份；
    /// - Mac 上开了 iCloud 云盘：~/Library/Mobile Documents/com~apple~CloudDocs/夏夏账本/ledger.sqlite；
    /// - 否则放在 Application Support/XiaxiaLedger/ledger.sqlite（iPhone 版现在也在这里，接 iCloud 时再改）。
    /// 第一次用 SQLite 时，如果旧的 ledger.json 还在，会先把它读进来，下次保存就存进 SQLite。
    public static func defaultStore() -> any LedgerStore {
        if let override = ProcessInfo.processInfo.environment["XIAXIA_LEDGER_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return url.pathExtension.lowercased() == "json" ? JSONFileLedgerStore(url: url) : sqlite(url)
        }
        // 容器里有账本，而且老位置没有账本或已经搬过家，才用容器里的；
        // 否则（比如 iPhone 先建了个空账本、Mac 还没搬）继续用老位置，fin 不会突然读到空账本。
        let container = containerDocumentsOnDisk.appendingPathComponent("ledger.sqlite")
        let fm = FileManager.default
        if fm.fileExists(atPath: container.path),
           !fm.fileExists(atPath: iCloudFolder.appendingPathComponent("ledger.sqlite").path)
            || fm.fileExists(atPath: iCloudFolder.appendingPathComponent(movedMarker).path) {
            return sqlite(container)
        }
        #if os(macOS)
        let iCloudDrive = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloudDrive.path) {
            return sqlite(iCloudFolder.appendingPathComponent("ledger.sqlite"))
        }
        #endif
        return sqlite(appSupportFolder.appendingPathComponent("ledger.sqlite"))
    }

    /// app 启动时用：带 iCloud 权限的正式版先问系统要容器（第一次会建好），把旧账本搬进去，再用容器里的账本。
    /// iPhone 上没有容器（没开 iCloud）时用本机的账本。
    public static func appStore() -> any LedgerStore {
        if ProcessInfo.processInfo.environment["XIAXIA_LEDGER_PATH"]?.isEmpty == false { return defaultStore() }
        if hasICloudEntitlement, let docs = ubiquityDocuments() {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            #if os(macOS)
            migrateToContainer(docs)
            #endif
            let file = docs.appendingPathComponent("ledger.sqlite")
            #if os(iOS)
            // iPhone：账本可能还只是 iCloud 里的占位文件（.ledger.sqlite.icloud）。请系统下载，最多等 15 秒，
            // 免得把还没下载的账本当成空账本、再在上面记账，和 Mac 那份打架。
            let placeholder = docs.appendingPathComponent(".ledger.sqlite.icloud")
            if !FileManager.default.fileExists(atPath: file.path), FileManager.default.fileExists(atPath: placeholder.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: file)
                for _ in 0..<30 where !FileManager.default.fileExists(atPath: file.path) { Thread.sleep(forTimeInterval: 0.5) }
            }
            #endif
            return sqlite(file)
        }
        return defaultStore()
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

    public func changeStamp() -> String? { primary.changeStamp() ?? legacy.changeStamp() }
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
