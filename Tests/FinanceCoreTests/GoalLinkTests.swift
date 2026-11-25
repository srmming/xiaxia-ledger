import XCTest
@testable import FinanceCore

/// 改目标名字后，存进目标的钱不能和目标断开（2026-11-25 ming「修 5 个丢账问题」第 5 条）。全是编造数据。
final class GoalLinkTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 23)

    private func setup() throws -> (Ledger, Goal) {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "示例银行", kind: .bank)]
        let (g, _) = try l.addGoal(name: "示例旅行", bookID: l.books[0].id, target: Money(cents: 100000), today: today, author: "t")
        try l.deposit(goalID: g.id, amount: Money(cents: 10000), fromAccount: "bank", date: today, author: "t")
        return (l, try XCTUnwrap(l.goals.first))
    }

    private func saved(_ l: Ledger) -> Money { Plans.goals(l)[0].saved }

    /// 打开「改目标」后又存了一笔，再拿打开时的旧样子保存改名：新存的那笔还算在目标里。
    func testRenameWithStaleCopyKeepsLaterDeposit() throws {
        var (l, opened) = try setup()
        try l.deposit(goalID: opened.id, amount: Money(cents: 5000), fromAccount: "bank", date: today, author: "手机")
        XCTAssertEqual(saved(l), Money(cents: 15000))

        opened.name = "示例海边旅行"
        try l.updateGoal(opened, author: "t")
        XCTAssertEqual(l.goals[0].name, "示例海边旅行")
        XCTAssertEqual(l.goals[0].contributionIDs.count, 2)
        XCTAssertEqual(saved(l), Money(cents: 15000))
        XCTAssertEqual(Plans.goalDeposits(l.goals[0], in: l).count, 2)
    }

    /// 旧样子里的大目标、排序这些不会被写回去。
    func testStaleCopyDoesNotOverwritePinnedOrRank() throws {
        var (l, opened) = try setup()
        l.goals[0].pinned = true
        l.goals[0].rank = 3
        opened.target = Money(cents: 120000)
        try l.updateGoal(opened, author: "t")
        XCTAssertTrue(l.goals[0].pinned)
        XCTAssertEqual(l.goals[0].rank, 3)
        XCTAssertEqual(l.goals[0].target, Money(cents: 120000))
    }

    /// 改名 → 又存一笔 → 撤销改名：名字回来，后存的那笔还在目标里。
    func testUndoRenameKeepsDepositMadeAfterRename() throws {
        var (l, g) = try setup()
        g.name = "示例海边旅行"
        let rename = try l.updateGoal(g, author: "t")
        try l.deposit(goalID: g.id, amount: Money(cents: 2500), fromAccount: "bank", date: today, author: "t")
        try l.undo(changeID: rename.id, author: "t")
        XCTAssertEqual(l.goals[0].name, "示例旅行")
        XCTAssertEqual(saved(l), Money(cents: 12500))
    }

    /// 撤销存钱照样能把那笔拿掉（不会被「从改动记录补回」又算进去）。
    func testUndoDepositStillRemovesIt() throws {
        var (l, g) = try setup()
        let dep = try l.deposit(goalID: g.id, amount: Money(cents: 2500), fromAccount: "bank", date: today, author: "t")
        try l.undo(changeID: dep.id, author: "t")
        XCTAssertEqual(saved(l), Money(cents: 10000))
        _ = g
    }

    /// 老账本里已经断开的：存款列表丢了那笔，但改动记录还在，进度照样算上；取钱也按取出那笔减掉。
    func testAlreadyBrokenLedgerHealsFromChangeRecords() throws {
        var (l, g) = try setup()
        try l.deposit(goalID: g.id, amount: Money(cents: 5000), fromAccount: "bank", date: today, author: "t")
        try l.withdraw(goalID: g.id, amount: Money(cents: 2000), toAccount: "bank", date: today, author: "t")
        XCTAssertEqual(saved(l), Money(cents: 13000))
        l.goals[0].contributionIDs = []   // 模拟以前被旧样子写回、断开了
        XCTAssertEqual(saved(l), Money(cents: 13000))
        XCTAssertEqual(Plans.goalDeposits(l.goals[0], in: l).count, 2)
        let f = try XCTUnwrap(Plans.goalForecasts(l, today: today).first)
        XCTAssertEqual(f.saved, Money(cents: 13000))
        XCTAssertGreaterThan(f.monthlyPace.cents, 0)
    }

    /// 存了钱的目标，就算存款列表断了，也不能直接撤销「建目标」把目标删掉。
    func testCannotUndoGoalCreationWhenOnlyChangeRecordLinksDeposit() throws {
        var (l, _) = try setup()
        let create = try XCTUnwrap(l.changes.first { $0.kind == .goal })
        l.goals[0].contributionIDs = []
        XCTAssertThrowsError(try l.undo(changeID: create.id, author: "t"))
    }
}
