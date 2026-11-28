import XCTest
@testable import FinanceCore

/// 迁移「每个目标各有一个账户」：只在示例账本（内存里现造的）和临时文件夹里的副本上跑。
final class GoalAccountMigrationTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 18)

    /// 所有账户的余额加起来（主币种）。
    private func total(_ l: Ledger) -> Money { l.transactions.reduce(.zero) { $0 + l.baseAmount($1) } }

    /// 示例账本，并保证里面有一个「在日常卡里划出来」的目标，存了 140。返回账本和那个目标。
    private func ledgerWithLooseGoals() throws -> Ledger {
        var l = DemoData.make(endingOn: today)
        let card = l.accounts.first { $0.kind == .bank }!.id
        var loose = l.goals.first { $0.savingsAccountID == nil && !$0.locked }
        if loose == nil {
            // 示例里目标已经满了：先删一个再加一个没有账户的
            try l.removeGoal(l.goals.last!.id, author: "测试")
            loose = try l.addGoal(name: "测试用的目标", bookID: l.books.first { !$0.isBusiness }!.id, target: Money(cents: 500_00), today: today, author: "测试").0
        }
        let g = loose!
        try l.deposit(goalID: g.id, amount: Money(cents: 120_00), fromAccount: card, date: today, author: "测试")
        try l.deposit(goalID: g.id, amount: Money(cents: 30_00), fromAccount: card, date: today, author: "测试")
        try l.withdraw(goalID: g.id, amount: Money(cents: 10_00), toAccount: card, date: today, author: "测试")
        looseID = g.id
        return l
    }
    private var looseID = UUID()

    func testEveryGoalGetsItsOwnAccountAndNothingElseMoves() throws {
        var l = try ledgerWithLooseGoals()
        let before = l
        let loose = l.goalsWithoutOwnAccount
        XCTAssertFalse(loose.isEmpty)
        let savedBefore = Dictionary(Plans.goals(l).map { ($0.id, $0.saved) }, uniquingKeysWith: { a, _ in a })
        let records = try l.giveEveryGoalItsOwnAccount(today: today, author: "迁移")
        XCTAssertFalse(records.isEmpty)
        XCTAssertTrue(records.allSatisfy { $0.author == "迁移" }, "每一步都写明是谁做的")
        // 每个目标都有自己的账户，没有两个目标共用
        XCTAssertTrue(l.goalsWithoutOwnAccount.isEmpty)
        let used = l.goals.compactMap(\.savingsAccountID)
        XCTAssertEqual(Set(used).count, used.count)
        // 每个目标存了多少：一分不差
        for s in Plans.goals(l) { XCTAssertEqual(s.saved, savedBefore[s.id], s.name) }
        XCTAssertGreaterThanOrEqual(Plans.goals(l).first { $0.id == looseID }?.saved ?? .zero, Money(cents: 140_00), "刚存进去的 140 还在")
        // 所有账户加起来：一分不差；旧流水一笔没删没改
        XCTAssertEqual(total(l), total(before), "前后合计一致")
        for t in before.transactions { XCTAssertEqual(l.transactions.first { $0.id == t.id }, t, "旧流水不动") }
        XCTAssertEqual(l.accounts.count, before.accounts.count + loose.count, "只多了存钱罐")
        // 这个月的收支不受影响（挪钱不算收入也不算支出）
        let month = today.yearMonth
        XCTAssertEqual(Summaries.monthly(l.transactions, month: month, bookID: nil), Summaries.monthly(before.transactions, month: month, bookID: nil))
        // 再跑一遍：没有要迁的了，什么都不做
        let again = l
        XCTAssertTrue(try l.giveEveryGoalItsOwnAccount(today: today, author: "迁移").isEmpty)
        XCTAssertEqual(l, again)
    }

    func testMigrationCanBeUndoneStepByStepAndSurvivesSaving() throws {
        var l = try ledgerWithLooseGoals()
        let before = l
        let records = try l.giveEveryGoalItsOwnAccount(today: today, author: "迁移")
        // 存盘再读（临时文件夹里的副本，用完就删）
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xiaxia-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SQLiteLedgerStore(url: dir.appendingPathComponent("copy.sqlite"))
        try store.save(l)
        var back = try store.load()
        XCTAssertTrue(back.goalsWithoutOwnAccount.isEmpty)
        XCTAssertEqual(total(back), total(before))
        // 从后往前一条条撤销：回到迁移前的样子
        for r in records.reversed() { try back.undo(changeID: r.id, author: "迁移") }
        XCTAssertEqual(back.goals.map(\.savingsAccountID), before.goals.map(\.savingsAccountID))
        XCTAssertEqual(back.accounts.map(\.id), before.accounts.map(\.id))
        XCTAssertEqual(total(back), total(before))
        XCTAssertEqual(Plans.goals(back).map(\.saved), Plans.goals(before).map(\.saved))
    }

    func testOneAccountOneGoalRule() throws {
        var l = try ledgerWithLooseGoals()
        try l.giveEveryGoalItsOwnAccount(today: today, author: "迁移")
        let a = l.goals[0], b = l.goals[1]
        XCTAssertThrowsError(try l.setGoalAccount(b.id, accountID: a.savingsAccountID, author: "测试"), "一个账户只能对一个目标")
        XCTAssertTrue(l.goalsSharingAnAccount.isEmpty)
        XCTAssertThrowsError(try l.setGoalAccount(a.id, accountID: "没有这个账户", author: "测试"))
    }
}
