import XCTest

/// 自己动手记账：计算器键盘、常记的一键再记、转账、改一笔、多选。
/// 只用 -XiaxiaDemo（编造的示例账本，只在内存里）。
final class ManualEntryTests: XCTestCase {
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

    private func key(_ app: XCUIApplication, _ k: String) -> XCUIElement { app.buttons["key-\(k)"] }

    /// 计算器键盘：12,50 + 3 → 显示「= 15,50 €」；按「=」变成 15,50。键盘最下面一排和「记下」都点得到（不互相挡）。
    func testCalculatorKeypad() {
        let app = launch("-XiaxiaDemo", "-XiaxiaSheet", "add")
        XCTAssertTrue(key(app, "1").waitForExistence(timeout: 15), "记一笔没打开")
        for k in ["1", "2", ",", "5", "+", "3"] { key(app, k).tap() }
        let result = app.staticTexts["amountResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "算式下面没有显示结果")
        XCTAssertTrue(result.label.contains("15,50"), "12,50 + 3 算出来是 \(result.label)")
        // 最下面一排键和按钮都要露在外面能点。
        for k in [",", "0", "C", "="] { XCTAssertTrue(key(app, k).isHittable, "「\(k)」键被挡住了") }
        XCTAssertTrue(app.buttons["记下"].isHittable, "「记下」按钮被挡住了")
        XCTAssertTrue(app.buttons["再记一笔"].isHittable, "「再记一笔」按钮被挡住了")
        key(app, "=").tap()
        XCTAssertFalse(result.exists, "按了等于，算式还在")
        XCTAssertTrue(find(app, "金额 ").label.contains("15"), "按了等于金额不对：\(find(app, "金额 ").label)")
    }

    /// 「常记的」点一下：金额、名称、分类都填好，直接能记下。
    func testFrequentEntryFillsEverything() {
        let app = launch("-XiaxiaDemo", "-XiaxiaSheet", "add")
        let chip = button(app, "再记一笔 交通卡")
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "没有「常记的」交通卡")
        chip.tap()
        XCTAssertTrue(button(app, "交通").isSelected, "分类没跟着选上")
        let save = app.buttons["记下"]
        XCTAssertTrue(save.isEnabled, "点了常记的还是不能记")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "记下之后面板没关")
    }

    /// 「再记一笔」：记下后表单留着、金额清空，能接着记。
    func testSaveAndContinue() {
        let app = launch("-XiaxiaDemo", "-XiaxiaSheet", "add")
        XCTAssertTrue(key(app, "4").waitForExistence(timeout: 15))
        key(app, "4").tap()
        button(app, "超市").tap()
        app.buttons["再记一笔"].tap()
        XCTAssertTrue(find(app, "已记下 1 笔").waitForExistence(timeout: 5), "没提示已记下")
        XCTAssertFalse(app.buttons["记下"].isEnabled, "记下后金额和分类没清空")
    }

    /// 转账：自己两个账户之间挪钱。
    func testTransferBetweenAccounts() {
        let app = launch("-XiaxiaDemo", "-XiaxiaSheet", "add")
        XCTAssertTrue(app.buttons["转账"].waitForExistence(timeout: 15), "没有「转账」")
        app.buttons["转账"].tap()
        key(app, "5").tap(); key(app, "0").tap()
        let to = button(app, "转到：还没选")
        XCTAssertTrue(to.waitForExistence(timeout: 5), "没有「转到」")
        XCTAssertFalse(app.buttons["记下"].isEnabled, "没选转到哪就能记")
        to.tap()
        let target = app.buttons["Revolut"].exists ? app.buttons["Revolut"] : app.collectionViews.buttons.element(boundBy: 1)
        target.tap()
        let save = app.buttons["记下"]
        XCTAssertTrue(save.isEnabled, "选好了还是不能记")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "记下之后面板没关")
    }

    /// 从总览进流水，点一笔 → 改 → 面板是「改这一笔」，保存回到详情；再试「选择」多选。
    func testEditAndMultiSelectOnPhone() {
        let app = launch("-XiaxiaDemo")
        let all = button(app, "全部")
        XCTAssertTrue(all.waitForExistence(timeout: 15), "总览没有去流水的「全部」")
        for _ in 0..<5 where !all.isHittable { app.swipeUp() }
        all.tap()
        let firstRow = app.collectionViews.cells.element(boundBy: 2)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "流水页没有内容")
        firstRow.tap()
        let edit = app.buttons["tx-edit"]
        for _ in 0..<4 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "iPhone 详情里没有「改」")
        edit.tap()
        XCTAssertTrue(app.navigationBars["改这一笔"].waitForExistence(timeout: 5), "没打开「改这一笔」")
        let save = app.buttons["保存"]
        XCTAssertTrue(save.isEnabled, "原样也该能保存")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "保存后面板没关")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let select = app.buttons["select-toggle"]
        XCTAssertTrue(select.waitForExistence(timeout: 5), "流水页没有「选择」")
        select.tap()
        app.collectionViews.cells.element(boundBy: 2).tap()
        app.collectionViews.cells.element(boundBy: 3).tap()
        XCTAssertTrue(find(app, "选了 2 笔").waitForExistence(timeout: 5), "多选没选上")
        app.buttons["一起改…"].tap()
        XCTAssertTrue(button(app, "改分类").waitForExistence(timeout: 5), "一起改面板没出来")
    }
}
