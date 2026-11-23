import XCTest
@testable import FinanceCore

/// 「欠款与分期」顶上那一行、家底里补上的那部分。全是编造数据。
final class ObligationsTests: XCTestCase {
    private func d(_ m: Int, _ day: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: day) }

    private func ledger() -> Ledger {
        var l = Ledger.starter
        l.accounts = [Account(id: "bank", name: "示例银行", kind: .bank)]
        return l
    }

    func testDebtsAndInstallmentsAddUpAsOfADate() throws {
        var l = ledger()
        let book = l.books[0].id
        let (lent, _) = try l.addDebt(counterparty: "小林", direction: .theyOweMe, amount: Money(cents: 30000), bookID: book,
                                      date: d(9, 1), accountID: "bank", author: "t")
        try l.repay(debtID: lent.id, amount: Money(cents: 10000), date: d(10, 15), accountID: "bank", author: "t")
        _ = try l.addDebt(counterparty: "表姐", direction: .iOweThem, amount: Money(cents: 50000), bookID: book,
                          date: d(10, 1), accountID: "bank", author: "t")
        let (inst, _) = try l.addInstallment(name: "示例手机", bookID: book, accountID: "bank", total: Money(cents: 60000), count: 6,
                                             purchaseDate: d(9, 20), firstPayment: d(10, 5), author: "t")
        try l.payInstallment(inst.id, date: d(10, 5), author: "t")

        // 9 月底：小林欠 300，分期 600 还没还
        let sep = Plans.obligations(l, asOf: d(9, 30))
        XCTAssertEqual(sep.owedToMe.cents, 30000)
        XCTAssertEqual(sep.iOwe.cents, 60000)
        // 10 月底：小林还了 100；表姐借了 500；分期还了一期 100
        let oct = Plans.obligations(l, asOf: d(10, 31))
        XCTAssertEqual(oct.owedToMe.cents, 20000)
        XCTAssertEqual(oct.iOwe.cents, 50000 + 50000)
        XCTAssertEqual(oct.net.cents, 20000 - 100000)
        // 我还欠的拆开：分期 500 + 借来的 500
        XCTAssertEqual(oct.installments.cents, 50000)
        XCTAssertEqual(oct.borrowed.cents, 50000)
        // 借之前什么都没有
        XCTAssertTrue(Plans.obligations(l, asOf: d(8, 31)).isEmpty)
    }

    func testClosedDebtAndOtherBookLeftOut() throws {
        var l = ledger()
        l.books.append(Book(id: "shop", name: "示例小店", currency: "EUR"))
        var (debt, _) = try l.addDebt(counterparty: "小林", direction: .theyOweMe, amount: Money(cents: 30000), bookID: l.books[0].id,
                                      date: d(9, 1), accountID: nil, author: "t")
        _ = try l.addDebt(counterparty: "供货商", direction: .iOweThem, amount: Money(cents: 12000), bookID: "shop",
                          date: d(9, 1), accountID: nil, author: "t")
        XCTAssertEqual(Plans.obligations(l, asOf: d(9, 2), bookID: "shop").iOwe.cents, 12000)
        XCTAssertEqual(Plans.obligations(l, asOf: d(9, 2), bookID: "shop").owedToMe.cents, 0)
        debt.closed = true
        try l.updateDebt(debt, author: "t")
        XCTAssertEqual(Plans.obligations(l, asOf: d(9, 2)).owedToMe.cents, 0)
    }
}
