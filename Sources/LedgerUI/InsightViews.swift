import FinanceCore
import SwiftUI

extension LedgerModel {
    /// 正在看的月份、账本的 AI 意见（没点「知道了」的）。
    var shownInsights: [Insight] { ledger.insights(month: shownMonth, bookID: selectedBookID) }

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
    @State var appeared = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        AskAIReader { ask in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label {
                        Text(insight.kind == .monthlyReview ? "夏夏 · \(insight.month.month) 月点评" : "夏夏说 · \(insight.kind.label)")
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ai)
                    Spacer()
                    Text("\(insight.author) · \(insight.createdAt.friendly)").font(.caption).foregroundStyle(Color.fg2)
                }
                Text(insight.title).font(large ? .title3.weight(.bold) : .headline).fixedSize(horizontal: false, vertical: true)
                if !insight.body.isEmpty {
                    Text(insight.body).font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button {
                        ask("关于你写的「\(insight.title)」，我想接着问：", page: "夏夏建议")
                    } label: { Label("接着问", systemImage: "sparkles") }
                        .buttonStyle(.softAI)
                    Button("知道了") { withAnimation(.snappy) { model.dismiss(insight) } }
                        .buttonStyle(.soft)
                    Spacer()
                    if showAllLink { MoreLink(title: "夏夏建议", section: .insights) }
                }
                .padding(.top, 2)
            }
            .aiCard()
        }
        .onAppear { if !reduceMotion { appeared = true } }
        .accessibilityElement(children: .contain)
    }
}

/// 提醒列表的一行：前面一个彩色小标签说是什么（留意、建议、好消息、要处理）。
struct InsightRow: View {
    @Environment(LedgerModel.self) var model
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                KitTag(text: insight.kind.label, color: insight.kind.color, background: insight.kind.soft)
                Text("\(insight.author) · \(insight.createdAt.friendly)").font(.caption).foregroundStyle(Color.fg2)
                Spacer()
                if insight.dismissedAt == nil {
                    Button("知道了") { withAnimation(.snappy) { model.dismiss(insight) } }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(Color.fg2)
                } else {
                    Text("知道了").font(.caption).foregroundStyle(Color.fg3)
                }
            }
            Text(insight.title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if !insight.body.isEmpty {
                Text(insight.body).font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .opacity(insight.dismissedAt == nil ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}
