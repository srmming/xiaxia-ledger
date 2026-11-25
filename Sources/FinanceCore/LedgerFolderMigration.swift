import Foundation

extension LedgerFiles {
    static func requireActive(_ folder: URL) throws {
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(LedgerStores.movedMarker).path) {
            throw BusinessError(message: "账本已搬家，请在手机上重新连接新的账本文件夹")
        }
    }

    /// 同一台设备上的附件、纸条写入与切换目录互斥。标记也随 iCloud 同步给旧绑定。
    static func withActiveFolder<T>(_ folder: URL, _ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try withLedgerFileLock(at: folder.appendingPathComponent(".账本位置")) {
            try requireActive(folder)
            return try action()
        }
    }

    /// 逐文件核对。重试时沿用相同的文件，同名不同内容则保留两端原件并停止切换。
    static func copyVerifiedTree(from source: URL, to target: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        let properties = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isSymbolicLink != true,
              (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw BusinessError(message: "账本文件夹内有链接，无法确认搬迁内容")
        }
        if source.lastPathComponent.hasSuffix(".icloud") {
            #if canImport(Darwin)
            let filename = String(source.lastPathComponent.dropFirst().dropLast(".icloud".count))
            try? fm.startDownloadingUbiquitousItem(at: source.deletingLastPathComponent().appendingPathComponent(filename))
            #endif
            throw BusinessError(message: "有账本文件尚未下载，等 iCloud 同步后再搬家")
        }
        if properties.isDirectory == true {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                try copyVerifiedTree(from: child, to: target.appendingPathComponent(child.lastPathComponent))
            }
        } else {
            guard properties.isRegularFile == true else { throw BusinessError(message: "无法读取账本附件") }
            if !fm.fileExists(atPath: target.path) { try coordinatedCopy(from: source, to: target) }
            guard fm.contentsEqual(atPath: source.path, andPath: target.path) else {
                throw BusinessError(message: "两处文件内容不同，尚未切换账本位置")
            }
        }
    }
}
