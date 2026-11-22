import XCTest
@testable import FinanceCore

// 自己动手记账：算式、备注和标签、重复记账、复制、拆开、退款、批量加标签、搜索、常记的。
// 只用编造的数字。
final class ManualEntryTests: XCTestCase {
    let d = LocalDate(year: 2026, month: 1, day: 31)

    func ledger() -> Ledger {
        var l = Ledger.fresh
        l.accounts = [Account(id: "card", name: "银行卡", kind: .bank), Account(id: "cash", name: "现金", kind: .cash)]
        return l
    }

    func expense(_ cents: Int64, _ text: String, _ category: String = "超市", date: LocalDate? = nil) -> Transaction {
        Transaction(date: date ?? d, amount: Money(cents: -cents), description: text, accountID: "card", bookID: "personal",
                    category: category, source: "手记")
    }

    // MARK: 算式

    func testExpressions() {
        XCTAssertEqual(Money.evaluate("12,50+3,20")?.cents, 1570)
        XCTAssertEqual(Money.evaluate("20-4,5")?.cents, 1550)
        XCTAssertEqual(Money.evaluate("3*2,20")?.cents, 660)
        XCTAssertEqual(Money.evaluate("2,20×3")?.cents, 660)
        XCTAssertEqual(Money.evaluate("1.234,56")?.cents, 123456)
        XCTAssertEqual(Money.evaluate("-5+2")?.cents, -300)
        XCTAssertEqual(Money.evaluate("10 − 2,5")?.cents, 750)
        XCTAssertNil(Money.evaluate("12+"))
        XCTAssertNil(Money.evaluate("abc"))
        XCTAssertTrue(Money.isExpression("12+3"))
        XCTAssertFalse(Money.isExpression("-12"))
    }

    // MARK: 备注和标签

    func testNoteAndTagsRoundTrip() throws {
        var l = ledger()
        var t = expense(1250, "超市")
        t.note = "和小王 AA"
        t.tags = ["旅行"]
        try l.addTransaction(t, author: "我")
        let data = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(Ledger.self, from: data)
        XCTAssertEqual(back.transactions[0].note, "和小王 AA")
        XCTAssertEqual(back.transactions[0].tags, ["旅行"])
    }

    func testOldTransactionsWithoutNoteStillLoad() throws {
        let json = #"{"id":"6A1B6E1A-0C5E-4C1F-9C2E-111111111111","date":"2026-01-02","amount":{"cents":-100},"description":"x","accountID":"card"}"#
        let t = try JSONDecoder().decode(Transaction.self, from: Data(json.utf8))
        XCTAssertNil(t.note)
        XCTAssertNil(t.tags)
    }

    func testTagCleaning() {
        XCTAssertEqual(Tags.clean(["#旅行", " 报销 ", "旅行", "", "#"]), ["旅行", "报销"])
        XCTAssertEqual(Tags.clean(["旅行,报销"]), ["旅行", "报销"])
    }

    func testTagManyAndUndo() throws {
        var l = ledger()
        try l.addTransaction(expense(100, "A"), author: "我")
        try l.addTransaction(expense(200, "B"), author: "我")
        let ids = l.transactions.map(\.id)
        let c = try l.tagTransactions(ids, add: ["#旅行"], author: "我")
        XCTAssertEqual(l.transactions.map(\.tagList), [["旅行"], ["旅行"]])
        XCTAssertEqual(l.allTags, ["旅行"])
        try l.tagTransactions([ids[0]], add: [], remove: ["旅行"], author: "我")
        XCTAssertNil(l.transactions[0].tags)
        try l.undo(changeID: l.changes.last!.id, author: "我")
        try l.undo(changeID: c.id, author: "我")
        XCTAssertNil(l.transactions[1].tags)
    }

    func testSearchFindsNoteTagAndAmount() {
        var t = expense(1250, "MERCADONA 1234")
        t.note = "生日蛋糕"
        t.tags = ["派对"]
        XCTAssertTrue(t.matches("蛋糕"))
        XCTAssertTrue(t.matches("#派对"))
        XCTAssertTrue(t.matches("#派"))
        XCTAssertFalse(t.matches("#旅行"))
        XCTAssertTrue(t.matches("12,50"))
        XCTAssertTrue(t.matches("超市"))
        XCTAssertFalse(t.matches("房租"))
    }

    // MARK: 复制、退款、拆开

    func testDuplicate() throws {
        var l = ledger()
        var t = expense(1500, "理发", "个人护理")
        t.tags = ["自己"]
        try l.addTransaction(t, author: "我")
        let today = LocalDate(year: 2026, month: 2, day: 7)
        let c = try l.duplicateTransaction(t.id, date: today, author: "我")
        XCTAssertEqual(l.transactions.count, 2)
        XCTAssertEqual(l.transactions[1].date, today)
        XCTAssertEqual(l.transactions[1].amount, t.amount)
        XCTAssertEqual(l.transactions[1].tags, ["自己"])
        XCTAssertNotEqual(l.transactions[1].id, t.id)
        try l.undo(changeID: c.id, author: "我")
        XCTAssertEqual(l.transactions.count, 1)
    }

    func testRefundReducesSpending() throws {
        var l = ledger()
        let t = expense(6000, "鞋", "购物")
        try l.addTransaction(t, author: "我")
        XCTAssertThrowsError(try l.addRefund(of: t.id, amount: Money(cents: 7000), date: d, author: "我"))
        try l.addRefund(of: t.id, date: d, author: "我")
        let r = l.transactions[1]
        XCTAssertEqual(r.amount.cents, 6000)
        XCTAssertEqual(r.category, Transaction.refundCategory)
        XCTAssertEqual(r.accountID, "card")
        XCTAssertEqual(Summaries.balances(l.transactions)["card"], .zero)
        XCTAssertThrowsError(try l.addRefund(of: r.id, date: d, author: "我"), "收入不能再退款")
    }

    func testSplitAndUndo() throws {
        var l = ledger()
        let t = expense(4830, "超市")
        try l.addTransaction(t, author: "我")
        XCTAssertThrowsError(try l.splitTransaction(t.id, parts: [SplitPart(amount: Money(cents: 3000)), SplitPart(amount: Money(cents: 1000))], author: "我"))
        let c = try l.splitTransaction(t.id, parts: [SplitPart(amount: Money(cents: 3000), category: "超市"),
                                                     SplitPart(amount: Money(cents: 1830), category: "日用品")], author: "我")
        XCTAssertEqual(l.transactions.count, 2)
        XCTAssertEqual(l.transactions.map(\.amount.cents).sorted(), [-3000, -1830])
        XCTAssertEqual(l.transactions[0].id, t.id)
        XCTAssertEqual(l.transactions[1].category, "日用品")
        try l.undo(changeID: c.id, author: "我")
        XCTAssertEqual(l.transactions, [t])
    }

    func testSplitPartParsing() {
        XCTAssertEqual(SplitPart(parsing: "18,30:日用品"), SplitPart(amount: Money(cents: 1830), category: "日用品"))
        XCTAssertEqual(SplitPart(parsing: "30"), SplitPart(amount: Money(cents: 3000)))
        XCTAssertNil(SplitPart(parsing: "abc:x"))
    }

    func testTransfersCannotBeSplitOrCopied() throws {
        var l = ledger()
        try l.addAccountTransfer(amount: Money(cents: 5000), from: "card", to: "cash", date: d, author: "我")
        let id = l.transactions[0].id
        XCTAssertThrowsError(try l.duplicateTransaction(id, author: "我"))
        XCTAssertThrowsError(try l.splitTransaction(id, parts: [SplitPart(amount: Money(cents: 1)), SplitPart(amount: Money(cents: 4999))], author: "我"))
    }

    // MARK: 重复记账

    func testDateMath() {
        XCTAssertEqual(LocalDate(year: 2026, month: 1, day: 31).adding(months: 1), LocalDate(year: 2026, month: 2, day: 28))
        XCTAssertEqual(LocalDate(year: 2026, month: 12, day: 15).adding(months: 1), LocalDate(year: 2027, month: 1, day: 15))
        XCTAssertEqual(LocalDate(year: 2026, month: 12, day: 29).adding(days: 7), LocalDate(year: 2027, month: 1, day: 5))
        XCTAssertEqual(LocalDate(year: 2026, month: 11, day: 23).weekdayIndex, 0)   // 周一
    }

    func testMonthlyRuleKeepsDayOfMonth() {
        let r = Recurring(template: expense(65000, "房租", "住房"), frequency: .monthly, start: d)
        XCTAssertEqual(r.nextDate, LocalDate(year: 2026, month: 2, day: 28))
        XCTAssertEqual(r.date(after: 2), LocalDate(year: 2026, month: 3, day: 31))
        XCTAssertEqual(r.summary, "每月 31 号 · 房租 650,00 €")
    }

    func testRecurringPostsDueAndUndoes() throws {
        var l = ledger()
        let start = LocalDate(year: 2026, month: 1, day: 1)
        try l.addRecurring(expense(65000, "房租", "住房", date: start), frequency: .monthly, author: "我")
        XCTAssertEqual(l.transactions.count, 1)
        XCTAssertNil(l.postDueRecurring(today: LocalDate(year: 2026, month: 1, day: 31), author: "我"))
        let c = try XCTUnwrap(l.postDueRecurring(today: LocalDate(year: 2026, month: 3, day: 5), author: "我"))
        XCTAssertEqual(l.transactions.map(\.date), [start, LocalDate(year: 2026, month: 2, day: 1), LocalDate(year: 2026, month: 3, day: 1)])
        XCTAssertEqual(l.recurring[0].nextDate, LocalDate(year: 2026, month: 4, day: 1))
        XCTAssertTrue(c.summary.contains("房租"))
        // 同一天再跑一次不会重复记。
        XCTAssertNil(l.postDueRecurring(today: LocalDate(year: 2026, month: 3, day: 5), author: "我"))
        try l.undo(changeID: c.id, author: "我")
        XCTAssertEqual(l.transactions.count, 1)
        XCTAssertEqual(l.recurring[0].nextDate, LocalDate(year: 2026, month: 2, day: 1))
    }

    func testRecurringStopsAtUntilAndWhenPaused() throws {
        var l = ledger()
        let start = LocalDate(year: 2026, month: 1, day: 5)
        try l.addRecurring(expense(300, "咖啡", "餐饮", date: start), frequency: .weekly, until: LocalDate(year: 2026, month: 1, day: 20), author: "我")
        l.postDueRecurring(today: LocalDate(year: 2026, month: 3, day: 1), author: "我")
        XCTAssertEqual(l.transactions.count, 3)   // 5 号、12 号、19 号
        var r = l.recurring[0]
        r.paused = true
        r.until = nil
        try l.updateRecurring(r, author: "我")
        XCTAssertNil(l.postDueRecurring(today: LocalDate(year: 2026, month: 3, day: 1), author: "我"))
    }

    func testUndoAddRecurringRemovesRule() throws {
        var l = ledger()
        let c = try l.addRecurring(expense(1000, "话费", "通讯"), frequency: .monthly, author: "我")
        XCTAssertEqual(l.recurring.count, 1)
        try l.undo(changeID: c.id, author: "我")
        XCTAssertTrue(l.recurring.isEmpty)
        XCTAssertTrue(l.transactions.isEmpty)
    }

    func testRemoveRecurringAndUndo() throws {
        var l = ledger()
        try l.addRecurring(expense(1000, "话费", "通讯"), frequency: .monthly, author: "我")
        let id = l.recurring[0].id
        XCTAssertEqual(l.findRecurring("话费").map(\.id), [id])
        let c = try l.removeRecurring(id, author: "我")
        XCTAssertTrue(l.recurring.isEmpty)
        XCTAssertEqual(l.transactions.count, 1, "已经记上的不动")
        try l.undo(changeID: c.id, author: "我")
        XCTAssertEqual(l.recurring.map(\.id), [id])
    }

    func testMakeExistingRecurring() throws {
        var l = ledger()
        let t = expense(999, "健身房", "运动", date: LocalDate(year: 2026, month: 1, day: 10))
        try l.addTransaction(t, author: "我")
        try l.makeRecurring(t.id, frequency: .monthly, author: "我")
        XCTAssertEqual(l.recurring[0].nextDate, LocalDate(year: 2026, month: 2, day: 10))
    }

    func testRecurringSurvivesSQLite() throws {
        #if canImport(SQLite3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var l = ledger()
        var t = expense(65000, "房租", "住房")
        t.note = "备注"; t.tags = ["家"]
        try l.addRecurring(t, frequency: .monthly, author: "我")
        let store = SQLiteLedgerStore(url: url)
        try store.save(l)
        let back = try store.load()
        XCTAssertEqual(back.recurring, l.recurring)
        XCTAssertEqual(back.transactions[0].tags, ["家"])
        XCTAssertEqual(back.transactions[0].note, "备注")
        #endif
    }

    // MARK: 常记的

    func testFrequentEntries() throws {
        var l = ledger()
        let today = LocalDate(year: 2026, month: 3, day: 1)
        for k in 0..<3 { try l.addTransaction(expense(220, "咖啡", "餐饮", date: today.adding(days: -k)), author: "我") }
        try l.addTransaction(expense(4500, "一次性", "购物", date: today), author: "我")
        var imported = expense(999, "导入的", "购物", date: today)
        imported.source = "bank.csv"
        try l.addTransaction(imported, author: "AI")
        try l.addTransaction(expense(150, "很久以前", "餐饮", date: today.adding(days: -200)), author: "我")
        let f = l.frequentEntries(income: false, today: today)
        XCTAssertEqual(f.map(\.description), ["咖啡", "一次性"])
        XCTAssertEqual(f[0].amount.cents, -220)
        XCTAssertTrue(l.frequentEntries(income: true, today: today).isEmpty)
    }
}
