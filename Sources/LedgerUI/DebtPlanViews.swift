import FinanceCore
import SwiftUI

// 欠款改分期（ming 2026-11-23）：「排个还款计划」「记一笔还款」两个小窗口。我欠的、欠我的都能用。
// 规则都在 FinanceCore/DebtPlan.swift，这里只是填表和预览。

/// 欠款那行「⋯」里弹出来的窗口。
struct DebtSheet: Identifiable {
    enum Kind { case repay, plan }
    let id = UUID()
    let debtID: UUID
    let kind: Kind
}

/// 排 / 改还款计划：填每月还多少或分几期，自动算每期日期和金额，某一期可以点开改。
struct DebtPlanSheet: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    let debtID: UUID

    enum Mode: String, CaseIterable { case perMonth = "每月还多少", count = "分几期" }
    @State private var mode: Mode = .count
    @State private var perMonthText = ""
    @State private var count = 6
    @State private var start = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    /// 自己改过的那几期（改过就不再跟着上面重算）。
    @State private var draft: [PlannedPayment] = []
    @State private var edited = false
    @State private var editing: Int?
    @State private var editText = ""
    @State private var error: String?
    @State private var confirmClear = false

    private var debt: Debt? { model.ledger.debts.first { $0.id == debtID } }
    private var status: DebtStatus? { Plans.debts(model.ledger, today: .today).first { $0.id == debtID } }
    private var outstanding: Money { status?.outstanding ?? .zero }

    var body: some View {
        Form {
            if let d = debt, let st = status {
                Section {
                    LabeledContent(d.direction == .theyOweMe ? "\(d.counterparty)还欠我" : "我还欠\(d.counterparty)", value: st.outstanding.ui)
                    Picker("怎么排", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if mode == .perMonth {
                        FormField("每月还多少", "比如 100", text: $perMonthText).decimalKeyboard()
                    } else {
                        Stepper(value: $count, in: 1...60) { Text("分 \(count) 期") }
                    }
                    DatePicker("第一期哪天", selection: $start, displayedComponents: .date)
                } footer: {
                    if d.plan != nil { Text("已经还完的期会留着，从下一期开始重排。") }
                }
                Section {
                    if draft.isEmpty {
                        Text(mode == .perMonth ? "填上每月还多少，这里会排出每一期。" : "选好分几期，这里会排出每一期。")
                            .foregroundStyle(Color.fg2)
                    }
                    ForEach(Array(draft.enumerated()), id: \.offset) { i, p in
                        periodRow(i, p)
                    }
                } header: {
                    Text(draft.isEmpty ? "每一期" : "每一期（\(draft.count) 期，\(draft.last!.date.year) 年 \(draft.last!.date.month) 月还清）")
                } footer: {
                    if !draft.isEmpty { Text("点某一期可以改金额，差出来的钱自动从最后几期找补。") }
                }
                if d.plan != nil {
                    Section {
                        Button("不要计划了", role: .destructive) { confirmClear = true }
                    } footer: { Text("还是一笔欠款，只是不分期了。可以撤销。") }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(debt?.plan == nil ? "排个还款计划" : "改还款计划")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(draft.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: load)
        .onChange(of: mode) { _, _ in recompute() }
        .onChange(of: perMonthText) { _, _ in recompute() }
        .onChange(of: count) { _, _ in recompute() }
        .onChange(of: start) { _, _ in recompute() }
        .confirmationDialog("不要这个还款计划了？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("不要了", role: .destructive) {
                do { try model.edit { try $0.clearDebtPlan(debtID, author: model.author) }; dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
        .alert("改这一期", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("金额", text: $editText)
            Button("好") { applyEdit() }
            Button("取消", role: .cancel) { editing = nil }
        } message: { Text("改完以后最后几期会跟着变，合计还是 \(outstanding.ui)。") }
        .errorAlert($error)
    }

    private func periodRow(_ i: Int, _ p: PlannedPayment) -> some View {
        Button {
            editing = i
            editText = p.amount.formatted.replacingOccurrences(of: " €", with: "")
        } label: {
            HStack {
                Text("第 \(i + 1) 期").foregroundStyle(Color.fg2).frame(width: 64, alignment: .leading)
                Text(p.date.short)
                Spacer()
                Text(p.amount.ui).font(.kitAmount)
                Image(systemName: "pencil").font(.caption).foregroundStyle(Color.fg3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(i + 1) 期，\(p.date.short)，\(p.amount.spoken)，点一下改金额")
    }

    private func load() {
        guard let d = debt else { return }
        if let plan = d.plan, let p = model.ledger.planProgress(debtID), let k = p.currentIndex {
            // 已经有计划：从正在还的这一期起列出来（这一期只列还差的）。
            var rest = Array(plan[k...])
            rest[0].amount = p.nextAmount
            draft = rest
            edited = true
            count = rest.count
            start = rest[0].date.asDate
        } else {
            if let due = d.dueDate {
                let months = max(1, (due.year - LocalDate.today.year) * 12 + due.month - LocalDate.today.month)
                count = min(60, months)
            }
            recompute()
        }
    }

    private func recompute() {
        if edited, debt?.plan != nil, draft.first?.date == LocalDate(start) && mode == .count && draft.count == count { return }
        edited = false
        let first = LocalDate(start)
        switch mode {
        case .perMonth:
            if let m = Money(parsing: perMonthText.replacingOccurrences(of: " ", with: "")), m.cents > 0 {
                draft = DebtPlans.schedule(outstanding: outstanding, start: first, perMonth: m.magnitude)
            } else { draft = [] }
        case .count:
            draft = DebtPlans.schedule(outstanding: outstanding, start: first, count: count)
        }
    }

    private func applyEdit() {
        defer { editing = nil }
        guard let i = editing, let m = Money(parsing: editText.replacingOccurrences(of: " ", with: "")), m.cents > 0 else {
            error = "金额看不懂，写成 120 或 120,50 这样。"; return
        }
        guard let p = DebtPlans.rebalanced(draft, index: i, amount: m.magnitude) else {
            error = "这一期改成 \(m.magnitude.ui) 就超过还欠的 \(outstanding.ui) 了。"; return
        }
        draft = p
        edited = true
    }

    private func save() {
        guard draft.count <= 120 else { error = "期数太多了，多还一点或者少分几期。"; return }
        do {
            try model.edit { try $0.setDebtPlan(debtID, plan: draft, author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 记一笔还款。有计划、又比这期该还的多或少时，夏夏问怎么调：
/// 多还：抵最后几期（早点还清）/ 之后每期少还；少还：补到下一期 / 顺延一期。选完告诉你还清提前多久。
struct DebtRepaySheet: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    let debtID: UUID

    @State private var amountText = ""
    @State private var date = Date()
    @State private var accountID = ""
    /// nil = 计划不动。
    @State private var adjust: RepayAdjust?
    @State private var error: String?

    private var debt: Debt? { model.ledger.debts.first { $0.id == debtID } }
    private var status: DebtStatus? { Plans.debts(model.ledger, today: .today).first { $0.id == debtID } }
    private var amount: Money? {
        guard let m = Money(parsing: amountText.replacingOccurrences(of: " ", with: "")), m.cents > 0 else { return nil }
        return m.magnitude
    }
    private var preview: RepayPreview? { amount.flatMap { model.ledger.repayPreview(debtID, amount: $0, today: LocalDate(date)) } }

    var body: some View {
        Form {
            if let d = debt, let st = status {
                Section {
                    LabeledContent(d.direction == .theyOweMe ? "\(d.counterparty)还欠我" : "我还欠\(d.counterparty)", value: st.outstanding.ui)
                    if let p = model.ledger.planProgress(debtID), let next = p.nextDate {
                        LabeledContent("这一期（第 \(p.paidCount + 1) / \(p.count) 期）", value: "\(next.short) · \(p.nextAmount.ui)")
                    }
                    FormField(d.direction == .theyOweMe ? "这次收回多少" : "这次还了多少", "比如 100", text: $amountText).decimalKeyboard()
                    DatePicker("哪天", selection: $date, displayedComponents: .date)
                    Picker(d.direction == .theyOweMe ? "钱进了哪个账户" : "从哪个账户还的", selection: $accountID) {
                        ForEach(model.visibleAccounts) { Text($0.name).tag($0.id) }
                    }
                }
                if let p = preview {
                    if p.paysOff {
                        Section { Label("这笔还完就还清啦 🎉", systemImage: "checkmark.seal.fill").foregroundStyle(Color.income) }
                    } else if !p.options.isEmpty {
                        Section {
                            ForEach(p.options, id: \.adjust) { o in optionRow(o.adjust, o.adjust.label, o.detail) }
                            optionRow(nil, "计划先不动", "以后再说")
                        } header: {
                            HStack(spacing: 6) {
                                XiaxiaAvatar(persona: model.persona, size: 20).accessibilityHidden(true)
                                Text(p.difference.cents > 0
                                     ? "比这期多还了 \(p.difference.magnitude.ui)，多出来的怎么算？"
                                     : "比这期少还了 \(p.difference.magnitude.ui)，差的怎么办？")
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("记一笔还款")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("记上", action: save).disabled(amount == nil || accountID.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            if let p = model.ledger.planProgress(debtID), p.currentIndex != nil {
                amountText = p.nextAmount.formatted.replacingOccurrences(of: " €", with: "")
            } else if let st = status {
                amountText = st.outstanding.formatted.replacingOccurrences(of: " €", with: "")
            }
            accountID = model.visibleAccounts.first?.id ?? ""
        }
        .onChange(of: amountText) { _, _ in adjust = preview?.options.first?.adjust }
        .errorAlert($error)
    }

    private func optionRow(_ value: RepayAdjust?, _ title: String, _ detail: String) -> some View {
        Button { adjust = value } label: {
            HStack(spacing: 10) {
                Image(systemName: adjust == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(adjust == value ? Color.brand : Color.fg3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(Color.fg2)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(adjust == value ? .isSelected : [])
    }

    private func save() {
        guard let amount else { return }
        let how = (preview?.options.isEmpty ?? true) ? nil : adjust
        do {
            try model.edit { try $0.repay(debtID: debtID, amount: amount, date: LocalDate(date), accountID: accountID, adjust: how, author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
