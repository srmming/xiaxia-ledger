import XCTest
@testable import FinanceCore

final class AppLockTests: XCTestCase {
    func testOffNeverLocks() {
        let p = AppLockPolicy(enabled: false, grace: 0)
        XCTAssertFalse(p.locks(on: .launch))
        XCTAssertFalse(p.locks(on: .wake))
        XCTAssertFalse(p.locks(on: .returned(after: 10_000)))
    }

    func testLaunchAndWakeAlwaysLock() {
        let p = AppLockPolicy(enabled: true, grace: 900)
        XCTAssertTrue(p.locks(on: .launch))
        XCTAssertTrue(p.locks(on: .wake))
    }

    func testGrace() {
        let p = AppLockPolicy(enabled: true, grace: 300)
        XCTAssertFalse(p.locks(on: .returned(after: 20)))
        XCTAssertFalse(p.locks(on: .returned(after: 299)))
        XCTAssertTrue(p.locks(on: .returned(after: 300)))
        XCTAssertTrue(AppLockPolicy(enabled: true, grace: 0).locks(on: .returned(after: 0)), "立刻：一离开就锁")
        XCTAssertTrue(AppLockPolicy(enabled: true, grace: 0).locks(on: .returned(after: 1)))
    }

    func testUnknownGraceFallsBackToFiveMinutes() {
        XCTAssertEqual(AppLockPolicy(enabled: true, grace: 42).grace, 300)
        XCTAssertEqual(AppLockPolicy().enabled, false, "默认不上锁")
    }
}
