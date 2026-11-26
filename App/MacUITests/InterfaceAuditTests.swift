import AppKit
import XCTest

/// Mac 界面审查（2026-11-26，照官网审查的做法）：只用 -XiaxiaDemo 示例账本（编造的，只在内存里），不碰真账本。
/// 每一页：截图（深色 / 浅色）、记下每个控件的位置大小、把每个按钮真的点一遍看有没有反应、悬停看有没有变化、
/// 按 Tab 看键盘能走到哪些控件。只记录、不判对错（不会让 CI 变红），结果写成 JSON + PNG，交给审查脚本出报告。
final class InterfaceAuditTests: XCTestCase {
    struct Page { let side: String; let key: String }
    static let lifePages = ["overview", "spending", "trends", "wealth", "plans", "subscriptions", "debts", "reimburse",
                            "insights", "changes", "transactions", "settings"]
    static let shopPages = ["overview", "transactions", "spending", "trends", "wealth", "fixed", "debts", "settings"]
    static let sheets = ["add", "books", "accounts", "categories", "memory", "newCategory", "connectAI", "plan",
                         "newInstallment", "newDebt", "fixedCost", "sideTransfer", "feedback", "daily"]

    lazy var out: URL = {
        let env = ProcessInfo.processInfo.environment["AUDIT_OUT"] ?? (NSTemporaryDirectory() + "xiaxia-ui-audit")
        let url = URL(fileURLWithPath: env)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        print("AUDIT_OUT=\(url.path)")
        return url
    }()

    override func setUp() { continueAfterFailure = true }

    // MARK: 启动

    func launch(_ page: Page?, sheet: String? = nil, dark: Bool = true, shop: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-XiaxiaDemo", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "es_ES",
                    "-AppleInterfaceStyle", dark ? "Dark" : "Light", "-NSQuitAlwaysKeepsWindows", "NO"]
        if let page { args += ["-XiaxiaSection", page.key] }
        if shop || page?.side == "shop" { args += ["-XiaxiaBook", "shop"] }
        if let sheet { args += ["-XiaxiaSheet", sheet] }
        app.launchArguments = args
        app.launch()
        // 第一次启动有时窗口出来得慢（2026-11-26 在 ming 的 Mac 上第一组就找不到窗口）：再激活一次、还没有就重开。
        // 2026-11-26 查到：开发版被强杀过以后，XCTest 启动它只出菜单栏、不出主窗口（app 自带的「窗口」菜单兜底也找不到那一项）；
        // 点一下程序坞图标（= reopen）主窗口就出来了。这是 app 的毛病，记进审查报告；这里先绕开，好接着审。
        if !app.windows.firstMatch.waitForExistence(timeout: 12) {
            let dock = XCUIApplication(bundleIdentifier: "com.apple.dock")
            let icon = dock.icons.matching(NSPredicate(format: "label BEGINSWITH %@", "夏夏账本")).firstMatch
            if icon.exists { icon.click() } else { app.activate() }
            _ = app.windows.firstMatch.waitForExistence(timeout: 15)
        }
        sleep(2)  // 等动画、图表画完
        return app
    }

    // MARK: 控件快照

    struct Control: Codable {
        var type: String, label: String, id: String, value: String
        var x: Double, y: Double, w: Double, h: Double
        var enabled: Bool, selected: Bool
    }

    static let clickable: Set<XCUIElement.ElementType> = [.button, .popUpButton, .menuButton, .checkBox, .radioButton,
                                                          .segmentedControl, .switch, .link, .toolbarButton, .disclosureTriangle,
                                                          .stepper, .incrementArrow, .decrementArrow, .comboBox, .textField,
                                                          .searchField, .slider, .colorWell, .datePicker]

    func flatten(_ s: XCUIElementSnapshot, into list: inout [(XCUIElementSnapshot)]) {
        list.append(s)
        for c in s.children { flatten(c, into: &list) }
    }

    func controls(in el: XCUIElement) -> (controls: [Control], texts: [Control], signature: String) {
        guard let snap = try? el.snapshot() else { return ([], [], "") }
        var all: [XCUIElementSnapshot] = []
        flatten(snap, into: &all)
        var cs: [Control] = [], ts: [Control] = [], sig: [String] = []
        for s in all {
            let c = Control(type: String(describing: s.elementType.rawValue), label: s.label, id: s.identifier,
                            value: (s.value as? CustomStringConvertible)?.description ?? "",
                            x: s.frame.minX, y: s.frame.minY, w: s.frame.width, h: s.frame.height,
                            enabled: s.isEnabled, selected: s.isSelected)
            if Self.clickable.contains(s.elementType) { cs.append(c) }
            if s.elementType == .staticText, !s.label.isEmpty { ts.append(c) }
            if !s.label.isEmpty || !c.value.isEmpty { sig.append("\(s.elementType.rawValue)|\(s.label)|\(c.value)|\(s.isSelected)") }
        }
        return (cs, ts, sig.joined(separator: "\n"))
    }

    // MARK: 截图裁剪（悬停前后比）

    func crop(_ shot: XCUIScreenshot, _ r: CGRect, window: CGRect) -> Data? {
        guard let rep = NSBitmapImageRep(data: shot.pngRepresentation), let cg = rep.cgImage else { return nil }
        let scale = CGFloat(cg.width) / max(window.width, 1)
        let rect = CGRect(x: (r.minX - window.minX) * scale, y: (r.minY - window.minY) * scale, width: r.width * scale, height: r.height * scale).integral
        guard let part = cg.cropping(to: rect), let data = part.dataProvider?.data else { return nil }
        return data as Data
    }

    func save(_ shot: XCUIScreenshot, _ name: String) {
        try? shot.pngRepresentation.write(to: out.appendingPathComponent(name + ".png"))
    }

    func write<T: Encodable>(_ value: T, _ name: String) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(value).write(to: out.appendingPathComponent(name + ".json"))
    }

    // MARK: 每一页

    struct ClickResult: Codable {
        var label: String, type: String, x: Double, y: Double, w: Double, h: Double
        var result: String      // sheet / menu / popover / alert / window / changed / nothing
        var hoverChanged: Bool?
        var after: String       // 点了之后新出现的东西（弹窗标题等）
    }

    struct PageReport: Codable {
        var name: String
        var window: [Double]
        var controls: [Control]
        var texts: [Control]
        var clicks: [ClickResult]
        var tabOrder: [String]
    }

    static let skipLabels = ["关闭", "最小化", "全屏", "缩放", "close", "minimize", "zoom", "full screen"]

    func auditPage(_ page: Page) {
        let name = "\(page.side)-\(page.key)"
        var app = launch(page)
        var win = app.windows.firstMatch
        let wf = win.frame
        save(win.screenshot(), name + "-dark")
        let base = controls(in: win)

        // 去重：同样的类型 + 名字只点一次（流水里几十行一样的只点第一行），最多 45 个。
        var seen = Set<String>()
        let targets = base.controls.filter { c in
            guard c.enabled, c.w > 1, c.h > 1, c.y > wf.minY + 4 else { return false }
            if Self.skipLabels.contains(where: { c.label.lowercased().hasPrefix($0) }) { return false }
            if c.id.hasPrefix("_XCUI:") { return false }
            let key = "\(c.type)|\(c.label.prefix(12))"
            return seen.insert(key).inserted
        }.prefix(36)

        var clicks: [ClickResult] = []
        for c in targets {
            let rect = CGRect(x: c.x, y: c.y, width: c.w, height: c.h)
            let origin = win.coordinate(withNormalizedOffset: .zero)
            let at = origin.withOffset(CGVector(dx: rect.midX - wf.minX, dy: rect.midY - wf.minY))
            // 悬停：鼠标先放到标题栏，再移到控件上，比前后像素。
            origin.withOffset(CGVector(dx: wf.width / 2, dy: 12)).hover()
            usleep(250_000)
            let before = crop(win.screenshot(), rect, window: wf)
            at.hover()
            usleep(450_000)
            let hovered = crop(win.screenshot(), rect, window: wf)
            let hoverChanged = (before != nil && hovered != nil) ? before != hovered : nil

            let sheets0 = win.sheets.count, menus0 = app.menus.count, pops0 = app.popovers.count
            let alerts0 = app.alerts.count + app.dialogs.count, wins0 = app.windows.count
            let sig0 = controls(in: win).signature
            at.click()
            usleep(800_000)
            var result = "nothing", after = ""
            if win.sheets.count > sheets0 || app.sheets.count > sheets0 {
                result = "sheet"; after = (win.sheets.firstMatch.staticTexts.firstMatch.label)
            } else if app.menus.count > menus0 {
                result = "menu"; after = app.menus.firstMatch.menuItems.allElementsBoundByIndex.prefix(8).map(\.title).joined(separator: "、")
            } else if app.popovers.count > pops0 {
                result = "popover"; after = app.popovers.firstMatch.staticTexts.firstMatch.label
            } else if app.alerts.count + app.dialogs.count > alerts0 {
                result = "alert"; after = app.alerts.firstMatch.label
            } else if app.windows.count != wins0 {
                result = "window"
            } else if controls(in: win).signature != sig0 {
                result = "changed"
            }
            clicks.append(.init(label: c.label.isEmpty ? c.id : c.label, type: c.type, x: c.x, y: c.y, w: c.w, h: c.h,
                                result: result, hoverChanged: hoverChanged, after: after))
            if result == "nothing" { continue }
            // 复原：Esc 关菜单 / 弹窗；状态变了就重开这一页，保证每个按钮都从同样的起点点。
            app.typeKey(.escape, modifierFlags: [])
            usleep(300_000)
            let closed = result == "sheet" ? !(win.sheets.firstMatch.exists || app.sheets.firstMatch.exists) : false
            if closed { clicks[clicks.count - 1].after += " · Esc 能关" }
            if result != "menu" && result != "popover" && !closed {
                app.terminate()
                app = launch(page)
                win = app.windows.firstMatch
            }
        }

        // 键盘：Tab 走一圈（CI 上已经打开「键盘导航」）。
        app.terminate()
        app = launch(page)
        win = app.windows.firstMatch
        var order: [String] = []
        for _ in 0..<60 {
            app.typeKey(.tab, modifierFlags: [])
            usleep(150_000)
            let f = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
            guard f.exists else { order.append("（看不出焦点在哪）"); continue }
            let label = f.label.isEmpty ? (f.identifier.isEmpty ? f.title : f.identifier) : f.label
            let entry = "\(f.elementType.rawValue)|\(label)"
            if order.first == entry { break }
            order.append(entry)
        }
        app.terminate()

        // 浅色截图（对比度也要看浅色）。
        app = launch(page, dark: false)
        win = app.windows.firstMatch
        save(win.screenshot(), name + "-light")
        let lightTexts = controls(in: win).texts
        app.terminate()

        write(PageReport(name: name, window: [wf.minX, wf.minY, wf.width, wf.height], controls: base.controls,
                         texts: base.texts, clicks: clicks, tabOrder: order), name)
        write(lightTexts, name + "-light-texts")
    }

    func auditSheet(_ sheet: String, shop: Bool) {
        let name = "sheet-\(shop ? "shop-" : "")\(sheet)"
        let app = launch(nil, sheet: sheet, shop: shop)
        let win = app.windows.firstMatch
        let target = win.sheets.firstMatch.exists ? win.sheets.firstMatch : win
        save(target.screenshot(), name + "-dark")
        let c = controls(in: target)
        let f = target.frame
        var order: [String] = []
        for _ in 0..<40 {
            app.typeKey(.tab, modifierFlags: [])
            usleep(150_000)
            let el = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
            guard el.exists else { order.append("（看不出焦点在哪）"); continue }
            let entry = "\(el.elementType.rawValue)|\(el.label.isEmpty ? el.identifier : el.label)"
            if order.first == entry { break }
            order.append(entry)
        }
        // Esc 能不能关掉弹窗
        app.typeKey(.escape, modifierFlags: [])
        usleep(600_000)
        let escCloses = !win.sheets.firstMatch.exists
        write(PageReport(name: name, window: [f.minX, f.minY, f.width, f.height], controls: c.controls, texts: c.texts,
                         clicks: [ClickResult(label: "Esc", type: "key", x: 0, y: 0, w: 0, h: 0,
                                              result: escCloses ? "closed" : "stayed", hoverChanged: nil, after: "")],
                         tabOrder: order), name)
        app.terminate()
    }

    // 拆成几个测试：一个出问题不拖累别的，日志里也看得出跑到哪。
    func test1LifePages() { for p in Self.lifePages { auditPage(Page(side: "life", key: p)) } }
    func test2ShopPages() { for p in Self.shopPages { auditPage(Page(side: "shop", key: p)) } }
    func test3Sheets() {
        for s in Self.sheets where s != "daily" { auditSheet(s, shop: false) }
        for s in ["add", "daily", "fixedCost", "sideTransfer"] { auditSheet(s, shop: true) }
    }
}
