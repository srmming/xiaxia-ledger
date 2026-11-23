import FinanceCore
import SwiftUI

/// 目标：离存钱目标还差多少？视觉重心是最快到期（或最接近完成）的目标，一个大进度环。右上角「新目标」自己登记。
/// （ming 2026-11-23：以前叫「计划」、还放着分期和借款；分期、借款搬去「欠款与分期」，这页只放存钱目标。）
struct PlansPage: View {
    @Environment(LedgerModel.self) var model
    /// iPhone 上分三格：目标 / 订阅 / 欠款（Mac 上这三个各是一页）。
    @State private var tab = 0

    var body: some View {
        #if os(iOS)
        VStack(spacing: Kit.gap) {
            Picker("看哪个", selection: $tab) {
                Text("目标").tag(0)
                Text("订阅").tag(1)
                Text("欠款").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("plansTab")
            switch tab {
            case 1:
                SubscriptionsCard()
                AskAICard(title: "让夏夏帮你找订阅", note: nil, page: "订阅",
                          prompts: [AIPrompt(kind: "订阅", text: "帮我从流水里找出所有订阅，问我哪些是，再写进夏夏账本")])
            case 2:
                DebtsPage(embedded: true)
            default:
                plans
            }
        }
        .kitPage()
        .onAppear { if model.section == .debts { tab = 2 } else if model.section == .subscriptions { tab = 1 } }
        #else
        plans.kitPage()
        #endif
    }

    @ViewBuilder private var plans: some View {
        let goals = filteredGoals
        Group {
            if goals.isEmpty {
                VStack(spacing: Kit.gap) {
                    VStack(spacing: 12) {
                        KitEmptyState(symbol: "target", title: "还没有存钱目标",
                                      message: "想为什么事存钱？旅行、换电脑、应急金……定个数，进度会画在这里。自己登记或者跟夏夏说一句都行。",
                                      prompt: "帮我建一个 2.000 € 的存钱目标，明年 6 月前存够", page: "目标")
                        newPlanButton
                    }
                    .kitCard()
                    AskAICard(title: "想定个存钱目标？", note: nil, page: "目标", prompts: model.prompts(for: .plans))
                }
            } else {
                Columns(sideWidth: 390, breakpoint: 780) {
                    HStack {
                        Text("存钱目标").font(.kitSection)
                        Spacer()
                        newPlanButton
                    }
                    if let first = goals.first { heroGoal(first) }
                    XiaxiaSays(page: "plans", pageName: "目标", sentence: xiaxia(goals: goals),
                               question: "看看我的存钱目标：照现在的速度来得及吗？要怎么调整？")
                } side: {
                    if goals.count > 1 { otherGoals(Array(goals.dropFirst())) }
                    AskAICard(title: "存钱、改目标，跟夏夏说一句", note: nil, page: "目标", prompts: Array(model.prompts(for: .plans).prefix(2)))
                }
            }
        }
    }

    /// 有截止日期的排前面（越早越前），再按完成度。
    private var filteredGoals: [GoalStatus] {
        Plans.goals(model.ledger)
            .filter { g in model.selectedBookID == nil || model.ledger.goals.first { $0.id == g.id }?.bookID == model.selectedBookID }
            .sorted { a, b in
                switch (a.deadline, b.deadline) {
                case let (x?, y?): return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.percent > b.percent
                }
            }
    }

    private func heroGoal(_ g: GoalStatus) -> some View {
        let left = g.target - g.saved
        var sentence = left.cents <= 0 ? Text("已经存够了。") : Text("还差 ") + em(left.rounded) + Text("。")
        if left.cents > 0, let due = g.deadline {
            let months = max(1, (due.year - LocalDate.today.year) * 12 + due.month - LocalDate.today.month)
            let perMonth = Money(cents: left.cents / Int64(months))
            sentence = sentence + Text(verbatim: "要在 \(due.year) 年 \(due.month) 月前存够，每月存 \(perMonth.rounded) 就行。")
        }
        return HStack(alignment: .center, spacing: 24) {
            GoalRing(fraction: Double(g.percent) / 100)
                .frame(width: ringSize, height: ringSize)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(g.name).font(.caption).foregroundStyle(Color.fg2)
                    Spacer()
                    PlanRowMenu(target: .goal(g.id), name: g.name)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(g.saved.rounded).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("/ " + g.target.rounded).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Color.fg3)
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(g.saved.rounded).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().fixedSize()
                        Text("/ " + g.target.rounded).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(Color.fg3)
                    }
                }
                sentence.font(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
        .kitCard(padding: 20)
        .accessibilityElement(children: .contain)
    }

    private var newPlanButton: some View {
        Button { model.sheet = .plan } label: { Label("新目标", systemImage: "plus") }
            .buttonStyle(.soft)
            .help("登记一个存钱目标")
    }

    /// 夏夏先说的一句：最该先看的目标来不来得及。
    private func xiaxia(goals: [GoalStatus]) -> String {
        guard let g = goals.first else { return model.voiced("还没有存钱目标，定一个吧。", .neutral) }
        let left = g.target - g.saved
        if left.cents <= 0 { return model.voiced("「\(g.name)」已经存够了。", .good) }
        if let due = g.deadline {
            let months = max(1, (due.year - LocalDate.today.year) * 12 + due.month - LocalDate.today.month)
            return model.voiced("「\(g.name)」还差 \(left.rounded)，要在 \(due.year) 年 \(due.month) 月前存够，每月得存 \(Money(cents: left.cents / Int64(months)).rounded)。", .neutral)
        }
        return model.voiced("「\(g.name)」还差 \(left.rounded)，已经存了 \(g.percent)%。", .neutral)
    }

    private var ringSize: CGFloat {
        #if os(iOS)
        116
        #else
        150
        #endif
    }

    private func otherGoals(_ goals: [GoalStatus]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("其它目标")
            ForEach(goals, id: \.id) { g in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(g.name).font(.callout)
                        Spacer()
                        Text("\(g.saved.rounded) / \(g.target.rounded)").font(.kitAmount)
                        PlanRowMenu(target: .goal(g.id), name: g.name)
                    }
                    Bar(fraction: Double(g.percent) / 100, color: Color.kit(0x0EA5E9, 0x38BDF8), height: 6)
                    Text(goalNote(g)).font(.caption).foregroundStyle(Color.fg2)
                }
                .accessibilityElement(children: .contain)
            }
        }
        .kitCard()
    }

    private func goalNote(_ g: GoalStatus) -> String {
        var parts: [String] = []
        if let book = model.ledger.goals.first(where: { $0.id == g.id })?.bookID, model.ledger.books.count > 1 { parts.append(model.bookName(book)) }
        if let due = g.deadline { parts.append("\(due.year) 年 \(due.month) 月前") }
        let left = g.target - g.saved
        parts.append(left.cents > 0 ? "还差 \(left.rounded)" : "已存够")
        return parts.joined(separator: " · ")
    }
}
