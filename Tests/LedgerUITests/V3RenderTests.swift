#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import LedgerUI

/// 不开窗口，把界面 v3 的页面直接画成图（离屏），给人看效果用。
/// 只有设了环境变量 XIAXIA_RENDER_DIR 才跑；平时跳过。数据全是示例。
@MainActor
final class V3RenderTests: XCTestCase {
    func testRenderOnboardingOffscreen() throws {
        guard let dir = ProcessInfo.processInfo.environment["XIAXIA_RENDER_DIR"] else { throw XCTSkip("没设 XIAXIA_RENDER_DIR") }
        for step in 0..<5 {
            let s = V3State()
            s.onboardingStep = step
            if step >= 2 { s.wish = "三年后不用为钱发愁" }
            let view = V3Onboarding().environment(s).environment(\.v3InlineXia, true)
                .frame(width: 1280, height: 800).background(V3.bg).environment(\.colorScheme, .light)
            let r = ImageRenderer(content: view)
            r.scale = 1
            guard let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                XCTFail("第 \(step + 1) 步没画出来"); continue
            }
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ob\(step + 1).png"))
        }
    }
}
#endif
