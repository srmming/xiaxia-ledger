#if os(macOS)
import AppKit
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
        // 刚进总览、还没有流水：顶上夏夏说一句去导入
        let empty = V3State()
        empty.onboardingStep = nil
        empty.patch { $0.wipe() }
        empty.sayCardID = "想省事？把银行流水拖进来，我帮你填"
        try write(V3Shell().environment(empty), "overview-empty", to: dir)
    }
}
#endif
