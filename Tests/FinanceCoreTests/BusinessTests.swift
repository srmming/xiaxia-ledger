import XCTest
@testable import FinanceCore

final class BusinessTests: XCTestCase {
    let today = LocalDate("2026-04-02")!
    let author = "测试"
    func tx(_ name: String, _ cents: Int64, category: String = "花材", book: String = "miora",
            date: String = "2026-04-01", account: String = "shop") -> Transaction {
        Transaction(date: LocalDate(date)!, amount: Money(cents: cents), description: name, accountID: account, bookID: book, category: category)
    }
    func testEnableDisableUndoAndChoose() throws {
        var l = Ledger.fresh
        guard case .enabled(let created) = try l.enableBusinessMode(author: author) else { return XCTFail() }
        XCTAssertEqual(l.books.count, 2)
        try l.undo(changeID: created.id, author: author)
        XCTAssertEqual(l.books, Ledger.fresh.books)
        XCTAssertNil(l.business)
        l = .starter
        _ = try l.enableBusinessMode(author: author)
        XCTAssertEqual(l.businessBook?.id, "miora")
        _ = l.disableBusinessMode(author: author)
        XCTAssertEqual(l.business?.enabled, false)
        _ = try l.enableBusinessMode(author: author)
        XCTAssertEqual(l.books.count, 2)
        l = .starter
        l.books.append(Book(id: "shop", name: "二店", kind: .business))
        let original = l
        guard case .needsChoice(let choices) = try l.enableBusinessMode(author: author) else { return XCTFail() }
        XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(original, l)
        _ = try l.enableBusinessMode(choose: "shop", author: author)
        XCTAssertEqual(l.businessBook?.id, "shop")
    }
    func testProfitCapitalAndTransfers() throws {
        var l = Ledger.starter
        _ = try l.enableBusinessMode(author: author)
        let stock = tx("首批花材", -800)
        var loan = tx("本金", -500); loan.flow = .debt
        var out = tx("提款", -100), into = tx("提款", 100, book: "personal", account: "life")
        out.transferID = UUID(); into.transferID = out.transferID
        l.accounts.append(Account(id: "stash", name: "隐藏", kind: .cash, isPrivate: true))
        l.transactions = [stock, loan, out, into, tx("利息", -50, category: "利息"), tx("后续花材", -300),
                          tx("退花材", 20), tx("销售", 1000, category: "营业收入"), tx("私房", 200, account: "stash")]
        var capital = Capital(total: Money(cents: 1000), openedOn: today, items: [.init(name: "花材", amount: .init(cents: 800), txIDs: [stock.id])])
        _ = try l.setCapital(capital, author: author)
        let report = try l.businessReport(month: today.yearMonth, today: today)
        XCTAssertEqual(report.profit.cents, 670)
        XCTAssertEqual(report.cost.cents, 330)
        XCTAssertEqual(report.takenHome.cents, 100)
        XCTAssertEqual(l.capitalProgress(today: today)?.estimate, .tooEarly)
        capital.openedOn = LocalDate("2026-01-01")
        capital.recoveredBefore = .init(cents: 200)
        _ = try l.setCapital(capital, author: author)
        XCTAssertEqual(l.capitalProgress(today: today)?.recovered.cents, 870)
        XCTAssertEqual(l.capitalProgress(today: today)?.estimate, .notRecovering)
        l.transactions.append(tx("三月收入", 100, category: "营业收入", date: "2026-03-01"))
        XCTAssertEqual(l.capitalProgress(today: today)?.estimate, .months(1))
        l.transactions.append(tx("销售", 100, category: "营业收入"))
        XCTAssertEqual(l.capitalProgress(today: today)?.estimate, .done)
    }
    func testGuessAndMove() throws {
        var l = Ledger.starter
        _ = try l.enableBusinessMode(author: author)
        let bag = tx("书包", -10)
        XCTAssertEqual(SideGuess.guess(bag, current: .business, ledger: l)?.to, .life)
        XCTAssertEqual(SideGuess.guess(tx("批发进货", -10), current: .life, ledger: l)?.to, .business)
        XCTAssertNil(SideGuess.guess(tx("无记录商户", -10), current: .business, ledger: l))
        l.transactions = [bag]
        let c = try l.moveToSide(bag.id, side: .life, author: author)
        XCTAssertEqual(l.transactions[0].bookID, "personal")
        try l.undo(changeID: c.id, author: author)
        XCTAssertEqual(l.transactions[0], bag)
    }
    func testJSONAndPhoneRoundTrip() throws {
        var ledger = Ledger.fresh
        let change = try ledger.startWithBusiness(capital: .init(cents: 500), author: author)
        XCTAssertEqual(ledger.business?.startSide, .business)
        XCTAssertEqual(ledger.lifeBookIDs.count, 1)
        ledger.receivables = [.init(name: "模拟应收", amount: .init(cents: 123))]
        let note = try XCTUnwrap(ledger.syncNote(since: .fresh, device: "模拟手机"))
        var synced = Ledger.fresh
        XCTAssertTrue(synced.apply(note))
        XCTAssertEqual(synced.business, ledger.business)
        XCTAssertEqual(synced.receivables, ledger.receivables)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileLedgerStore(url: dir.appendingPathComponent("synthetic.json"))
        try store.save(.fresh)
        try store.save(ledger)
        let loaded = try store.load()
        XCTAssertEqual(loaded.business, ledger.business)
        XCTAssertEqual(loaded.receivables, ledger.receivables)
        XCTAssertEqual(loaded.minReaderVersion, 2)
        XCTAssertEqual(LedgerBackup.list(for: store.url).count, 1)
        try ledger.undo(changeID: change.id, author: author)
        XCTAssertNil(ledger.business)
        XCTAssertEqual(ledger.books, Ledger.fresh.books)
        let future = Data(#"{"minReaderVersion":99}"#.utf8)
        try future.write(to: store.url)
        XCTAssertEqual(try store.load().minReaderVersion, 99)
        XCTAssertThrowsError(try store.save(ledger))
        XCTAssertEqual(try Data(contentsOf: store.url), future)
    }

    func testOldWriterAndSafeguards() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("demo.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SQLiteLedgerStore(url: url)
        var l = Ledger.starter
        l.transactions = [tx("模拟收款", 100)]
        try store.save(l)
        try SQLiteDB(url: url).exec("DROP TABLE receivables; DELETE FROM meta WHERE key='minReaderVersion'")
        XCTAssertEqual(try store.load(), l)
        _ = try l.enableBusinessMode(author: author)
        l.receivables = [.init(name: "模拟欠款", amount: .init(cents: 200))]
        let original = try Data(contentsOf: url)
        let backupDir = LedgerBackup.folder(for: url)
        try Data().write(to: backupDir)
        XCTAssertThrowsError(try store.save(l))
        XCTAssertEqual(try Data(contentsOf: url), original)
        try FileManager.default.removeItem(at: backupDir)
        try store.save(l)
        let backup = try XCTUnwrap(LedgerBackup.list(for: url).first)
        XCTAssertEqual(try Data(contentsOf: backup.url), original)
        let known = ["books","accounts","transactions","changes","debts","installments","goals","insights","subscriptions","memories","captures","paperwork"]
        let db = try SQLiteDB(url: url)
        for table in known {
            try db.exec("CREATE TEMP TABLE old AS SELECT * FROM \(table); DELETE FROM \(table); INSERT INTO \(table) SELECT * FROM old; DROP TABLE old")
        }
        try db.exec("INSERT OR REPLACE INTO meta SELECT * FROM meta WHERE key IN ('profile','currency','recurring','schemaVersion','lastStatementDate','appliedNotes')")
        // 老 Codable 重写每一条 change 时会扔掉不认识的字段。
        try db.exec("UPDATE changes SET json=json_remove(json, '$.before.changedBusiness', '$.before.business')")
        let loaded = try store.load()
        var reverted = loaded
        try reverted.undo(changeID: try XCTUnwrap(loaded.changes.last?.id), author: author)
        XCTAssertNil(reverted.business)
        XCTAssertEqual(loaded.books, l.books)
        XCTAssertEqual(loaded.transactions, l.transactions)
        XCTAssertEqual(loaded.business, l.business)
        XCTAssertEqual(loaded.receivables, l.receivables)
        try store.save(loaded)
        XCTAssertEqual(LedgerBackup.list(for: url).count, 1)
        try db.exec("UPDATE meta SET value='3' WHERE key='minReaderVersion'")
        let newer = try Data(contentsOf: url)
        XCTAssertEqual(try store.load().minReaderVersion, 3)
        XCTAssertThrowsError(try store.save(l))
        XCTAssertEqual(try Data(contentsOf: url), newer)
    }
}

extension BusinessTests {
    func testDescribeOnlyRoutedEntries() throws {
        var ledger = Ledger.starter
        _ = try ledger.enableBusinessMode(author: author)
        var explicit = tx("书包", -100, book: "personal")
        XCTAssertNil(try ledger.routeEntry(&explicit, side: nil))
        XCTAssertNil(try ledger.routeEntry(&explicit, side: "life"))
        var automatic = explicit
        automatic.bookID = nil
        XCTAssertEqual(try ledger.routeEntry(&automatic, side: nil), "放到生活（说明里有「书包」）")
        XCTAssertEqual(automatic.bookID, "personal")
        automatic.bookID = nil
        XCTAssertEqual(try ledger.routeEntry(&automatic, side: "business"), "放到生意（指定了生意）")
        _ = ledger.disableBusinessMode(author: author)
        automatic.bookID = nil
        XCTAssertNil(try ledger.routeEntry(&automatic, side: "business"))
    }

    func testLoadRecoversHotRollbackJournal() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.sqlite")
        let interrupted = dir.appendingPathComponent("interrupted.sqlite")
        try SQLiteLedgerStore(url: source).save(.starter)
        let writer = try SQLiteDB(url: source)
        try writer.exec("PRAGMA cache_size=1; PRAGMA cache_spill=1; PRAGMA synchronous=FULL; BEGIN IMMEDIATE")
        try writer.exec("DELETE FROM books; INSERT INTO meta VALUES ('spill', zeroblob(262144))")
        // 复制已经写出脏页、仍未提交的文件对，模拟进程在这里退出。
        try fm.copyItem(at: source, to: interrupted)
        let journal = URL(fileURLWithPath: interrupted.path + "-journal")
        try fm.copyItem(at: URL(fileURLWithPath: source.path + "-journal"), to: journal)
        try writer.exec("ROLLBACK")
        XCTAssertThrowsError(try SQLiteDB(url: interrupted, readOnly: true).query("SELECT json FROM books"))
        XCTAssertEqual(try SQLiteLedgerStore(url: interrupted).load(), .starter)
        XCTAssertFalse(fm.fileExists(atPath: journal.path))
    }

    func testWritableConnectionRestoresDeleteJournalMode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.sqlite")
        let store = SQLiteLedgerStore(url: url)
        try store.save(.fresh)
        XCTAssertEqual(try SQLiteDB(url: url).query("PRAGMA journal_mode=WAL"), ["wal"])
        _ = try store.load()
        XCTAssertEqual(try SQLiteDB(url: url, readOnly: true).query("PRAGMA journal_mode"), ["delete"])
    }

    func testDemoShowsPartialRecoveryAndEstimate() throws {
        let end = LocalDate("2026-11-25")!
        let ledger = DemoData.make(endingOn: end)
        let progress = try XCTUnwrap(ledger.capitalProgress(today: end))
        XCTAssertTrue((0.4...0.6).contains(progress.fraction))
        guard case .months(let months) = progress.estimate else { return XCTFail("示例应能估算回本月数") }
        XCTAssertGreaterThan(months, 0)
        let capital = try XCTUnwrap(ledger.business?.capital)
        XCTAssertEqual(capital.items.reduce(Money.zero) { $0 + $1.amount }, capital.total)
    }
}
