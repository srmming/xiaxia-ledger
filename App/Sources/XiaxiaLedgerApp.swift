import LedgerUI
import SwiftUI

/// iPhone 和 Mac 正式 app 的入口。界面和规则都在 LedgerUI / FinanceCore 里。
@main
struct XiaxiaLedgerApp: App {
    #if os(macOS)
    @StateObject private var updater = AppUpdater()
    #endif

    var body: some Scene {
        #if os(macOS)
        XiaxiaScene()
            .commands {
                CommandGroup(after: .appInfo) { CheckForUpdatesButton(updater: updater) }
            }
        #else
        XiaxiaScene()
        #endif
    }
}
