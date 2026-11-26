import FinanceCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 提反馈（ming 2026-11-25「帮我做一个用户可以提交反馈的位置在界面上」）：设置最下面、Mac 菜单「帮助 → 反馈问题」。
/// 最简单、不用服务器也不用密钥：写好以后打开用户自己的邮件 app，内容都填好，按发送就行；没设邮箱可以复制。
/// 只带版本和系统信息，不带账本里的任何东西。
struct FeedbackSheet: View {
    static let address = "ming@ming95.com"

    enum Kind: String, CaseIterable, Identifiable {
        case bug, idea, other
        var id: String { rawValue }
        var label: String {
            switch self { case .bug: tr("遇到问题"); case .idea: tr("提个想法"); case .other: tr("别的") }
        }
        var subject: String {
            switch self { case .bug: "问题"; case .idea: "想法"; case .other: "反馈" }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var kind: Kind = .bug
    @State private var text = ""
    @State private var withInfo = true
    @State private var copied = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                Picker(tr("是什么"), selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(kind == .bug ? tr("在哪一页、点了什么、看到了什么？") : tr("想要什么、为什么想要？"))
                            .foregroundStyle(Color.fg3).padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .accessibilityLabel(tr("想说的话"))
                        .accessibilityIdentifier("feedback.text")
                }
                Toggle(tr("带上版本和系统信息"), isOn: $withInfo)
            } footer: {
                Text(tr("会打开你的邮件 app，内容已经填好，按发送就行。不会带上账本里的任何东西。"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("反馈问题 / 提个想法"))
        #if os(macOS)
        .safeAreaInset(edge: .bottom) {
            HStack {
                // 和别的弹窗一样：取消在左，主按钮在右（审查 2026-11-26）。⌘↩ 直接发送。
                Button(tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                Spacer()
                Button(copied ? tr("复制好了") : tr("复制")) { copy() }.disabled(trimmed.isEmpty).controlSize(.large)
                Button(tr("用邮件发送")) { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .sheetPrimary()
                    .help(tr("⌘↩ 发送"))
                    .disabled(trimmed.isEmpty)
                    .accessibilityIdentifier("feedback.send")
            }
            .padding(16)
        }
        #else
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("发送")) { send() }.disabled(trimmed.isEmpty).keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("feedback.send")
            }
            ToolbarItem(placement: .bottomBar) {
                Button(copied ? tr("复制好了") : tr("复制下来")) { copy() }.disabled(trimmed.isEmpty)
            }
        }
        #endif
        .onAppear { focused = true }
    }

    private var info: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        #if os(macOS)
        let device = "Mac"
        #else
        let device = UIDevice.current.model
        #endif
        return "夏夏账本 \(v) (\(b)) · \(device) · \(os) · \(Locale.current.identifier)"
    }

    private var body_: String { withInfo ? "\(trimmed)\n\n——\n\(info)" : trimmed }

    private func send() {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = Self.address
        c.queryItems = [URLQueryItem(name: "subject", value: "夏夏账本 · \(kind.subject)"), URLQueryItem(name: "body", value: body_)]
        guard let url = c.url else { return copy() }
        openURL(url) { ok in
            if ok { dismiss() } else { copy() }
        }
    }

    private func copy() {
        let all = "发到 \(Self.address)\n\(body_)"
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(all, forType: .string)
        #else
        UIPasteboard.general.string = all
        #endif
        copied = true
    }
}
