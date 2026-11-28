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
        XCTAssertEqual(b.totals.have, eur("4520"), "日常卡 + 储蓄 + 目标罐 + 借出去的 120，不含店里的 3.200")
        XCTAssertEqual(b.totals.owe, eur("640"), "店的信用卡、装修贷款不算")
        XCTAssertEqual(b.totals.net, eur("3880"))
        XCTAssertEqual(b.sum(.shop), .zero)
        XCTAssertEqual(b.wealthBlocks.map(\.amount).reduce(.zero, +), b.totals.have)
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
        XCTAssertEqual(b.totals.have, eur("4820"))
        XCTAssertEqual(b.account("小店账户")?.balance, eur("2700"))
        XCTAssertThrowsError(try b.transferBetweenSides(eur("10"), toHome: true, shopAccount: "日常卡", homeAccount: "储蓄"), "两头必须一边一个")
        XCTAssertThrowsError(try b.transferBetweenSides(eur("10"), toHome: false, shopAccount: "装修贷款", homeAccount: "日常卡"))
    }
}

/// 转账弹窗的规则：少于 2 个账户不出现；两边都开时「到」多一组对面的账户。
final class TransferRulesTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }
    private func book(_ accounts: [TrialBook.Account]) -> TrialBook {
        TrialBook(accounts: accounts, entries: [], upcoming: [],
                  month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
                  journey: Journey(name: "换新电脑", stops: [eur("700"), eur("1400")], saved: eur("500"), monthlyPlan: eur("200")), monthlyMust: eur("860"))
    }

    func testNeedsTwoAccountsOnThisSide() {
        var b = book([.init(emoji: "💳", name: "日常卡", note: "", balance: eur("1500")),
                      .init(emoji: "🏪", name: "小店账户", note: "", balance: eur("3000"), kind: .shop, block: .shop)])
        XCTAssertFalse(b.canTransfer(on: .life), "生活只有一个账户：没得转（店里的不算）")
        XCTAssertFalse(b.canTransfer(on: .biz))
        b.accounts.append(.init(emoji: "💳", name: "信用卡", note: "", balance: eur("640"), kind: .debt, block: .none))
        XCTAssertTrue(b.canTransfer(on: .life), "一个放钱的 + 一个欠的：能转（就是还款）")
        b.accounts.append(.init(emoji: "💶", name: "店里现金", note: "", balance: eur("200"), kind: .shop, block: .shop))
        XCTAssertTrue(b.canTransfer(on: .biz))
        XCTAssertFalse(book([.init(emoji: "💳", name: "信用卡", note: "", balance: eur("640"), kind: .debt, block: .none)]).canTransfer(on: .life), "只有欠的，没有能转出的")
    }

    func testCrossGroupAndTheOneWayAcross() throws {
        var b = book([.init(emoji: "💳", name: "日常卡", note: "", balance: eur("1500")),
                      .init(emoji: "🏦", name: "储蓄", note: "", balance: eur("2400"), block: .emergency),
                      .init(emoji: "🏪", name: "小店账户", note: "", balance: eur("3000"), kind: .shop, block: .shop),
                      .init(emoji: "🏦", name: "装修贷款", note: "", balance: eur("8400"), kind: .debt, block: .none, side: .biz)])
        XCTAssertEqual(b.crossTargets(from: .life).map(\.name), ["小店账户"], "店里欠的不在里面")
        XCTAssertEqual(b.crossTargets(from: .biz).map(\.name), ["日常卡"])
        try b.transferAny(eur("100"), from: "日常卡", to: "小店账户")
        XCTAssertEqual(b.account("小店账户")?.balance, eur("3100"))
        XCTAssertEqual(b.capital.last?.name, "自己垫给店里", "走的是「两边转钱」那条路")
        try b.transferAny(eur("50"), from: "小店账户", to: "日常卡")
        XCTAssertEqual(b.account("日常卡")?.balance, eur("1450"))
        try b.transferAny(eur("50"), from: "日常卡", to: "储蓄")
        XCTAssertEqual(b.account("储蓄")?.balance, eur("2450"), "同一边照常转")
        XCTAssertThrowsError(try b.transferAny(eur("50"), from: "日常卡", to: "装修贷款"), "不能直接还店里的贷款")
        XCTAssertThrowsError(try b.transferAny(eur("50"), from: "小店账户", to: "储蓄"))
        b.showBiz = false
        XCTAssertTrue(b.crossTargets(from: .life).isEmpty, "只管生活时没有「店里的」这一组")
        XCTAssertThrowsError(try b.transferAny(eur("50"), from: "日常卡", to: "小店账户"))
    }
}

/// 家底页：置顶的卡片（最多 4 张）和其余账户的分组列表。
final class AccountCardsTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }

    private func book() -> TrialBook {
        TrialBook(
            accounts: [.init(emoji: "💳", name: "日常卡", note: "", balance: eur("1500")),
                       .init(emoji: "💶", name: "现金", note: "", balance: eur("85")),
                       .init(emoji: "🏦", name: "储蓄", note: "", balance: eur("2400"), block: .emergency),
                       .init(emoji: "⭐", name: "目标罐", note: "", balance: eur("500"), block: .goal),
                       .init(emoji: "💳", name: "信用卡", note: "", balance: eur("640"), kind: .debt, block: .none),
                       .init(emoji: "🧑", name: "借给小李", note: "", balance: eur("120"), kind: .lent, block: .none),
                       .init(emoji: "🙈", name: "私房钱", note: "", balance: eur("1250"), kind: .secret, block: .none),
                       .init(emoji: "🏪", name: "小店账户", note: "", balance: eur("3000"), kind: .shop, block: .shop),
                       .init(emoji: "💶", name: "店里现金", note: "", balance: eur("200"), kind: .shop, block: .shop),
                       .init(emoji: "🏦", name: "装修贷款", note: "", balance: eur("8400"), kind: .debt, block: .none, side: .biz)],
            entries: [], upcoming: [],
            month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
            journey: Journey(name: "换新电脑", stops: [eur("700"), eur("1400")], saved: eur("500"), monthlyPlan: eur("200")),
            monthlyMust: eur("860"))
    }

    func testDefaultPinIsTheDailyCard() {
        let b = book()
        XCTAssertEqual(b.pinned(on: .life).map(\.name), ["日常卡"])
        XCTAssertEqual(b.pinned(on: .biz).map(\.name), ["小店账户"])
        XCTAssertEqual(b.listed(on: .life).map(\.title), ["日常能用", "存起来的", "欠的和借出去的"])
        XCTAssertEqual(b.listed(on: .life).map { $0.accounts.map(\.name) }, [["现金"], ["储蓄", "目标罐"], ["信用卡", "借给小李"]])
        XCTAssertEqual(b.listed(on: .biz).map(\.title), ["能用的", "欠着的"])
        XCTAssertEqual(b.listed(on: .biz).map { $0.accounts.map(\.name) }, [["店里现金"], ["装修贷款"]])
    }

    func testEveryAccountShowsExactlyOnce() throws {
        var b = book()
        try b.setPinned("储蓄", true)
        try b.setPinned("信用卡", true)
        for side in [TrialBook.Side.life, .biz] {
            let shown = b.pinned(on: side).map(\.name) + b.listed(on: side).flatMap(\.accounts).map(\.name)
            XCTAssertEqual(shown.sorted(), b.pinnable(on: side).map(\.name).sorted(), "置顶的 + 列表里的 = 这一边全部账户，不多不少")
            XCTAssertFalse(shown.contains("私房钱"))
        }
        XCTAssertFalse(b.pinned(on: .life).contains { $0.side == .biz })
        XCTAssertFalse(b.listed(on: .life).flatMap(\.accounts).contains { $0.side == .biz })
    }

    func testPinUnpinAndLimit() throws {
        var b = book()
        try b.setPinned("储蓄", true)
        XCTAssertEqual(b.pinned(on: .life).map(\.name), ["日常卡", "储蓄"], "默认置顶的那张留着，新的排在后面")
        try b.setPinned("信用卡", true)
        try b.setPinned("现金", true)
        XCTAssertThrowsError(try b.setPinned("目标罐", true), "最多 4 张")
        XCTAssertThrowsError(try b.setPinned("私房钱", true))
        try b.setPinned("日常卡", false)
        XCTAssertEqual(b.pinned(on: .life).map(\.name), ["储蓄", "信用卡", "现金"])
        XCTAssertTrue(b.listed(on: .life).first { $0.title == "日常能用" }?.accounts.contains { $0.name == "日常卡" } ?? false)
        for n in ["储蓄", "信用卡", "现金"] { try b.setPinned(n, false) }
        XCTAssertEqual(b.pinned(on: .life).map(\.name), ["日常卡"], "一张都不置顶时，回到默认的日常卡")
        XCTAssertEqual(b.pinned(on: .biz).map(\.name), ["小店账户"], "生活这边怎么改，店里那排不受影响")
    }

    func testDragToReorderAndRemovedAccounts() throws {
        var b = book()
        for n in ["储蓄", "信用卡"] { try b.setPinned(n, true) }
        try b.movePin("信用卡", to: 0)
        XCTAssertEqual(b.pinned(on: .life).map(\.name), ["信用卡", "日常卡", "储蓄"])
        try b.movePin("信用卡", to: 9)
        XCTAssertEqual(b.pinned(on: .life).map(\.name), ["日常卡", "储蓄", "信用卡"], "拖过头就放到最后")
        XCTAssertThrowsError(try b.movePin("现金", to: 0), "没置顶的拖不了")
        try b.removeAccount("信用卡")
        XCTAssertEqual(b.pinned(on: .life).map(\.name), ["日常卡", "储蓄"], "账户删了，卡片跟着没")
        try b.editAccount("储蓄", newName: "存起来的钱", balance: eur("2400"), secret: false)
        XCTAssertEqual(b.pinned(on: .life).map(\.name), ["日常卡", "存起来的钱"], "改名不影响置顶")
    }

    func testCardLook() throws {
        var b = book()
        XCTAssertEqual(b.account("信用卡")?.cardLook, 4, "欠的默认浅粉，红字看得清")
        XCTAssertEqual(b.account("小店账户")?.cardLook, 2)
        try b.setCardStyle("日常卡", 3)
        XCTAssertEqual(b.account("日常卡")?.cardLook, 3)
        XCTAssertThrowsError(try b.setCardStyle("日常卡", AccountCards.styleCount))
    }
}
