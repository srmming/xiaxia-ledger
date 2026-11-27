import XCTest
@testable import FinanceCore

/// 界面 v3 的几条算账规则。数字全是编的。
final class JourneyTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    private var laptop: Journey {
        var j = Journey(name: "换新电脑", stops: [eur("50"), eur("200"), eur("700"), eur("1050"), eur("1400")],
                        saved: eur("519"), monthlyPlan: eur("200"))
        j.savedThisMonth = eur("80")
        return j
    }

    func testWhereIAm() {
        let j = laptop
        XCTAssertEqual(j.stations.count, 6)
        XCTAssertEqual(j.total, eur("1400"))
        XCTAssertEqual(j.nextIndex, 3)
        XCTAssertEqual(j.remainingToNext, eur("181"))
        XCTAssertEqual(j.position.passed, 2)
        XCTAssertEqual(j.position.fraction, 319.0 / 500.0, accuracy: 0.0001)
    }

    func testDepositReachesStations() {
        var j = laptop
        XCTAssertTrue(j.deposit(eur("20")).isEmpty)
        XCTAssertEqual(j.saved, eur("539"))
        XCTAssertEqual(j.savedThisMonth, eur("100"))
        let reached = j.deposit(eur("161"))
        XCTAssertEqual(reached.map(\.target), [eur("700")])
        XCTAssertEqual(j.nextIndex, 4)
        // 一次过两站
        XCTAssertEqual(j.deposit(eur("700")).map(\.target), [eur("1050"), eur("1400")])
        XCTAssertTrue(j.isFinished)
        XCTAssertEqual(j.remainingToNext, .zero)
        // 0 和负数不算
        XCTAssertTrue(j.deposit(.zero).isEmpty)
        XCTAssertTrue(j.deposit(eur("-5")).isEmpty)
    }

    func testSmallerStepsHalve() {
        XCTAssertEqual(Journey.smallerSteps(from: eur("200")), [eur("100"), eur("50")])
        XCTAssertEqual(Journey.smallerSteps(from: eur("3")), [eur("1,50")])
        XCTAssertEqual(Journey.smallerSteps(from: eur("1")), [])
    }

    func testMonthsAndDelay() {
        let j = laptop   // 还差 881，每月 200
        XCTAssertEqual(j.monthsToFinish(), 5)
        XCTAssertEqual(j.monthsToFinish(monthly: eur("100")), 9)
        XCTAssertNil(j.monthsToFinish(monthly: .zero))
        XCTAssertEqual(j.delayMonths(ifNextMonthIs: eur("100")), 0)   // 100 + 4×200 = 900 ≥ 881
        XCTAssertEqual(j.delayMonths(ifNextMonthIs: eur("50")), 1)    // 50 + 4×200 = 850 < 881
    }

    func testHouseholdTotals() {
        let t = HouseholdTotals(holdings: [eur("1500"), eur("85")], debts: [eur("640")])
        XCTAssertEqual(t.have, eur("1585"))
        XCTAssertEqual(t.owe, eur("640"))
        XCTAssertEqual(t.net, eur("945"))
        // 欠的写成负数也按欠算
        XCTAssertEqual(HouseholdTotals(holdings: [], debts: [eur("-300")]).net, eur("-300"))
    }

    func testFreeToSpend() {
        let f = FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12)
        XCTAssertEqual(f.left, eur("976,61"))
        XCTAssertEqual(f.perDay, eur("81,38"))
        XCTAssertEqual(f.spentTotal, eur("1163,39"))
        XCTAssertEqual(FreeToSpend(income: eur("100"), fixed: eur("200"), forGoals: .zero, spent: .zero, daysLeft: 5).perDay, .zero)
        XCTAssertEqual(FreeToSpend(income: eur("100"), fixed: .zero, forGoals: .zero, spent: .zero, daysLeft: 0).perDay, .zero)
    }

    func testEmergencyRunway() {
        let r = EmergencyRunway(fund: eur("2400"), monthlyMust: eur("860"))
        XCTAssertEqual(r.monthsText, "2,8")
        XCTAssertEqual(r.fraction(), 2400.0 / 860.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(EmergencyRunway(fund: eur("2400"), monthlyMust: .zero).monthsText, "0,0")
    }

    func testQuickPhrase() {
        XCTAssertEqual(QuickPhrase.parse("刚才咖啡 3 块 2"), QuickPhrase(name: "咖啡", emoji: "☕", amount: eur("3,20")))
        XCTAssertEqual(QuickPhrase.parse("午饭12,5"), QuickPhrase(name: "午饭", emoji: "🥗", amount: eur("12,50")))
        XCTAssertEqual(QuickPhrase.parse("打车 15"), QuickPhrase(name: "打车", emoji: "🚕", amount: eur("15")))
        XCTAssertEqual(QuickPhrase.parse("买了本书 18.90€"), QuickPhrase(name: "本书", emoji: "🧾", amount: eur("18,90")))
        XCTAssertEqual(QuickPhrase.parse("花了 20")?.name, "一笔开销")
        // 没有「块」就不把后面的数字当小数
        XCTAssertEqual(QuickPhrase.parse("超市 23 2 袋")?.amount, eur("23"))
        XCTAssertNil(QuickPhrase.parse("刚才喝了杯咖啡"))
        XCTAssertNil(QuickPhrase.parse("咖啡 0"))
    }
}
