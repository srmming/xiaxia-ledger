import FinanceCore
import SwiftUI

// 总览最上面的夏夏卡片：一张说一件事，左右拖动看下一张（Mac 触控板两指左右滑，也可以点两边的箭头或下面的小圆点）。
// 先是 app 自己算的（离目标、留意、快要扣钱、夸一句，见 FinanceCore/Nudges.swift），后面是 AI 写的本月点评。

extension LedgerModel {
    /// 只在看本月时算：说的都是「接下来该做什么」。
    func overviewNudges(_ s: MonthStatus) -> [Nudge] {
        guard s.isCurrent else { return [] }
        let today = LocalDate.today
        let m = today.yearMonth
        let book = selectedBookID
        let expenses = [m, m.previous, m.previous.previous].flatMap { expenseTransactions($0, bookID: book) }
        let subs = subscriptionStatus.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        let native = nativeBalances
        return Nudges.overview(expenses: expenses, today: today, currency: ledger.baseCurrency, aim: ledger.profile.aim,
                               projectedEnd: s.projectedEnd, spentSoFar: s.spentSoFar, lastMonthSameDaySpent: s.lastMonthSameDaySpent,
                               subscriptions: subs, accountName: { self.accountName($0) }, balance: { native[$0] })
    }
}

struct XiaxiaCards: View {
    @Environment(LedgerModel.self) var model
    let nudges: [Nudge]
    let insight: Insight?
    @State private var current: String?
    /// 「知道了」：当天不再显示这一张（第二天情况变了会重新算）。存成「id@日期」一行一个。
    @AppStorage("xiaxia.nudgesDismissed") private var dismissedRaw = ""

    enum Item: Identifiable {
        case nudge(Nudge), insight(Insight)
        var id: String {
            switch self {
            case .nudge(let n): n.id
            case .insight(let i): "insight-\(i.id)"
            }
        }
    }

    var items: [Item] {
        let today = LocalDate.today.description
        let hidden = Set(dismissedRaw.split(separator: "\n").map(String.init))
        var list: [Item] = nudges.filter { !hidden.contains("\($0.id)@\(today)") }.map { .nudge($0) }
        if let insight { list.append(.insight(insight)) }
        return list
    }

    var body: some View {
        let list = items
        let index = list.firstIndex { $0.id == current } ?? 0
        VStack(spacing: 2) {
            ScrollView(.horizontal) {
                // 几张卡一样高（按最高那张），短的不会下面空一截。
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                        card(item, number: i + 1, of: list.count)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.vertical, 3).padding(.horizontal, 2)
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            if list.count > 1 {
                HStack(spacing: 14) {
                    arrow("chevron.left", label: "上一张", enabled: index > 0) { go(list, index - 1) }
                    HStack(spacing: 7) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                            Button { go(list, i) } label: {
                                Circle().fill(i == index ? Color.ai : Color.fg3.opacity(0.35))
                                    .frame(width: i == index ? 8 : 6, height: i == index ? 8 : 6)
                                    .frame(width: 14, height: 14).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("第 \(i + 1) 张")
                        }
                    }
                    arrow("chevron.right", label: "下一张", enabled: index < list.count - 1) { go(list, index + 1) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("xiaxiaCards.pager")
            }
        }
        .accessibilityIdentifier("xiaxiaCards")
    }

    private func go(_ list: [Item], _ i: Int) {
        guard list.indices.contains(i) else { return }
        withAnimation(.smooth) { current = list[i].id }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.bold)).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.ai : Color.fg3.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func card(_ item: Item, number: Int, of count: Int) -> some View {
        switch item {
        case .insight(let i): InsightCard(insight: i)
        case .nudge(let n): nudgeCard(n, number: number, of: count)
        }
    }

    private func nudgeCard(_ n: Nudge, number: Int, of count: Int) -> some View {
        AskAIReader { ask in
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label {
                            Text("夏夏 · \(n.label)")
                        } icon: {
                            MascotView(.xiaxia, size: 20, face: true, animated: false)
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ai)
                        Spacer()
                        if count > 1 { Text("\(number)/\(count)").font(.caption).foregroundStyle(Color.fg2).monospacedDigit() }
                    }
                    Text(n.title.keepingAmountsTogether).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(n.advice.keepingAmountsTogether).font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { ask(n.question, page: "总览") } label: {
                            Label(n.question, systemImage: "sparkles").lineLimit(1)
                        }
                        .buttonStyle(.softAI)
                        .accessibilityHint("问夏夏这个问题")
                        Button { dismiss(n) } label: { Text("知道了").lineLimit(1).fixedSize() }
                            .buttonStyle(.soft)
                        Spacer(minLength: 8)
                        MoreLink(title: "夏夏建议", section: .insights)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MascotView(.xiaxia, pose: pose(n), size: 80)
                    .accessibilityHidden(true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .aiCard()
        }
        .accessibilityElement(children: .contain)
    }

    private func pose(_ n: Nudge) -> MascotPose {
        switch n.kind {
        case .goal: .write
        case .unusual: .think
        case .upcoming: .worried
        case .praise: .celebrate
        }
    }

    private func dismiss(_ n: Nudge) {
        let today = LocalDate.today.description
        // 只留今天的记录，免得越存越长。
        var keep = dismissedRaw.split(separator: "\n").map(String.init).filter { $0.hasSuffix("@\(today)") }
        keep.append("\(n.id)@\(today)")
        withAnimation(.snappy) { dismissedRaw = keep.joined(separator: "\n") }
    }
}
