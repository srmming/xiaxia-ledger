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
        XCTAssertEqual(s.log.first?.mine, true)
        s.undo()
        XCTAssertEqual(s.book, before)
        XCTAssertFalse(s.log.contains(where: \.mine))
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

    func testGoingToBizSwitchesSide() {
        let s = V3State()
        s.go(.payback)
        XCTAssertEqual(s.side, .biz)
        s.switchSide(.life)
        XCTAssertEqual(s.page, .overview)
    }
}
#endif
