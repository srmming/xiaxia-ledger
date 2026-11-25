import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// 每次读取独立持有的凭据。Ledger 的值副本在第一次修改时分离凭据，
/// 因此 save 可以回写成功版本，又不会把另一份旧副本一起标记为最新。
final class LedgerRevision: @unchecked Sendable, Equatable {
    private let lock = NSLock()
    private var lastFile: URL?
    private var versions: [URL: Data] = [:]

    static func == (_ lhs: LedgerRevision, _ rhs: LedgerRevision) -> Bool { true }
    static var conflict: BusinessError { BusinessError(message: "账本刚被别处改过，请再试一次") }

    func copy() -> LedgerRevision {
        lock.lock(); defer { lock.unlock() }
        let copy = LedgerRevision()
        copy.versions = versions
        copy.lastFile = lastFile
        return copy
    }

    func check(_ url: URL, current: Data?) throws {
        guard expected(at: url) == current else { throw Self.conflict }
    }

    func expected(at url: URL) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return versions[url.standardizedFileURL.resolvingSymlinksInPath()]
    }

    var ledgerFolder: URL? {
        lock.lock(); defer { lock.unlock() }
        return lastFile?.deletingLastPathComponent()
    }

    func record(_ url: URL, digest: Data?) {
        lock.lock(); defer { lock.unlock() }
        let file = url.standardizedFileURL.resolvingSymlinksInPath()
        lastFile = file
        versions[file] = digest
    }
}

extension Ledger {
    mutating func detachRevision() {
        if !isKnownUniquelyReferenced(&revision) { revision = revision.copy() }
    }

    /// 显式替换内容时，由目标快照决定能否写回。
    public func replacingContents(of target: Ledger) -> Ledger {
        var replacement = self
        replacement.revision = target.revision.copy()
        return replacement
    }

    func contentDigest() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return Data(SHA256.hash(data: try encoder.encode(self)))
    }
}

/// 固定的旁文件用于互斥。数据文件可原子替换，锁文件不能随之换 inode。
func withLedgerFileLock<T>(at file: URL, _ body: () throws -> T) throws -> T {
    let path = file.standardizedFileURL.resolvingSymlinksInPath().path + ".lock"
    let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { _ = close(fd) }
    while flock(fd, LOCK_EX) != 0 {
        if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    return try body()
}
