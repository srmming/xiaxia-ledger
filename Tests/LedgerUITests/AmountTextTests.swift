import XCTest
import FinanceCore
@testable import LedgerUI

/// 界面上的金额：数字和 € 之间用不换行空格，€ 不会单独换到下一行；fin / MCP 用的 formatted 保持普通空格。
final class AmountTextTests: XCTestCase {
    func testUIAmountKeepsEuroOnSameLine() {
        let m = Money(cents: 388_237)
        XCTAssertEqual(m.formatted, "3.882,37 €")
        XCTAssertEqual(m.ui, "3.882,37\u{00A0}€")
        XCTAssertEqual(Money(cents: -2340).display, "\u{2212}23,40\u{00A0}€")
        XCTAssertEqual(Money(cents: 115_000).rounded, "1.150\u{00A0}€")
    }

    func testFreeTextFromAI() {
        XCTAssertEqual("已经存了 3.000,00 €，目标 5.000,00 €。".keepingAmountsTogether,
                       "已经存了 3.000,00\u{00A0}€，目标 5.000,00\u{00A0}€。")
        XCTAssertEqual("每月 20 USD 和 9 月 5 日".keepingAmountsTogether, "每月 20\u{00A0}USD 和 9 月 5 日")
    }
}
