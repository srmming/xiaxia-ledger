import XCTest
@testable import FinanceCore

final class VoiceRulesTests: XCTestCase {
    func testPauseChoices() {
        XCTAssertEqual(VoiceRules.pauses.indices.map(VoiceRules.title), ["1 秒", "1,5 秒", "2 秒", "不自动发"])
        XCTAssertEqual(VoiceRules.pause(VoiceRules.defaultIndex), 1.5)
        XCTAssertNil(VoiceRules.pause(3) as Double?, "不自动发：没有停顿时长")
        XCTAssertEqual(VoiceRules.pause(99), 1.5, "乱给的序号用默认的")
    }

    /// 听写语言：三种，默认中文；序号不对回到中文。
    func testDictationLanguages() {
        XCTAssertEqual(VoiceRules.languages.map(\.title), ["中文", "西班牙语", "英语"])
        XCTAssertEqual(VoiceRules.languages.map(\.localeID), ["zh-CN", "es-ES", "en-US"])
        XCTAssertEqual(VoiceRules.localeID(VoiceRules.defaultLanguageIndex), "zh-CN")
        XCTAssertEqual(VoiceRules.localeID(1), "es-ES"); XCTAssertEqual(VoiceRules.languageTitle(2), "英语")
        XCTAssertEqual(VoiceRules.localeID(9), "zh-CN"); XCTAssertEqual(VoiceRules.languageTitle(-1), "中文")
    }
}
