import XCTest
@testable import FinanceCore

/// 搬进 app 的 iCloud 容器：只复制、旧文件留着、容器里已有就不动。全用临时文件夹和编造数据。
final class ICloudContainerTests: XCTestCase {
    func testMigrateCopiesOnceAndKeepsOld() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("xiaxia-icloud-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("CloudDocs/夏夏账本")
        let container = root.appendingPathComponent("container/Documents")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)

        XCTAssertFalse(LedgerStores.migrateToContainer(container, from: old), "旧位置没有账本就不搬")

        try Data("旧账本".utf8).write(to: old.appendingPathComponent("ledger.sqlite"))
        XCTAssertTrue(LedgerStores.migrateToContainer(container, from: old))
        XCTAssertEqual(try String(contentsOf: container.appendingPathComponent("ledger.sqlite"), encoding: .utf8), "旧账本")
        XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent("ledger.sqlite").path), "旧文件留着当备份")
        XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent("已搬家-请看这里.txt").path))

        // 搬过一次（有说明文件）就不再搬
        try fm.removeItem(at: container.appendingPathComponent("ledger.sqlite"))
        XCTAssertFalse(LedgerStores.migrateToContainer(container, from: old))
    }

    /// iPhone 先开、容器里是空账本：Mac 搬家时把空的挪开换成老账本；容器里已经有流水就不动。
    func testMigrateReplacesEmptyContainerOnly() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("xiaxia-icloud-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("CloudDocs/夏夏账本")
        let container = root.appendingPathComponent("container/Documents")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)

        // 老账本：一笔编造的流水
        var mac = Ledger.fresh
        mac.transactions.append(Transaction(date: LocalDate(year: 2026, month: 1, day: 2), amount: Money(cents: -1234),
                                            description: "编造的咖啡", accountID: mac.accounts.first?.id ?? "cash"))
        try LedgerStores.sqlite(old.appendingPathComponent("ledger.sqlite")).save(mac)
        // 容器里：iPhone 建的空账本
        try LedgerStores.sqlite(container.appendingPathComponent("ledger.sqlite")).save(.fresh)

        XCTAssertTrue(LedgerStores.migrateToContainer(container, from: old))
        XCTAssertEqual(try LedgerStores.sqlite(container.appendingPathComponent("ledger.sqlite")).load().transactions.count, 1)
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: container.path).contains { $0.hasPrefix("ledger.sqlite.空账本-") }, "空的留作备份")

        // 换一个场景：容器里已经有流水，不覆盖
        try fm.removeItem(at: old.appendingPathComponent(LedgerStores.movedMarker))
        var phone = Ledger.fresh
        phone.transactions.append(Transaction(date: LocalDate(year: 2026, month: 2, day: 3), amount: Money(cents: -500),
                                              description: "编造的面包", accountID: phone.accounts.first?.id ?? "cash"))
        phone.transactions.append(Transaction(date: LocalDate(year: 2026, month: 2, day: 4), amount: Money(cents: -700),
                                              description: "编造的牛奶", accountID: phone.accounts.first?.id ?? "cash"))
        try LedgerStores.sqlite(container.appendingPathComponent("ledger.sqlite")).save(phone)
        XCTAssertFalse(LedgerStores.migrateToContainer(container, from: old))
        XCTAssertEqual(try LedgerStores.sqlite(container.appendingPathComponent("ledger.sqlite")).load().transactions.count, 2)
    }

    func testContainerPathOnDisk() {
        XCTAssertTrue(LedgerStores.containerDocumentsOnDisk.path.hasSuffix("Library/Mobile Documents/iCloud~com~srmming~xiaxia-ledger/Documents"))
    }

    /// 测试进程没签 iCloud 权限：不能去用容器（不然会把账本搬进一个不同步的文件夹）。
    func testUnsignedProcessHasNoICloudEntitlement() {
        #if os(macOS)
        XCTAssertFalse(LedgerStores.hasICloudEntitlement)
        #endif
    }
}
