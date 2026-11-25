import FinanceCore
import XCTest
@testable import LedgerUI

/// 删除数据的确认：点「删除…」时定下范围，最后一步前账本变了就不删（示例账本，全是编的）。
@MainActor
final class WipeConfirmationTests: XCTestCase {
    private func demo() -> Ledger { DemoData.make(endingOn: LocalDate(year: 2026, month: 11, day: 25)) }

    func testUnchangedLedgerStaysValid() {
        let ledger = demo()
        let book = ledger.books[1].id
        XCTAssertTrue(WipeConfirmation(scope: .book(book), name: "店", ledger: ledger).stillValid(in: ledger))
        XCTAssertTrue(WipeConfirmation(scope: .everything, name: "全部", ledger: ledger).stillValid(in: ledger))
    }

    /// 审查复现的情况：确认框开着时那个账本在别处被删了。原来会变成删全部，现在范围还是那个账本，而且不删。
    func testBookRemovedElsewhereCancels() throws {
        let ledger = demo()
        let book = ledger.books[1].id
        let pending = WipeConfirmation(scope: .book(book), name: "店", ledger: ledger)
        var changed = ledger
        _ = try changed.removeBook(book, moveTo: ledger.books[0].id, author: "测试")
        XCTAssertEqual(pending.scope, .book(book), "范围不能变成全部")
        XCTAssertFalse(pending.stillValid(in: changed))
    }

    /// 两次确认之间别处又记了一笔：要删的数量和给人看的不一样了，也不删。
    func testNewEntryElsewhereCancels() throws {
        let ledger = demo()
        let pending = WipeConfirmation(scope: .everything, name: "全部", ledger: ledger)
        var changed = ledger
        let tx = Transaction(date: LocalDate(year: 2026, month: 11, day: 25), amount: Money(cents: -350), description: "咖啡",
                             accountID: ledger.accounts[0].id, bookID: ledger.books[0].id)
        _ = try changed.addTransaction(tx, author: "测试")
        XCTAssertFalse(pending.stillValid(in: changed))
    }

    /// 审查复现：删掉一笔再记一笔，数量一样，但新记的那笔不能被删。
    func testSwapOneEntryKeepsCountButCancels() throws {
        let ledger = demo()
        let book = ledger.books[0].id
        let pending = WipeConfirmation(scope: .book(book), name: "个人", ledger: ledger)
        var changed = ledger
        let old = try XCTUnwrap(changed.transactions.first { $0.bookID == book })
        _ = try changed.removeTransactions([old.id], author: "测试")
        let tx = Transaction(date: old.date, amount: Money(cents: -999), description: "新记的一笔", accountID: old.accountID, bookID: book)
        _ = try changed.addTransaction(tx, author: "测试")
        XCTAssertEqual(changed.wipeCount(.book(book)), pending.count, "数量故意弄成一样")
        XCTAssertFalse(pending.stillValid(in: changed))
    }

    /// 审查复现：删掉账本再建一个同 ID 同名的，也不算同一份。
    func testRecreatedSameBookCancels() throws {
        let ledger = demo()
        let book = ledger.books[1]
        let pending = WipeConfirmation(scope: .book(book.id), name: "店", ledger: ledger)
        var changed = ledger
        changed.books.removeAll { $0.id == book.id }
        changed.books.append(Book(id: book.id, name: book.name, currency: book.currency, kind: book.kind))
        changed.transactions = changed.transactions.map { var t = $0; if t.bookID == book.id { t.note = "改过" }; return t }
        XCTAssertFalse(pending.stillValid(in: changed))
    }

    /// 审查复现的另一种：别处已经把一笔记到磁盘上了，这个窗口还没刷新就去只删店里的账。
    /// 保存时的校验会拦住，磁盘上那笔还在。
    func testStaleWindowWipeDoesNotLoseEntrySavedElsewhere() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.sqlite")
        try SQLiteLedgerStore(url: url).save(demo())
        let model = LedgerModel(store: SQLiteLedgerStore(url: url))
        let shop = try XCTUnwrap(model.ledger.books.first { $0.isBusiness }).id
        let personal = try XCTUnwrap(model.ledger.books.first { !$0.isBusiness }).id

        // 另一个程序（比如 AI 用 fin）往个人账本记了一笔，已经存盘。
        let other = SQLiteLedgerStore(url: url)
        var elsewhere = try other.load()
        let tx = Transaction(date: LocalDate(year: 2026, month: 11, day: 25), amount: Money(cents: -350), description: "别处记的咖啡",
                             accountID: elsewhere.accounts[0].id, bookID: personal)
        _ = try elsewhere.addTransaction(tx, author: "测试")
        try other.save(elsewhere)

        // 这个窗口还拿着旧账本：确认时的快照对得上，但保存会被拒。
        let pending = WipeConfirmation(scope: .book(shop), name: "店", ledger: model.ledger)
        XCTAssertTrue(pending.stillValid(in: model.ledger))
        XCTAssertThrowsError(try model.wipe(.book(shop)))
        XCTAssertTrue(try SQLiteLedgerStore(url: url).load().transactions.contains { $0.id == tx.id }, "别处记的那笔不能丢")
    }
}
