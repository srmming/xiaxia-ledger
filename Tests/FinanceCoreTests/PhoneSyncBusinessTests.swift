import XCTest
@testable import FinanceCore

/// 手机改 → 写成纸条 → Mac 收：生意设置（管哪边、货值、本钱…）、客人欠款、分类图标、「这家店算哪一类」都要传得到。只用示例账本。
final class PhoneSyncBusinessTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 18)
    private var base: Ledger { DemoData.make(endingOn: today) }

    /// 手机上从 `mac` 那份改成 `phone`，写纸条，Mac 收下。返回 Mac 收完的样子和那张纸条。
    private func deliver(_ phone: Ledger, since start: Ledger, to mac: Ledger) throws -> (Ledger, SyncNote) {
        let note = try XCTUnwrap(phone.syncNote(since: start, device: "iPhone"))
        // 纸条要能存成文件再读回来
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let read = try dec.decode(SyncNote.self, from: enc.encode(note))
        var out = mac
        XCTAssertTrue(out.apply(read))
        return (out, read)
    }

    func testManagedSidesTravelFromPhoneToMac() throws {
        let start = base
        var phone = start
        try phone.setManagedSides(.life, author: "小晴")
        let (mac, note) = try deliver(phone, since: start, to: start)
        XCTAssertEqual(note.changedBusiness, true); XCTAssertNotNil(note.originalRows?["meta"]?["business"])
        XCTAssertEqual(mac.managedSides, .life)
        XCTAssertEqual(mac.business, phone.business)
        XCTAssertEqual(mac.changes.last?.author, "小晴")
        XCTAssertFalse(mac.changes.contains { $0.syncConflicts?.isEmpty == false }, "没有冲突")
    }

    func testStockCapitalAndRestDaysTravel() throws {
        let start = base
        var phone = start
        try phone.addStockEstimate(Money(cents: 640_00), date: today, author: "小晴")
        try phone.setShopRest(today, rest: true, author: "小晴")
        let (mac, _) = try deliver(phone, since: start, to: start)
        XCTAssertEqual(mac.business?.stockEstimates, phone.business?.stockEstimates)
        XCTAssertEqual(mac.business?.restDays, phone.business?.restDays)
        XCTAssertEqual(mac.business, phone.business)
    }

    func testPhoneAndMacChangeDifferentBusinessFieldsBothKept() throws {
        let start = base
        var phone = start, mac = start
        try phone.setManagedSides(.biz, author: "小晴")
        try mac.addStockEstimate(Money(cents: 500_00), date: today, author: "小满")
        let (out, _) = try deliver(phone, since: start, to: mac)
        XCTAssertEqual(out.managedSides, .biz, "手机改的管哪边收下了")
        XCTAssertEqual(out.business?.stockEstimates?.count, 1, "电脑上估的货值还在")
        XCTAssertFalse(out.changes.contains { $0.syncConflicts?.isEmpty == false })
    }

    func testSameBusinessFieldChangedOnBothKeepsMacAndRecordsConflict() throws {
        let start = base
        var phone = start, mac = start
        try phone.setManagedSides(.biz, author: "小晴")
        try mac.setManagedSides(.life, author: "小满")
        let (out, _) = try deliver(phone, since: start, to: mac)
        XCTAssertEqual(out.managedSides, .life, "同一项两边都改了：留电脑的")
        XCTAssertTrue(out.changes.contains { $0.syncConflicts?.contains { $0.rowID == "business" } == true }, "留一条冲突给人核对")
    }

    func testPhoneTurnsBusinessOnForTheFirstTime() throws {
        let start = Ledger.fresh
        var phone = start
        try phone.setManagedSides(.both, author: "小晴")
        let (mac, note) = try deliver(phone, since: start, to: start)
        XCTAssertNil(note.originalRows?["meta"]?["business"])
        XCTAssertEqual(mac.business, phone.business)
        XCTAssertEqual(mac.books.map(\.id), phone.books.map(\.id), "新开的生意账本也到了")
        XCTAssertEqual(mac.managedSides, .both)
        XCTAssertGreaterThanOrEqual(mac.minReaderVersion, 2)
    }

    func testCustomerDebtsTravelAndDeleteTravels() throws {
        var start = base
        let old = Receivable(name: "阿云", amount: Money(cents: 45_00))
        start.receivables = [old]
        // 改一条
        var phone = start
        phone.receivables[0].amount = Money(cents: 30_00)
        let (mac, note) = try deliver(phone, since: start, to: start)
        XCTAssertEqual(note.receivables?.count, 1)
        XCTAssertEqual(mac.receivables, phone.receivables)
        // 加一条
        var phone2 = mac
        phone2.receivables.append(Receivable(name: "小岚", amount: Money(cents: 12_00)))
        let (mac2, _) = try deliver(phone2, since: mac, to: mac)
        XCTAssertEqual(mac2.receivables.count, 2)
        // 删一条（带作者、能撤销的那种）
        var phone3 = mac2
        let c = try phone3.removeReceivable(old.id, author: "小晴")
        let (mac3, note3) = try deliver(phone3, since: mac2, to: mac2)
        XCTAssertEqual(note3.deletes?["receivables"], [old.id.uuidString])
        XCTAssertEqual(mac3.receivables.map(\.name), ["小岚"])
        // Mac 上撤销：那条回来
        var undo = mac3
        _ = try undo.undo(changeID: c.id, author: "小满")
        XCTAssertEqual(undo.receivables.count, 2)
    }

    func testCategoryIconAndPlaceAnswerTravel() throws {
        let start = base
        var phone = start
        try phone.setCategoryEmoji("超市", emoji: "🧺", author: "小晴")
        try phone.setPlaceCategory("Super Lumi", category: "超市", author: "小晴")
        try phone.skipPlaceQuestion("Cafe Brisa", author: "小晴")
        let (mac, note) = try deliver(phone, since: start, to: start)
        XCTAssertNotNil(note.profile)
        XCTAssertEqual(mac.categoryEmojis["超市"], "🧺")
        XCTAssertEqual(mac.placeCategory(for: "SUPER LUMI 0042"), "超市")
        XCTAssertEqual(mac.profile, phone.profile)
    }

    /// 整本账往返：手机上把能改的都改一遍，Mac 收完和手机上看到的一样（除了「收过哪些纸条」这种各记各的）。
    func testFullRoundTripMatches() throws {
        var start = base
        start.receivables = [Receivable(name: "阿云", amount: Money(cents: 45_00))]
        var phone = start
        try phone.setManagedSides(.life, author: "小晴")
        try phone.addStockEstimate(Money(cents: 640_00), date: today, author: "小晴")
        try phone.setCategoryEmoji("餐饮", emoji: "🍜", author: "小晴")
        phone.receivables[0].amount = Money(cents: 20_00)
        try phone.addCategory("养花", income: false, author: "小晴")
        let (mac, note) = try deliver(phone, since: start, to: start)
        var a = mac, b = phone
        a.appliedNotes = []; b.appliedNotes = []
        XCTAssertEqual(a.business, b.business); XCTAssertEqual(a.receivables, b.receivables); XCTAssertEqual(a.profile, b.profile)
        XCTAssertEqual(a.changes.map(\.id), b.changes.map(\.id))
        XCTAssertEqual(a.transactions, b.transactions); XCTAssertEqual(a.accounts, b.accounts); XCTAssertEqual(a.books, b.books)
        // 同一张纸条再来一次：不收两遍
        var again = mac
        XCTAssertFalse(again.apply(note))
        XCTAssertEqual(again, mac)
    }

    // MARK: 自己加的分类：一个一个合并

    func testPhoneIconAndMacNewCategoryBothKept() throws {
        var start = base
        try start.addCategory("养花", income: false, author: "小满")
        start.profile.memoryTidiedAt = Date(timeIntervalSince1970: 1_795_000_000)   // 设置里带日期的也要读得回原值
        var phone = start, mac = start
        try phone.setCategoryEmoji("养花", emoji: "🪴", author: "小晴")       // 手机改 A 的图标
        try mac.addCategory("宠物零食", income: false, author: "小满")          // Mac 加了 B
        let (out, _) = try deliver(phone, since: start, to: mac)
        XCTAssertEqual(out.categoryEmojis["养花"], "🪴")
        XCTAssertTrue(out.profile.categories.contains { $0.name == "宠物零食" })
        XCTAssertFalse(out.changes.contains { $0.syncConflicts?.isEmpty == false }, "不算冲突")
    }

    func testPhoneAddsAndRemovesWhileMacChangesAnother() throws {
        var start = base
        try start.addCategory("养花", income: false, author: "小满")
        try start.addCategory("夜宵", income: false, author: "小满")
        var phone = start, mac = start
        try phone.addCategory("学琴", income: false, author: "小晴")            // 手机加一个
        try phone.removeCategory("夜宵", moveTo: nil, author: "小晴")            // 手机删一个
        try mac.setCategoryEmoji("养花", emoji: "🌷", author: "小满")           // Mac 改另一个
        try mac.setPlaceCategory("Super Lumi", category: "超市", author: "小满") // Mac 还改了别的设置
        let (out, _) = try deliver(phone, since: start, to: mac)
        let names = Set(out.profile.categories.map(\.name))
        XCTAssertTrue(names.contains("学琴")); XCTAssertFalse(names.contains("夜宵")); XCTAssertTrue(names.contains("养花"))
        XCTAssertEqual(out.categoryEmojis["养花"], "🌷")
        XCTAssertEqual(out.placeCategory(for: "Super Lumi"), "超市", "电脑上别的设置没被盖掉")
        XCTAssertFalse(out.changes.contains { $0.syncConflicts?.isEmpty == false })
    }

    func testSameCategoryChangedOnBothKeepsMacAndRecordsConflict() throws {
        var start = base
        try start.addCategory("养花", income: false, author: "小满")
        var phone = start, mac = start
        try phone.setCategoryEmoji("养花", emoji: "🪴", author: "小晴")
        try phone.addCategory("学琴", income: false, author: "小晴")
        try mac.setCategoryEmoji("养花", emoji: "🌷", author: "小满")
        let (out, _) = try deliver(phone, since: start, to: mac)
        XCTAssertEqual(out.categoryEmojis["养花"], "🌷", "同一个分类两边都改了：留电脑的")
        XCTAssertTrue(out.profile.categories.contains { $0.name == "学琴" }, "手机另外加的那个照收")
        let conflict = out.changes.compactMap(\.syncConflicts).flatMap { $0 }.first { $0.rowID == "profile" }
        XCTAssertEqual(conflict?.fields, ["分类「养花」"])
    }

    func testMergeCategoriesRules() {
        let a = CustomCategory(name: "A", income: false), b = CustomCategory(name: "B", income: false)
        var a2 = a; a2.emoji = "🅰️"
        var a3 = a; a3.emoji = "🔤"
        // 两边改成一样的：不算冲突
        XCTAssertEqual(Ledger.mergeCategories(base: [a], proposed: [a2], current: [a2]).conflicts, [])
        // 手机改、电脑删了
        XCTAssertEqual(Ledger.mergeCategories(base: [a], proposed: [a2], current: []).conflicts, ["A"])
        // 手机删、电脑改了：留着电脑的
        let r = Ledger.mergeCategories(base: [a, b], proposed: [b], current: [a3, b])
        XCTAssertEqual(r.rows, [a3, b]); XCTAssertEqual(r.conflicts, ["A"])
        // 手机没动：电脑的原样
        XCTAssertEqual(Ledger.mergeCategories(base: [a], proposed: [a], current: [a3, b]).rows, [a3, b])
    }
}
