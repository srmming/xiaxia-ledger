import XCTest
@testable import FinanceCore

/// 预测卡（Outlook）：认固定开销、认一次性开销、月底大概花、下个月要付、店里估收入。数据全是编的。
final class OutlookTests: XCTestCase {
    let today = LocalDate("2026-05-20")!
    let author = "测试"

    func lifeLedger() throws -> Ledger {
        var l = Ledger.starter
        _ = try l.enableBusinessMode(author: author)
        l.accounts += [Account(id: "life", name: "日常卡", kind: .bank), Account(id: "shop", name: "公司卡", kind: .bank)]
        var txs: [Transaction] = []
        for m in 2...5 {
            txs.append(Transaction(date: LocalDate(year: 2026, month: m, day: 1), amount: Money(cents: -70000), description: "房租",
                                   accountID: "life", bookID: "personal", category: "房租"))
        }
        var d = LocalDate("2026-02-01")!
        while d < today {
            txs.append(Transaction(date: d, amount: Money(cents: -3000), description: "超市", accountID: "life", bookID: "personal", category: "超市"))
            d = d.adding(days: 3)
        }
        txs.append(Transaction(date: LocalDate("2026-03-15")!, amount: Money(cents: -90000), description: "电视", accountID: "life",
                               bookID: "personal", category: "电器"))
        l.transactions = txs
        return l
    }

    func testDetectsFixedAndSkipsAfterNo() throws {
        var l = try lifeLedger()
        let guesses = Outlook.fixedGuesses(l, side: .life, today: today)
        XCTAssertEqual(guesses.map(\.category), ["房租"], "每月一次、金额一样的房租认成固定开销；超市一个月好几笔不算")
        XCTAssertEqual(guesses.first?.day, 1)
        let no = l.markNotFixed(guesses[0].key, name: "房租", author: author)
        XCTAssertTrue(Outlook.fixedGuesses(l, side: .life, today: today).isEmpty, "说了不算就不再问")
        _ = try l.undo(changeID: no.id, author: author)
        XCTAssertEqual(Outlook.fixedGuesses(l, side: .life, today: today).count, 1)
        // 说「算」：加进固定开销（生活账本），之后就不再是「认出来的」，而是固定开销列表里的。
        _ = try l.addFixedCost(name: "房租", amount: Money(cents: 70000), day: 1, accountID: "life", category: "房租",
                               bookID: "personal", today: today, author: author)
        XCTAssertTrue(Outlook.fixedGuesses(l, side: .life, today: today).isEmpty)
        XCTAssertEqual(l.recurring.last?.template.bookID, "personal")
    }

    func testLifeCardsLeaveOutFixedAndOneOff() throws {
        var l = try lifeLedger()
        let r = try XCTUnwrap(Outlook.life(l, balance: Money(cents: 300000), today: today))
        // 每天平均只算超市（30 € 每 3 天 ≈ 10 €/天），房租是固定的、电视是一次性的都不算。
        XCTAssertLessThan(r.dailyAverage.cents, 1100)
        XCTAssertGreaterThan(r.dailyAverage.cents, 900)
        XCTAssertEqual(r.fixedLeft, .zero, "这个月房租已经付了")
        XCTAssertEqual(r.daysLeft, 11)
        XCTAssertEqual(r.monthEnd.cents, r.spentSoFar.cents + r.dailyAverage.cents * 11)
        XCTAssertTrue(r.next.fixed.contains { $0.name == "房租" && $0.amount.cents == 70000 && $0.date == LocalDate("2026-06-01") })
        XCTAssertEqual(r.next.variable.map(\.name), ["超市"])
        XCTAssertNotNil(r.runway)
        // AI 说电视不是一次性的：就算进平时的花销。
        let tv = l.transactions.first { $0.description == "电视" }!
        let mark = try l.markOneOff([tv.id], oneOff: false, author: author)
        let r2 = try XCTUnwrap(Outlook.life(l, balance: Money(cents: 300000), today: today))
        XCTAssertGreaterThan(r2.dailyAverage.cents, 1500)
        XCTAssertFalse(Outlook.reviewQueue(l, today: today).contains { $0.tx.id == tv.id })
        _ = try l.undo(changeID: mark.id, author: author)
        XCTAssertNil(l.profile.oneOff?[tv.id.uuidString])
    }

    func testReviewQueueGuessesWithRule() throws {
        var l = try lifeLedger()
        let big = Transaction(date: LocalDate("2026-05-18")!, amount: Money(cents: -40000), description: "沙发", accountID: "life",
                              bookID: "personal", category: "家具", source: "手记")
        l.transactions.append(big)
        let queue = Outlook.reviewQueue(l, today: today)
        XCTAssertEqual(queue.first { $0.tx.id == big.id }?.guess, true, "超过每月花销 10% 的一笔，规则猜是一次性")
        XCTAssertEqual(queue.first { $0.tx.description == "超市" }?.guess, false)
    }

    func testNotEnoughDataHidesCards() throws {
        var l = Ledger.starter
        l.accounts += [Account(id: "life", name: "日常卡", kind: .bank)]
        l.transactions = [Transaction(date: today.adding(days: -10), amount: Money(cents: -500), description: "咖啡",
                                      accountID: "life", bookID: "personal", category: "餐饮")]
        XCTAssertNil(Outlook.life(l, balance: Money(cents: 1000), today: today))
    }

    func testBusinessEstimatesByWeekday() throws {
        var l = try lifeLedger()
        var d = LocalDate("2026-04-01")!
        while d < today {
            l.transactions.append(Transaction(date: d, amount: Money(cents: 5000), description: "现金收入", accountID: "shop",
                                              bookID: "miora", category: "营业收入"))
            d = d.adding(days: 1)
        }
        let b = try XCTUnwrap(Outlook.business(l, balance: Money(cents: 200000), today: today))
        XCTAssertEqual(b.received.cents, 19 * 5000)
        XCTAssertEqual(b.estimateRest.cents, 12 * 5000, "今天还没记，今天到月底 12 天每天按 50 € 估")
        XCTAssertEqual(b.monthIncome.cents, 31 * 5000)
        XCTAssertFalse(b.next.fixed.contains { $0.name == "房租" }, "生活那边的房租不算店里的")
    }
}
