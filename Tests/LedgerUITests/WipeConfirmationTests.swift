import FinanceCore
import XCTest
@testable import LedgerUI

/// 删除数据的确认：点「删除…」时定下范围，最后一步前账本变了就不删（示例账本，全是编的）。
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
}
