#if os(macOS)
import Combine
import LedgerUI
import Sparkle
import SwiftUI

/// Mac 版更新（Sparkle）：每天在后台看一次 appcast。查到新版不弹窗，只在侧栏左下角显示「有新版本 x.y.z」；
/// 点它（或菜单「检查更新…」、设置里的「检查更新」）才打开更新窗口：看新版改了什么，点「安装更新」，下载、换好、重开。
/// 开发版（Debug）、截图和示例模式不检查，免得开发时弹窗。
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var controller: SPUStandardUpdaterController?
    @Published var canCheck = false
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        let args = ProcessInfo.processInfo.arguments
        let quiet = ["-XiaxiaSnapshot", "-XiaxiaDemo", "-XiaxiaEmpty"].contains(where: args.contains)
        guard AppUpdateSupport.isAvailable, !quiet else { return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        controller = c
        c.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        observer = NotificationCenter.default.addObserver(forName: AppUpdateSupport.checkNow, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func check() { controller?.checkForUpdates(nil) }

    // MARK: 后台查到新版：不弹窗，交给侧栏左下角提醒（Sparkle 的「温和提醒」）

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        Task { @MainActor in AppUpdateSupport.state.available = version }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in AppUpdateSupport.state.available = nil }
    }

    // MARK: 换新版之前先把账本复制一份（更新本身不碰账本）

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
