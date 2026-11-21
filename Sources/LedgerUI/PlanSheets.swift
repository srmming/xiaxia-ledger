import FinanceCore
import SwiftUI

/// 记一个分期：买的那天按全额算支出。
struct AddInstallmentView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var totalText = ""
    @State private var count = 6
    @State private var feeText = ""
    @State private var accountID = ""
    @State private var bookID = "personal"
    @State private var category = ""
    @State private var buyDate = Date()
    @State private var firstDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("买了什么，如「美甲灯」", text: $name)
                TextField("总价（不含手续费）", text: $totalText).decimalKeyboard().monospacedDigit()
                Stepper("分 \(count) 期", value: $count, in: 2...60)
                if let t = Money(parsing: totalText), t.cents > 0 {
                    LabeledContent("每期大约", value: Money(cents: t.magnitude.cents / Int64(count)).formatted)
                }
                TextField("手续费或利息（没有就空着）", text: $feeText).decimalKeyboard().monospacedDigit()
            }
            Section {
                Picker("从哪个账户扣", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Text(a.name).tag(a.id) }
                }
                Picker("账本", selection: $bookID) { ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) } }
                TextField("分类，如「设备」「数码」", text: $category)
                DatePicker("哪天买的", selection: $buyDate, displayedComponents: .date)
                DatePicker("第一期哪天扣", selection: $firstDate, displayedComponents: .date)
            } footer: {
                Text("买的那天记一笔全额支出；之后每期还款算还债，不再算支出。手续费单独算支出。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("记一个分期")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Money(parsing: totalText) == nil || accountID.isEmpty)
            }
        }
        .onAppear { if accountID.isEmpty { accountID = model.visibleAccounts.first { $0.kind != .cash }?.id ?? model.visibleAccounts.first?.id ?? "" } }
        .errorAlert($error)
    }

    private func save() {
        guard let total = Money(parsing: totalText) else { return }
        let fee = Money(parsing: feeText)
        do {
            try model.edit {
                try $0.addInstallment(name: name.trimmingCharacters(in: .whitespaces), bookID: bookID, accountID: accountID,
                                      total: total.magnitude, count: count, purchaseDate: LocalDate(buyDate),
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
            .filter { $0.accountID == inst.accountID && $0.flow == nil && $0.amount.isExpense && !inst.paidIDs.contains($0.id) }
            .filter { abs($0.amount.magnitude.cents - per) <= max(100, per / 20) }
            .sorted { $0.date > $1.date }
            .prefix(8).map { $0 }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("已还", value: "\(status.paidCount)/\(status.count) 期")
                LabeledContent("还剩", value: status.remaining.formatted)
            }
            if !candidates.isEmpty {
                Section {
                    ForEach(candidates) { t in
                        Button {
                            pickedTx = pickedTx == t.id ? nil : t.id
                        } label: {
                            HStack {
                                Image(systemName: pickedTx == t.id ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.coral)
                                TransactionRow(tx: t)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("是不是这几笔银行扣款？") } footer: {
                    Text("选中一笔，就把它认成这期还款，不再算支出。都不是就在下面新记一笔。")
                }
            }
            if pickedTx == nil {
                Section("新记一笔") {
                    TextField("金额，默认 \(status.perPayment.formatted)", text: $amountText).decimalKeyboard().monospacedDigit()
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(status.name)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("记这一期", action: save) }
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

/// 建一个存钱目标。
struct AddGoalView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var targetText = ""
    @State private var bookID = "personal"
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var savingsAccountID = ""
    @State private var locked = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("存钱做什么，如「应急金」「回国机票」", text: $name)
                TextField("目标金额", text: $targetText).decimalKeyboard().monospacedDigit()
                Picker("账本", selection: $bookID) { ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) } }
                Toggle("有截止日期", isOn: $hasDeadline)
                if hasDeadline { DatePicker("哪天前存够", selection: $deadline, displayedComponents: .date) }
            }
            Section {
                Picker("钱放在哪", selection: $savingsAccountID) {
                    Text("在现有账户里划出").tag("")
                    ForEach(model.visibleAccounts) { a in Text("专门的账户：\(a.name)").tag(a.id) }
                }
                Toggle("锁定（存进去到期前不能取）", isOn: $locked)
            } footer: {
                Text("有 Revolut 储蓄罐这类专门账户就选它，进度直接看它的余额；没有就在现有账户里划出，每笔存入单独记。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("建一个存钱目标")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Money(parsing: targetText) == nil)
            }
        }
        .errorAlert($error)
    }

    private func save() {
        guard let target = Money(parsing: targetText) else { return }
        do {
            try model.edit {
                try $0.addGoal(name: name.trimmingCharacters(in: .whitespaces), bookID: bookID, target: target.magnitude,
                               deadline: hasDeadline ? LocalDate(deadline) : nil,
                               savingsAccountID: savingsAccountID.isEmpty ? nil : savingsAccountID,
                               locked: locked, author: model.author).1
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

    var body: some View {
        Form {
            Section {
                LabeledContent("已存", value: "\(status.saved.formatted) / \(status.target.formatted)")
                ProgressView(value: Double(status.percent), total: 100).tint(Color.income)
            }
            Section {
                if !status.locked {
                    Picker("", selection: $withdrawing) {
                        Text("存钱").tag(false)
                        Text("取钱").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                TextField("金额", text: $amountText).decimalKeyboard().monospacedDigit()
                Picker(withdrawing ? "取到哪个账户" : "钱从哪个账户来", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Text(a.name).tag(a.id) }
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
            } footer: {
                Text(status.locked ? "这是锁定的目标，只能存，到期前不能取。" : "存钱、取钱都不算收支。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(status.name)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(withdrawing ? "取出" : "存进去", action: save).disabled(Money(parsing: amountText) == nil || accountID.isEmpty)
            }
        }
        .onAppear { if accountID.isEmpty { accountID = model.visibleAccounts.first { $0.kind != .savings }?.id ?? "" } }
        .errorAlert($error)
    }

    private func save() {
        guard let m = Money(parsing: amountText) else { return }
        do {
            if withdrawing {
                try model.edit { try $0.withdraw(goalID: status.id, amount: m.magnitude, toAccount: accountID, date: LocalDate(date), author: model.author) }
            } else {
                try model.edit { try $0.deposit(goalID: status.id, amount: m.magnitude, fromAccount: accountID, date: LocalDate(date), author: model.author) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
