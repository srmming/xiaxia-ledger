import XCTest

/// iPhone 版「逐条检查」（docs/CHECKLIST.md）：每页每个按钮点一遍、每页截图（示例 / 空账本、浅色 / 深色、大字号），
/// 再把记一笔、改、删、撤销走一遍。只用 -XiaxiaDemo / -XiaxiaEmpty，数据只在内存里，不碰真账本。
///
/// 这一组不挡合并：发现的问题写进报告（checklist-report.txt），不让测试失败，好让一次跑完所有项。
/// 平时的 CI 跳过它（太慢），在 Actions 页手动跑「iphone-check」。
/// 截图和报告写到环境变量 XIAXIA_SHOTS 指的文件夹（xcodebuild 用 TEST_RUNNER_XIAXIA_SHOTS 传进来），没有就挂在测试结果里。
final class PhoneChecklistTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        // 平时的 CI 和本机 xcodebuild test 不跑这一组（一次要几十分钟），只有 iphone-check 流程给了 XIAXIA_SHOTS 才跑。
        try XCTSkipIf(Self.outDir == nil, "逐条检查只在 iphone-check 流程里跑")
    }

    // MARK: - 工具

    private static let outDir: URL? = {
        guard let p = ProcessInfo.processInfo.environment["XIAXIA_SHOTS"], !p.isEmpty else { return nil }
        let url = URL(fileURLWithPath: p)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func note(_ line: String) {
        print("CHECK \(line)")
        guard let dir = Self.outDir else { return }
        let file = dir.appendingPathComponent("checklist-report.txt")
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: file)
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let png = app.screenshot().pngRepresentation
        if let dir = Self.outDir, (try? png.write(to: dir.appendingPathComponent("\(name).png"))) != nil {
            return
        } else {
            let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            a.name = name
            a.lifetime = .keepAlways
            add(a)
        }
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "es_ES"]
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 20)
        return app
    }

    private func find(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// 屏幕上能看到的文字和按钮，拼成一串：点了按钮前后不一样，就算「有反应」。
    private func signature(_ app: XCUIApplication) -> String {
        guard app.state == .runningForeground else { return "<app 不在前台>" }
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(150).map(\.label)
        let buttons = app.buttons.allElementsBoundByIndex.prefix(150).map { "\($0.label)|\($0.isSelected)" }
        let fields = app.textFields.count + app.alerts.count + app.sheets.count + app.switches.count
        return (texts + buttons).joined(separator: "¦") + "#\(fields)"
    }

    private func slug(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>| \n·,，、")
        return String(s.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) }.prefix(28))
    }

    /// 一页的主角区域里能点的按钮（不含底部标签栏）。返回「标签 + 第几个同名」，重开 app 后还能找回同一个。
    private func pageButtons(_ app: XCUIApplication) -> [(label: String, nth: Int)] {
        let tabBar = app.tabBars.firstMatch.frame
        var seen: [String: Int] = [:]
        var out: [(label: String, nth: Int)] = []
        for b in app.buttons.allElementsBoundByIndex {
            guard b.exists else { continue }
            let f = b.frame
            if f.isEmpty || (!tabBar.isEmpty && f.intersects(tabBar)) { continue }
            let label = b.label.isEmpty ? (b.identifier.isEmpty ? "" : "#" + b.identifier) : b.label
            if label.isEmpty { continue }
            let n = seen[label, default: 0]
            seen[label] = n + 1
            out.append((label: label, nth: n))
        }
        return out
    }

    private func element(_ app: XCUIApplication, label: String, nth: Int) -> XCUIElement {
        if label.hasPrefix("#") {
            return app.buttons.matching(identifier: String(label.dropFirst())).element(boundBy: nth)
        }
        return app.buttons.matching(NSPredicate(format: "label == %@", label)).element(boundBy: nth)
    }

    /// 打开一个标签；plans 的 sub 是计划页里第几格（0 目标 1 订阅 2 欠款 3 报销），spending 的 sub=1 是趋势。
    private func open(_ app: XCUIApplication, tab: String, sub: Int?) {
        let t = app.tabBars.buttons[tab]
        if t.waitForExistence(timeout: 10) { t.tap() }
        guard let sub else { return }
        // 每个标签各有一排分格（收支：花在哪 / 趋势；计划：目标 / 订阅 / 欠款 / 报销），按里面的字认，别点到别的标签留着的那排。
        let seg = tab == "计划" ? app.segmentedControls["plansTab"]
            : app.segmentedControls.containing(.button, identifier: "趋势").firstMatch
        if seg.waitForExistence(timeout: 5), sub < seg.buttons.count { seg.buttons.element(boundBy: sub).tap() }
    }

    // MARK: - 3.1 / 4.1 / 5.4 / 5.5：每页截图

    private let pages: [(name: String, tab: String, sub: Int?)] = [
        ("overview", "总览", nil), ("spending", "收支", 0), ("trends", "收支", 1), ("wealth", "家底", nil),
        ("goals", "计划", 0), ("subs", "计划", 1), ("debts", "计划", 2), ("reimburse", "计划", 3), ("xiaxia", "夏夏", nil),
    ]

    private func walkPages(_ prefix: String, _ args: [String]) {
        let app = launch(args)
        for p in pages {
            open(app, tab: p.tab, sub: p.sub)
            sleep(1)
            shot(app, "\(prefix)-\(p.name)-1")
            // 往下滑几屏，看下面有没有挤坏、截断。
            var last = signature(app)
            for i in 2...4 {
                app.swipeUp()
                let now = signature(app)
                if now == last { break }
                shot(app, "\(prefix)-\(p.name)-\(i)")
                last = now
            }
            // 回到顶上，免得下一页开在中间。
            app.tabBars.buttons[p.tab].tap()
        }
        // 设置和它的每个二级页。
        for pane in ["", "books", "sync", "xiaxia", "memory", "privacy", "author", "data"] {
            let a = launch(args + ["-XiaxiaSection", "settings"] + (pane.isEmpty ? [] : ["-XiaxiaSettingsPage", pane]))
            sleep(2)
            shot(a, "\(prefix)-settings\(pane.isEmpty ? "" : "-" + pane)")
            a.terminate()
        }
        // 记一笔、管理页、新目标
        for sheet in ["add", "books", "accounts", "categories", "plan", "newInstallment", "newDebt", "memory"] {
            let a = launch(args + ["-XiaxiaSheet", sheet])
            sleep(2)
            shot(a, "\(prefix)-sheet-\(sheet)")
            a.terminate()
        }
    }

    func test01PagesDemoLight() { walkPages("demo-light", ["-XiaxiaDemo", "-xiaxia.appearance", "light"]) }
    func test02PagesDemoDark() { walkPages("demo-dark", ["-XiaxiaDemo", "-xiaxia.appearance", "dark"]) }
    func test03PagesEmpty() { walkPages("empty-light", ["-XiaxiaEmpty", "-xiaxia.appearance", "light"]) }
    func test04PagesLargeText() {
        walkPages("demo-bigtext", ["-XiaxiaDemo", "-xiaxia.appearance", "light",
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
    }

    // MARK: - 3.2：每页每个按钮点了都有反应

    private func pressEveryButton(_ args: [String], tag: String) {
        var navDone = Set<String>()   // 顶栏的按钮（账本、问 AI、记一笔、设置）每页都一样，只点一次
        for p in pages {
            var app = launch(args)
            open(app, tab: p.tab, sub: p.sub)
            sleep(1)
            let nav = app.navigationBars.firstMatch.frame
            let list = pageButtons(app).filter { b in
                let f = element(app, label: b.label, nth: b.nth).frame
                guard !nav.isEmpty, f.intersects(nav) else { return true }
                return navDone.insert(b.label).inserted
            }
            note("[\(tag)] \(p.name)：\(list.count) 个按钮：\(list.map(\.label).joined(separator: " / "))")
            var fresh = true
            for (label, nth) in list {
                if !fresh {
                    app.terminate()
                    app = launch(args)
                    open(app, tab: p.tab, sub: p.sub)
                    sleep(1)
                }
                let target = element(app, label: label, nth: nth)
                var tries = 0
                while target.exists && !target.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
                guard target.exists, target.isHittable else {
                    note("没点到 [\(tag)] \(p.name) ·「\(label)」#\(nth)（找不到或被挡住）")
                    fresh = false; continue
                }
                let before = signature(app)
                target.tap()
                sleep(1)
                let after = signature(app)
                let name = "btn-\(tag)-\(p.name)-\(slug(label))-\(nth)"
                if before == after {
                    note("没反应 [\(tag)] \(p.name) ·「\(label)」#\(nth)")
                    shot(app, name + "-没反应")
                    fresh = tries == 0   // 没滑过、没变化：不用重开，接着点下一个
                } else {
                    note("有反应 [\(tag)] \(p.name) ·「\(label)」#\(nth)")
                    shot(app, name)
                    fresh = false
                }
            }
            app.terminate()
        }
    }

    func test10ButtonsDemo() { pressEveryButton(["-XiaxiaDemo"], tag: "demo") }
    func test11ButtonsEmpty() { pressEveryButton(["-XiaxiaEmpty"], tag: "empty") }

    // MARK: - 1.x：记一笔 → 撤销；删一笔 → 改动记录里撤销

    func test20AddThenUndo() {
        let app = launch(["-XiaxiaDemo", "-XiaxiaSheet", "add"])
        let k = app.buttons["key-7"]
        guard k.waitForExistence(timeout: 15) else { note("没通过 1.17 记一笔没打开"); return }
        for key in ["7", "7", ",", "7"] { app.buttons["key-\(key)"].tap() }
        let name = app.textFields["名称"]
        if name.waitForExistence(timeout: 3) { name.tap(); name.typeText("检查用一笔") }
        let pick = ["超市", "餐饮", "交通", "购物"].map { button(app, $0) }.first { $0.exists && $0.isHittable }
        pick?.tap()
        shot(app, "flow-add-filled")
        let save = app.buttons["记下"]
        guard save.isEnabled else { note("没通过 1.17 填好了「记下」还是灰的"); shot(app, "flow-add-disabled"); return }
        save.tap()
        let toast = find(app, "记下")
        let undo = app.buttons["撤销"]
        shot(app, "flow-add-toast")
        if undo.waitForExistence(timeout: 4) && undo.isHittable {
            undo.tap()
            note("通过 1.13 记一笔后底部提示有「撤销」，点得到")
        } else if toast.exists {
            // 提示是一整块（accessibilityElement combine），按钮不单独露出来：点提示右边。
            let r = toast.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
            r.tap()
            note("留意 1.13 底部提示里的「撤销」不是单独的按钮（VoiceOver 读不出来、自动检查点不到），改点提示右边")
        } else {
            note("没通过 1.13 记下后底部没有提示")
        }
        sleep(2)
        shot(app, "flow-add-undone")
        // 去流水里找刚才那笔，应该没有了。
        open(app, tab: "总览", sub: nil)
        let all = button(app, "全部")
        for _ in 0..<5 where all.exists && !all.isHittable { app.swipeUp() }
        if all.exists { all.tap() }
        sleep(1)
        if find(app, "检查用一笔").exists {
            note("没通过 1.13 撤销后「检查用一笔」还在流水里"); shot(app, "flow-add-undo-failed")
        } else {
            note("通过 1.13 撤销后流水里没有「检查用一笔」")
        }
    }

    func test21DeleteThenUndoInChanges() {
        let app = launch(["-XiaxiaDemo"])
        let all = button(app, "全部")
        guard all.waitForExistence(timeout: 10) else { note("没通过 总览没有去流水的「全部」"); return }
        for _ in 0..<5 where !all.isHittable { app.swipeUp() }
        all.tap()
        let row = app.collectionViews.cells.element(boundBy: 2)
        guard row.waitForExistence(timeout: 10) else { note("没通过 流水页没有内容"); return }
        let rowLabel = row.label
        row.tap()
        let del = app.buttons["删除"].firstMatch
        for _ in 0..<4 where del.exists && !del.isHittable { app.swipeUp() }
        guard del.waitForExistence(timeout: 5) else { note("没通过 1.12 iPhone 详情里没有「删除」"); shot(app, "flow-del-nobutton"); return }
        del.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "删除")).element(boundBy: 1)
        let sheetConfirm = app.sheets.buttons["删除"].exists ? app.sheets.buttons["删除"] : confirm
        shot(app, "flow-del-confirm")
        guard sheetConfirm.waitForExistence(timeout: 5) else { note("没通过 1.12 删除没有二次确认"); return }
        sheetConfirm.tap()
        sleep(2)
        shot(app, "flow-del-done")
        note("通过 1.12 iPhone 详情能删一笔（\(rowLabel)）")
        // 改动记录：夏夏标签 → 改动记录
        open(app, tab: "夏夏", sub: nil)
        let changes = button(app, "改动记录")
        for _ in 0..<6 where changes.exists && !changes.isHittable { app.swipeUp() }
        guard changes.exists else { note("没通过 iPhone 上找不到「改动记录」入口"); shot(app, "flow-del-nochanges"); return }
        changes.tap()
        sleep(1)
        shot(app, "flow-changes")
        let undo = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "撤销")).firstMatch
        guard undo.waitForExistence(timeout: 5) else { note("没通过 改动记录里没有「撤销」"); return }
        undo.tap()
        sleep(1)
        shot(app, "flow-changes-undone")
        note(find(app, "已撤销").exists ? "通过 1.13 改动记录里撤销删除" : "留意 1.13 改动记录点了撤销，没看到「已撤销」")
    }

    // MARK: - 5.3：小屏（这组在哪台模拟器上跑就截哪台；CI 另用 iPhone SE 跑一遍 test01）

    func test30DeviceInfo() {
        let app = launch(["-XiaxiaDemo"])
        note("设备：\(app.windows.firstMatch.frame.size)")
    }
}
