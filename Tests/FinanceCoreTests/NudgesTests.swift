import XCTest
@testable import FinanceCore

// 总览夏夏卡片：离目标、留意、快要扣钱、夸一句。测试只用编造的数字。
final class NudgesTests: XCTestCase {
    let today = LocalDate(year: 2026, month: 11, day: 20)
    func d(_ m: Int, _ day: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: day) }
    func spend(_ date: LocalDate, _ cents: Int64, _ desc: String, _ cat: String, account: String = "card") -> Transaction {
        Transaction(date: date, amount: Money(cents: -cents), description: desc, accountID: account, bookID: "personal", category: cat)
    }

    func run(_ expenses: [Transaction], aim: String? = nil, end: Money? = nil, subs: [SubscriptionStatus] = [],
             balance: Money? = nil, spent: Int64 = 100_00, last: Int64 = 100_00) -> [Nudge] {
        Nudges.overview(expenses: expenses, today: today, currency: "EUR", aim: aim, projectedEnd: end,
                        spentSoFar: Money(cents: spent), lastMonthSameDaySpent: Money(cents: last), subscriptions: subs,
                        accountName: { _ in "银行卡" }, balance: { _ in balance })
    }

    func testSavingTarget() {
        XCTAssertEqual(Nudges.monthlySavingTarget(aim: "每个月存下 300 €"), Money(cents: 300_00))
        XCTAssertEqual(Nudges.monthlySavingTarget(aim: "每个月存下 1.000 ¥"), Money(cents: 1000_00))
        XCTAssertNil(Nudges.monthlySavingTarget(aim: "每个月存下一笔钱"))
        XCTAssertNil(Nudges.monthlySavingTarget(aim: "搞清楚钱都花哪了"))
    }

    func testGoalGapSaysWhereToCut() {
        // 外卖这个月 5 次，每次 20 €；离 300 € 还差 80 € → 少点 4 次就够。
        let food = (1...5).map { spend(d(11, $0 * 3), 20_00, "外卖", "外卖") }
        let rent = spend(d(11, 1), 900_00, "房租", "房租")
        let n = run(food + [rent], aim: "每个月存下 300 €", end: Money(cents: 220_00)).first!
        XCTAssertEqual(n.kind, .goal)
        XCTAssertTrue(n.title.contains("还差 80 €"), n.title)
        XCTAssertTrue(n.advice.contains("「外卖」") && n.advice.contains("少花 4 次"), n.advice)
        XCTAssertEqual(n.question, "怎么省出这 80 €？")
    }

    func testGoalReached() {
        let n = run([], aim: "每个月存下 300 €", end: Money(cents: 450_00)).first!
        XCTAssertEqual(n.kind, .goal)
        XCTAssertTrue(n.title.contains("比目标多 150 €"), n.title)
    }

    func testUnusualWeek() {
        // 前 8 周每周花材 100 €，这周 160 € → 多 60%。
        var txs: [Transaction] = []
        for w in 1...8 { txs.append(spend(today.adding(days: -7 * w - 1), 100_00, "VIVERO", "花材")) }
        txs.append(spend(today.adding(days: -2), 60_00, "VIVERO", "花材"))
        txs.append(spend(today.adding(days: -1), 100_00, "FLORES SOL", "花材"))
        let n = run(txs).first { $0.kind == .unusual }!
        XCTAssertTrue(n.title.contains("「花材」比平时多 60%"), n.title)
        XCTAssertTrue(n.advice.lowercased().contains("flores sol") && n.advice.contains("11 月 19 日"), n.advice)
    }

    func testUpcomingAndShortBalance() {
        var l = Ledger.starter
        l.accounts = [Account(id: "card", name: "银行卡", kind: .bank)]
        try? l.addSubscription(Subscription(name: "视频会员", amount: Money(cents: 12_99), cycle: .monthly, nextDate: d(11, 22), accountID: "card"), author: "测试")
        try? l.addSubscription(Subscription(name: "健身房", amount: Money(cents: 39_00), cycle: .monthly, nextDate: d(12, 10), accountID: "card"), author: "测试")
        let subs = Subscriptions.status(l, today: today)
        let ok = run([], subs: subs, balance: Money(cents: 500_00)).first { $0.kind == .upcoming }!
        XCTAssertEqual(ok.title, "后天扣「视频会员」，一共 13 €。")
        XCTAssertEqual(ok.advice, "扣款账户里的钱够。")
        let low = run([], subs: subs, balance: Money(cents: 5_00)).first { $0.kind == .upcoming }!
        XCTAssertTrue(low.advice.contains("「银行卡」里的钱不够扣"), low.advice)
    }

    func testPraiseOnlyWhenNothingElse() {
        let n = run([], spent: 80_00, last: 100_00)
        XCTAssertEqual(n.map(\.kind), [.praise])
        XCTAssertEqual(n[0].title, "这个月花钱比上个月同期稳。")
    }
}
