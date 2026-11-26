import FinanceCore
import SwiftUI

extension LedgerModel {
    /// 正在看的月份、账本的 AI 意见（没点「知道了」的）。
    var shownInsights: [Insight] { insightsHere(month: shownMonth) }

    /// 最该先看的一条：本月点评，没有就最新的一条。
    var leadInsight: Insight? { shownInsights.first }

    func dismiss(_ insight: Insight) {
        perform { try $0.dismissInsight(insight.id, author: author) }
    }
}

extension Insight.Kind {
    var color: Color {
        switch self {
        case .monthlyReview, .tip: .ai
        case .alert: .warn
        case .goodNews: .income
        case .action: .alert
        }
    }
    var soft: Color {
        switch self {
        case .monthlyReview, .tip: .aiSoft
        case .alert: .warnSoft
        case .goodNews: .incomeSoft
        case .action: .alertSoft
        }
    }
}

/// 夏夏意见卡：AI 经 MCP 写进账本的点评或提醒。「接着问」复制带上下文的话并打开 Claude，「知道了」收起来。
struct InsightCard: View {
    @Environment(LedgerModel.self) var model
    let insight: Insight
    var large = false
    var showAllLink = true
    /// 总览卡叠里最多几行，免得一张特别长把下面挤出屏幕（全文在「夏夏建议」页）。
    var bodyLines: Int? = nil
    /// 总览卡叠里每张一样高：按钮钉在卡底，夏夏小一点。
    var fixedHeight: CGFloat? = nil
    @State var appeared = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 夏夏的动作跟着这条意见的口气：好消息庆祝、要处理担心、留意在想、点评按性格。
    private var pose: MascotPose {
        switch insight.kind {
        case .goodNews: .celebrate
        case .action: .worried
        case .alert: .think
        case .tip: .write
        case .monthlyReview: model.persona.mascotPose
        }
    }

    var body: some View {
        AskAIReader { ask in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label {
                        Text(insight.kind == .monthlyReview ? tr("夏夏 · \(insight.month.month) 月点评") : tr("夏夏说 · \(insight.kind.label)"))
                    } icon: {
                        // 和右边站着的一样是夏夏（ming 2026-11-23：左上角是小橘、右边是夏夏，对不上）。谁写的看右上角的名字。
                        CharacterSlot(size: 20, face: true, animated: false)
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ai)
                    Spacer()
                    Text("\(insight.author) · \(insight.createdAt.friendly)").font(.caption).foregroundStyle(Color.fg2)
                }
                // 夏夏本人站在文字右边念这条意见；大字号时让出位置给文字。
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.title.keepingAmountsTogether).font(large ? .title3.weight(.bold) : .headline).lineLimit(fixedHeight == nil ? nil : 2).fixedSize(horizontal: false, vertical: fixedHeight == nil)
                        if !insight.body.isEmpty {
                            Text(insight.body.keepingAmountsTogether).font(.subheadline).foregroundStyle(Color.fg2).lineLimit(bodyLines).fixedSize(horizontal: false, vertical: fixedHeight == nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize {
                        CharacterSlot(pose: pose, size: large ? 120 : fixedHeight == nil ? 80 : 64, interactive: true)
                    }
                }
                if fixedHeight != nil { Spacer(minLength: 0) }
                // 按钮单独一行、占满整张卡的宽度：和夏夏挤在一行时，iPhone 上「接着问」会被压成竖排。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { followUp(ask); dismissButton; Spacer(minLength: 8); if showAllLink { MoreLink(title: tr("夏夏建议"), section: .insights) } }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { followUp(ask); dismissButton }
                        if showAllLink { MoreLink(title: tr("夏夏建议"), section: .insights) }
                    }
                }
                .padding(.top, fixedHeight == nil ? 2 : 0)
            }
            .frame(height: fixedHeight, alignment: .top)
            .aiCard()
        }
        .onAppear { if !reduceMotion { appeared = true } }
        .accessibilityElement(children: .contain)
    }

    private func followUp(_ ask: AskAIAction) -> some View {
        Button {
            ask(tr("关于你写的「\(insight.title)」，我想接着问："), page: "夏夏建议")
        } label: { Label(tr("接着问"), systemImage: "sparkles").lineLimit(1).fixedSize() }
            .buttonStyle(.softAI)
    }

    private var dismissButton: some View {
        Button { withAnimation(.snappy) { model.dismiss(insight) } } label: { Text(tr("知道了")).lineLimit(1).fixedSize() }
            .buttonStyle(.soft)
    }
}

/// 提醒列表的一行：前面一个彩色小标签说是什么（留意、建议、好消息、要处理）。
struct InsightRow: View {
    @Environment(LedgerModel.self) var model
    let insight: Insight

    var body: some View {
        let target = AppSection.forInsight(insight)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                KitTag(text: insight.kind.label, color: insight.kind.color, background: insight.kind.soft)
                Text("\(insight.author) · \(insight.createdAt.friendly)").font(.caption).foregroundStyle(Color.fg2)
                Spacer()
                if insight.dismissedAt == nil {
                    Button(tr("知道了")) { withAnimation(.snappy) { model.dismiss(insight) } }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(Color.fg2)
                        .padding(.horizontal, 6).frame(minHeight: 24).contentShape(Rectangle()).hoverBubble()
                } else {
                    Text(tr("知道了")).font(.caption).foregroundStyle(Color.fg3)
                }
            }
            // 点一下去相关的那一页（审查 2026-11-26：原来点了没反应）。
            Button {
                if let target { withAnimation(.snappy) { model.section = target } }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(insight.title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let target {
                            Text(tr("去「\(target.title)」")).font(.caption).foregroundStyle(Color.fg2)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Color.fg3)
                        }
                    }
                    if !insight.body.isEmpty {
                        Text(insight.body).font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(target == nil)
            .hoverHighlight()
            .accessibilityHint(target.map { tr("打开「\($0.title)」") } ?? "")
        }
        .padding(.vertical, 8)
        .opacity(insight.dismissedAt == nil ? 1 : 0.6)
        .accessibilityElement(children: .contain)
    }
}
