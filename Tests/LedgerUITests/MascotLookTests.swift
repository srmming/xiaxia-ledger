import XCTest
@testable import LedgerUI

/// 夏夏的样子：只留夏夏一个角色，7 种样子，旧设置直接对上，缺图退回。
final class MascotLookTests: XCTestCase {
    /// 老用户升级：存着的 girl / boy 原样对上女孩 / 男孩；认不出来的值（比如以后的新样子被旧版读到）是女孩。
    func testOldSettingsMapStraightAcross() {
        XCTAssertEqual(MascotLook.stored("girl"), .girl)
        XCTAssertEqual(MascotLook.stored("boy"), .boy)
        XCTAssertEqual(MascotLook.stored(""), .girl)
        XCTAssertEqual(MascotLook.stored("dragon"), .girl)
        XCTAssertEqual(MascotLook.storageKey, "mascotLook", "沿用旧键，不用搬设置")
    }

    /// 现在能挑的：4 种人物有图；宠物画齐之前不出现。
    func testAvailableLooksFollowImages() {
        for look in [MascotLook.girl, .boy, .woman, .man] {
            XCTAssertTrue(MascotLook.available.contains(look), "\(look) 应该能挑")
            for pose in MascotPose.allCases {
                XCTAssertTrue(MascotImages.has("\(look.prefix)-\(pose.rawValue)"), "缺 \(look.prefix)-\(pose.rawValue)")
            }
            XCTAssertTrue(MascotImages.has("\(look.prefix)-blink") && MascotImages.has("\(look.prefix)-talk"), "\(look) 缺眨眼或说话帧")
        }
        for pet in [MascotLook.cat, .westie, .capy] where !MascotImages.has("\(pet.prefix)-idle") {
            XCTAssertFalse(MascotLook.available.contains(pet))
            // 存了一个还没有图的样子：照女孩显示，不出空白。
            XCTAssertEqual(MascotLook.stored(pet.rawValue), .girl)
            XCTAssertEqual(MascotImages.key(.write, look: pet), "xiaxia-write")
        }
        XCTAssertEqual(MascotLook.kidChoices, [.girl, .boy])
    }

    /// 只剩夏夏：伙伴的图不在 app 里了（挪到 design/mascot/retired/partners）。
    func testPartnersAreGone() {
        for name in ["orange", "lilac", "star"] {
            XCTAssertFalse(MascotImages.has("\(name)-idle"), "\(name) 的图还在 app 里")
            XCTAssertNil(MascotData.faces["\(name)-idle"])
        }
    }

    /// 每种有图的样子都有脸的位置（小圆头像用）。
    func testEveryLookHasFace() {
        for look in MascotLook.available {
            XCTAssertNotNil(MascotData.faces["\(look.prefix)-idle"], "\(look) 没有脸的位置")
        }
    }

    /// 开生意模式：没自己挑过的女孩 / 男孩换成同性别的成年版；挑过的、宠物、成年版不动。
    func testBusinessSuggestion() {
        XCTAssertEqual(MascotLook.businessSuggestion(current: .girl, chosen: false), .woman)
        XCTAssertEqual(MascotLook.businessSuggestion(current: .boy, chosen: false), .man)
        XCTAssertNil(MascotLook.businessSuggestion(current: .girl, chosen: true))
        XCTAssertNil(MascotLook.businessSuggestion(current: .woman, chosen: false))
        XCTAssertNil(MascotLook.businessSuggestion(current: .cat, chosen: false))
    }

    func testApplyBusinessDefaultReturnsPreviousForUndo() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MascotLookTests-\(UUID().uuidString)"))
        defaults.set("boy", forKey: MascotLook.storageKey)
        XCTAssertEqual(MascotLook.applyBusinessDefault(defaults), .boy, "返回换之前的，给「换回来」用")
        XCTAssertEqual(defaults.string(forKey: MascotLook.storageKey), "man")
        XCTAssertNil(MascotLook.applyBusinessDefault(defaults), "已经是成年版，再开一次不动")
        defaults.set("girl", forKey: MascotLook.storageKey)
        defaults.set(true, forKey: MascotLook.chosenKey)
        XCTAssertNil(MascotLook.applyBusinessDefault(defaults), "自己挑过的不动")
        XCTAssertEqual(defaults.string(forKey: MascotLook.storageKey), "girl")
    }

    /// 女孩版的 4 段逐帧动画都在，帧数和时长对得上；别的样子没有就不播。
    func testGirlClips() throws {
        let expected: [(MascotPose, Int)] = [(.hello, 8), (.cheer, 8), (.celebrate, 8), (.write, 12)]
        for (pose, count) in expected {
            let clip = try XCTUnwrap(MascotClip.for(pose, look: .girl), "女孩没有 \(pose) 动画")
            XCTAssertEqual(clip.frames.count, count)
            for f in clip.frames { XCTAssertTrue(MascotImages.has(f.key), "缺帧 \(f.key)") }
            XCTAssertEqual(clip.frame(at: 0), clip.frames[0].key)
            XCTAssertEqual(clip.frame(at: clip.duration + 5), clip.frames[count - 1].key, "播完停在最后一帧")
        }
        XCTAssertNil(MascotClip.for(.hello, look: .woman))
        XCTAssertNil(MascotClip.for(.idle, look: .girl))
    }
}
