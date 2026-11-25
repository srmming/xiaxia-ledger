import XCTest
@testable import LedgerUI

final class MascotImagesTests: XCTestCase {
    /// 生意版每个角色都有待机图，打开生意那边就用生意版。
    func testBusinessSetIsUsedWhenAvailable() {
        for c in ["xiaxia", "orange", "lilac", "star"] {
            XCTAssertTrue(MascotImages.has("\(c)-biz-idle"), "缺 \(c)-biz-idle")
        }
        XCTAssertEqual(MascotImages.prefix(.xiaxia, .girl, business: true), "xiaxia-biz")
        XCTAssertEqual(MascotImages.key(.xiaxia, .write, business: true), "xiaxia-biz-write")
        // 生活那边不受影响。
        XCTAssertEqual(MascotImages.prefix(.xiaxia, .girl), "xiaxia")
        XCTAssertEqual(MascotImages.key(.xiaxia, .write), "xiaxia-write")
    }

    /// 缺图时一级一级退：男生生意版还没画，男生在生意那边先用男生的生活版。
    func testFallbackOrder() {
        XCTAssertEqual(MascotImages.candidates("xiaxia", .boy, business: true), ["xiaxia-biz-boy", "xiaxia-boy", "xiaxia-biz", "xiaxia"])
        XCTAssertEqual(MascotImages.candidates("xiaxia", .girl, business: true), ["xiaxia-biz", "xiaxia"])
        XCTAssertEqual(MascotImages.candidates("xiaxia", .boy, business: false), ["xiaxia-boy", "xiaxia"])
        XCTAssertEqual(MascotImages.prefix(.xiaxia, .boy, business: true), "xiaxia-boy")
    }

    /// 生意版没有的动作退回生意版的待机图，不混进生活版的画风。
    func testMissingPoseFallsBackToBusinessIdle() {
        XCTAssertEqual(MascotImages.key(.orange, .celebrate, business: true), "orange-biz-idle")
    }
}
