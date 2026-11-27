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
        let nogoal = V3State()
        nogoal.onboardingStep = nil; nogoal.patch { $0.wipe() }; nogoal.page = .goals
        try write(V3Shell().environment(nogoal), "goals-empty", to: dir)
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
}
#endif
