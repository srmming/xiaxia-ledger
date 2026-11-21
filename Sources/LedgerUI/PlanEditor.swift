import FinanceCore
import SwiftUI

/// 计划页「新计划」：存钱目标、分期、借款三选一。每次都进改动记录，能撤销。
struct NewPlanSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case goal = "存钱目标", installment = "分期", debt = "借款"
        var id: String { rawValue }
    }

    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var kind: Kind = .goal
    @State var name = ""
    @State var amountText = ""
    @State var bookID = ""
    @State var accountID = ""
    // 目标
    @State var hasDeadline = false
    @State var deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State var savingsAccountID = ""
    // 分期
    @State var count = 12
    @State var firstPayment = Date()
    // 借款
    @State var theyOweMe = true
    @State var date = Date()
    @State var error: String?

    private var amount: Money? {
        guard let m = Money(parsing: amountText.replacingOccurrences(of: " ", with: "")), m.cents != 0 else { return nil }
        return m.magnitude
    }

    var body: some View {
        Form {
            Section {
                Picker("要登记的是", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("planKind")
            } footer: { Text(footer) }

            switch kind {
            case .goal: goalFields
            case .installment: installmentFields
            case .debt: debtFields
            }

            if model.ledger.books.count > 1 {
                Section {
                    Picker("账本", selection: $bookID) {
                        ForEach(model.ledger.books) { Text($0.name).tag($0.id) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("新计划")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!canSave) }
        }
        .onAppear {
            if bookID.isEmpty { bookID = model.selectedBookID ?? model.defaultBookID }
            if accountID.isEmpty { accountID = model.defaultAccountID }
        }
        .onChange(of: kind) { _, _ in error = nil }
        .errorAlert($error)
    }

    private var footer: String {
        switch kind {
        case .goal: "比如「旅行」2.000 €，明年 6 月前存够。存钱时跟夏夏说「往旅行里存 100」。"
        case .installment: "比如「手机」每月 45 €，分 24 期。买的那天按全额记一笔支出，之后每期扣款不再算支出。"
        case .debt: "比如「小王借我 300 €」。还钱时跟夏夏说「小王还了我 100」。"
        }
    }

    private var canSave: Bool {
        guard amount != nil, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return kind != .installment || !accountID.isEmpty
    }

    @ViewBuilder private var goalFields: some View {
        Section {
            TextField("名字，比如「旅行」", text: $name)
            TextField("要存多少，比如 2.000", text: $amountText).decimalKeyboard()
            Toggle("有截止日期", isOn: $hasDeadline)
            if hasDeadline {
                DatePicker("哪天前存够", selection: $deadline, displayedComponents: .date)
            }
            Picker("钱放在哪", selection: $savingsAccountID) {
                Text("在现有账户里划出").tag("")
                ForEach(model.visibleAccounts) { Text($0.name).tag($0.id) }
            }
        } footer: {
            Text(savingsAccountID.isEmpty ? "每次存钱单独记一笔，账户余额不变。" : "进度就是这个账户的余额。")
        }
    }

    @ViewBuilder private var installmentFields: some View {
        Section {
            TextField("买的是什么，比如「手机」", text: $name)
            TextField("每期多少，比如 45", text: $amountText).decimalKeyboard()
            Stepper("一共 \(count) 期", value: $count, in: 2...120)
            DatePicker("第一期哪天扣", selection: $firstPayment, displayedComponents: .date)
            accountPicker("从哪个账户扣", allowNone: false)
        } footer: {
            if let amount { Text(verbatim: "一共 \(Money(cents: amount.cents * Int64(count)).formatted)。") }
        }
    }

    @ViewBuilder private var debtFields: some View {
        Section {
            Picker("方向", selection: $theyOweMe) {
                Text("我借给别人").tag(true)
                Text("我向别人借").tag(false)
            }
            .pickerStyle(.segmented)
            TextField(theyOweMe ? "借给谁" : "向谁借", text: $name)
            TextField("多少，比如 300", text: $amountText).decimalKeyboard()
            DatePicker("哪天", selection: $date, displayedComponents: .date)
            accountPicker(theyOweMe ? "钱从哪个账户出去" : "钱进了哪个账户", allowNone: true)
        } footer: {
            Text("选了账户会同时记一笔「往来」，不算收入也不算支出。很早以前的旧账可以选「不记进出」。")
        }
    }

    private func accountPicker(_ title: String, allowNone: Bool) -> some View {
        Picker(title, selection: $accountID) {
            if allowNone || accountID.isEmpty { Text(allowNone ? "不记进出" : "选一个").tag("") }
            ForEach(model.visibleAccounts) { Text($0.name).tag($0.id) }
        }
    }

    private func save() {
        guard let amount else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        let author = model.author
        do {
            switch kind {
            case .goal:
                try model.edit { l in
                    try l.addGoal(name: n, bookID: bookID, target: amount, deadline: hasDeadline ? LocalDate(deadline) : nil,
                                  savingsAccountID: savingsAccountID.isEmpty ? nil : savingsAccountID, author: author).1
                }
            case .installment:
                let total = Money(cents: amount.cents * Int64(count))
                try model.edit { l in
                    try l.addInstallment(name: n, bookID: bookID, accountID: accountID, total: total, count: count,
                                         purchaseDate: .today, firstPayment: LocalDate(firstPayment), author: author).1
                }
            case .debt:
                try model.edit { l in
                    try l.addDebt(counterparty: n, direction: theyOweMe ? .theyOweMe : .iOweThem, amount: amount, bookID: bookID,
                                  date: LocalDate(date), accountID: accountID.isEmpty ? nil : accountID, author: author).1
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 改一个目标：名字、金额、截止日期。也能删。
struct GoalEditor: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    let goal: Goal
    @State var name = ""
    @State var amountText = ""
    @State var hasDeadline = false
    @State var deadline = Date()
    @State var confirmDelete = false
    @State var error: String?

    var body: some View {
        Form {
            Section {
                TextField("名字", text: $name)
                TextField("要存多少", text: $amountText).decimalKeyboard()
                Toggle("有截止日期", isOn: $hasDeadline)
                if hasDeadline { DatePicker("哪天前存够", selection: $deadline, displayedComponents: .date) }
            }
            Section {
                Button("删除这个目标", role: .destructive) { confirmDelete = true }
            } footer: { Text("在现有账户里划出的存钱记录一起删，账户余额不变。删错了可以撤销。") }
        }
        .formStyle(.grouped)
        .navigationTitle("改目标")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .onAppear {
            name = goal.name
            amountText = goal.target.formatted.replacingOccurrences(of: " €", with: "")
            hasDeadline = goal.deadline != nil
            deadline = goal.deadline?.asDate ?? Date()
        }
        .confirmationDialog("删除目标「\(goal.name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                do { try model.edit { try $0.removeGoal(goal.id, author: model.author) }; dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
        .errorAlert($error)
    }

    private func save() {
        guard let m = Money(parsing: amountText.replacingOccurrences(of: " ", with: "")), m.cents > 0 else { error = "金额看不懂，写成 2.000 这样。"; return }
        var g = goal
        g.name = name.trimmingCharacters(in: .whitespaces)
        g.target = m.magnitude
        g.deadline = hasDeadline ? LocalDate(deadline) : nil
        do {
            if g != goal { try model.edit { try $0.updateGoal(g, author: model.author) } }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 计划页每一行右边的「⋯」：改、删、结清。
struct PlanRowMenu: View {
    enum Target { case goal(UUID), installment(UUID), debt(UUID) }
    @Environment(LedgerModel.self) var model
    let target: Target
    let name: String
    @State var confirmDelete = false
    @State var editingGoal: Goal?

    var body: some View {
        Menu {
            if case .goal(let id) = target, let g = model.ledger.goals.first(where: { $0.id == id }) {
                Button { editingGoal = g } label: { Label("改…", systemImage: "pencil") }
            }
            if case .debt(let id) = target, let d = model.ledger.debts.first(where: { $0.id == id }) {
                Button { var x = d; x.closed = true; model.perform { try $0.updateDebt(x, author: model.author) } } label: {
                    Label("结清（剩下的不用还了）", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("删除…", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(Color.fg2)
        }
        .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        .accessibilityLabel("\(name) 的操作")
        .confirmationDialog("删除「\(name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: remove)
        } message: { Text("相关的流水会一起删。删错了可以在改动记录里撤销。") }
        .sheet(item: $editingGoal) { g in
            NavigationStack { GoalEditor(goal: g) }
                .environment(model)
                #if os(macOS)
                .frame(width: 460, height: 360)
                #endif
        }
    }

    private func remove() {
        switch target {
        case .goal(let id): model.perform { try $0.removeGoal(id, author: model.author) }
        case .installment(let id): model.perform { try $0.removeInstallment(id, author: model.author) }
        case .debt(let id): model.perform { try $0.removeDebt(id, author: model.author) }
        }
    }
}
