import FinanceCore
import SwiftUI

/// 夏夏建议：夏夏怎么看我的钱？最上面写下你想让夏夏帮你做到什么；下面是 AI 经 MCP 写进账本的点评、提醒，和 AI 最近做了什么。
struct InsightsPage: View {
    @Environment(LedgerModel.self) var model
    @State var allMonths = false

    var body: some View {
        let tools = model.aiTools
        VStack(alignment: .leading, spacing: Kit.gap) {
            statusLine(tools)
            AimCard()
            if tools.isEmpty && !model.anyAIConnected {
                NotConnectedCard()
            }
            Columns(sideWidth: 380, breakpoint: 780) {
                if let review = model.shownInsights.first(where: { $0.kind == .monthlyReview }) {
                    InsightCard(insight: review, large: true, showAllLink: false)
                } else {
                    reviewCard
                }
                remindersCard
                recentAIWork
            } side: {
                AskAICard(title: tr("常用的话，点一下就复制"), note: nil, page: "夏夏建议", prompts: model.prompts(for: .overview))
            }
        }
        .kitPage()
    }

    private func statusLine(_ tools: [AITool]) -> some View {
        FlowLayout(spacing: 12) {
            if tools.isEmpty {
                StatusDot(color: .fg3, text: tr("还没有 AI 写过账本"))
            } else {
                ForEach(tools.prefix(3)) { t in StatusDot(color: .income, text: tr("\(t.name) 用过 · \(t.last.friendly)")) }
            }
            StatusDot(color: model.loadError == nil ? .income : .alert, text: model.loadError == nil ? tr("账本已读到") : tr("账本读不出来"))
        }
        .font(.caption).foregroundStyle(Color.fg2)
    }

    /// 本月点评：AI 还没写意见时，引你让 AI 看看这个月。
    private var reviewCard: some View {
        let m = model.shownMonth.month
        return AskAIReader { ask in
            VStack(alignment: .leading, spacing: 10) {
                Label { Text(tr("\(m) 月点评")).font(.subheadline.weight(.semibold)) } icon: { Image(systemName: "sparkles") }
                    .foregroundStyle(Color.ai)
                Text(tr("让 AI 看看这个月的账")).font(.title3.weight(.bold))
                Text(tr("AI 会读这个月的流水，告诉你花得怎么样、哪里要留意、月底大概剩多少。以后它写的点评会直接显示在这里。"))
                    .font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { ask(tr("看看我 \(m) 月的账：花得怎么样、哪里要留意、月底大概剩多少？"), page: "夏夏建议") } label: {
                        Label(tr("让 AI 点评 \(m) 月"), systemImage: "sparkles")
                    }
                    .buttonStyle(.softAI)
                }
                .padding(.top, 2)
            }
            .aiCard()
        }
    }

    private var remindersCard: some View {
        let list = (allMonths ? model.insightsHere(includeDismissed: true)
                    : model.insightsHere(month: model.shownMonth, includeDismissed: true))
            .filter { $0.kind != .monthlyReview || allMonths }
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: tr("其它提醒")) {
                // 一条条点「知道了」太累：一次全部收起（审查 2026-11-26）。
                if list.contains(where: { $0.dismissedAt == nil }) {
                    Button(tr("全部知道了")) {
                        withAnimation(.snappy) { for i in list where i.dismissedAt == nil { model.dismiss(i) } }
                    }
                    .buttonStyle(.soft).font(.caption)
                }
                Picker(tr("范围"), selection: $allMonths) {
                    Text(tr("本月")).tag(false)
                    Text(tr("全部")).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if list.isEmpty {
                Text(tr("AI 发现要留意的事（比如某类花得比平时多、信用卡快到期），会写在这里。"))
                    .font(.subheadline).foregroundStyle(Color.fg2).padding(.vertical, 6)
            }
            ForEach(list.prefix(30)) { i in
                InsightRow(insight: i)
                if i.id != list.prefix(30).last?.id { Divider() }
            }
        }
        .kitCard()
    }

    private var recentAIWork: some View {
        let changes = model.changesOnThisSide.filter { !model.isMe($0.author) }.sorted { $0.createdAt > $1.createdAt }.prefix(6)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: tr("AI 最近做了什么")) {
                MoreLink(title: tr("改动记录"), section: .changes)
            }
            if changes.isEmpty {
                Text(tr("AI 还没动过账本。跟它说「帮我导入对账单」或「帮我记一笔」，做完会出现在这里。"))
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
    @Environment(LedgerModel.self) var model
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(Color.ai)
            Text(tr("还没连上 AI")).font(.headline)
            #if os(macOS)
            Text(tr("夏夏账本靠 AI 记账。点一下，帮你把 Claude、Codex 这些 AI 连上这本账。"))
                .font(.subheadline).foregroundStyle(Color.fg2).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button { model.sheet = .connectAI } label: { Label(tr("连接你的 AI"), systemImage: "link") }
                .buttonStyle(AISolidButtonStyle())
            #else
            Text(tr("夏夏账本靠 AI 记账。AI 工具在 Mac 上连：打开 Mac 上的夏夏账本，按「连接你的 AI」走一遍，AI 记的账会同步到这里。"))
                .font(.subheadline).foregroundStyle(Color.fg2).multilineTextAlignment(.center).frame(maxWidth: 420)
            #endif
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .kitCard()
    }
}

// MARK: - 改动记录

/// 改动记录：AI 最近动了什么？按时间排，谁改的一眼看出，能撤销。
struct ChangesPage: View {
    @Environment(LedgerModel.self) var model
    @State var who = 0   // 0 全部、1 只看 AI、2 只看我

    var body: some View {
        let all = model.changesOnThisSide.sorted { $0.createdAt > $1.createdAt }
        let list = all.filter { c in who == 0 || (who == 1 ? !model.isMe(c.author) : model.isMe(c.author)) }
        let groups = Dictionary(grouping: list.prefix(200), by: { LocalDate($0.createdAt) }).sorted { $0.key > $1.key }
        Columns(sideWidth: 340, breakpoint: 760) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: tr("所有改动")) {
                    Picker(tr("看谁的"), selection: $who) {
                        Text(tr("全部")).tag(0)
                        Text(tr("只看 AI")).tag(1)
                        Text(tr("只看我")).tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if list.isEmpty {
                    Text(who == 1 ? tr("AI 还没动过账本。") : tr("还没有改动。")).font(.subheadline).foregroundStyle(Color.fg2).padding(.vertical, 12)
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
            Text(tr("每次写入都会记下是谁、什么时候、改了什么。撤销后账本回到改之前的样子，撤销本身也会记一条。"))
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
            Text(tr("这个月 AI 帮你做了")).font(.caption).foregroundStyle(Color.fg2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(ai.count)).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                Text(tr("次改动")).font(.headline)
            }
            Text(verbatim: tr("涉及 \(txCount) 笔流水，其中导入 \(imported) 笔。你自己改了 \(mine.count) 次。"))
                .font(.subheadline).foregroundStyle(Color.fg2)
        }
        .kitCard()
        .accessibilityElement(children: .combine)
    }
}

/// 一条改动：头像、「谁 做了什么」、时间、涉及的几笔、撤销。
struct ChangeRow: View {
    @Environment(LedgerModel.self) var model
    let change: ChangeRecord
    var showUndo = true
    @State private var hovering = false

    var body: some View {
        let me = model.isMe(change.author)
        let txs = change.transactionIDs.prefix(3).compactMap { id in model.transaction(id) ?? change.previous?.first { $0.id == id } }
        HStack(alignment: .top, spacing: 12) {
            Monogram.author(change.author, isMe: me)
            VStack(alignment: .leading, spacing: 3) {
                (Text(me ? tr("你") : change.author).fontWeight(.semibold) + Text(" " + change.summary))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .strikethrough(change.undone)
                Text(change.undone ? tr("\(change.createdAt.clock) · 已撤销") : change.createdAt.clock)
                    .font(.caption).foregroundStyle(Color.fg2)
                if !txs.isEmpty, change.transactionIDs.count > 1 || change.kind == .importBatch {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(txs) { t in Text("• \(Merchant.display(t.description)) \(t.amount.display)") }
                        if change.transactionIDs.count > 3 { Text(tr("• …还有 \(change.transactionIDs.count - 3) 笔")) }
                    }
                    .font(.caption).foregroundStyle(Color.fg2).padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if showUndo, change.canUndo, !change.undone {
                Button { model.undo(change.id) } label: { Label(tr("撤销"), systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.soft)
                    .help(tr("把账本改回这次改动之前的样子"))
                    // Mac：鼠标放到这一行上才显示，每行一个「撤销」太吵（键盘 Tab 仍然能走到）。
                    .opacity(showsUndoAlways || hovering ? 1 : 0)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // 点一行：去流水只看这次改的那几笔（审查 2026-11-26：原来 30 行点了都没反应）。
        .onTapGesture { if canOpen { model.showTransactions(TransactionFilter(ids: Set(change.transactionIDs))) } }
        .hoverHighlight()
        .onHover { hovering = $0 }
        .help(canOpen ? tr("点一下，在流水里看这次改的 \(change.transactionIDs.count) 笔") : "")
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: tr("在流水里看")) { if canOpen { model.showTransactions(TransactionFilter(ids: Set(change.transactionIDs))) } }
    }

    private var showsUndoAlways: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    private var canOpen: Bool {
        !change.undone && change.transactionIDs.contains { model.transaction($0) != nil }
    }
}
