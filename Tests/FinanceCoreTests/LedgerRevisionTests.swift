import Foundation
import XCTest
@testable import FinanceCore

final class LedgerRevisionTests: XCTestCase {
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func entry(_ description: String) -> Transaction {
        Transaction(date: LocalDate("2026-10-10")!, amount: .init(cents: 125),
                    description: description, accountID: "test", bookID: "personal")
    }

    private func checkSeparateCopies(_ store: any LedgerStore, url: URL) throws {
        var window = try store.load()
        window.accounts = [Account(id: "test", name: "模拟现金", kind: .cash)]
        try store.save(window)
        let firstRead = try store.load()
        var winner = firstRead, sibling = firstRead, separate = try store.load()
        winner.accounts[0].name = "同一行的新名字"
        try store.save(winner)
        let bytes = try Data(contentsOf: url)
        for stale in [sibling, separate] {
            var edit = stale
            edit.accounts[0].name = "旧副本的改名"
            XCTAssertThrowsError(try store.save(edit)) { XCTAssertEqual($0.localizedDescription, "账本刚被别处改过，请再试一次") }
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        sibling = winner
        separate = winner
        try sibling.addTransaction(entry("第二次保存"), author: "测试")
        try store.save(sibling)
        XCTAssertThrowsError(try store.save(separate))
        try sibling.addTransaction(entry("第三次保存"), author: "测试")
        try store.save(sibling)
        let result = try store.load()
        XCTAssertEqual(result.accounts[0].name, "同一行的新名字")
        XCTAssertEqual(result.transactions.map(\.description), ["第二次保存", "第三次保存"])
    }

    func testSQLiteForkedCopiesAndConsecutiveSaves() throws {
        try withFolder { dir in
            let url = dir.appendingPathComponent("ledger.sqlite")
            try checkSeparateCopies(SQLiteLedgerStore(url: url), url: url)
        }
    }

    func testJSONForkedCopiesAndConsecutiveSaves() throws {
        try withFolder { dir in
            let url = dir.appendingPathComponent("ledger.json")
            try checkSeparateCopies(JSONFileLedgerStore(url: url), url: url)
        }
    }

    func testWipeAndRestoreRejectStaleTarget() throws {
        try withFolder { dir in
            let url = dir.appendingPathComponent("ledger.sqlite")
            let store = SQLiteLedgerStore(url: url)
            var initial = try store.load()
            initial.transactions = [entry("原始流水")]
            try store.save(initial)
            let backup = try XCTUnwrap(LedgerBackup.make(of: url, label: "测试"))
            var wipe = try store.load(), latest = try store.load()
            let restore = try LedgerBackup.load(backup, replacing: wipe)
            try wipe.wipe(.everything, author: "测试")
            latest.transactions.append(entry("恢复操作期间的流水"))
            try store.save(latest)
            XCTAssertThrowsError(try store.save(wipe))
            XCTAssertThrowsError(try store.save(restore))
            XCTAssertEqual(try store.load().transactions, latest.transactions)
            let retry = try LedgerBackup.load(backup, replacing: store.load())
            try store.save(retry)
            XCTAssertEqual(try store.load().transactions, initial.transactions)
        }
    }

    func testPhoneInboxAndFinInterleaveWithoutLosingEitherEntry() throws {
        try withFolder { dir in
            let primary = SQLiteLedgerStore(url: dir.appendingPathComponent("ledger.sqlite"))
            var seed = Ledger.fresh
            seed.accounts = [Account(id: "test", name: "模拟现金", kind: .cash)]
            try primary.save(seed)
            // mac 已读取待入账纸条、尚未保存时，fin 提交另一笔。
            var note = SyncNote(id: "test-phone", device: "iPhone", createdAt: Date(), summary: "手机流水")
            note.transactions = [entry("手机流水")]
            try SyncNotes.write(note, ledgerFolder: dir)
            let finEntry = entry("fin 流水")
            let interleaving = InterleavingStore(primary: primary) {
                var fin = try primary.load()
                try fin.addTransaction(finEntry, author: "fin")
                try primary.save(fin)
            }
            XCTAssertThrowsError(try InboxApplyingStore(primary: interleaving, folder: dir).load())
            XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: dir), 1)
            let staleFin = try primary.load()
            let inbox = InboxApplyingStore(primary: primary, folder: dir)
            let combined = try inbox.load()
            XCTAssertEqual(combined.transactions.map(\.description), ["fin 流水", "手机流水"])
            XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: dir), 0)
            // 反过来，fin 用收纸条之前读到的副本保存也必须被挡住。
            XCTAssertThrowsError(try primary.save(staleFin))
            XCTAssertEqual(try inbox.load().transactions, combined.transactions)
        }
    }
}

private struct InterleavingStore: LedgerStore {
    let primary: SQLiteLedgerStore
    let beforeSave: @Sendable () throws -> Void
    func load() throws -> Ledger { try primary.load() }
    func save(_ ledger: Ledger) throws { try beforeSave(); try primary.save(ledger) }
}

extension LedgerRevisionTests {
    func testPhoneRejectsSecondLocalWindowAndCanAppendAfterReload() throws {
        try withFolder { dir in
            let phone = PhoneSyncStore(folder: dir, cache: dir.appendingPathComponent("cache/phone.sqlite"))
            var first = try phone.load(), second = try phone.load()
            first.transactions.append(entry("手机甲"))
            try phone.save(first)
            second.transactions.append(entry("手机乙"))
            XCTAssertThrowsError(try phone.save(second))
            XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: dir), 1)
            first.transactions.append(entry("手机甲续记"))
            try phone.save(first)
            var retry = try phone.load()
            retry.transactions.append(entry("手机乙"))
            try phone.save(retry)
            XCTAssertEqual(try phone.load().transactions.map(\.description), ["手机甲", "手机甲续记", "手机乙"])
        }
    }
}
