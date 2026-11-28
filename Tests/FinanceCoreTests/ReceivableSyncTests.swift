import XCTest
@testable import FinanceCore

/// Mac 删掉的客人欠款，不能被手机上的旧纸条带回来（2026-11-28 Mac 线程请手机查）。
final class ReceivableSyncTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 28)

    private func base() throws -> (Ledger, UUID) {
        var l = DemoData.make(endingOn: today)
        let r = Receivable(name: "测试客人", amount: Money(cents: 50_00))
        l.receivables.append(r)
        return (l, r.id)
    }

    /// 手机改了别的（没碰这条）：Mac 删掉的不回来。
    func testPhoneUnrelatedEditDoesNotBringBack() throws {
        let (b, id) = try base()
        var phone = b, mac = b
        var t = phone.transactions[0]; t.description = "手机改的"
        try phone.editTransaction(t, author: "手机")
        let note = try XCTUnwrap(phone.syncNote(since: b, device: "iPhone"))
        XCTAssertNil(note.receivables)
        _ = try mac.removeReceivable(id, author: "Mac")
        mac.apply(note)
        XCTAssertFalse(mac.receivables.contains { $0.id == id })
    }

    /// 手机写纸条时还没看到 Mac 的删除，纸条晚到、反复收：都不回来。
    func testLateDuplicateNoteDoesNotBringBack() throws {
        let (b, id) = try base()
        var phone = b, mac = b
        var t = phone.transactions[0]; t.description = "手机改的"
        try phone.editTransaction(t, author: "手机")
        let note = try XCTUnwrap(phone.syncNote(since: b, device: "iPhone"))
        _ = try mac.removeReceivable(id, author: "Mac")
        mac.apply(note); mac.apply(note)
        XCTAssertFalse(mac.receivables.contains { $0.id == id })
    }
}

/// 手机上的改动要真的传到 Mac（0829a78 以后）：客人欠款、管哪边。
final class PhoneToMacSyncTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 28)

    func testPhoneReceivableEditReachesMac() throws {
        var b = DemoData.make(endingOn: today)
        b.receivables.append(Receivable(name: "测试客人", amount: Money(cents: 50_00)))
        var phone = b, mac = b
        let i = phone.receivables.count - 1
        phone.receivables[i].amount = Money(cents: 80_00)
        let note = try XCTUnwrap(phone.syncNote(since: b, device: "iPhone"))
        XCTAssertNotNil(note.receivables)
        mac.apply(note)
        XCTAssertEqual(mac.receivables.last?.amount, Money(cents: 80_00))
    }

    func testPhoneManagedSidesReachesMac() throws {
        let b = DemoData.make(endingOn: today)
        var phone = b, mac = b
        try phone.setManagedSides(.life, author: "手机")
        let note = try XCTUnwrap(phone.syncNote(since: b, device: "iPhone"))
        mac.apply(note)
        XCTAssertEqual(mac.managedSides, .life)
    }

    /// Mac 同时改了生意的别的设置：按字段合并，两边的都留下。
    func testManagedSidesMergesWithMacBusinessEdit() throws {
        let b = DemoData.make(endingOn: today)
        var phone = b, mac = b
        try phone.setManagedSides(.life, author: "手机")
        let note = try XCTUnwrap(phone.syncNote(since: b, device: "iPhone"))
        var s = try XCTUnwrap(mac.business)
        let rest = LocalDate(year: 2026, month: 11, day: 29)
        s.restDays = (s.restDays ?? []) + [rest]
        mac.business = s
        mac.apply(note)
        XCTAssertEqual(mac.managedSides, .life)
        XCTAssertTrue(mac.business?.restDays?.contains(rest) == true)
    }
}
