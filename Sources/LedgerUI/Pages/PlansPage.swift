import FinanceCore
import SwiftUI

/// 计划：离目标还差多少？视觉重心是最快到期（或最接近完成）的目标，一个大进度环。
struct PlansPage: View {
    @Environment(LedgerModel.self) var model

    var body: some View {
        let goals = filteredGoals
        let installments = Plans.installments(model.ledger).filter { i in
            model.selectedBookID == nil || model.ledger.installments.first { $0.id == i.id }?.bookID == model.selectedBookID
        }
        let debts = Plans.debts(model.ledger, today: .today).filter { d in
            model.selectedBookID == nil || model.ledger.debts.first { $0.id == d.id }?.bookID == model.selectedBookID
        }
        Group {
            if goals.isEmpty && installments.isEmpty && debts.isEmpty {
                VStack(spacing: Kit.gap) {
                    KitEmptyState(symbol: "target", title: "还没有计划",
                                  message: "存钱目标、分期、谁欠谁，都跟 AI 说一句就建好，进度会画在这里。",
                                  prompt: "帮我建一个 2.000 € 的存钱目标，明年 6 月前存够", page: "计划")
                        .kitCard()
                    AskAICard(title: "想加目标、记欠款、记分期？", note: nil, page: "计划", prompts: model.prompts(for: .plans))
                }
            } else {
                Columns(sideWidth: 390, breakpoint: 780) {
                    if let first = goals.first { heroGoal(first) }
                    if goals.count > 1 { otherGoals(Array(goals.dropFirst())) }
                } side: {
                    if !installments.isEmpty { installmentsCard(installments) }
                    if !debts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader("借款往来").padding(.bottom, 6)
                            ForEach(debts, id: \.id) { d in
                                DebtRow(debt: d)
                                if d.id != debts.last?.id { Divider().padding(.leading, 42) }
                            }
                        }
                        .kitCard()
                    }
                    AskAICard(title: "想加目标、记欠款、记分期？", note: nil, page: "计划", prompts: Array(model.prompts(for: .plans).prefix(2)))
                }
            }
        }
        .kitPage()
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
                Text(g.name).font(.caption).foregroundStyle(Color.fg2)
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
        .accessibilityElement(children: .combine)
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
                    }
                    Bar(fraction: Double(g.percent) / 100, color: Color.kit(0x0EA5E9, 0x38BDF8), height: 6)
                    Text(goalNote(g)).font(.caption).foregroundStyle(Color.fg2)
                }
                .accessibilityElement(children: .combine)
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

    private func installmentsCard(_ list: [InstallmentStatus]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("分期")
            ForEach(list, id: \.id) { i in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(i.name).font(.callout).lineLimit(1)
                        Spacer()
                        Text("第 \(i.paidCount) / \(i.count) 期").font(.caption).foregroundStyle(Color.fg2).monospacedDigit()
                    }
                    SegmentedProgress(done: i.paidCount, total: i.count)
                    Text("每期 \(i.perPayment.formatted)" + (i.nextDate.map { " · 下一期 \($0.short)" } ?? " · 已还完"))
                        .font(.caption).foregroundStyle(Color.fg2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kitCard()
    }
}
