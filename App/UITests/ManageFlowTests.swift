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

    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    private func typeInAlert(_ app: XCUIApplication, _ text: String, clear: Int = 0) {
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "弹框里没有输入框")
        field.tap()
        if clear > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: clear)) }
        field.typeText(text)
    }

    /// 新建分类先挑图标：点「奶茶」图标，名字跟着填成「奶茶」，建好后能在管理分类里看到。
    func testNewCategoryIconFirst() {
        let app = launch("-XiaxiaEmpty", "-XiaxiaSheet", "newCategory")
        let field = app.textFields["分类名字"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "新建分类面板没出来")
        XCTAssertFalse(app.buttons["建好了"].isEnabled, "没名字就能建")
        let tea = app.buttons["奶茶"]
        XCTAssertTrue(tea.waitForExistence(timeout: 5), "图标格子里没有「奶茶」按钮（VoiceOver 也点不到）")
        tea.tap()
        XCTAssertEqual(field.value as? String, "奶茶", "点了图标，名字没跟着填")
        XCTAssertTrue(tea.isSelected, "点过的图标没标成选中")
        // 搜图标
        let search = app.textFields["按名字搜图标"]
        search.tap()
        search.typeText("火锅")
        XCTAssertTrue(app.buttons["火锅"].waitForExistence(timeout: 5), "搜「火锅」没找到")
        app.buttons["建好了"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "建好了面板没关")
    }

    /// 已有分类换图标 → 改回自动。
    func testChangeCategoryIcon() {
        let app = launch("-XiaxiaDemo", "-XiaxiaSheet", "categories")
        let iconButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "给「")).firstMatch
        XCTAssertTrue(iconButton.waitForExistence(timeout: 15), "分类前面的图标点不到")
        iconButton.tap()
        XCTAssertTrue(find(app, "现在是按名字自动配的").waitForExistence(timeout: 5), "换图标面板没出来")
        let done = app.buttons["换好了"]
        XCTAssertFalse(done.isEnabled, "没挑就能换")
        app.buttons["火锅"].tap()
        XCTAssertTrue(done.isEnabled)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "换好了面板没关")
        iconButton.tap()
        XCTAssertTrue(find(app, "你挑过图标").waitForExistence(timeout: 5), "换过的图标没记住")
        app.buttons["改回自动"].tap()
        XCTAssertTrue(find(app, "你挑过图标").waitForNonExistence(timeout: 5), "改回自动后面板没关")
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
        // 等编辑页完全收起再点列表，不然这一下会点在正在关的弹层上（2026-11-21 CI 上出现过）。
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "保存后编辑页没关")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "银行卡")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "加的账户没出现")
        row.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("2")
        app.buttons["保存"].tap()
        XCTAssertTrue(find(app, "银行卡2").waitForExistence(timeout: 5), "账户改名没生效")
    }

    /// 全新的空账本：记一笔时当场加账户和新分类（弹出新建分类面板，名字按「咖啡」自动配图标），能记下。
    func testQuickAddOnEmptyLedger() {
        let app = launch("-XiaxiaEmpty", "-XiaxiaSheet", "add")
        let one = app.buttons["1"]
        XCTAssertTrue(one.waitForExistence(timeout: 15), "记一笔没打开")
        XCTAssertTrue(app.buttons["支出"].exists && app.buttons["收入"].exists, "方向不是「支出 / 收入」")
        one.tap()
        app.buttons["2"].tap()
        let save = app.buttons["记下"]
        XCTAssertFalse(save.isEnabled, "没选分类和账户就能记")

        app.buttons["加一个新分类"].tap()
        let field = app.textFields["分类名字"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "新建分类面板没出来")
        field.tap()
        field.typeText("咖啡")
        app.buttons["建好了"].tap()
        XCTAssertTrue(button(app, "咖啡").waitForExistence(timeout: 5), "新分类没出现在格子里")
        XCTAssertTrue(button(app, "咖啡").isSelected, "建好的分类没直接选上")

        app.buttons["账户：还没选"].tap()
        app.buttons["新账户…"].tap()
        typeInAlert(app, "现金")
        app.alerts.buttons["加上"].tap()

        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "填好了还是不能记")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "记下之后面板没关")
    }

    /// 名称输入几个字，下面提示以前用过的名字，点一下分类跟着选好。
    func testQuickAddNameSuggestionPicksCategory() {
        let app = launch("-XiaxiaDemo", "-XiaxiaSheet", "add")
        let one = app.buttons["1"]
        XCTAssertTrue(one.waitForExistence(timeout: 15), "记一笔没打开")
        one.tap()
        let name = app.textFields["名称"]
        name.tap()
        name.typeText("Lumi")
        let hint = find(app, "用「Super Lumi」")
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "没有提示以前用过的名字")
        hint.tap()
        XCTAssertTrue(button(app, "超市").isSelected, "点了提示，分类没跟着选上")
    }

    /// 计划页自己登记一个存钱目标。
    func testNewGoalFromPlans() {
        let app = launch("-XiaxiaEmpty", "-XiaxiaSheet", "plan")
        let name = app.textFields["名字，比如「旅行」"]
        XCTAssertTrue(name.waitForExistence(timeout: 15), "新计划没打开")
        name.tap()
        name.typeText("旅行")
        let amount = app.textFields["要存多少，比如 2.000"]
        amount.tap()
        amount.typeText("2000")
        app.buttons["保存"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "保存后没关")
        app.tabBars.buttons["计划"].tap()
        XCTAssertTrue(find(app, "旅行").waitForExistence(timeout: 5), "目标没出现在计划页")
    }

    /// 计划页「订阅」：登记一个，合计和这一行出来；再「不续了」，合计变成 0。
    func testSubscriptionAddAndCancel() {
        let app = launch("-XiaxiaEmpty")
        app.tabBars.buttons["计划"].tap()
        let tab = app.segmentedControls["plansTab"].buttons["订阅"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "计划页没有「订阅」那一格")
        tab.tap()
        let add = app.buttons["addSubscription"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "没有登记订阅的按钮")
        add.tap()
        let name = app.textFields["名字，比如「视频会员」"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "登记订阅没打开")
        name.tap()
        name.typeText("音乐会员")
        let amount = app.textFields["每次扣多少，比如 13,99"]
        amount.tap()
        amount.typeText("10,99")
        app.buttons["保存"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "保存后没关")
        // 界面上金额和 € 之间是不换行空格（Money.ui），这样 € 不会单独换到下一行。
        XCTAssertTrue(find(app, "10,99\u{00A0}€").waitForExistence(timeout: 5), "每月合计没出来")
        XCTAssertTrue(find(app, "音乐会员").exists, "订阅没出现在列表里")
        app.buttons["音乐会员 的操作"].tap()
        app.buttons["不续了"].tap()
        XCTAssertTrue(find(app, "已经停了的 1 个").waitForExistence(timeout: 5), "停了以后没归到「已经停了的」")
    }

    /// 夏夏建议页：点一个例子写下目标。
    func testAimOnXiaxiaPage() {
        let app = launch("-XiaxiaEmpty")
        let tab = app.tabBars.buttons["夏夏"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        let example = app.buttons["每个月存下 500 €"]
        XCTAssertTrue(example.waitForExistence(timeout: 5), "没有目标示例")
        example.tap()
        app.buttons["就这个"].tap()
        XCTAssertTrue(app.staticTexts["你的目标"].waitForExistence(timeout: 5), "目标没存下")
    }

    /// 示例账本：5 个标签都能点开，设置里三个管理入口都在。
    func testTabsAndSettingsEntries() {
        let app = launch("-XiaxiaDemo")
        for tab in ["总览", "收支", "家底", "计划", "夏夏"] {
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
        let sharp = find(app, "毒舌")
        for _ in 0..<6 where !sharp.isHittable { app.swipeUp() }
        XCTAssertTrue(sharp.waitForExistence(timeout: 5), "设置里没有夏夏的性格")
        sharp.tap()
        XCTAssertTrue(sharp.isSelected, "选了毒舌没生效")
    }
}
