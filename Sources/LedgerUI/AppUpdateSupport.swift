#if os(macOS)
import FinanceCore
import Foundation
import Observation
import SwiftUI

/// Mac 版自动更新在 LedgerUI 这边要用到的东西（更新程序本身 Sparkle 在 app 那层）。
public enum AppUpdateSupport {
    /// 设置里「检查更新」按钮发这个通知，app 那层收到就让 Sparkle 去查。
    public static let checkNow = Notification.Name("xiaxia.checkForUpdates")
    /// 后台查到的新版本号（app 那层的更新程序填）；侧栏左下角据此显示「有新版本」。
    /// 截图看样子：启动参数带 -XiaxiaUpdatePreview 就假装有新版 0.2.1（开发版、截图模式也显示）。
    @MainActor public static let state: AppUpdateState = {
        let s = AppUpdateState()
        if preview { s.available = "0.2.1" }
        return s
    }()
    static var preview: Bool { ProcessInfo.processInfo.arguments.contains("-XiaxiaUpdatePreview") }

    /// 这个 app 有没有配好自动更新（开发版、没填更新公钥的包没有）。
    public static var isAvailable: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return !(Bundle.main.bundleIdentifier ?? "").hasSuffix(".debug") && feed.hasPrefix("https://") && !key.isEmpty
    }

    public static func requestCheck() { NotificationCenter.default.post(name: checkNow, object: nil) }

    public static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?")（\(info["CFBundleVersion"] as? String ?? "?")）"
    }

    /// 换新版之前把账本复制一份，放在账本旁边的「更新前备份」文件夹里，只留最近 5 份。
    /// 更新只换 app 本身，不碰账本；这份备份是防新版第一次打开时升级账本格式出意外。
    @discardableResult
    public static func backupLedger(toVersion: String) -> URL? {
        let store = LedgerStores.appStore()
        guard let url = (store as? MigratingStore)?.primary.url ?? (store as? SQLiteLedgerStore)?.url else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let folder = url.deletingLastPathComponent().appendingPathComponent(tr("更新前备份"))
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let dest = folder.appendingPathComponent(tr("ledger-\(f.string(from: Date()))-更新到\(toVersion).sqlite"))
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: dest)
            let old = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for u in old.filter({ $0.pathExtension == "sqlite" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(5) {
                try? fm.removeItem(at: u)
            }
            return dest
        } catch { return nil }
    }
}

@MainActor @Observable
public final class AppUpdateState {
    /// 有新版时是它的版本号（比如 0.2.1），没有就是 nil。
    public var available: String?
}

/// 设置 →「同步」页里的「更新」一组。
struct AppUpdateRows: View {
    private var state: AppUpdateState { AppUpdateSupport.state }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("现在的版本 \(AppUpdateSupport.versionText)")).font(.callout)
                Text(state.available.map { tr("有新版本 \($0)") } ?? tr("每次打开都会看一眼有没有新版，有的话左下角会提醒"))
                    .font(.caption).foregroundStyle(state.available == nil ? Color.fg2 : Color.brand)
            }
            Spacer(minLength: 12)
            Link(tr("更新日志"), destination: Changelog.webURL)
                .font(.callout)
                .help(tr("每一版改了什么（官网）"))
            Button(state.available == nil ? tr("检查更新") : tr("现在更新")) { AppUpdateSupport.requestCheck() }
                .accessibilityIdentifier("settings.checkUpdate")
        }
        .padding(.vertical, 9)
    }
}

/// 侧栏左下角的「更新」：平时是一行灰色小字，有新版时变成带红点的「有新版本 x.y.z」。
/// 点一下打开更新窗口（看新版改了什么、点「安装更新」，下载、换好、重开）。
struct SidebarUpdateButton: View {
    private var state: AppUpdateState { AppUpdateSupport.state }

    var body: some View {
        if AppUpdateSupport.isAvailable || AppUpdateSupport.preview {
            Button { AppUpdateSupport.requestCheck() } label: {
                HStack(spacing: 6) {
                    if let v = state.available {
                        Circle().fill(Color.alert).frame(width: 7, height: 7)
                        Text(tr("有新版本 \(v)")).foregroundStyle(.primary).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(tr("更新")).fontWeight(.semibold).foregroundStyle(Color.brand)
                    } else {
                        Image(systemName: "arrow.down.circle")
                        Text(tr("检查更新"))
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.fg3)
                // 有新版时变成一条带底色的提示条，比一行灰字显眼，但不弹窗。
                .padding(.horizontal, state.available == nil ? 0 : 10)
                .padding(.vertical, state.available == nil ? 0 : 7)
                .background {
                    if state.available != nil {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.brandSoft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.available == nil ? tr("看看有没有新版本") : tr("看新版改了什么，点「安装更新」"))
            .accessibilityLabel(state.available.map { tr("有新版本 \($0)，点一下更新") } ?? tr("检查更新"))
            .accessibilityIdentifier("sidebar.update")
        }
    }
}
#endif
