import AppKit
import LedgerUI
import SwiftUI

/// `swift run XiaxiaLedgerApp` 用的 Mac 开发版。正式的 iOS / Mac app 在 App/ 里（XcodeGen 工程），界面都来自 LedgerUI。
@main
enum DevMain {
    /// 带 -XiaxiaV3 1 就开「界面 v3」开发版的窗口，否则是平常的 app。
    static func main() {
        if V3Launch.enabled { V3DevApp.main() } else { XiaxiaLedgerDevApp.main() }
    }
}

struct V3DevApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene { V3Scene() }
}

struct XiaxiaLedgerDevApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene { XiaxiaScene() }
}
