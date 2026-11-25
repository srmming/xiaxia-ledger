import XCTest
@testable import FinanceCore

final class StaleOverwriteTests: XCTestCase {
    private func ledger() -> Ledger {
        var l = Ledger.fresh
        l.accounts = [Account(id: "cash", name: "模拟现金", kind: .cash)]
        l.transactions = [row("原名")]
        return l
    }

    private func row(_ name: String) -> Transaction {
        Transaction(date: LocalDate("2026-10-10")!, amount: .init(cents: 250), description: name,
                    accountID: "cash", bookID: "personal")
    }

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testQueuedPhoneRenamePreservesMacAmountAndReportsSameFieldConflict() throws {
        let base = ledger()
        var handset = base, mac = base
        var edit = base.transactions[0]
        edit.description = "手机的新名字"; edit.note = "手机补充"
        try handset.editTransaction(edit, author: "手机")
        let note = try XCTUnwrap(handset.syncNote(since: base, device: "模拟手机"))
        let dir = try folder()
        try SyncNotes.write(note, ledgerFolder: dir)
        let wire = try XCTUnwrap(SyncNotes.files(in: SyncNotes.inbox(dir)).first.flatMap(SyncNotes.read))
        edit = base.transactions[0]
        edit.amount = .init(cents: 789)
        try mac.editTransaction(edit, author: "Mac")
        var conflict = mac
        XCTAssertTrue(mac.apply(wire))
        XCTAssertEqual(mac.transactions[0].description, "手机的新名字")
        XCTAssertEqual(mac.transactions[0].amount.cents, 789)
        XCTAssertNil(mac.changes.compactMap(\.syncConflicts).first)

        edit.description = "Mac 的新名字"
        try conflict.editTransaction(edit, author: "Mac")
        XCTAssertTrue(conflict.apply(wire))
        XCTAssertEqual(conflict.transactions[0].description, "Mac 的新名字")
        XCTAssertEqual(conflict.transactions[0].amount.cents, 789)
        XCTAssertEqual(conflict.transactions[0].note, "手机补充")
        let item = try XCTUnwrap(conflict.changes.last?.syncConflicts?.first)
        XCTAssertEqual(item.fields, ["description"])
        XCTAssertEqual(item.rowID, edit.id.uuidString)
        let offered = try JSONDecoder().decode(Transaction.self, from: XCTUnwrap(item.phoneValue))
        XCTAssertEqual(offered.description, "手机的新名字")
        XCTAssertFalse(conflict.apply(wire))
    }

    func testPhoneDeleteAndConcurrentMacEditPreserveMacRecord() throws {
        let base = ledger()
        var phone = base, mac = base
        try phone.removeTransactions([base.transactions[0].id], author: "手机")
        let note = try XCTUnwrap(phone.syncNote(since: base, device: "iPhone"))
        mac.transactions[0].amount = .init(cents: 789)
        mac.apply(note)
        XCTAssertEqual(mac.transactions.first?.amount.cents, 789)
        XCTAssertEqual(mac.changes.last?.syncConflicts?.first?.fields, ["删除"])
    }

    func testUndoRenameKeepsNewAmountAndRejectsLaterRename() throws {
        var mac = ledger(), edit = mac.transactions[0]
        edit.description = "第一版"
        let change = try mac.editTransaction(edit, author: "甲")
        edit.amount = .init(cents: 789)
        try mac.editTransaction(edit, author: "乙")
        var other = mac
        try mac.undo(changeID: change.id, author: "甲")
        XCTAssertEqual(mac.transactions[0].description, "原名")
        XCTAssertEqual(mac.transactions[0].amount.cents, 789)
        edit.description = "第二版"
        try other.editTransaction(edit, author: "乙")
        // 即使后来改回相同文字，也不能当成没人改过。
        edit.description = "第一版"
        try other.editTransaction(edit, author: "乙")
        let untouched = other
        XCTAssertThrowsError(try other.undo(changeID: change.id, author: "甲"))
        XCTAssertEqual(other, untouched)
    }

    func testUndoAccountRenameKeepsNewInstitution() throws {
        var l = ledger(), account = l.accounts[0]
        account.name = "新的账户名"
        let renamed = try l.updateAccount(account, author: "甲")
        account.institution = "虚构机构"
        try l.updateAccount(account, author: "乙")
        try l.undo(changeID: renamed.id, author: "甲")
        XCTAssertEqual(l.accounts[0].name, "模拟现金")
        XCTAssertEqual(l.accounts[0].institution, "虚构机构")
    }

    func testUndoAddRejectsChangedRowEvenWithoutAnEditRecord() throws {
        var mac = ledger()
        var added = row("新流水")
        let change = try mac.addTransaction(added, author: "甲")
        added.amount = .init(cents: 789)
        mac.transactions[1] = added
        XCTAssertThrowsError(try mac.undo(changeID: change.id, author: "甲"))
        XCTAssertEqual(mac.transactions[1], added)
    }

    func testRestoreSkipsArchivedNotesAndAcceptsPending() throws {
        let dir = try folder(), file = dir.appendingPathComponent("ledger.sqlite")
        let raw = SQLiteLedgerStore(url: file), mac = InboxApplyingStore(primary: raw, folder: dir)
        var initial = Ledger.fresh
        initial.appliedNotes = ["备份独有"]
        try raw.save(initial)
        let backup = try XCTUnwrap(LedgerBackup.make(of: file, label: "模拟备份"))
        var archived = SyncNote(id: "已收A", device: "iPhone", createdAt: Date(), summary: "旧纸条")
        archived.transactions = [row("旧纸条")]
        try SyncNotes.write(archived, ledgerFolder: dir)
        var live = try mac.load()
        XCTAssertEqual(live.transactions.count, 1)
        live.appliedNotes = ["当前独有"] // 模拟老版本裁掉了较早的凭据；归档文件仍在。
        try raw.save(live)
        var pending = SyncNote(id: "待收B", device: "iPhone", createdAt: Date(), summary: "新纸条")
        pending.transactions = [row("新纸条")]
        try SyncNotes.write(pending, ledgerFolder: dir)
        let restored = try LedgerBackup.load(backup, replacing: live)
        try mac.save(restored)
        XCTAssertTrue(try raw.load().transactions.isEmpty)
        XCTAssertEqual(try mac.load().transactions.map(\.description), ["新纸条"])
        XCTAssertEqual(Set(try mac.load().appliedNotes), ["备份独有", "当前独有", "已收A", "待收B"])
    }

    func testMigrationCollectsNotesCopiesAttachmentsAndRejectsOldPhone() throws {
        let root = try folder(), old = root.appendingPathComponent("旧目录"), new = root.appendingPathComponent("新目录")
        try SQLiteLedgerStore(url: old.appendingPathComponent("ledger.sqlite")).save(.fresh)
        let phone = PhoneSyncStore(folder: old, cache: root.appendingPathComponent("cache/old.sqlite"))
        var edited = try phone.load()
        let bytes = Data("模拟附件".utf8)
        let filename = try LedgerFiles.saveAttachment(bytes, into: old.appendingPathComponent("附件"))
        edited.transactions.append(row("搬家前"))
        _ = edited.addCapture(.init(kind: .photo, text: "模拟", photo: filename, device: "手机"), author: "甲")
        try phone.save(edited)
        XCTAssertTrue(LedgerStores.migrateToContainer(new, from: old))
        let disk = SQLiteLedgerStore(url: new.appendingPathComponent("ledger.sqlite"))
        let moved = try disk.load()
        XCTAssertEqual(moved.transactions.map(\.description), ["搬家前"])
        XCTAssertEqual(moved.captures.first?.photo, filename)
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("附件").appendingPathComponent(filename)), bytes)
        XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: old), 0)
        let newEntry = row("搬家后")
        edited.transactions.append(newEntry)
        XCTAssertThrowsError(try phone.save(edited)) { XCTAssertTrue($0.localizedDescription.contains("重新连接")) }
        XCTAssertThrowsError(try LedgerFiles.saveAttachment(bytes, into: old.appendingPathComponent("附件")))
        let rebound = PhoneSyncStore(folder: new, cache: root.appendingPathComponent("cache/new.sqlite"))
        var latest = try rebound.load()
        latest.transactions.append(newEntry)
        try rebound.save(latest)
        XCTAssertEqual(try InboxApplyingStore(primary: disk, folder: new).load().transactions.map(\.description), ["搬家前", "搬家后"])
    }

    func testMissingAttachmentPreventsSwitchAndMigrationCanRetry() throws {
        let root = try folder(), old = root.appendingPathComponent("旧目录"), new = root.appendingPathComponent("新目录")
        var data = ledger()
        _ = data.addCapture(.init(kind: .photo, text: "模拟", photo: "receipt.jpg", device: "手机"), author: "甲")
        try SQLiteLedgerStore(url: old.appendingPathComponent("ledger.sqlite")).save(data)
        XCTAssertFalse(LedgerStores.migrateToContainer(new, from: old))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.appendingPathComponent(LedgerStores.movedMarker).path))
        let assets = old.appendingPathComponent("附件")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("模拟补到的文件".utf8).write(to: assets.appendingPathComponent("receipt.jpg"))
        XCTAssertTrue(LedgerStores.migrateToContainer(new, from: old))
    }
}

extension StaleOverwriteTests {
    func testConflictingPaymentDeletionPreservesAllPlanReferences() throws {
        var base = ledger()
        let payment = base.transactions[0]
        base.installments = [.init(name: "模拟分期", bookID: "personal", accountID: "cash", total: .init(cents: 500),
                                   count: 2, firstDate: payment.date, paidIDs: [payment.id])]
        base.debts = [.init(counterparty: "模拟借款", direction: .iOweThem, principal: .init(cents: 500),
                            bookID: "personal", startDate: payment.date, repaymentIDs: [payment.id])]
        base.goals = [.init(name: "模拟目标", bookID: "personal", target: .init(cents: 500), contributionIDs: [payment.id])]
        var phone = base
        let deletion = try phone.removeTransactions([payment.id], author: "手机")
        phone.transactions.append(row("另一笔独立流水"))
        let note = try XCTUnwrap(phone.syncNote(since: base, device: "手机"))
        var mac = base
        mac.transactions[0].description = "Mac 改过的名称"
        mac.apply(note)
        XCTAssertEqual(mac.transactions.map(\.description), ["Mac 改过的名称", "另一笔独立流水"])
        XCTAssertEqual(mac.installments, base.installments)
        XCTAssertEqual(mac.debts, base.debts)
        XCTAssertEqual(mac.goals, base.goals)
        XCTAssertFalse(mac.changes.contains { $0.id == deletion.id })
        let conflicts = try XCTUnwrap(mac.changes.last?.syncConflicts)
        XCTAssertEqual(conflicts.count, 1)
        let members = try JSONDecoder().decode([LinkedSyncMember].self, from: XCTUnwrap(conflicts.first?.phoneValue))
        XCTAssertEqual(Set(members.map(\.row.table)), ["transactions", "installments", "debts", "goals"])

        var clean = base
        clean.apply(note)
        XCTAssertEqual(clean.transactions.map(\.description), ["另一笔独立流水"])
        XCTAssertTrue(clean.installments[0].paidIDs.isEmpty && clean.debts[0].repaymentIDs.isEmpty && clean.goals[0].contributionIDs.isEmpty)
    }

    func testConflictingPlanEditDoesNotInsertUnlinkedPayment() throws {
        var base = ledger()
        base.installments = [.init(name: "分期", bookID: "personal", accountID: "cash", total: .init(cents: 800),
                                   count: 3, firstDate: base.transactions[0].date)]
        var phone = base, mac = base
        let a = row("手机还款"), b = row("Mac 还款")
        phone.transactions.append(a); phone.installments[0].paidIDs = [a.id]
        mac.transactions.append(b); mac.installments[0].paidIDs = [b.id]
        mac.apply(try XCTUnwrap(phone.syncNote(since: base, device: "手机")))
        XCTAssertEqual(mac.installments[0].paidIDs, [b.id])
        XCTAssertFalse(mac.transactions.contains(a))
        XCTAssertEqual(mac.changes.last?.syncConflicts?.first?.table, "relatedRecords")
    }

    func testLateNoteWaitsForAttachmentAndArrivesExactlyOnceAfterMigration() throws {
        let root = try folder(), old = root.appendingPathComponent("旧位置"), new = root.appendingPathComponent("新位置")
        try SQLiteLedgerStore(url: old.appendingPathComponent("ledger.sqlite")).save(.fresh)
        XCTAssertTrue(LedgerStores.migrateToContainer(new, from: old))
        let store = LedgerStores.sqlite(new.appendingPathComponent("ledger.sqlite"), relocatedFrom: old)
        var note = SyncNote(id: "late-001", device: "手机", createdAt: Date(), summary: "离线收款")
        note.transactions = [row("晚到的收款")]
        note.captures = [.init(kind: .photo, text: "小票", photo: "late.jpg", device: "手机")]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let inbox = SyncNotes.inbox(old)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let source = inbox.appendingPathComponent("late-001.sync2")
        try encoder.encode(note).write(to: source)
        let stamp = store.changeStamp()
        XCTAssertTrue(try store.load().transactions.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let assets = old.appendingPathComponent("附件")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let bytes = Data("模拟补到的照片".utf8)
        try bytes.write(to: assets.appendingPathComponent("late.jpg"))
        XCTAssertNotEqual(store.changeStamp(), stamp)
        XCTAssertEqual(try store.load().transactions.map(\.description), ["晚到的收款"])
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("附件/late.jpg")), bytes)
        XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: old), 0)
        XCTAssertEqual(SyncNotes.files(in: SyncNotes.done(old)).count, 1)
        try encoder.encode(note).write(to: source)
        XCTAssertFalse(LedgerStores.migrateToContainer(new, from: old)) // 已经搬完，只补收。
        XCTAssertEqual(try store.load().transactions.count, 1)
        XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: old), 0)
        XCTAssertEqual(try store.load().appliedNotes, ["late-001"])
    }

    private func migratedReceiptQueue() throws -> (old: URL, new: URL, store: InboxApplyingStore, ids: [String]) {
        let root = try folder(), old = root.appendingPathComponent("旧目录"), new = root.appendingPathComponent("新目录")
        let offline = root.appendingPathComponent("离线手机")
        var empty = Ledger.fresh
        empty.accounts = [Account(id: "cash", name: "模拟现金", kind: .cash)]
        try SQLiteLedgerStore(url: old.appendingPathComponent("ledger.sqlite")).save(empty)
        XCTAssertTrue(LedgerStores.migrateToContainer(new, from: old))
        var captured = empty
        let receipt = Capture(kind: .photo, text: "模拟小票", photo: "receipt.jpg", device: "手机")
        captured.addCapture(receipt, author: "手机")
        var entered = captured
        let transaction = row("小票入账")
        try entered.resolveCapture(receipt.id, as: transaction, author: "手机")
        var deleted = entered
        try deleted.removeTransactions([transaction.id], author: "手机")
        var ids: [String] = []
        for (before, after) in [(empty, captured), (captured, entered), (entered, deleted)] {
            let time = Date(timeIntervalSince1970: Double(ids.count))
            let note = try XCTUnwrap(after.syncNote(since: before, device: "手机", now: time))
            ids.append(note.id)
            try SyncNotes.write(note, ledgerFolder: offline)
        }
        try FileManager.default.createDirectory(at: SyncNotes.inbox(old), withIntermediateDirectories: true)
        for file in SyncNotes.files(in: SyncNotes.inbox(offline)).reversed() {
            try FileManager.default.copyItem(at: file, to: SyncNotes.inbox(old).appendingPathComponent(file.lastPathComponent))
        }
        let store = InboxApplyingStore(primary: SQLiteLedgerStore(url: new.appendingPathComponent("ledger.sqlite")),
                                       folder: new, relocatedFrom: old)
        return (old, new, store, ids)
    }

    func testLateReceiptPhotoThenBookingAndDeletionArchiveInOrderOnce() throws {
        let queue = try migratedReceiptQueue()
        XCTAssertTrue(try queue.store.load().appliedNotes.isEmpty)
        let assets = queue.old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("模拟照片".utf8).write(to: assets.appendingPathComponent("receipt.jpg"))
        let received = try queue.store.load()
        XCTAssertEqual(queue.store.lastApplied.map(\.id), queue.ids)
        XCTAssertTrue(received.transactions.isEmpty)
        XCTAssertEqual(received.captures.count, 1)
        XCTAssertEqual(received.changes.filter { $0.summary.hasPrefix("待记录入账：") }.count, 1)
        XCTAssertTrue(received.changes.compactMap(\.syncConflicts).isEmpty)
        for folder in [queue.old, queue.new] {
            XCTAssertEqual(try SyncNotes.archivedIDs(in: folder), queue.ids)
            XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: folder), 0)
        }
        XCTAssertEqual(try queue.store.load().appliedNotes, queue.ids)
    }

    func testMissingReceiptPhotoKeepsLaterBookingAndDeletionPending() throws {
        let queue = try migratedReceiptQueue()
        for _ in 0..<2 {
            let pending = try queue.store.load()
            XCTAssertTrue(pending.appliedNotes.isEmpty)
            XCTAssertTrue(pending.captures.isEmpty && pending.transactions.isEmpty)
            XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: queue.old), 3)
            XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: queue.new), 0)
            XCTAssertTrue(try SyncNotes.archivedIDs(in: queue.old).isEmpty)
            XCTAssertTrue(try SyncNotes.archivedIDs(in: queue.new).isEmpty)
        }
    }

    func testMovedMarkerPlaceholderRejectsPhoneAndAttachments() throws {
        let root = try folder(), old = root.appendingPathComponent("旧位置")
        try SQLiteLedgerStore(url: old.appendingPathComponent("ledger.sqlite")).save(.fresh)
        let phone = PhoneSyncStore(folder: old, cache: root.appendingPathComponent("cache/ledger.sqlite"))
        var value = try phone.load()
        value.transactions.append(row("旧绑定"))
        try Data().write(to: old.appendingPathComponent(".\(LedgerStores.movedMarker).icloud"))
        XCTAssertThrowsError(try phone.save(value)) { XCTAssertTrue($0.localizedDescription.contains("重新连接")) }
        XCTAssertThrowsError(try LedgerFiles.saveAttachment(Data(), into: old.appendingPathComponent("附件")))
        XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: old), 0)
    }

    func testScannerRequestsBothJSONAndSync2Placeholders() throws {
        let dir = try folder()
        for name in [".old.json.icloud", ".edit.sync2.icloud", ".other.txt.icloud", "ready.sync2"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }
        var requested: [String] = []
        let ready = SyncNotes.files(in: dir) { requested.append($0.lastPathComponent) }
        XCTAssertEqual(Set(requested), ["old.json", "edit.sync2"])
        XCTAssertEqual(ready.map(\.lastPathComponent), ["ready.sync2"])
    }
}

extension StaleOverwriteTests {
    func testLateNoteRemainsInOldInboxWhenNewStoreCannotCommit() throws {
        let root = try folder(), old = root.appendingPathComponent("旧位置"), new = root.appendingPathComponent("新位置")
        try SQLiteLedgerStore(url: old.appendingPathComponent("ledger.sqlite")).save(.fresh)
        XCTAssertTrue(LedgerStores.migrateToContainer(new, from: old))
        let raw = SQLiteLedgerStore(url: new.appendingPathComponent("ledger.sqlite"))
        var note = SyncNote(id: "late-retry", device: "手机", createdAt: Date(), summary: "晚到")
        note.transactions = [row("重试收款")]
        let inbox = SyncNotes.inbox(old)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(note).write(to: inbox.appendingPathComponent("late-retry.json"))
        let blocked = InboxApplyingStore(primary: RefuseDeliverySave(raw: raw), folder: new, relocatedFrom: old)
        XCTAssertThrowsError(try blocked.load())
        XCTAssertTrue(try raw.load().appliedNotes.isEmpty)
        XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: old), 1)
        let retry = InboxApplyingStore(primary: raw, folder: new, relocatedFrom: old)
        XCTAssertEqual(try retry.load().transactions.map(\.description), ["重试收款"])
        XCTAssertEqual(try retry.load().appliedNotes, ["late-retry"])
        XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: old), 0)
    }
}

private struct RefuseDeliverySave: LedgerStore {
    let raw: SQLiteLedgerStore
    func load() throws -> Ledger { try raw.load() }
    func save(_ ledger: Ledger) throws { throw BusinessError(message: "模拟写入失败") }
}
