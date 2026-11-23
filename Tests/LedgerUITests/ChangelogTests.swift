import XCTest
@testable import LedgerUI

/// 更新日志：app 带的那份读得出来；更新后第一次打开该不该出「这次更新了什么」。版本内容都是编的。
@MainActor
final class ChangelogTests: XCTestCase {
    private let sample: [ChangelogEntry] = Changelog.decode(Data("""
    {"releases":[
      {"version":"0.2.10","date":"2026-12-01","title":"十","summary":"s","items":["a"]},
      {"version":"0.2.9","date":"2026-11-30","title":"九","summary":"s","items":["b"]},
      {"version":"0.2.5","date":"2026-11-24","title":"五","summary":"s","items":["c"]},
      {"version":"0.2.4","date":"2026-11-23","title":"四","summary":"s","items":["d"]}
    ]}
    """.utf8))

    private func freshDefaults() -> UserDefaults {
        let name = "xiaxia.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testBundledChangelogLoads() {
        XCTAssertFalse(Changelog.all.isEmpty)
        XCTAssertTrue(Changelog.all.allSatisfy { !$0.title.isEmpty && !$0.items.isEmpty })
        let versions = Changelog.all.map(\.version)
        XCTAssertEqual(versions, versions.sorted { Changelog.isNewer($0, than: $1) })
    }

    func testVersionCompare() {
        XCTAssertTrue(Changelog.isNewer("0.2.10", than: "0.2.9"))
        XCTAssertTrue(Changelog.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(Changelog.isNewer("0.2.4", than: "0.2.4"))
        XCTAssertEqual(sample.map(\.version), ["0.2.10", "0.2.9", "0.2.5", "0.2.4"])
    }

    func testEntriesBetweenVersions() {
        XCTAssertEqual(Changelog.entries(after: "0.2.4", upTo: "0.2.9", in: sample).map(\.version), ["0.2.9", "0.2.5"])
        XCTAssertTrue(Changelog.entries(after: "0.2.10", upTo: "0.2.10", in: sample).isEmpty)
    }

    func testNewInstallShowsNothingAndRemembersVersion() {
        let d = freshDefaults()
        XCTAssertTrue(WhatsNewState.pending(current: "0.2.9", hasData: false, defaults: d, list: sample).isEmpty)
        XCTAssertEqual(d.string(forKey: WhatsNewState.seenKey), "0.2.9")
    }

    func testOldUserWithoutRecordCountsFrom024() {
        let d = freshDefaults()
        XCTAssertEqual(WhatsNewState.pending(current: "0.2.5", hasData: true, defaults: d, list: sample).map(\.version), ["0.2.5"])
        XCTAssertNil(d.string(forKey: WhatsNewState.seenKey), "没点「知道了」之前不记，下次打开还出")
    }

    func testAfterUpdateShowsEverySkippedVersionOnce() {
        let d = freshDefaults()
        d.set("0.2.5", forKey: WhatsNewState.seenKey)
        XCTAssertEqual(WhatsNewState.pending(current: "0.2.10", hasData: true, defaults: d, list: sample).map(\.version), ["0.2.10", "0.2.9"])
        d.set("0.2.10", forKey: WhatsNewState.seenKey)
        XCTAssertTrue(WhatsNewState.pending(current: "0.2.10", hasData: true, defaults: d, list: sample).isEmpty)
    }

    func testVersionWithoutNotesShowsNothing() {
        let d = freshDefaults()
        d.set("0.2.10", forKey: WhatsNewState.seenKey)
        XCTAssertTrue(WhatsNewState.pending(current: "0.2.11", hasData: true, defaults: d, list: sample).isEmpty)
        XCTAssertEqual(d.string(forKey: WhatsNewState.seenKey), "0.2.11")
    }
}
