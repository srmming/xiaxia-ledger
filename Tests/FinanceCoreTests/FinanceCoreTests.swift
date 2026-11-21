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
        XCTAssertEqual(try store.load(), .starter)
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
        XCTAssertEqual(try store.load(), .starter)
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
