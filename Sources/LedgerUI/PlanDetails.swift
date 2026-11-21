import FinanceCore
import SwiftUI

/// 一笔借款：还欠多少、每次还款的记录；能记还款、改约定日期、算了不用还、删掉。
struct DebtDetailView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var repaying: DebtStatus?
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        let status = Plans.debts(model.ledger, today: .today, includeClosed: true).first { $0.id == id }
        let debt = model.ledger.debts.first { $0.id == id }
        Group {
            if let status, let debt {
                let ids = Set(model.ledger.debtTransactionIDs(id))
                let history = model.ledger.transactions.filter { ids.contains($0.id) }.sorted { $0.date > $1.date }
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(status.direction == .theyOweMe ? "\(status.counterparty) 还欠我" : "我还欠 \(status.counterparty)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            BigAmount(money: status.outstanding, size: 32)
                            Bar(fraction: Double(status.repaid.cents) / Double(max(status.principal.cents, 1)), color: .income, height: 8)
                            Text("一共 \(status.principal.formatted)，已还 \(status.repaid.formatted)").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        if status.outstanding.cents > 0 {
                            Button { repaying = status } label: { Label("记一笔还款", systemImage: "plus.circle.fill") }
                        }
                    }
                    Section("约定") {
                        LabeledContent("哪天借的", value: debt.startDate.friendly)
                        LabeledContent("哪天前还") {
                            Text(debt.dueDate?.friendly ?? "没约定").foregroundStyle(status.overdue ? Color.coral : .primary)
                        }
                        LabeledContent("账本", value: model.bookName(debt.bookID))
                        if let note = debt.note, !note.isEmpty { LabeledContent("备注", value: note) }
                        Button("改名字、还款日、备注") { editing = true }
                    }
                    Section("每一笔记录") {
                        if history.isEmpty { Text("还没有流水记录（这是以前的旧账）。").foregroundStyle(.secondary) }
                        ForEach(history) { t in TransactionRow(tx: t, showDate: true) }
                    }
                    Section {
                        if debt.closed {
                            Button("重新打开这笔借款") { toggleClosed(debt) }
                        } else if status.outstanding.cents > 0 {
                            Button(status.direction == .theyOweMe ? "剩下的不用还了，结清" : "对方说不用还了，结清") { toggleClosed(debt) }
                        }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("删掉这笔借款", systemImage: "trash") }
                    } footer: { Text("删掉会连同它的借出、还款流水一起删，账户余额会变回去。删错了能撤销。") }
                }
                .formStyle(.grouped)
                .navigationTitle(status.counterparty)
            } else {
                ContentUnavailableView("这笔借款已经删掉了", systemImage: "person.2")
            }
        }
        .inlineTitle()
        .sheet(item: $repaying) { d in NavigationStack { RepayView(debt: d) }.sheetSize() }
        .sheet(isPresented: $editing) {
            if let debt { NavigationStack { EditDebtView(debt: debt) }.sheetSize(height: 380) }
        }
        .confirmationDialog("删掉和「\(debt?.counterparty ?? "")」的这笔借款？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                model.perform { try $0.removeDebt(id, author: model.author) }
                dismiss()
            }
        }
    }

    private func toggleClosed(_ debt: Debt) {
        var d = debt
        d.closed.toggle()
        model.perform { try $0.updateDebt(d, author: model.author) }
    }
}

struct EditDebtView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let debt: Debt
    @State private var who = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var note = ""

    var body: some View {
        Form {
            PromptField("对方", text: $who)
            Toggle("约好了哪天前还", isOn: $hasDue.animation())
            if hasDue { DatePicker("哪天前还", selection: $due, displayedComponents: .date) }
            PromptField("备注", text: $note)
        }
        .formStyle(.grouped)
        .navigationTitle("改借款")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    var d = debt
                    d.counterparty = who.trimmingCharacters(in: .whitespaces)
                    d.dueDate = hasDue ? LocalDate(due) : nil
                    d.note = note.isEmpty ? nil : note
                    if d != debt { model.perform { try $0.updateDebt(d, author: model.author) } }
                    dismiss()
                }
                .disabled(who.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            who = debt.counterparty; note = debt.note ?? ""
            hasDue = debt.dueDate != nil
            due = debt.dueDate?.asDate ?? Date().addingTimeInterval(30 * 86400)
        }
    }
}

/// 一个分期：每一期哪天扣、扣了没有；能记一期、删掉。
struct InstallmentDetailView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var paying: InstallmentStatus?
    @State private var confirmDelete = false

    var body: some View {
        let status = Plans.installments(model.ledger).first { $0.id == id }
        let inst = model.ledger.installments.first { $0.id == id }
        Group {
            if let status, let inst {
                let paid = inst.paidIDs.compactMap { model.transaction($0) }.sorted { $0.date < $1.date }
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("还剩").font(.subheadline).foregroundStyle(.secondary)
                            BigAmount(money: status.remaining, size: 32)
                            Bar(fraction: Double(status.paidCount) / Double(max(status.count, 1)), height: 8)
                            Text("总价 \(inst.total.formatted)，分 \(inst.count) 期，每期 \(status.perPayment.formatted)，已还 \(status.paidCount) 期")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        if status.paidCount < status.count {
                            Button { paying = status } label: { Label("记第 \(status.paidCount + 1) 期还款", systemImage: "plus.circle.fill") }
                        }
                        LabeledContent("从哪扣", value: "\(model.accountName(inst.accountID)) · \(model.bookName(inst.bookID))")
                    }
                    Section("每一期") {
                        ForEach(0..<inst.count, id: \.self) { k in
                            HStack {
                                Image(systemName: k < paid.count ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(k < paid.count ? Color.income : Color.secondary)
                                Text("第 \(k + 1) 期")
                                Spacer()
                                if k < paid.count {
                                    Text("\(paid[k].date.friendly) · \(paid[k].amount.magnitude.formatted)").foregroundStyle(.secondary).monospacedDigit()
                                } else {
                                    Text("\(dueDate(inst, k).friendly) · \(status.perPayment.formatted)").monospacedDigit()
                                        .foregroundStyle(dueDate(inst, k) < LocalDate.today ? Color.coral : .secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("删掉这个分期", systemImage: "trash") }
                    } footer: { Text("删掉会连同买的那笔支出和每期还款一起删。删错了能撤销。") }
                }
                .formStyle(.grouped)
                .navigationTitle(status.name)
            } else {
                ContentUnavailableView("这个分期已经删掉了", systemImage: "calendar")
            }
        }
        .inlineTitle()
        .sheet(item: $paying) { i in NavigationStack { PayInstallmentView(status: i) }.sheetSize() }
        .confirmationDialog("删掉分期「\(inst?.name ?? "")」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                model.perform { try $0.removeInstallment(id, author: model.author) }
                dismiss()
            }
        }
    }

    private func dueDate(_ inst: Installment, _ k: Int) -> LocalDate {
        let m = inst.firstDate.yearMonth.adding(months: k)
        return LocalDate(year: m.year, month: m.month, day: min(inst.firstDate.day, 28))
    }
}

/// 一个存钱目标：存了多少、每月要存多少才来得及、每次存取记录；能存、取、改、删。
struct GoalDetailView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var moving: GoalStatus?
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        let status = Plans.goals(model.ledger).first { $0.id == id }
        let goal = model.ledger.goals.first { $0.id == id }
        Group {
            if let status, let goal {
                let history = self.history(goal)
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("已经存了").font(.subheadline).foregroundStyle(.secondary)
                                if goal.locked { Label("锁定", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                            }
                            BigAmount(money: status.saved, size: 32)
                            Bar(fraction: Double(status.percent) / 100, color: .income, height: 8)
                            Text("目标 \(status.target.formatted)，完成 \(status.percent)%").font(.caption).foregroundStyle(.secondary)
                            if let hint = pace(status) { Text(hint).font(.footnote) }
                        }
                        .padding(.vertical, 4)
                        Button { moving = status } label: { Label(goal.locked ? "存钱" : "存钱或取钱", systemImage: "plus.circle.fill") }
                    }
                    Section("设定") {
                        LabeledContent("钱放在哪", value: goal.savingsAccountID.map { model.accountName($0) } ?? "平时的账户里，记个数")
                        LabeledContent("哪天前存够", value: goal.deadline?.friendly ?? "没设截止日")
                        LabeledContent("账本", value: model.bookName(goal.bookID))
                        Button("改名字、金额、日期") { editing = true }
                    }
                    Section("每一次存取") {
                        if history.isEmpty { Text("还没存过。").foregroundStyle(.secondary) }
                        ForEach(history) { t in TransactionRow(tx: t, showDate: true) }
                    }
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("删掉这个目标", systemImage: "trash") }
                    } footer: {
                        Text(goal.savingsAccountID == nil ? "删掉后，记在这个目标名下的钱变回普通余额，账户里的钱不会少。删错了能撤销。"
                             : "只删目标，储蓄账户和里面的钱不动。删错了能撤销。")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(status.name)
            } else {
                ContentUnavailableView("这个目标已经删掉了", systemImage: "target")
            }
        }
        .inlineTitle()
        .sheet(item: $moving) { g in NavigationStack { GoalMoneyView(status: g) }.sheetSize() }
        .sheet(isPresented: $editing) {
            if let goal { NavigationStack { AddGoalView(editing: goal) }.sheetSize() }
        }
        .confirmationDialog("删掉目标「\(goal?.name ?? "")」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                model.perform { try $0.removeGoal(id, author: model.author) }
                dismiss()
            }
        }
    }

    private func history(_ goal: Goal) -> [Transaction] {
        if let account = goal.savingsAccountID {
            return model.ledger.transactions.filter { $0.accountID == account }.sorted { $0.date > $1.date }
        }
        let ids = Set(goal.contributionIDs)
        return model.ledger.transactions.filter { ids.contains($0.id) }.sorted { $0.date > $1.date }
    }

    /// 「还差 3.000 €，离 6 月 30 日还有 7 个月，每月存 428,57 € 就够。」
    private func pace(_ s: GoalStatus) -> String? {
        let left = s.target.cents - s.saved.cents
        if left <= 0 { return "已经存够了。" }
        guard let deadline = s.deadline else { return "还差 \(Money(cents: left).formatted)。" }
        let days = deadline.daysFromToday
        if days < 0 { return "已经过了 \(deadline.friendly)，还差 \(Money(cents: left).formatted)。" }
        let months = max(1, Int((Double(days) / 30.4).rounded(.up)))
        return "还差 \(Money(cents: left).formatted)，还有 \(months) 个月，每月存 \(Money(cents: left / Int64(months)).formatted) 就够。"
    }
}
