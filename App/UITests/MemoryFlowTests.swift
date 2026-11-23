import XCTest

/// 夏夏的记忆：在 iPhone 模拟器上真的点一遍。只用空账本 / 编造的示例账本，数据都在内存里。
final class MemoryFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ args: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "es_ES"]
        app.launch()
        return app
    }

    private func find(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// 空账本：先看到「还没记住什么」，自己记一条，记完就能在那一格里看到。
    func testAddFirstMemoryOnEmptyLedger() {
        let app = launch("-XiaxiaEmpty", "-XiaxiaSheet", "memory")
        XCTAssertTrue(find(app, "夏夏还没记住什么").waitForExistence(timeout: 15), "空的时候没有说明")
        XCTAssertTrue(button(app, "让夏夏先认识我").exists, "空的时候没有「让夏夏先认识我」")
        app.buttons["memory-add"].firstMatch.tap()

        let save = app.buttons["memory-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "记一条的面板没出来")
        XCTAssertFalse(save.isEnabled, "什么都没填就能记")
        let title = app.descendants(matching: .any)["memory-title"]
        title.tap()
        title.typeText("工资")
        let text = app.descendants(matching: .any)["memory-text"]
        text.tap()
        text.typeText("明年一月起涨一点")
        XCTAssertTrue(save.isEnabled, "填好了还不能记")
        save.tap()

        // 「明年」要记成具体的年份。
        let nextYear = Calendar.current.component(.year, from: Date()) + 1
        XCTAssertTrue(find(app, "\(nextYear) 年一月起涨一点").waitForExistence(timeout: 5), "记完没出现在页面上，或者「明年」没换成具体年份")
        XCTAssertTrue(button(app, "记得的事 · 1").exists, "那一格的数字没跟着变")
        XCTAssertFalse(find(app, "夏夏还没记住什么").exists, "记了一条，空状态还在")
    }

    /// 示例账本：三格都有东西；到了该整理的时候有提示条，清掉一条后提示条消失。
    func testTabsAndMonthlyTidyOnDemoLedger() {
        let app = launch("-XiaxiaDemo", "-XiaxiaSheet", "memory")
        XCTAssertTrue(app.buttons["memory-add"].waitForExistence(timeout: 15), "记忆页没出来")
        XCTAssertTrue(find(app, "6 月和 12 月各多发一份双薪").exists, "「记得的事」里没有工资那条")

        button(app, "我的规矩").tap()
        XCTAssertTrue(find(app, "还给姐姐的钱不算花销").waitForExistence(timeout: 5), "「我的规矩」里没有内容")
        button(app, "做事经验").tap()
        XCTAssertTrue(find(app, "信用卡对账单里的").waitForExistence(timeout: 5), "「做事经验」里没有内容")

        let look = app.buttons["memory-tidy"]
        XCTAssertTrue(look.exists, "该整理了，却没有提示条")
        look.tap()
        let clear = app.buttons["清掉「夏天去海边」"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "整理单子上没有半年没动的那条")
        XCTAssertTrue(app.buttons["留着「阿杰借的钱」"].exists, "整理单子上没有到期的那条")
        clear.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 5), "点了清掉还在")
        app.buttons["memory-tidy-done"].tap()
        XCTAssertTrue(look.waitForNonExistence(timeout: 5), "整理过了提示条还在")

        // 搜索：三类一起搜。
        let search = app.textFields["memory-search"]
        search.tap()
        search.typeText("姐姐")
        XCTAssertTrue(find(app, "还给姐姐的钱不算花销").waitForExistence(timeout: 5), "搜「姐姐」没搜到")
    }

    /// 设置里一眼找得到「夏夏的记忆」，点进去就是记忆页（2026-11-23 新设置页：一级列表 → 二级页）。
    func testMemoryEntryInSettings() {
        let app = launch("-XiaxiaDemo")
        let settings = app.buttons["设置"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "没有「设置」")
        settings.tap()
        let row = app.buttons["settings.memory"].firstMatch
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "设置里没有「夏夏的记忆」")
        XCTAssertTrue(row.label.contains("记得"), "「夏夏的记忆」那一行没写记得几件事：\(row.label)")
        row.tap()
        XCTAssertTrue(app.buttons["memory-add"].firstMatch.waitForExistence(timeout: 5), "点进去不是记忆页")
        XCTAssertTrue(button(app, "记得的事").exists, "记忆页没有三格切换")
    }
}
