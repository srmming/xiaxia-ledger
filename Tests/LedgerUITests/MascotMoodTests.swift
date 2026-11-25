import XCTest
@testable import LedgerUI

/// 夏夏像宠物一样的 6 个反应（用假的钟，不真等）。
@MainActor
final class MascotMoodTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var roll = 0.0

    private func makeMood(_ look: MascotLook = .woman) -> MascotMood {
        let mood = MascotMood(now: { [unowned self] in clock }, random: { [unowned self] r in r.lowerBound + (r.upperBound - r.lowerBound) * roll })
        mood.look = { look }
        return mood
    }

    private func advance(_ mood: MascotMood, _ seconds: Double) {
        for _ in 0..<Int(seconds) { clock.addTimeInterval(1); mood.tick() }
    }

    /// 1. 点它：换成打招呼或欢呼，过一会儿回到页面给的动作；连点 5 下就毒舌。
    func testPokeAndPokeFiveTimes() {
        let mood = makeMood()
        mood.poke()
        XCTAssertTrue([.hello, .cheer].contains(mood.pose(base: .idle)))
        advance(mood, 2)
        XCTAssertEqual(mood.pose(base: .worried), .worried, "反应完回到页面给的动作")
        for _ in 0..<5 { mood.poke() }
        XCTAssertEqual(mood.pose(base: .idle), .sharp)
    }

    /// 2. 闲着时隔一阵做个小动作。
    func testIdleFidget() {
        let mood = makeMood()
        roll = 0
        advance(mood, 12)
        XCTAssertNotEqual(mood.pose(base: .idle), .idle, "12 秒没事做个小动作")
        advance(mood, 2)
        XCTAssertEqual(mood.pose(base: .idle), .idle)
    }

    /// 3. 两分钟没人理就睡，点一下醒来先打招呼。
    func testFallsAsleepAndWakes() {
        let mood = makeMood()
        roll = 1 // 小动作间隔拉到最长
        advance(mood, MascotMood.sleepAfter + 1)
        XCTAssertTrue(mood.asleep)
        XCTAssertEqual(mood.pose(base: .idle), .sleep)
        mood.poke()
        XCTAssertFalse(mood.asleep)
        XCTAssertEqual(mood.pose(base: .idle), .hello)
    }

    /// 4. 记一笔：先写，再欢呼，然后回去。3 秒内连着记很多笔只反应一次。
    func testRecordedSequenceAndCooldown() {
        let mood = makeMood()
        mood.note(.recorded)
        XCTAssertEqual(mood.pose(base: .idle), .write)
        advance(mood, 1)
        XCTAssertEqual(mood.pose(base: .idle), .cheer)
        advance(mood, 1)
        XCTAssertEqual(mood.pose(base: .idle), .idle)
        mood.note(.recorded)
        clock.addTimeInterval(0.5)
        let before = mood.moment
        mood.note(.recorded)
        XCTAssertEqual(mood.moment, before, "冷却中不重新开始")
    }

    /// 5. 存钱、回本：庆祝。
    func testSavedCelebrates() {
        let mood = makeMood()
        mood.note(.saved)
        XCTAssertEqual(mood.pose(base: .idle), .celebrate)
        let other = makeMood()
        other.note(.recovered)
        XCTAssertEqual(other.pose(base: .idle), .celebrate)
    }

    /// 6. 花超了：页面给「担心」，没有临时反应时就显示担心。
    func testWorriedBaseShows() {
        XCTAssertEqual(makeMood().pose(base: .worried), .worried)
    }

    /// 女孩版：反应有逐帧动画时播动画，时长按动画来。
    func testGirlPlaysClip() throws {
        let mood = makeMood(.girl)
        mood.note(.saved)
        let m = try XCTUnwrap(mood.moment)
        XCTAssertEqual(m.clip?.name, "xiaxia-celebrate")
        XCTAssertGreaterThanOrEqual(m.until.timeIntervalSince(m.start), 2.5)
        let adult = makeMood(.woman)
        adult.note(.saved)
        XCTAssertNil(adult.moment?.clip, "成年版还没有逐帧动画，用单张图")
    }
}
