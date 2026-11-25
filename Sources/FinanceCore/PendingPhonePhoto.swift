import Foundation

/// 等待起点独立于纸条生成时间，重开账本也沿用第一次看到它的时刻。
struct PhotoWaitTimes {
    static let limit: TimeInterval = 3 * 24 * 3600
    let folder: URL
    private var url: URL { SyncNotes.done(folder).appendingPathComponent(".照片等待") }

    func read() throws -> [String: Date] {
        do { return try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: url)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [:] }
    }

    func write(_ times: [String: Date]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(times).write(to: url, options: .atomic)
    }

    func expired(at now: Date) -> [String] {
        ((try? read()) ?? [:]).filter { now.timeIntervalSince($0.value) >= Self.limit }.keys.sorted()
    }
}

/// 和提示一起保存待补的引用，保证保存失败时能按原纸条重试。
struct PendingPhonePhoto: Hashable, Codable, Sendable {
    let file: String
    var captureIDs: [UUID] = []
    var attachments: [String: [Attachment]] = [:]

    func available(from old: URL, in target: URL) -> Bool {
        guard LatePhoneDelivery.validName(file) else { return false }
        let relative = LedgerFiles.attachmentsFolderName + "/" + file
        let source = old.appendingPathComponent(relative)
        return FileManager.default.isReadableFile(atPath: source.path) &&
            FileManager.default.contentsEqual(atPath: source.path, andPath: target.appendingPathComponent(relative).path)
    }

    func restoreReferences(in ledger: inout Ledger) {
        for i in ledger.captures.indices where captureIDs.contains(ledger.captures[i].id) && ledger.captures[i].photo == nil {
            ledger.captures[i].photo = file
        }
        let live = Set(ledger.transactions.map(\.id))
        for i in ledger.paperwork.indices where live.contains(ledger.paperwork[i].id) {
            for item in attachments[ledger.paperwork[i].id.uuidString] ?? [] {
                if !ledger.paperwork[i].attachments.contains(where: { $0.id == item.id || $0.file == file }) {
                    ledger.paperwork[i].attachments.append(item)
                }
            }
        }
    }
}

extension Ledger {
    public var missingPhonePhotoCount: Int { Set(changes.compactMap { $0.pendingPhonePhoto?.file }).count }

    mutating func updatePendingPhotos(_ missing: Set<String>, now: Date) {
        for i in changes.indices {
            if let photo = changes[i].pendingPhonePhoto, !missing.contains(photo.file) {
                changes[i].pendingPhonePhoto = nil
            }
        }
        for file in missing.sorted() {
            var photo = PendingPhonePhoto(file: file)
            for i in captures.indices where captures[i].photo == file {
                photo.captureIDs.append(captures[i].id)
                captures[i].photo = nil
            }
            for i in paperwork.indices {
                let refs = paperwork[i].attachments.filter { $0.file == file }
                if !refs.isEmpty {
                    if transactions.contains(where: { $0.id == paperwork[i].id }) {
                        photo.attachments[paperwork[i].id.uuidString] = refs
                    }
                    paperwork[i].attachments.removeAll { $0.file == file }
                }
            }
            let needed = !photo.captureIDs.isEmpty || !photo.attachments.isEmpty
            if let i = changes.firstIndex(where: { $0.pendingPhonePhoto?.file == file }) {
                changes[i].pendingPhonePhoto = needed ? photo : nil
            } else if needed {
                var notice = ChangeRecord(kind: .edit, summary: "照片没到，先记上了", transactionIDs: [], author: "手机同步", createdAt: now)
                notice.pendingPhonePhoto = photo
                changes.append(notice)
            }
        }
    }
}

extension ExternalActivity {
    public var missingPhonePhotoCount: Int { Set(changes.compactMap { $0.pendingPhonePhoto?.file }).count }
}
