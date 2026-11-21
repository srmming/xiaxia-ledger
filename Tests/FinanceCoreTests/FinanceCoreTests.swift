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
