#if os(macOS)
import AppKit
import FinanceCore
import SwiftUI
import XCTest
@testable import LedgerUI

/// 不开窗口，把界面 v3 的页面直接画成图（离屏），给人看效果用。
/// 只有设了环境变量 XIAXIA_RENDER_DIR 才跑；平时跳过。数据全是示例。
@MainActor
final class V3RenderTests: XCTestCase {
    private func write<V: View>(_ view: V, _ name: String, to dir: String) throws {
        let r = ImageRenderer(content: view.frame(width: 1280, height: 800).background(V3.bg).environment(\.colorScheme, .light))
        r.scale = 1
        guard let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            XCTFail("\(name) 没画出来"); return
        }
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func testRenderOnboardingOffscreen() throws {
        guard let dir = ProcessInfo.processInfo.environment["XIAXIA_RENDER_DIR"] else { throw XCTSkip("没设 XIAXIA_RENDER_DIR") }
        for step in 0..<5 {
            let s = V3State()
            s.onboardingStep = step
            if step >= 2 { s.wish = "三年后不用为钱发愁" }
            try write(V3Onboarding().environment(s).environment(\.v3InlineXia, true), "ob\(step + 1)", to: dir)
        }
        // 最后一步选中一张卡的样子
        let picked = V3State()
        picked.onboardingStep = 4; picked.ai = "Claude"
        try write(V3Onboarding().environment(picked).environment(\.v3InlineXia, true), "ob5-picked", to: dir)
        // 「自己的 API」已经填了的样子（假密钥，内存里的假钥匙串）
        let own = V3State()
        own.onboardingStep = 4
        own.keyStore = MemorySecretStore()
        own.saveAPIKey("sk-demo-000", provider: .anthropic)
        own.toast = nil
        try write(V3Onboarding().environment(own).environment(\.v3InlineXia, true), "ob5-own-api", to: dir)
        own.onboardingStep = nil; own.page = .settings; own.settingsSub = .ai
        try write(V3Shell().environment(own), "set-ai-own-api", to: dir)
        // 走完引导直接到总览；目标页空着的样子
        let done = V3State()
        done.onboardingStep = 4; done.ai = "Claude"
        done.nextStep(); done.toast = nil
        XCTAssertNil(done.moment)
        try write(V3Shell().environment(done), "after-onboarding", to: dir)
        done.lastSaid = ("照这样花，这个月存钱差一点。", Date()); done.sayCardID = nil; done.sayUnreadID = "照这样花，这个月存钱差一点。"
        try write(V3Shell().environment(done), "sidebar-chat-unread", to: dir)
        done.sayUnreadID = nil; done.sayDismissed = ["照这样花，这个月存钱差一点。"]
        try write(V3Shell().environment(done), "sidebar-chat-read", to: dir)
        done.side = .biz; done.page = .bizHome
        try write(V3Shell().environment(done), "sidebar-xia-biz", to: dir)
        done.side = .life; done.page = .overview
        done.updateVersion = "0.3.1"
        try write(V3Shell().environment(done), "sidebar-update", to: dir)
        let nogoal = V3State()
        nogoal.onboardingStep = nil; nogoal.patch { $0.wipe() }; nogoal.page = .goals
        try write(V3Shell().environment(nogoal), "goals-empty", to: dir)
        // 新导航、右上角主按钮跟着页面变
        func shell(_ name: String, _ setup: (V3State) -> Void) throws {
            let s = V3State(); s.onboardingStep = nil; setup(s); s.toast = nil
            try write(V3Shell().environment(s), name, to: dir)
        }
        try shell("tx-importing") { $0.page = .transactions; $0.importProgress = ("晴空银行 11 月流水", 40, 52) }
        try shell("spending-donut") { $0.page = .spending }
        try shell("trends-weekly") { $0.page = .trends }
        try shell("sheet-sub-accounts") { s in
            s.page = .subscriptions
            _ = s.addAccount(emoji: "💳", name: "新开的卡", note: "", balance: Money(cents: 300_00), kind: .own)
            _ = s.addAccount(emoji: "💳", name: "第二张卡", note: "", balance: Money(cents: 120_00), kind: .own)
            s.sheet = .subscription
        }
        // 生活和生意的账户分开：生活的总览、家底、管理账户里没有店里的；店里的在生意那边管
        try shell("split-overview") { $0.page = .overview }
        try shell("split-wealth") { $0.page = .wealth }
        try shell("split-accounts-life") { $0.page = .wealth; $0.sheet = .accounts }
        try shell("split-accounts-biz") { $0.side = .biz; $0.page = .shopWealth; $0.sheet = .accounts }
        try shell("split-manual-biz") { $0.side = .biz; $0.page = .bizHome; $0.sheet = .manual }
        try shell("biz-fixed") { $0.side = .biz; $0.page = .fixed }
        try shell("sheet-fixed-add") { $0.side = .biz; $0.page = .fixed; $0.sheet = .fixed }
        try shell("sheet-fixed-edit") { $0.side = .biz; $0.page = .fixed; $0.sheet = .fixedEdit("水电") }
        try shell("biz-flow") { $0.side = .biz; $0.page = .shopFlow }
        try shell("sheet-shopday-channels") { $0.side = .biz; $0.page = .bizHome; $0.sheet = .shopDay(18) }
        try shell("sheet-shopday-expense") { $0.side = .biz; $0.page = .shopFlow; $0.shopDayExpense = true; $0.sheet = .shopDay(18) }
        try shell("biz-home-channels") { s in
            s.side = .biz; s.page = .bizHome
            s.change("记好了") { try $0.recordShopDay(18, channels: [.init("小店账户", Money(cents: 112_00)), .init("店里现金", Money(cents: 74_00))]) }
        }
        try shell("sheet-purchase") { $0.side = .biz; $0.page = .stock; $0.sheet = .purchase }
        try shell("biz-debts") { $0.side = .biz; $0.page = .bizDebts }
        try shell("sheet-transfer-life") { $0.page = .overview; $0.manualStartKind = 2; $0.sheet = .manual }
        try shell("sheet-transfer-biz") { $0.side = .biz; $0.page = .bizHome; $0.manualStartKind = 2; $0.sheet = .manual }
        try shell("goals-big-and-small") { $0.page = .goals }
        try shell("sheet-holdback") { $0.sheet = .holdBack }
        try shell("biz-shop-wealth") { $0.side = .biz; $0.page = .shopWealth }
        try shell("biz-home-wealth-card") { $0.side = .biz; $0.page = .bizHome }
        try shell("sheet-shop-account") { $0.side = .biz; $0.page = .shopWealth; $0.sheet = .shopAccount }
        let lockedState = V3State(); lockedState.onboardingStep = nil; lockedState.locked = true
        try write(V3LockScreen().environment(lockedState), "lock-screen", to: dir)
        try shell("set-lock") { $0.page = .settings; $0.settingsSub = .privacy }
        try shell("nav-wealth") { $0.page = .wealth }
        try shell("nav-goals") { $0.page = .goals }
        try shell("nav-biz") { $0.side = .biz; $0.page = .fixed }
        // 问夏夏：带一张图问要不要买
        try shell("chat-buy") { s in
            s.chatOpen = true
            s.chat = [.init(mine: true, text: "想买个降噪耳机 279", attachment: "🖼 耳机.jpg")]
            if let c = try? s.book.checkPurchase(name: "降噪耳机", price: Money(cents: 279_00)) { s.chat.append(.init(mine: false, text: c.line, check: c)) }
            s.chat.append(.init(mine: true, text: "", attachment: "🔗 shop.example.com"))
            s.chat.append(.init(mine: false, text: "多少钱？"))
        }
        // 「要不要买」那张小卡单独画一张（聊天页是能滚动的，离屏画不出里面的内容）
        let buy = V3State()
        if let c = try? buy.book.checkPurchase(name: "降噪耳机", price: Money(cents: 279_00)) {
            let m = V3State.ChatMessage(mine: false, text: c.line, check: c)
            try write(V3BuyCard(message: m, check: c).environment(buy).frame(width: 1280, height: 800), "chat-buy-card", to: dir)
        }
        // 记一笔：三种方式
        let old = UserDefaults.standard.object(forKey: "xiaxia.v3.addWay")
        for (i, name) in ["add-say", "add-manual", "add-file"].enumerated() {
            UserDefaults.standard.set(i, forKey: "xiaxia.v3.addWay")
            try shell(name) { $0.showAdd = true }
        }
        if let old { UserDefaults.standard.set(old, forKey: "xiaxia.v3.addWay") } else { UserDefaults.standard.removeObject(forKey: "xiaxia.v3.addWay") }
        // 刚进总览、还没有流水：顶上夏夏说一句去导入
        let empty = V3State()
        empty.onboardingStep = nil
        empty.patch { $0.wipe() }
        empty.sayCardID = "想省事？把银行流水拖进来，我帮你填"
        try write(V3Shell().environment(empty), "overview-empty", to: dir)
        // 管哪边：只管生活、只管生意、设置里的两个开关
        for (mode, name) in [(V3State.Mode.life, "sides-life"), (.biz, "sides-biz")] {
            let s = V3State()
            s.onboardingStep = nil
            s.mode = mode
            try write(V3Shell().environment(s), name, to: dir)
        }
        let set = V3State()
        set.onboardingStep = nil; set.page = .settings; set.settingsSub = .business
        try write(V3Shell().environment(set), "sides-settings", to: dir)
    }

    /// 规格对照的那四组图（有数据、没数据、设置、弹窗）全部离屏重画一遍。
    func testRenderSpecSetOffscreen() throws {
        guard let dir = ProcessInfo.processInfo.environment["XIAXIA_RENDER_SPEC_DIR"] else { throw XCTSkip("没设 XIAXIA_RENDER_SPEC_DIR") }
        func out(_ sub: String) throws -> String {
            let d = (dir as NSString).appendingPathComponent(sub)
            try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            return d
        }
        func fresh() -> V3State { let s = V3State(); s.onboardingStep = nil; return s }
        for p in V3State.Page.life + V3State.Page.biz {
            let s = fresh(); s.go(p); if V3State.Page.biz.contains(p) { s.side = .biz; s.page = p }
            try write(V3Shell().environment(s), p.rawValue, to: try out("有数据"))
            let e = fresh(); e.patch { $0.wipe() }; if V3State.Page.biz.contains(p) { e.side = .biz }; e.page = p
            try write(V3Shell().environment(e), p.rawValue, to: try out("没数据"))
        }
        let log = fresh(); log.page = .settings; log.showLog = true
        try write(V3Shell().environment(log), "log", to: try out("有数据"))
        for f in [V3State.Forced.loading, .error] {
            let s = fresh(); s.forced = f
            try write(V3Shell().environment(s), f.rawValue, to: try out("没数据"))
        }
        let txErr = fresh(); txErr.page = .transactions; txErr.forced = .error
        try write(V3Shell().environment(txErr), "出错-流水", to: try out("没数据"))
        let home = fresh(); home.page = .settings
        try write(V3Shell().environment(home), "settings", to: try out("设置"))
        for sub in ["ai", "xia", "memory", "speak", "privacy", "author", "books", "business", "money", "sync", "data"] {
            let s = fresh(); s.page = .settings; s.settingsSub = V3State.SettingsSub(rawValue: sub)
            try write(V3Shell().environment(s), "set-" + sub, to: try out("设置"))
        }
        for name in ["sheet-save", "sheet-cat", "sheet-amount", "sheet-sub", "sheet-debt", "sheet-repay", "sheet-daily", "sheet-fixed", "sheet-purchase",
                     "sheet-stock", "sheet-capital", "sheet-captotal", "sheet-transfer", "sheet-shopdebt", "sheet-memo", "sheet-forget", "sheet-tidy", "sheet-meet",
                     "sheet-del1", "sheet-del2", "sheet-restore", "sheet-feedback", "sheet-books", "sheet-accounts", "sheet-cats", "sheet-base",
                     "sheet-plan", "sheet-subinfo", "sheet-fixededit"] {
            let s = fresh()
            V3Sheet.fromLaunch(name, s)
            try write(V3Shell().environment(s), name, to: try out("弹窗"))
        }
    }
}
#endif
