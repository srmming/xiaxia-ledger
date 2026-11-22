import FinanceCore
import Foundation
import XCTest

/// app 和外面的 AI 之间递的纸条：现在在看什么、让 app 跳到哪。
final class AppBridgeTests: XCTestCase {
    override func setUp() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        setenv("XIAXIA_BRIDGE_DIR", dir.path, 1)
    }
    override func tearDown() { unsetenv("XIAXIA_BRIDGE_DIR") }

    func testViewRoundTripAndDescribe() {
        XCTAssertNil(AppBridge.readView())
        let id = UUID()
        let sel = AppBridge.SelectedTransaction(id: id, date: "2026-11-03", amount: "-12,50 €", description: "超市",
                                                category: "超市", account: "银行卡", book: "个人")
        AppBridge.writeView(AppBridge.View(page: "流水", month: "2026-11", bookID: nil, bookName: "全部账本", selected: sel))
        let v = AppBridge.readView()
        XCTAssertEqual(v?.selected?.id, id)
        let text = v?.describe() ?? ""
        XCTAssertTrue(text.contains("「流水」页"))
        XCTAssertTrue(text.contains("超市 -12,50 €"))
        XCTAssertFalse(text.contains("分钟前"))
        let old = AppBridge.View(page: "总览", month: nil, bookID: nil, bookName: "全部账本", selected: nil,
                                 updatedAt: Date().addingTimeInterval(-3600))
        XCTAssertTrue(old.describe().contains("60 分钟前"))
    }

    func testOpenRequestIsTakenOnceAndExpires() throws {
        XCTAssertFalse(AppBridge.hasOpenRequest)
        try AppBridge.requestOpen(.init(page: "花销", month: "2026-10", author: "Claude"))
        XCTAssertTrue(AppBridge.hasOpenRequest)
        XCTAssertEqual(AppBridge.takeOpenRequest()?.month, "2026-10")
        XCTAssertNil(AppBridge.takeOpenRequest())
        try AppBridge.requestOpen(.init(page: "花销", author: "Claude", createdAt: Date().addingTimeInterval(-3600)))
        XCTAssertNil(AppBridge.takeOpenRequest(), "一小时前的纸条不该再跳")
        XCTAssertFalse(AppBridge.hasOpenRequest)
    }

    func testPageNames() {
        XCTAssertEqual(AppBridge.pageName("spending"), "花销")
        XCTAssertEqual(AppBridge.pageName("总览"), "总览")
        XCTAssertNil(AppBridge.pageName("nopage"))
    }
}
