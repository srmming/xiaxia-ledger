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
