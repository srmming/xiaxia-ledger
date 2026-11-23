import XCTest
@testable import FinanceCore

// 趋势页和家底页的算法。测试只用编造的数字。
final class TrendsTests: XCTestCase {
    func month(_ m: Int, income: Int64, _ spend: [String: Int64]) -> MonthlySummary {
        var by: [String: Money] = [:]
        for (k, v) in spend { by[k] = Money(cents: -v) }
        return MonthlySummary(month: YearMonth(year: 2026, month: m), bookID: nil, income: Money(cents: income),
                              expense: Money(cents: -spend.values.reduce(0, +)), byCategory: by)
    }

    func testCreepingFindsCategoriesRisingSeveralMonths() {
        let months = [
            month(6, income: 2000_00, ["餐饮": 200_00, "购物": 90_00, "房租": 700_00, "娱乐": 30_00]),
            month(7, income: 2000_00, ["餐饮": 180_00, "购物": 60_00, "房租": 720_00, "娱乐": 32_00]),
            month(8, income: 2000_00, ["餐饮": 210_00, "购物": 80_00, "房租": 740_00, "娱乐": 34_00]),
            month(9, income: 2000_00, ["餐饮": 240_00, "购物": 70_00, "房租": 760_00, "娱乐": 36_00]),
            month(10, income: 2000_00, ["餐饮": 260_00, "购物": 120_00, "房租": 780_00, "娱乐": 38_00]),
        ]
        let out = Trends.creeping(months)
        // 餐饮从 7 月的 180 连涨 3 个月到 260；购物只涨了最近 1 个月；房租是固定开销不算；娱乐每次只涨 2 € 不算。
        XCTAssertEqual(out.map(\.category), ["餐饮"])
        XCTAssertEqual(out[0].months, 3)
        XCTAssertEqual(out[0].since, YearMonth(year: 2026, month: 7))
        XCTAssertEqual(out[0].extra, Money(cents: 80_00))
        XCTAssertTrue(Trends.creeping(Array(months.prefix(2))).isEmpty, "不到 3 个月不找")
        XCTAssertEqual(Trends.averageSaved(months), Money(cents: 924_00), "五个月一共存下 4.620 €")
        XCTAssertEqual(Trends.averageSaved([]), .zero)
    }

    func testTrendNudgesSayBetterOrWorse() {
        let better = [month(5, income: 1000_00, ["餐饮": 900_00]), month(6, income: 1000_00, ["餐饮": 900_00]),
                      month(7, income: 1000_00, ["餐饮": 900_00]), month(8, income: 1000_00, ["餐饮": 600_00]),
                      month(9, income: 1000_00, ["餐饮": 600_00]), month(10, income: 1000_00, ["餐饮": 600_00])]
        let a = Nudges.trends(months: better, creeping: [], currency: "EUR")
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].kind, .praise)
        XCTAssertTrue(a[0].title.contains("越过越好") && a[0].title.contains("多存 300 €"), a[0].title)
        XCTAssertTrue(a[0].advice.contains("平均每月存下 250 €"), a[0].advice)
        let worse = Nudges.trends(months: better.reversed().enumerated().map { i, s in var s = s; s.month = YearMonth(year: 2026, month: 5 + i); return s },
                                  creeping: [Trends.Creep(category: "餐饮", months: 3, before: Money(cents: 100_00), now: Money(cents: 180_00),
                                                          since: YearMonth(year: 2026, month: 7))], currency: "EUR")
        XCTAssertEqual(worse.map(\.key), ["trend-saved", "trend-creep-餐饮"])
        XCTAssertEqual(worse[0].kind, .unusual)
        XCTAssertTrue(worse[0].title.contains("少存 300 €"), worse[0].title)
        XCTAssertTrue(worse[1].title.contains("「餐饮」连涨 3 个月，比 7 月多 80 €"), worse[1].title)
        // 只有两个月：不比前后，只说平均。
        let few = Nudges.trends(months: Array(better.prefix(2)), creeping: [], currency: "EUR")
        XCTAssertTrue(few[0].title.contains("这 2 个月平均每月存下 100 €"), few[0].title)
    }

    func testWealthBreakdownSplitsWhereTheMoneyIs() {
        let accounts = [Account(id: "bank", name: "银行卡", kind: .bank), Account(id: "cash", name: "现金", kind: .cash),
                        Account(id: "pot", name: "储蓄罐", kind: .savings), Account(id: "shop", name: "店里的卡", kind: .bank),
                        Account(id: "visa", name: "信用卡", kind: .credit), Account(id: "trip", name: "旅行钱包", kind: .wallet)]
        let balances = ["bank": Money(cents: 2000_00), "cash": Money(cents: 100_00), "pot": Money(cents: 1500_00),
                        "shop": Money(cents: 800_00), "visa": Money(cents: -300_00), "trip": Money(cents: 400_00)]
        let goals = [(goal: Goal(name: "旅行", bookID: "personal", target: Money(cents: 1000_00), savingsAccountID: "trip"), saved: Money(cents: 400_00)),
                     (goal: Goal(name: "电脑", bookID: "personal", target: Money(cents: 2000_00)), saved: Money(cents: 500_00))]
        let w = WealthBreakdown.make(accounts: accounts, balances: balances, goals: goals, businessAccounts: ["shop"],
                                     obligations: Obligations(owedToMe: Money(cents: 50_00), iOwe: Money(cents: 250_00), installments: Money(cents: 100_00)))
        XCTAssertEqual(w.liquid, Money(cents: 1600_00), "银行卡 2000 + 现金 100，划给「电脑」目标 500")
        XCTAssertEqual(w.saved, Money(cents: 2400_00), "储蓄罐 1500 + 旅行钱包 400 + 划给目标的 500")
        XCTAssertEqual(w.shop, Money(cents: 800_00))
        XCTAssertEqual(w.owed, Money(cents: 550_00), "信用卡 300 + 借的和分期 250")
        XCTAssertEqual(w.owedToMe, Money(cents: 50_00))
        // 真家底 = 所有账户余额加起来 + 欠我的 − 我欠的，和家底曲线同一个数。
        XCTAssertEqual(w.net, Money(cents: 2000_00 + 100_00 + 1500_00 + 800_00 - 300_00 + 400_00 + 50_00 - 250_00))
    }

    func testWealthNudges() {
        let w = WealthBreakdown(liquid: Money(cents: 2500_00), saved: Money(cents: 1000_00), shop: .zero, owedToMe: .zero, owed: Money(cents: 3000_00))
        let out = Nudges.wealth(w, monthlySpend: Money(cents: 1000_00), threeMonthsAgo: Money(cents: 200_00), currency: "EUR")
        XCTAssertEqual(out.map(\.key), ["wealth-runway", "wealth-owed", "wealth-change"])
        XCTAssertTrue(out[0].title.contains("够你过 2,5 个月"), out[0].title)
        XCTAssertTrue(out[0].advice.contains("还差 500 €"), out[0].advice)
        XCTAssertEqual(out[1].kind, .upcoming)
        XCTAssertTrue(out[1].advice.contains("还差 500 €"), out[1].advice)
        XCTAssertTrue(out[2].title.contains("真家底 500 €，比 3 个月前多了 300 €"), out[2].title)
        let empty = Nudges.wealth(WealthBreakdown(liquid: Money(cents: 80_00), saved: .zero, shop: .zero, owedToMe: .zero, owed: .zero),
                                  monthlySpend: .zero, threeMonthsAgo: nil, currency: "EUR")
        XCTAssertEqual(empty.map(\.key), ["wealth-net"])
    }
}
