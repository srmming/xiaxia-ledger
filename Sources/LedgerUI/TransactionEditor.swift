import FinanceCore
import SwiftUI

/// 记一笔 / 改一笔。支出、收入、转账（自己账户之间，或账本之间）。
/// 填说明时会按以前的习惯自动选好分类；上次用的账户和账本会记住。
public struct TransactionEditor: View {
    enum Kind: Hashable { case expense, income, transfer }
    enum TransferKind: Hashable { case accounts, books }

    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let editing: Transaction?
    @State private var kind = Kind.expense
    @State private var transferKind = TransferKind.accounts
    @State private var amountText = ""
    @State private var text = ""
    @State private var category = ""
    @State private var categoryTouched = false
    @State private var accountID = ""
    @State private var toAccountID = ""
    @State private var bookID = ""
    @State private var toBookID = ""
    @State private var startAccountID = ""
    @State private var guessedAccountID: String?
    @State private var date = Date()
    @State private var keepAdding = false
    @State private var savedCount = 0
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var focus: Field?

    enum Field { case amount, text, category }

    public init() { editing = nil }
    init(editing: Transaction) { self.editing = editing }

    private var magnitude: Money? {
        guard let m = Money(parsing: amountText), m.cents != 0 else { return nil }
        return m.magnitude
    }

    /// 借款、储蓄、分期、转账、期初余额：金额和性质跟着「计划」走，这里只让看和删。
    private var locked: Bool { editing.map { $0.flow != nil || $0.isTransfer } ?? false }

    private var problem: String? {
        if model.visibleAccounts.isEmpty { return "还没有账户，先到「设置」里加一个。" }
        if amountText.isEmpty { return nil }
        if magnitude == nil { return "金额没看懂，写成 12,50 这样。" }
        if kind == .transfer {
            if transferKind == .accounts, accountID == toAccountID { return "转出和转入要选两个不同的账户。" }
            if transferKind == .books, bookID == toBookID { return "要选两个不同的账本。" }
        }
        return nil
    }

    private var canSave: Bool {
        magnitude != nil && !accountID.isEmpty && problem == nil && (kind == .transfer && transferKind == .accounts || !bookID.isEmpty)
    }

    public var body: some View {
        Group {
            if let t = editing, locked { LockedTransactionView(tx: t) } else { form }
        }
        .onAppear(perform: load)
        .errorAlert($error)
    }

    private var form: some View {
        Form {
            Section {
                Picker("类型", selection: $kind.animation(.snappy)) {
                    Text("支出").tag(Kind.expense)
                    Text("收入").tag(Kind.income)
                    Text("转账").tag(Kind.transfer)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                AmountField(prompt: "0,00", text: $amountText,
                            color: kind == .income ? .income : kind == .expense ? .primary : .secondary)
                    .focused($focus, equals: .amount)
                    .onSubmit { focus = .text }
                PromptField(placeholder, text: $text)
                    .focused($focus, equals: .text)
                    .onChange(of: text) { suggest() }
                if let problem { Text(problem).font(.footnote).foregroundStyle(Color.coral) }
            } footer: {
                if editing != nil, kind == .transfer {
                    Text("改成转账后，这笔不再算收入或支出。比如银行对账单里的「取现」「转到 Revolut」。")
                }
            }

            if kind == .transfer {
                transferSection
            } else {
                Section("分类") {
                    CategoryChips(categories: chipCategories, selection: $category) { _ in categoryTouched = true }
                        .padding(.vertical, 4)
                    PromptField("别的分类，自己写", text: $category)
                        .focused($focus, equals: .category)
                        .onChange(of: category) { if focus == .category { categoryTouched = true } }
                }
                Section {
                    Picker("账本", selection: $bookID.animation(.snappy)) {
                        ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) }
                    }
                    .pickerStyle(.segmented)
                    Picker(kind == .income ? "钱进了哪个账户" : "从哪个账户花的", selection: $accountID) {
                        ForEach(model.visibleAccounts) { a in Label(a.name, systemImage: a.kind.symbol).tag(a.id) }
                    }
                    dateRow
                }
            }

            if let t = editing {
                Section {
                    if let source = t.source { LabeledContent("来源", value: source) }
                    if let change = model.ledger.changes.last(where: { $0.transactionIDs.contains(t.id) }) {
                        LabeledContent("最后是谁改的", value: "\(change.author) · \(change.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Button(role: .destructive, action: delete) { Label("删掉这一笔", systemImage: "trash") }
                } footer: { Text("删错了，底部会出现「撤销」；之后也能在「改动记录」里撤销。") }
            } else {
                Section {
                    Toggle("保存后接着记下一笔", isOn: $keepAdding)
                } footer: {
                    if savedCount > 0 { Text("这次已经记了 \(savedCount) 笔。").foregroundStyle(Color.income) }
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 36) }   // 最后一行别被 Mac 面板的底栏挡住
        #endif
        .navigationTitle(editing == nil ? "记一笔" : "改这一笔")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(savedCount > 0 ? "完成" : "取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var placeholder: String {
        switch kind {
        case .expense: "说明，如「Mercadona」「午饭」"
        case .income: "说明，如「工资」「客人刷卡」"
        case .transfer: transferKind == .accounts ? "说明（可以不写），如「取现金」" : "说明（可以不写），如「店里的钱拿回家」"
        }
    }

    private var chipCategories: [String] {
        var list = model.categories(bookID: bookID.isEmpty ? nil : bookID, income: kind == .income, limit: 14)
        if !category.isEmpty, !list.contains(category) { list.insert(category, at: 0) }
        return list
    }

    private var dateRow: some View {
        HStack {
            DatePicker("日期", selection: $date, displayedComponents: .date)
            if !Calendar.current.isDateInToday(date) {
                Button("今天") { date = Date() }.buttonStyle(.borderless).font(.subheadline)
            } else {
                Button("昨天") { date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date() }
                    .buttonStyle(.borderless).font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var transferSection: some View {
        if editing == nil {
            Section {
                Picker("哪种转账", selection: $transferKind.animation(.snappy)) {
                    Text("自己账户之间").tag(TransferKind.accounts)
                    Text("账本之间").tag(TransferKind.books)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // 最常见的是「从店里拿钱回家」，所以默认方向是从店到个人。
                .onChange(of: transferKind) {
                    if transferKind == .books, bookID == "personal", !toBookID.isEmpty { swap(&bookID, &toBookID) }
                }
                if transferKind == .accounts {
                    Picker("从哪个账户", selection: $accountID) {
                        ForEach(model.visibleAccounts) { a in Label(a.name, systemImage: a.kind.symbol).tag(a.id) }
                    }
                    Picker("到哪个账户", selection: $toAccountID) {
                        ForEach(model.visibleAccounts) { a in Label(a.name, systemImage: a.kind.symbol).tag(a.id) }
                    }
                } else {
                    Picker("从哪个账本", selection: $bookID) { ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) } }
                    Picker("到哪个账本", selection: $toBookID) { ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) } }
                    Picker("钱在哪个账户里", selection: $accountID) {
                        ForEach(model.visibleAccounts) { a in Label(a.name, systemImage: a.kind.symbol).tag(a.id) }
                    }
                }
                dateRow
            } footer: {
                Text(transferKind == .accounts
                     ? "比如在取款机取 200 现金、把钱从 CaixaBank 转到 Revolut。钱还是你的，只是换了地方，不算收入也不算支出。"
                     : "比如从店里拿 500 给自己用：店的账本记一笔「老板提款」，个人账本记一笔进账。看「全部」时两笔抵消。")
            }
        } else {
            Section {
                Picker("另一半记在哪", selection: $toAccountID) {
                    Text("不用补（另一个账户的对账单里已经有了）").tag("")
                    ForEach(model.visibleAccounts.filter { $0.id != accountID }) { a in Text("在「\(a.name)」补一笔").tag(a.id) }
                }
            } footer: {
                Text("比如这笔是银行卡取现 200：选「在现金补一笔」，现金就多 200。如果两边的对账单都导入了，就选不用补。")
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let t = editing {
            kind = t.amount.isIncome ? .income : .expense
            amountText = t.amount.inputText
            text = t.description
            category = t.category ?? ""
            categoryTouched = t.category != nil
            accountID = t.accountID
            bookID = t.bookID ?? model.suggester.guess(t.description).bookID ?? model.defaultBookID
            date = t.date.asDate
            if t.category == nil { suggest() }
            return
        }
        focus = .amount
        accountID = model.defaultAccountID
        bookID = model.defaultBookID
        toBookID = model.ledger.books.first { $0.id != bookID }?.id ?? ""
        startAccountID = accountID
        toAccountID = model.visibleAccounts.first { $0.id != accountID }?.id ?? ""
    }

    /// 按以前的习惯猜分类：以前「Mercadona」都记成超市，这次填了 Mercadona 就先选上超市。自己点过分类就不再动。
    private func suggest() {
        guard kind != .transfer else { return }
        suggestAccount()
        guard !categoryTouched else { return }
        let g = model.suggester.guess(text)
        if let c = g.category { category = c }
        if editing == nil, let b = g.bookID, model.selectedBookID == nil { bookID = b }
    }

    /// 按以前的习惯猜账户：上次「Mercadona」是用 imagin 刷的，这次先选上 imagin。自己换过账户就不再动。
    private func suggestAccount() {
        guard editing == nil, accountID == startAccountID || accountID == guessedAccountID else { return }
        let key = Dedup.normalize(text)
        guard !key.isEmpty else { return }
        let visible = Set(model.visibleAccounts.map(\.id))
        let last = model.ledger.transactions
            .filter { $0.flow == nil && visible.contains($0.accountID) && Dedup.normalize($0.description) == key }
            .max { $0.date < $1.date }
        if let last { accountID = last.accountID; guessedAccountID = last.accountID }
    }

    private func save() {
        guard let m = magnitude, canSave else { return }
        let day = LocalDate(date)
        do {
            switch kind {
            case .transfer:
                if let t = editing {
                    // 先把改过的金额、说明、日期存上，再标成转账，两步算一条改动不现实，就分两条记。
                    var updated = t
                    updated.amount = t.amount.isIncome ? m : -m
                    updated.description = text.isEmpty ? t.description : text
                    updated.date = day
                    if updated != t { try model.edit(quiet: true) { try $0.editTransaction(updated, author: model.author) } }
                    try model.edit { try $0.markAsAccountTransfer([t.id], counterAccount: toAccountID.isEmpty ? nil : toAccountID, author: model.author) }
                } else if transferKind == .accounts {
                    try model.edit {
                        try $0.addAccountTransfer(amount: m, from: accountID, to: toAccountID, date: day,
                                                  bookID: nil, note: text.isEmpty ? nil : text, author: model.author)
                    }
                } else {
                    try model.edit {
                        try $0.addTransfer(amount: m, fromBook: bookID, toBook: toBookID, accountID: accountID, date: day,
                                           note: text.isEmpty ? nil : text, author: model.author)
                    }
                }
            case .expense, .income:
                let amount = kind == .income ? m : -m
                let cat = category.trimmingCharacters(in: .whitespaces)
                let description = text.isEmpty ? (cat.isEmpty ? (kind == .income ? "收入" : "支出") : cat) : text
                if var t = editing {
                    t.amount = amount; t.description = description; t.accountID = accountID; t.bookID = bookID
                    t.category = cat.isEmpty ? nil : cat; t.date = day
                    let updated = t
                    if updated == editing { dismiss(); return }
                    try model.edit { try $0.editTransaction(updated, author: model.author) }
                } else {
                    let tx = Transaction(date: day, amount: amount, description: description, accountID: accountID,
                                         bookID: bookID, category: cat.isEmpty ? nil : cat, source: "手记")
                    try model.edit { try $0.addTransaction(tx, author: model.author) }
                }
            }
            if kind != .transfer { model.lastBookID = bookID }
            model.lastAccountID = accountID
            if editing == nil, keepAdding {
                savedCount += 1
                amountText = ""; text = ""; category = ""; categoryTouched = false
                focus = .amount
            } else {
                dismiss()
            }
        } catch { self.error = error.localizedDescription }
    }

    private func delete() {
        guard let t = editing else { return }
        do {
            try model.edit { try $0.removeTransactions([t.id], author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 借款、储蓄、分期、转账、期初余额的流水：只看，不在这里改金额。
struct LockedTransactionView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tx: Transaction
    @State private var error: String?

    private var nature: (title: String, hint: String) {
        switch tx.flow {
        case .debt:
            if model.ledger.installments.contains(where: { $0.paidIDs.contains(tx.id) }) {
                return ("分期还款", "这是一期分期还款，不算支出。要改期数或删掉这个分期，到「计划」里点那个分期。")
            }
            return ("借款往来", "借出、借入、还款都不算收入或支出。要改，到「计划」里点对应的那笔借款。")
        case .saving: return ("存钱目标", "存进目标或从目标取出，不算收支。要改，到「计划」里点那个目标。")
        case .opening: return ("期初余额", "开始用账本那天账户里的钱。要改，到「设置」里点这个账户。")
        case .internal: return ("自己账户间转账", "钱从一个账户挪到另一个，不算收入也不算支出。记错了就删掉重记。")
        case nil: return ("账本间转账", "钱从一个账本挪到另一个。单看一个账本时照常算，看「全部」时两笔抵消。记错了就删掉重记。")
        }
    }

    var body: some View {
        let pair = model.ledger.pairedIDs(of: tx.id).filter { $0 != tx.id }.compactMap { model.transaction($0) }
        Form {
            Section {
                LabeledContent("金额") { AmountText(money: tx.amount, font: .title3.bold()) }
                LabeledContent("说明", value: tx.description)
                LabeledContent("日期", value: tx.date.friendly)
                LabeledContent("账户", value: model.accountName(tx.accountID))
                if let b = tx.bookID { LabeledContent("账本", value: model.bookName(b)) }
                LabeledContent("性质", value: nature.title)
            } footer: { Text(nature.hint) }
            if !pair.isEmpty {
                Section("成对的另一笔") { ForEach(pair) { TransactionRow(tx: $0, showDate: true) } }
            }
            if tx.flow == .internal || (tx.flow == nil && tx.isTransfer) {
                Section {
                    Button(role: .destructive) {
                        do {
                            try model.edit { try $0.removeTransactions($0.pairedIDs(of: tx.id), author: model.author) }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    } label: { Label(pair.isEmpty ? "删掉这一笔" : "两笔一起删掉", systemImage: "trash") }
                    if tx.flow == .internal, pair.isEmpty {
                        Button("改回普通的收入 / 支出") {
                            var t = tx
                            t.flow = nil; t.category = nil; t.transferID = nil
                            do {
                                try model.edit { try $0.editTransaction(t, author: model.author) }
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("这一笔")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .errorAlert($error)
    }
}
