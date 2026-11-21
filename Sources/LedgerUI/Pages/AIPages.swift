import FinanceCore
import SwiftUI

/// AI 意见：AI 怎么看我的钱？以后 AI 经 MCP 把点评和提醒写进账本，这里显示；现在先引你去问 AI，并列出 AI 最近做了什么。
struct InsightsPage: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        let tools = model.aiTools
        VStack(alignment: .leading, spacing: Kit.gap) {
            statusLine(tools)
            if tools.isEmpty {
                NotConnectedCard()
            }
            Columns(sideWidth: 380, breakpoint: 780) {
                reviewCard
                recentAIWork
            } side: {
                AskAICard(title: "常用的话，点一下就复制", note: nil, page: "AI 意见", prompts: model.prompts(for: .overview))
            }
        }
        .kitPage()
    }

    private func statusLine(_ tools: [AITool]) -> some View {
        HStack(spacing: 14) {
            if tools.isEmpty {
                StatusDot(color: .fg3, text: "还没有 AI 写过账本")
            } else {
                ForEach(tools.prefix(3)) { t in StatusDot(color: .income, text: "\(t.name) 用过 · \(t.last.friendly)") }
            }
            StatusDot(color: model.loadError == nil ? .income : .alert, text: model.loadError == nil ? "账本已读到" : "账本读不出来")
        }
        .font(.caption).foregroundStyle(Color.fg2)
    }

    /// 本月点评：AI 还没写意见时，引你让 AI 看看这个月。
    private var reviewCard: some View {
        let m = model.shownMonth.month
        return AskAIReader { ask in
            VStack(alignment: .leading, spacing: 10) {
                Label { Text("\(m) 月点评").font(.subheadline.weight(.semibold)) } icon: { Image(systemName: "sparkles") }
                    .foregroundStyle(Color.ai)
                Text("让 AI 看看这个月的账").font(.title3.weight(.bold))
                Text("AI 会读这个月的流水，告诉你花得怎么样、哪里要留意、月底大概剩多少。以后它写的点评会直接显示在这里。")
                    .font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { ask("看看我 \(m) 月的账：花得怎么样、哪里要留意、月底大概剩多少？", page: "AI 意见") } label: {
                        Label("让 AI 点评 \(m) 月", systemImage: "sparkles")
                    }
                    .buttonStyle(.softAI)
                }
                .padding(.top, 2)
            }
            .aiCard()
        }
    }

    private var recentAIWork: some View {
        let changes = model.ledger.changes.filter { !model.isMe($0.author) }.sorted { $0.createdAt > $1.createdAt }.prefix(6)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "AI 最近做了什么") {
                MoreLink(title: "改动记录", section: .changes)
            }
            if changes.isEmpty {
                Text("AI 还没动过账本。跟它说「帮我导入对账单」或「帮我记一笔」，做完会出现在这里。")
                    .font(.subheadline).foregroundStyle(Color.fg2).padding(.vertical, 6)
            }
            ForEach(Array(changes)) { c in
                ChangeRow(change: c, showUndo: false)
                if c.id != changes.last?.id { Divider().padding(.leading, 42) }
            }
        }
        .kitCard()
    }
}

struct StatusDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 7, height: 7); Text(text) }
    }
}

/// 还没连上 AI：复制 MCP 配置，粘进 Claude / Codex 的设置。
struct NotConnectedCard: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(Color.ai)
            Text("还没连上 AI").font(.headline)
            Text("夏夏账本靠 AI 记账。在 Claude 或 Codex 里装上夏夏账本的 MCP，就能让它读写这本账。")
                .font(.subheadline).foregroundStyle(Color.fg2).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 8) {
                Button {
                    Clipboard.copy(model.mcpConfig)
                    model.toast = .init(text: "MCP 配置已复制", changeID: nil)
                } label: { Label("复制 MCP 配置", systemImage: "doc.on.doc") }
                    .buttonStyle(AISolidButtonStyle())
                Button("怎么装？") {
                    if let url = URL(string: "https://github.com/srmming/xiaxia-ledger#readme") { openURL(url) }
                }
                .buttonStyle(.soft)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .kitCard()
    }
}

// MARK: - 改动记录

/// 改动记录：AI 最近动了什么？按时间排，谁改的一眼看出，能撤销。
struct ChangesPage: View {
    @Environment(LedgerModel.self) private var model
    @State private var who = 0   // 0 全部、1 只看 AI、2 只看我

    var body: some View {
        let all = model.ledger.changes.sorted { $0.createdAt > $1.createdAt }
        let list = all.filter { c in who == 0 || (who == 1 ? !model.isMe(c.author) : model.isMe(c.author)) }
        let groups = Dictionary(grouping: list.prefix(200), by: { LocalDate($0.createdAt) }).sorted { $0.key > $1.key }
        Columns(sideWidth: 340, breakpoint: 760) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "所有改动") {
                    Picker("看谁的", selection: $who) {
                        Text("全部").tag(0)
                        Text("只看 AI").tag(1)
                        Text("只看我").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if list.isEmpty {
                    Text(who == 1 ? "AI 还没动过账本。" : "还没有改动。").font(.subheadline).foregroundStyle(Color.fg2).padding(.vertical, 12)
                }
                ForEach(groups, id: \.key) { day, changes in
                    Text(day.friendly).font(.caption).foregroundStyle(Color.fg2).padding(.top, 6)
                    ForEach(changes) { c in
                        ChangeRow(change: c, showUndo: true)
                        if c.id != changes.last?.id { Divider().padding(.leading, 42) }
                    }
                }
            }
            .kitCard()
        } side: {
            monthSummary(all)
            Text("每次写入都会记下是谁、什么时候、改了什么。撤销后账本回到改之前的样子，撤销本身也会记一条。")
                .font(.caption).foregroundStyle(Color.fg2)
                .padding(Kit.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sunken.opacity(0.6), in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
        }
        .kitPage()
    }

    private func monthSummary(_ all: [ChangeRecord]) -> some View {
        let month = LocalDate.today.yearMonth
        let thisMonth = all.filter { LocalDate($0.createdAt).yearMonth == month && !$0.undone }
        let ai = thisMonth.filter { !model.isMe($0.author) }
        let mine = thisMonth.filter { model.isMe($0.author) }
        let txCount = ai.reduce(0) { $0 + $1.transactionIDs.count }
        let imported = ai.filter { $0.kind == .importBatch }.reduce(0) { $0 + $1.transactionIDs.count }
        return VStack(alignment: .leading, spacing: 6) {
            Text("这个月 AI 帮你做了").font(.caption).foregroundStyle(Color.fg2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(ai.count)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                Text("次改动").font(.headline)
            }
            Text("涉及 \(txCount) 笔流水，其中导入 \(imported) 笔。你自己改了 \(mine.count) 次。")
                .font(.subheadline).foregroundStyle(Color.fg2)
        }
        .kitCard()
        .accessibilityElement(children: .combine)
    }
}

/// 一条改动：头像、「谁 做了什么」、时间、涉及的几笔、撤销。
struct ChangeRow: View {
    @Environment(LedgerModel.self) private var model
    let change: ChangeRecord
    var showUndo = true

    var body: some View {
        let me = model.isMe(change.author)
        let txs = change.transactionIDs.prefix(3).compactMap { id in model.transaction(id) ?? change.previous?.first { $0.id == id } }
        HStack(alignment: .top, spacing: 12) {
            Monogram.author(change.author, isMe: me)
            VStack(alignment: .leading, spacing: 3) {
                (Text(me ? "你" : change.author).fontWeight(.semibold) + Text(" " + change.summary))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .strikethrough(change.undone)
                Text(change.undone ? "\(change.createdAt.clock) · 已撤销" : change.createdAt.clock)
                    .font(.caption).foregroundStyle(Color.fg2)
                if !txs.isEmpty, change.transactionIDs.count > 1 || change.kind == .importBatch {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(txs) { t in Text("• \(Merchant.display(t.description)) \(t.amount.display)") }
                        if change.transactionIDs.count > 3 { Text("• …还有 \(change.transactionIDs.count - 3) 笔") }
                    }
                    .font(.caption).foregroundStyle(Color.fg2).padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if showUndo, change.canUndo, !change.undone {
                Button { model.undo(change.id) } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.soft)
                    .help("把账本改回这次改动之前的样子")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
