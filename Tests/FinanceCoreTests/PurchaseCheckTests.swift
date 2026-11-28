import XCTest
@testable import FinanceCore

final class PurchaseCheckTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    private var book: TrialBook {
        var b = TrialBook(
            accounts: [.init(emoji: "💳", name: "日常卡", note: "", balance: eur("1500")),
                       .init(emoji: "🏦", name: "储蓄", note: "", balance: eur("2400"), block: .emergency),
                       .init(emoji: "⭐", name: "目标罐", note: "", balance: eur("500"), block: .goal),
                       .init(emoji: "💳", name: "信用卡", note: "", balance: eur("640"), kind: .debt, block: .none)],
            entries: [], upcoming: [],
            month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
            journey: Journey(name: "换新电脑", stops: [eur("700"), eur("1400")], saved: eur("500"), monthlyPlan: eur("200")),
            monthlyMust: eur("860"))
        b.usualDailySpend = eur("31")
        return b
    }

    func testThreeNumbers() throws {
        let c = try book.checkPurchase(name: "降噪耳机", price: eur("279"))
        XCTAssertEqual(c.leftAfter, eur("697,61"))
        XCTAssertEqual(c.days, 9)
        XCTAssertEqual(c.weeksLate, 6)
        XCTAssertTrue(c.fitsDaily)
        XCTAssertEqual(c.verdict, .ok)
    }

    func testVerdicts() throws {
        XCTAssertEqual(try book.checkPurchase(name: "手机", price: eur("400")).verdict, .wait, "一下花掉三成以上：先放两天")
        XCTAssertEqual(try book.checkPurchase(name: "相机", price: eur("1200")).verdict, .wait, "这个月随便花的不够")
        XCTAssertEqual(try book.checkPurchase(name: "摩托", price: eur("1800")).verdict, .no, "日常的钱不够付，要动存着的钱")
        XCTAssertThrowsError(try book.checkPurchase(name: "空", price: .zero))
    }

    func testParseWant() {
        let w = PurchaseCheck.parseWant("想买个降噪耳机 279")
        XCTAssertEqual(w?.name, "降噪耳机")
        XCTAssertEqual(w?.price, eur("279"))
        XCTAssertEqual(PurchaseCheck.parseWant("这个值得买吗 95")?.name, "这样东西")
        XCTAssertNil(PurchaseCheck.parseWant("这个值得买吗"))
    }

    func testEmergencySettings() throws {
        var b = book
        XCTAssertEqual(b.emergencyAccounts.map(\.name), ["储蓄"])
        XCTAssertEqual(b.emergencyGoal, eur("2580"))
        try b.setEmergency(accounts: ["日常卡", "储蓄"], months: 6)
        XCTAssertEqual(b.sum(.emergency), eur("3900"))
        XCTAssertEqual(b.emergencyGoal, eur("5160"))
        XCTAssertThrowsError(try b.setEmergency(accounts: ["目标罐"], months: 3), "目标罐不能同时是应急钱")
        XCTAssertThrowsError(try b.setEmergency(accounts: ["信用卡"], months: 3))
        XCTAssertThrowsError(try b.setEmergency(accounts: [], months: 2))
        try b.setEmergency(accounts: [], months: 1)
        XCTAssertTrue(b.emergencyAccounts.isEmpty)
        XCTAssertEqual(b.account("储蓄")?.block, .daily, "不算应急钱的回到日常")
        // 应急钱不算日常能花的：钱都设成应急以后，买东西要动存着的钱
        try b.setEmergency(accounts: ["日常卡", "储蓄"], months: 3)
        XCTAssertEqual(try b.checkPurchase(name: "耳机", price: eur("100")).verdict, .no)
    }
}
