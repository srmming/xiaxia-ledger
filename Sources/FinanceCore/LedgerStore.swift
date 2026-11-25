import Foundation
import CryptoKit
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
        guard FileManager.default.fileExists(atPath: url.path) else {
            let fresh = Ledger.fresh
            fresh.revision.record(url, digest: nil)
            return fresh
        }
        return try decode(Data(contentsOf: url))
    }

    private func decode(_ data: Data) throws -> Ledger {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ledger = try decoder.decode(Ledger.self, from: data)
        ledger.revision.record(url, digest: Data(SHA256.hash(data: data)))
        Money.defaultCurrency = ledger.currency.base
        return ledger
    }

    public func save(_ ledger: Ledger) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try withLedgerFileLock(at: url) {
            let current = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            let existing = try current.map(decode) ?? .fresh
            try ledger.checkBusinessVersion()
            try existing.checkBusinessVersion()
            for value in [ledger, existing] {
                guard value.business == nil, value.receivables.isEmpty, value.minReaderVersion < 2,
                      !value.changes.contains(where: { $0.before?.changedBusiness == true }) else {
                    throw BusinessError(message: "生意模式需要 SQLite 账本")
                }
            }
            try ledger.revision.check(url, current: existing.revision.expected(at: url))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(ledger)
            try data.write(to: url, options: .atomic)
            ledger.revision.record(url, digest: Data(SHA256.hash(data: data)))
        }
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
        guard old.standardizedFileURL.resolvingSymlinksInPath() != container.standardizedFileURL.resolvingSymlinksInPath() else { return false }
        if LedgerFiles.hasMoved(old) {
            #if canImport(SQLite3)
            if fm.fileExists(atPath: target.path) {
                _ = try? InboxApplyingStore(primary: SQLiteLedgerStore(url: target), folder: container, relocatedFrom: old).load()
            }
            #endif
            return false
        }
        guard fm.fileExists(atPath: source.path) else { return false }
        let pending = container.appendingPathComponent(".搬家待确认")
        #if canImport(SQLite3)
        do {
            return try LedgerFiles.withActiveFolder(old) {
                try LedgerFiles.withActiveFolder(container) {
                    // 先确认所有待收纸条可读；损坏的纸条不能悄悄跳过。
                    for url in SyncNotes.files(in: SyncNotes.inbox(old)) {
                        guard let note = SyncNotes.read(url), note.id == url.deletingPathExtension().lastPathComponent else { return false }
                    }
                    _ = try InboxApplyingStore(primary: SQLiteLedgerStore(url: source), folder: old).load()
                    let from = try SQLiteDB(url: source, allowCreate: false)
                    try from.holdExclusiveLock()
                    guard !LedgerFiles.hasMoved(old), try from.hasLedger() else { return false }
                    let to = try SQLiteDB(url: target)
                    try to.holdExclusiveLock()
                    if try to.hasLedger() {
                        let isFresh = try SQLiteLedgerStore(url: target).read(from: to) == Ledger.fresh
                        if isFresh {
                            let aside = container.appendingPathComponent("ledger.sqlite.空账本-\(UUID().uuidString)")
                            try to.writeSnapshot(to: aside)
                        } else {
                            // 上次数据库复制完成、旧目录的切换标记却未写成：只有目标内容未动才可重试。
                            guard let staged = try? Data(contentsOf: pending), staged == (try to.storageDigest()) else { return false }
                        }
                    }
                    let sourceLedger = try SQLiteLedgerStore(url: source).read(from: from)
                    let unapplied = SyncNotes.unapplied(ledgerFolder: old, ledger: sourceLedger)
                    guard unapplied.isEmpty else { return false }
                    for directory in [LedgerFiles.attachmentsFolderName, SyncNotes.folderName] {
                        try LedgerFiles.copyVerifiedTree(from: old.appendingPathComponent(directory),
                                                         to: container.appendingPathComponent(directory))
                    }
                    let assets = container.appendingPathComponent(LedgerFiles.attachmentsFolderName)
                    let referenced = sourceLedger.captures.compactMap(\.photo) + sourceLedger.paperwork.flatMap { $0.attachments.map(\.file) }
                    let oldAssets = old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
                    guard referenced.allSatisfy({ name in
                        name == (name as NSString).lastPathComponent && !name.isEmpty && name != "." && name != ".."
                        && fm.isReadableFile(atPath: oldAssets.appendingPathComponent(name).path)
                        && fm.contentsEqual(atPath: oldAssets.appendingPathComponent(name).path,
                                            andPath: assets.appendingPathComponent(name).path)
                    }), let digest = try from.storageDigest() else { return false }
                    try digest.write(to: pending, options: .atomic)
                    try from.copyDatabase(to: to)
                    try to.exec("PRAGMA journal_mode = DELETE")
                    guard try to.storageDigest() == digest else { return false }
                    try Data("账本已经搬到 app 的 iCloud 容器（iCloud 云盘里的「夏夏账本」app 文件夹），这里的 ledger.sqlite 是搬家前的备份，不再更新。\n".utf8)
                        .write(to: marker, options: .atomic)
                    try? fm.removeItem(at: pending)
                    return true
                }
            }
        } catch { return false }
        #else
        return false
        #endif
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
            if url.pathExtension.lowercased() == "json" { return JSONFileLedgerStore(url: url) }
            // 显式路径只在同目录查旧 JSON，不能导入其他位置的账本。
            return sqlite(url, legacyURL: url.deletingPathExtension().appendingPathExtension("json"))
        }
        // 容器里有账本，而且老位置没有账本或已经搬过家，才用容器里的；
        // 否则（比如 iPhone 先建了个空账本、Mac 还没搬）继续用老位置，fin 不会突然读到空账本。
        let container = containerDocumentsOnDisk.appendingPathComponent("ledger.sqlite")
        let fm = FileManager.default
        if fm.fileExists(atPath: container.path),
           (!fm.fileExists(atPath: iCloudFolder.appendingPathComponent("ledger.sqlite").path)
                && !fm.fileExists(atPath: iCloudFolder.appendingPathComponent(".ledger.sqlite.icloud").path))
            || LedgerFiles.hasMoved(iCloudFolder) {
            return sqlite(container, relocatedFrom: iCloudFolder)
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
        #if os(iOS)
        // 带 iCloud 权限的 iPhone 版：app 自己的 iCloud 容器里有电脑放的账本，就自动和电脑同步，不用选文件夹（ming 2026-11-25）。
        // 手机照样不直接写账本，改动写成小纸条放在容器里，由电脑收进账本（见 PhoneSync.swift）。
        if let docs = iCloudContainerWithLedger() { return phoneStore(docs) }
        // 老办法：选过 iCloud 云盘里的「夏夏账本」文件夹（电脑还是不带 iCloud 权限的旧版时）。
        if let folder = PhoneFolderLink.resolve() { return phoneStore(folder) }
        // 容器里还没有账本（电脑还没开过新版）：先用手机本机的账本，别在容器里另起一本和电脑打架。
        if ubiquityDocuments() != nil { return defaultStore() }
        #endif
        if hasICloudEntitlement, let docs = ubiquityDocuments() {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            #if os(macOS)
            if !migrateToContainer(docs),
               !LedgerFiles.hasMoved(iCloudFolder),
               ["ledger.sqlite", ".ledger.sqlite.icloud"].contains(where: { FileManager.default.fileExists(atPath: iCloudFolder.appendingPathComponent($0).path) }) {
                return sqlite(iCloudFolder.appendingPathComponent("ledger.sqlite"))
            }
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
            #if os(macOS)
            return sqlite(file, relocatedFrom: iCloudFolder)
            #else
            return sqlite(file)
            #endif
        }
        return defaultStore()
    }

    /// 这个文件夹是不是 app 自己的 iCloud 容器（…/iCloud~com~srmming~xiaxia-ledger/Documents）。
    public static func isAppContainer(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/" + containerID.replacingOccurrences(of: ".", with: "~") + "/")
    }

    #if os(iOS)
    /// iPhone：app 的 iCloud 容器里已经有账本（或者它的 iCloud 占位文件）就返回容器文件夹；
    /// 只有占位文件时请系统下载（不等它，PhoneSyncStore 会先显示上次的副本）。没权限、没开 iCloud、没账本都返回 nil。
    public static func iCloudContainerWithLedger() -> URL? {
        guard let docs = ubiquityDocuments() else { return nil }
        let fm = FileManager.default
        let file = docs.appendingPathComponent("ledger.sqlite")
        let placeholder = docs.appendingPathComponent(".ledger.sqlite.icloud")
        if fm.fileExists(atPath: file.path) { return docs }
        if fm.fileExists(atPath: placeholder.path) {
            try? fm.startDownloadingUbiquitousItem(at: file)
            return docs
        }
        return nil
    }
    #endif

    /// iPhone 接 iCloud 文件夹用的账本；本地副本放在 Application Support。
    public static func phoneStore(_ folder: URL) -> PhoneSyncStore {
        PhoneSyncStore(folder: folder, device: "iPhone", cache: appSupportFolder.appendingPathComponent("iCloud 副本/ledger.sqlite"))
    }

    /// iPhone 本机的账本（没接 iCloud 文件夹时用的那本）。
    public static func localPhoneStore() -> any LedgerStore { sqlite(appSupportFolder.appendingPathComponent("ledger.sqlite")) }

    static func sqlite(_ url: URL, legacyURL: URL? = nil, relocatedFrom: URL? = nil) -> any LedgerStore {
        #if canImport(SQLite3)
        let legacy = JSONFileLedgerStore(url: legacyURL ?? appSupportFolder.appendingPathComponent("ledger.json"))
        // 读账本时顺便收 iPhone 写的小纸条（见 PhoneSync.swift）。
        return InboxApplyingStore(primary: MigratingStore(primary: SQLiteLedgerStore(url: url), legacy: legacy),
                                  folder: url.deletingLastPathComponent(), relocatedFrom: relocatedFrom)
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
        let placeholder = primary.url.deletingLastPathComponent().appendingPathComponent(".\(primary.url.lastPathComponent).icloud")
        if !FileManager.default.fileExists(atPath: primary.url.path), !FileManager.default.fileExists(atPath: placeholder.path),
           FileManager.default.fileExists(atPath: legacy.url.path) {
            return try legacy.load()
        }
        return try primary.load()
    }

    public func save(_ ledger: Ledger) throws {
        guard ledger.revision.expected(at: legacy.url) != nil, ledger.revision.expected(at: primary.url) == nil else {
            return try primary.save(ledger)
        }
        try withLedgerFileLock(at: legacy.url) {
            let current = try legacy.load()
            try ledger.revision.check(legacy.url, current: current.revision.expected(at: legacy.url))
            try primary.save(ledger)
        }
    }

    public func changeStamp() -> String? { primary.changeStamp() ?? legacy.changeStamp() }
}
#endif

/// 账本在哪（设置页、fin context 里显示）。
public func ledgerLocation(_ store: any LedgerStore) -> String {
    if let s = store as? PhoneSyncStore { return "iCloud 云盘 › \(s.folder.lastPathComponent)" }
    if let url = ledgerFileURL(store) { return url.path }
    return "示例数据（不会保存）"
}
