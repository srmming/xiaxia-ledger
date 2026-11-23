#if os(macOS)
import Combine
import LedgerUI
import Sparkle
import SwiftUI

/// Mac 版自动更新（Sparkle）：每天去 appcast 看一次，有新版在后台下载，下次退出 / 打开时换好，不弹窗。
/// 设置 →「同步」里能关自动更新、手动检查；菜单「夏夏账本 → 检查更新…」也能查。
/// 开发版（Debug）、截图和示例模式不检查，免得开发时弹窗。
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private(set) var controller: SPUStandardUpdaterController?
    @Published var canCheck = false
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        let args = ProcessInfo.processInfo.arguments
        let quiet = ["-XiaxiaSnapshot", "-XiaxiaDemo", "-XiaxiaEmpty"].contains(where: args.contains)
        guard AppUpdateSupport.isAvailable, !quiet else { return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller = c
        c.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        observer = NotificationCenter.default.addObserver(forName: AppUpdateSupport.checkNow, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func check() { controller?.checkForUpdates(nil) }

    /// 换新版之前先把账本复制一份（更新本身不碰账本）。
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        AppUpdateSupport.backupLedger(toVersion: item.displayVersionString)
    }
}

/// 菜单「夏夏账本 → 检查更新…」。
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        if updater.controller != nil {
            Button("检查更新…") { updater.check() }
                .disabled(!updater.canCheck)
        }
    }
}
#endif
