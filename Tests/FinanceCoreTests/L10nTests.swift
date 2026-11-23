import XCTest
@testable import FinanceCore

/// 多语言：查表、带值的句子、两张表对不对得上。
final class L10nTests: XCTestCase {
    override func tearDown() { L10n.choice = L10n.fallbackChoice }

    func testLookupAndFallback() {
        XCTAssertEqual(L10n.string("家底", in: .zhHans), "家底")
        XCTAssertEqual(L10n.string("家底", in: .en), "Net worth")
        XCTAssertEqual(L10n.string("家底", in: .es), "Patrimonio")
        XCTAssertEqual(L10n.string("表里没有的一句话", in: .en), "表里没有的一句话", "没翻的显示中文原文")
        L10n.choice = .es
        XCTAssertEqual(tr("设置"), "Ajustes")
        XCTAssertEqual(trKey("流水"), "Movimientos")
        L10n.choice = .zhHans
        XCTAssertEqual(tr("设置"), "设置")
    }

    func testInterpolationBecomesPlaceholders() {
        let n = 3, name = "店"
        let t: L10nText = "\(name)有 \(n) 笔"
        XCTAssertEqual(t.key, "%@有 %@ 笔")
        XCTAssertEqual(t.args, ["店", "3"])
        XCTAssertEqual(L10n.string(t, in: .zhHans), "店有 3 笔")
        XCTAssertEqual(L10n.fill("%2$@ items in %1$@", ["Shop", "3"]), "3 items in Shop", "译文可以换顺序")
        XCTAssertEqual(L10n.fill("%@ of %@", ["1", "2"]), "1 of 2")
        XCTAssertEqual(L10n.fill("50% 的 %@", ["钱"]), "50% 的 钱", "普通百分号不受影响")
    }

    func testSystemLanguagePick() {
        XCTAssertEqual(AppLanguage.fromSystem(["es-ES", "en-GB"]), .es)
        XCTAssertEqual(AppLanguage.fromSystem(["zh-Hans-CN"]), .zhHans)
        XCTAssertEqual(AppLanguage.fromSystem(["fr-FR", "en-US"]), .en)
        XCTAssertEqual(AppLanguage.fromSystem(["fr-FR"]), .en, "都没有就用英文")
    }

    func testLoadFromDefaults() {
        let d = UserDefaults(suiteName: "xiaxia-l10n-\(UUID().uuidString)")!
        XCTAssertEqual(L10n.load(from: d), L10n.fallbackChoice)
        d.set("es", forKey: L10n.defaultsKey)
        XCTAssertEqual(L10n.load(from: d), .es)
        XCTAssertEqual(L10n.language, .es)
        d.set("乱写的", forKey: L10n.defaultsKey)
        XCTAssertEqual(L10n.load(from: d), L10n.fallbackChoice)
    }

    /// 英文、西班牙语两张表的键要一模一样，译文不能空，`%@` 的个数要和原文一样。
    func testTablesAreComplete() {
        XCTAssertEqual(Set(L10n.en.keys), Set(L10n.es.keys), "两张表的键不一样")
        for (lang, table) in [("en", L10n.en), ("es", L10n.es)] {
            for (key, value) in table {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang)「\(key)」是空的")
                XCTAssertEqual(L10n.placeholders(value), L10n.placeholders(key), "\(lang)「\(key)」里 %@ 的个数和原文不一样")
            }
        }
    }
}
