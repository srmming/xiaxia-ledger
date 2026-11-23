#if os(macOS)
import FinanceCore
import Foundation
import SwiftUI

/// Mac 版自动更新在 LedgerUI 这边要用到的东西（更新程序本身 Sparkle 在 app 那层）。
public enum AppUpdateSupport {
    /// 设置里「检查更新」按钮发这个通知，app 那层收到就让 Sparkle 去查。
    public static let checkNow = Notification.Name("xiaxia.checkForUpdates")
    /// Sparkle 自己读的开关：后台下载、下次退出 / 打开时换好，不弹窗打扰。Info.plist 里默认开。
    public static let autoInstallKey = "SUAutomaticallyUpdate"

    /// 这个 app 有没有配好自动更新（开发版、没填更新公钥的包没有）。
    public static var isAvailable: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return !(Bundle.main.bundleIdentifier ?? "").hasSuffix(".debug") && feed.hasPrefix("https://") && !key.isEmpty
    }

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
        let folder = url.deletingLastPathComponent().appendingPathComponent("更新前备份")
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let dest = folder.appendingPathComponent("ledger-\(f.string(from: Date()))-更新到\(toVersion).sqlite")
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

/// 设置 →「同步」页里的「更新」一组。
struct AppUpdateRows: View {
    @AppStorage(AppUpdateSupport.autoInstallKey) private var autoInstall = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("自动更新").font(.callout)
                Text("有新版时在后台下载，下次打开就是新版，不打扰你").font(.caption).foregroundStyle(Color.fg2)
            }
            Spacer(minLength: 12)
            Toggle("自动更新", isOn: $autoInstall).labelsHidden().toggleStyle(.switch)
                .accessibilityIdentifier("settings.autoUpdate")
        }
        .padding(.vertical, 9)
        Divider()
        HStack(spacing: 12) {
            Text("现在的版本").font(.callout)
            Text(AppUpdateSupport.versionText).font(.callout).foregroundStyle(Color.fg2)
            Spacer(minLength: 12)
            Button("检查更新") { NotificationCenter.default.post(name: AppUpdateSupport.checkNow, object: nil) }
        }
        .padding(.vertical, 9)
    }
}
#endif
