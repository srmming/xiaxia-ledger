import FinanceCore
import Foundation
import XCTest

/// app 发现账本被外面的 AI 改过：找出新改动、算出「Claude 刚记了 N 笔」、一键全部撤销。
final class ActivityTests: XCTestCase {
    func sample() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "银行", kind: .bank)]
        return l
    }

    func tx(_ cents: Int64, _ name: String) -> Transaction {
        Transaction(date: LocalDate(year: 2026, month: 11, day: 3), amount: Money(cents: cents), description: name, accountID: "bank", bookID: "personal")
    }

    func testOwnChangesAreIgnored() throws {
        let old = sample()
        var new = old
        try new.addTransaction(tx(-1000, "咖啡"), author: "我")
        XCTAssertNil(ExternalActivity.between(old, new, me: "我"))
        XCTAssertNil(ExternalActivity.between(old, old, me: "我"))
    }

    func testAIAddsAreCountedAndUndoneTogether() throws {
        let old = sample()
        var new = old
        try new.addTransaction(tx(-1000, "咖啡"), author: "Claude")
        try new.addTransaction(tx(-2500, "超市"), author: "Claude")
        try new.addTransaction(tx(-300, "面包"), author: "我")
        let a = try XCTUnwrap(ExternalActivity.between(old, new, me: "我"))
        XCTAssertEqual(a.headline, "Claude 刚记了 2 笔")
        XCTAssertEqual(a.transactionIDs.count, 2)
        XCTAssertEqual(a.undoableIDs.count, 2)
        for id in a.undoableIDs { try new.undo(changeID: id, author: "我") }
        XCTAssertEqual(new.transactions.map(\.description), ["面包"])
    }

    func testNonTransactionChangeAndMerge() throws {
        let old = sample()
        var mid = old
        try mid.setAim("每个月存下 500 €", author: "Codex")
        let a = try XCTUnwrap(ExternalActivity.between(old, mid, me: "我"))
        XCTAssertTrue(a.headline.hasPrefix("Codex 刚改了账本："))
        XCTAssertTrue(a.transactionIDs.isEmpty)
        var new = mid
        try new.addTransaction(tx(-1000, "咖啡"), author: "Claude")
        let b = try XCTUnwrap(ExternalActivity.between(mid, new, me: "我"))
        let both = a.merged(with: b)
        XCTAssertEqual(both.authors, ["Codex", "Claude"])
        XCTAssertEqual(both.changes.count, 2)
        XCTAssertEqual(both.headline, "Codex、Claude 刚记了 1 笔")
    }

    #if canImport(SQLite3)
    func testFileStampChangesOnSave() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SQLiteLedgerStore(url: dir.appendingPathComponent("l.sqlite"))
        XCTAssertNil(store.changeStamp())
        var l = sample()
        try store.save(l)
        let s1 = try XCTUnwrap(store.changeStamp())
        try l.addTransaction(tx(-1000, "咖啡"), author: "Claude")
        try store.save(l)
        XCTAssertNotEqual(store.changeStamp(), s1)
        XCTAssertNil(InMemoryLedgerStore(l).changeStamp())
        // app 实际用的是外面包了一层的 MigratingStore，指纹要透过去。
        let wrapped = MigratingStore(primary: store, legacy: JSONFileLedgerStore(url: dir.appendingPathComponent("old.json")))
        XCTAssertEqual(wrapped.changeStamp(), store.changeStamp())
    }
    #endif
}
