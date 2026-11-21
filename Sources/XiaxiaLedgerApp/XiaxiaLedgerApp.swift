import AppKit
import FinanceCore
import Observation
import SwiftUI

@main
struct XiaxiaLedgerApp: App {
    @State private var model = LedgerModel(store: JSONFileLedgerStore.defaultStore())

    init() {
        // 用 swift run 启动时也显示成普通窗口 app。
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("夏夏账本") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

/// app 里的账本状态。和 CLI 读写同一个文件。
@MainActor @Observable
final class LedgerModel {
    let store: any LedgerStore
    var ledger: Ledger = .starter
    var selectedBookID: String?   // nil = 全部
    var loadError: String?

    init(store: any LedgerStore) {
        self.store = store
        reload()
    }

    func reload() {
        do { ledger = try store.load(); loadError = nil }
        catch { loadError = error.localizedDescription }
    }
}
