import XCTest

/// 一个新用户从零开始会做的事，在 iPhone 模拟器上真的点一遍。
/// 都用 -XiaxiaEmpty（空账本）或 -XiaxiaDemo（编造的示例账本），数据只在内存里，不碰任何真账本。
final class ManageFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ args: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "es_ES"]
        app.launch()
        return app
    }

    /// 标签以这段文字开头的元素（列表行里的文字常被系统并进按钮的标签；底部提示「加账户「…」」不算）。
    private func find(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    private func typeInAlert(_ app: XCUIApplication, _ text: String, clear: Int = 0) {
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "弹框里没有输入框")
        field.tap()
        if clear > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: clear)) }
        field.typeText(text)
    }

    /// 账本：新建 → 改名 → 删除（空账本直接删）。
    func testBookAddRenameDelete() {
        let app = launch("-XiaxiaEmpty", "-XiaxiaSheet", "books")
        let field = app.textFields["名字，比如「家庭」「第二家店」"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "管理账本页没打开")
        field.tap()
        field.typeText("家庭")
        app.buttons["新建"].tap()
        XCTAssertTrue(app.staticTexts["家庭"].waitForExistence(timeout: 5), "新建的账本没出现")

        app.buttons["家庭 的操作"].tap()
        app.buttons["改名…"].tap()
        typeInAlert(app, "一家人", clear: 4)
        app.alerts.buttons["改名"].tap()
        XCTAssertTrue(app.staticTexts["一家人"].waitForExistence(timeout: 5), "改名没生效")

        app.buttons["一家人 的操作"].tap()
        app.buttons["删除…"].tap()
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "删除确认没出来")
        delete.tap()
        XCTAssertTrue(app.staticTexts["一家人"].waitForNonExistence(timeout: 5), "账本没删掉")
        XCTAssertTrue(app.staticTexts["个人"].exists, "原来的账本不见了")
    }

    /// 里面有流水的账本：要先选挪到哪，再删。
    func testDeleteBookWithContentMovesItFirst() {
        let app = launch("-XiaxiaDemo", "-XiaxiaSheet", "books")
        let menu = app.buttons["我的小店 的操作"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "示例账本里没有「我的小店」")
        menu.tap()
        app.buttons["删除…"].tap()
        let move = app.buttons["挪过去并删除"]
        XCTAssertTrue(move.waitForExistence(timeout: 5), "有流水的账本没要求先挪")
        move.tap()
        XCTAssertTrue(app.staticTexts["我的小店"].waitForNonExistence(timeout: 5), "账本没删掉")
    }

    /// 账本菜单里能找到「管理账本…」。
    func testBookMenuHasManageEntry() {
        let app = launch("-XiaxiaDemo")
        let menu = app.buttons["账本：全部"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "顶部没有账本菜单")
        menu.tap()
        app.buttons["管理账本…"].tap()
        XCTAssertTrue(app.textFields["名字，比如「家庭」「第二家店」"].waitForExistence(timeout: 5), "管理账本页没打开")
    }

    /// 账户：加一个，再改名。
    func testAccountAddAndRename() {
        let app = launch("-XiaxiaEmpty", "-XiaxiaSheet", "accounts")
        let add = app.buttons["加一个账户"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), "管理账户页没打开")
        add.tap()
        let name = app.textFields["名字"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("银行卡")
        app.buttons["保存"].tap()
        let row = find(app, "银行卡")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "加的账户没出现")
        row.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("2")
        app.buttons["保存"].tap()
        XCTAssertTrue(find(app, "银行卡2").waitForExistence(timeout: 5), "账户改名没生效")
    }

    /// 全新的空账本：记一笔时当场加账户和新分类，能记下。
    func testQuickAddOnEmptyLedger() {
        let app = launch("-XiaxiaEmpty", "-XiaxiaSheet", "add")
        let one = app.buttons["1"]
        XCTAssertTrue(one.waitForExistence(timeout: 15), "记一笔没打开")
        one.tap()
        app.buttons["2"].tap()
        let save = app.buttons["记下"]
        XCTAssertFalse(save.isEnabled, "没选分类和账户就能记")

        app.buttons["新分类"].tap()
        typeInAlert(app, "咖啡")
        app.alerts.buttons["用这个"].tap()

        app.buttons["选账户 ▾"].tap()
        app.buttons["新账户…"].tap()
        typeInAlert(app, "现金")
        app.alerts.buttons["加上"].tap()

        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "填好了还是不能记")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "记下之后面板没关")
    }

    /// 示例账本：5 个标签都能点开，设置里三个管理入口都在。
    func testTabsAndSettingsEntries() {
        let app = launch("-XiaxiaDemo")
        for tab in ["总览", "收支", "家底", "计划", "AI"] {
            let b = app.tabBars.buttons[tab]
            XCTAssertTrue(b.waitForExistence(timeout: 15), "没有「\(tab)」标签")
            b.tap()
            XCTAssertTrue(b.isSelected, "「\(tab)」点了没切过去")
        }
        app.tabBars.buttons["总览"].tap()
        app.buttons["设置"].firstMatch.tap()
        for entry in ["管理账本（新建、改名、删除）", "管理分类"] {
            let e = find(app, entry)
            for _ in 0..<4 where !e.isHittable { app.swipeUp() }
            XCTAssertTrue(e.waitForExistence(timeout: 5), "设置里没有「\(entry)」")
        }
    }
}
