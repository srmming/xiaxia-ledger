import FinanceCore
import SwiftUI

/// 欠款与分期：我还欠多少、别人欠我多少？（ming 2026-11-23 从「计划」里拆出来单独一页。）
/// 视觉重心是顶上两个数；下面左边分期、右边借款往来（我欠的 / 欠我的）。这些都已经算进家底。
struct DebtsPage: View {
    @Environment(LedgerModel.self) var model
    /// iPhone 的「计划」标签里也用这一页，那里外面已经有滚动了。
    var embedded = false

    var body: some View {
        if embedded { content } else { content.kitPage() }
    }

    @ViewBuilder private var content: some View {
        let installments = filteredInstallments
        let debts = filteredDebts
        if installments.isEmpty && debts.isEmpty {
            VStack(spacing: Kit.gap) {
                VStack(spacing: 12) {
                    KitEmptyState(symbol: "arrow.left.arrow.right", title: "没有欠款，也没有分期",
                                  message: "借钱给别人、跟别人借钱、分期买东西，登记一下就会算进家底，还到哪一期也看得清。",
                                  prompt: "帮我记一笔欠款：朋友借了我 300 €，下个月还", page: "欠款与分期")
                    addButtons
                }
                .kitCard()
                AskAICard(title: "跟夏夏说一句也能记", note: nil, page: "欠款与分期", prompts: model.prompts(for: .debts))
            }
        } else {
            // ming 2026-11-23：分期没还完的也是欠款。按「我欠的 / 欠我的」分两边，分期和借来的钱放在一起。
            VStack(alignment: .leading, spacing: Kit.gap) {
                totalsCard(installments: installments, debts: debts)
                Columns(sideWidth: 320, breakpoint: 640) {
                    iOweCard(installments: installments, borrowed: debts.filter { $0.direction == .iOweThem })
                } side: {
                    owedToMeCard(debts.filter { $0.direction == .theyOweMe })
                }
            }
        }
    }

    private var filteredInstallments: [InstallmentStatus] {
        Plans.installments(model.ledger).filter { i in
            i.remaining.cents > 0 && (model.selectedBookID == nil || model.ledger.installments.first { $0.id == i.id }?.bookID == model.selectedBookID)
        }
    }

    private var filteredDebts: [DebtStatus] {
        Plans.debts(model.ledger, today: .today).filter { d in
            model.selectedBookID == nil || model.ledger.debts.first { $0.id == d.id }?.bookID == model.selectedBookID
        }
    }

    // MARK: 顶上两个数

    private func totalsCard(installments: [InstallmentStatus], debts: [DebtStatus]) -> some View {
        let o = Plans.obligations(model.ledger, asOf: .today, bookID: model.selectedBookID)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 36) { figures(o) }
                    VStack(alignment: .leading, spacing: 10) { figures(o) }
                }
                Spacer(minLength: 12)
                addButtons
            }
            nextLine(installments: installments, debts: debts)
                .font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .kitCard(padding: 20)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func figures(_ o: Obligations) -> some View {
        figure("我还欠", o.iOwe, note: oweNote(o), color: o.iOwe.cents > 0 ? .primary : .fg2)
        figure("别人欠我", o.owedToMe, note: "借出去还没收回", color: o.owedToMe.cents > 0 ? .income : .fg2)
    }

    /// 「分期 989 € + 借款 250 €」：我还欠的是哪几块。
    private func oweNote(_ o: Obligations) -> String {
        var parts: [String] = []
        if o.installments.cents > 0 { parts.append("分期 \(o.installments.rounded)") }
        if o.borrowed.cents > 0 { parts.append("借款 \(o.borrowed.rounded)") }
        return parts.isEmpty ? "什么都不欠" : parts.joined(separator: " + ")
    }

    private func figure(_ label: String, _ money: Money, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Color.fg2)
            Text(money.rounded)
                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(money.cents)))
            Text(note).font(.caption).foregroundStyle(Color.fg3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(money.spoken)")
    }

    /// 一句话：最先要处理的那件事（过期没还的借款 → 最近一期分期 → 最早到期的借款），后面说一句已经算进家底。
    private func nextLine(installments: [InstallmentStatus], debts: [DebtStatus]) -> Text {
        var t: Text
        if let late = debts.filter(\.overdue).sorted(by: { ($0.dueDate ?? .today) < ($1.dueDate ?? .today) }).first, let due = late.dueDate {
            t = late.direction == .theyOweMe
                ? Text("\(late.counterparty)的 ") + em(late.outstanding.rounded, .bad) + Text(" 本该 \(due.short) 还，可以提醒一下。")
                : Text("欠\(late.counterparty)的 ") + em(late.outstanding.rounded, .bad) + Text(" 本该 \(due.short) 还，记得还上。")
        } else if let next = installments.compactMap({ i in i.nextDate.map { (i, $0) } }).min(by: { $0.1 < $1.1 }) {
            let days = LocalDate.today.days(until: next.1)
            t = Text("下一笔：「\(next.0.name)」\(days >= 0 && days <= 2 ? Nudges.dayWord(days) : next.1.short)扣 ") + em(next.0.perPayment.rounded) + Text("。")
        } else if let soon = debts.filter({ $0.dueDate != nil }).min(by: { $0.dueDate! < $1.dueDate! }), let due = soon.dueDate {
            t = Text(soon.direction == .theyOweMe ? "\(soon.counterparty)说好 \(due.short) 前还你 " : "欠\(soon.counterparty)的要在 \(due.short) 前还 ")
                + em(soon.outstanding.rounded) + Text("。")
        } else {
            t = Text("")
        }
        return t + Text(" 这些已经算进家底了。").foregroundColor(.fg2)
    }

    private var addButtons: some View {
        HStack(spacing: 8) {
            Button { model.sheet = .newInstallment } label: { Label("记分期", systemImage: "plus") }
                .buttonStyle(.soft)
                .help("登记一笔分期：手机、家电、店里的设备")
            Button { model.sheet = .newDebt } label: { Label("记借款", systemImage: "plus") }
                .buttonStyle(.soft)
                .help("登记谁欠谁：借给别人或跟别人借")
        }
    }

    // MARK: 我欠的（分期 + 借来的）

    private func iOweCard(installments: [InstallmentStatus], borrowed: [DebtStatus]) -> some View {
        let total = installments.reduce(Money.zero) { $0 + $1.remaining } + borrowed.reduce(Money.zero) { $0 + $1.outstanding }
        return VStack(alignment: .leading, spacing: 4) {
            header("我欠的", total)
            if installments.isEmpty && borrowed.isEmpty {
                Text("什么都不欠。分期买东西点「记分期」，跟别人借钱点「记借款」。")
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(installments, id: \.id) { i in
                installmentRow(i)
                if i.id != installments.last?.id || !borrowed.isEmpty { Divider().padding(.leading, 44) }
            }
            ForEach(borrowed, id: \.id) { d in
                debtRow(d)
                if d.id != borrowed.last?.id { Divider().padding(.leading, 42) }
            }
        }
        .kitCard()
    }

    private func installmentRow(_ i: InstallmentStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: "分期", size: 32)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(i.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text("分期").font(.caption2.weight(.semibold)).foregroundStyle(Color.fg2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.sunken, in: Capsule())
                    Spacer()
                    Text("还剩 \(i.remaining.rounded)").font(.kitAmount)
                    PlanRowMenu(target: .installment(i.id), name: i.name)
                }
                SegmentedProgress(done: i.paidCount, total: i.count)
                Text(installmentNote(i)).font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func installmentNote(_ i: InstallmentStatus) -> String {
        var parts = ["第 \(i.paidCount) / \(i.count) 期", "每期 \(i.perPayment.ui)"]
        if let next = i.nextDate { parts.append("下一期 \(next.short)") }
        if let book = model.ledger.installments.first(where: { $0.id == i.id })?.bookID, model.ledger.books.count > 1, model.selectedBookID == nil {
            parts.append(model.bookName(book))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 欠我的

    private func owedToMeCard(_ list: [DebtStatus]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header("欠我的", list.reduce(Money.zero) { $0 + $1.outstanding })
            if list.isEmpty {
                Text("没有借出去还没收回的钱。借给别人时点「记借款」。")
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(list, id: \.id) { d in
                debtRow(d)
                if d.id != list.last?.id { Divider().padding(.leading, 42) }
            }
        }
        .kitCard()
    }

    private func header(_ title: String, _ total: Money) -> some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(title)
            Spacer()
            if total.cents > 0 {
                Text(total.rounded).font(.callout.weight(.semibold)).foregroundStyle(Color.fg2).monospacedDigit()
            }
        }
        .padding(.bottom, 2)
    }

    private func debtRow(_ d: DebtStatus) -> some View {
        HStack(spacing: 6) {
            DebtRow(debt: d)
            PlanRowMenu(target: .debt(d.id), name: d.counterparty)
        }
    }
}
