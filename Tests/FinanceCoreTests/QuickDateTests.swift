import XCTest
@testable import FinanceCore

final class QuickDateTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    /// 2026 年 11 月 18 日，周三。
    private var today: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))! }

    private func days(_ t: String) -> Int? { QuickDate.extract(t, today: today, calendar: cal)?.daysAgo }

    func testWords() {
        XCTAssertEqual(days("昨天打车 15"), 1)
        XCTAssertEqual(days("前天午饭 12,5"), 2)
        XCTAssertEqual(days("今天咖啡 3"), 0)
        XCTAssertNil(days("咖啡 3,2"))
    }

    func testWeekdays() {
        XCTAssertEqual(days("周一超市 40"), 2, "这周一：两天前")
        XCTAssertEqual(days("周三咖啡 3"), 0)
        XCTAssertEqual(days("周五电影 9"), 5, "这周五还没到：算上一个周五")
        XCTAssertEqual(days("上周五电影 9"), 5)
        XCTAssertEqual(days("上周一房租 600"), 9)
        XCTAssertEqual(days("上星期日买菜 20"), 3)
    }

    func testDayOfMonth() {
        XCTAssertEqual(days("12 号超市 40"), 6)
        XCTAssertEqual(days("18号咖啡 3"), 0)
        XCTAssertEqual(days("25 号房租 600"), 24, "这个月 25 号还没到：算上个月的")
        // 日期那几个字拿掉以后，金额不会认错成 12
        let r = QuickDate.extract("12 号超市 40", today: today, calendar: cal)!
        XCTAssertEqual(QuickPhrase.parse(r.rest)?.amount, Money(parsing: "40"))
    }

    func testLabel() {
        XCTAssertEqual(QuickDate.label(daysAgo: 0, today: today, calendar: cal), "今天")
        XCTAssertEqual(QuickDate.label(daysAgo: 1, today: today, calendar: cal), "昨天")
        XCTAssertEqual(QuickDate.label(daysAgo: 6, today: today, calendar: cal), "11 月 12 日")
    }
}
