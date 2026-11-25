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

    private func migratedReceiptQueue(includeDeletion: Bool = true, now: @escaping () -> Date = Date.init) throws -> (old: URL, new: URL, store: InboxApplyingStore, ids: [String]) {
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
        var steps = [(empty, captured), (captured, entered)]
        if includeDeletion { steps.append((entered, deleted)) }
        for (before, after) in steps {
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
                                       folder: new, relocatedFrom: old, now: now)
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

    func testThreeDayTimeoutFromFirstSeenBooksWithoutPhotoAndRepairsOnce() throws {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let queue = try migratedReceiptQueue(includeDeletion: false, now: { clock })
        let before = try queue.store.load()
        XCTAssertTrue(before.appliedNotes.isEmpty)
        let stamp = queue.store.changeStamp()
        clock.addTimeInterval(3 * 86400 - 1)
        let reopened = InboxApplyingStore(primary: queue.store.primary, folder: queue.new, relocatedFrom: queue.old, now: { clock })
        XCTAssertTrue(try reopened.load().transactions.isEmpty)
        XCTAssertEqual(stamp, reopened.changeStamp())
        clock.addTimeInterval(1)
        XCTAssertNotEqual(stamp, reopened.changeStamp())
        let booked = try reopened.load()
        XCTAssertEqual(booked.transactions.count, 1)
        XCTAssertEqual(booked.appliedNotes, queue.ids)
        XCTAssertNil(booked.captures.first?.photo)
        XCTAssertEqual(booked.paperwork.first?.attachments, [])
        XCTAssertEqual(booked.missingPhonePhotoCount, 1)
        let activity = try XCTUnwrap(ExternalActivity.between(before, booked, me: "Mac"))
        XCTAssertEqual(activity.missingPhonePhotoCount, 1)
        XCTAssertEqual(try reopened.load().missingPhonePhotoCount, 1)

        let assets = queue.old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("模拟照片".utf8).write(to: assets.appendingPathComponent("receipt.jpg"))
        for _ in 0..<2 {
            let repaired = try reopened.load()
            XCTAssertEqual(repaired.transactions, booked.transactions)
            XCTAssertEqual(repaired.appliedNotes, queue.ids)
            XCTAssertEqual(repaired.captures.first?.photo, "receipt.jpg")
            XCTAssertEqual(repaired.paperwork.first?.attachments.map(\.file), ["receipt.jpg"])
            XCTAssertEqual(repaired.missingPhonePhotoCount, 0)
            XCTAssertEqual(activity.current(in: repaired)?.missingPhonePhotoCount, 0)
            XCTAssertEqual(repaired.changes.map(\.id), booked.changes.map(\.id))
        }
    }

    func testThreeDayTimeoutReleasesDeletionAndLatePhotoDoesNotReviveTransaction() throws {
        var clock = Date()
        let queue = try migratedReceiptQueue(now: { clock })
        XCTAssertTrue(try queue.store.load().appliedNotes.isEmpty)
        clock.addTimeInterval(3 * 86400 + 1)
        let deleted = try queue.store.load()
        XCTAssertEqual(deleted.appliedNotes, queue.ids)
        XCTAssertEqual(deleted.changes.filter { $0.summary.hasPrefix("待记录入账：") }.count, 1)
        XCTAssertTrue(deleted.transactions.isEmpty)
        XCTAssertEqual(deleted.missingPhonePhotoCount, 1)
        let assets = queue.old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("模拟照片".utf8).write(to: assets.appendingPathComponent("receipt.jpg"))
        let repaired = try queue.store.load()
        XCTAssertTrue(repaired.transactions.isEmpty)
        XCTAssertTrue(repaired.paperwork.flatMap(\.attachments).isEmpty)
        XCTAssertEqual(repaired.captures.first?.photo, "receipt.jpg")
        XCTAssertEqual(repaired.missingPhonePhotoCount, 0)
        XCTAssertEqual(repaired.appliedNotes, queue.ids)
    }

    // 模拟前两张纸条连 iCloud 占位文件都还没出现，只有最后一张删除先到。
    private func holdReceiptAndBooking(in old: URL) throws -> [URL] {
        let offline = try folder()
        let files = SyncNotes.files(in: SyncNotes.inbox(old))
        XCTAssertEqual(files.count, 3)
        return try files.dropLast().map { source in
            let held = offline.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: held)
            return held
        }
    }

    func testDeleteArrivesBeforeUnseenBookingAndPhotoSuppressesBookingOnce() throws {
        let queue = try migratedReceiptQueue()
        let held = try holdReceiptAndBooking(in: queue.old)
        let first = try queue.store.load()
        XCTAssertEqual(first.appliedNotes, [queue.ids[2]])
        XCTAssertEqual(first.pendingPhoneDeletes?.count, 1)

        let reopened = InboxApplyingStore(primary: queue.store.primary, folder: queue.new, relocatedFrom: queue.old)
        for file in held {
            try FileManager.default.copyItem(at: file, to: SyncNotes.inbox(queue.old).appendingPathComponent(file.lastPathComponent))
        }
        XCTAssertEqual(try reopened.load().appliedNotes, first.appliedNotes)
        let assets = queue.old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("模拟迟到照片".utf8).write(to: assets.appendingPathComponent("receipt.jpg"))
        for attempt in 0..<2 {
            if attempt == 1 {
                for file in held {
                    try FileManager.default.copyItem(at: file, to: SyncNotes.inbox(queue.old).appendingPathComponent(file.lastPathComponent))
                }
            }
            let result = try reopened.load()
            XCTAssertTrue(result.transactions.isEmpty)
            XCTAssertTrue(result.paperwork.isEmpty)
            XCTAssertNil(result.pendingPhoneDeletes)
            XCTAssertEqual(result.appliedNotes, [queue.ids[2], queue.ids[0], queue.ids[1]])
            XCTAssertEqual(result.changes.filter { $0.summary.contains("晚到的入账") }.count, 1)
        }
        let database = queue.new.appendingPathComponent("ledger.sqlite")
        let cleaned = try Data(contentsOf: database)
        XCTAssertNil(try reopened.load().pendingPhoneDeletes)
        XCTAssertEqual(try Data(contentsOf: database), cleaned)
    }

    func testUnmatchedDeleteAllowsLaterBookingsEvenAfter72Hours() throws {
        var now = Date()
        let queue = try migratedReceiptQueue(now: { now })
        _ = try holdReceiptAndBooking(in: queue.old)
        let tombstones = try XCTUnwrap(queue.store.load().pendingPhoneDeletes)
        for days in [0, 31] {
            now.addTimeInterval(Double(days) * 86400)
            var next = SyncNote(id: "later-\(days)", device: "手机", createdAt: now, summary: "无关流水")
            next.transactions = [row("之后的另一笔")]
            let simulated = try folder()
            try SyncNotes.write(next, ledgerFolder: simulated)
            let file = try XCTUnwrap(SyncNotes.files(in: SyncNotes.inbox(simulated)).first)
            try FileManager.default.copyItem(at: file, to: SyncNotes.inbox(queue.old).appendingPathComponent(file.lastPathComponent))
            let result = try queue.store.load()
            XCTAssertTrue(result.transactions.contains(try XCTUnwrap(next.transactions?.first)))
            XCTAssertEqual(result.pendingPhoneDeletes, days == 0 ? tombstones : nil)
            XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: queue.old), 0)
        }
    }

    private func checkUndoBeforeLateBooking(onPhone: Bool) throws {
        let queue = try migratedReceiptQueue()
        let held = try holdReceiptAndBooking(in: queue.old)
        let removed = try queue.store.load()
        let phone = PhoneSyncStore(folder: queue.new, device: "手机", cache: try folder().appendingPathComponent("cache.sqlite"))
        var restored = onPhone ? try phone.load() : removed
        let change = try XCTUnwrap(removed.changes.first { $0.kind == .remove })
        try restored.undo(changeID: change.id, author: onPhone ? "手机" : "Mac")
        XCTAssertNil(restored.pendingPhoneDeletes)
        if onPhone {
            try phone.save(restored)
        } else {
            try queue.store.save(restored)
        }
        let saved = try queue.store.load()
        XCTAssertNil(saved.pendingPhoneDeletes)
        XCTAssertEqual(saved.transactions.map(\.id), change.transactionIDs)
        XCTAssertTrue(saved.changes.contains { $0.id == change.id && $0.undone })

        let assets = queue.old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("模拟照片".utf8).write(to: assets.appendingPathComponent("receipt.jpg"))
        for file in held {
            try FileManager.default.copyItem(at: file, to: SyncNotes.inbox(queue.old).appendingPathComponent(file.lastPathComponent))
        }
        let final = try queue.store.load()
        XCTAssertEqual(final.transactions, saved.transactions)
        XCTAssertFalse(final.changes.contains { $0.syncConflicts != nil })
        XCTAssertTrue(queue.ids.allSatisfy { final.appliedNotes.contains($0) })
    }

    func testMacUndoRestoresDeletedTransactionBeforeLateBooking() throws {
        try checkUndoBeforeLateBooking(onPhone: false)
    }

    func testPhoneUndoRestoresDeletedTransactionBeforeLateBooking() throws {
        try checkUndoBeforeLateBooking(onPhone: true)
    }

    func testUnmatchedTombstonesExpireAfter30DaysWithoutFurtherWrites() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let queue = try migratedReceiptQueue(now: { now })
        _ = try holdReceiptAndBooking(in: queue.old)
        XCTAssertEqual(try queue.store.load().pendingPhoneDeletes?.count, 1)
        now.addTimeInterval(30 * 86400 - 1)
        let reopened = InboxApplyingStore(primary: queue.store.primary, folder: queue.new, relocatedFrom: queue.old, now: { now })
        XCTAssertEqual(try reopened.load().pendingPhoneDeletes?.count, 1)
        let stamp = reopened.changeStamp()
        now.addTimeInterval(1)
        XCTAssertNotEqual(stamp, reopened.changeStamp())
        let cleaned = try reopened.load()
        XCTAssertNil(cleaned.pendingPhoneDeletes)
        let db = queue.new.appendingPathComponent("ledger.sqlite")
        let bytes = try Data(contentsOf: db)
        for _ in 0..<3 {
            now.addTimeInterval(86400)
            XCTAssertEqual(try reopened.load(), cleaned)
            XCTAssertEqual(try Data(contentsOf: db), bytes)
        }
    }

    func testUndatedTombstonesStartRetentionAtFirstRead() throws {
        let id = UUID(), start = Date(timeIntervalSince1970: 1_800_000_000)
        var value = Ledger.fresh
        value.pendingPhoneDeletes = try JSONDecoder().decode(PhoneDeletionReceipts.self, from: JSONEncoder().encode([id]))
        value.prunePhoneDeletes(at: start)
        let persisted = try JSONEncoder().encode(value)
        value = try JSONDecoder().decode(Ledger.self, from: persisted)
        value.prunePhoneDeletes(at: start.addingTimeInterval(30 * 86400 - 1))
        XCTAssertEqual(value.pendingPhoneDeletes?.received[id.uuidString], .waitingSince(start.timeIntervalSince1970))
        value.prunePhoneDeletes(at: start.addingTimeInterval(30 * 86400))
        XCTAssertNil(value.pendingPhoneDeletes)
    }

    private func writeLegacyNote(_ note: SyncNote, folder: URL) throws {
        var legacy = note
        legacy.originalRows = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inbox = SyncNotes.inbox(folder)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try encoder.encode(legacy).write(to: inbox.appendingPathComponent(legacy.id + ".json"))
    }

    func testLegacyDeleteThenRenameAndAmountEditThenInitialBooking() throws {
        let base = ledger(), dir = try folder()
        let store = InboxApplyingStore(primary: SQLiteLedgerStore(url: dir.appendingPathComponent("ledger.sqlite")), folder: dir)
        var renamed = base, edit = base.transactions[0]
        edit.description = "改过名字"
        try renamed.editTransaction(edit, author: "手机")
        var changed = renamed
        edit.amount = .init(cents: 789)
        try changed.editTransaction(edit, author: "手机")
        var deleted = changed
        try deleted.removeTransactions([edit.id], author: "手机")
        let order = [(changed, deleted), (base, renamed), (renamed, changed), (.fresh, base)]
        for (i, pair) in order.enumerated() {
            let note = try XCTUnwrap(pair.1.syncNote(since: pair.0, device: "旧手机"))
            try writeLegacyNote(note, folder: dir)
            let mac = try store.load()
            XCTAssertTrue(mac.transactions.isEmpty)
            XCTAssertEqual(mac.pendingPhoneDeletes?.count ?? 0, i == 3 ? 0 : 1)
            XCTAssertEqual(mac.changes.filter { $0.summary.contains("晚到的入账") }.count, i == 3 ? 1 : 0)
        }
    }

    private enum QueuedOperation { case rename, amount, split, deletion, undo }

    private func checkRelatedQueue(_ operation: QueuedOperation, legacy: Bool,
                                   timeout: Bool = false, bookingFirst: Bool = false, failSave: Bool = false) throws {
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        let queue = try migratedReceiptQueue(now: { time })
        _ = try holdReceiptAndBooking(in: queue.old)
        let removed = try queue.store.load()
        let deletion = try XCTUnwrap(removed.changes.first { $0.kind == .remove })
        let row = try XCTUnwrap(deletion.previous?.first)
        var base = removed
        base.transactions = [row]
        base.changes = []
        var after = base
        switch operation {
        case .rename, .amount:
            var edit = row
            if operation == .amount { edit.amount = Money(cents: 444) } else { edit.description = "手机改名" }
            try after.editTransaction(edit, author: "手机")
        case .split:
            try after.splitTransaction(row.id, parts: [.init(amount: Money(cents: 100)), .init(amount: Money(cents: 150))], author: "手机")
        case .deletion:
            try after.removeTransactions([row.id], author: "手机")
        case .undo:
            base = removed
            after = removed
            try after.undo(changeID: deletion.id, author: "手机")
        }
        func deliver(_ note: SyncNote) throws {
            let source = try folder()
            if legacy { try writeLegacyNote(note, folder: source) }
            else { try SyncNotes.write(note, ledgerFolder: source) }
            let file = try XCTUnwrap(SyncNotes.files(in: SyncNotes.inbox(source)).first)
            try FileManager.default.copyItem(at: file, to: SyncNotes.inbox(queue.old).appendingPathComponent(file.lastPathComponent))
        }
        let otherID = UUID()
        var independent = SyncNote(id: "other-delete", device: "另一台手机", createdAt: time, summary: "无关删除")
        independent.deletes = ["transactions": [otherID.uuidString]]
        try deliver(independent)
        XCTAssertNotNil(try queue.store.load().pendingPhoneDeletes?.received[otherID.uuidString])
        time.addTimeInterval(29 * 86400)
        if bookingFirst {
            var booking = SyncNote(id: "01", device: "手机", createdAt: time, summary: "入账")
            booking.transactions = [row]
            try deliver(booking)
        }
        var prior = SyncNote(id: "02", device: "手机", createdAt: time, summary: "前一张小票")
        prior.captures = [.init(kind: .photo, text: "模拟照片", photo: "prior.jpg", device: "手机")]
        try deliver(prior)
        var note = try XCTUnwrap(after.syncNote(since: base, device: "手机"))
        note.id = "03"
        try deliver(note)
        let first = try queue.store.load()
        XCTAssertEqual(first.pendingPhoneDeletes?.queued[row.id.uuidString], ["03"])
        XCTAssertFalse(first.appliedNotes.contains("03"))
        let reopened = InboxApplyingStore(primary: queue.store.primary, folder: queue.new, relocatedFrom: queue.old, now: { time })
        time.addTimeInterval(86400)
        let atExpiry = try reopened.load()
        XCTAssertEqual(atExpiry.pendingPhoneDeletes?.queued[row.id.uuidString], ["03"])
        XCTAssertNil(atExpiry.pendingPhoneDeletes?.received[otherID.uuidString])
        if timeout {
            time.addTimeInterval(2 * 86400)
        } else {
            let dir = queue.old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("模拟照片".utf8).write(to: dir.appendingPathComponent("prior.jpg"))
        }
        if failSave {
            let raw = SQLiteLedgerStore(url: queue.new.appendingPathComponent("ledger.sqlite"))
            let failing = InboxApplyingStore(primary: RefuseDeliverySave(raw: raw), folder: queue.new, relocatedFrom: queue.old, now: { time })
            XCTAssertThrowsError(try failing.load())
            XCTAssertFalse(try raw.load().appliedNotes.contains("03"))
            XCTAssertEqual(try raw.load().pendingPhoneDeletes?.queued[row.id.uuidString], ["03"])
        }
        let result = try reopened.load()
        XCTAssertTrue(result.appliedNotes.contains("03"))
        XCTAssertNil(result.pendingPhoneDeletes)
        XCTAssertEqual(result.transactions.contains { $0.id == row.id }, operation == .undo)
        XCTAssertEqual(result.changes.filter { $0.summary.contains("晚到的入账") }.count, bookingFirst ? 1 : 0)
    }

    func testDay29QueuedRenameProtectsDeleteUntilPhotoArrives() throws {
        for legacy in [false, true] { try checkRelatedQueue(.rename, legacy: legacy) }
    }
    func testQueuedAmountProtectsDeleteThroughPhotoTimeout() throws {
        for legacy in [false, true] { try checkRelatedQueue(.amount, legacy: legacy, timeout: true) }
    }
    func testSplitWaitingForRetryKeepsDeletionReceipt() throws {
        for legacy in [false, true] { try checkRelatedQueue(.split, legacy: legacy, failSave: true) }
    }
    func testQueuedDeletionSurvivesDay30() throws {
        for legacy in [false, true] { try checkRelatedQueue(.deletion, legacy: legacy) }
    }
    func testQueuedPhoneUndoSurvivesExpiryAndRestoresOnce() throws {
        for legacy in [false, true] { try checkRelatedQueue(.undo, legacy: legacy, timeout: true) }
    }
    func testMatchedBookingKeepsReceiptUntilQueuedRenameCommits() throws {
        for legacy in [false, true] { try checkRelatedQueue(.rename, legacy: legacy, bookingFirst: true, failSave: true) }
    }

    private func checkBookingWaitingAcrossExpiry(photoOnDay: Int?, undoOnDay30: Bool, temporarilyOffline: Bool = false) throws {
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        let queue = try migratedReceiptQueue(now: { time })
        let held = try holdReceiptAndBooking(in: queue.old)
        let deletion = try XCTUnwrap(queue.store.load().changes.first { $0.kind == .remove })
        let id = try XCTUnwrap(deletion.transactionIDs.first)
        time.addTimeInterval(29 * 86400)
        for file in held {
            try FileManager.default.copyItem(at: file, to: SyncNotes.inbox(queue.old).appendingPathComponent(file.lastPathComponent))
        }
        XCTAssertEqual(try queue.store.load().pendingPhoneDeletes?.received[id.uuidString], .bookingSeen)
        let booking = try XCTUnwrap(held.last)
        let visible = SyncNotes.inbox(queue.old).appendingPathComponent(booking.lastPathComponent)
        let offline = try folder().appendingPathComponent(booking.lastPathComponent)
        if temporarilyOffline { try FileManager.default.moveItem(at: visible, to: offline) }
        let reopened = InboxApplyingStore(primary: queue.store.primary, folder: queue.new, relocatedFrom: queue.old, now: { time })
        time.addTimeInterval(86400)
        var waiting = try reopened.load()
        XCTAssertEqual(waiting.pendingPhoneDeletes?.received[id.uuidString], .bookingSeen)
        XCTAssertEqual(waiting.appliedNotes, [queue.ids[2]])
        if undoOnDay30 {
            try waiting.undo(changeID: deletion.id, author: "Mac")
            try reopened.save(waiting)
        }
        time.addTimeInterval(Double((photoOnDay ?? 32) - 30) * 86400)
        if temporarilyOffline { try FileManager.default.moveItem(at: offline, to: visible) }
        if photoOnDay != nil {
            let assets = queue.old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            try Data("模拟照片".utf8).write(to: assets.appendingPathComponent("receipt.jpg"))
        }
        for _ in 0..<2 {
            let mac = try reopened.load()
            XCTAssertNil(mac.pendingPhoneDeletes)
            XCTAssertEqual(mac.transactions.map(\.id), undoOnDay30 ? [id] : [])
            XCTAssertEqual(mac.appliedNotes, [queue.ids[2], queue.ids[0], queue.ids[1]])
            XCTAssertEqual(mac.changes.filter { $0.summary.contains("晚到的入账") }.count, undoOnDay30 ? 0 : 1)
        }
    }

    func testDay29BookingSurvivesDay30CleanupUntilDay31Photo() throws {
        try checkBookingWaitingAcrossExpiry(photoOnDay: 31, undoOnDay30: false)
    }

    func testObservedBookingTemporarilyOfflineAtExpiryAfterRestart() throws {
        try checkBookingWaitingAcrossExpiry(photoOnDay: 31, undoOnDay30: false, temporarilyOffline: true)
    }

    func testDay29BookingStillSuppressedAt72HourPhotoTimeout() throws {
        try checkBookingWaitingAcrossExpiry(photoOnDay: nil, undoOnDay30: false)
    }

    func testUndoAtDay30WhileBookingWaitsForPhoto() throws {
        try checkBookingWaitingAcrossExpiry(photoOnDay: 31, undoOnDay30: true)
    }

    func testPhoneUndoBookingAndDeletionInAllDeliveryOrders() throws {
        let booked = ledger()
        var deleted = booked
        let deletion = try deleted.removeTransactions([booked.transactions[0].id], author: "手机")
        var undone = deleted
        try undone.undo(changeID: deletion.id, author: "手机")
        let pairs = [(Ledger.fresh, booked), (booked, deleted), (deleted, undone)]
        let notes = try pairs.map { try XCTUnwrap($0.1.syncNote(since: $0.0, device: "手机")) }
        for legacy in [false, true] {
            for order in [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]] {
                var mac = Ledger.fresh
                for i in order {
                    var note = notes[i]
                    if legacy { note.originalRows = nil }
                    mac.apply(note)
                }
                XCTAssertEqual(mac.transactions, booked.transactions, "旧格式 \(legacy)，顺序 \(order)")
                XCTAssertNil(mac.pendingPhoneDeletes)
                XCTAssertEqual(mac.changes.first { $0.id == deletion.id }?.undone, true)
                XCTAssertTrue(mac.changes.allSatisfy { $0.syncConflicts == nil })
            }
        }
    }

    // A 入账、E 改名、D 删除、U 手机撤销、M 在 Mac 上撤销。每个用例只撤销同一笔一次。
    func testBookingEditDeleteAndUndoArrivalOrders() throws {
        let base = ledger(), id = base.transactions[0].id
        var edited = base, tx = base.transactions[0]
        tx.description = "改名后"
        try edited.editTransaction(tx, author: "手机")
        var deleted = edited
        let removal = try deleted.removeTransactions([id], author: "手机")
        var undone = deleted
        try undone.undo(changeID: removal.id, author: "手机")
        let steps = [("A", Ledger.fresh, base), ("E", base, edited), ("D", edited, deleted), ("U", deleted, undone)]
        var notes: [Character: SyncNote] = [:]
        for (operation, before, after) in steps {
            notes[Character(operation)] = try XCTUnwrap(after.syncNote(since: before, device: "手机"))
        }

        for order in ["AED","ADE","EAD","EDA","DAE","DEA"] {
            var cases = [order]
            for i in 0...order.count {
                let index = order.index(order.startIndex, offsetBy: i)
                cases.append(String(order[..<index]) + "U" + String(order[index...]))
                if order[..<index].contains("D") { cases.append(String(order[..<index]) + "M" + String(order[index...])) }
            }
            for sequence in cases {
                for legacy in [false, true] {
                    for hours in [0, 48, 72] {
                        for cross in [false, true] {
                            try checkSequence(sequence, order: order, legacy: legacy, hours: hours, cross: cross,
                                              notes: notes, id: id, removal: removal.id)
                        }
                    }
                }
            }
        }
    }

    private func checkSequence(_ sequence: String, order: String, legacy: Bool, hours: Int, cross: Bool,
                               notes: [Character: SyncNote], id: UUID, removal: UUID) throws {
        let root = try folder(), old = root.appendingPathComponent("旧"), new = root.appendingPathComponent("新")
        let inbox = SyncNotes.inbox(old)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data().write(to: old.appendingPathComponent(LedgerStores.movedMarker))
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        let store = InboxApplyingStore(primary: InMemoryLedgerStore(.fresh), folder: new, relocatedFrom: old, now: { time })
        let afterDelete = sequence.drop { $0 != "D" }.dropFirst()
        let gate = afterDelete.first { $0 != "M" } ?? "D"
        let label = "顺序 \(sequence)，旧格式 \(legacy)，等 \(hours) 小时，跨期 \(cross)"
        func deliver(_ note: SyncNote) throws {
            if legacy { try writeLegacyNote(note, folder: old); return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let ext = (note.originalRows ?? [:]).isEmpty && (note.deletes ?? [:]).isEmpty ? "json" : "sync2"
            try encoder.encode(note).write(to: inbox.appendingPathComponent(note.id).appendingPathExtension(ext))
        }
        for step in sequence {
            if step == "M" {
                var mac = try store.load()
                if mac.transactions.isEmpty {
                    try mac.undo(changeID: removal, author: "Mac")
                    try store.save(mac)
                } else {
                    XCTAssertThrowsError(try mac.undo(changeID: removal, author: "Mac"), label)
                }
                continue
            }
            if step == gate {
                time.addTimeInterval(Double(cross ? (hours == 0 ? 30 : 29) : 1) * 86400)
                if hours > 0 {
                    var prior = SyncNote(id: "000-photo", device: "手机", createdAt: time, summary: "模拟等待")
                    prior.captures = [.init(kind: .photo, text: "测试", photo: "gate.jpg", device: "手机")]
                    try deliver(prior)
                }
            }
            let note = try XCTUnwrap(notes[step])
            try deliver(note)
            if step == gate && hours > 0 {
                XCTAssertFalse(try store.load().appliedNotes.contains(note.id), label)
                time.addTimeInterval(86400)
                XCTAssertFalse(try store.load().appliedNotes.contains(note.id), label)
                time.addTimeInterval(Double(hours - 24) * 3600)
                if hours < 72 {
                    let assets = old.appendingPathComponent(LedgerFiles.attachmentsFolderName)
                    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
                    try Data("模拟照片".utf8).write(to: assets.appendingPathComponent("gate.jpg"))
                }
            }
            XCTAssertTrue(try store.load().appliedNotes.contains(note.id), label)
        }
        let mac = try store.load()
        let keep = sequence.contains("U") || sequence.contains("M") || ["ADE","EAD"].contains(order)
        XCTAssertEqual(mac.transactions.map(\.id), keep ? [id] : [], label)
        if !sequence.contains("U") && ["ADE","EAD"].contains(order) {
            XCTAssertTrue(mac.changes.contains { $0.syncConflicts?.isEmpty == false }, label)
        }
        XCTAssertNil(mac.pendingPhoneDeletes, label)
    }

    func testTwoDeletionsOnlyUndoTheNamedDeletionInAll24Orders() throws {
        let booked = ledger(), id = booked.transactions[0].id
        var first = booked
        let d1 = try first.removeTransactions([id], author: "手机")
        var undone = first
        try undone.undo(changeID: d1.id, author: "手机")
        var second = undone
        let d2 = try second.removeTransactions([id], author: "手机")
        let steps = [(Ledger.fresh, booked), (booked, first), (first, undone), (undone, second)]
        let notes = try steps.map { try XCTUnwrap($0.1.syncNote(since: $0.0, device: "手机")) }
        for legacy in [false, true] {
            for a in notes.indices {
                for b in notes.indices where b != a {
                    for c in notes.indices where c != a && c != b {
                        let d = try XCTUnwrap(notes.indices.first { ![a,b,c].contains($0) })
                        let dir = try folder()
                        let raw = SQLiteLedgerStore(url: dir.appendingPathComponent("ledger.sqlite"))
                        for index in [a,b,c,d] {
                            if legacy { try writeLegacyNote(notes[index], folder: dir) }
                            else { try SyncNotes.write(notes[index], ledgerFolder: dir) }
                            _ = try InboxApplyingStore(primary: raw, folder: dir).load()
                        }
                        let result = try raw.load()
                        let label = "顺序 \([a,b,c,d])，旧格式 \(legacy)"
                        XCTAssertTrue(result.transactions.isEmpty, label)
                        XCTAssertEqual(result.changes.first { $0.id == d1.id }?.undone, true, label)
                        XCTAssertEqual(result.changes.first { $0.id == d2.id }?.undone, false, label)
                        XCTAssertEqual(Set(result.appliedNotes), Set(notes.map(\.id)), label)
                    }
                }
            }
        }
    }

    func testMacUndoClearsOnlyOneOfTwoDeletionReceipts() throws {
        let booked = ledger(), id = booked.transactions[0].id
        var mac = Ledger.fresh
        var deleteIDs: [UUID] = []
        for _ in 0..<2 {
            var phone = booked
            let deletion = try phone.removeTransactions([id], author: "手机")
            deleteIDs.append(deletion.id)
            mac.apply(try XCTUnwrap(phone.syncNote(since: booked, device: "手机")))
        }
        XCTAssertEqual(Set(mac.pendingPhoneDeletes?.deletionIDs[id.uuidString] ?? []), Set(deleteIDs.map(\.uuidString)))
        try mac.undo(changeID: deleteIDs[0], author: "Mac")
        XCTAssertTrue(mac.transactions.isEmpty)
        XCTAssertEqual(mac.pendingPhoneDeletes?.deletionIDs[id.uuidString], [deleteIDs[1].uuidString])
        try mac.undo(changeID: deleteIDs[1], author: "Mac")
        XCTAssertEqual(mac.transactions, booked.transactions)
        XCTAssertNil(mac.pendingPhoneDeletes)
    }

    // cbf9bc6 的 JSONFileLedgerStore 实际保存的模拟账本，包含旧编辑器生成的原始改名记录。
    private func mainRenameFixture() throws -> (Ledger, ChangeRecord) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/cbf9bc6-rename.json")
        let value = try JSONFileLedgerStore(url: url).load()
        let change = try XCTUnwrap(value.changes.last)
        XCTAssertNil(change.resultingTransactions)
        return (value, change)
    }

    func testUndoLastRenameLoadedFromMainLedger() throws {
        var (value, change) = try mainRenameFixture()
        try value.undo(changeID: change.id, author: "Mac")
        XCTAssertEqual(value.transactions.first?.description, "模拟原名")
        XCTAssertEqual(value.transactions.first?.amount.cents, 250)
    }

    func testUndoMainRenameAfterLaterAmountEditPreservesAmount() throws {
        var (value, change) = try mainRenameFixture()
        var edit = try XCTUnwrap(value.transactions.first)
        edit.amount = Money(cents: 789)
        try value.editTransaction(edit, author: "Mac")
        try value.undo(changeID: change.id, author: "Mac")
        XCTAssertEqual(value.transactions.first?.description, "模拟原名")
        XCTAssertEqual(value.transactions.first?.amount.cents, 789)
    }

    func testLegacyAccountUndoChecksOnlyAffectedRows() throws {
        var value = ledger(), account = value.accounts[0]
        account.name = "升级前改名"
        let change = try value.updateAccount(account, author: "Mac")
        value.changes[value.changes.count - 1].planFieldHashes = nil
        try value.addTransaction(row("独立流水"), author: "Mac")
        var conflict = value
        account.institution = "后来改的机构"
        try conflict.updateAccount(account, author: "Mac")
        XCTAssertThrowsError(try conflict.undo(changeID: change.id, author: "Mac"))
        XCTAssertEqual(conflict.accounts.first, account)
        try value.undo(changeID: change.id, author: "Mac")
        XCTAssertEqual(value.accounts.first?.name, "模拟现金")
        XCTAssertEqual(value.transactions.count, 2)
    }

    func testLegacyJSONBookingWithoutSequenceIsApplied() throws {
        let dir = try folder()
        let store = InboxApplyingStore(primary: SQLiteLedgerStore(url: dir.appendingPathComponent("ledger.sqlite")), folder: dir)
        var add = SyncNote(id: "old-add", device: "旧手机", createdAt: Date(), summary: "模拟入账")
        add.transactions = [row("旧手机入账")]
        try writeLegacyNote(add, folder: dir)
        XCTAssertEqual(try store.load().transactions, add.transactions)
        XCTAssertEqual(try SyncNotes.archivedIDs(in: dir), [add.id])
    }

    func testLegacyJSONDeletionWithOriginalInChangeIsApplied() throws {
        let dir = try folder(), base = ledger()
        let store = InboxApplyingStore(primary: SQLiteLedgerStore(url: dir.appendingPathComponent("ledger.sqlite")), folder: dir)
        try store.save(base)
        var removed = base
        try removed.removeTransactions([base.transactions[0].id], author: "旧手机")
        let delete = try XCTUnwrap(removed.syncNote(since: base, device: "旧手机"))
        try writeLegacyNote(delete, folder: dir)
        let saved = try store.load()
        XCTAssertTrue(saved.transactions.isEmpty)
        XCTAssertNil(saved.pendingPhoneDeletes)
        XCTAssertTrue(saved.changes.allSatisfy { $0.syncConflicts == nil })
        XCTAssertEqual(try SyncNotes.archivedIDs(in: dir), [delete.id])
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
