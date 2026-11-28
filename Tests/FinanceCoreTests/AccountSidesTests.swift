import XCTest
@testable import FinanceCore

/// 硬规则：生活和生意的账户完全分开，只有「两边转钱」能让钱跨过去。
final class AccountSidesTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    private var book: TrialBook {
        TrialBook(
            accounts: [.init(emoji: "💳", name: "日常卡", note: "", balance: eur("1500")),
                       .init(emoji: "🏦", name: "储蓄", note: "", balance: eur("2400"), block: .emergency),
                       .init(emoji: "⭐", name: "目标罐", note: "", balance: eur("500"), block: .goal),
                       .init(emoji: "💳", name: "信用卡", note: "", balance: eur("640"), kind: .debt, block: .none),
                       .init(emoji: "🧑", name: "借给小李", note: "", balance: eur("120"), kind: .lent, block: .none),
                       .init(emoji: "🏪", name: "小店账户", note: "", balance: eur("3000"), kind: .shop, block: .shop),
                       .init(emoji: "💶", name: "店里现金", note: "", balance: eur("200"), kind: .shop, block: .shop),
                       .init(emoji: "💳", name: "店的信用卡", note: "", balance: eur("180"), kind: .debt, block: .none, side: .biz),
                       .init(emoji: "🏦", name: "装修贷款", note: "", balance: eur("8400"), kind: .debt, block: .none, side: .biz)],
            entries: [], upcoming: [],
            month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
            journey: Journey(name: "换新电脑", stops: [eur("700"), eur("1400")], saved: eur("500"), monthlyPlan: eur("200")),
            monthlyMust: eur("860"))
    }

    func testEveryAccountBelongsToOneSide() {
        let b = book
        XCTAssertEqual(b.accounts(on: .life).map(\.name), ["日常卡", "储蓄", "目标罐", "信用卡", "借给小李"])
        XCTAssertEqual(b.accounts(on: .biz).map(\.name), ["小店账户", "店里现金", "店的信用卡", "装修贷款"])
        XCTAssertEqual(b.accounts(on: .life).count + b.accounts(on: .biz).count, b.accounts.count)
    }

    func testLifeTotalsLeaveShopMoneyOut() {
        let b = book
        XCTAssertEqual(b.totals.have, eur("4400"), "日常卡 + 储蓄 + 目标罐，不含店里的 3.200")
        XCTAssertEqual(b.totals.owe, eur("640"), "店的信用卡、装修贷款不算")
        XCTAssertEqual(b.totals.net, eur("3760"))
        XCTAssertEqual(b.sum(.shop), .zero)
        XCTAssertEqual(b.sum(.daily) + b.sum(.emergency) + b.sum(.goal), b.totals.have)
        XCTAssertFalse(b.owned.contains { $0.side == .biz })
        XCTAssertFalse(b.debts.contains { $0.side == .biz })
        XCTAssertFalse(b.emergencyCandidates.contains { $0.side == .biz })
        XCTAssertEqual(b.runway.fund, eur("2400"))
    }

    func testPickersNeverMixSides() {
        let b = book
        for use in [TrialBook.AccountUse.pay, .receive, .moveOut, .moveIn] {
            XCTAssertTrue(b.accounts(for: use, side: .life).allSatisfy { $0.side == .life }, "生活：\(use)")
            XCTAssertTrue(b.accounts(for: use, side: .biz).allSatisfy { $0.side == .biz }, "生意：\(use)")
            XCTAssertFalse(b.accounts(for: use, side: .life).isEmpty)
            XCTAssertFalse(b.accounts(for: use, side: .biz).isEmpty)
        }
        XCTAssertEqual(b.accounts(for: .moveIn, side: .biz).map(\.name), ["小店账户", "店里现金", "店的信用卡", "装修贷款"])
        XCTAssertTrue(b.transferShortcuts.allSatisfy { s in b.account(s.from)?.side == .life && b.account(s.to)?.side == .life })
    }

    func testWritesCannotCrossSides() {
        let start = book
        var b = start
        XCTAssertThrowsError(try b.transfer(eur("50"), from: "日常卡", to: "小店账户"))
        XCTAssertThrowsError(try b.transfer(eur("50"), from: "小店账户", to: "储蓄"))
        XCTAssertThrowsError(try b.transfer(eur("50"), from: "日常卡", to: "装修贷款"))
        XCTAssertThrowsError(try b.move(eur("50"), from: "店里现金", to: "日常卡"))
        XCTAssertThrowsError(try b.repay(debt: "信用卡", amount: eur("50"), from: "小店账户"))
        XCTAssertThrowsError(try b.repay(debt: "店的信用卡", amount: eur("50"), from: "日常卡"))
        XCTAssertThrowsError(try b.record(name: "午饭", emoji: "🍜", amount: eur("9"), account: "小店账户"))
        XCTAssertThrowsError(try b.record(name: "进货", emoji: "📦", amount: eur("9"), account: "日常卡", side: .biz))
        XCTAssertThrowsError(try b.addAccount(emoji: "🏪", name: "第二个店账户", note: "", balance: .zero, kind: .shop))
        XCTAssertTrue(b == start, "都没做成，账本一点没变")
        // 同一边里照常能转
        XCTAssertNoThrow(try b.transfer(eur("50"), from: "小店账户", to: "店里现金"))
        XCTAssertNoThrow(try b.transfer(eur("80"), from: "小店账户", to: "店的信用卡"))
        XCTAssertEqual(b.account("店的信用卡")?.balance, eur("100"))
        XCTAssertNoThrow(try b.transfer(eur("50"), from: "日常卡", to: "储蓄"))
    }

    func testOnlyTheSideTransferCrosses() throws {
        var b = book
        try b.transferBetweenSides(eur("300"), toHome: true, shopAccount: "小店账户", homeAccount: "日常卡")
        XCTAssertEqual(b.totals.have, eur("4700"))
        XCTAssertEqual(b.account("小店账户")?.balance, eur("2700"))
        XCTAssertThrowsError(try b.transferBetweenSides(eur("10"), toHome: true, shopAccount: "日常卡", homeAccount: "储蓄"), "两头必须一边一个")
        XCTAssertThrowsError(try b.transferBetweenSides(eur("10"), toHome: false, shopAccount: "装修贷款", homeAccount: "日常卡"))
    }
}
