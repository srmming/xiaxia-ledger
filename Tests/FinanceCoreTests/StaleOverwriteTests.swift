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
