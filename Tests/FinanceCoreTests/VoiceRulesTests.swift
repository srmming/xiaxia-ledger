import XCTest
@testable import FinanceCore

final class VoiceRulesTests: XCTestCase {
    func testPauseChoices() {
        XCTAssertEqual(VoiceRules.pauses.indices.map(VoiceRules.title), ["1 秒", "1,5 秒", "2 秒", "不自动发"])
        XCTAssertEqual(VoiceRules.pause(VoiceRules.defaultIndex), 1.5)
        XCTAssertNil(VoiceRules.pause(3) as Double?, "不自动发：没有停顿时长")
        XCTAssertEqual(VoiceRules.pause(99), 1.5, "乱给的序号用默认的")
    }
}
