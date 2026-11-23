import XCTest
@testable import FinanceCore

// 测试只用编造的数字，真实流水不进仓库。
final class MoneyTests: XCTestCase {
    func testSpanishFormat() {
        XCTAssertEqual(Money(cents: 123456).formatted, "1.234,56 €")
        XCTAssertEqual(Money(cents: -5).formatted, "-0,05 €")
        XCTAssertEqual(Money(cents: 100000000).formatted, "1.000.000,00 €")
        XCTAssertEqual(Money(cents: 99900).formatted, "999,00 €")
    }

    func testParsing() {
        XCTAssertEqual(Money(parsing: "1.234,56")?.cents, 123456)
        XCTAssertEqual(Money(parsing: "-12,3")?.cents, -1230)
        XCTAssertEqual(Money(parsing: "1234.56")?.cents, 123456)
        XCTAssertEqual(Money(parsing: "1.234")?.cents, 123400)
        XCTAssertEqual(Money(parsing: "12 €")?.cents, 1200)
        XCTAssertNil(Money(parsing: "abc"))
    }

    func testDecimalString() {
        XCTAssertEqual(Money(cents: -123405).decimalString, "-1234.05")
    }
}

final class SummaryTests: XCTestCase {
    let d = LocalDate(year: 2026, month: 10, day: 3)

    func testTransfersCancelInAllButCountPerBook() {
        let transfer = UUID()
        let txs = [
            Transaction(date: d, amount: Money(cents: 50000), description: "Servicios", accountID: "bank", bookID: "miora", category: "收入"),
            Transaction(date: d, amount: Money(cents: -20000), description: "Retirada", accountID: "bank", bookID: "miora", category: "老板提款", transferID: transfer),
            Transaction(date: d, amount: Money(cents: 20000), description: "Retirada", accountID: "bank", bookID: "personal", category: "收入", transferID: transfer),
            Transaction(date: d, amount: Money(cents: -1500), description: "Mercadona", accountID: "cash", bookID: "personal", category: "餐饮"),
        ]
        let m = YearMonth(year: 2026, month: 10)
        let all = Summaries.monthly(txs, month: m, bookID: nil)
        XCTAssertEqual(all.income.cents, 50000)
        XCTAssertEqual(all.expense.cents, -1500)

        let miora = Summaries.monthly(txs, month: m, bookID: "miora")
        XCTAssertEqual(miora.net.cents, 30000)
        let personal = Summaries.monthly(txs, month: m, bookID: "personal")
        XCTAssertEqual(personal.income.cents, 20000)
    }
}

final class DedupTests: XCTestCase {
    func testDropsDuplicatesButKeepsRealRepeats() {
        let d = LocalDate(year: 2026, month: 11, day: 2)
        let coffee = Transaction(date: d, amount: Money(cents: -150), description: "CAFÉ Bar", accountID: "revolut")
        let existing = [coffee]
        let incoming = [
            Transaction(date: d, amount: Money(cents: -150), description: "cafe  bar", accountID: "revolut"),
            Transaction(date: d, amount: Money(cents: -150), description: "Cafe Bar", accountID: "revolut"),
        ]
        XCTAssertEqual(Dedup.newTransactions(incoming, existing: existing).count, 1)
    }
}

final class StoreTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONFileLedgerStore(url: url)
        XCTAssertEqual(try store.load(), .fresh)
        var ledger = Ledger.starter
        ledger.accounts = [Account(id: "cash", name: "现金", kind: .cash)]
        ledger.transactions = [Transaction(date: LocalDate(year: 2026, month: 1, day: 5), amount: Money(cents: -999), description: "x", accountID: "cash")]
        try store.save(ledger)
        XCTAssertEqual(try store.load(), ledger)
    }
}

final class PlansTests: XCTestCase {
    func testDebtOutstandingAndLoanNotExpense() {
        let d0 = LocalDate(year: 2026, month: 9, day: 1)
        let lend = Transaction(date: d0, amount: Money(cents: -30000), description: "借给朋友", accountID: "bank", bookID: "personal", flow: .debt)
        let back = Transaction(date: LocalDate(year: 2026, month: 10, day: 1), amount: Money(cents: 10000), description: "还款", accountID: "bank", bookID: "personal", flow: .debt)
        var ledger = Ledger.starter
        ledger.transactions = [lend, back]
        ledger.debts = [Debt(counterparty: "朋友 A", direction: .theyOweMe, principal: Money(cents: 30000), bookID: "personal",
                             startDate: d0, dueDate: LocalDate(year: 2026, month: 10, day: 15), repaymentIDs: [back.id])]
        let list = Plans.debts(ledger, today: LocalDate(year: 2026, month: 11, day: 21))
        XCTAssertEqual(list.first?.outstanding.cents, 20000)
        XCTAssertEqual(list.first?.overdue, true)
        // 借出去的钱不算支出
        XCTAssertEqual(Summaries.monthly(ledger.transactions, month: YearMonth(year: 2026, month: 9), bookID: nil).expense.cents, 0)
    }

    func testInstallmentProgress() {
        let p1 = Transaction(date: LocalDate(year: 2026, month: 10, day: 5), amount: Money(cents: -10000), description: "分期 1/6", accountID: "bank")
        var ledger = Ledger.starter
        ledger.transactions = [p1]
        ledger.installments = [Installment(name: "美甲灯", bookID: "miora", accountID: "bank", total: Money(cents: 60000),
                                           count: 6, firstDate: LocalDate(year: 2026, month: 10, day: 5), paidIDs: [p1.id])]
        let s = Plans.installments(ledger).first!
        XCTAssertEqual(s.paidCount, 1)
        XCTAssertEqual(s.remaining.cents, 50000)
        XCTAssertEqual(s.nextDate, LocalDate(year: 2026, month: 11, day: 5))
    }

    func testGoalBySavingsAccount() {
        var ledger = Ledger.starter
        ledger.accounts = [Account(id: "pot", name: "储蓄罐", kind: .savings)]
        ledger.transactions = [Transaction(date: LocalDate(year: 2026, month: 11, day: 1), amount: Money(cents: 150000), description: "存入", accountID: "pot", flow: .saving)]
        ledger.goals = [Goal(name: "应急金", bookID: "personal", target: Money(cents: 600000), savingsAccountID: "pot")]
        XCTAssertEqual(Plans.goals(ledger).first?.percent, 25)
    }

    func testOldLedgerFileStillDecodes() throws {
        let json = #"{"schemaVersion":1,"books":[{"id":"personal","name":"个人","currency":"EUR"}],"accounts":[],"transactions":[]}"#
        let ledger = try JSONDecoder().decode(Ledger.self, from: Data(json.utf8))
        XCTAssertEqual(ledger.books.count, 1)
        XCTAssertTrue(ledger.debts.isEmpty)
    }
}

final class EditorTests: XCTestCase {
    func sample() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "银行", kind: .bank), Account(id: "stash", name: "私房钱", kind: .cash, isPrivate: true)]
        return l
    }

    func testDebtAddRepayUndo() throws {
        var l = sample()
        let d0 = LocalDate(year: 2026, month: 11, day: 1)
        let (debt, add) = try l.addDebt(counterparty: "阿华", direction: .theyOweMe, amount: Money(cents: 50000),
                                        bookID: "personal", date: d0, accountID: "bank", author: "测试")
        XCTAssertEqual(l.transactions.first?.amount.cents, -50000)
        XCTAssertEqual(l.transactions.first?.flow, .debt)
        let repay = try l.repay(debtID: debt.id, amount: Money(cents: 20000), date: LocalDate(year: 2026, month: 11, day: 10),
                                accountID: "bank", author: "测试")
        XCTAssertEqual(Plans.debts(l, today: d0).first?.outstanding.cents, 30000)
        XCTAssertEqual(l.openDebts(named: "阿华").count, 1)
        // 借款和还款都不算收支
        XCTAssertEqual(Summaries.monthly(l.transactions, month: d0.yearMonth, bookID: "personal").expense.cents, 0)
        // 还有还款时不能先撤销借款
        XCTAssertThrowsError(try l.undo(changeID: add.id, author: "测试"))
        try l.undo(changeID: repay.id, author: "测试")
        XCTAssertEqual(Plans.debts(l, today: d0).first?.outstanding.cents, 50000)
        try l.undo(changeID: add.id, author: "测试")
        XCTAssertTrue(l.debts.isEmpty)
        XCTAssertTrue(l.transactions.isEmpty)
        XCTAssertThrowsError(try l.undo(changeID: add.id, author: "测试"))
    }

    func testPrivateAccountHiddenFromSummary() throws {
        var l = sample()
        let d = LocalDate(year: 2026, month: 11, day: 3)
        try l.addTransaction(Transaction(date: d, amount: Money(cents: -1000), description: "咖啡", accountID: "bank", bookID: "personal"), author: "ming")
        try l.addTransaction(Transaction(date: d, amount: Money(cents: -5000), description: "偷偷买的", accountID: "stash", bookID: "personal"), author: "ming")
        XCTAssertEqual(Summaries.monthly(l.transactions, month: d.yearMonth, bookID: nil, hiddenAccounts: l.privateAccountIDs).expense.cents, -1000)
        XCTAssertEqual(Summaries.monthly(l.transactions, month: d.yearMonth, bookID: nil).expense.cents, -6000)
        XCTAssertEqual(l.changes.count, 2)
    }

    func testUnknownAccountRejected() {
        var l = sample()
        XCTAssertThrowsError(try l.addTransaction(Transaction(date: .today, amount: Money(cents: 1), description: "x", accountID: "nope"), author: "ming"))
    }

    func testOldAccountJSONDecodes() throws {
        let a = try JSONDecoder().decode(Account.self, from: Data(#"{"id":"cash","name":"现金","kind":"cash"}"#.utf8))
        XCTAssertFalse(a.isPrivate)
    }
}

final class ImportTests: XCTestCase {
    // 编造的 Revolut 导出，格式和真实文件一样。
    let revolut = """
    Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
    CARD_PAYMENT,Current,2026-11-03 10:01:02,2026-11-04 09:00:00,Mercadona,-23.45,0.00,EUR,COMPLETED,976.55
    TOPUP,Current,2026-11-01 08:00:00,2026-11-01 08:00:01,"Top-up by *1234",1000.00,0.00,EUR,COMPLETED,1000.00
    CARD_PAYMENT,Current,2026-11-05 12:00:00,,Pending shop,-5.00,0.00,EUR,PENDING,
    CARD_PAYMENT,Current,2026-11-06 12:00:00,2026-11-06 12:00:00,Tienda UK,-10.00,0.00,GBP,COMPLETED,
    EXCHANGE,Current,2026-11-07 12:00:00,2026-11-07 12:00:00,"Café, bar",-3.10,0.20,EUR,COMPLETED,972.25
    """

    func testRevolutCSV() throws {
        let r = try Importers.revolutCSV(revolut, accountID: "revolut", source: "test.csv")
        XCTAssertEqual(r.transactions.count, 3)
        XCTAssertEqual(r.skipped.count, 2)
        XCTAssertEqual(r.transactions[0].date, LocalDate(year: 2026, month: 11, day: 4))
        XCTAssertEqual(r.transactions[0].amount.cents, -2345)
        XCTAssertEqual(r.transactions[2].description, "Café, bar")
        XCTAssertEqual(r.transactions[2].amount.cents, -330)  // 手续费算进去
    }

    func testImportDedupAndUndo() throws {
        var l = Ledger.starter
        l.accounts = [Account(id: "revolut", name: "Revolut", kind: .wallet)]
        let r = try Importers.revolutCSV(revolut, accountID: "revolut", source: "a.csv")
        let first = try l.importTransactions(r.transactions, accountID: "revolut", source: "a.csv", author: "测试")
        XCTAssertEqual(first.added.count, 3)
        XCTAssertEqual(l.lastStatementDate["revolut"], LocalDate(year: 2026, month: 11, day: 7))
        let again = try l.importTransactions(r.transactions, accountID: "revolut", source: "a.csv", author: "测试")
        XCTAssertEqual(again.added.count, 0)
        XCTAssertEqual(again.duplicates, 3)
        XCTAssertNil(again.change)
        try l.undo(changeID: first.change!.id, author: "测试")
        XCTAssertTrue(l.transactions.isEmpty)
    }

    func testGenericCSVSpanishBank() throws {
        // 编造的西班牙银行格式：分号分隔、日在前、千分位用点、收支分两列，前面有两行说明。
        let text = """
        Cuenta;ES00 0000
        Periodo;noviembre
        Fecha;Concepto;Cargo;Abono;Saldo
        03/11/2026;RECIBO LUZ;45,20;;1.954,80
        05/11/2026;TRANSFERENCIA NOMINA;;2.900,00;4.854,80
        Total;;45,20;2.900,00;
        """
        let r = try Importers.genericCSV(text, map: .init(date: "Fecha", debit: "Cargo", credit: "Abono", description: "Concepto", skipRows: 2),
                                         accountID: "caixa", source: "x.csv")
        XCTAssertEqual(r.transactions.map(\.amount.cents), [-4520, 290000])
        XCTAssertEqual(r.transactions[0].date, LocalDate(year: 2026, month: 11, day: 3))
        XCTAssertEqual(r.skipped.count, 1)  // 合计行
    }

    func testGenericCSVWithCategoryBookFlow() throws {
        // 编造的「从别的记账表搬过来」格式：带分类、账本、性质三列。
        let text = """
        日期,金额,说明,分类,账本,性质
        2026-11-01,"-12,50",超市,超市日用,personal,
        2026-11-02,"80,00",刷卡结算,营业收入,miora,
        2026-11-03,-50,还朋友,借款往来,,debt
        2026-11-04,-20,转去 Revolut,内部转账,,互转
        """
        let r = try Importers.genericCSV(text, map: .init(date: "日期", amount: "金额", description: "说明",
                                                          category: "分类", book: "账本", flow: "性质"),
                                         accountID: "caixa", source: "x.csv")
        XCTAssertEqual(r.transactions.map(\.amount.cents), [-1250, 8000, -5000, -2000])
        XCTAssertEqual(r.transactions.map(\.category), ["超市日用", "营业收入", "借款往来", "内部转账"])
        XCTAssertEqual(r.transactions.map(\.bookID), ["personal", "miora", nil, nil])
        XCTAssertEqual(r.transactions.map(\.flow), [nil, nil, .debt, .internal])
        // 互转不算收支：这个月只有 80 收入、12,50 支出。
        let s = Summaries.monthly(r.transactions, month: YearMonth(year: 2026, month: 11), bookID: nil)
        XCTAssertEqual(s.income.cents, 8000)
        XCTAssertEqual(s.expense.cents, -1250)
        let bad = "日期,金额,说明,性质\n2026-11-01,-1,x,什么\n"
        XCTAssertThrowsError(try Importers.genericCSV(bad, map: .init(date: "日期", amount: "金额", description: "说明", flow: "性质"),
                                                      accountID: "caixa", source: "x.csv"))
    }

    func testCSVQuotes() {
        let rows = CSV.parse("a,b\n\"x, y\",\"he said \"\"hi\"\"\"\n")
        XCTAssertEqual(rows, [["a", "b"], ["x, y", "he said \"hi\""]])
    }
}

final class EditTests: XCTestCase {
    func ledger() -> (Ledger, Transaction, Transaction) {
        var l = Ledger.starter
        l.accounts = [Account(id: "caixa", name: "Caixa", kind: .bank), Account(id: "imagin", name: "imagin", kind: .bank)]
        let d = LocalDate(year: 2026, month: 11, day: 10)
        let out = Transaction(date: d, amount: Money(cents: -50000), description: "转账给自己", accountID: "caixa", bookID: "miora")
        let inn = Transaction(date: d, amount: Money(cents: 50000), description: "来自店里", accountID: "imagin", bookID: "personal")
        l.transactions = [out, inn]
        return (l, out, inn)
    }

    func testCategorizeAssignAndUndoRestores() throws {
        var (l, out, _) = ledger()
        let c1 = l.categorize([out.id], category: "老板提款", author: "测试")
        XCTAssertEqual(l.transactions[0].category, "老板提款")
        let c2 = try l.assignBook([out.id], bookID: "personal", author: "测试")
        XCTAssertEqual(l.transactions[0].bookID, "personal")
        try l.undo(changeID: c2.id, author: "测试")
        XCTAssertEqual(l.transactions[0].bookID, "miora")
        XCTAssertEqual(l.transactions[0].category, "老板提款")
        try l.undo(changeID: c1.id, author: "测试")
        XCTAssertNil(l.transactions[0].category)
        XCTAssertEqual(l.transactions.count, 2)  // 撤销改动不会删流水
        XCTAssertThrowsError(try l.assignBook([out.id], bookID: "nope", author: "测试"))
    }

    func testLinkTransferCancelsInAll() throws {
        var (l, out, inn) = ledger()
        try l.linkTransfer(out: out.id, into: inn.id, author: "测试")
        let m = YearMonth(year: 2026, month: 11)
        XCTAssertEqual(Summaries.monthly(l.transactions, month: m, bookID: nil).expense.cents, 0)
        XCTAssertEqual(Summaries.monthly(l.transactions, month: m, bookID: "miora").expense.cents, -50000)
        XCTAssertThrowsError(try l.linkTransfer(out: inn.id, into: out.id, author: "测试"))
    }

    func testAddTransferSameAccount() throws {
        var (l, _, _) = ledger()
        try l.addTransfer(amount: Money(cents: 2000), fromBook: "miora", toBook: "personal", accountID: "caixa",
                          date: LocalDate(year: 2026, month: 11, day: 12), author: "测试")
        XCTAssertEqual(Summaries.balances(l.transactions)["caixa"]?.cents, -50000)  // 同账户两笔抵消
        XCTAssertEqual(l.transactions.filter(\.isTransfer).count, 2)
    }

    func testFindByPrefix() throws {
        let (l, out, _) = ledger()
        XCTAssertEqual(try l.findTransactions([String(out.id.uuidString.prefix(8)).lowercased()]).first?.id, out.id)
        XCTAssertThrowsError(try l.findTransactions(["zzzzzzzz"]))
    }
}

final class InstallmentRuleTests: XCTestCase {
    func testPurchaseCountsFullThenPaymentsDont() throws {
        var l = Ledger.starter
        l.accounts = [Account(id: "caixa", name: "Caixa", kind: .bank)]
        let buyDay = LocalDate(year: 2026, month: 9, day: 1)
        let (inst, add) = try l.addInstallment(name: "美甲灯", bookID: "miora", accountID: "caixa", total: Money(cents: 60000), count: 6,
                                               purchaseDate: buyDay, firstPayment: LocalDate(year: 2026, month: 10, day: 5),
                                               category: "设备", fee: Money(cents: 1500), author: "测试")
        // 买的那个月：全额 600 + 手续费 15 算支出；账户只少了手续费
        XCTAssertEqual(Summaries.monthly(l.transactions, month: buyDay.yearMonth, bookID: "miora").expense.cents, -61500)
        XCTAssertEqual(Summaries.balances(l.transactions)["caixa"]?.cents, -1500)
        // 第一期还款：不算支出
        let pay = try l.payInstallment(inst.id, date: LocalDate(year: 2026, month: 10, day: 5), author: "测试")
        XCTAssertEqual(Summaries.monthly(l.transactions, month: YearMonth(year: 2026, month: 10), bookID: "miora").expense.cents, 0)
        XCTAssertEqual(Plans.installments(l).first?.paidCount, 1)
        XCTAssertEqual(Plans.installments(l).first?.remaining.cents, 50000)
        // 导入的扣款认领成第二期
        let bank = Transaction(date: LocalDate(year: 2026, month: 11, day: 5), amount: Money(cents: -10000), description: "CUOTA FINANC", accountID: "caixa")
        try l.addTransaction(bank, author: "测试")
        let link = try l.linkInstallmentPayment(inst.id, transactionID: bank.id, author: "测试")
        XCTAssertEqual(Summaries.monthly(l.transactions, month: YearMonth(year: 2026, month: 11), bookID: "miora").expense.cents, 0)
        XCTAssertEqual(Plans.installments(l).first?.paidCount, 2)
        // 撤销认领：那笔回到普通支出，分期回到第 1 期
        try l.undo(changeID: link.id, author: "测试")
        XCTAssertNil(l.transactions.first { $0.id == bank.id }?.flow)
        XCTAssertEqual(Plans.installments(l).first?.paidCount, 1)
        // 有还款时不能先撤销分期本身
        XCTAssertThrowsError(try l.undo(changeID: add.id, author: "测试"))
        try l.undo(changeID: pay.id, author: "测试")
        try l.undo(changeID: add.id, author: "测试")
        XCTAssertTrue(l.installments.isEmpty)
        XCTAssertEqual(l.transactions.count, 1)  // 只剩那笔银行扣款
    }
}

#if canImport(SQLite3)
final class SQLiteStoreTests: XCTestCase {
    func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    func testRoundTripEverything() throws {
        let url = tempURL("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SQLiteLedgerStore(url: url)
        XCTAssertEqual(try store.load(), .fresh)
        var l = Ledger.starter
        l.accounts = [Account(id: "cash", name: "现金", kind: .cash), Account(id: "stash", name: "私房钱", kind: .cash, isPrivate: true)]
        let t = Transaction(date: LocalDate(year: 2026, month: 11, day: 1), amount: Money(cents: -1234), description: "咖啡 \"拿铁\"",
                            accountID: "cash", bookID: "personal", category: "餐饮")
        l.transactions = [t, Transaction(date: LocalDate(year: 2026, month: 11, day: 2), amount: Money(cents: 500), description: "x", accountID: "stash")]
        l.changes = [ChangeRecord(kind: .add, summary: "记一笔", transactionIDs: [t.id], author: "测试", createdAt: Date(timeIntervalSince1970: 1_800_000_000))]
        l.debts = [Debt(counterparty: "阿华", direction: .theyOweMe, principal: Money(cents: 100), bookID: "personal", startDate: t.date)]
        l.goals = [Goal(name: "宝宝", bookID: "personal", target: Money(cents: 100000), locked: true)]
        l.lastStatementDate = ["cash": t.date]
        try store.save(l)
        XCTAssertEqual(try store.load(), l)
        // 再存一次（整体替换）也一样
        l.transactions.removeLast()
        try store.save(l)
        XCTAssertEqual(try store.load(), l)
    }

    func testMigratesFromLegacyJSON() throws {
        let json = tempURL("json"), db = tempURL("sqlite")
        defer { try? FileManager.default.removeItem(at: json); try? FileManager.default.removeItem(at: db) }
        var l = Ledger.starter
        l.accounts = [Account(id: "cash", name: "现金", kind: .cash)]
        try JSONFileLedgerStore(url: json).save(l)
        let store = MigratingStore(primary: SQLiteLedgerStore(url: db), legacy: JSONFileLedgerStore(url: json))
        XCTAssertEqual(try store.load().accounts.count, 1)   // 先读旧 JSON
        try store.save(try store.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.path))
        XCTAssertEqual(try SQLiteLedgerStore(url: db).load().accounts.count, 1)
    }
}
#endif

final class GoalEditTests: XCTestCase {
    func base() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "caixa", name: "Caixa", kind: .bank), Account(id: "pot", name: "储蓄罐", kind: .savings)]
        l.transactions = [Transaction(date: LocalDate(year: 2026, month: 11, day: 1), amount: Money(cents: 300000), description: "工资",
                                      accountID: "caixa", bookID: "personal", category: "收入")]
        return l
    }

    func testEarmarkInExistingAccount() throws {
        var l = base()
        let d = LocalDate(year: 2026, month: 11, day: 5)
        let (g, add) = try l.addGoal(name: "店铺装修", bookID: "personal", target: Money(cents: 400000), author: "测试")
        let dep = try l.deposit(goalID: g.id, amount: Money(cents: 50000), fromAccount: "caixa", date: d, author: "测试")
        XCTAssertEqual(Plans.goals(l).first?.saved.cents, 50000)
        XCTAssertEqual(Summaries.balances(l.transactions)["caixa"]?.cents, 300000)   // 划出不改余额
        XCTAssertEqual(Summaries.monthly(l.transactions, month: d.yearMonth, bookID: "personal").expense.cents, 0)
        try l.withdraw(goalID: g.id, amount: Money(cents: 20000), toAccount: "caixa", date: d, author: "测试")
        XCTAssertEqual(Plans.goals(l).first?.saved.cents, 30000)
        XCTAssertThrowsError(try l.undo(changeID: add.id, author: "测试"))   // 还有存取记录
        _ = dep
    }

    func testSavingsAccountAndLocked() throws {
        var l = base()
        let d = LocalDate(year: 2026, month: 11, day: 5)
        let (g, _) = try l.addGoal(name: "宝宝", bookID: "personal", target: Money(cents: 100000), savingsAccountID: "pot", locked: true, author: "测试")
        let dep = try l.deposit(goalID: g.id, amount: Money(cents: 8000), fromAccount: "caixa", date: d, author: "测试")
        XCTAssertEqual(Summaries.balances(l.transactions)["pot"]?.cents, 8000)
        XCTAssertEqual(Summaries.balances(l.transactions)["caixa"]?.cents, 292000)
        XCTAssertEqual(Plans.goals(l).first?.saved.cents, 8000)
        XCTAssertEqual(Plans.goals(l).first?.locked, true)
        XCTAssertThrowsError(try l.withdraw(goalID: g.id, amount: Money(cents: 100), toAccount: "caixa", date: d, author: "测试"))
        try l.undo(changeID: dep.id, author: "测试")
        XCTAssertEqual(Summaries.balances(l.transactions)["pot"] ?? .zero, .zero)
        XCTAssertTrue(l.goals[0].contributionIDs.isEmpty)
    }
}

final class FixMistakesTests: XCTestCase {
    func base() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "cash", name: "现金", kind: .cash)]
        l.transactions = [Transaction(date: LocalDate(year: 2026, month: 11, day: 3), amount: Money(cents: -1250), description: "超市",
                                      accountID: "cash", bookID: "personal", category: "吃饭")]
        return l
    }

    func testEditThenUndo() throws {
        var l = base()
        var t = l.transactions[0]
        t.amount = Money(cents: -2500); t.category = "日用"
        let c = try l.editTransaction(t, author: "测试")
        XCTAssertEqual(l.transactions[0].amount.cents, -2500)
        try l.undo(changeID: c.id, author: "测试")
        XCTAssertEqual(l.transactions[0].amount.cents, -1250)
        XCTAssertEqual(l.transactions[0].category, "吃饭")
    }

    func testRemoveThenUndo() throws {
        var l = base()
        let id = l.transactions[0].id
        let c = try l.removeTransactions([id], author: "测试")
        XCTAssertTrue(l.transactions.isEmpty)
        try l.undo(changeID: c.id, author: "测试")
        XCTAssertEqual(l.transactions.map(\.id), [id])
    }

    func testOpeningBalanceIsNotIncomeAndCanBeChanged() throws {
        var l = base()
        let d = LocalDate(year: 2026, month: 11, day: 1)
        try l.setOpeningBalance(accountID: "cash", amount: Money(cents: 10000), date: d, author: "测试")
        try l.setOpeningBalance(accountID: "cash", amount: Money(cents: 20000), date: d, author: "测试")
        XCTAssertEqual(l.transactions.filter { $0.flow == .opening }.count, 1)
        XCTAssertEqual(Summaries.balances(l.transactions)["cash"]?.cents, 18750)
        XCTAssertEqual(Summaries.monthly(l.transactions, month: d.yearMonth, bookID: nil).income.cents, 0)
    }
}

final class ManageTests: XCTestCase {
    let day = LocalDate(year: 2026, month: 11, day: 3)

    func testRefundReducesExpenseNotIncome() {
        let txs = [
            Transaction(date: day, amount: Money(cents: 200_000), description: "工资", accountID: "bank", bookID: "personal", category: "工资"),
            Transaction(date: day, amount: Money(cents: -10_000), description: "ZARA", accountID: "bank", bookID: "personal", category: "购物"),
            Transaction(date: day, amount: Money(cents: 4_000), description: "ZARA 退货", accountID: "bank", bookID: "personal", category: "购物"),
        ]
        let m = YearMonth(year: 2026, month: 11)
        let s = Summaries.monthly(txs, month: m, bookID: "personal")
        XCTAssertEqual(s.income, Money(cents: 200_000))
        XCTAssertEqual(s.expense, Money(cents: -6_000))
        let r = Reports.summaries(txs, months: [m], bookID: "personal")[0]
        XCTAssertEqual(r.income, s.income)
        XCTAssertEqual(r.expense, s.expense)
        XCTAssertEqual(Reports.categoryTotals([r], expense: true).first { $0.name == "购物" }?.amount, Money(cents: 6_000))
        // 某个月只有退款：照样冲减支出（按整本账判断分类性质）
        let dec = Transaction(date: LocalDate(year: 2026, month: 12, day: 2), amount: Money(cents: 1_500), description: "退货", accountID: "bank", bookID: "personal", category: "购物")
        let d = Summaries.monthly(txs + [dec], month: YearMonth(year: 2026, month: 12), bookID: "personal")
        XCTAssertEqual(d.income, .zero)
        XCTAssertEqual(d.expense, Money(cents: 1_500))
    }

    func testFlowDecodingIsLenient() throws {
        func tx(_ flow: String) throws -> Transaction {
            let json = #"{"id":"11111111-1111-1111-1111-111111111111","date":"2026-11-03","amount":{"cents":-500},"description":"x","accountID":"bank","flow":"\#(flow)"}"#
            return try JSONDecoder().decode(Transaction.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try tx("internal").flow, .internal)
        XCTAssertEqual(try tx("move").flow, .internal)      // 旧写法
        XCTAssertNil(try tx("something-new").flow)          // 不认识的值不让整本账打不开
    }

    func ledger() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "银行", kind: .bank), Account(id: "cash", name: "现金", kind: .cash)]
        return l
    }

    func testAccountTransferMovesMoneyButIsNotIncomeOrExpense() throws {
        var l = ledger()
        let change = try l.addAccountTransfer(amount: Money(cents: 20000), from: "bank", to: "cash", date: day, author: "t")
        let b = Summaries.balances(l.transactions)
        XCTAssertEqual(b["bank"]?.cents, -20000)
        XCTAssertEqual(b["cash"]?.cents, 20000)
        let m = Summaries.monthly(l.transactions, month: day.yearMonth, bookID: nil)
        XCTAssertEqual(m.income.cents, 0)
        XCTAssertEqual(m.expense.cents, 0)
        XCTAssertEqual(l.pairedIDs(of: change.transactionIDs[0]).count, 2)
        try l.undo(changeID: change.id, author: "t")
        XCTAssertTrue(l.transactions.isEmpty)
        XCTAssertThrowsError(try l.addAccountTransfer(amount: Money(cents: 100), from: "bank", to: "bank", date: day, author: "t"))
    }

    func testMarkImportedAsTransferAddsOtherHalfAndUndoRemovesIt() throws {
        var l = ledger()
        let tx = Transaction(date: day, amount: Money(cents: -20000), description: "REINTEGRO CAJERO", accountID: "bank")
        try l.addTransaction(tx, author: "t")
        let change = try l.markAsAccountTransfer([tx.id], counterAccount: "cash", author: "t")
        XCTAssertEqual(l.transactions.count, 2)
        XCTAssertEqual(Summaries.monthly(l.transactions, month: day.yearMonth, bookID: nil).expense.cents, 0)
        XCTAssertEqual(Summaries.balances(l.transactions)["cash"]?.cents, 20000)
        try l.undo(changeID: change.id, author: "t")
        XCTAssertEqual(l.transactions.count, 1)
        XCTAssertNil(l.transactions[0].flow)
        XCTAssertEqual(Summaries.monthly(l.transactions, month: day.yearMonth, bookID: nil).expense.cents, -20000)
    }

    func testClassifyAndRenameCategory() throws {
        var l = ledger()
        let a = Transaction(date: day, amount: Money(cents: -1000), description: "A", accountID: "bank")
        let b = Transaction(date: day, amount: Money(cents: -2000), description: "B", accountID: "bank")
        try l.addTransaction(a, author: "t"); try l.addTransaction(b, author: "t")
        try l.classify([a.id, b.id], category: "吃饭", bookID: "personal", author: "t")
        XCTAssertTrue(l.transactions.allSatisfy { $0.category == "吃饭" && $0.bookID == "personal" })
        let change = try l.renameCategory("吃饭", to: "餐饮", author: "t")
        XCTAssertTrue(l.transactions.allSatisfy { $0.category == "餐饮" })
        try l.undo(changeID: change.id, author: "t")
        XCTAssertTrue(l.transactions.allSatisfy { $0.category == "吃饭" })
    }

    func testAccountLifecycle() throws {
        var l = ledger()
        let created = try l.createAccount(Account(id: "rev", name: "Revolut", kind: .wallet), openingBalance: Money(cents: 5000), author: "t")
        XCTAssertEqual(Summaries.balances(l.transactions)["rev"]?.cents, 5000)
        var renamed = l.accounts.first { $0.id == "rev" }!
        renamed.name = "Revolut 个人"; renamed.isPrivate = true
        let change = try l.updateAccount(renamed, author: "t")
        XCTAssertEqual(l.accounts.first { $0.id == "rev" }?.name, "Revolut 个人")
        try l.undo(changeID: change.id, author: "t")
        XCTAssertEqual(l.accounts.first { $0.id == "rev" }?.name, "Revolut")
        // 有流水的账户不能删
        try l.addTransaction(Transaction(date: day, amount: Money(cents: -100), description: "x", accountID: "bank"), author: "t")
        XCTAssertThrowsError(try l.removeAccount("bank", author: "t"))
        // 只有期初余额的可以删，撤销能放回来
        let removed = try l.removeAccount("rev", author: "t")
        XCTAssertNil(l.accounts.first { $0.id == "rev" })
        XCTAssertNil(Summaries.balances(l.transactions)["rev"])
        try l.undo(changeID: removed.id, author: "t")
        XCTAssertEqual(Summaries.balances(l.transactions)["rev"]?.cents, 5000)
        // 撤销「加账户」：账户和期初余额一起没
        try l.removeAccount("rev", author: "t")
        _ = created
    }

    func testUndoCreateAccountRemovesIt() throws {
        var l = ledger()
        let created = try l.createAccount(Account(id: "rev", name: "Revolut", kind: .wallet), openingBalance: Money(cents: 5000), author: "t")
        try l.undo(changeID: created.id, author: "t")
        XCTAssertNil(l.accounts.first { $0.id == "rev" })
        XCTAssertTrue(l.transactions.isEmpty)
    }

    func testRemoveDebtTakesItsTransactionsAndUndoRestores() throws {
        var l = ledger()
        let (debt, _) = try l.addDebt(counterparty: "阿华", direction: .theyOweMe, amount: Money(cents: 50000), bookID: "personal",
                                      date: day, accountID: "bank", author: "t")
        try l.repay(debtID: debt.id, amount: Money(cents: 20000), date: day, accountID: "bank", author: "t")
        XCTAssertEqual(l.debtTransactionIDs(debt.id).count, 2)
        let change = try l.removeDebt(debt.id, author: "t")
        XCTAssertTrue(l.debts.isEmpty)
        XCTAssertTrue(l.transactions.isEmpty)
        try l.undo(changeID: change.id, author: "t")
        XCTAssertEqual(l.transactions.count, 2)
        XCTAssertEqual(Plans.debts(l, today: day).first?.outstanding.cents, 30000)
    }

    func testCloseDebtAndReopen() throws {
        var l = ledger()
        var (debt, _) = try l.addDebt(counterparty: "阿华", direction: .theyOweMe, amount: Money(cents: 50000), bookID: "personal",
                                      date: day, accountID: nil, author: "t")
        debt.closed = true
        let change = try l.updateDebt(debt, author: "t")
        XCTAssertTrue(Plans.debts(l, today: day).isEmpty)
        try l.undo(changeID: change.id, author: "t")
        XCTAssertEqual(Plans.debts(l, today: day).count, 1)
    }

    func testRemoveInstallmentAndGoal() throws {
        var l = ledger()
        let (inst, _) = try l.addInstallment(name: "灯", bookID: "miora", accountID: "bank", total: Money(cents: 60000), count: 6,
                                             purchaseDate: day, firstPayment: day, author: "t")
        try l.payInstallment(inst.id, date: day, author: "t")
        XCTAssertEqual(l.transactions.count, 3)
        let c1 = try l.removeInstallment(inst.id, author: "t")
        XCTAssertTrue(l.transactions.isEmpty)
        try l.undo(changeID: c1.id, author: "t")
        XCTAssertEqual(Plans.installments(l).first?.paidCount, 1)

        let (goal, _) = try l.addGoal(name: "机票", bookID: "personal", target: Money(cents: 100000), author: "t")
        try l.deposit(goalID: goal.id, amount: Money(cents: 30000), fromAccount: "bank", date: day, author: "t")
        let c2 = try l.removeGoal(goal.id, author: "t")
        XCTAssertTrue(l.goals.isEmpty)
        XCTAssertEqual(l.transactions.count, 3)
        try l.undo(changeID: c2.id, author: "t")
        XCTAssertEqual(Plans.goals(l).first?.saved.cents, 30000)
    }
}

final class SuggestTests: XCTestCase {
    let day = LocalDate(year: 2026, month: 11, day: 3)

    func testGuessesFromHistoryIncludingDifferentStoreNumbers() {
        let history = [
            Transaction(date: day, amount: Money(cents: -1000), description: "MERCADONA 1234 VALENCIA", accountID: "a", bookID: "personal", category: "超市"),
            Transaction(date: day, amount: Money(cents: -1000), description: "MERCADONA 1234 VALENCIA", accountID: "a", bookID: "personal", category: "超市"),
            Transaction(date: day, amount: Money(cents: -900), description: "Proveedor Unas SL", accountID: "a", bookID: "miora", category: "耗材"),
        ]
        let s = Suggester(history)
        XCTAssertEqual(s.guess("Mercadona 1234 Valencia").category, "超市")
        XCTAssertEqual(s.guess("MERCADONA 0098 VALENCIA").bookID, "personal")
        XCTAssertEqual(s.guess("proveedor unas sl").category, "耗材")
        XCTAssertTrue(s.guess("从没见过的店").isEmpty)
    }

    func testApplyingGuessesOnlyFillsBlanks() {
        var l = Ledger.starter
        l.transactions = [Transaction(date: day, amount: Money(cents: -1000), description: "Glovo", accountID: "a", bookID: "personal", category: "餐饮")]
        let incoming = [
            Transaction(date: day, amount: Money(cents: -500), description: "GLOVO", accountID: "a"),
            Transaction(date: day, amount: Money(cents: -500), description: "Nuevo", accountID: "a"),
        ]
        let r = l.applyingGuesses(to: incoming)
        XCTAssertEqual(r.guessed, 1)
        XCTAssertEqual(r.transactions[0].category, "餐饮")
        XCTAssertEqual(r.transactions[0].bookID, "personal")
        XCTAssertNil(r.transactions[1].category)
    }
}

final class ReportTests: XCTestCase {
    func testMonthMath() {
        XCTAssertEqual(YearMonth(year: 2026, month: 1).adding(months: -1), YearMonth(year: 2025, month: 12))
        XCTAssertEqual(YearMonth(year: 2026, month: 12).adding(months: 1), YearMonth(year: 2027, month: 1))
        XCTAssertEqual(Reports.months(endingAt: YearMonth(year: 2026, month: 2), count: 3).map(\.description), ["2025-12", "2026-01", "2026-02"])
    }

    func testSummariesMatchMonthly() {
        let d = LocalDate(year: 2026, month: 10, day: 3)
        let t = UUID()
        let txs = [
            Transaction(date: d, amount: Money(cents: 50000), description: "S", accountID: "bank", bookID: "miora", category: "收入"),
            Transaction(date: d, amount: Money(cents: -20000), description: "R", accountID: "bank", bookID: "miora", category: "老板提款", transferID: t),
            Transaction(date: d, amount: Money(cents: 20000), description: "R", accountID: "bank", bookID: "personal", category: "收入", transferID: t),
            Transaction(date: d, amount: Money(cents: -1500), description: "M", accountID: "cash", bookID: "personal", category: "餐饮"),
            Transaction(date: d, amount: Money(cents: -9900), description: "ATM", accountID: "bank", flow: .internal),
        ]
        let m = YearMonth(year: 2026, month: 10)
        for book in [nil, "miora", "personal"] as [String?] {
            XCTAssertEqual(Reports.summaries(txs, months: [m], bookID: book)[0], Summaries.monthly(txs, month: m, bookID: book))
        }
        let cats = Reports.categoryTotals(Reports.summaries(txs, months: [m], bookID: nil), expense: true)
        XCTAssertEqual(cats.map(\.name), ["餐饮"])
    }

    func testCSVExportQuotesText() {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "银行", kind: .bank)]
        let tx = Transaction(date: LocalDate(year: 2026, month: 1, day: 2), amount: Money(cents: -1250), description: "说 \"你好\", 再见", accountID: "bank", bookID: "personal", category: "餐饮")
        let csv = Reports.csv([tx], ledger: l)
        XCTAssertTrue(csv.contains("2026-01-02,-12.50,\"说 \"\"你好\"\", 再见\",\"餐饮\",\"银行\",\"个人\",支出"))
    }
}

final class ImportGuessTests: XCTestCase {
    func testDetectsRevolut() {
        let text = "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance\nCARD_PAYMENT,Current,2026-11-01 10:00:00,2026-11-02 10:00:00,Cafe,-3.50,0.00,EUR,COMPLETED,100.00\n"
        XCTAssertEqual(ImportGuess.detect(text).format, .revolut)
    }

    func testDetectsSpanishBankHeaderAfterTitleRows() throws {
        let text = "Movimientos de la cuenta;;;\nFecha;Concepto;Importe;Saldo\n03/11/2026;MERCADONA;-12,50;100,00\n"
        let d = ImportGuess.detect(text)
        XCTAssertEqual(d.format, .generic)
        XCTAssertEqual(d.skipRows, 1)
        XCTAssertEqual(d.date, "Fecha")
        XCTAssertEqual(d.description, "Concepto")
        XCTAssertEqual(d.amount, "Importe")
        XCTAssertTrue(d.isComplete)
        let r = try Importers.genericCSV(text, map: .init(date: d.date!, amount: d.amount, description: d.description!, skipRows: d.skipRows),
                                         accountID: "bank", source: "t")
        XCTAssertEqual(r.transactions.first?.amount.cents, -1250)
    }

    func testGuessesAccountFromFileName() {
        let accounts = [Account(id: "caixa", name: "CaixaBank", kind: .bank), Account(id: "revolut", name: "Revolut", kind: .wallet)]
        XCTAssertEqual(ImportGuess.account(fileName: "revolut-2026-11.csv", text: "", accounts: accounts), "revolut")
        XCTAssertNil(ImportGuess.account(fileName: "movimientos.csv", text: "", accounts: accounts))
    }
}

final class ReconcileTests: XCTestCase {
    let day = LocalDate(year: 2026, month: 11, day: 20)

    func ledger() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "银行", kind: .bank)]
        l.transactions = [
            Transaction(date: LocalDate(year: 2026, month: 11, day: 1), amount: Money(cents: 100_000), description: "期初余额", accountID: "bank", flow: .opening),
            Transaction(date: LocalDate(year: 2026, month: 11, day: 5), amount: Money(cents: -2_500), description: "MERCADONA", accountID: "bank", bookID: "personal", category: "超市"),
            Transaction(date: LocalDate(year: 2026, month: 11, day: 5), amount: Money(cents: -2_500), description: "Mercadona", accountID: "bank", bookID: "personal", category: "超市"),
            Transaction(date: LocalDate(year: 2026, month: 11, day: 25), amount: Money(cents: -9_900), description: "之后的一笔", accountID: "bank", bookID: "personal", category: "购物"),
        ]
        return l
    }

    func testMatches() throws {
        let r = try Reconcile.check(ledger(), accountID: "bank", statementBalance: Money(cents: 95_000), asOf: day)
        XCTAssertTrue(r.matches)
        XCTAssertEqual(r.count, 3)          // 25 号那笔在对账日之后，不算
        XCTAssertTrue(r.suspects.isEmpty)
    }

    func testFindsDuplicate() throws {
        // 银行其实只扣了一次 25 €
        let r = try Reconcile.check(ledger(), accountID: "bank", statementBalance: Money(cents: 97_500), asOf: day)
        XCTAssertEqual(r.difference, Money(cents: 2_500))
        XCTAssertFalse(r.suspects.isEmpty)
        XCTAssertTrue(r.suspects.allSatisfy { $0.amount == Money(cents: -2_500) })
        XCTAssertTrue(Reconcile.text(r).contains("重复"))
    }

    func testUnknownAccount() {
        XCTAssertThrowsError(try Reconcile.check(ledger(), accountID: "nope", statementBalance: .zero, asOf: day))
    }

    func testMonthlyReportReads() {
        var l = ledger()
        l.transactions.append(Transaction(date: LocalDate(year: 2026, month: 11, day: 2), amount: Money(cents: 200_000), description: "工资", accountID: "bank", bookID: "personal", category: "工资"))
        l.transactions.append(Transaction(date: LocalDate(year: 2026, month: 11, day: 8), amount: Money(cents: -1_200), description: "没整理的", accountID: "bank"))
        let text = MonthlyReport.text(l, month: YearMonth(year: 2026, month: 11), bookID: nil, today: day)
        XCTAssertTrue(text.contains("进账 2.000,00 €"))
        XCTAssertTrue(text.contains("超市"))
        XCTAssertTrue(text.contains("1 笔流水还没分类"))
        XCTAssertFalse(text.contains("期初余额"))
    }
}

final class MerchantTests: XCTestCase {
    func testCleansBankText() {
        XCTAssertEqual(Merchant.display("UBR* PENDING.UBER"), "Uber")
        XCTAssertEqual(Merchant.display("Top-up Apple Pay top-up by *9362"), "Apple Pay 充值")
        XCTAssertEqual(Merchant.display("Top-up by *1234"), "充值")
        XCTAssertEqual(Merchant.display("COMPRA TARJ. PANADERIA LOPEZ MADRID 48213377"), "Panaderia Lopez Madrid")
        XCTAssertEqual(Merchant.display("MERCADONA AVDA ESPAÑA"), "Mercadona")
        XCTAssertEqual(Merchant.display("PAYPAL *STEAMGAMES 4029357733"), "Steamgames")
    }

    func testLeavesGoodTextAlone() {
        XCTAssertEqual(Merchant.display("水电"), "水电")
        XCTAssertEqual(Merchant.display("Wenzhou Supermercados"), "Wenzhou Supermercados")
        XCTAssertEqual(Merchant.display("Consorcio Regional de Transportes de Madrid"), "Consorcio Regional de Transportes de Madrid")
        XCTAssertEqual(Merchant.display("STAR OTO#O"), "Star Oto#o")
        XCTAssertEqual(Merchant.display(""), "")
        XCTAssertEqual(Merchant.display("FERRETERIA HUBER SL"), "Ferreteria Huber SL")
        XCTAssertEqual(Merchant.display("Revolut**5670"), "Revolut")
    }
}

final class DebtRulesTests: XCTestCase {
    let day = LocalDate(year: 2026, month: 11, day: 3)

    func testExactNameWinsAndOverRepayIsRefused() throws {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "银行", kind: .bank)]
        _ = try l.addDebt(counterparty: "阿华", direction: .theyOweMe, amount: Money(cents: 10_000), bookID: "personal",
                          date: day, accountID: "bank", dueDate: nil, note: nil, author: "test")
        _ = try l.addDebt(counterparty: "阿华2", direction: .theyOweMe, amount: Money(cents: 5_000), bookID: "personal",
                          date: day, accountID: "bank", dueDate: nil, note: nil, author: "test")
        let hits = l.openDebts(named: "阿华")
        XCTAssertEqual(hits.map(\.counterparty), ["阿华"])
        XCTAssertEqual(l.openDebts(named: "阿").count, 2)
        XCTAssertThrowsError(try l.repay(debtID: hits[0].id, amount: Money(cents: 10_001), date: day, accountID: "bank", author: "test"))
        XCTAssertNoThrow(try l.repay(debtID: hits[0].id, amount: Money(cents: 10_000), date: day, accountID: "bank", author: "test"))
    }
}

final class BetweenBooksTests: XCTestCase {
    let m = YearMonth(year: 2026, month: 5)
    func tx(_ day: Int, _ cents: Int64, _ account: String, _ book: String, flow: Transaction.Flow? = .internal, month: Int = 5) -> Transaction {
        Transaction(date: LocalDate(year: 2026, month: month, day: day), amount: Money(cents: cents), description: "t",
                    accountID: account, bookID: book, category: flow == nil ? "超市" : nil, flow: flow)
    }

    func testMoneyTakenHomeFromTheShop() {
        let txs = [
            tx(2, -40_000, "shopbank", "shop"), tx(3, 40_000, "mybank", "personal"),    // 店里拿 400 回家
            tx(9, 10_000, "shopbank", "shop"), tx(8, -10_000, "mybank", "personal"),    // 垫 100 回店里
            tx(10, -5_000, "mybank", "personal"), tx(10, 5_000, "card", "personal"),    // 个人账户之间挪，不算
            tx(12, -3_000, "mybank", "personal", flow: nil),                             // 普通开销
        ]
        let personal = Summaries.monthly(txs, month: m, bookID: "personal")
        XCTAssertEqual(personal.betweenBooks, Money(cents: 30_000))
        XCTAssertEqual(personal.expense, Money(cents: -3_000))
        XCTAssertEqual(personal.income, .zero)
        XCTAssertEqual(personal.netWithBetweenBooks, Money(cents: 27_000))
        XCTAssertEqual(Summaries.monthly(txs, month: m, bookID: "shop").betweenBooks, Money(cents: -30_000))
        XCTAssertEqual(Summaries.monthly(txs, month: m, bookID: nil).betweenBooks, .zero)
        XCTAssertEqual(Reports.summaries(txs, months: [m], bookID: "shop")[0].betweenBooks, Money(cents: -30_000))
        XCTAssertEqual(Summaries.unmatchedInternal(txs, months: [m]).count, 0)
    }

    func testOneSidedTransferIsFlaggedNotCounted() {
        let txs = [
            tx(2, -40_000, "shopbank", "shop"), tx(3, 40_000, "mybank", "personal"),
            tx(20, -7_000, "mybank", "personal"),            // 还信用卡只记了扣款这一边
            tx(21, -20_900, "shopbank", "shop"),             // 店里账户替个人还卡，另一边没记
            tx(1, 40_000, "card", "personal", month: 6),     // 金额一样但隔了一个月，不能乱配
        ]
        XCTAssertEqual(Summaries.monthly(txs, month: m, bookID: "personal").betweenBooks, Money(cents: 40_000))
        XCTAssertEqual(Summaries.monthly(txs, month: m, bookID: "shop").betweenBooks, Money(cents: -40_000))
        XCTAssertEqual(Summaries.pairInternal(txs).unpaired.count, 3)
        // 店只有一个账户：从它转出去没配上的那笔只可能去了别的账本，要提醒。
        // 个人有两个账户：没配上的多半是自己账户之间的（还信用卡），不提醒。
        let flagged = Summaries.unmatchedInternal(txs, months: [m])
        XCTAssertEqual(flagged.count, 1)
        XCTAssertEqual(flagged.total, Money(cents: 20_900))
        // 店里的账户偶尔刷过个人开销，也还是算店的账户。
        let shared = txs + [tx(15, -1_200, "shopbank", "personal", flow: nil)]
        XCTAssertEqual(Summaries.unmatchedInternal(shared, months: [m]).count, 1)
        XCTAssertEqual(Summaries.unmatchedInternal(shared, months: [YearMonth(year: 2026, month: 6)]).count, 0)
    }

    func testPairsNearestDateAndNeverSameAccount() {
        let txs = [
            tx(5, -10_000, "shopbank", "shop"), tx(5, 10_000, "shopbank", "shop"),      // 同一个账户不配
            tx(9, 10_000, "mybank", "personal"), tx(6, 10_000, "card", "personal"),     // 6 号更近
        ]
        let p = Summaries.pairInternal(txs)
        XCTAssertEqual(p.crossBook.map(\.accountID).sorted(), ["card", "shopbank"])
        XCTAssertEqual(p.unpaired.count, 2)
    }

    func testLabelNamesTheOtherBook() {
        let books = [Book(id: "personal", name: "个人"), Book(id: "shop", name: "美甲店")]
        XCTAssertEqual(Reports.betweenBooksLabel(Money(cents: 100), bookID: "personal", books: books), "从美甲店拿的")
        XCTAssertEqual(Reports.betweenBooksLabel(Money(cents: -100), bookID: "shop", books: books), "拿去个人的")
        XCTAssertEqual(Reports.betweenBooksLabel(Money(cents: 100), bookID: "a", books: books + [Book(id: "a", name: "A")]), "从别的账本拿的")
    }
}

final class InsightTests: XCTestCase {
    let nov = YearMonth(year: 2026, month: 11)

    func testReviewReplacesAndUndoBringsBack() throws {
        var l = Ledger.starter
        let first = try l.addInsight(Insight(month: nov, kind: .monthlyReview, title: "第一版点评", body: "", author: "Claude"), author: "Claude")
        try l.addInsight(Insight(month: nov, kind: .alert, title: "超市多了", body: "多 74 €", author: "Claude"), author: "Claude")
        let second = try l.addInsight(Insight(month: nov, kind: .monthlyReview, title: "第二版点评", body: "", author: "Codex"), author: "Codex")
        XCTAssertEqual(l.insights(month: nov).map(\.title), ["第二版点评", "超市多了"])
        XCTAssertTrue(second.canUndo)
        try l.undo(changeID: second.id, author: "ming")
        XCTAssertEqual(l.insights(month: nov).map(\.title), ["第一版点评", "超市多了"])
        try l.undo(changeID: first.id, author: "ming")
        XCTAssertEqual(l.insights(month: nov).map(\.title), ["超市多了"])
    }

    func testDismissHidesAndUndoShowsAgain() throws {
        var l = Ledger.starter
        try l.addInsight(Insight(month: nov, kind: .tip, title: "两个视频会员", body: "", author: "Claude"), author: "Claude")
        let id = l.insights[0].id
        XCTAssertNotNil(l.findInsight(String(id.uuidString.prefix(8))))
        let change = try l.dismissInsight(id, author: "ming")
        XCTAssertTrue(l.insights(month: nov).isEmpty)
        XCTAssertEqual(l.insights(month: nov, includeDismissed: true).count, 1)
        try l.undo(changeID: change.id, author: "ming")
        XCTAssertEqual(l.insights(month: nov).count, 1)
    }

    func testEmptyTitleRejected() {
        var l = Ledger.starter
        XCTAssertThrowsError(try l.addInsight(Insight(month: nov, kind: .tip, title: "  ", body: "", author: "AI"), author: "AI"))
    }

    func testSQLiteRoundTripKeepsInsights() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("insights-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var l = Ledger.starter
        try l.addInsight(Insight(month: nov, bookID: "personal", kind: .goodNews, title: "存钱进度比计划快", body: "已经 62%", author: "Codex",
                                     createdAt: Date(timeIntervalSince1970: 1_800_000_000)), author: "Codex")
        let store = SQLiteLedgerStore(url: url)
        try store.save(l)
        let back = try store.load()
        XCTAssertEqual(back.insights, l.insights)
        XCTAssertEqual(back.insights.first?.kind, .goodNews)
    }

    func testUnknownKindReadsAsTip() throws {
        let json = #"{"id":"6F1D2C3B-0000-4000-8000-000000000001","month":{"year":2026,"month":11},"kind":"somethingNew","title":"新种类","author":"AI"}"#
        let i = try JSONDecoder().decode(Insight.self, from: Data(json.utf8))
        XCTAssertEqual(i.kind, .tip)
        XCTAssertEqual(i.body, "")
    }
}


final class BookManageTests: XCTestCase {
    func testAddRenameRemoveEmptyBook() throws {
        var l = Ledger.fresh
        XCTAssertEqual(l.books.map(\.name), ["个人"])
        try l.addBook(name: "家庭", author: "我")
        XCTAssertThrowsError(try l.addBook(name: "家庭", author: "我"))
        let id = try XCTUnwrap(l.books.first { $0.name == "家庭" }?.id)
        try l.renameBook(id, to: "一家人", author: "我")
        XCTAssertEqual(l.books.last?.name, "一家人")
        let change = try l.removeBook(id, author: "我")
        XCTAssertEqual(l.books.count, 1)
        try l.undo(changeID: change.id, author: "我")
        XCTAssertEqual(l.books.map(\.name).sorted(), ["一家人", "个人"].sorted())
    }

    func testLastBookCannotBeRemoved() {
        var l = Ledger.fresh
        XCTAssertThrowsError(try l.removeBook("personal", author: "我")) { XCTAssertEqual($0 as? ManageError, .lastBook) }
    }

    func testRemoveBookWithContentNeedsTargetAndUndoMovesBack() throws {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "银行卡", kind: .bank)]
        let d = LocalDate(year: 2026, month: 11, day: 3)
        let tx = Transaction(date: d, amount: Money(cents: -1200), description: "测试", accountID: "bank", bookID: "miora", category: "耗材")
        l.transactions = [tx]
        _ = try l.addGoal(name: "新设备", bookID: "miora", target: Money(cents: 50000), author: "我")
        XCTAssertEqual(l.bookUsage("miora").transactions, 1)
        XCTAssertThrowsError(try l.removeBook("miora", author: "我")) { XCTAssertEqual($0 as? ManageError, .bookInUse("Miora 美甲店", 2)) }
        XCTAssertThrowsError(try l.removeBook("miora", moveTo: "miora", author: "我"))
        let change = try l.removeBook("miora", moveTo: "personal", author: "我")
        XCTAssertEqual(l.books.map(\.id), ["personal"])
        XCTAssertEqual(l.transactions[0].bookID, "personal")
        XCTAssertEqual(l.goals[0].bookID, "personal")
        try l.undo(changeID: change.id, author: "我")
        XCTAssertTrue(l.books.contains { $0.id == "miora" })
        XCTAssertEqual(l.transactions[0].bookID, "miora")
        XCTAssertEqual(l.goals[0].bookID, "miora")
    }

    func testOldBookWithoutKindStillDecodes() throws {
        let data = Data(#"{"id":"x","name":"店","currency":"EUR"}"#.utf8)
        let b = try JSONDecoder().decode(Book.self, from: data)
        XCTAssertNil(b.kind)
        XCTAssertFalse(b.isBusiness)
    }
}

/// 夏夏的性格、你的目标、自己加的分类、写给某一页的意见（2026-11-21 ming 要的）。
final class ProfileTests: XCTestCase {
    func testPersonaAndAimUndo() throws {
        var l = Ledger.fresh
        XCTAssertEqual(l.profile.persona, .gentle, "默认是温和直说")
        let c1 = try l.setPersona(.sharp, author: "我")
        XCTAssertEqual(l.profile.persona, .sharp)
        XCTAssertThrowsError(try l.setPersona(.sharp, author: "我"))
        let c2 = try l.setAim("  每个月存下 500 €  ", author: "我")
        XCTAssertEqual(l.profile.aim, "每个月存下 500 €")
        _ = try l.undo(changeID: c2.id, author: "我")
        XCTAssertNil(l.profile.aim)
        XCTAssertEqual(l.profile.persona, .sharp, "撤销目标不动性格")
        _ = try l.undo(changeID: c1.id, author: "我")
        XCTAssertEqual(l.profile.persona, .gentle)
        _ = try l.setAim("少点外卖", author: "我")
        _ = try l.setAim("", author: "我")
        XCTAssertNil(l.profile.aim, "空字符串 = 清掉")
    }

    /// 给助手改名、设怎么称呼用户（ming 2026-11-23）：界面文字里的「夏夏」跟着换，「夏夏账本」不换；能撤销；AI 拿得到。
    func testAssistantNameAndCallUser() throws {
        var l = Ledger.fresh
        XCTAssertEqual(l.profile.xiaName, "夏夏")
        XCTAssertEqual(l.profile.renamed("问夏夏"), "问夏夏", "没改名不动")
        let c = try l.setNames(assistant: "  小橙  ", callUser: "阿明", author: "我")
        XCTAssertEqual(l.profile.xiaName, "小橙")
        XCTAssertEqual(l.profile.userCallName, "阿明")
        XCTAssertEqual(l.profile.renamed("问夏夏"), "问小橙")
        XCTAssertEqual(l.profile.renamed("打开夏夏账本，让夏夏细说"), "打开夏夏账本，让小橙细说")
        let ctx = LedgerContext(ledger: l)
        XCTAssertEqual(ctx.assistantName, "小橙")
        XCTAssertEqual(ctx.callUser, "阿明")
        let prompt = ChatRunner.prompt(question: "午饭 12", voice: "", aim: nil, where: "总览", history: [(true, "嗨")],
                                       name: l.profile.xiaName, callUser: l.profile.userCallName)
        XCTAssertTrue(prompt.contains("你是「小橙」") && prompt.contains("称呼用户「阿明」"))
        XCTAssertThrowsError(try l.setNames(assistant: "小橙", callUser: "阿明", author: "我"), "没变要提示")
        _ = try l.setNames(assistant: "夏夏", callUser: "", author: "我")
        XCTAssertNil(l.profile.assistantName, "填回「夏夏」= 默认")
        XCTAssertNil(l.profile.userCallName)
        _ = try l.setNames(assistant: "一二三四五六七八九十一二三", callUser: nil, author: "我")
        XCTAssertEqual(l.profile.xiaName.count, 12, "名字最多 12 个字")
        var u = Ledger.fresh
        let c2 = try u.setNames(assistant: "小橙", callUser: nil, author: "我")
        _ = try u.undo(changeID: c2.id, author: "我")
        XCTAssertNil(u.profile.assistantName, "能撤销")
        _ = c
        let data = try JSONEncoder().encode(l.profile)
        XCTAssertNoThrow(try JSONDecoder().decode(Profile.self, from: data))
    }

    func testAddCategoryAndRename() throws {
        var l = Ledger.fresh
        l.accounts = [Account(id: "bank", name: "银行卡", kind: .bank)]
        let c = try l.addCategory("宠物", income: false, author: "我")
        XCTAssertEqual(l.profile.categories, [CustomCategory(name: "宠物", income: false)])
        XCTAssertThrowsError(try l.addCategory("宠物", income: false, author: "我"), "重名要提示")
        XCTAssertNoThrow(try l.addCategory("宠物", income: true, author: "我"), "收入里可以有同名的")
        _ = try l.renameCategory("宠物", to: "猫狗", author: "我")
        XCTAssertTrue(l.profile.categories.contains(CustomCategory(name: "猫狗", income: false)))
        XCTAssertFalse(l.profile.categories.contains { $0.name == "宠物" })
        _ = try l.undo(changeID: c.id, author: "我")
        XCTAssertFalse(l.profile.categories.contains { $0.name == "宠物" && !$0.income })
    }

    func testCategoryIcons() throws {
        var l = Ledger.fresh
        l.accounts = [Account(id: "bank", name: "银行卡", kind: .bank)]
        XCTAssertTrue(CategoryIcons.isValid("bubbletea"))
        XCTAssertFalse(CategoryIcons.isValid("nosuchicon"))
        XCTAssertThrowsError(try l.addCategory("奶茶", income: false, icon: "nosuchicon", author: "我"), "不认识的图标要提示")
        XCTAssertTrue(l.profile.categories.isEmpty, "报错不留半截")
        _ = try l.addCategory("奶茶", income: false, icon: "bubbletea", author: "我")
        XCTAssertEqual(l.categoryIcons, ["奶茶": "bubbletea"])

        // 已有流水、没自建过的分类也能换图标；方向按流水猜
        _ = try l.addTransaction(Transaction(date: .today, amount: Money(cents: 120_000), description: "工资", accountID: "bank",
                                             bookID: "personal", category: "工资"), author: "我")
        let c = try l.setCategoryIcon("工资", icon: "bonus", author: "我")
        XCTAssertEqual(l.categoryIcons["工资"], "bonus")
        XCTAssertEqual(l.profile.categories.first { $0.name == "工资" }?.income, true)
        _ = try l.undo(changeID: c.id, author: "我")
        XCTAssertNil(l.categoryIcons["工资"], "换图标能撤销")

        _ = try l.setCategoryIcon("奶茶", icon: nil, author: "我")
        XCTAssertNil(l.categoryIcons["奶茶"], "nil = 改回自动")
        XCTAssertTrue(l.profile.categories.contains { $0.name == "奶茶" }, "改回自动不删分类")

        // 改名、并进别的分类，挑过的图标跟着走
        _ = try l.setCategoryIcon("奶茶", icon: "bubbletea", author: "我")
        _ = try l.addCategory("饮品", income: false, author: "我")
        _ = try l.renameCategory("奶茶", to: "饮品", author: "我")
        XCTAssertEqual(l.profile.categories.filter { $0.name == "饮品" }.count, 1, "并进去只留一个")
        XCTAssertEqual(l.categoryIcons["饮品"], "bubbletea", "并进去图标不丢")
    }

    func testOldProfileWithoutIconsStillLoads() throws {
        let p = try JSONDecoder().decode(Profile.self, from: Data(#"{"persona":"calm","categories":[{"name":"宠物","income":false}]}"#.utf8))
        XCTAssertEqual(p.categories, [CustomCategory(name: "宠物", income: false)])
        XCTAssertNil(p.categories[0].icon)
    }

    func testRenameCategoryWithTransactionsAlsoRenamesCustom() throws {
        var l = Ledger.fresh
        l.accounts = [Account(id: "bank", name: "银行卡", kind: .bank)]
        _ = try l.addCategory("咖啡", income: false, author: "我")
        _ = try l.addTransaction(Transaction(date: .today, amount: Money(cents: -350), description: "咖啡", accountID: "bank",
                                             bookID: "personal", category: "咖啡"), author: "我")
        let r = try l.renameCategory("咖啡", to: "饮料", author: "我")
        XCTAssertEqual(l.transactions[0].category, "饮料")
        XCTAssertEqual(l.profile.categories.map(\.name), ["饮料"])
        _ = try l.undo(changeID: r.id, author: "我")
        XCTAssertEqual(l.transactions[0].category, "咖啡")
        XCTAssertEqual(l.profile.categories.map(\.name), ["咖啡"])
    }

    func testInsightForPage() throws {
        var l = Ledger.fresh
        let m = LocalDate.today.yearMonth
        _ = try l.addInsight(Insight(month: m, kind: .tip, title: "总览这条", body: "", author: "Claude"), author: "Claude")
        _ = try l.addInsight(Insight(month: m, kind: .alert, title: "花销这条", body: "", page: "spending", author: "Claude"), author: "Claude")
        XCTAssertEqual(l.insight(forPage: "overview", month: m, bookID: nil)?.title, "总览这条", "没写页面的算总览")
        XCTAssertEqual(l.insight(forPage: "spending", month: m, bookID: nil)?.title, "花销这条")
        XCTAssertNil(l.insight(forPage: "trends", month: m, bookID: nil))
    }

    func testContextCarriesVoiceAndAim() throws {
        var l = Ledger.fresh
        _ = try l.setPersona(.calm, author: "我")
        _ = try l.setAim("先把信用卡还清", author: "我")
        let ctx = LedgerContext(ledger: l)
        XCTAssertEqual(ctx.persona, "文静")
        XCTAssertEqual(ctx.voice, Persona.calm.instruction)
        XCTAssertEqual(ctx.aim, "先把信用卡还清")
    }

    func testProfileSurvivesSQLiteAndUnknownPersona() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var l = Ledger.fresh
        _ = try l.setPersona(.cheer, author: "我")
        _ = try l.addCategory("宠物", income: false, author: "我")
        try SQLiteLedgerStore(url: url).save(l)
        let back = try SQLiteLedgerStore(url: url).load()
        XCTAssertEqual(back.profile, l.profile)
        let odd = try JSONDecoder().decode(Profile.self, from: Data(#"{"persona":"pirate"}"#.utf8))
        XCTAssertEqual(odd.persona, .gentle, "不认识的性格当默认")
    }
}
