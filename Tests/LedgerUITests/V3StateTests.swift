#if os(macOS)
import FinanceCore
import XCTest
@testable import LedgerUI

/// 界面 v3 开发版：点了按钮以后数字对不对、撤销回不回得去。数字全是编的示例。
@MainActor
final class V3StateTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    func testDemoNumbersMatchTheDesign() {
        let s = V3State()
        XCTAssertEqual(s.book.month.left, eur("976,61"))
        XCTAssertEqual(s.book.totals.have, eur("8420"))
        XCTAssertEqual(s.book.totals.owe, eur("1840"))
        XCTAssertEqual(s.book.totals.net, eur("6580"))
        XCTAssertEqual(s.book.journey.remainingToNext, eur("181"))
        XCTAssertEqual(s.book.runway.monthsText, "2,8")
        // 四块加起来就是「一共有」；私房钱、借出去的不算
        let blocks = s.book.sum(.daily) + s.book.sum(.emergency) + s.book.sum(.goal) + s.book.sum(.shop)
        XCTAssertEqual(blocks, s.book.totals.have)
    }

    func testRecordThenUndo() {
        let s = V3State()
        let before = s.book
        s.record(QuickPhrase(name: "咖啡", emoji: "☕", amount: eur("3,20")), account: "现金", place: "Café Nube")
        XCTAssertEqual(s.book.month.left, eur("973,41"))
        XCTAssertEqual(s.book.today.first?.name, "咖啡")
        XCTAssertEqual(s.book.accounts.first { $0.name == "现金" }?.balance, eur("81,80"))
        XCTAssertEqual(s.toast?.canUndo, true)
        XCTAssertEqual(s.ledger.changes.first?.author, "你")
        XCTAssertEqual(s.ledger.changes.first?.kind, .add)
        s.undo()
        XCTAssertEqual(s.book, before)
        XCTAssertEqual(s.ledger.changes.first?.undone, true)
        XCTAssertNil(s.ledger.lastUndoable)
        // 没东西可撤时不出错
        s.undo()
        XCTAssertEqual(s.book, before)
    }

    func testDepositMovesMoneyAndDropsAStar() {
        let s = V3State()
        let net = s.book.totals.net
        XCTAssertTrue(s.deposit().isEmpty)
        XCTAssertEqual(s.book.journey.saved, eur("539"))
        XCTAssertEqual(s.book.accounts.first { $0.block == .goal }?.balance, eur("539"))
        XCTAssertEqual(s.book.accounts.first { $0.name == "日常卡" }?.balance, eur("1476,61"))
        XCTAssertEqual(s.book.totals.net, net, "自己账户之间挪钱，净剩不变")
        XCTAssertEqual(s.starDrops, 1)
        // 存够这一站：到 700 那一站
        let reached = s.deposit(s.book.journey.remainingToNext)
        XCTAssertEqual(reached.map(\.target), [eur("700")])
        let letter = s.arrivalLetter(for: reached[0])
        XCTAssertTrue(letter.tag.contains("700"))
        XCTAssertFalse(letter.paragraphs.isEmpty)
    }

    func testHalfGoesToEmergencyWhenAgreed() {
        let s = V3State()
        s.change("好，以后存钱自动对半分") { $0.splitWithEmergency = true }
        s.deposit(eur("20"))
        XCTAssertEqual(s.book.journey.saved, eur("529"))
        XCTAssertEqual(s.book.sum(.emergency), eur("2410"))
    }

    func testAddAccountChangesTotals() {
        let s = V3State()
        s.addAccount(emoji: "🤝", name: "跟朋友借的", note: "欠的钱", balance: eur("300"), kind: .debt)
        XCTAssertEqual(s.book.totals.owe, eur("2140"))
        XCTAssertEqual(s.book.totals.net, eur("6280"))
        s.addAccount(emoji: "🧑", name: "借给小王", note: "别人欠我", balance: eur("50"), kind: .lent)
        XCTAssertEqual(s.book.totals.have, eur("8420"), "借出去的收回来之前不算进一共有")
    }

    func testOnboardingStepsAndFirstStepMoment() {
        let s = V3State()
        XCTAssertEqual(s.onboardingStep, 0)
        for _ in 0..<4 { s.nextStep() }
        XCTAssertEqual(s.onboardingStep, 4)
        s.previousStep()
        XCTAssertEqual(s.onboardingStep, 3)
        s.nextStep(); s.nextStep()
        XCTAssertNil(s.onboardingStep)
        XCTAssertNil(s.moment, "没连 AI：直接进总览")

        let t = V3State()
        t.ai = "Claude"
        for _ in 0..<5 { t.nextStep() }
        XCTAssertEqual(t.moment, .firstStep, "连了 AI：进去先定第一步")
    }

    func testMonthNames() {
        XCTAssertEqual(V3State.monthName(after: 1), "12 月")
        XCTAssertEqual(V3State.monthName(after: 5), "明年 4 月")
        XCTAssertEqual(V3State.monthName(after: 14), "2028 年 1 月")
    }

    func testRulesComeFromTheCoreAndFailuresSayWhy() {
        let s = V3State()
        let before = s.book
        // 存的比账户里的多：什么都不变，底下说清为什么
        XCTAssertTrue(s.deposit(eur("5000")).isEmpty)
        XCTAssertEqual(s.book, before)
        XCTAssertEqual(s.toast?.isError, true)
        XCTAssertEqual(s.toast?.canUndo, false)
        XCTAssertEqual(s.starDrops, 0)
        XCTAssertNil(s.ledger.lastUndoable)
    }

    func testDeleteRecategorizeAndUndoFromTheLog() {
        let s = V3State()
        let start = s.book
        let lumi = s.book.entries.first { $0.place == "Super Lumi" }!
        XCTAssertTrue(s.change("归好了", kind: .categorize) { try $0.recategorize(entry: lumi.id, emoji: "🛒", name: "超市", always: true) })
        XCTAssertEqual(s.book.entries.first { $0.id == lumi.id }?.name, "超市")
        let afterFirst = s.book
        let coffee = s.book.today.first { $0.name == "咖啡" }!
        XCTAssertTrue(s.change("删掉了", kind: .remove) { try $0.delete(entry: coffee.id) })
        XCTAssertEqual(s.book.month.left, eur("979,81"))
        XCTAssertEqual(s.book.account("现金")?.balance, eur("88,20"))
        s.undo()
        XCTAssertEqual(s.book, afterFirst)
        // 在改动记录里撤销更早的一条：它后面的也一起撤回
        s.record(QuickPhrase(name: "打车", emoji: "🚕", amount: eur("15")), account: "日常卡")
        let first = s.ledger.changes.first { $0.kind == .categorize && !$0.undone && s.ledger.canUndo($0.id) }!
        s.undo(change: first.id)
        XCTAssertEqual(s.book, start)
    }

    func testShopDayFixedCostAndTransfer() {
        let s = V3State()
        let shop = s.book.account("小店账户")!.balance
        XCTAssertTrue(s.change("记好了") { try $0.recordShopDay(18, cash: self.eur("74"), card: self.eur("112")) })
        XCTAssertEqual(s.book.shopDays.first { $0.day == 18 }?.total, eur("186"))
        XCTAssertEqual(s.book.account("小店账户")?.balance, shop + eur("186"))
        // 改同一天：只算差的
        XCTAssertTrue(s.change("改好了") { try $0.recordShopDay(18, cash: self.eur("74"), card: self.eur("100")) })
        XCTAssertEqual(s.book.account("小店账户")?.balance, shop + eur("174"))
        XCTAssertFalse(s.change("记好了") { try $0.recordShopDay(25, cash: self.eur("10"), card: .zero) }, "还没到的日子记不了")
        XCTAssertEqual(s.book.fixedTotal, eur("1790"))
        XCTAssertTrue(s.change("加好了") { try $0.addFixedCost(name: "店面保险", amount: self.eur("35"), note: "每月 12 日", canSkip: false) })
        XCTAssertEqual(s.book.fixedTotal, eur("1825"))
        let net = s.book.totals.net
        XCTAssertTrue(s.change("转好了") { try $0.transferBetweenSides(self.eur("300"), toHome: true, shopAccount: "小店账户", homeAccount: "日常卡") })
        XCTAssertEqual(s.book.totals.net, net, "两边挪钱，净剩不变")
    }

    func testMemoryCategoriesAndAccounts() {
        let s = V3State()
        let n = s.book.memos.count
        XCTAssertTrue(s.change("记下了") { try $0.remember(.rule, topic: "转给妈妈的钱", line: "明年 1 月起每月多转 50 €") })
        XCTAssertEqual(s.book.memos.count, n, "已经有这个话题：加在它下面，不另开一条")
        XCTAssertEqual(s.book.memos.first { $0.topic == "转给妈妈的钱" }?.lines.count, 2)
        let cafe = s.book.memos.first { $0.topic == "Café Nube" }!
        XCTAssertTrue(s.change("删掉了") { try $0.removeMemo(cafe.id) })
        s.undo()
        XCTAssertNotNil(s.book.memos.first { $0.id == cafe.id }, "删掉能撤销")
        // 彻底忘掉：撤销也回不来
        XCTAssertTrue(s.change("改了别的") { try $0.renameBook(.biz, to: "花店") })
        s.forget(memo: cafe.id)
        s.undo()
        XCTAssertNil(s.book.memos.first { $0.id == cafe.id })
        XCTAssertEqual(s.book.shopName, "Miora 小店")

        // 分类改成已有的名字 = 并成一个，流水一起改
        XCTAssertTrue(s.change("并好了") { try $0.editCategory("咖啡", newName: "餐饮", emoji: "☕") })
        XCTAssertFalse(s.book.categories.contains { $0.name == "咖啡" })
        XCTAssertEqual(s.book.today.first { $0.place == "Café Nube" }?.name, "餐饮")

        // 账户：改名流水跟着改；有流水的不能删
        XCTAssertTrue(s.change("存好了") { try $0.editAccount("现金", newName: "钱包", balance: self.eur("90"), secret: false) })
        XCTAssertEqual(s.book.today.first { $0.place == "Café Nube" }?.account, "钱包")
        XCTAssertFalse(s.change("删掉了") { try $0.removeAccount("钱包") })
        XCTAssertEqual(s.toast?.isError, true)
    }

    func testDeleteEverythingKeepsABackupAndEmptyBookDoesNotBreak() {
        let s = V3State()
        let before = s.book
        let backups = s.backups.count
        s.deleteEverything()
        XCTAssertTrue(s.book.isEmpty)
        XCTAssertEqual(s.backups.count, backups + 1)
        XCTAssertEqual(s.book.totals.net, .zero)
        XCTAssertFalse(s.book.memos.isEmpty, "记忆不删")
        // 空账本上常用的数都能算，不出错
        _ = s.book.journey.remainingToNext; _ = s.book.journey.position; _ = s.book.journey.overallFraction
        _ = s.book.journey.monthsToFinish(); _ = s.book.runway.monthsText; _ = s.book.month.perDay; _ = s.book.dailyBreakEven
        XCTAssertFalse(s.depositAndCelebrate(eur("20")), "空账本里存不了，但不崩")
        s.restore(s.backups[0].id)
        XCTAssertEqual(s.book, before)
    }

    func testSubscriptionCycleInstallmentQueuedGoalAndCapitalTotal() {
        let s = V3State()
        let monthly = s.book.subscriptionsMonthly
        XCTAssertTrue(s.change("加好了") { try $0.addSubscription(name: "域名", amount: self.eur("24"), note: "每年扣", forWork: true, cycle: 3) })
        XCTAssertEqual(s.book.subscriptionsMonthly, monthly + eur("2"), "一年 24 € 折成每月 2 €")
        let owe = s.book.totals.owe
        XCTAssertTrue(s.change("记上了") { try $0.addInstallment(name: "新冰箱", total: self.eur("600"), periods: 12, paid: 2, day: 8) })
        XCTAssertEqual(s.book.totals.owe, owe + eur("500"))
        XCTAssertEqual(s.book.upcoming.last?.amount, eur("50"))
        XCTAssertFalse(s.change("记上了") { try $0.addInstallment(name: "沙发", total: self.eur("600"), periods: 12, paid: 12, day: 8) })
        XCTAssertTrue(s.change("存成目标了") { try $0.queueGoal(name: "攒够 6 个月底气", total: self.eur("5160")) })
        XCTAssertEqual(s.book.nextGoals.first?.note, "排在「换新电脑」后面")
        XCTAssertEqual(s.book.journey.name, "换新电脑", "现在这条路不动")
        s.undo()
        XCTAssertTrue(s.book.nextGoals.isEmpty)
        XCTAssertTrue(s.change("存好了") { try $0.setCapitalTotal(self.eur("32000")) })
        XCTAssertEqual(s.book.capitalTotal, eur("32000"))
    }

    func testGoingToBizSwitchesSide() {
        let s = V3State()
        s.go(.payback)
        XCTAssertEqual(s.side, .biz)
        s.switchSide(.life)
        XCTAssertEqual(s.page, .overview)
    }
}
#endif
