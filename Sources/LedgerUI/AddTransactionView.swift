import FinanceCore
import SwiftUI

/// 记一笔：金额、支出/收入、说明、分类、账户、账本、日期。
public struct AddTransactionView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var isIncome = false
    @State private var text = ""
    @State private var category = ""
    @State private var accountID = ""
    @State private var bookID = ""
    @State private var date = Date()
    @State private var error: String?
    @FocusState private var amountFocused: Bool

    public init() {}

    private var amount: Money? {
        guard let m = Money(parsing: amountText), m.cents != 0 else { return nil }
        return isIncome ? m.magnitude : -m.magnitude
    }

    public var body: some View {
        Form {
            Section {
                Picker("类型", selection: $isIncome) {
                    Text("支出").tag(false)
                    Text("收入").tag(true)
                }
                .pickerStyle(.segmented)
                TextField("金额，如 12,50", text: $amountText)
                    .decimalKeyboard()
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .focused($amountFocused)
                TextField("说明，如「超市」", text: $text)
            }
            Section("分类") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.knownCategories.prefix(12), id: \.self) { c in
                            Button(c) { category = c }
                                .buttonStyle(.bordered)
                                .tint(category == c ? Color.coral : .secondary)
                        }
                    }
                }
                TextField("或者自己写", text: $category)
            }
            Section {
                Picker("账户", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Label(a.name, systemImage: a.kind.symbol).tag(a.id) }
                }
                Picker("账本", selection: $bookID) {
                    ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) }
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
            }
            if model.ledger.accounts.isEmpty {
                Section { Text("还没有账户，先到「设置」里加一个。").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("记一笔")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(amount == nil || accountID.isEmpty || bookID.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear {
            amountFocused = true
            if accountID.isEmpty { accountID = model.visibleAccounts.first { $0.kind == .cash }?.id ?? model.visibleAccounts.first?.id ?? "" }
            if bookID.isEmpty { bookID = model.selectedBookID ?? model.ledger.books.first?.id ?? "" }
        }
        .errorAlert($error)
    }

    private func save() {
        guard let amount else { return }
        let description = text.isEmpty ? (category.isEmpty ? (isIncome ? "收入" : "支出") : category) : text
        let tx = Transaction(date: LocalDate(date), amount: amount, description: description, accountID: accountID,
                             bookID: bookID, category: category.isEmpty ? nil : category, source: "手记")
        do {
            try model.edit { try $0.addTransaction(tx, author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
