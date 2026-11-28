import XCTest
@testable import FinanceCore

/// 把正式账本整理成界面要的样子（只读）。只用示例账本（DemoData，内存里现造的），不碰任何账本文件。
final class LedgerBridgeTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 18)
    private var ledger: Ledger { DemoData.make(endingOn: today) }

    func testSnapshotNeverChangesTheLedger() {
        let l = ledger
        let before = l
        _ = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertEqual(l, before, "只读：正式账本一个字都没变")
        XCTAssertEqual(l.changes.count, before.changes.count)
    }

    func testAccountBalancesAddUpToTheLedger() {
        let l = ledger
        let b = LedgerBridge.snapshot(of: l, today: today, showPrivate: true)
        // 每个账户的余额 = 这个账户所有流水加起来（换成主币种）
        var sums: [String: Money] = [:]
        for t in l.transactions { sums[t.accountID, default: .zero] = sums[t.accountID, default: .zero] + l.baseAmount(t) }
        for a in l.accounts {
            let shown = b.account(a.name)
            XCTAssertNotNil(shown, "\(a.name) 应该在")
            let bal = sums[a.id] ?? .zero
            XCTAssertEqual(shown?.balance, a.kind == .credit ? (bal < .zero ? bal.magnitude : .zero) : bal, a.name)
        }
        // 界面上生活 + 店里手里的钱，合起来 = 正式账本里不是信用卡的账户余额之和
        let held = l.accounts.filter { $0.kind != .credit }.map { sums[$0.id] ?? .zero }.reduce(.zero, +)
        XCTAssertEqual(b.inHand + b.shopHeld.map(\.balance).reduce(.zero, +), held, "前后合计一致")
    }

    func testOldPrivateAccountsShowByDefaultAndCanBeHidden() {
        var l = ledger
        guard let first = l.accounts.firstIndex(where: { $0.kind != .credit }) else { return XCTFail() }
        l.accounts[first].isPrivate = true
        let hiddenName = l.accounts[first].name
        let off = LedgerBridge.snapshot(of: l, today: today, showPrivate: false)
        let on = LedgerBridge.snapshot(of: l, today: today)
        XCTAssertTrue(l.accounts[first].isPrivate, "旧数据里的标记不删不改")
        XCTAssertNil(off.account(hiddenName), "开关关掉：和旧界面一样不显示、不算进合计")
        XCTAssertNotNil(on.account(hiddenName))
        XCTAssertFalse(off.entries.contains { $0.account == hiddenName })
        XCTAssertNotEqual(off.inHand + off.shopHeld.map(\.balance).reduce(.zero, +), on.inHand + on.shopHeld.map(\.balance).reduce(.zero, +))
    }

    func testSidesMonthAndSlices() {
        let l = ledger
        let b = LedgerBridge.snapshot(of: l, today: today)
        // 生活和生意分开：用的是正式账本自己的判断
        let biz = WealthBreakdown.businessAccounts(l)
        for a in l.accounts {
            XCTAssertEqual(b.account(a.name)?.side, biz.contains(a.id) ? .biz : .life, a.name)
        }
        XCTAssertEqual(b.showBiz, l.books.contains { $0.isBusiness })
        XCTAssertEqual(b.thisMonth, .init(2026, 11))
        XCTAssertEqual(b.todayDay, 18)
        // 这个月：进账、花掉的，和正式账本的流水逐笔加出来的一样
        let bizBooks = Set(l.books.filter(\.isBusiness).map(\.id))
        let spending = Summaries.expenseCategories(l.transactions)
        var income = Money.zero, expense = Money.zero
        for t in l.transactions where t.countsAsIncomeOrExpense && !t.isTransfer && t.date.yearMonth == today.yearMonth && t.date <= today
            && !(t.bookID.map { bizBooks.contains($0) } ?? false) {
            if Summaries.countsAsIncome(t, expenseCategories: spending) { income = income + l.baseAmount(t) } else { expense = expense + l.baseAmount(t) }
        }
        XCTAssertEqual(b.month.income, income)
        // 「这个月花掉」= 到今天真花掉的；还没到日子的固定开销不算花掉，但「还能随便花」照样先给它留着
        XCTAssertEqual(b.month.spentTotal, expense.magnitude)
        XCTAssertEqual(b.month.left, income - b.month.spentTotal - b.month.fixedLeft - b.month.forGoals)
        XCTAssertEqual(b.spendByCategory.map(\.amount).reduce(.zero, +), expense.magnitude, "圆环各段加起来 = 这个月花掉的")
        XCTAssertEqual(b.spendByCategory.map(\.amount), b.spendByCategory.map(\.amount).sorted(by: >))
        // 流水：新的在前，都是到今天为止的
        XCTAssertEqual(b.entries.map(\.daysAgo), b.entries.map(\.daysAgo).sorted())
        XCTAssertTrue(b.entries.allSatisfy { $0.daysAgo >= 0 && $0.daysAgo <= 90 })
        XCTAssertFalse(b.entries.isEmpty)
        // 过去的月份能切，每个月都有自己的家底；「比上个月」两句有数可比
        XCTAssertGreaterThan(b.months.count, 1)
        for m in b.pastMonths {
            XCTAssertEqual(m.have - m.owe, m.net, "\(m.key.month) 月底：净剩 = 有 − 欠")
            XCTAssertEqual(m.sliceTotal, m.spentTotal, "\(m.key.month) 月：分类加起来 = 一共花掉")
        }
        XCTAssertNotNil(b.netMoreThanLastMonth); XCTAssertNotNil(b.spentLessThanLastMonthSameDay)
        XCTAssertFalse(b.pastMonths.contains { $0.key == b.thisMonth })
    }

    func testGoalsAndSubscriptionsComeAcross() {
        let l = ledger
        let b = LedgerBridge.snapshot(of: l, today: today)
        let statuses = Plans.goals(l)
        if let first = l.goals.sorted(by: { ($0.pinned ? 0 : 1, $0.rank ?? Int.max) < ($1.pinned ? 0 : 1, $1.rank ?? Int.max) }).first, let s = statuses.first(where: { $0.id == first.id }) {
            XCTAssertEqual(b.journey.name, first.name)
            XCTAssertEqual(b.journey.saved, s.saved, "大目标存了多少，和正式账本算的一样")
            XCTAssertEqual(b.journey.total, first.target)
        }
        XCTAssertEqual(b.subscriptions.count, Subscriptions.status(l, today: today).count)
        XCTAssertLessThanOrEqual(b.smallGoals.count, Plans.maxSmallGoals)
    }

    /// 第 3 步给账户加的两个字段（置顶第几张、卡片底色）：存进账本文件再读回来还在；改之前、改之后别的东西一样不变。
    /// 只在临时文件夹里写一份示例账本的副本，用完就删。
    func testNewAccountFieldsSurviveSavingAndOldDataStaysIntact() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xiaxia-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SQLiteLedgerStore(url: dir.appendingPathComponent("copy.sqlite"))
        var l = ledger
        try store.save(l)
        let plain = try store.load()
        XCTAssertTrue(plain.accounts.allSatisfy { $0.cardPin == nil && $0.cardStyle == nil }, "老数据：两个新字段都是空的")
        let balancesBefore = Summaries.balances(plain.transactions)
        // 在界面上置顶一张、换个底色，写进正式账本，再存盘、读回
        let before = LedgerBridge.snapshot(of: l, today: today)
        var after = before
        let name = before.accounts(on: .life).first { $0.kind == .own && $0.block == .daily }!.name
        let second = before.accounts(on: .life).first { $0.kind == .own && $0.name != name }!.name
        try after.setPinned(second, true)
        try after.setCardStyle(second, 2)
        let records = try LedgerBridge.apply(before: before, after: after, to: &l, today: today, author: "测试")
        XCTAssertFalse(records.isEmpty)
        XCTAssertTrue(records.allSatisfy { $0.author == "测试" })
        try store.save(l)
        let back = try store.load()
        XCTAssertEqual(back.accounts.first { $0.name == second }?.cardStyle, 2)
        XCTAssertNotNil(back.accounts.first { $0.name == second }?.cardPin)
        XCTAssertNotNil(back.accounts.first { $0.name == name }?.cardPin, "原来默认置顶的那张也记下来了")
        // 别的一样没变：流水、每个账户的余额、私房钱标记
        XCTAssertEqual(back.transactions.count, plain.transactions.count)
        XCTAssertEqual(Summaries.balances(back.transactions), balancesBefore, "前后每个账户的余额一致")
        XCTAssertEqual(back.accounts.map(\.isPrivate), plain.accounts.map(\.isPrivate))
        XCTAssertEqual(LedgerBridge.snapshot(of: back, today: today).pinned(on: .life).map(\.name), [name, second])
    }
}
