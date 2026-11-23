import XCTest
@testable import FinanceCore

/// 删除数据、删除前备份（设置 → 数据）。全用示例账本。
final class DataResetTests: XCTestCase {
    let end = LocalDate(year: 2026, month: 11, day: 20)
    lazy var demo = DemoData.make(endingOn: end)

    func testWipeEverythingKeepsOnlyPreferences() throws {
        var l = demo
        l.profile.persona = .sharp
        l.profile.assistantName = "小鲸"
        let count = l.wipeCount(.everything)
        XCTAssertEqual(count.transactions, demo.transactions.count)
        XCTAssertEqual(count.accounts, demo.accounts.count)
        XCTAssertFalse(count.isEmpty)

        let change = try l.wipe(.everything, author: "测试", backupNote: "删除前备份/ledger-x.sqlite")
        XCTAssertTrue(l.transactions.isEmpty)
        XCTAssertTrue(l.accounts.isEmpty)
        XCTAssertTrue(l.goals.isEmpty)
        XCTAssertTrue(l.debts.isEmpty)
        XCTAssertTrue(l.installments.isEmpty)
        XCTAssertTrue(l.subscriptions.isEmpty)
        XCTAssertTrue(l.recurring.isEmpty)
        XCTAssertTrue(l.insights.isEmpty)
        XCTAssertTrue(l.memories.isEmpty)
        XCTAssertEqual(l.books.map(\.id), Ledger.fresh.books.map(\.id), "回到只有一个「个人」账本")
        XCTAssertEqual(l.profile.persona, .sharp, "性格留着")
        XCTAssertEqual(l.profile.assistantName, "小鲸", "名字留着")
        XCTAssertEqual(l.currency, demo.currency, "主币种留着")
        XCTAssertEqual(l.changes.count, 1, "只剩一条「清空了」的记录")
        XCTAssertEqual(l.changes.first?.id, change.id)
        XCTAssertFalse(change.canUndo, "清空不能撤销，靠备份恢复")
        XCTAssertTrue(change.summary.contains("删除前备份/ledger-x.sqlite"))
        XCTAssertFalse(DemoData.isDemo(l), "清空后不再是示例账本")
        XCTAssertTrue(l.wipeCount(.everything).isEmpty)
    }

    func testWipeOneBookLeavesTheOther() throws {
        var l = demo
        let shop = DemoData.shopBookID
        let otherBefore = l.transactions.filter { $0.bookID != shop }
        let count = l.wipeCount(.book(shop))
        XCTAssertGreaterThan(count.transactions, 0)
        XCTAssertEqual(count.accounts, 0, "只清一个账本时账户不删")

        let change = try l.wipe(.book(shop), author: "测试")
        XCTAssertFalse(l.transactions.contains { $0.bookID == shop })
        XCTAssertEqual(l.transactions.filter { $0.bookID != shop }, otherBefore, "别的账本的流水一笔不动")
        XCTAssertEqual(l.accounts, demo.accounts, "账户留着")
        XCTAssertEqual(l.books, demo.books, "账本本身留着")
        XCTAssertFalse(l.goals.contains { $0.bookID == shop })
        XCTAssertFalse(l.debts.contains { $0.bookID == shop })
        XCTAssertFalse(l.installments.contains { $0.bookID == shop })
        XCTAssertFalse(l.subscriptions.contains { $0.bookID == shop })
        XCTAssertEqual(l.changes.count, demo.changes.count + 1)
        XCTAssertFalse(change.canUndo)
        XCTAssertTrue(l.wipeCount(.book(shop)).isEmpty)

        // 留下来的目标、欠款、分期不再引用被删的流水。
        let left = Set(l.transactions.map(\.id))
        XCTAssertTrue(l.goals.flatMap(\.contributionIDs).allSatisfy(left.contains))
        XCTAssertTrue(l.debts.flatMap(\.repaymentIDs).allSatisfy(left.contains))
        XCTAssertTrue(l.installments.flatMap(\.paidIDs).allSatisfy(left.contains))
    }

    func testWipeUnknownBookThrows() {
        var l = demo
        XCTAssertThrowsError(try l.wipe(.book("没有这个"), author: "测试"))
        XCTAssertEqual(l, demo, "出错时什么都不动")
    }

    func testCountText() {
        XCTAssertEqual(WipeCount().text, "没有东西")
        XCTAssertEqual(WipeCount(transactions: 1528, accounts: 6, goals: 1).text, "1.528 笔流水、6 个账户、1 个目标")
        XCTAssertEqual(WipeCount.grouped(999), "999")
        XCTAssertEqual(WipeCount.grouped(1_234_567), "1.234.567")
    }

    func testBackupCopiesFileAndKeepsLatest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xiaxia-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileLedgerStore(url: dir.appendingPathComponent("ledger.json"))
        XCTAssertNil(try LedgerBackup.make(of: store.url, label: "删除前"), "账本文件还没有时不用备份")
        try store.save(demo)
        XCTAssertEqual(LedgerBackup.fileURL(of: store), store.url)
        XCTAssertNil(LedgerBackup.fileURL(of: InMemoryLedgerStore(demo)), "内存账本没有文件")

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var made: [URL] = []
        for i in 0..<4 {
            let u = try XCTUnwrap(try LedgerBackup.make(of: store.url, label: "删除前", keep: 3, now: base.addingTimeInterval(Double(i) * 60)))
            made.append(u)
        }
        let list = LedgerBackup.list(for: store.url)
        XCTAssertEqual(list.count, 3, "只留最近 3 份")
        XCTAssertEqual(list.first?.url.lastPathComponent, made.last?.lastPathComponent, "最新的排最前")
        XCTAssertFalse(FileManager.default.fileExists(atPath: made[0].path), "最旧的那份清掉了")
        XCTAssertEqual(list.first?.url.deletingLastPathComponent().lastPathComponent, LedgerBackup.folderName)

        // 同一秒再备份一次不会盖掉上一份。
        let again = try XCTUnwrap(try LedgerBackup.make(of: store.url, label: "删除前", keep: 10, now: base.addingTimeInterval(180)))
        XCTAssertNotEqual(again.lastPathComponent, made[3].lastPathComponent)

        // 清空后从备份里读回来，和清空前一模一样。
        var wiped = demo
        try wiped.wipe(.everything, author: "测试")
        try store.save(wiped)
        let restored = try LedgerBackup.load(made[3])
        XCTAssertEqual(restored.transactions.count, demo.transactions.count)
        XCTAssertEqual(restored.accounts, demo.accounts)
        try store.save(restored)
        XCTAssertEqual(try store.load().transactions.count, demo.transactions.count)
    }
}
