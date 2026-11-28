import XCTest
@testable import FinanceCore

/// 按月取数：能选哪些月、过去的月份拿到的是那个月的数。
final class TrialMonthsTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    private func book() -> TrialBook {
        var b = TrialBook(accounts: [.init(emoji: "💳", name: "日常卡", note: "", balance: eur("1500"))], entries: [], upcoming: [],
                          month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
                          journey: Journey(name: "换新电脑", stops: [eur("700")], saved: .zero), monthlyMust: eur("860"))
        b.spendByCategory = [.init(emoji: "🛒", name: "超市", amount: eur("142,19"), lastMonth: eur("162"))]
        b.pastMonths = [
            .init(key: .init(2026, 10), income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("612"),
                  slices: [.init(emoji: "🛒", name: "超市", amount: eur("162"), lastMonth: eur("150")), .init(emoji: "💊", name: "看病", amount: eur("120"), lastMonth: .zero)]),
            .init(key: .init(2026, 8), income: eur("2100"), fixed: eur("892"), forGoals: .zero, spent: eur("700")),
        ]
        return b
    }

    func testWhichMonthsCanBePicked() {
        let b = book()
        XCTAssertEqual(b.thisMonth, .init(2026, 11))
        XCTAssertEqual(b.months, [.init(2026, 8), .init(2026, 9), .init(2026, 10), .init(2026, 11)], "从最早有数据的月到这个月，一个不漏")
        XCTAssertEqual(b.clampMonth(.init(2026, 12)), .init(2026, 11), "还没到的月份选不了")
        XCTAssertEqual(b.clampMonth(.init(2027, 1)), .init(2026, 11))
        XCTAssertEqual(b.clampMonth(.init(2025, 3)), .init(2026, 8), "比最早的还早也选不了")
        XCTAssertEqual(TrialBook.MonthKey(2026, 1).previous, .init(2025, 12))
        XCTAssertEqual(TrialBook.MonthKey(2025, 12).next, .init(2026, 1))
        XCTAssertEqual(TrialBook.MonthKey(2026, 10).label(thisYear: 2026), "10 月")
        XCTAssertEqual(TrialBook.MonthKey(2025, 12).label(thisYear: 2026), "2025 年 12 月")
    }

    func testEachMonthHasItsOwnNumbers() {
        let b = book()
        let now = b.monthData(b.thisMonth)
        XCTAssertEqual(now.spentTotal, b.month.spentTotal)
        XCTAssertEqual(now.left, b.month.left, "这个月的是账本里现算的")
        XCTAssertEqual(now.slices, b.spendByCategory)
        let oct = b.monthData(.init(2026, 10))
        XCTAssertEqual(oct.spentTotal, eur("1504"))
        XCTAssertEqual(oct.left, eur("636"), "2.340 − 892 − 200 − 612")
        XCTAssertEqual(oct.topSlices().map(\.name), ["超市", "看病"])
        XCTAssertEqual(oct.sliceTotal, eur("282"))
        let sep = b.monthData(.init(2026, 9))
        XCTAssertEqual(sep.spentTotal, .zero, "中间没数据的月份全是 0，不会拿别的月的数顶上")
        XCTAssertEqual(b.monthData(.init(2027, 5)), now, "还没到的月份：给这个月的")
    }

    func testChangingThisMonthDoesNotTouchPastMonths() throws {
        var b = book()
        let oct = b.monthData(.init(2026, 10))
        try b.record(name: "午饭", emoji: "🍜", amount: eur("12"), account: "日常卡")
        XCTAssertEqual(b.monthData(.init(2026, 10)), oct)
        XCTAssertEqual(b.monthData(b.thisMonth).spent, eur("283,39"))
    }

    /// 检查报告第 16 条：数据页、账本页的笔数是同一份；改动记录页「自己进来 + 手记」不超过总数。
    func testEntryCountsAgreeEverywhere() throws {
        var b = TrialBook.demo
        XCTAssertEqual(b.counts.entries, b.entryCounts.life + b.entryCounts.shop)
        let before = b.counts.entries, hand = b.entrySources.hand
        let pay = b.accounts(for: .pay, side: .life).first!.name
        try b.record(name: "咖啡", emoji: "☕", amount: Money(cents: 3_20), account: pay)
        XCTAssertEqual(b.counts.entries, before + 1)
        XCTAssertEqual(b.entrySources.hand, hand + 1, "手记的多一笔")
        XCTAssertLessThanOrEqual(b.entrySources.auto + b.entrySources.hand, b.counts.entries)
    }

    /// 趋势页的折线：累计到今天 = 这个月一共花掉；记一笔，线的末端跟着涨；每天只增不减。
    func testSpendPaceFollowsTheBook() throws {
        var b = TrialBook.demo
        let p = b.spendPace
        XCTAssertEqual(p.soFar.count, b.todayDay)
        XCTAssertEqual(p.soFar.last, b.month.spentTotal)
        XCTAssertTrue(zip(p.soFar, p.soFar.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertEqual(p.last.last, b.previousMonthData?.spentTotal)
        XCTAssertEqual(p.weeks.reduce(.zero, +), b.month.spent, "每周平时花的加起来 = 这个月平时花的")
        let pay = b.accounts(for: .pay, side: .life).first!.name
        try b.record(name: "咖啡", emoji: "☕", amount: Money(cents: 3_20), account: pay)
        XCTAssertEqual(b.spendPace.soFar.last, p.soFar.last! + Money(cents: 3_20))
        XCTAssertEqual(b.spendPace.soFar.last, b.month.spentTotal)
    }
}
