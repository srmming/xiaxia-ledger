import FinanceCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 「问 AI」：把一句带上下文的话复制到剪贴板，然后打开 Claude。app 自己不和 AI 对话（那是以后的事）。
struct AIPrompt: Identifiable, Hashable {
    var kind: String      // 记账、导入、问问题、月报、目标……
    var text: String
    var id: String { kind + text }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

extension LedgerModel {
    /// 现在看的是哪儿：给 AI 的话前面带上，AI 就知道你在问哪个月、哪个账本。
    func contextLine(page: String) -> String {
        "我在看夏夏账本的「\(page)」，\(shownMonth.label)，\(selectedBookID == nil ? "全部账本" : bookName(selectedBookID) + "账本")。"
    }

    /// 每页常用的几句话。说法通用，不写死具体银行、店名、人名。
    func prompts(for section: AppSection) -> [AIPrompt] {
        let m = "\(shownMonth.month) 月"
        let record = AIPrompt(kind: "记账", text: "帮我记一笔：今天在超市花了 23,40 €，记到\(bookName(defaultBookID))账本")
        let importer = AIPrompt(kind: "导入", text: "这是我的银行对账单，帮我整理好导进夏夏账本")
        switch section {
        case .plans:
            return [AIPrompt(kind: "目标", text: "帮我建一个 2.000 € 的存钱目标，明年 6 月前存够"),
                    AIPrompt(kind: "欠款", text: "帮我记一笔欠款：朋友借了我 300 €，下个月还"),
                    AIPrompt(kind: "分期", text: "帮我记一个分期：手机 1.200 €，分 12 期从信用卡扣")]
        case .spending:
            return [AIPrompt(kind: "问问题", text: "\(m)钱主要花在哪了？哪些可以省？"), record,
                    AIPrompt(kind: "整理", text: "帮我看看\(m)有没有分错类的流水")]
        case .trends:
            return [AIPrompt(kind: "问问题", text: "最近 12 个月我花钱的趋势怎么样？"), AIPrompt(kind: "月报", text: "给我写一份\(m)的月报，写进夏夏账本")]
        case .wealth:
            return [AIPrompt(kind: "问问题", text: "月底的钱够还信用卡吗？"), AIPrompt(kind: "对账", text: "帮我核对一下各个账户的余额和银行对不对得上")]
        case .transactions, .changes:
            return [record, importer, AIPrompt(kind: "整理", text: "帮我看看最近的流水有没有重复或分错类的")]
        default:
            return [record, importer, AIPrompt(kind: "问问题", text: "这个月为什么比上个月花得多？"),
                    AIPrompt(kind: "问问题", text: "月底的钱够还信用卡吗？"), AIPrompt(kind: "月报", text: "给我写一份\(m)的月报，写进夏夏账本")]
        }
    }

    /// 连别的 AI 工具时粘进它的 MCP 设置里的那段。
    var mcpConfig: String {
        #if os(macOS)
        let fin = NSHomeDirectory() + "/.local/bin/fin"
        #else
        let fin = "~/.local/bin/fin"
        #endif
        return """
        { "mcpServers": { "xiaxia-ledger": { "command": "\(fin)", "args": ["mcp"] } } }
        """
    }
}

/// 复制一句话并打开 Claude；打不开 Claude app 就打开网页版。
@MainActor
struct AskAIAction {
    let model: LedgerModel
    let openURL: OpenURLAction

    func callAsFunction(_ text: String, page: String? = nil, open: Bool = true) {
        let full = page.map { model.contextLine(page: $0) + text } ?? text
        Clipboard.copy(full)
        model.toast = .init(text: open ? "已复制，在 Claude 里粘贴就行" : "已复制", changeID: nil)
        guard open, let app = URL(string: "claude://") else { return }
        openURL(app) { accepted in
            if !accepted, let web = URL(string: "https://claude.ai/new") { openURL(web) }
        }
    }
}

/// 页面里用：@Environment(\.openURL) + model 拼出 AskAIAction。
struct AskAIReader<Content: View>: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.openURL) var openURL
    @ViewBuilder var content: (AskAIAction) -> Content
    var body: some View { content(AskAIAction(model: model, openURL: openURL)) }
}

/// 「想记账或问问题？跟 AI 说就行」：虚线框，点任意一句就复制并打开 Claude。
struct AskAICard: View {
    var title = "想记账或问问题？跟 AI 说就行"
    var note: String? = "点一句，复制好话术并打开 Claude。记好的账会自动出现在这里。"
    let page: String
    let prompts: [AIPrompt]

    var body: some View {
        AskAIReader { ask in
            VStack(alignment: .leading, spacing: 10) {
                Label { Text(title).font(.kitSection) } icon: { Image(systemName: "sparkles").foregroundStyle(Color.ai) }
                if let note { Text(note).font(.caption).foregroundStyle(Color.fg2) }
                VStack(spacing: 8) {
                    ForEach(prompts) { p in
                        Button { ask(p.text, page: page) } label: { PromptRow(prompt: p) }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("复制并问 AI：\(p.text)")
                    }
                }
            }
            .askCard()
        }
    }
}

struct PromptRow: View {
    let prompt: AIPrompt
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            KitTag(text: prompt.kind, color: .ai, background: .aiSoft)
            Text(prompt.text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(Color.fg3)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// 工具栏和 iPhone 右下角的实心「问 AI」按钮。
struct AskAIButton: View {
    let page: String
    var compact = false
    var body: some View {
        AskAIReader { ask in
            Button {
                ask("", page: page)
            } label: {
                Label("问 AI", systemImage: "sparkles")
            }
            .buttonStyle(AISolidButtonStyle())
            .help("复制当前页面的上下文，打开 Claude（⌘K）")
            .accessibilityHint("复制当前页面、月份和账本，打开 Claude")
        }
    }
}
