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
