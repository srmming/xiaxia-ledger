import AppKit
import LedgerUI
import SwiftUI

/// `swift run XiaxiaLedgerApp` 用的 Mac 开发版。正式的 iOS / Mac app 在 App/ 里（XcodeGen 工程），界面都来自 LedgerUI。
@main
struct XiaxiaLedgerDevApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene { XiaxiaScene() }
}
