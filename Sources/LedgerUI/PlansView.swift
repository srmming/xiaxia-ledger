import FinanceCore
import SwiftUI

/// 计划：谁欠我钱 / 我欠谁、分期、目标和储蓄。都能在这里记。
public struct PlansView: View {
    @Environment(LedgerModel.self) private var model
    @State private var addingDebt = false
    @State private var addingInstallment = false
    @State private var addingGoal = false
    @State private var repaying: DebtStatus?
    @State private var paying: InstallmentStatus?
    @State private var depositing: GoalStatus?

    public init() {}

    public var body: some View {
        let debts = Plans.debts(model.ledger, today: .today)
        let owed = debts.filter { $0.direction == .theyOweMe }, owe = debts.filter { $0.direction == .iOweThem }
        let insts = Plans.installments(model.ledger).filter { $0.paidCount < $0.count }
        let goals = Plans.goals(model.ledger)
        List {
            Section {
                HStack {
                    total("别人欠我", owed, color: .income)
                    Divider()
                    total("我欠别人", owe, color: .primary)
                }
                Text("借出、借入、还款都不算收入或支出。").font(.caption).foregroundStyle(.secondary)
            }
            Section("谁欠我钱") { debtRows(owed); addDebtButton }
            Section("我欠谁") { debtRows(owe); addDebtButton }
            Section {
                if insts.isEmpty { Text("没有进行中的分期").foregroundStyle(.secondary) }
                ForEach(insts, id: \.id) { i in
                    Button { paying = i } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(i.name); Spacer(); Text("\(i.paidCount)/\(i.count) 期").foregroundStyle(.secondary) }
                            ProgressView(value: Double(i.paidCount), total: Double(max(i.count, 1))).tint(Color.coral)
                            Text("每期 \(i.perPayment.formatted) · 还剩 \(i.remaining.formatted) · 下次 \(i.nextDate?.short ?? "—")")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("记一期还款")
                }
                Button { addingInstallment = true } label: { Label("记一个分期", systemImage: "plus") }
            } header: { Text("分期") } footer: {
                Text("买的那天按全额算支出，之后每期还款算还债，不再算支出。点一个分期记一期还款。")
            }
            Section {
                if goals.isEmpty { Text("还没有存钱目标").foregroundStyle(.secondary) }
                ForEach(goals, id: \.id) { g in
                    Button { depositing = g } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                if g.locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                                Text(g.name); Spacer(); Text("\(g.percent)%").bold().monospacedDigit()
                            }
                            ProgressView(value: Double(g.percent), total: 100).tint(Color.income)
                            Text("\(g.saved.formatted) / \(g.target.formatted)\(g.deadline.map { " · \($0.short)前" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("存钱或取钱")
                }
                Button { addingGoal = true } label: { Label("建一个存钱目标", systemImage: "plus") }
            } header: { Text("目标和储蓄") } footer: {
                Text("存进目标的钱不算支出。锁定的目标存进去就不能取。")
            }
        }
        .navigationTitle("计划")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { addingDebt = true } label: { Label("记一笔欠款", systemImage: "person.badge.plus") }
                    Button { addingInstallment = true } label: { Label("记一个分期", systemImage: "calendar") }
                    Button { addingGoal = true } label: { Label("建一个存钱目标", systemImage: "target") }
                } label: { Text("新建计划") }
            }
        }
        .sheet(isPresented: $addingDebt) { NavigationStack { AddDebtView() }.sheetSize() }
        .sheet(isPresented: $addingInstallment) { NavigationStack { AddInstallmentView() }.sheetSize() }
        .sheet(isPresented: $addingGoal) { NavigationStack { AddGoalView() }.sheetSize() }
        .sheet(item: $paying) { i in NavigationStack { PayInstallmentView(status: i) }.sheetSize() }
        .sheet(item: $depositing) { g in NavigationStack { GoalMoneyView(status: g) }.sheetSize() }
        .sheet(item: $repaying) { d in NavigationStack { RepayView(debt: d) }.sheetSize() }
    }

    private var addDebtButton: some View {
        Button { addingDebt = true } label: { Label("记一笔欠款", systemImage: "plus") }
    }

    private func total(_ title: String, _ list: [DebtStatus], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(list.reduce(Money.zero) { $0 + $1.outstanding }.formatted)
                .font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func debtRows(_ list: [DebtStatus]) -> some View {
        if list.isEmpty {
            Text("没有").foregroundStyle(.secondary)
        }
        ForEach(list, id: \.id) { d in
            Button { repaying = d } label: {
                HStack {
                    Text(String(d.counterparty.prefix(1)))
                        .font(.subheadline.bold()).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Color.coral.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.counterparty)
                        Text("借了 \(d.principal.formatted)，已还 \(d.repaid.formatted)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(d.outstanding.formatted).monospacedDigit().bold()
                        if let due = d.dueDate {
                            Text(d.overdue ? "已过 \(due.short)" : "\(due.short)前")
                                .font(.caption).foregroundStyle(d.overdue ? Color.coral : .secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("记一笔还款")
        }
    }
}

extension DebtStatus: Identifiable {}
extension InstallmentStatus: Identifiable {}
extension GoalStatus: Identifiable {}

/// 记一笔欠款。
struct AddDebtView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var who = ""
    @State private var direction = Debt.Direction.theyOweMe
    @State private var amountText = ""
    @State private var accountID = ""
    @State private var bookID = "personal"
    @State private var date = Date()
    @State private var hasDue = false
    @State private var due = Date().addingTimeInterval(30 * 86400)
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        Form {
            Picker("方向", selection: $direction) {
                Text("别人欠我").tag(Debt.Direction.theyOweMe)
                Text("我欠别人").tag(Debt.Direction.iOweThem)
            }
            .pickerStyle(.segmented)
            Section {
                TextField("对方，如「阿华」", text: $who)
                TextField("金额", text: $amountText).decimalKeyboard().monospacedDigit()
                Picker(direction == .theyOweMe ? "钱从哪个账户出" : "钱进了哪个账户", selection: $accountID) {
                    Text("不记流水（以前的旧账）").tag("")
                    ForEach(model.visibleAccounts) { a in Text(a.name).tag(a.id) }
                }
                Picker("账本", selection: $bookID) { ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) } }
                DatePicker("哪天借的", selection: $date, displayedComponents: .date)
                Toggle("约定了还款日", isOn: $hasDue)
                if hasDue { DatePicker("哪天前还", selection: $due, displayedComponents: .date) }
                TextField("备注", text: $note)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("记一笔欠款")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(who.trimmingCharacters(in: .whitespaces).isEmpty || Money(parsing: amountText) == nil)
            }
        }
        .errorAlert($error)
    }

    private func save() {
        guard let m = Money(parsing: amountText) else { return }
        do {
            try model.edit {
                try $0.addDebt(counterparty: who.trimmingCharacters(in: .whitespaces), direction: direction, amount: m.magnitude,
                               bookID: bookID, date: LocalDate(date), accountID: accountID.isEmpty ? nil : accountID,
                               dueDate: hasDue ? LocalDate(due) : nil, note: note.isEmpty ? nil : note, author: model.author).1
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 记一笔还款。
struct RepayView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let debt: DebtStatus
    @State private var amountText = ""
    @State private var accountID = ""
    @State private var date = Date()
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(debt.direction == .theyOweMe ? "\(debt.counterparty) 还欠我" : "我还欠 \(debt.counterparty)") {
                    Text(debt.outstanding.formatted).monospacedDigit().bold()
                }
            }
            Section {
                TextField("还了多少", text: $amountText).decimalKeyboard().monospacedDigit()
                Button("全部还清") { amountText = debt.outstanding.decimalString.replacingOccurrences(of: ".", with: ",") }
                Picker(debt.direction == .theyOweMe ? "钱进了哪个账户" : "从哪个账户还", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Text(a.name).tag(a.id) }
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("记一笔还款")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(Money(parsing: amountText) == nil || accountID.isEmpty)
            }
        }
        .onAppear { if accountID.isEmpty { accountID = model.visibleAccounts.first?.id ?? "" } }
        .errorAlert($error)
    }

    private func save() {
        guard let m = Money(parsing: amountText) else { return }
        do {
            try model.edit { try $0.repay(debtID: debt.id, amount: m.magnitude, date: LocalDate(date), accountID: accountID, author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

extension View {
    func sheetSize() -> some View {
        #if os(macOS)
        frame(minWidth: 420, minHeight: 460)
        #else
        self
        #endif
    }
}
