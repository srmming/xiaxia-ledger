import FinanceCore
import Foundation
import Observation
import SwiftUI

/// 更新日志里的一版（数据在 Resources/Changelog.json，官网 /changelog.html 和 Mac 更新窗口也用这一份）。
public struct ChangelogEntry: Decodable, Identifiable, Equatable {
    public let version: String
    public let date: String
    public let title: String
    public let summary: String
    public let items: [String]
    public var id: String { version }
}

public enum Changelog {
    /// 官网上的更新日志页。
    public static let webURL = URL(string: "https://xiaxia.ming95.com/changelog.html")!

    /// app 里带的全部更新日志，新版在前。读不到就是空的（不影响用 app）。
    public static let all: [ChangelogEntry] = {
        guard let url = Bundle.module.url(forResource: "Changelog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }()

    struct File: Decodable { let releases: [ChangelogEntry] }

    static func decode(_ data: Data) -> [ChangelogEntry] {
        ((try? JSONDecoder().decode(File.self, from: data))?.releases ?? [])
            .sorted { isNewer($0.version, than: $1.version) }
    }

    /// 按数字比版本号：0.2.10 比 0.2.9 新。
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 从 old 升到 current，中间每一版改了什么（新版在前，不含 old 本身）。
    static func entries(after old: String, upTo current: String, in list: [ChangelogEntry] = all) -> [ChangelogEntry] {
        list.filter { isNewer($0.version, than: old) && !isNewer($0.version, than: current) }
    }
}

/// 更新后第一次打开：右下角一张小卡片写着「这次更新了什么」，不挡操作，点「知道了」就收起。
/// 只在真的从旧版升上来时出：新装的不出（没东西可比），同一版只出一次。
@MainActor @Observable
public final class WhatsNewState {
    /// 记着「已经看过哪一版的更新内容」。
    static let seenKey = "xiaxia.whatsNew.seenVersion"
    /// 加这个功能之前的最后一版：老用户升上来时还没有 seenKey，就当是从这一版升上来的。
    static let lastVersionBefore = "0.2.4"

    /// 要显示的几版（新版在前）；空就是不显示。
    public var entries: [ChangelogEntry] = []
    /// 现在的版本号（卡片标题用）。
    public private(set) var current = ""

    public static let shared = WhatsNewState()

    /// 启动时调用一次。hasData：账本里已经有东西（说明不是新装的）。
    /// 截图看样子：启动参数 -XiaxiaWhatsNew <旧版本号> 假装刚从那一版升上来（截图、示例模式也显示）。
    public func checkOnLaunch(hasData: Bool, defaults: UserDefaults = .standard) {
        let info = Bundle.main.infoDictionary ?? [:]
        current = info["CFBundleShortVersionString"] as? String ?? ""
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-XiaxiaWhatsNew"), i + 1 < args.count {
            entries = Changelog.entries(after: args[i + 1], upTo: current)
            return
        }
        let quiet = ["-XiaxiaSnapshot", "-XiaxiaDemo", "-XiaxiaEmpty"].contains(where: args.contains)
        let isDev = (Bundle.main.bundleIdentifier ?? "").hasSuffix(".debug")
        guard !quiet, !isDev, !current.isEmpty else { return }
        entries = Self.pending(current: current, hasData: hasData, defaults: defaults)
    }

    /// 该显示哪几版（不改任何记录）。
    static func pending(current: String, hasData: Bool, defaults: UserDefaults, list: [ChangelogEntry] = Changelog.all) -> [ChangelogEntry] {
        var seen = defaults.string(forKey: seenKey)
        if seen == nil {
            // 没记过：用过 app 的老用户当作从 0.2.4 升上来；新装的什么都不出，直接记下现在的版本。
            let usedBefore = hasData || defaults.bool(forKey: LedgerModel.welcomeDoneKey) || defaults.bool(forKey: "xiaxia.aiSetupShown")
            guard usedBefore else { defaults.set(current, forKey: seenKey); return [] }
            seen = lastVersionBefore
        }
        guard let seen, Changelog.isNewer(current, than: seen) else { return [] }
        let list = Changelog.entries(after: seen, upTo: current, in: list)
        if list.isEmpty { defaults.set(current, forKey: seenKey) }   // 这一版没写更新日志：不出卡片
        return list
    }

    public func dismiss(defaults: UserDefaults = .standard) {
        if !current.isEmpty, !ProcessInfo.processInfo.arguments.contains("-XiaxiaWhatsNew") {
            defaults.set(current, forKey: Self.seenKey)
        }
        entries = []
    }
}

#if os(macOS)
/// 右下角的「这次更新了什么」卡片。最多列最新一版的 4 条，别的版本只给标题，完整的去官网看。
struct WhatsNewCard: View {
    let state: WhatsNewState
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let top = state.entries.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    MascotView(.xiaxia, pose: .celebrate, size: 44, face: true, animated: false)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("已更新到 \(state.current)")).font(.caption.weight(.semibold)).foregroundStyle(Color.brand)
                        Text(top.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { withAnimation(.snappy) { state.dismiss() } } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tr("收起"))
                    .accessibilityLabel(tr("收起更新内容"))
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(top.items.prefix(4).enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").font(.callout.weight(.bold)).foregroundStyle(Color.brand).accessibilityHidden(true)
                            Text(item).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if state.entries.count > 1 {
                    Text(tr("之前几版：") + state.entries.dropFirst().map { "\($0.version) \($0.title)" }.joined(separator: "；"))
                        .font(.caption).foregroundStyle(Color.fg3).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button(tr("完整更新日志")) {
                        openURL(URL(string: Changelog.webURL.absoluteString + "#v\(top.version)") ?? Changelog.webURL)
                    }
                    .buttonStyle(.soft)
                    Button(tr("知道了")) { withAnimation(.snappy) { state.dismiss() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 340, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tr("已更新到 \(state.current)：\(top.title)"))
            .accessibilityIdentifier("whatsNew.card")
        }
    }
}
#endif
