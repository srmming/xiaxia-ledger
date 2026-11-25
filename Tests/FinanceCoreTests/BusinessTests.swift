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
    func testJSONRejectsBusinessAndReceivablesWithoutChangingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileLedgerStore(url: dir.appendingPathComponent("synthetic.json"))
        try store.save(.fresh)
        let original = try Data(contentsOf: store.url)
        var ledger = Ledger.fresh
        _ = try ledger.startWithBusiness(capital: .init(cents: 500), author: author)
        for value in [ledger, { var l = Ledger.fresh; l.receivables = [.init(name: "模拟应收", amount: .init(cents: 123))]; return l }()] {
            XCTAssertThrowsError(try store.save(value)) { XCTAssertEqual($0.localizedDescription, "生意模式需要 SQLite 账本") }
            XCTAssertEqual(try Data(contentsOf: store.url), original)
        }
        ledger = .fresh
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
        l = try store.load()
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
        try store.save(try store.load())
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

extension BusinessTests {
    func testPhoneRejectsBusinessChangesBeforeWritingNote() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let phone = PhoneSyncStore(folder: dir, cache: dir.appendingPathComponent("cache.sqlite"))
        let original = try phone.load()
        var settings = original
        _ = try settings.enableBusinessMode(author: author)
        var debt = original
        debt.receivables = [.init(name: "模拟应收", amount: .init(cents: 20))]
        for change in [settings, debt] {
            XCTAssertThrowsError(try phone.save(change)) { XCTAssertTrue($0.localizedDescription.contains("在 Mac 上修改")) }
            XCTAssertTrue(SyncNotes.files(in: SyncNotes.inbox(dir)).isEmpty)
            XCTAssertEqual(try phone.load(), original)
        }
        var ordinary = original
        ordinary.transactions.append(tx("手机记账", 200, book: "personal"))
        try phone.save(ordinary)
        XCTAssertEqual(SyncNotes.files(in: SyncNotes.inbox(dir)).count, 1)
    }

    func testCannotSwitchBooksWithCapital() throws {
        var l = Ledger.starter
        _ = try l.enableBusinessMode(author: author)
        let capitalChange = try l.setCapital(.init(total: .init(cents: 100)), author: author)
        l.books.append(Book(id: "second", name: "二店", kind: .business))
        let before = l
        XCTAssertThrowsError(try l.enableBusinessMode(choose: "second", author: author)) {
            XCTAssertTrue($0.localizedDescription.contains("清掉"))
        }
        XCTAssertEqual(l, before)
        try l.undo(changeID: capitalChange.id, author: author)
        _ = try l.enableBusinessMode(choose: "second", author: author)
        XCTAssertEqual(l.businessBook?.id, "second")
    }

    func testTakeHomeUsesTransferIDBeforeDate() throws {
        var l = Ledger.starter
        _ = try l.enableBusinessMode(author: author)
        var out = tx("拿回家", -1000, account: "shop")
        var home = tx("生活收款", 1000, book: "personal", date: "2026-04-02", account: "life")
        var unrelated = tx("店内同额入账", 1000, account: "other")
        out.flow = .internal; home.flow = .internal; unrelated.flow = .internal
        out.transferID = UUID(); home.transferID = out.transferID
        l.transactions = [out, unrelated, home]
        XCTAssertEqual(try l.businessReport(month: today.yearMonth, today: today).takenHome.cents, 1000)
        // 少了明确配对的收款端，也不能用其他编号或未配对的流水补上。
        l.transactions.removeLast()
        unrelated.bookID = "personal"
        l.transactions.append(unrelated)
        XCTAssertEqual(try l.businessReport(month: today.yearMonth, today: today).takenHome.cents, 0)
    }

    func testWALBackupFailurePreservesBytesAndRetryBacksUpCommittedRows() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let src = dir.appendingPathComponent("source.sqlite")
        let url = dir.appendingPathComponent("active.sqlite")
        try SQLiteLedgerStore(url: src).save(.starter)
        let db = try SQLiteDB(url: src)
        try db.exec("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; DELETE FROM books WHERE id='miora'")
        // 模拟关闭前复制的主文件和 WAL，已提交的删除仍只在 WAL 里。
        for suffix in ["", "-wal"] {
            try fm.copyItem(atPath: src.path + suffix, toPath: url.path + suffix)
        }
        let wal = URL(fileURLWithPath: url.path + "-wal")
        let mainBytes = try Data(contentsOf: url), walBytes = try Data(contentsOf: wal)
        let store = SQLiteLedgerStore(url: url)
        var ledger = try store.load()
        XCTAssertEqual(ledger.books.map(\.id), ["personal"])
        _ = try ledger.enableBusinessMode(author: author)
        let folder = LedgerBackup.folder(for: url)
        try Data().write(to: folder)
        XCTAssertThrowsError(try store.save(ledger))
        XCTAssertEqual(try Data(contentsOf: url), mainBytes)
        XCTAssertEqual(try Data(contentsOf: wal), walBytes)
        XCTAssertEqual(try SQLiteDB.reader(url: url).query("PRAGMA journal_mode"), ["wal"])
        try fm.removeItem(at: folder)
        try store.save(ledger)
        let backup = try XCTUnwrap(LedgerBackup.list(for: url).first)
        let restored = try LedgerBackup.load(backup.url)
        XCTAssertEqual(restored.books.map(\.id), ["personal"])
        XCTAssertNil(restored.business)
        XCTAssertEqual(try store.load().business, ledger.business)
        XCTAssertEqual(try SQLiteDB.reader(url: url).query("PRAGMA journal_mode"), ["delete"])
    }

    func testDisabledContextOmitsBusinessKeys() throws {
        var l = Ledger.starter
        _ = try l.enableBusinessMode(author: author)
        let encoder = JSONEncoder()
        func fields() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(LedgerContext(ledger: l))) as? [String: Any])
        }
        XCTAssertEqual(try fields()["businessEnabled"] as? Bool, true)
        _ = l.disableBusinessMode(author: author)
        let context = try fields()
        for key in ["businessEnabled", "businessBookID", "lifeBookIDs"] { XCTAssertNil(context[key]) }
    }
}

extension BusinessTests {
    func testConcurrentWALCommitRequiresReloadAndIsIncludedInUpgradeBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SQLiteLedgerStore(url: dir.appendingPathComponent("synthetic.sqlite"))
        try store.save(.starter)
        var stale = try store.load()
        _ = try stale.enableBusinessMode(author: author)

        let payment = tx("另一窗口的模拟收款", 1234)
        func insertPayment(_ db: SQLiteDB, _ entry: Transaction) throws {
            let json = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
            try db.run("""
                INSERT INTO transactions (id,seq,date,amount_cents,account_id,book_id,description,json)
                VALUES (?,1,?,?,?,?,?,?)
                """, [entry.id.uuidString, entry.date.description, entry.amount.cents, entry.accountID, entry.bookID, entry.description, json])
        }
        do {
            let other = try SQLiteDB(url: store.url)
            try other.exec("PRAGMA journal_mode=WAL")
            try insertPayment(other, payment)
        }
        // 对方已经提交并关闭连接。此时没有锁竞争，必须靠快照校验拦下旧数据。
        let bytes = try Data(contentsOf: store.url)
        XCTAssertThrowsError(try store.save(stale)) {
            XCTAssertEqual($0.localizedDescription, "账本刚被别处改过，请再试一次")
        }
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        XCTAssertTrue(LedgerBackup.list(for: store.url).isEmpty)

        var retry = try store.load()
        XCTAssertEqual(retry.transactions, [payment])
        XCTAssertNil(retry.business)
        _ = try retry.enableBusinessMode(author: author)
        var testedLock = false
        try store.save(retry) { source, destination in
            // 来自另一连接的普通写入必须等候；此处设为零等待，让测试无需依靠定时或轮询。
            let other = try SQLiteDB(url: store.url)
            try other.exec("PRAGMA busy_timeout=0")
            XCTAssertThrowsError(try insertPayment(other, self.tx("同时记账", 200))) {
                XCTAssertTrue($0.localizedDescription.contains("locked"))
            }
            try source.writeSnapshot(to: destination)
            testedLock = true
        }
        XCTAssertTrue(testedLock)
        let backup = try XCTUnwrap(LedgerBackup.list(for: store.url).first)
        let original = try LedgerBackup.load(backup.url)
        let upgraded = try store.load()
        XCTAssertNil(original.business)
        XCTAssertEqual(upgraded.business, retry.business)
        XCTAssertEqual(original.transactions, [payment])
        XCTAssertEqual(upgraded.transactions, [payment])
    }
}

extension BusinessTests {
    func testCompetingBusinessUpgradeCannotOverwriteWinner() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SQLiteLedgerStore(url: dir.appendingPathComponent("two-writers.sqlite"))
        try store.save(.starter)
        var first = try store.load(), second = try store.load()
        _ = try first.enableBusinessMode(author: "甲")
        _ = try second.enableBusinessMode(author: "乙")
        first.transactions.append(tx("甲窗口的模拟收款", 345))
        try store.save(first)
        let bytes = try Data(contentsOf: store.url)
        XCTAssertThrowsError(try store.save(second)) {
            XCTAssertEqual($0.localizedDescription, "账本刚被别处改过，请再试一次")
        }
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        XCTAssertEqual(try store.load().transactions, first.transactions)
        XCTAssertEqual(LedgerBackup.list(for: store.url).count, 1)
    }
}

extension BusinessTests {
    func testPreUpgradeEntryCannotOverwriteBusinessInDeleteMode() throws {
        try checkPreUpgradeEntry(wal: false)
    }

    func testPreUpgradeEntryCannotOverwriteBusinessInWALMode() throws {
        try checkPreUpgradeEntry(wal: true)
    }

    private func checkPreUpgradeEntry(wal: Bool) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SQLiteLedgerStore(url: dir.appendingPathComponent("synthetic.sqlite"))
        var seed = Ledger.starter
        seed.accounts = [Account(id: "shop", name: "模拟现金", kind: .cash)]
        try store.save(seed)
        if wal { try SQLiteDB(url: store.url).exec("PRAGMA journal_mode=WAL") }

        var ordinary = try store.load(), owner = try store.load()
        let first = tx("升级时的模拟收款", 200), second = tx("升级后继续记账", 300)
        _ = try owner.enableBusinessMode(author: "窗口甲")
        try owner.addTransaction(first, author: "窗口甲")
        try store.save(owner)
        try owner.addTransaction(second, author: "窗口甲")
        try store.save(owner) // 原升级窗口不重新读，也能继续记。

        // 升级默认转回 DELETE；也覆盖数据库实际使用 WAL 时的独占锁入口。
        if wal { try SQLiteDB(url: store.url).exec("PRAGMA journal_mode=WAL") }
        let mode = wal ? "wal" : "delete"
        XCTAssertEqual(try SQLiteDB.reader(url: store.url).query("PRAGMA journal_mode"), [mode])
        let bytes = try Data(contentsOf: store.url)
        let other = tx("另一个窗口的模拟收款", 400)
        try ordinary.addTransaction(other, author: "窗口乙")
        XCTAssertThrowsError(try store.save(ordinary)) {
            XCTAssertEqual($0.localizedDescription, "账本刚被别处改过，请再试一次")
        }
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        XCTAssertEqual(try SQLiteDB.reader(url: store.url).query("PRAGMA journal_mode"), [mode])
        var latest = try store.load()
        XCTAssertEqual(latest.business, owner.business)
        XCTAssertEqual(latest.transactions, [first, second])
        try latest.addTransaction(other, author: "窗口乙")
        try store.save(latest)
        XCTAssertEqual(try store.load().transactions, [first, second, other])
    }

    func testTwoOrdinarySQLiteWindowsRejectStaleSave() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SQLiteLedgerStore(url: dir.appendingPathComponent("legacy.sqlite"))
        var seed = Ledger.starter
        seed.accounts = [Account(id: "shop", name: "模拟现金", kind: .cash)]
        try store.save(seed)
        var first = try store.load(), second = try store.load()
        try first.addTransaction(tx("甲", 100), author: "甲")
        try store.save(first)
        try second.addTransaction(tx("乙", 200), author: "乙")
        XCTAssertThrowsError(try store.save(second)) { XCTAssertEqual($0.localizedDescription, "账本刚被别处改过，请再试一次") }
        let last = try store.load()
        XCTAssertEqual(last.minReaderVersion, 1)
        XCTAssertEqual(last.transactions, first.transactions)
    }
}
