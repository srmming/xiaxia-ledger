import FinanceCore
import SwiftUI

/// 计划：谁欠我钱 / 我欠谁、分期、存钱目标。点一项进去看每一笔记录，能记还款、改、删。
public struct PlansView: View {
    @Environment(LedgerModel.self) private var model
    @State private var showClosed = false

    public init() {}

    public var body: some View {
        let all = Plans.debts(model.ledger, today: .today, includeClosed: true)
        let open = all.filter { $0.outstanding.cents > 0 }
        let closed = all.filter { $0.outstanding.cents == 0 }
        let owed = open.filter { $0.direction == .theyOweMe }, owe = open.filter { $0.direction == .iOweThem }
        let insts = Plans.installments(model.ledger)
        let running = insts.filter { $0.paidCount < $0.count }, finished = insts.filter { $0.paidCount >= $0.count }
        let goals = Plans.goals(model.ledger)
        List {
            Section {
                HStack {
                    total("别人欠我", owed, color: .income)
                    Divider()
                    total("我欠别人", owe, color: .primary)
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("分期还剩").font(.subheadline).foregroundStyle(.secondary)
                        Text(running.reduce(Money.zero) { $0 + $1.remaining }.formatted)
                            .font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                            .minimumScaleFactor(0.6).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("借出、借入、还款、分期还款、存进目标的钱，都不算收入或支出。")
            }

            Section {
                if owed.isEmpty { Text("现在没人欠你钱。").foregroundStyle(.secondary) }
                ForEach(owed, id: \.id) { debtLink($0) }
            } header: {
                header("谁欠我钱", add: "借出去一笔") { model.sheet = .addDebt(.theyOweMe) }
            }

            Section {
                if owe.isEmpty { Text("你现在不欠别人钱。").foregroundStyle(.secondary) }
                ForEach(owe, id: \.id) { debtLink($0) }
            } header: {
                header("我欠谁", add: "借进来一笔") { model.sheet = .addDebt(.iOweThem) }
            }

            Section {
                if running.isEmpty { Text("没有进行中的分期。").foregroundStyle(.secondary) }
                ForEach(running, id: \.id) { i in
                    NavigationLink { InstallmentDetailView(id: i.id) } label: { installmentRow(i) }
                }
            } header: {
                header("分期", add: "记一个分期") { model.sheet = .addInstallment }
            } footer: {
                Text("买的那天按全额算支出，之后每期还款算还债，不再算支出。")
            }

            Section {
                if goals.isEmpty { Text("还没有存钱目标。比如「应急金 6.000 €」「回国机票」。").foregroundStyle(.secondary) }
                ForEach(goals, id: \.id) { g in
                    NavigationLink { GoalDetailView(id: g.id) } label: { goalRow(g) }
                }
            } header: {
                header("存钱目标", add: "建一个目标") { model.sheet = .addGoal }
            }

            if !closed.isEmpty || !finished.isEmpty {
                Section {
                    DisclosureGroup("已经结清的（\(closed.count + finished.count)）", isExpanded: $showClosed) {
                        ForEach(closed, id: \.id) { debtLink($0) }
                        ForEach(finished, id: \.id) { i in
                            NavigationLink { InstallmentDetailView(id: i.id) } label: { installmentRow(i) }
                        }
                    }
                }
            }
        }
        .navigationTitle("计划")
        #if os(iOS)
        .contentMargins(.bottom, 40, for: .scrollContent)
        #endif
    }

    private func header(_ title: String, add: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) { Label(add, systemImage: "plus").font(.subheadline) }
                .buttonStyle(.borderless)
                .textCase(nil)
        }
    }

    private func total(_ title: String, _ list: [DebtStatus], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(list.reduce(Money.zero) { $0 + $1.outstanding }.formatted)
                .font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(color)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func debtLink(_ d: DebtStatus) -> some View {
        NavigationLink { DebtDetailView(id: d.id) } label: {
            HStack {
                Text(String(d.counterparty.prefix(1)))
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(d.outstanding.cents == 0 ? AnyShapeStyle(Color.gray.gradient) : AnyShapeStyle(Color.coral.gradient), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.counterparty)
                    Text("借了 \(d.principal.formatted)，已还 \(d.repaid.formatted)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if d.outstanding.cents == 0 {
                        Text("已结清").foregroundStyle(.secondary)
                    } else {
                        Text(d.outstanding.formatted).monospacedDigit().bold()
                        if let due = d.dueDate {
                            Text(d.overdue ? "已过 \(due.short)" : "\(due.friendly)前")
                                .font(.caption).foregroundStyle(d.overdue ? Color.coral : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func installmentRow(_ i: InstallmentStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(i.name); Spacer(); Text("\(i.paidCount)/\(i.count) 期").foregroundStyle(.secondary) }
            Bar(fraction: Double(i.paidCount) / Double(max(i.count, 1)))
            Text(i.paidCount >= i.count ? "已经还完" : "每期 \(i.perPayment.formatted) · 还剩 \(i.remaining.formatted) · 下次 \(i.nextDate?.friendly ?? "—")")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func goalRow(_ g: GoalStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if g.locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                Text(g.name); Spacer(); Text("\(g.percent)%").bold().monospacedDigit()
            }
            Bar(fraction: Double(g.percent) / 100, color: .income)
            Text("\(g.saved.formatted) / \(g.target.formatted)\(g.deadline.map { " · \($0.friendly)前" } ?? "")")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

extension DebtStatus: Identifiable {}
extension InstallmentStatus: Identifiable {}
extension GoalStatus: Identifiable {}
