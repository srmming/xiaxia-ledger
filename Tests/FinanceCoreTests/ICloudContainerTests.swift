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

        // 容器里已经有（比如 iPhone 记过），再也不覆盖
        try Data("容器里新记的".utf8).write(to: container.appendingPathComponent("ledger.sqlite"))
        XCTAssertFalse(LedgerStores.migrateToContainer(container, from: old))
        XCTAssertEqual(try String(contentsOf: container.appendingPathComponent("ledger.sqlite"), encoding: .utf8), "容器里新记的")
    }

    func testContainerPathOnDisk() {
        XCTAssertTrue(LedgerStores.containerDocumentsOnDisk.path.hasSuffix("Library/Mobile Documents/iCloud~com~srmming~xiaxia-ledger/Documents"))
    }
}
