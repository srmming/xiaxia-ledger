import FinanceCore
import SwiftUI

/// 记一笔欠款：借出去（别人欠我）或借进来（我欠别人）。
struct AddDebtView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var who = ""
    @State private var direction: Debt.Direction
    @State private var amountText = ""
    @State private var accountID = ""
    @State private var bookID = ""
    @State private var date = Date()
    @State private var hasDue = false
    @State private var due = Date().addingTimeInterval(30 * 86400)
    @State private var note = ""
    @State private var error: String?
    @FocusState private var whoFocused: Bool

    init(direction: Debt.Direction = .theyOweMe) { _direction = State(initialValue: direction) }

    private var amount: Money? { Money(parsing: amountText).flatMap { $0.cents != 0 ? $0.magnitude : nil } }

    /// 以前借过钱的人，点一下就填上名字。
    private var people: [String] {
        var seen: [String] = []
        for d in model.ledger.debts.reversed() where !seen.contains(d.counterparty) { seen.append(d.counterparty) }
        return Array(seen.prefix(6))
    }

    var body: some View {
        Form {
            Section {
                Picker("方向", selection: $direction.animation(.snappy)) {
                    Text("我借给别人").tag(Debt.Direction.theyOweMe)
                    Text("我向别人借").tag(Debt.Direction.iOweThem)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                AmountField(prompt: "0,00", text: $amountText)
                TextField(direction == .theyOweMe ? "借给谁，如「阿华」" : "向谁借，如「妈妈」", text: $who)
                    .focused($whoFocused)
                if !people.isEmpty, who.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(people, id: \.self) { p in Button(p) { who = p }.buttonStyle(.bordered).controlSize(.small) } }
                    }
                }
            }
            Section {
                Picker(direction == .theyOweMe ? "钱从哪个账户出" : "钱进了哪个账户", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Text(a.name).tag(a.id) }
                    Divider()
                    Text("以前的旧账，不动账户余额").tag("")
                }
                Picker("账本", selection: $bookID) { ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) } }
                DatePicker("哪天借的", selection: $date, displayedComponents: .date)
                Toggle("约好了哪天前还", isOn: $hasDue.animation())
                if hasDue { DatePicker("哪天前还", selection: $due, displayedComponents: .date) }
                TextField("备注（可以不写）", text: $note)
            } footer: {
                Text(direction == .theyOweMe
                     ? "保存后，「\(accountID.isEmpty ? "账户" : model.accountName(accountID))」会少这么多钱，但不算支出。对方还钱时到「计划」里点这笔，记一笔还款。"
                     : "保存后，账户里会多这么多钱，但不算收入。还钱时到「计划」里点这笔，记一笔还款。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("记一笔欠款")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(who.trimmingCharacters(in: .whitespaces).isEmpty || amount == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            if bookID.isEmpty { bookID = model.selectedBookID ?? model.ledger.books.first?.id ?? "" }
            if accountID.isEmpty { accountID = model.defaultAccountID }
        }
        .errorAlert($error)
    }

    private func save() {
        guard let m = amount else { return }
        do {
            try model.edit {
                try $0.addDebt(counterparty: who.trimmingCharacters(in: .whitespaces), direction: direction, amount: m,
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

    private var amount: Money? { Money(parsing: amountText).flatMap { $0.cents != 0 ? $0.magnitude : nil } }

    var body: some View {
        Form {
            Section {
                LabeledContent(debt.direction == .theyOweMe ? "\(debt.counterparty) 还欠我" : "我还欠 \(debt.counterparty)") {
                    Text(debt.outstanding.formatted).monospacedDigit().bold()
                }
            }
            Section {
                AmountField(prompt: debt.outstanding.inputText, text: $amountText)
                HStack {
                    Button("全部还清") { amountText = debt.outstanding.inputText }
                    Button("还一半") { amountText = Money(cents: debt.outstanding.cents / 2).inputText }
                }
                .buttonStyle(.bordered).controlSize(.small)
                Picker(debt.direction == .theyOweMe ? "钱进了哪个账户" : "从哪个账户还", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Text(a.name).tag(a.id) }
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
            } footer: {
                if let a = amount, a > debt.outstanding {
                    Text("比还欠的多了 \((a - debt.outstanding).formatted)，多出来的也会记上。").foregroundStyle(Color.coral)
                } else if let a = amount {
                    Text("记完还欠 \((debt.outstanding - a).formatted)。")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("记一笔还款")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(amount == nil || accountID.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { if accountID.isEmpty { accountID = model.defaultAccountID } }
        .errorAlert($error)
    }

    private func save() {
        guard let m = amount else { return }
        do {
            try model.edit { try $0.repay(debtID: debt.id, amount: m, date: LocalDate(date), accountID: accountID, author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 记一个分期：买的那天按全额算支出。
struct AddInstallmentView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var totalText = ""
    @State private var count = 6
    @State private var feeText = ""
    @State private var accountID = ""
    @State private var bookID = ""
    @State private var category = ""
    @State private var buyDate = Date()
    @State private var firstDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var error: String?

    private var total: Money? { Money(parsing: totalText).flatMap { $0.cents != 0 ? $0.magnitude : nil } }

    var body: some View {
        Form {
            Section {
                TextField("买了什么，如「美甲灯」「iPhone」", text: $name)
                AmountField(prompt: "总价", text: $totalText)
                Stepper("分 \(count) 期", value: $count, in: 2...60)
                if let t = total {
                    LabeledContent("每期大约", value: Money(cents: t.cents / Int64(count)).formatted)
                }
                TextField("手续费或利息一共多少（没有就空着）", text: $feeText).decimalKeyboard().monospacedDigit()
            }
            Section {
                Picker("从哪个账户扣", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Text(a.name).tag(a.id) }
                }
                Picker("账本", selection: $bookID.animation(.snappy)) { ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) } }
                DatePicker("哪天买的", selection: $buyDate, displayedComponents: .date)
                DatePicker("第一期哪天扣", selection: $firstDate, displayedComponents: .date)
            }
            Section {
                CategoryChips(categories: model.categories(bookID: bookID.isEmpty ? nil : bookID, income: false, limit: 10), selection: $category)
                    .padding(.vertical, 4)
                TextField("别的分类，自己写", text: $category)
            } header: { Text("分类") } footer: {
                Text("买的那天记一笔全额支出；之后每期还款算还债，不再算支出。手续费单独算一笔支出。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("记一个分期")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || total == nil || accountID.isEmpty)
            }
        }
        .onAppear {
            if accountID.isEmpty { accountID = model.visibleAccounts.first { $0.kind != .cash }?.id ?? model.visibleAccounts.first?.id ?? "" }
            if bookID.isEmpty { bookID = model.defaultBookID }
        }
        .errorAlert($error)
    }

    private func save() {
        guard let total else { return }
        let fee = Money(parsing: feeText)
        do {
            try model.edit {
                try $0.addInstallment(name: name.trimmingCharacters(in: .whitespaces), bookID: bookID, accountID: accountID,
                                      total: total, count: count, purchaseDate: LocalDate(buyDate),
                                      firstPayment: LocalDate(firstDate), category: category.isEmpty ? nil : category,
                                      fee: fee, author: model.author).1
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 记一期分期还款：新记一笔，或者认领一笔已经导入的银行扣款。
struct PayInstallmentView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let status: InstallmentStatus
    @State private var amountText = ""
    @State private var date = Date()
    @State private var pickedTx: UUID?
    @State private var error: String?

    /// 可能是这期扣款的流水：同账户、普通支出、金额和每期差不多。
    private var candidates: [Transaction] {
        guard let inst = model.ledger.installments.first(where: { $0.id == status.id }) else { return [] }
        let per = inst.perPayment.cents
        return model.ledger.transactions
            .filter { $0.accountID == inst.accountID && $0.flow == nil && $0.amount.isExpense && !inst.paidIDs.contains($0.id) && $0.id != inst.purchaseID }
            .filter { abs($0.amount.magnitude.cents - per) <= max(100, per / 20) }
            .sorted { $0.date > $1.date }
            .prefix(6).map { $0 }
    }

    var body: some View {
        let options = candidates
        Form {
            Section {
                LabeledContent("这是第几期", value: "第 \(status.paidCount + 1) 期，共 \(status.count) 期")
                LabeledContent("还剩", value: status.remaining.formatted)
            }
            if !options.isEmpty {
                Section {
                    ForEach(options) { t in
                        Button {
                            pickedTx = pickedTx == t.id ? nil : t.id
                        } label: {
                            HStack {
                                Image(systemName: pickedTx == t.id ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.coral)
                                TransactionRow(tx: t, showDate: true)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("银行已经扣了？是不是这几笔里的一笔") } footer: {
                    Text("选中一笔，就把它认成这期还款，不再算支出。都不是就在下面新记一笔。")
                }
            }
            if pickedTx == nil {
                Section("新记一笔") {
                    TextField("金额，不填就是 \(status.perPayment.formatted)", text: $amountText).decimalKeyboard().monospacedDigit()
                    DatePicker("哪天扣的", selection: $date, displayedComponents: .date)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(status.name)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("记这一期", action: save).keyboardShortcut(.defaultAction) }
        }
        .onAppear {
            if let next = status.nextDate, next <= LocalDate.today { date = next.asDate }
        }
        .errorAlert($error)
    }

    private func save() {
        do {
            if let tx = pickedTx {
                try model.edit { try $0.linkInstallmentPayment(status.id, transactionID: tx, author: model.author) }
            } else {
                let amount = Money(parsing: amountText)
                try model.edit { try $0.payInstallment(status.id, amount: amount, date: LocalDate(date), author: model.author) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 建一个存钱目标，或者改一个已有的。
struct AddGoalView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let editing: Goal?
    @State private var name = ""
    @State private var targetText = ""
    @State private var bookID = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var savingsAccountID = ""
    @State private var locked = false
    @State private var error: String?

    init(editing: Goal? = nil) { self.editing = editing }

    private var target: Money? { Money(parsing: targetText).flatMap { $0.cents != 0 ? $0.magnitude : nil } }

    var body: some View {
        Form {
            Section {
                TextField("存钱做什么，如「应急金」「回国机票」", text: $name)
                AmountField(prompt: "目标金额", text: $targetText)
                Picker("账本", selection: $bookID) { ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) } }
                Toggle("想在某天前存够", isOn: $hasDeadline.animation())
                if hasDeadline {
                    DatePicker("哪天前存够", selection: $deadline, displayedComponents: .date)
                    if let t = target, let hint = monthlyHint(t) { Text(hint).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section {
                Picker("钱放在哪", selection: $savingsAccountID) {
                    Text("就放在平时的账户里，记个数").tag("")
                    ForEach(model.visibleAccounts) { a in Text("专门的账户：\(a.name)").tag(a.id) }
                }
                .disabled(editing != nil)
                Toggle("锁定（存进去到期前不能取）", isOn: $locked)
            } footer: {
                Text("有 Revolut 储蓄罐这类专门放这笔钱的账户就选它，进度直接看它的余额。没有就选第一项：钱还在原来的账户里，每次「存进去」只是记个数。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(editing == nil ? "建一个存钱目标" : "改目标")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || target == nil)
            }
        }
        .onAppear {
            if let g = editing, name.isEmpty {
                name = g.name; targetText = g.target.inputText; bookID = g.bookID
                hasDeadline = g.deadline != nil
                if let d = g.deadline { deadline = d.asDate }
                savingsAccountID = g.savingsAccountID ?? ""; locked = g.locked
            } else if bookID.isEmpty { bookID = model.defaultBookID }
        }
        .errorAlert($error)
    }

    private func monthlyHint(_ target: Money) -> String? {
        let months = max(1, Calendar.current.dateComponents([.month], from: Date(), to: deadline).month ?? 1)
        let saved = editing.flatMap { g in Plans.goals(model.ledger).first { $0.id == g.id }?.saved } ?? .zero
        let left = target.cents - saved.cents
        guard left > 0 else { return nil }
        return "还有 \(months) 个月，每个月存 \(Money(cents: left / Int64(months)).formatted) 就够。"
    }

    private func save() {
        guard let target else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            if var g = editing {
                g.name = trimmed; g.target = target; g.bookID = bookID
                g.deadline = hasDeadline ? LocalDate(deadline) : nil; g.locked = locked
                let updated = g
                if updated != editing { try model.edit { try $0.updateGoal(updated, author: model.author) } }
            } else {
                try model.edit {
                    try $0.addGoal(name: trimmed, bookID: bookID, target: target,
                                   deadline: hasDeadline ? LocalDate(deadline) : nil,
                                   savingsAccountID: savingsAccountID.isEmpty ? nil : savingsAccountID,
                                   locked: locked, author: model.author).1
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 往目标里存钱 / 取钱。
struct GoalMoneyView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let status: GoalStatus
    @State private var withdrawing = false
    @State private var amountText = ""
    @State private var accountID = ""
    @State private var date = Date()
    @State private var error: String?

    private var amount: Money? { Money(parsing: amountText).flatMap { $0.cents != 0 ? $0.magnitude : nil } }
    private var goal: Goal? { model.ledger.goals.first { $0.id == status.id } }

    var body: some View {
        Form {
            Section {
                LabeledContent("已存", value: "\(status.saved.formatted) / \(status.target.formatted)")
                Bar(fraction: Double(status.percent) / 100, color: .income, height: 8)
            }
            Section {
                if !status.locked {
                    Picker("", selection: $withdrawing.animation(.snappy)) {
                        Text("存钱").tag(false)
                        Text("取钱").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                AmountField(prompt: "0,00", text: $amountText)
                Picker(withdrawing ? "取到哪个账户" : "钱从哪个账户来", selection: $accountID) {
                    ForEach(model.visibleAccounts.filter { $0.id != goal?.savingsAccountID }) { a in Text(a.name).tag(a.id) }
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
            } footer: {
                Text(status.locked ? "这是锁定的目标，只能存，到期前不能取。"
                     : goal?.savingsAccountID != nil ? "钱会在这个账户和「\(model.accountName(goal?.savingsAccountID ?? ""))」之间挪动，不算收支。"
                     : "钱还在原来的账户里，只是记上「这部分是给这个目标的」。不算收支。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(status.name)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(withdrawing ? "取出" : "存进去", action: save).disabled(amount == nil || accountID.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            if accountID.isEmpty {
                accountID = model.visibleAccounts.first { $0.kind != .savings && $0.id != goal?.savingsAccountID }?.id ?? ""
            }
        }
        .errorAlert($error)
    }

    private func save() {
        guard let m = amount else { return }
        do {
            if withdrawing {
                try model.edit { try $0.withdraw(goalID: status.id, amount: m, toAccount: accountID, date: LocalDate(date), author: model.author) }
            } else {
                try model.edit { try $0.deposit(goalID: status.id, amount: m, fromAccount: accountID, date: LocalDate(date), author: model.author) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
