import XCTest
@testable import FinanceCore

/// 目标、订阅、欠款三页（2026-11-23）：欠款改分期、多还少还重排、目标来不来得及、订阅分组。全是编造数据。
final class PagePlansTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day) }

    private func ledger() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "示例银行", kind: .bank), Account(id: "pot", name: "示例储蓄罐", kind: .savings)]
        return l
    }

    private func borrow(_ l: inout Ledger, _ cents: Int64, who: String = "示例表姐", dir: Debt.Direction = .iOweThem) throws -> Debt {
        try l.addDebt(counterparty: who, direction: dir, amount: Money(cents: cents), bookID: l.books[0].id,
                      date: d(2026, 10, 1), accountID: "bank", author: "t").0
    }

    // MARK: 欠款改分期

    func testPlanByPerMonthAndByCount() throws {
        var l = ledger()
        let debt = try borrow(&l, 100000)
        try l.planDebt(debt.id, perMonth: Money(cents: 30000), start: d(2026, 12, 5), author: "t")
        var plan = l.debts[0].plan!
        XCTAssertEqual(plan.map(\.amount.cents), [30000, 30000, 30000, 10000])
        XCTAssertEqual(plan.map(\.date), [d(2026, 12, 5), d(2027, 1, 5), d(2027, 2, 5), d(2027, 3, 5)])

        try l.planDebt(debt.id, count: 3, start: d(2026, 12, 5), author: "t")
        plan = l.debts[0].plan!
        XCTAssertEqual(plan.map(\.amount.cents), [33333, 33333, 33334])
        XCTAssertEqual(plan.reduce(0) { $0 + $1.amount.cents }, 100000)
        // 撤销重排 = 回到每月 300 的那份
        try l.undo(changeID: l.changes.last!.id, author: "t")
        XCTAssertEqual(l.debts[0].plan!.count, 4)
    }

    func testProgressCountsPeriodsAfterPlanning() throws {
        var l = ledger()
        let debt = try borrow(&l, 60000)
        // 排计划之前已经还了 100：计划只排剩下的 500
        try l.repay(debtID: debt.id, amount: Money(cents: 10000), date: d(2026, 10, 20), accountID: "bank", author: "t")
        try l.planDebt(debt.id, count: 5, start: d(2026, 11, 10), author: "t")
        XCTAssertEqual(l.debts[0].plan!.map(\.amount.cents), [10000, 10000, 10000, 10000, 10000])
        var p = try XCTUnwrap(l.planProgress(debt.id, today: d(2026, 11, 1)))
        XCTAssertEqual(p.paidCount, 0)
        XCTAssertEqual(p.nextAmount.cents, 10000)
        XCTAssertFalse(p.overdue)
        try l.repay(debtID: debt.id, amount: Money(cents: 10000), date: d(2026, 11, 10), accountID: "bank", author: "t")
        p = try XCTUnwrap(l.planProgress(debt.id, today: d(2026, 12, 20)))
        XCTAssertEqual(p.paidCount, 1)
        XCTAssertEqual(p.remainingCount, 4)
        XCTAssertEqual(p.nextDate, d(2026, 12, 10))
        XCTAssertTrue(p.overdue, "12 月 10 日那期过了还没还")
    }

    func testOverpayShortenOrLower() throws {
        var l = ledger()
        let debt = try borrow(&l, 50000)
        try l.planDebt(debt.id, count: 5, start: d(2026, 11, 10), author: "t")   // 5 × 100
        let preview = try XCTUnwrap(l.repayPreview(debt.id, amount: Money(cents: 25000), today: d(2026, 11, 10)))
        XCTAssertEqual(preview.due.cents, 10000)
        XCTAssertEqual(preview.difference.cents, 15000)
        XCTAssertEqual(preview.options.map(\.adjust), [.shortenPlan, .lowerPayments])
        XCTAssertEqual(preview.options[0].monthsEarlier, 1, "多还 150：最后一期没了，倒数第二期只剩 50")
        XCTAssertEqual(preview.options[1].nextAmount?.cents, 6250, "剩下 250 分 4 期")

        var a = l
        try a.repay(debtID: debt.id, amount: Money(cents: 25000), date: d(2026, 11, 10), accountID: "bank", adjust: .shortenPlan, author: "t")
        XCTAssertEqual(a.debts[0].plan!.map(\.amount.cents), [25000, 10000, 10000, 5000])
        XCTAssertEqual(a.planProgress(debt.id, today: d(2026, 11, 11))?.paidCount, 1)
        XCTAssertTrue(a.changes.last!.summary.contains("提前 1 个月"))
        // 撤销：还款和计划一起回去
        try a.undo(changeID: a.changes.last!.id, author: "t")
        XCTAssertEqual(a.debts[0].plan!.map(\.amount.cents), [10000, 10000, 10000, 10000, 10000])
        XCTAssertTrue(a.debts[0].repaymentIDs.isEmpty)

        var b = l
        try b.repay(debtID: debt.id, amount: Money(cents: 25000), date: d(2026, 11, 10), accountID: "bank", adjust: .lowerPayments, author: "t")
        XCTAssertEqual(b.debts[0].plan!.map(\.amount.cents), [25000, 6250, 6250, 6250, 6250])
        XCTAssertEqual(b.debts[0].plan!.last!.date, d(2027, 3, 10))
    }

    func testUnderpayAddToNextOrExtend() throws {
        var l = ledger()
        let debt = try borrow(&l, 30000)
        try l.planDebt(debt.id, count: 3, start: d(2026, 11, 10), author: "t")   // 3 × 100
        var a = l
        try a.repay(debtID: debt.id, amount: Money(cents: 6000), date: d(2026, 11, 10), accountID: "bank", adjust: .addToNext, author: "t")
        XCTAssertEqual(a.debts[0].plan!.map(\.amount.cents), [6000, 14000, 10000])
        var b = l
        try b.repay(debtID: debt.id, amount: Money(cents: 6000), date: d(2026, 11, 10), accountID: "bank", adjust: .extendPlan, author: "t")
        XCTAssertEqual(b.debts[0].plan!.map(\.amount.cents), [6000, 10000, 10000, 4000])
        XCTAssertEqual(b.debts[0].plan!.last!.date, d(2027, 2, 10))

        // 这期一分没还：顺延 = 从这期起都往后挪一个月
        var c = l
        try c.skipPlannedPayment(debt.id, adjust: .extendPlan, today: d(2026, 11, 20), author: "t")
        XCTAssertEqual(c.debts[0].plan!.map(\.date), [d(2026, 12, 10), d(2027, 1, 10), d(2027, 2, 10)])
        var e = l
        try e.skipPlannedPayment(debt.id, adjust: .addToNext, today: d(2026, 11, 20), author: "t")
        XCTAssertEqual(e.debts[0].plan!.map(\.amount.cents), [20000, 10000])
        // 多还的选项不能用在「这期没还」上
        XCTAssertThrowsError(try e.skipPlannedPayment(debt.id, adjust: .shortenPlan, author: "t"))
    }

    func testEditOnePeriodRebalancesTheTail() throws {
        var l = ledger()
        let debt = try borrow(&l, 40000)
        try l.planDebt(debt.id, count: 4, start: d(2026, 11, 10), author: "t")   // 4 × 100
        try l.editPlannedPayment(debt.id, index: 1, amount: Money(cents: 20000), author: "t")
        XCTAssertEqual(l.debts[0].plan!.map(\.amount.cents), [10000, 20000, 10000])
        try l.editPlannedPayment(debt.id, index: 2, amount: Money(cents: 5000), author: "t")
        XCTAssertEqual(l.debts[0].plan!.map(\.amount.cents), [10000, 20000, 5000, 5000])
        XCTAssertEqual(l.debts[0].plan!.last!.date, d(2027, 2, 10))
        XCTAssertThrowsError(try l.editPlannedPayment(debt.id, index: 0, amount: Money(cents: 50000), author: "t"))
        // 写的计划加起来不等于还欠的：不让存
        XCTAssertThrowsError(try l.setDebtPlan(debt.id, plan: [PlannedPayment(date: d(2026, 12, 1), amount: Money(cents: 100))], author: "t"))
    }

    func testTheyOweMeCanHaveAPlanToo() throws {
        var l = ledger()
        let debt = try borrow(&l, 20000, who: "示例同事", dir: .theyOweMe)
        try l.planDebt(debt.id, perMonth: Money(cents: 5000), start: d(2026, 11, 15), author: "t")
        let o = Plans.debtOverview(l, today: d(2026, 11, 3))
        XCTAssertEqual(o.incomingThisMonth.cents, 5000)
        XCTAssertEqual(o.dueThisMonth.cents, 0)
        XCTAssertTrue(o.payoffs.isEmpty, "时间线只放我欠的")
    }

    func testOverviewDueThisMonthAndAllClear() throws {
        var l = ledger()
        let book = l.books[0].id
        let debt = try borrow(&l, 30000)
        try l.planDebt(debt.id, count: 3, start: d(2026, 11, 20), author: "t")
        _ = try l.addInstallment(name: "示例手机", bookID: book, accountID: "bank", total: Money(cents: 60000), count: 6,
                                 purchaseDate: d(2026, 10, 1), firstPayment: d(2026, 11, 5), author: "t")
        let o = Plans.debtOverview(l, today: d(2026, 11, 3))
        XCTAssertEqual(o.dueThisMonth.cents, 10000 + 10000)
        XCTAssertEqual(o.iOwe.cents, 30000 + 60000)
        XCTAssertEqual(o.payoffs.map(\.name), ["欠示例表姐", "示例手机"])
        XCTAssertEqual(o.allClear, d(2027, 4, 5))
        // 加一笔没约日子的：全部还清算不出来
        _ = try borrow(&l, 5000, who: "示例朋友")
        XCTAssertNil(Plans.debtOverview(l, today: d(2026, 11, 3)).allClear)
        XCTAssertEqual(Plans.debtOverview(l, today: d(2026, 11, 3)).undatedCount, 1)
    }

    func testOldDebtJSONStillLoads() throws {
        let json = #"{"id":"6F1B1B1B-0000-0000-0000-000000000001","counterparty":"x","direction":"iOweThem","principal":{"cents":100},"bookID":"p","startDate":"2026-01-01","repaymentIDs":[],"closed":false}"#
        let debt = try JSONDecoder().decode(Debt.self, from: Data(json.utf8))
        XCTAssertNil(debt.plan)
    }

    // MARK: 目标来不来得及

    func testGoalForecastBehindAndExtra() throws {
        var l = ledger()
        let (goal, _) = try l.addGoal(name: "示例旅行", bookID: l.books[0].id, target: Money(cents: 200000),
                                      deadline: d(2027, 6, 30), author: "t")
        // 最近三个月每月存 150
        for m in [9, 10, 11] {
            try l.deposit(goalID: goal.id, amount: Money(cents: 15000), fromAccount: "bank", date: d(2026, m, 1), author: "t")
        }
        let today = d(2026, 11, 23)
        let f = try XCTUnwrap(Plans.goalForecasts(l, today: today).first)
        XCTAssertEqual(f.saved.cents, 45000)
        XCTAssertEqual(f.left.cents, 155000)
        XCTAssertEqual(f.monthlyPace.cents, 45000 * 30 / 84, "9 月 1 日开始存，按 84 天平均")
        XCTAssertEqual(f.pace, .behind)
        XCTAssertEqual(f.monthsToDeadline, 7)
        XCTAssertEqual(f.neededPerMonth?.cents, 22143)
        XCTAssertNotNil(f.extraPerMonth)
        XCTAssertGreaterThan(f.monthsLate ?? 0, 0)
    }

    func testGoalSortingPinAndReorder() throws {
        var l = ledger()
        let book = l.books[0].id
        let (a, _) = try l.addGoal(name: "示例应急金", bookID: book, target: Money(cents: 100000), author: "t")
        let (b, _) = try l.addGoal(name: "示例换电脑", bookID: book, target: Money(cents: 100000), deadline: d(2027, 3, 1), author: "t")
        var order = Plans.sortedGoals(Plans.goalForecasts(l, today: d(2026, 11, 23))).map(\.id)
        XCTAssertEqual(order, [b.id, a.id], "定了日子的更急")
        try l.pinGoal(a.id, author: "t")
        order = Plans.sortedGoals(Plans.goalForecasts(l, today: d(2026, 11, 23))).map(\.id)
        XCTAssertEqual(order.first, a.id)
        try l.undo(changeID: l.changes.last!.id, author: "t")
        XCTAssertFalse(l.goals.contains(where: \.pinned))
        try l.reorderGoals([a.id, b.id], author: "t")
        order = Plans.sortedGoals(Plans.goalForecasts(l, today: d(2026, 11, 23))).map(\.id)
        XCTAssertEqual(order, [a.id, b.id])
    }

    // MARK: 订阅

    func testSubscriptionReviewAndGroups() throws {
        var l = ledger()
        let today = d(2026, 11, 23)
        try l.addSubscription(Subscription(name: "示例视频会员", amount: Money(cents: 999), cycle: .monthly, nextDate: d(2026, 11, 25),
                                           accountID: "bank", match: "examplevideo"), author: "t")
        try l.addSubscription(Subscription(name: "示例云盘", amount: Money(cents: 299), cycle: .monthly, nextDate: d(2026, 12, 15), accountID: "bank",
                                           rarelyUsed: true), author: "t")
        try l.addSubscription(Subscription(name: "示例域名", amount: Money(cents: 1200), cycle: .yearly, nextDate: d(2027, 5, 1), accountID: "bank"), author: "t")
        try l.addSubscription(Subscription(name: "示例健身", amount: Money(cents: 3000), cycle: .monthly, nextDate: d(2026, 11, 29), accountID: "bank"), author: "t")
        // 视频会员最近一次扣了 12,99：涨价
        l.transactions.append(Transaction(date: d(2026, 10, 25), amount: Money(cents: -1299), description: "EXAMPLEVIDEO", accountID: "bank"))
        let st = Subscriptions.status(l, today: today)
        let video = try XCTUnwrap(st.first { $0.name == "示例视频会员" })
        XCTAssertTrue(video.priceUp)
        XCTAssertTrue(video.isDueVerySoon)
        XCTAssertEqual(video.reviewReason, "刚涨价")
        let groups = Subscriptions.groups(st, today: today)
        XCTAssertEqual(groups.map(\.kind), [.review, .thisWeek, .yearly])
        XCTAssertEqual(groups[0].items.map(\.name).sorted(), ["示例云盘", "示例视频会员"])
        let t = Subscriptions.totals(st)
        XCTAssertEqual(t.weekCount, 2)
        XCTAssertEqual(t.weekAmount.cents, 999 + 3000)
        XCTAssertEqual(t.reviewCount, 2)
        XCTAssertEqual(st.first { $0.name == "示例域名" }?.monthlyAmount.cents, 100)
    }
}
