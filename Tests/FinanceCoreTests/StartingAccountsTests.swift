import XCTest
@testable import FinanceCore

final class StartingAccountsTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    func testSampleTotals() {
        let s = StartingAccounts.sample
        XCTAssertEqual(s.totals.have, eur("1585"))
        XCTAssertEqual(s.totals.owe, eur("640"))
        XCTAssertEqual(s.totals.net, eur("945"))
    }

    func testSameKindTwiceGetsANumber() throws {
        var s = StartingAccounts.sample
        let a = try s.add(.daily), b = try s.add(.daily)
        XCTAssertEqual(s.rows.first { $0.id == a }?.name, "日常卡 2")
        XCTAssertEqual(s.rows.first { $0.id == b }?.name, "日常卡 3")
    }

    func testDeleteThenAddBackAndUndo() throws {
        var s = StartingAccounts.sample
        let original = s
        let daily = s.rows[0]
        let removed = s.remove(daily.id)
        XCTAssertEqual(removed?.index, 0)
        XCTAssertEqual(s.totals.have, eur("85"))
        // 删掉以后还能再加回来，名字还是「日常卡」
        let again = try s.add(.daily)
        XCTAssertEqual(s.rows.first { $0.id == again }?.name, "日常卡")
        s.remove(again)
        // 撤销：回到原来的位置
        s.restore(removed!.row, at: removed!.index)
        XCTAssertEqual(s, original)
    }

    func testLentCountsAsHaveBorrowedAsOwe() throws {
        var s = StartingAccounts()
        let l = try s.add(.lent), b = try s.add(.borrowed)
        s.setText(l, "120"); s.setText(b, "300")
        XCTAssertEqual(s.totals.have, eur("120"))
        XCTAssertEqual(s.totals.owe, eur("300"))
        XCTAssertEqual(s.rows[0].name, "", "名字留给人填：谁？")
        XCTAssertEqual(s.rows[0].displayName, "别人欠我的")
    }

    func testCustomCanBeEitherSideAndRenamed() throws {
        var s = StartingAccounts()
        let c = try s.add(.custom)
        s.rename(c, to: "BBVA"); s.setText(c, "1.000")
        XCTAssertEqual(s.totals.have, eur("1000"))
        s.setOwes(c, true)
        XCTAssertEqual(s.totals.owe, eur("1000"))
        XCTAssertEqual(s.totals.have, .zero)
        // 别的种类不能这样翻
        let d = try s.add(.daily)
        s.setOwes(d, true)
        XCTAssertEqual(s.rows.first { $0.id == d }?.owes, false)
    }

    func testEmptyAndUnreadable() throws {
        var s = StartingAccounts()
        XCTAssertEqual(s.totals.net, .zero, "全删光：净剩 0")
        let a = try s.add(.cash)
        XCTAssertFalse(s.hasUnreadable, "空着算 0")
        s.setText(a, "abc")
        XCTAssertTrue(s.hasUnreadable)
        XCTAssertEqual(s.totals.have, .zero)
    }

    func testLimit() throws {
        var s = StartingAccounts()
        for _ in 0..<StartingAccounts.limit { try s.add(.cash) }
        XCTAssertThrowsError(try s.add(.cash))
    }
}
