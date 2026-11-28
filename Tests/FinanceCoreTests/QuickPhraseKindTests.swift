import XCTest
@testable import FinanceCore

/// 「说一句」认方向：花了、收了、还钱、转账、借给别人、别人还我；说了「店里」记到生意那边。
final class QuickPhraseKindTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    func testParseTellsTheKinds() {
        XCTAssertEqual(QuickPhrase.parse("午饭 12,5")?.kind, .spend)
        XCTAssertEqual(QuickPhrase.parse("还信用卡 640")?.kind, .repay(to: "信用卡"))
        XCTAssertEqual(QuickPhrase.parse("信用卡还了 640")?.kind, .repay(to: "信用卡"))
        XCTAssertEqual(QuickPhrase.parse("还阿青 100")?.kind, .repay(to: "阿青"))
        XCTAssertEqual(QuickPhrase.parse("店里收了 200")?.kind, .income); XCTAssertEqual(QuickPhrase.parse("店里收了 200")?.shop, true)
        XCTAssertEqual(QuickPhrase.parse("今天发工资 1850")?.kind, .income); XCTAssertEqual(QuickPhrase.parse("今天发工资 1850")?.shop, false)
        XCTAssertEqual(QuickPhrase.parse("卖了旧手机 80")?.kind, .income)
        XCTAssertEqual(QuickPhrase.parse("转 200 到储蓄")?.kind, .transfer(to: "储蓄"))
        XCTAssertEqual(QuickPhrase.parse("借给小李 50")?.kind, .lend(to: "小李"))
        XCTAssertEqual(QuickPhrase.parse("小李还我 50")?.kind, .repaidToMe(from: "小李"))
        XCTAssertEqual(QuickPhrase.parse("小李还了我 50")?.kind, .repaidToMe(from: "小李"))
        XCTAssertEqual(QuickPhrase.parse("向阿青借了 500")?.kind, .borrow(from: "阿青"))
        XCTAssertEqual(QuickPhrase.parse("跟阿青借 500")?.kind, .borrow(from: "阿青"))
        XCTAssertEqual(QuickPhrase.parse("阿青借我 500")?.kind, .borrow(from: "阿青"))
        XCTAssertEqual(QuickPhrase.parse("店里买了胶带 12")?.kind, .spend); XCTAssertEqual(QuickPhrase.parse("店里买了胶带 12")?.shop, true)
        XCTAssertEqual(QuickPhrase.parse("咖啡 3,5")?.name, "咖啡")
        // 哪些话算在说一笔账
        XCTAssertTrue(QuickPhrase.isBookkeeping("还信用卡 640")); XCTAssertTrue(QuickPhrase.isBookkeeping("店里收了 200"))
        XCTAssertTrue(QuickPhrase.isBookkeeping("记一笔午饭 12,5")); XCTAssertTrue(QuickPhrase.isBookkeeping("转 200 到储蓄"))
        XCTAssertFalse(QuickPhrase.isBookkeeping("这个耳机 200 值得买吗")); XCTAssertFalse(QuickPhrase.isBookkeeping("这个月还能花多少"))
    }

    func testRecordingEachKindMovesTheRightNumbers() throws {
        var b = TrialBook.demo
        let pay = "日常卡"
        let month = b.month, net = b.totals.net
        func bal(_ n: String) -> Money { b.account(n)?.balance ?? .zero }
        // 还信用卡：不算花销，净剩不变
        let card = bal("信用卡"), daily = bal(pay)
        XCTAssertTrue(try b.record(QuickPhrase.parse("还信用卡 100")!, account: pay).contains("不算花销"))
        XCTAssertEqual(bal("信用卡"), card - eur("100")); XCTAssertEqual(bal(pay), daily - eur("100"))
        XCTAssertEqual(b.month.spentTotal, month.spentTotal); XCTAssertEqual(b.totals.net, net)
        // 店里收了 200：进店里的账户，这天的营业额多 200；生活的进账、花销都不变
        let shop = b.shopHeld.first!.name, shopBal = bal(shop), day = b.shopDays.first { $0.day == b.todayDay }?.total ?? .zero
        try b.record(QuickPhrase.parse("店里收了 200")!, account: pay)
        XCTAssertEqual(bal(shop), shopBal + eur("200"))
        XCTAssertEqual(b.shopDays.first { $0.day == b.todayDay }?.total, day + eur("200"))
        XCTAssertEqual(b.month.income, month.income); XCTAssertEqual(b.month.spentTotal, month.spentTotal)
        // 工资：是收入，不是支出
        try b.record(QuickPhrase.parse("发工资 1850")!, account: pay)
        XCTAssertEqual(b.month.income, month.income + eur("1850")); XCTAssertEqual(b.month.spentTotal, month.spentTotal)
        // 转 50 到储蓄：两个账户之间挪，不算花销
        let savings = b.accounts.first { $0.name.contains("储蓄") }!.name, was = bal(savings), d2 = bal(pay)
        try b.record(QuickPhrase.parse("转 50 到储蓄")!, account: pay)
        XCTAssertEqual(bal(savings), was + eur("50")); XCTAssertEqual(bal(pay), d2 - eur("50"))
        XCTAssertEqual(b.month.spentTotal, month.spentTotal)
        // 借给小李 50，小李还我 20：都不算收支，净剩不变
        // （示例里小李本来就欠着一笔：加在同一行上，不另开一行）
        let n2 = b.totals.net, d3 = bal(pay), li = bal("借给小李"), rows = b.accounts.count
        try b.record(QuickPhrase.parse("借给小李 50")!, account: pay)
        XCTAssertEqual(bal("借给小李"), li + eur("50")); XCTAssertEqual(bal(pay), d3 - eur("50")); XCTAssertEqual(b.totals.net, n2)
        XCTAssertEqual(b.accounts.count, rows)
        try b.record(QuickPhrase.parse("小李还我 20")!, account: pay)
        XCTAssertEqual(bal("借给小李"), li + eur("30")); XCTAssertEqual(bal(pay), d3 - eur("30")); XCTAssertEqual(b.totals.net, n2)
        // 借给一个新的人：多一行
        try b.record(QuickPhrase.parse("借给阿树 15")!, account: pay)
        XCTAssertEqual(bal("借给阿树"), eur("15")); XCTAssertEqual(b.totals.net, n2)
        XCTAssertEqual(b.month.spentTotal, month.spentTotal); XCTAssertEqual(b.month.income, month.income + eur("1850"))
        // 向阿树借了 80：钱进来了，但欠着，不算收入，净剩不变
        let n3 = b.totals.net, d4 = bal(pay), inc3 = b.month.income
        XCTAssertTrue(try b.record(QuickPhrase.parse("向阿树爸借了 80")!, account: pay).contains("不算收入"))
        XCTAssertEqual(bal(pay), d4 + eur("80")); XCTAssertEqual(bal("阿树爸"), eur("80"))
        XCTAssertEqual(b.totals.net, n3); XCTAssertEqual(b.month.income, inc3)
        // 说不清的：不猜，说人话，什么都不动
        let keep = b
        XCTAssertThrowsError(try b.record(QuickPhrase.parse("还阿毛 10")!, account: pay))
        XCTAssertThrowsError(try b.record(QuickPhrase.parse("转 10 到火星")!, account: pay))
        XCTAssertThrowsError(try b.record(QuickPhrase.parse("小张还我 10")!, account: pay))
        XCTAssertEqual(b, keep)
        // 只管生活时说「店里」：照样记在生活这边
        var lifeOnly = TrialBook.demo
        try lifeOnly.setSides(life: true, biz: false)
        let inc = lifeOnly.month.income
        try lifeOnly.record(QuickPhrase.parse("店里收了 200")!, account: pay)
        XCTAssertEqual(lifeOnly.month.income, inc + eur("200"))
    }

    /// 接着正式账本：这几句写进去的是还款 / 收入 / 转账 / 借款，不是支出。
    func testTheSamePhrasesOnTheRealLedger() throws {
        let today = LocalDate(year: 2026, month: 11, day: 18)
        var l = DemoData.make(endingOn: today)
        func say(_ text: String) throws -> [ChangeRecord] {
            let before = LedgerBridge.snapshot(of: l, today: today)
            let pay = before.accounts(for: .pay, side: .life).first { $0.kind == .own && $0.balance > Money(cents: 1000_00) }!.name
            var after = before
            try after.record(QuickPhrase.parse(text)!, account: pay)
            return try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "小晴")
        }
        let spent = LedgerBridge.snapshot(of: l, today: today).month.spentTotal
        let income = LedgerBridge.snapshot(of: l, today: today).month.income
        try XCTAssertEqual(say("还信用卡 100").last?.kind, .transfer)
        XCTAssertEqual(LedgerBridge.snapshot(of: l, today: today).month.spentTotal, spent, "还信用卡不算花销")
        _ = try say("借给小李 50")
        XCTAssertEqual(l.debts.last?.counterparty, "小李"); XCTAssertEqual(l.transactions.last?.flow, .debt)
        _ = try say("小李还我 20")
        _ = try say("借给小李 10")
        let b = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(b.month.spentTotal, spent); XCTAssertEqual(b.month.income, income, "借出去、还回来都不算收支")
        let debts = l.debts.count
        _ = try say("向阿青借了 300")
        XCTAssertEqual(l.debts.count, debts + 1); XCTAssertEqual(l.debts.last?.direction, .iOweThem)
        XCTAssertEqual(l.transactions.last?.amount, Money(cents: 300_00)); XCTAssertEqual(l.transactions.last?.flow, .debt)
        XCTAssertEqual(LedgerBridge.snapshot(of: l, today: today).month.income, income, "借来的钱不算收入")
        _ = try say("发工资 500")
        XCTAssertEqual(LedgerBridge.snapshot(of: l, today: today).month.income, income + Money(cents: 500_00))
        XCTAssertEqual(l.transactions.last?.amount, Money(cents: 500_00))
    }
}
