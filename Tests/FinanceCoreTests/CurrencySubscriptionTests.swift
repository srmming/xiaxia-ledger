import XCTest
@testable import FinanceCore

// 多币种和订阅。测试只用编造的数字。
final class CurrencyTests: XCTestCase {
    func d(_ m: Int, _ day: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: day) }

    /// 一个欧元账户 + 一个美元账户，汇率表：10 月 1 日 1 € = 1,10 US$，10 月 15 日 1 € = 1,25 US$。
    func sample() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "eur", name: "欧元卡", kind: .bank), Account(id: "usd", name: "美元卡", kind: .bank, currency: "usd")]
        l.currency.rates = ["USD": [RatePoint(date: d(10, 1), perEUR: 1.10), RatePoint(date: d(10, 15), perEUR: 1.25)],
                            "CNY": [RatePoint(date: d(10, 1), perEUR: 8.0)]]
        l.transactions = [
            Transaction(date: d(10, 3), amount: Money(cents: -1000), description: "超市", accountID: "eur", bookID: "personal", category: "超市"),
            Transaction(date: d(10, 3), amount: Money(cents: -1100), description: "Diner", accountID: "usd", bookID: "personal", category: "餐饮"),
            Transaction(date: d(10, 20), amount: Money(cents: 2500), description: "Refund salary", accountID: "usd", bookID: "personal", category: "工资"),
        ]
        return l
    }

    override func tearDown() { Money.defaultCurrency = "EUR" }

    func testFormatInOtherCurrencies() {
        XCTAssertEqual(Money(cents: 123456).formatted(in: "USD"), "1.234,56 US$")
        XCTAssertEqual(Money(cents: -123456).formatted(in: "JPY"), "-1.235 JP¥")
        XCTAssertEqual(Money(cents: 5).formatted(in: "EUR"), "0,05 €")
        XCTAssertEqual(Money(cents: 100).formatted, "1,00 €")
    }

    func testOldLedgersUnchanged() {
        var l = sample()
        l.accounts.removeLast()
        l.transactions.removeAll { $0.accountID == "usd" }
        XCTAssertFalse(l.hasForeignAccounts)
        XCTAssertEqual(l.baseTransactions, l.transactions)
    }

    func testConvertsWithRateOfThatDay() {
        let l = sample()
        let base = l.baseTransactions
        XCTAssertEqual(base[0].amount.cents, -1000)                 // 欧元不变
        XCTAssertEqual(base[1].amount.cents, -1000)                 // 11 US$ / 1,10 = 10 €
        XCTAssertEqual(base[2].amount.cents, 2000)                  // 25 US$ / 1,25 = 20 €（用 10 月 15 日的）
        let s = Summaries.monthly(base, month: YearMonth(year: 2026, month: 10), bookID: nil)
        XCTAssertEqual(s.expense.cents, -2000)
        XCTAssertEqual(s.income.cents, 2000)
    }

    func testStoredFXWinsAndBankRate() throws {
        var l = sample()
        l.fillMissingFX()
        XCTAssertEqual(l.transactions[1].fx?.rate ?? 0, 1 / 1.10, accuracy: 1e-9)
        XCTAssertNil(l.transactions[0].fx)
        // 汇率表后来又变了，记下时存的汇率不变。
        l.currency.rates["USD"] = [RatePoint(date: d(10, 1), perEUR: 2.0)]
        XCTAssertEqual(l.baseAmount(l.transactions[1]).cents, -1000)
        // 银行实际扣了 10,50 €。
        try l.setRate(l.transactions[1].id, bankAmount: Money(cents: 1050), author: "ming")
        XCTAssertEqual(l.baseAmount(l.transactions[1]).cents, -1050)
        XCTAssertEqual(l.transactions[1].fx?.source, "bank")
        try l.undo(changeID: l.changes.last!.id, author: "ming")
        XCTAssertEqual(l.baseAmount(l.transactions[1]).cents, -1000)
    }

    func testChangeBaseCurrencyKeepsAmountsAndUndo() throws {
        var l = sample()
        let before = l.transactions
        try l.setBaseCurrency("USD", author: "ming")
        XCTAssertEqual(l.transactions.map(\.amount), before.map(\.amount))   // 金额一分没动
        XCTAssertEqual(l.currency(ofAccount: "eur"), "EUR")
        XCTAssertEqual(l.currency(ofAccount: "usd"), "USD")
        XCTAssertEqual(l.baseAmount(l.transactions[0]).cents, -1100)          // 10 € × 1,10
        XCTAssertEqual(Money(cents: 100).formatted, "1,00 US$")
        try l.undo(changeID: l.changes.last!.id, author: "ming")
        XCTAssertEqual(l.baseCurrency, "EUR")
        XCTAssertNil(l.accounts[0].currency)
        XCTAssertEqual(l.accounts[1].currency, "USD")
        XCTAssertEqual(Money(cents: 100).formatted, "1,00 €")
    }

    func testCrossRateViaEuro() {
        let l = sample()
        let r = l.currency.rate(from: "USD", to: "CNY", on: d(10, 5))!
        XCTAssertEqual(r.rate, 8.0 / 1.10, accuracy: 1e-9)
    }

    func testMissingRateFallsBackAndIsReported() {
        var l = sample()
        l.currency.rates = [:]
        XCTAssertEqual(l.missingRateCurrencies, ["USD"])
        XCTAssertEqual(l.baseAmount(l.transactions[1]).cents, -1100)
        XCTAssertTrue(l.needsRateRefresh)
    }

    func testSetAccountCurrency() throws {
        var l = sample()
        try l.setAccountCurrency("eur", "CNY", author: "ming")
        XCTAssertEqual(l.currency(ofAccount: "eur"), "CNY")
        XCTAssertEqual(l.transactions[0].amount.cents, -1000)
        XCTAssertNotNil(l.transactions[0].fx)
        try l.undo(changeID: l.changes.last!.id, author: "ming")
        XCTAssertNil(l.accounts[0].currency)
        XCTAssertNil(l.transactions[0].fx)
        XCTAssertThrowsError(try l.setAccountCurrency("eur", "XXX", author: "ming"))
    }

    func testParseECB() {
        let xml = """
        <gesmes:Envelope><Cube><Cube time='2026-11-20'><Cube currency='USD' rate='1.0573'/><Cube currency='CNY' rate='7.6543'/></Cube>
        <Cube time="2026-11-19"><Cube currency="USD" rate="1.0500"/></Cube></Cube></gesmes:Envelope>
        """
        let t = ECBRates.parse(xml)
        XCTAssertEqual(t["USD"]?.count, 2)
        XCTAssertEqual(t["USD"]?.first?.date, d(11, 19))
        XCTAssertEqual(t["CNY"]?.first?.perEUR ?? 0, 7.6543, accuracy: 1e-9)
        var l = sample()
        l.applyRates(t)
        XCTAssertEqual(l.currency.rates["USD"]?.last?.perEUR ?? 0, 1.0573, accuracy: 1e-9)
        XCTAssertEqual(l.currency.rates["USD"]?.count, 4)
        XCTAssertNotNil(l.currency.updatedAt)
    }

    func testAccountBalancesNativeAndBase() {
        var l = sample()
        l.currency.rates["USD"] = [RatePoint(date: d(1, 1), perEUR: 2.0)]
        let b = l.accountBalances(asOf: d(11, 1))
        XCTAssertEqual(b["usd"]?.native.cents, 1400)
        XCTAssertEqual(b["usd"]?.base.cents, 700)
        XCTAssertEqual(l.formatted(l.transactions[1]), "-11,00 US$")
    }

    func testSQLiteRoundTripKeepsCurrencyAndSubscriptions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fx-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var l = sample()
        l.fillMissingFX()
        l.transactions[0].original = ForeignAmount(amount: Money(cents: 1200), currency: "usd")
        try l.addSubscription(Subscription(name: "Netflix", amount: Money(cents: 1399), cycle: .monthly, nextDate: d(11, 5), accountID: "eur"), author: "ming")
        let store = SQLiteLedgerStore(url: url)
        try store.save(l)
        let back = try store.load()
        XCTAssertEqual(back.currency, l.currency)
        XCTAssertEqual(back.accounts, l.accounts)
        XCTAssertEqual(back.transactions, l.transactions)
        XCTAssertEqual(back.subscriptions, l.subscriptions)
        XCTAssertEqual(back.transactions[0].original?.formatted, "12,00 US$")
    }

    func testUnknownChangeKindStillReads() throws {
        let json = #"{"id":"6F1D2C3B-0000-4000-8000-000000000001","kind":"fromTheFuture","summary":"x","transactionIDs":[],"author":"AI","createdAt":"2026-11-20T10:00:00Z","undone":false}"#
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(ChangeRecord.self, from: Data(json.utf8)).kind, .edit)
    }
}

final class SubscriptionTests: XCTestCase {
    func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day) }
    let today = LocalDate(year: 2026, month: 11, day: 20)

    func ledger() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "card", name: "卡", kind: .bank)]
        var txs: [Transaction] = []
        // 视频会员：每月 3 号 12,99，最近一次涨到 13,99
        for m in 6...11 {
            txs.append(Transaction(date: d(2026, m, 3), amount: Money(cents: m == 11 ? -1399 : -1299), description: "NETFLIX.COM 866-579",
                                   accountID: "card", bookID: "personal", category: "娱乐"))
        }
        // 云盘：每年
        txs.append(Transaction(date: d(2024, 12, 1), amount: Money(cents: -2999), description: "CLOUDBOX ANNUAL", accountID: "card", bookID: "personal"))
        txs.append(Transaction(date: d(2025, 12, 2), amount: Money(cents: -2999), description: "CLOUDBOX ANNUAL", accountID: "card", bookID: "personal"))
        // 超市：经常去，金额乱，不是订阅
        for (i, day) in [2, 5, 9, 14, 20, 26].enumerated() {
            for m in 9...11 { txs.append(Transaction(date: d(2026, m, day), amount: Money(cents: -1000 - Int64(i * 777)), description: "MERCADONA", accountID: "card")) }
        }
        // 固定开销：每月同一天同一个数，但不是订阅（有分类的看分类，没分类的看描述）
        for m in 6...11 {
            txs.append(Transaction(date: d(2026, m, 1), amount: Money(cents: -90000), description: "ALQUILER PISO", accountID: "card", category: "房租"))
            txs.append(Transaction(date: d(2026, m, 28), amount: Money(cents: -150000), description: "NOMINA EMPLEADA", accountID: "card"))
            txs.append(Transaction(date: d(2026, m, 5), amount: Money(cents: -5480), description: "ABONO TRANSPORTE", accountID: "card"))
        }
        for m in [1, 4, 7, 10] { txs.append(Transaction(date: d(2026, m, 20), amount: Money(cents: -61200), description: "AEAT IVA TRIMESTRAL", accountID: "card")) }
        // 健身房：停了（最后一次是 6 月）
        for m in 2...6 { txs.append(Transaction(date: d(2026, m, 10), amount: Money(cents: -2990), description: "GYMFIT", accountID: "card")) }
        l.transactions = txs
        return l
    }

    func testDateMath() {
        XCTAssertEqual(d(2026, 1, 31).adding(months: 1), d(2026, 2, 28))
        XCTAssertEqual(d(2026, 12, 30).adding(days: 3), d(2027, 1, 2))
        XCTAssertEqual(d(2026, 11, 1).days(until: d(2026, 12, 1)), 30)
        XCTAssertEqual(LocalDate.daysIn(YearMonth(year: 2028, month: 2)), 29)
    }

    func testDetect() {
        let found = Subscriptions.detect(ledger(), today: today)
        XCTAssertEqual(found.map(\.key).sorted(), ["cloudboxannual", "netflix"])
        let nf = found.first { $0.key == "netflix" }!
        XCTAssertEqual(nf.cycle, .monthly)
        XCTAssertEqual(nf.nextDate, d(2026, 12, 3))
        XCTAssertEqual(nf.amount.cents, 1399)
        XCTAssertEqual(nf.name, "Netflix")
        let cb = found.first { $0.key == "cloudboxannual" }!
        XCTAssertEqual(cb.cycle, .yearly)
        XCTAssertEqual(cb.nextDate, d(2026, 12, 2))
    }

    func testRegisterStatusTotalsAndUndo() throws {
        var l = ledger()
        let nf = Subscriptions.detect(l, today: today).first { $0.key == "netflix" }!
        var s = nf.subscription()
        s.amount = Money(cents: 1299)
        s.nextDate = d(2026, 7, 3)          // 登记时写的日子早过了：显示时自动往后推
        try l.addSubscription(s, author: "Claude")
        try l.addSubscription(Subscription(name: "云盘", amount: Money(cents: 3000), cycle: .yearly, nextDate: d(2026, 12, 2), match: "cloudbox"), author: "Claude")
        XCTAssertTrue(Subscriptions.detect(l, today: today).isEmpty)   // 登记过的不再列
        let st = Subscriptions.status(l, today: today)
        XCTAssertEqual(st.map(\.name), ["云盘", "Netflix"])
        let n = st[1]
        XCTAssertEqual(n.nextDate, d(2026, 12, 3))
        XCTAssertEqual(n.daysLeft, 13)
        XCTAssertTrue(n.priceChanged)
        XCTAssertEqual(n.lastChargeAmount?.cents, 1399)
        XCTAssertEqual(n.chargeCount, 6)
        let t = Subscriptions.totals(st)
        XCTAssertEqual(t.monthly.cents, 1299 + 250)
        XCTAssertEqual(t.yearly.cents, 1299 * 12 + 3000)
        XCTAssertEqual(t.activeCount, 2)

        try l.cancelSubscription(n.id, on: today, author: "ming")
        XCTAssertEqual(Subscriptions.totals(Subscriptions.status(l, today: today)).activeCount, 1)
        XCTAssertThrowsError(try l.cancelSubscription(n.id, author: "ming"))
        try l.undo(changeID: l.changes.last!.id, author: "ming")
        XCTAssertTrue(l.subscriptions.first { $0.id == n.id }!.isActive)

        let found = try l.findSubscription("netf")
        XCTAssertEqual(found.id, n.id)
        try l.removeSubscription(found.id, author: "ming")
        XCTAssertEqual(l.subscriptions.count, 1)
        try l.undo(changeID: l.changes.last!.id, author: "ming")
        XCTAssertEqual(l.subscriptions.count, 2)
        // 撤销「登记」：删掉
        let addChange = l.changes.first { $0.kind == .subscription }!
        try l.undo(changeID: addChange.id, author: "ming")
        XCTAssertEqual(l.subscriptions.map(\.name), ["云盘"])
    }

    func testForeignSubscriptionConvertsToBase() throws {
        var l = ledger()
        l.currency.rates["USD"] = [RatePoint(date: d(2026, 1, 1), perEUR: 2.0)]
        try l.addSubscription(Subscription(name: "AI 会员", amount: Money(cents: 2000), currency: "USD", cycle: .monthly, nextDate: d(2026, 12, 1)), author: "ming")
        let st = Subscriptions.status(l, today: today)
        XCTAssertEqual(st[0].currency, "USD")
        XCTAssertEqual(st[0].monthlyBase.cents, 1000)
        XCTAssertThrowsError(try l.addSubscription(Subscription(name: "x", amount: .zero, cycle: .monthly, nextDate: today), author: "ming"))
    }

    func testCycleText() {
        XCTAssertEqual(Subscription.Cycle(text: "每年"), .yearly)
        XCTAssertEqual(Subscription.Cycle(text: "monthly"), .monthly)
        XCTAssertNil(Subscription.Cycle(text: "biweekly"))
    }
}
