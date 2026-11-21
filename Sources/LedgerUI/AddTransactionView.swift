import FinanceCore
import SwiftUI

/// 记一笔 / 改一笔：支出、收入、账本间转账。
public struct AddTransactionView: View {
    enum Kind: Hashable { case expense, income, transfer }

    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let editing: Transaction?
    @State private var kind = Kind.expense
    @State private var amountText = ""
    @State private var text = ""
    @State private var category = ""
    @State private var accountID = ""
    @State private var bookID = ""
    @State private var toBookID = ""
    @State private var date = Date()
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var amountFocused: Bool

    public init() { editing = nil }
    init(editing: Transaction) { self.editing = editing }

    private var magnitude: Money? {
        guard let m = Money(parsing: amountText), m.cents != 0 else { return nil }
        return m.magnitude
    }

    private var canSave: Bool {
        guard magnitude != nil, !accountID.isEmpty, !bookID.isEmpty else { return false }
        return kind != .transfer || (!toBookID.isEmpty && toBookID != bookID)
    }

    public var body: some View {
        Form {
            Section {
                if editing == nil {
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(Kind.expense)
                        Text("收入").tag(Kind.income)
                        Text("账本间转账").tag(Kind.transfer)
                    }
                    .pickerStyle(.segmented)
                } else {
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(Kind.expense)
                        Text("收入").tag(Kind.income)
                    }
                    .pickerStyle(.segmented)
                }
                TextField("金额，如 12,50", text: $amountText)
                    .decimalKeyboard()
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .focused($amountFocused)
                TextField(kind == .transfer ? "说明，如「店里取现金回家」" : "说明，如「超市」", text: $text)
            }
            if kind != .transfer {
                Section("分类") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(model.knownCategories.prefix(14), id: \.self) { c in
                                Button(c) { category = c }
                                    .buttonStyle(.bordered)
                                    .tint(category == c ? Color.coral : .secondary)
                            }
                        }
                    }
                    TextField("或者自己写", text: $category)
                }
            }
            Section {
                Picker("账户", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Label(a.name, systemImage: a.kind.symbol).tag(a.id) }
                }
                Picker(kind == .transfer ? "从哪个账本" : "账本", selection: $bookID) {
                    ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) }
                }
                if kind == .transfer {
                    Picker("到哪个账本", selection: $toBookID) {
                        ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) }
                    }
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
            } footer: {
                if kind == .transfer {
                    Text("比如从店里拿钱给自己用：店的账本记一笔转出，个人账本记一笔转入。看「全部」时两笔抵消，不重复算。")
                }
            }
            if model.ledger.accounts.isEmpty {
                Section { Text("还没有账户，先到「设置」里加一个。").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(editing == nil ? "记一笔" : "改一笔")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear(perform: load)
        .errorAlert($error)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let t = editing {
            kind = t.amount.isIncome ? .income : .expense
            amountText = t.amount.magnitude.decimalString.replacingOccurrences(of: ".", with: ",")
            text = t.description
            category = t.category ?? ""
            accountID = t.accountID
            bookID = t.bookID ?? model.ledger.books.first?.id ?? ""
            date = t.date.asDate
            return
        }
        amountFocused = true
        accountID = model.visibleAccounts.first { $0.kind == .cash }?.id ?? model.visibleAccounts.first?.id ?? ""
        bookID = model.selectedBookID ?? model.ledger.books.first?.id ?? ""
        toBookID = model.ledger.books.first { $0.id != bookID }?.id ?? ""
    }

    private func save() {
        guard let m = magnitude else { return }
        do {
            switch kind {
            case .transfer:
                try model.edit {
                    try $0.addTransfer(amount: m, fromBook: bookID, toBook: toBookID, accountID: accountID, date: LocalDate(date),
                                       note: text.isEmpty ? nil : text, author: model.author)
                }
            case .expense, .income:
                let amount = kind == .income ? m : -m
                let description = text.isEmpty ? (category.isEmpty ? (kind == .income ? "收入" : "支出") : category) : text
                if var t = editing {
                    t.amount = amount; t.description = description; t.accountID = accountID; t.bookID = bookID
                    t.category = category.isEmpty ? nil : category; t.date = LocalDate(date)
                    let updated = t
                    try model.edit { try $0.editTransaction(updated, author: model.author) }
                } else {
                    let tx = Transaction(date: LocalDate(date), amount: amount, description: description, accountID: accountID,
                                         bookID: bookID, category: category.isEmpty ? nil : category, source: "手记")
                    try model.edit { try $0.addTransaction(tx, author: model.author) }
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
