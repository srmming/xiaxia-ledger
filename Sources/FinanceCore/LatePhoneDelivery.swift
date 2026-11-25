import Foundation

/// 旧绑定设备离线时写下的文件可能晚于切换标记到达。新 Mac 的收件入口按原编号补收。
enum LatePhoneDelivery {
    static func stamp(_ old: URL) -> String? {
        let inbox = SyncNotes.inbox(old), done = SyncNotes.done(old)
        let assets = old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
        let pending = SyncNotes.files(in: inbox)
        let referenced = pending.compactMap(SyncNotes.read).flatMap(attachmentNames).filter(validName)
        return fileStamp([inbox, done, assets] + pending + referenced.sorted().map { assets.appendingPathComponent($0) })
    }

    private static func attachmentNames(_ note: SyncNote) -> [String] {
        (note.captures ?? []).compactMap(\.photo) + (note.paperwork ?? []).flatMap { $0.attachments.map(\.file) }
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && (name as NSString).lastPathComponent == name
    }

    struct Batch {
        var ready: [URL] = []
        var waiting: [String: String] = [:] // 设备 → 最早缺件纸条编号
        var unreadable: String? // 无法识别设备时，后续纸条都要等。

        func allows(_ note: SyncNote) -> Bool {
            if let unreadable, note.id >= unreadable { return false }
            if let first = waiting[note.device], note.id >= first { return false }
            return true
        }
    }

    static func stage(from old: URL, to target: URL, applied: Set<String>) throws -> Batch {
        let fm = FileManager.default
        let assets = old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
        let newAssets = target.appendingPathComponent(LedgerFiles.attachmentsFolderName)
        if fm.fileExists(atPath: assets.path) {
            for file in try fm.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil) {
                let name = file.lastPathComponent
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    LedgerFiles.requestDownload(assets.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count))))
                    continue
                }
                guard !name.hasPrefix(".") else { continue }
                let destination = newAssets.appendingPathComponent(name)
                if !fm.fileExists(atPath: destination.path) {
                    try fm.createDirectory(at: newAssets, withIntermediateDirectories: true)
                    try LedgerFiles.copyVerifiedTree(from: file, to: destination)
                }
            }
        }
        let oldInbox = SyncNotes.inbox(old), newInbox = SyncNotes.inbox(target)
        func candidates(in dir: URL) -> [URL] {
            SyncNotes.files(in: dir, includeUndownloaded: true, requestDownload: LedgerFiles.requestDownload)
        }
        let sources = candidates(in: oldInbox) + candidates(in: SyncNotes.done(old)).filter {
            !applied.contains($0.deletingPathExtension().lastPathComponent)
        }
        var batch = Batch()
        for source in sources.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = source.deletingPathExtension().lastPathComponent
            guard let note = SyncNotes.read(source), note.id == id else {
                if applied.contains(id) { continue }
                batch.unreadable = id
                break
            }
            guard batch.allows(note) else { continue }
            let available = attachmentNames(note).allSatisfy { name in
                guard validName(name) else { return false }
                let original = assets.appendingPathComponent(name), copy = newAssets.appendingPathComponent(name)
                return fm.isReadableFile(atPath: original.path) && fm.contentsEqual(atPath: original.path, andPath: copy.path)
            }
            guard available else {
                if !applied.contains(id) { batch.waiting[note.device] = id }
                continue
            }
            let copies = [newInbox, SyncNotes.done(target)].flatMap { dir in
                ["json", "sync2"].map { dir.appendingPathComponent(id).appendingPathExtension($0) }
            }.filter { fm.fileExists(atPath: $0.path) }
            guard copies.allSatisfy({ SyncNotes.read($0) == note }) else {
                throw BusinessError(message: "同编号的手机纸条内容不同，已保留两边原件")
            }
            let fromInbox = source.deletingLastPathComponent() == oldInbox
            if copies.isEmpty || (fromInbox && !copies.contains(where: { $0.deletingLastPathComponent() == newInbox })) {
                try fm.createDirectory(at: newInbox, withIntermediateDirectories: true)
                try LedgerFiles.copyVerifiedTree(from: source, to: newInbox.appendingPathComponent(source.lastPathComponent))
            }
            if fromInbox { batch.ready.append(source) }
        }
        return batch
    }

    static func archive(_ staged: [URL], from old: URL, to target: URL, applied: Set<String>) {
        let verified = staged.filter { file in
            let id = file.deletingPathExtension().lastPathComponent
            guard applied.contains(id), let original = SyncNotes.read(file) else { return false }
            return ["json", "sync2"].contains { ext in
                let archived = SyncNotes.done(target).appendingPathComponent(id).appendingPathExtension(ext)
                return SyncNotes.read(archived) == original
            }
        }
        if !verified.isEmpty { SyncNotes.archive(verified, ledgerFolder: old) }
    }
}
