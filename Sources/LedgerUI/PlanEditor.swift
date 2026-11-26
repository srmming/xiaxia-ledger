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

    @FocusState private var focus: Bool

    var body: some View {
        // 分期、借款各自一张（ming 2026-11-25 重做）：最要紧的先填（谁 / 什么、多少），下面一句话说清楚会记成什么。
        // Mac 上按钮在底下，回车保存、Esc 取消；打开就能打字。
        VStack(spacing: 0) {
            Form {
                switch kind {
                case .goal: goalFields
                case .installment: installmentFields
                case .debt: debtFields
                }
                // 开着生意模式时不问账本：在哪边登记就算哪边的。
                if model.ledger.books.count > 1 && !model.businessOn {
                    Section {
                        Picker(tr("账本"), selection: $bookID) {
                            ForEach(model.ledger.books) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                Section { } footer: { Text(summary ?? footer).font(.caption).foregroundStyle(Color.fg2) }
            }
            .formStyle(.grouped)
            #if os(macOS)
            Divider()
            HStack {
                Button(tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                Spacer()
                Button(action: save) { Text(tr("记下")).frame(minWidth: 80) }
                    .buttonStyle(.borderedProminent).solidTint().controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            #endif
        }
        .tint(model.side == .business ? Color.shop : Color.brand)
        .navigationTitle(kind == .goal ? tr("新目标") : kind == .installment ? tr("记分期") : tr("记借款"))
        .inlineTitle()
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(tr("保存"), action: save).disabled(!canSave) }
        }
        #endif
        .onAppear {
            if bookID.isEmpty { bookID = model.selectedBookID ?? model.defaultBookID }
            if accountID.isEmpty {
                let d = model.defaultAccountID
                accountID = model.accountsOnThisSide.contains { $0.id == d } ? d : model.accountsOnThisSide.first?.id ?? d
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focus = true }
        }
        .onChange(of: kind) { _, _ in error = nil }
        .errorAlert($error)
    }

    /// 填好了就用一句话说清楚：「新手机 每月 45 €，24 期，一共 1.080 €，从 12 月 1 日起从日常卡扣。」
    private var summary: String? {
        guard let amount, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let n = name.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .goal: return nil
        case .installment:
            let d = LocalDate(firstPayment)
            return tr("「\(n)」每月 \(amount.ui)，\(count) 期，一共 \(Money(cents: amount.cents * Int64(count)).ui)，\(d.month) 月 \(d.day) 日起从「\(model.accountName(accountID))」扣。买的那天按全额算一笔支出，之后每期不再算支出。")
        case .debt:
            let money = accountID.isEmpty ? tr("不记钱进出（旧账）") : theyOweMe ? tr("钱从「\(model.accountName(accountID))」出去") : tr("钱进了「\(model.accountName(accountID))」")
            return theyOweMe ? tr("\(n) 欠你 \(amount.ui)，\(money)。不算收入也不算支出。") : tr("你欠 \(n) \(amount.ui)，\(money)。不算收入也不算支出。")
        }
    }

    private var footer: String {
        switch kind {
        case .goal: tr("比如「旅行」2.000 €，明年 6 月前存够。存钱时跟夏夏说「往旅行里存 100」。")
        case .installment: tr("比如「手机」每月 45 €，分 12 期。买的那天按全额记一笔支出，之后每期扣款不再算支出。")
        case .debt: tr("比如「小王借我 300 €」。还钱时跟夏夏说「小王还了我 100」。")
        }
    }

    private var canSave: Bool {
        guard amount != nil, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return kind != .installment || !accountID.isEmpty
    }

    @ViewBuilder private var goalFields: some View {
        Section {
            FormField(tr("名字"), tr("比如「旅行」"), text: $name)
            FormField(tr("要存多少"), tr("比如 2.000"), text: $amountText).decimalKeyboard()
            Toggle(tr("有截止日期"), isOn: $hasDeadline)
            if hasDeadline {
                DatePicker(tr("哪天前存够"), selection: $deadline, displayedComponents: .date)
            }
            Picker(tr("钱放在哪"), selection: $savingsAccountID) {
                Text(tr("在现有账户里划出")).tag("")
                ForEach(model.visibleAccounts) { Text($0.name).tag($0.id) }
            }
        } footer: {
            Text(savingsAccountID.isEmpty ? tr("每次存钱单独记一笔，账户余额不变。") : tr("进度就是这个账户的余额。"))
        }
    }

    @ViewBuilder private var installmentFields: some View {
        Section {
            TextField(tr("买的是什么"), text: $name, prompt: Text(tr("比如「手机」"))).focused($focus)
            TextField(tr("每期多少"), text: $amountText, prompt: Text(tr("比如 45"))).decimalKeyboard()
            Stepper(tr("一共 \(count) 期"), value: $count, in: 2...120)
        }
        Section {
            DatePicker(tr("第一期哪天扣"), selection: $firstPayment, displayedComponents: .date)
            accountPicker(tr("从哪个账户扣"), allowNone: false)
        }
    }

    @ViewBuilder private var debtFields: some View {
        Section {
            Picker(tr("方向"), selection: $theyOweMe) {
                Text(tr("别人欠我")).tag(true)
                Text(tr("我欠别人")).tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()
            TextField(theyOweMe ? tr("谁欠我") : tr("我欠谁"), text: $name, prompt: Text(tr("写对方的名字"))).focused($focus)
            TextField(tr("多少"), text: $amountText, prompt: Text(tr("比如 300"))).decimalKeyboard()
        }
        Section {
            DatePicker(tr("哪天"), selection: $date, displayedComponents: .date)
            accountPicker(theyOweMe ? tr("钱从哪个账户出去") : tr("钱进了哪个账户"), allowNone: true)
        }
    }

    private func accountPicker(_ title: String, allowNone: Bool) -> some View {
        Picker(title, selection: $accountID) {
            if allowNone || accountID.isEmpty { Text(allowNone ? tr("不记进出（旧账）") : tr("选一个")).tag("") }
            ForEach(model.accountsOnThisSide) { Text($0.name).tag($0.id) }
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

/// 改一个目标：名字、金额、截止日期、钱存在哪。也能删。
struct GoalEditor: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    let goal: Goal
    @State var name = ""
    @State var amountText = ""
    @State var hasDeadline = false
    @State var deadline = Date()
    @State var stash: GoalStash?
    @State var stashNote = ""
    @State var confirmDelete = false
    @State var error: String?

    var body: some View {
        Form {
            Section {
                TextField(tr("名字"), text: $name)
                TextField(tr("要存多少"), text: $amountText).decimalKeyboard()
                Toggle(tr("有截止日期"), isOn: $hasDeadline)
                if hasDeadline { DatePicker(tr("哪天前存够"), selection: $deadline, displayedComponents: .date) }
            }
            Section {
                Picker(tr("钱真的存在哪"), selection: $stash) {
                    Text(tr("还没定")).tag(GoalStash?.none)
                    ForEach(GoalStash.allCases) { Text($0.label).tag(GoalStash?.some($0)) }
                }
                FormField(tr("具体在哪"), tr("比如「书桌上的小猪储蓄罐」"), text: $stashNote)
            } footer: { Text(tr("每次真的存了钱，都回来点小猪记一笔。")) }
            Section {
                Button(tr("删除这个目标"), role: .destructive) { confirmDelete = true }
            } footer: { Text(tr("在现有账户里划出的存钱记录一起删，账户余额不变。删错了可以撤销。")) }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("改目标"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(tr("保存"), action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .onAppear {
            name = goal.name
            amountText = goal.target.formatted.replacingOccurrences(of: " €", with: "")
            hasDeadline = goal.deadline != nil
            deadline = goal.deadline?.asDate ?? Date()
            stash = goal.stash
            stashNote = goal.stashNote ?? ""
        }
        .confirmationDialog(tr("删除目标「\(goal.name)」？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("删除"), role: .destructive) {
                do { try model.edit { try $0.removeGoal(goal.id, author: model.author) }; dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
        .errorAlert($error)
    }

    private func save() {
        guard let m = Money(parsing: amountText.replacingOccurrences(of: " ", with: "")), m.cents > 0 else { error = tr("金额看不懂，写成 2.000 这样。"); return }
        var g = goal
        g.name = name.trimmingCharacters(in: .whitespaces)
        g.target = m.magnitude
        g.deadline = hasDeadline ? LocalDate(deadline) : nil
        g.stash = stash
        let note = stashNote.trimmingCharacters(in: .whitespaces)
        g.stashNote = note.isEmpty ? nil : note
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
    @State var debtSheet: DebtSheet?

    var body: some View {
        Menu {
            if case .goal(let id) = target, let g = model.ledger.goals.first(where: { $0.id == id }) {
                Button { editingGoal = g } label: { Label(tr("改…"), systemImage: "pencil") }
                Button { model.perform { try $0.pinGoal(g.id, pinned: !g.pinned, author: model.author) } } label: {
                    Label(g.pinned ? tr("取消钉住") : tr("钉到最上面"), systemImage: g.pinned ? "pin.slash" : "pin")
                }
                if g.rank != nil {
                    Button { model.perform { try $0.resetGoalOrder(author: model.author) } } label: { Label(tr("顺序改回按急不急排"), systemImage: "arrow.up.arrow.down") }
                }
            }
            // 分期和欠款一样能记还款、提前还清（审查 2026-11-26：原来分期的菜单里只有「删除」）。
            if case .installment(let id) = target, let st = Plans.installments(model.ledger).first(where: { $0.id == id }), st.remaining.cents > 0 {
                let one = Money(cents: min(st.perPayment.cents, st.remaining.cents))
                Button { model.perform { try $0.payInstallment(id, amount: one, date: .today, author: model.author) } } label: {
                    Label(tr("记这一期还款（\(one.rounded)）"), systemImage: "arrow.uturn.backward.circle")
                }
                Button { model.perform { try $0.payOffInstallment(id, date: .today, author: model.author) } } label: {
                    Label(tr("提前还清（\(st.remaining.rounded)）"), systemImage: "checkmark.circle")
                }
                Divider()
            }
            if case .debt(let id) = target, let d = model.ledger.debts.first(where: { $0.id == id }), !d.closed {
                Button { debtSheet = DebtSheet(debtID: id, kind: .repay) } label: { Label(tr("记一笔还款…"), systemImage: "arrow.uturn.backward.circle") }
                Button { debtSheet = DebtSheet(debtID: id, kind: .plan) } label: {
                    Label(d.plan == nil ? tr("排个还款计划…") : tr("改还款计划…"), systemImage: "calendar.badge.clock")
                }
                if let p = model.ledger.planProgress(id), p.currentIndex != nil {
                    Menu {
                        Button(RepayAdjust.addToNext.label) { model.perform { try $0.skipPlannedPayment(id, adjust: .addToNext, author: model.author) } }
                        Button(RepayAdjust.extendPlan.label) { model.perform { try $0.skipPlannedPayment(id, adjust: .extendPlan, author: model.author) } }
                    } label: { Label(tr("这期先不还…"), systemImage: "clock.arrow.circlepath") }
                }
            }
            if case .debt(let id) = target, let d = model.ledger.debts.first(where: { $0.id == id }) {
                Button { var x = d; x.closed = true; model.perform { try $0.updateDebt(x, author: model.author) } } label: {
                    Label(tr("结清（剩下的不用还了）"), systemImage: "checkmark.circle")
                }
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: { Label(tr("删除…"), systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .actionMenuStyle()
        .accessibilityLabel(tr("\(name) 的操作"))
        .confirmationDialog(tr("删除「\(name)」？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("删除"), role: .destructive, action: remove)
        } message: { Text(tr("相关的流水会一起删。删错了可以在改动记录里撤销。")) }
        .sheet(item: $debtSheet) { x in
            NavigationStack {
                switch x.kind {
                case .repay: DebtRepaySheet(debtID: x.debtID)
                case .plan: DebtPlanSheet(debtID: x.debtID)
                }
            }
            .environment(model)
            #if os(macOS)
            .frame(width: 500, height: x.kind == .plan ? 560 : 460)
            #endif
        }
        .sheet(item: $editingGoal) { g in
            NavigationStack { GoalEditor(goal: g) }
                .environment(model)
                #if os(macOS)
                .frame(width: 460, height: 480)
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
