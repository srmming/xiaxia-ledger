import XCTest
@testable import FinanceCore

/// iPhone 新界面在正式账本上的写法（只用内存里现造的示例账本）。
final class PhoneBridgeTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 28)

    func testShopIncomeOnARecordedDayLandsAndUndoesAsAGroup() throws {
        var live = DemoData.make(endingOn: today)
        let before = LedgerBridge.snapshot(of: live, today: today)
        let acct = try XCTUnwrap(before.accounts.first { $0.side == .biz && $0.kind == .shop }?.name)
        let earnedBefore = before.shopMonth(before.thisMonth).income
        var after = before
        try after.addShopIncome(Money(cents: 500), account: acct, daysAgo: 0)
        let records = try LedgerBridge.apply(before: before, after: after, to: &live, today: today, author: "测试")
        XCTAssertFalse(records.isEmpty)
        let again = LedgerBridge.snapshot(of: live, today: today)
        XCTAssertEqual(again.shopMonth(again.thisMonth).income, earnedBefore + Money(cents: 500))
        for r in records.reversed() { _ = try live.undo(changeID: r.id, author: "测试") }
        let back = LedgerBridge.snapshot(of: live, today: today)
        XCTAssertEqual(back.shopMonth(back.thisMonth).income, earnedBefore)
    }
}
