import XCTest
import FinanceCore
@testable import LedgerUI

/// 分类名 → 图标：真实账本里常见的「大类·小类」写法都要配上，不能落到「其他」。名字都是编的写法示例。
final class CategoryStyleTests: XCTestCase {
    func testRealWorldNames() {
        let cases: [(String, XiaGlyph)] = [
            ("餐饮", .dining), ("交通出行", .transport), ("超市日用", .grocery), ("奶茶", .bubbletea),
            ("店铺·房租押金", .shoprent), ("AI·软件·订阅", .subscription), ("转给亲友·汇款", .remit),
            ("取现金", .cash), ("店铺·服务与保险", .insurance), ("住房·水电燃气", .utilities),
            ("美甲店收入", .revenue), ("其他收入", .income), ("员工工资", .staff), ("个人·外卖", .delivery),
            ("退税", .taxrefund), ("店租", .shoprent),
        ]
        for (name, want) in cases {
            XCTAssertEqual(CategoryStyle.glyph(name), want, name)
        }
        XCTAssertEqual(CategoryStyle.glyph(nil), .uncategorized)
        XCTAssertEqual(CategoryStyle.glyph("完全对不上的名字xyz"), .other)
    }

    func testEveryIconLabelMatchesItself() {
        for (name, label) in CategoryIcons.all where name != "other" {
            let g = CategoryStyle.glyph(label)
            XCTAssertNotEqual(g, .other, "「\(label)」(\(name)) 配不上图标")
        }
    }

    func testPickedIconWins() {
        CategoryStyle.customIcons = ["餐饮": "hotpot"]
        defer { CategoryStyle.customIcons = [:] }
        XCTAssertEqual(CategoryStyle.glyph("餐饮"), .hotpot)
        CategoryStyle.customIcons = [:]
        XCTAssertEqual(CategoryStyle.glyph("餐饮"), .dining, "改回自动后缓存要清掉")
    }

    func testMonogramSkipsDigits() {
        XCTAssertEqual(Monogram.initial("12 | Ana López"), "A")
        XCTAssertEqual(Monogram.initial("mercadona"), "M")
        XCTAssertEqual(Monogram.initial("街角咖啡"), "街")
        XCTAssertEqual(Monogram.initial("123"), "1")
        XCTAssertEqual(Monogram.initial(""), "")
    }
}
