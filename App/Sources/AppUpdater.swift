#if os(macOS)
import Combine
import Sparkle
import SwiftUI

/// Mac 版自动更新（Sparkle）：启动后每天去 appcast 看一次，有新版弹窗，点「安装更新」就换好。
/// 开发版（Debug）、截图和示例模式不检查，免得开发时弹窗。
@MainActor
final class AppUpdater: ObservableObject {
    let controller: SPUStandardUpdaterController?
    @Published var canCheck = false

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let id = Bundle.main.bundleIdentifier ?? ""
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        let args = ProcessInfo.processInfo.arguments
        let quiet = ["-XiaxiaSnapshot", "-XiaxiaDemo", "-XiaxiaEmpty"].contains(where: args.contains)
        guard !id.hasSuffix(".debug"), !feed.isEmpty, !key.isEmpty, !quiet else {
            controller = nil
            return
        }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = c
        c.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
    }

    func check() { controller?.checkForUpdates(nil) }
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
