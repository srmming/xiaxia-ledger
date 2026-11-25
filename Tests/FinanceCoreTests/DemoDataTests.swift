import XCTest
@testable import FinanceCore

/// 示例账本：全是编的，要像一个真人一年的账，每个功能都有数据，数字合理。
final class DemoDataTests: XCTestCase {
    let end = LocalDate(year: 2026, month: 11, day: 20)
    lazy var l = DemoData.make(endingOn: end)

    func testSameSeedSameLedger() {
        XCTAssertEqual(DemoData.make(endingOn: end), DemoData.make(endingOn: end), "同一天同一个种子要生成一模一样的账本")
        XCTAssertNotEqual(DemoData.make(endingOn: end, seed: 7).transactions.map(\.amount),
                          l.transactions.map(\.amount), "换种子数字要变")
        XCTAssertTrue(DemoData.isDemo(l))
        XCTAssertFalse(DemoData.isDemo(.fresh))
    }

    func testWorksForAnyToday() {
        for day in [LocalDate(year: 2027, month: 1, day: 1), LocalDate(year: 2028, month: 2, day: 29), LocalDate(year: 2026, month: 3, day: 31)] {
            let x = DemoData.make(endingOn: day)
            XCTAssertGreaterThan(x.transactions.count, 800, "\(day)")
            XCTAssertTrue(x.transactions.allSatisfy { $0.date <= day }, "\(day) 有未来的流水")
            XCTAssertTrue(x.transactions.contains { $0.date.yearMonth == day.yearMonth }, "\(day) 本月没有数据")
        }
    }

    func testThirteenMonthsNoFuture() {
        XCTAssertTrue(l.transactions.allSatisfy { $0.date <= end })
        XCTAssertEqual(l.transactions.map(\.date).min(), LocalDate(year: 2025, month: 11, day: 1))
        let months = Set(l.transactions.map(\.date.yearMonth))
        XCTAssertEqual(months.count, 13)
        XCTAssertTrue(l.changes.allSatisfy { $0.createdAt <= Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 21))! })
        XCTAssertTrue(l.insights.allSatisfy { $0.createdAt <= Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 21))! })
    }

    /// 公开仓库、要上架：不能出现真实的店名、银行、商户。
    func testNothingReal() throws {
        let data = try JSONEncoder().encode(l)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        for word in ["miora", "caixa", "imagin", "revolut", "mercadona", "glovo", "amazon", "netflix", "spotify", "美甲"] {
            XCTAssertFalse(text.contains(word), "示例账本里出现了「\(word)」")
        }
    }

    func testEveryFeatureHasData() {
        XCTAssertEqual(l.books.map(\.name), ["个人", "我的小店"])
        XCTAssertTrue(l.books[1].isBusiness)
        XCTAssertEqual(Set(l.accounts.map(\.kind)), Set(AccountKind.allCases))
        XCTAssertEqual(l.accounts.filter(\.isPrivate).count, 1)
        let flows = Set(l.transactions.compactMap(\.flow))
        XCTAssertEqual(flows, [.debt, .saving, .opening, .internal])
        // 退款：花钱分类里的进账。
        let spending = Summaries.expenseCategories(l.transactions)
        XCTAssertGreaterThanOrEqual(l.transactions.filter { $0.flow == nil && $0.amount.isIncome && spending.contains($0.category ?? "") }.count, 3)
        // 账本间转账（同一个钱箱）和跨账本的账户互转（老板提款）。
        XCTAssertEqual(l.transactions.filter { $0.flow == nil && $0.isTransfer }.count, 2)
        XCTAssertFalse(Summaries.pairInternal(l.transactions).crossBook.isEmpty)
        XCTAssertTrue(Summaries.pairInternal(l.transactions).unpaired.isEmpty, "账户互转都要配得上对")
        // 借款：借出、借入、逾期、已还清。
        let debts = Plans.debts(l, today: end, includeClosed: true)
        XCTAssertEqual(Set(debts.map(\.direction)), [.theyOweMe, .iOweThem])
        XCTAssertTrue(debts.contains { $0.overdue })
        XCTAssertTrue(debts.contains { $0.outstanding == .zero })
        // 分期：一个有手续费、都在还。
        XCTAssertEqual(l.installments.count, 2)
        XCTAssertTrue(Plans.installments(l).allSatisfy { $0.paidCount > 0 && $0.paidCount < $0.count })
        XCTAssertTrue(l.transactions.contains { $0.category == "手续费" && $0.source == "分期购买" })
        // 目标：挂储蓄罐的、划出的、锁定的、店里的。
        let goals = Plans.goals(l)
        XCTAssertEqual(goals.count, 4)
        XCTAssertTrue(goals.allSatisfy { $0.percent > 0 && $0.percent < 100 }, "\(goals.map { ($0.name, $0.percent) })")
        XCTAssertTrue(l.goals.contains { $0.locked })
        XCTAssertTrue(l.goals.contains { $0.savingsAccountID != nil })
        // 夏夏建议：每种都有，有一条看过了。
        XCTAssertEqual(Set(l.insights.map(\.kind)), Set(Insight.Kind.allCases))
        XCTAssertEqual(l.insights(month: end.yearMonth).filter { $0.kind == .monthlyReview }.count, 2, "全部 + 小店各一条本月点评")
        XCTAssertNil(l.insights(month: end.yearMonth).first?.bookID, "看「全部」时第一条要是总的点评，不是小店的")
        XCTAssertTrue(l.insights.contains { $0.dismissedAt != nil })
        // 还没整理的。
        XCTAssertEqual(l.transactions.filter { $0.flow == nil && $0.category == nil && $0.bookID == nil }.count, 3)
        XCTAssertEqual(l.profile.categories.map(\.name), ["宠物"])
    }

    func testChangeHistory() throws {
        let kinds = Set(l.changes.map(\.kind))
        for k: ChangeRecord.Kind in [.add, .importBatch, .categorize, .assignBook, .transfer, .debt, .repay, .installment,
                                     .installmentPayment, .goal, .goalDeposit, .opening, .account, .edit, .subscription] {
            XCTAssertTrue(kinds.contains(k), "改动记录里没有 \(k)")
        }
        XCTAssertTrue(l.changes.contains { $0.undone }, "要有一条撤销过的")
        XCTAssertGreaterThanOrEqual(Set(l.changes.map(\.author)).count, 4)
        XCTAssertEqual(l.changes.map(\.createdAt), l.changes.map(\.createdAt).sorted(), "改动记录按时间排")
        // 每笔流水都能在改动记录里找到来历。
        let traced = Set(l.changes.filter { !$0.undone }.flatMap(\.transactionIDs))
        let untraced = l.transactions.filter { !traced.contains($0.id) }
        XCTAssertTrue(untraced.isEmpty, "这些流水没有改动记录：\(untraced.prefix(3).map(\.description))")
        // 最近一批导入能撤销。
        var copy = l
        let last = try XCTUnwrap(copy.changes.last { $0.kind == .importBatch && $0.canUndo })
        let before = copy.transactions.count
        try copy.undo(changeID: last.id, author: "测试")
        XCTAssertEqual(copy.transactions.count, before - last.transactionIDs.count)
    }

    /// 数字要像真的：账户不透支、每个月店里有进账、全部合起来大多数月份有结余。
    func testNumbersAreReasonable() {
        let sorted = l.transactions
        for account in l.accounts where account.kind != .credit {
            var running = Money.zero
            for t in sorted where t.accountID == account.id {
                running = running + t.amount
                XCTAssertGreaterThanOrEqual(running.cents, 0, "\(account.name) 在 \(t.date) 透支了")
            }
        }
        // 信用卡每月还清，欠的只有这个月刷的。
        let credit = Summaries.balances(l.transactions)["credit"] ?? .zero
        XCTAssertLessThan(credit.magnitude.cents, 120_000)
        let months = Set(l.transactions.map(\.date.yearMonth)).sorted().dropLast()
        let base = l.baseTransactions
        var positive = 0
        for m in months {
            let all = Summaries.monthly(base, month: m, bookID: nil, hiddenAccounts: l.privateAccountIDs)
            let shop = Summaries.monthly(base, month: m, bookID: DemoData.shopBookID)
            let me = Summaries.monthly(base, month: m, bookID: "personal")
            XCTAssertGreaterThan(shop.income.cents, 300_000, "\(m) 店里进账太少")
            XCTAssertGreaterThan(me.income.cents, 130_000, "\(m) 个人收入太少")
            XCTAssertTrue((150_000...900_000).contains(all.expense.magnitude.cents), "\(m) 花了 \(all.expense.formatted)")
            XCTAssertEqual(me.betweenBooks.cents, 70_000, "\(m) 老板提款应该是 700 €")
            XCTAssertNil(all.byCategory["未分类"], "\(m) 有没分类的")
            if all.net.cents > 0 { positive += 1 }
        }
        XCTAssertGreaterThanOrEqual(positive, 8, "大多数月份要有结余")
    }

    /// 多币种和订阅：一个美元账户（每笔都记了汇率），欧元卡刷外币记了原价；订阅有涨价的、停了的、年付的、美元的，还有一个没登记的等着被认出来。
    func testCurrencyAndSubscriptions() {
        XCTAssertEqual(l.baseCurrency, "EUR")
        XCTAssertEqual(l.accounts.filter { $0.currency == "USD" }.count, 1)
        let usd = l.transactions.filter { $0.accountID == "usd" }
        XCTAssertGreaterThan(usd.count, 10)
        XCTAssertTrue(usd.allSatisfy { $0.fx?.source == "ecb" }, "美元账户每笔都要有汇率")
        XCTAssertTrue(l.missingRateCurrencies.isEmpty)
        XCTAssertTrue(l.transactions.contains { $0.original?.currency == "USD" })
        let subs = Subscriptions.status(l, today: end)
        XCTAssertEqual(subs.count, 7)
        XCTAssertEqual(subs.filter { $0.cancelledOn != nil }.count, 1)
        XCTAssertTrue(subs.contains { $0.cycle == .yearly })
        XCTAssertTrue(subs.contains { $0.currency == "USD" })
        XCTAssertEqual(subs.filter(\.priceChanged).map(\.name), ["StreamBox 视频会员"])
        XCTAssertTrue(subs.filter { $0.cancelledOn == nil }.allSatisfy { $0.chargeCount > 0 }, "登记的订阅在流水里都要有扣款")
        XCTAssertTrue(Subscriptions.detect(l, today: end).contains { $0.key.hasPrefix("linguapal") }, "没登记的语言课要能被认出来")
    }

    /// app 和 fin 能存能读：SQLite 存一遍读回来一样。
    func testRoundTripsThroughStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = JSONFileLedgerStore(url: dir.appendingPathComponent("demo.json"))
        XCTAssertThrowsError(try json.save(l))
        #if canImport(SQLite3)
        let db = SQLiteLedgerStore(url: dir.appendingPathComponent("demo.sqlite"))
        try db.save(l)
        XCTAssertEqual(try db.load(), l)
        #endif
    }
}
