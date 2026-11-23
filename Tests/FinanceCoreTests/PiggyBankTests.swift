import XCTest
@testable import FinanceCore

/// 目标页小金猪（2026-11-23）：1 个大目标 + 3 个小目标、存在哪、忍住了、提前几天、久没存要问。全是编造数据。
final class PiggyBankTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day) }
    private let today = LocalDate(year: 2026, month: 11, day: 23)

    private func ledger() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "示例银行", kind: .bank)]
        return l
    }

    func testOneMainThreeSmallThenFull() throws {
        var l = ledger()
        let book = l.books[0].id
        let (big, _) = try l.addGoal(name: "示例电脑", bookID: book, target: Money(cents: 140000), main: true, today: today, author: "t")
        for n in ["示例旅行", "示例耳机", "示例应急金"] {
            _ = try l.addGoal(name: n, bookID: book, target: Money(cents: 50000), today: today, author: "t")
        }
        XCTAssertThrowsError(try l.addGoal(name: "示例第五个", bookID: book, target: Money(cents: 1000), today: today, author: "t")) { e in
            guard case EditError.tooManyGoals(let names) = e else { return XCTFail("\(e)") }
            XCTAssertEqual(names.count, 4)
            XCTAssertTrue(e.localizedDescription.contains("目标不在多"))
        }
        let board = Plans.goalBoard(l, today: today)
        XCTAssertEqual(board.main?.id, big.id)
        XCTAssertEqual(board.small.count, 3)
        XCTAssertEqual(board.slotsLeft, 0)

        // 存够一个就空出位子
        let travel = try XCTUnwrap(l.goals.first { $0.name == "示例旅行" })
        try l.deposit(goalID: travel.id, amount: Money(cents: 50000), fromAccount: "bank", date: today, author: "t")
        XCTAssertNoThrow(try l.addGoal(name: "示例第五个", bookID: book, target: Money(cents: 1000), today: today, author: "t"))
    }

    func testNewMainReplacesOldAndUndoPutsItBack() throws {
        var l = ledger()
        let book = l.books[0].id
        let (a, _) = try l.addGoal(name: "示例甲", bookID: book, target: Money(cents: 1000), main: true, today: today, author: "t")
        let (b, change) = try l.addGoal(name: "示例乙", bookID: book, target: Money(cents: 1000), main: true, today: today, author: "t")
        XCTAssertEqual(Plans.goalBoard(l, today: today).main?.id, b.id)
        try l.undo(changeID: change.id, author: "t")
        XCTAssertEqual(l.goals.map(\.id), [a.id])
        XCTAssertTrue(l.goals[0].pinned)
    }

    func testOldLedgerOverLimitIsKeptAsExtra() throws {
        var l = ledger()
        let book = l.books[0].id
        // 老账本：直接塞 6 个，不经过 addGoal 的限制
        l.goals = (1...6).map { Goal(name: "示例\($0)", bookID: book, target: Money(cents: 10000)) }
        let board = Plans.goalBoard(l, today: today)
        XCTAssertNotNil(board.main)
        XCTAssertEqual(board.small.count, 3)
        XCTAssertEqual(board.extra.count, 2)
        XCTAssertEqual(l.goals.count, 6, "不删")
    }

    func testDaysEarlierMatchesDailyRate() throws {
        var l = ledger()
        // 截止还有 100 天、要存 1.000 € → 每天 10 €；存 30 € 提前 3 天
        let due = today.adding(days: 100)
        let (g, _) = try l.addGoal(name: "示例相机", bookID: l.books[0].id, target: Money(cents: 100000), deadline: due, today: today, author: "t")
        XCTAssertEqual(Plans.daysEarlier(l, goalID: g.id, amount: Money(cents: 3000), today: today), 3)
        let p = try XCTUnwrap(Plans.goalBoard(l, today: today).main)
        XCTAssertEqual(p.perDay?.cents, 1000)
        XCTAssertEqual(p.arrival, due)
        // 没定日子、也没存过：算不出
        let (h, _) = try l.addGoal(name: "示例随便", bookID: l.books[0].id, target: Money(cents: 100000), today: today, author: "t")
        XCTAssertNil(Plans.daysEarlier(l, goalID: h.id, amount: Money(cents: 3000), today: today))
    }

    func testHeldBackIsTaggedAndCounted() throws {
        var l = ledger()
        let (g, _) = try l.addGoal(name: "示例电脑", bookID: l.books[0].id, target: Money(cents: 100000), main: true, today: d(2026, 11, 1), author: "t")
        let c = try l.deposit(goalID: g.id, amount: Money(cents: 320), fromAccount: "bank", date: d(2026, 11, 5), heldBack: "示例咖啡", author: "t")
        XCTAssertTrue(c.summary.contains("忍住了"))
        try l.deposit(goalID: g.id, amount: Money(cents: 5000), fromAccount: "bank", date: d(2026, 11, 9), author: "t")
        let p = try XCTUnwrap(Plans.goalBoard(l, today: today).main)
        XCTAssertEqual(p.heldBackCount, 1)
        XCTAssertEqual(p.heldBackSaved.cents, 320)
        XCTAssertEqual(p.depositDays, [5, 9])
        XCTAssertEqual(Summaries.balances(l.transactions)["bank"] ?? .zero, .zero, "划出不改余额")
    }

    func testIdleGoalAsksAndKeepSilencesIt() throws {
        var l = ledger()
        let (g, _) = try l.addGoal(name: "示例旅行", bookID: l.books[0].id, target: Money(cents: 100000), today: d(2026, 9, 1), author: "t")
        try l.deposit(goalID: g.id, amount: Money(cents: 1000), fromAccount: "bank", date: d(2026, 9, 10), author: "t")
        var board = Plans.goalBoard(l, today: today)
        XCTAssertEqual(board.needsCheck?.id, g.id)
        XCTAssertEqual(board.needsCheck?.idleDays, 74)
        try l.keepGoal(g.id, pause: false, today: today, author: "t")
        board = Plans.goalBoard(l, today: today)
        XCTAssertNil(board.needsCheck)
        // 30 天以后还没存，再问
        board = Plans.goalBoard(l, today: today.adding(days: 31))
        XCTAssertNotNil(board.needsCheck)
        // 先放一放：90 天
        try l.keepGoal(g.id, pause: true, today: today, author: "t")
        XCTAssertNil(Plans.goalBoard(l, today: today.adding(days: 60)).needsCheck)
        try l.undo(changeID: l.changes.last!.id, author: "t")
        XCTAssertEqual(l.goals[0].quietUntil, today.adding(days: 30))
    }

    func testSmallHabitAndPhrase() {
        var l = ledger()
        // 最近 60 天 12 杯示例咖啡（3,20 €），上周 3 杯
        let days = [d(2026, 10, 1), d(2026, 10, 5), d(2026, 10, 9), d(2026, 10, 13), d(2026, 10, 17), d(2026, 10, 21),
                    d(2026, 10, 25), d(2026, 10, 29), d(2026, 11, 2), d(2026, 11, 16), d(2026, 11, 18), d(2026, 11, 21)]
        l.transactions = days.map { Transaction(date: $0, amount: Money(cents: -320), description: "示例咖啡馆", accountID: "bank") }
        l.transactions.append(Transaction(date: d(2026, 11, 20), amount: Money(cents: -4500), description: "示例超市", accountID: "bank"))
        let h = Plans.smallHabit(l, today: today)
        XCTAssertEqual(h.name, "示例咖啡馆")
        XCTAssertEqual(h.typical.cents, 320)
        XCTAssertEqual(h.lastWeek, 3)
        XCTAssertEqual(h.challengeLimit, 2)
        XCTAssertEqual(h.phrase(perDay: Money(cents: 160)), "每 2 天少一次「示例咖啡馆」")
        XCTAssertEqual(h.phrase(perDay: Money(cents: 320)), "每天少一次「示例咖啡馆」")
        XCTAssertEqual(Plans.smallHabit(ledger(), today: today), .fallback)
    }

    func testAdviceTooTightOffersLater() {
        var l = ledger()
        // 最近三个月每月剩 200 €
        for m in [8, 9, 10] {
            l.transactions.append(Transaction(date: d(2026, m, 1), amount: Money(cents: 100000), description: "示例工资", accountID: "bank"))
            l.transactions.append(Transaction(date: d(2026, m, 2), amount: Money(cents: -80000), description: "示例房租", accountID: "bank"))
        }
        XCTAssertEqual(Plans.monthlyRoom(l, today: today)?.cents, 20000)
        let a = Plans.goalAdvice(l, target: Money(cents: 200000), deadline: d(2027, 2, 28), today: today)
        XCTAssertTrue(a.tooTight)
        XCTAssertEqual(a.perMonth.cents, 66667)
        // 用一半（100 €/月）存 2.000 € = 20 个月
        XCTAssertEqual(a.easierDeadline, today.adding(months: 20))
        let ok = Plans.goalAdvice(l, target: Money(cents: 60000), deadline: d(2027, 11, 23), today: today)
        XCTAssertFalse(ok.tooTight)
    }

    func testOldGoalJSONStillReads() throws {
        let json = #"{"id":"6F1C5D3E-0000-4000-8000-000000000001","name":"旧目标","bookID":"personal","target":{"cents":100000},"contributionIDs":[],"locked":false}"#
        let g = try JSONDecoder().decode(Goal.self, from: Data(json.utf8))
        XCTAssertNil(g.stash)
        XCTAssertNil(g.icon)
        let weird = #"{"id":"6F1C5D3E-0000-4000-8000-000000000002","name":"新版","bookID":"personal","target":{"cents":100000},"stash":"rocket"}"#
        XCTAssertNil(try JSONDecoder().decode(Goal.self, from: Data(weird.utf8)).stash)
    }

    func testStashLoose() {
        XCTAssertEqual(GoalStash(loose: "储蓄罐"), .jar)
        XCTAssertEqual(GoalStash(loose: "银行卡"), .card)
        XCTAssertEqual(GoalStash(loose: "抽屉里"), .spot)
        XCTAssertEqual(GoalStash(loose: "card"), .card)
    }
}
