import XCTest
@testable import FinanceCore

/// 手机随手记、小票发票、报销、手机和 Mac 同步。全部用编造的数据。
final class PhoneCaptureTests: XCTestCase {
    let today = LocalDate(year: 2026, month: 11, day: 23)

    func sample() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "card", name: "示例卡", kind: .bank)]
        return l
    }

    // MARK: 一句话、小票文字

    func testSentenceGuess() {
        var g = CaptureGuess.parse(sentence: "今天午饭 10 欧", today: today)
        XCTAssertEqual(g.amount, Money(cents: -1000)); XCTAssertEqual(g.date, today)
        g = CaptureGuess.parse(sentence: "昨天打车花了12,50", today: today)
        XCTAssertEqual(g.amount, Money(cents: -1250)); XCTAssertEqual(g.date, LocalDate(year: 2026, month: 11, day: 22))
        g = CaptureGuess.parse(sentence: "收到报销 45.80€", today: today)
        XCTAssertEqual(g.amount, Money(cents: 4580))
        g = CaptureGuess.parse(sentence: "11月20日 超市 32,15 欧", today: today)
        XCTAssertEqual(g.date, LocalDate(year: 2026, month: 11, day: 20)); XCTAssertEqual(g.amount, Money(cents: -3215))
        // 看不出金额就不猜
        g = CaptureGuess.parse(sentence: "给妈妈买了花", today: today)
        XCTAssertNil(g.amount)
    }

    func testReceiptGuess() {
        let text = """
        CAFETERIA EJEMPLO SL
        NIF B00000000
        Fecha: 21/11/2026 10:42
        2 x Cafe con leche   3,40
        1 x Tostada          2,10
        SUBTOTAL             5,00
        IVA 10%              0,50
        TOTAL                5,50
        EFECTIVO            10,00
        CAMBIO               4,50
        """
        let g = CaptureGuess.parse(receipt: text, today: today)
        XCTAssertEqual(g.amount, Money(cents: -550))
        XCTAssertEqual(g.date, LocalDate(year: 2026, month: 11, day: 21))
        XCTAssertEqual(g.merchant, "CAFETERIA EJEMPLO SL")
        // 没有「合计」行：不猜金额
        XCTAssertNil(CaptureGuess.parse(receipt: "TIENDA\n3,40\n2,10", today: today).amount)
    }

    // MARK: 待记录入账、对上、不记、撤销

    func testResolveLinkDismissUndo() throws {
        var l = sample()
        let c1 = Capture(kind: .text, text: "午饭 10 欧", guess: CaptureGuess(amount: Money(cents: -1000), date: today), device: "iPhone")
        let c2 = Capture(kind: .photo, text: "", photo: "p1.jpg", guess: CaptureGuess(amount: Money(cents: -550)), device: "iPhone")
        let c3 = Capture(kind: .text, text: "记错了", device: "iPhone")
        for c in [c1, c2, c3] { l.addCapture(c, author: "ming") }
        XCTAssertEqual(l.pendingCaptures.count, 3)

        let tx = Transaction(date: today, amount: Money(cents: -1000), description: "午饭", accountID: "card", bookID: "personal", category: "餐饮")
        let change = try l.resolveCapture(c1.id, as: tx, author: "Claude")
        XCTAssertEqual(l.transactions.count, 1)
        XCTAssertEqual(l.captures.first { $0.id == c1.id }?.status, .done)
        XCTAssertThrowsError(try l.resolveCapture(c1.id, as: tx, author: "Claude")) { XCTAssertEqual($0 as? CaptureError, .alreadyHandled) }

        // 小票对上银行导进来的那笔：不新记，照片挂上去
        let bank = Transaction(date: today, amount: Money(cents: -550), description: "CAFETERIA", accountID: "card")
        l.transactions.append(bank)
        XCTAssertEqual(l.possibleMatches(for: l.captures.first { $0.id == c2.id }!).map(\.id), [bank.id])
        try l.linkCapture(c2.id, to: bank.id, author: "Claude")
        XCTAssertEqual(l.paperwork(for: bank.id)?.attachments.map(\.file), ["p1.jpg"])
        XCTAssertEqual(l.transactions.count, 2)

        try l.dismissCapture(c3.id, reason: "重复", author: "ming")
        XCTAssertTrue(l.pendingCaptures.isEmpty)

        // 撤销入账：流水删掉、待记录回到没入账
        _ = try l.undo(changeID: change.id, author: "ming")
        XCTAssertFalse(l.transactions.contains { $0.id == tx.id })
        XCTAssertEqual(l.captures.first { $0.id == c1.id }?.status, .pending)
    }

    // MARK: 小票发票、报销

    func testAttachAndReimburse() throws {
        var l = sample()
        let a = Transaction(date: today, amount: Money(cents: -2390), description: "出差午饭", accountID: "card")
        let b = Transaction(date: today.adding(days: -3), amount: Money(cents: -4500), description: "火车票", accountID: "card")
        l.transactions = [a, b]
        let att = Attachment(kind: .invoice, file: "inv.pdf", name: "发票.pdf", addedBy: "ming")
        let ch = try l.attach(att, to: a.id, author: "ming")
        XCTAssertEqual(l.paperwork(for: a.id)?.attachments.count, 1)
        XCTAssertTrue(l.paperwork(for: a.id)!.attachments[0].isPDF)
        _ = try l.undo(changeID: ch.id, author: "ming")
        XCTAssertNil(l.paperwork(for: a.id))
        try l.attach(att, to: a.id, author: "ming")

        try l.setReimbursement([a.id, b.id], status: .toSubmit, to: "示例公司", author: "ming")
        var s = l.reimbursementSummary
        XCTAssertEqual(s.toSubmit, Money(cents: 6890)); XCTAssertEqual(s.outstanding, Money(cents: 6890))
        let sub = try l.setReimbursement([b.id], status: .submitted, on: today, author: "ming")
        XCTAssertEqual(l.paperwork(for: b.id)?.submittedOn, today)
        try l.setReimbursement([a.id], status: .paid, on: today, author: "ming")
        s = l.reimbursementSummary
        XCTAssertEqual(s.paid, Money(cents: 2390)); XCTAssertEqual(s.submitted, Money(cents: 4500)); XCTAssertEqual(s.toSubmit, .zero)
        XCTAssertEqual(l.reimbursements(.submitted).map(\.id), [b.id])
        // 附件还在
        XCTAssertEqual(l.paperwork(for: a.id)?.attachments.count, 1)
        _ = try l.undo(changeID: sub.id, author: "ming")
        XCTAssertEqual(l.paperwork(for: b.id)?.reimburse, .toSubmit)

        let csv = l.reimbursementCSV(l.reimbursements())
        XCTAssertTrue(csv.hasPrefix("日期,名称,金额,找谁报销,状态"))
        XCTAssertTrue(csv.contains("\"出差午饭\",23.90,\"示例公司\",已到账"))
        XCTAssertTrue(csv.contains("合计,68.90"))
    }

    // MARK: 手机纸条：比较、收、收两遍

    func testSyncNoteRoundTrip() throws {
        var mac = sample()
        mac.transactions = [Transaction(date: today, amount: Money(cents: -100), description: "旧的", accountID: "card")]
        var phone = mac
        let added = Transaction(date: today, amount: Money(cents: -1000), description: "午饭", accountID: "card")
        try phone.addTransaction(added, author: "ming")
        phone.addCapture(Capture(kind: .text, text: "打车 12 欧", device: "iPhone"), author: "ming")
        phone.transactions.removeAll { $0.description == "旧的" }

        let note = try XCTUnwrap(phone.syncNote(since: mac, device: "iPhone"))
        XCTAssertEqual(note.transactions?.map(\.id), [added.id])
        XCTAssertEqual(note.deletes?["transactions"]?.count, 1)
        XCTAssertTrue(note.summary.contains("午饭"))
        XCTAssertNil(phone.syncNote(since: phone, device: "iPhone"))

        // 同时 Mac 上也记了一笔：收纸条后两笔都在
        let macTx = Transaction(date: today, amount: Money(cents: -300), description: "Mac 记的", accountID: "card")
        try mac.addTransaction(macTx, author: "Claude")
        XCTAssertTrue(mac.apply(note))
        XCTAssertFalse(mac.apply(note))     // 收过的不再收
        XCTAssertEqual(Set(mac.transactions.map(\.description)), ["午饭", "Mac 记的"])
        XCTAssertEqual(mac.pendingCaptures.count, 1)
        XCTAssertEqual(mac.appliedNotes, [note.id])

        // 纸条能存成 JSON 再读回来
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(SyncNote.self, from: enc.encode(note))
        XCTAssertEqual(back.id, note.id)
        XCTAssertEqual(back.transactions, note.transactions)
        XCTAssertEqual(back.captures?.map(\.id), note.captures?.map(\.id))
        XCTAssertEqual(back.deletes, note.deletes)
    }

    // MARK: 文件夹里实际走一遍：手机写纸条 → Mac 读账本时收

    #if canImport(SQLite3)
    func testPhoneAndMacThroughFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xia-sync-\(UUID().uuidString)")
        let folder = dir.appendingPathComponent("夏夏账本")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mac = InboxApplyingStore(primary: SQLiteLedgerStore(url: folder.appendingPathComponent("ledger.sqlite")), folder: folder)
        var start = sample()
        start.transactions = [Transaction(date: today, amount: Money(cents: -100), description: "示例", accountID: "card")]
        try mac.save(start)
        let file = folder.appendingPathComponent("ledger.sqlite")
        let beforePhone = try Data(contentsOf: file)

        let phone = PhoneSyncStore(folder: folder, cache: dir.appendingPathComponent("phone/cache.sqlite"))
        var p = try phone.load()
        XCTAssertEqual(p.transactions.count, 1)
        let stamp = phone.changeStamp()
        try p.addTransaction(Transaction(date: today, amount: Money(cents: -1000), description: "手机记的午饭", accountID: "card"), author: "ming")
        p.addCapture(Capture(kind: .photo, text: "", photo: "x.jpg", device: "iPhone"), author: "ming")
        try phone.save(p)
        XCTAssertNotEqual(phone.changeStamp(), stamp)
        XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: folder), 1)
        // 账本文件本身手机没动
        XCTAssertEqual(try SQLiteLedgerStore(url: folder.appendingPathComponent("ledger.sqlite")).load().transactions.count, 1)
        // 手机重新读：账本 + 自己的纸条
        XCTAssertEqual(try phone.load().transactions.count, 2)

        // Mac 读：收进来、存盘、纸条挪进「已收」
        let m = try mac.load()
        XCTAssertEqual(m.transactions.count, 2)
        XCTAssertEqual(m.pendingCaptures.count, 1)
        XCTAssertEqual(SyncNotes.pendingCount(ledgerFolder: folder), 0)
        XCTAssertEqual(SyncNotes.files(in: SyncNotes.done(folder)).count, 1)
        XCTAssertEqual(try SQLiteLedgerStore(url: folder.appendingPathComponent("ledger.sqlite")).load().transactions.count, 2)
        // 再读一遍不会多出来；手机看到的也还是 2 笔（不会收两遍）
        XCTAssertEqual(try mac.load().transactions.count, 2)
        XCTAssertEqual(try phone.load().transactions.count, 2)

        // Mac 被旧的一份覆盖（收过的丢了）：「已收」里的纸条下次读时补回来
        XCTAssertThrowsError(try SQLiteLedgerStore(url: file).save(start))
        try beforePhone.write(to: file, options: .atomic) // 模拟外部同步送回旧文件
        XCTAssertEqual(try mac.load().transactions.count, 2)
    }

    func testNewTablesSurviveSQLite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xia-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var l = sample()
        let t = Transaction(date: today, amount: Money(cents: -500), description: "x", accountID: "card")
        l.transactions = [t]
        l.addCapture(Capture(kind: .text, text: "咖啡 2 欧", guess: CaptureGuess(amount: Money(cents: -200)),
                             createdAt: Date(timeIntervalSince1970: 1_795_000_000), device: "iPhone"), author: "ming")
        try l.setReimbursement([t.id], status: .submitted, to: "示例公司", author: "ming")
        l.appliedNotes = ["a", "b"]
        let s = SQLiteLedgerStore(url: url)
        try s.save(l)
        let back = try s.load()
        XCTAssertEqual(back.captures, l.captures)
        XCTAssertEqual(back.paperwork, l.paperwork)
        XCTAssertEqual(back.appliedNotes, ["a", "b"])
    }
    #endif

    func testDemoLedgerHasPhoneNotesAndReimbursements() {
        let l = DemoData.make(endingOn: LocalDate(year: 2026, month: 11, day: 21))
        XCTAssertEqual(l.pendingCaptures.count, 2)
        XCTAssertEqual(l.paperwork.map(\.reimburse), [.toSubmit, .submitted, .paid])
        XCTAssertGreaterThan(l.reimbursementSummary.outstanding.cents, 0)
    }
}
