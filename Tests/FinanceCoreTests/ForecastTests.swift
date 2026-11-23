import XCTest
@testable import FinanceCore

// 趋势页「照这样花下去，月底和年底剩多少」。测试只用编造的数字。
final class ForecastTests: XCTestCase {
    typealias F = CashForecast.Flow
    func flow(_ income: Int64, _ spent: [String: Int64]) -> F {
        F(income: Money(cents: income), spent: Money(cents: spent.values.reduce(0, +)), byCategory: spent.mapValues { Money(cents: $0) })
    }

    func testMonthEndAndYearEnd() throws {
        // 平时每月进 2.000、花 1.500（房租 700、餐饮 500、购物 300）。今天 11 月 15 日，这个月已经进了 2.000、花了 900。
        let months = [flow(1800_00, ["房租": 700_00, "餐饮": 400_00]), // 最早这个月不算（只看最近 3 个）
                      flow(2000_00, ["房租": 700_00, "餐饮": 500_00, "购物": 300_00]),
                      flow(2000_00, ["房租": 700_00, "餐饮": 500_00, "购物": 300_00]),
                      flow(2000_00, ["房租": 700_00, "餐饮": 500_00, "购物": 300_00])]
        let today = LocalDate(year: 2026, month: 11, day: 15)
        let f = try XCTUnwrap(CashForecast.make(today: today, now: Money(cents: 3000_00),
                                                thisMonth: flow(2000_00, ["房租": 700_00, "餐饮": 200_00]), fullMonths: months,
                                                rising: ["餐饮"]))
        XCTAssertEqual(f.basisMonths, 3)
        XCTAssertEqual(f.monthlyIncome, Money(cents: 2000_00))
        XCTAssertEqual(f.monthlySpend, Money(cents: 1500_00))
        // 本月剩下：工资已经到了不再算；还要花 1.500 − 900 = 600（比照平时速度 15/30 × 1.500 = 750 少，取 750）。
        XCTAssertEqual(f.restIncome, .zero)
        XCTAssertEqual(f.restSpend, Money(cents: 750_00))
        XCTAssertEqual(f.monthEnd, Money(cents: 2250_00))
        // 12 月再存 500。
        XCTAssertEqual(f.yearEnd, Money(cents: 2750_00))
        XCTAssertEqual(f.yearEndDate, LocalDate(year: 2026, month: 12, day: 31))
        XCTAssertFalse(f.isNextYear)
        XCTAssertEqual(f.ahead.map(\.date), [today, LocalDate(year: 2026, month: 11, day: 30), LocalDate(year: 2026, month: 12, day: 31)])
        XCTAssertEqual(f.past.last, CashForecast.Point(date: today, value: Money(cents: 3000_00)))
        // 每月少花 10%：本月剩下少花 75，12 月少花 150。
        XCTAssertEqual(f.thriftyYearEnd, Money(cents: 2975_00))
        // 能少花的：房租是固定开销不算；餐饮最多、还在涨。
        XCTAssertEqual(f.levers.map(\.category), ["餐饮", "购物"])
        XCTAssertTrue(f.levers[0].rising)
        // 到年底还有 0,5 + 1 = 1,5 个月，餐饮少花一半（250）× 1,5 = 375。
        XCTAssertEqual(f.monthsLeft, 1.5, accuracy: 0.001)
        XCTAssertEqual(f.levers[0].halfSaves, Money(cents: 375_00))
    }

    func testOverspendingKeepsNormalPaceAndSalaryStillToCome() throws {
        // 这个月工资还没到，而且已经花超了：剩下的日子照平时速度继续花，工资照常会来。
        let months = [flow(2000_00, ["餐饮": 1000_00])]
        let f = try XCTUnwrap(CashForecast.make(today: LocalDate(year: 2026, month: 6, day: 10), now: Money(cents: 500_00),
                                                thisMonth: flow(0, ["餐饮": 1200_00]), fullMonths: months))
        XCTAssertEqual(f.restIncome, Money(cents: 2000_00))
        XCTAssertEqual(f.restSpend, Money(cents: 666_66))   // 1.000 × 20/30
        XCTAssertEqual(f.monthEnd, Money(cents: 1833_34))
        // 7–12 月每月再存 1.000。
        XCTAssertEqual(f.yearEnd, Money(cents: 7833_34))
        XCTAssertEqual(f.ahead.count, 8)
    }

    func testDecemberLooksAtNextYearAndNoFullMonthsMeansNothing() throws {
        let f = try XCTUnwrap(CashForecast.make(today: LocalDate(year: 2026, month: 12, day: 31), now: Money(cents: 100_00),
                                                thisMonth: F(), fullMonths: [flow(1000_00, ["餐饮": 1100_00])]))
        XCTAssertTrue(f.isNextYear)
        XCTAssertEqual(f.yearEndDate, LocalDate(year: 2027, month: 12, day: 31))
        // 12 月最后一天：本月剩下 0 天，没再花；明年每月亏 100，12 个月后是 −1.100。
        XCTAssertEqual(f.monthEnd, Money(cents: 100_00))
        XCTAssertEqual(f.yearEnd, Money(cents: -1100_00))
        XCTAssertNil(CashForecast.make(today: LocalDate(year: 2026, month: 3, day: 3), now: .zero, thisMonth: F(), fullMonths: [F()]))
    }

    func testNudgesSayYearEndAndBiggestLever() throws {
        let months = Array(repeating: flow(2000_00, ["餐饮": 900_00, "房租": 700_00]), count: 3)
        let good = try XCTUnwrap(CashForecast.make(today: LocalDate(year: 2026, month: 9, day: 30), now: Money(cents: 1000_00),
                                                   thisMonth: flow(2000_00, ["餐饮": 900_00, "房租": 700_00]), fullMonths: months, rising: ["餐饮"]))
        let a = Nudges.forecast(good, currency: "EUR")
        XCTAssertEqual(a.map(\.key), ["forecast-year", "forecast-lever-餐饮"])
        XCTAssertEqual(a[0].kind, .praise)
        // 10–12 月每月存 400：年底 2.200。
        XCTAssertTrue(a[0].title.contains("年底能剩 2.200 €") && a[0].title.contains("多 1.200 €"), a[0].title)
        XCTAssertTrue(a[1].title.contains("还在涨"), a[1].title)
        XCTAssertTrue(a[1].advice.contains("多剩 1.350 €"), a[1].advice)

        let bad = try XCTUnwrap(CashForecast.make(today: LocalDate(year: 2026, month: 9, day: 15), now: Money(cents: 100_00),
                                                  thisMonth: F(), fullMonths: Array(repeating: flow(1000_00, ["餐饮": 1500_00]), count: 3)))
        let b = Nudges.forecast(bad, currency: "EUR")
        XCTAssertEqual(b.first?.kind, .unusual)
        XCTAssertTrue(b[0].title.contains("钱会不够，还差 1.900 €"), b[0].title)
        XCTAssertEqual(b.last?.key, "forecast-month")
    }

    func testFlowsCountOnlyPersonalBooksWhenThereIsAShop() {
        let books = [Book(id: "me", name: "个人"), Book(id: "shop", name: "小店", kind: .business)]
        let d = LocalDate(year: 2026, month: 10, day: 5)
        let txs = [
            Transaction(date: d, amount: Money(cents: 1500_00), description: "工资", accountID: "bank", bookID: "me", category: "工资"),
            Transaction(date: d, amount: Money(cents: -300_00), description: "超市", accountID: "bank", bookID: "me", category: "餐饮"),
            Transaction(date: d, amount: Money(cents: 2000_00), description: "店里收入", accountID: "till", bookID: "shop", category: "营业收入"),
            Transaction(date: d, amount: Money(cents: -400_00), description: "进货", accountID: "till", bookID: "shop", category: "进货"),
        ]
        let ym = YearMonth(year: 2026, month: 10)
        let f = CashForecast.flows(txs, books: books, months: [ym])[ym]
        XCTAssertEqual(f?.income, Money(cents: 1500_00))
        XCTAssertEqual(f?.spent, Money(cents: 300_00))
        XCTAssertEqual(f?.byCategory, ["餐饮": Money(cents: 300_00)])
        // 只有个人账本：全部都算。
        let all = CashForecast.flows(txs, books: [Book(id: "me", name: "个人")], months: [ym])[ym]
        XCTAssertEqual(all?.income, Money(cents: 3500_00))
    }
}
