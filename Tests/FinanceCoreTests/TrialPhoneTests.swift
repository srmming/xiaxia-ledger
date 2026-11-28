import XCTest
@testable import FinanceCore

/// iPhone 界面 v3 的两条规则：生意那边一笔一笔记收进来的钱。数字都是编的。
final class TrialPhoneTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    private func book() -> TrialBook {
        var b = TrialBook(
            accounts: [.init(emoji: "💳", name: "日常卡", note: "", balance: eur("1500")),
                       .init(emoji: "⭐", name: "目标罐", note: "", balance: eur("500"), block: .goal),
                       .init(emoji: "🏪", name: "小店账户", note: "", balance: eur("3000"), kind: .shop, block: .shop),
                       .init(emoji: "💶", name: "店里现金", note: "", balance: eur("200"), kind: .shop, block: .shop)],
            entries: [], upcoming: [],
            month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
            journey: Journey(name: "换新电脑", stops: [eur("700"), eur("1400")], saved: eur("500"), monthlyPlan: eur("200")),
            monthlyMust: eur("860"))
        b.shopDays = (1...30).map { .init(day: $0, cash: .zero, card: .zero, state: $0 > 18 ? .future : .missing) }
        return b
    }

    func testShopIncomeAddsUp() throws {
        var b = book()
        try b.addShopIncome(eur("50"), account: "小店账户", daysAgo: 0)
        try b.addShopIncome(eur("20"), account: "小店账户", daysAgo: 0)
        try b.addShopIncome(eur("15"), account: "店里现金", daysAgo: 0)
        let today = try XCTUnwrap(b.shopDays.first { $0.day == b.todayDay })
        XCTAssertEqual(today.total, eur("85"))
        XCTAssertEqual(b.account("小店账户")?.balance, eur("3070"))
        XCTAssertEqual(b.account("店里现金")?.balance, eur("215"))
        XCTAssertThrowsError(try b.addShopIncome(eur("10"), account: "日常卡", daysAgo: 0), "生活的账户收不了店里的钱")
        XCTAssertThrowsError(try b.addShopIncome(eur("10"), account: "小店账户", daysAgo: 40), "只能记这个月")
    }
}
