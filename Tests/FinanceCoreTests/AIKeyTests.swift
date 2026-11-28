import XCTest
@testable import FinanceCore

/// 只用编出来的假密钥，只用内存里的假钥匙串。
final class AIKeyTests: XCTestCase {
    func testCleanKey() throws {
        XCTAssertEqual(try AIKeyRules.cleanKey("  sk-demo-000\n"), "sk-demo-000")
        XCTAssertThrowsError(try AIKeyRules.cleanKey("   "))
        XCTAssertThrowsError(try AIKeyRules.cleanKey("sk-demo 000"))
        XCTAssertThrowsError(try AIKeyRules.cleanKey("short"))
    }

    func testCleanAddress() throws {
        XCTAssertEqual(try AIKeyRules.cleanAddress(" https://api.example.com/v1 "), "https://api.example.com/v1")
        XCTAssertEqual(try AIKeyRules.cleanAddress("http://localhost:11434/v1"), "http://localhost:11434/v1")
        XCTAssertThrowsError(try AIKeyRules.cleanAddress("http://api.example.com"))
        XCTAssertThrowsError(try AIKeyRules.cleanAddress("随便写的"))
        XCTAssertThrowsError(try AIKeyRules.cleanAddress(""))
    }

    func testMaskedNeverShowsTheWholeKey() {
        let m = AIKeyRules.masked("sk-demo-000")
        XCTAssertFalse(m.contains("sk-demo"))
        XCTAssertTrue(m.hasPrefix("••••"))
        XCTAssertEqual(AIKeyRules.masked("12345678"), "••••••••", "刚好 8 位的一位都不露")
    }

    func testMemoryStore() throws {
        let s = MemorySecretStore()
        XCTAssertFalse(s.has("anthropic"))
        try s.save("sk-demo-000", for: "anthropic")
        XCTAssertTrue(s.has("anthropic"))
        try s.delete("anthropic")
        XCTAssertFalse(s.has("anthropic"))
    }
}
