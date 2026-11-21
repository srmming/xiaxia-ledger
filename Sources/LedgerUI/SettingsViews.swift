import FinanceCore
import SwiftUI

/// 改动记录：谁、什么时候、改了什么，能撤销。
public struct HistoryView: View {
    @Environment(LedgerModel.self) private var model
    @State private var confirming: ChangeRecord?
    @State private var onlyOthers = false

    public init() {}

    public var body: some View {
        let all = Array(model.ledger.changes.reversed())
        let list = onlyOthers ? all.filter { $0.author != model.author } : all
        let authors = Set(all.map(\.author))
        List {
            if authors.count > 1 {
                Section {
                    Toggle("只看别人（AI）改的", isOn: $onlyOthers.animation())
                }
            }
            if list.isEmpty {
                ContentUnavailableView {
                    Label("还没有改动", systemImage: "clock")
                } description: { Text("你或 AI 每记一笔、导入一批、改一个分类，这里都会留一条，写明是谁改的，随时能撤销。") }
            }
            ForEach(list) { c in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: c.author == model.author ? "person.crop.circle" : "sparkles")
                        .foregroundStyle(c.undone ? Color.secondary : Color.coral)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.summary).strikethrough(c.undone).foregroundStyle(c.undone ? .secondary : .primary)
                        Text("\(c.author) · \(c.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.undone {
                        Text("已撤销").font(.caption).foregroundStyle(.secondary)
                    } else if c.canUndo {
                        Button("撤销") { confirming = c }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("改动记录")
        .confirmationDialog("撤销这条改动？", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { c in
            Button("撤销", role: .destructive) { model.undo(c.id) }
        } message: { c in Text(c.summary) }
    }
}

/// 设置：账户（含私房钱）、账本、分类、导入和改动记录、数据在哪。
public struct SettingsView: View {
    @Environment(LedgerModel.self) private var model
    @State private var addingBook = false
    @State private var newBook = ""
    @State private var renamingBook: Book?
    @State private var bookName = ""

    public init() {}

    public var body: some View {
        content
        .navigationTitle("设置")
        .alert("新账本叫什么？", isPresented: $addingBook) {
            TextField("如「房东收租」", text: $newBook)
            Button("取消", role: .cancel) {}
            Button("加上") { model.perform { try $0.addBook(name: newBook, author: model.author) } }
        }
        .alert("账本改名", isPresented: Binding(get: { renamingBook != nil }, set: { if !$0 { renamingBook = nil } })) {
            TextField("名字", text: $bookName)
            Button("取消", role: .cancel) { renamingBook = nil }
            Button("改") {
                if let b = renamingBook { model.perform { try $0.renameBook(b.id, to: bookName, author: model.author) } }
                renamingBook = nil
            }
        }
    }

    #if os(macOS)
    /// Mac：和总览一样的卡片。
    private var content: some View {
        @Bindable var model = model
        let balances = model.balances
        let accounts = model.visibleAccounts
        return VStack(alignment: .leading, spacing: 16) {
            Card(spacing: 4) {
                CardHeader(title: "账户") {
                    Button { model.sheet = .addAccount } label: { Label("加一个账户", systemImage: "plus") }.buttonStyle(.borderless)
                }
                ForEach(accounts) { a in
                    NavigationLink { AccountDetailView(accountID: a.id) } label: {
                        macRow(a.name + (a.isPrivate ? "（私房钱）" : ""), symbol: a.isPrivate ? "lock.fill" : a.kind.symbol,
                               value: (balances[a.id] ?? .zero).formatted, chevron: true)
                    }
                    .buttonStyle(.plain)
                    if a.id != accounts.last?.id { Divider() }
                }
                Divider().padding(.vertical, 4)
                Toggle(isOn: $model.showPrivate.animation()) { Label("显示私房钱", systemImage: "lock") }
                    .toggleStyle(.switch)
                Text("点一个账户可以改名字、对一下余额、设成私房钱、删掉。私房钱账户平时不显示、不算进总览和报表；关掉 app 再开会自动藏回去。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                Card(spacing: 4) {
                    CardHeader(title: "账本") {
                        Button { newBook = ""; addingBook = true } label: { Label("加一个账本", systemImage: "plus") }.buttonStyle(.borderless)
                    }
                    ForEach(model.ledger.books) { b in
                        Button { bookName = b.name; renamingBook = b } label: {
                            macRow(b.name, symbol: "book.closed",
                                   value: "\(model.ledger.transactions.filter { $0.bookID == b.id }.count) 笔", chevron: false)
                        }
                        .buttonStyle(.plain)
                        if b.id != model.ledger.books.last?.id { Divider() }
                    }
                    Text("点一个账本改名字。每笔流水单独归一个账本，比如个人的和店里的分开算。")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                Card(spacing: 4) {
                    CardHeader("分类")
                    NavigationLink { CategoriesView() } label: {
                        macRow("改名、合并分类", symbol: "tag", value: "", chevron: true)
                    }
                    .buttonStyle(.plain)
                    Text("比如把「吃饭」和「餐饮」并成一个。").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
            Card(spacing: 8) {
                CardHeader(title: "数据") {
                    Button("重新读取账本") { model.reload(); model.toast = .init(text: "已经重新读取", changeID: nil) }.buttonStyle(.borderless)
                }
                Text(ledgerLocation(model.store)).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                Text("一共 \(model.ledger.transactions.count) 笔流水，\(model.ledger.changes.count) 条改动记录").font(.subheadline).monospacedDigit()
                Text("账本是一个文件，app 和 AI 用的 fin 读写同一份。AI 记完账，回到 app 就能看到。导出表格在「报表」右上角。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .pageScroll()
    }

    private func macRow(_ title: String, symbol: String, value: String, chevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
            if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .hoverHighlight()
    }
    #else
    private var content: some View {
        @Bindable var model = model
        let balances = model.balances
        return Form {
            Section {
                ForEach(model.visibleAccounts) { a in
                    NavigationLink { AccountDetailView(accountID: a.id) } label: {
                        LabeledContent {
                            Text((balances[a.id] ?? .zero).formatted).monospacedDigit()
                        } label: {
                            Label(a.name + (a.isPrivate ? "（私房钱）" : ""), systemImage: a.isPrivate ? "lock.fill" : a.kind.symbol)
                        }
                    }
                }
                Button { model.sheet = .addAccount } label: { Label("加一个账户", systemImage: "plus") }
            } header: { Text("账户") } footer: { Text("点一个账户可以改名字、对一下余额、设成私房钱、删掉。") }

            Section {
                Toggle(isOn: $model.showPrivate.animation()) { Label("显示私房钱", systemImage: "lock") }
            } footer: {
                Text("私房钱账户平时不显示、不算进总览和报表。打开这个开关才看得到；关掉 app 再开会自动藏回去。")
            }

            Section {
                ForEach(model.ledger.books) { b in
                    Button {
                        bookName = b.name; renamingBook = b
                    } label: {
                        LabeledContent {
                            Text("\(model.ledger.transactions.filter { $0.bookID == b.id }.count) 笔").foregroundStyle(.secondary)
                        } label: { Label(b.name, systemImage: "book.closed") }
                    }
                    .buttonStyle(.plain)
                }
                Button { newBook = ""; addingBook = true } label: { Label("加一个账本", systemImage: "plus") }
            } header: { Text("账本") } footer: { Text("点一个账本改名字。每笔流水单独归一个账本，比如个人的和店里的分开算。") }

            Section {
                NavigationLink { CategoriesView() } label: { Label("分类（改名、合并）", systemImage: "tag") }
                #if os(iOS)
                Button { model.sheet = .importer } label: { Label("导入对账单", systemImage: "tray.and.arrow.down") }
                NavigationLink { HistoryView() } label: { Label("改动记录（能撤销）", systemImage: "clock.arrow.circlepath") }
                #endif
            }

            Section {
                Text(ledgerLocation(model.store)).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                LabeledContent("一共", value: "\(model.ledger.transactions.count) 笔流水，\(model.ledger.changes.count) 条改动记录")
                Button("重新读取账本") { model.reload(); model.toast = .init(text: "已经重新读取", changeID: nil) }
            } header: { Text("数据") } footer: {
                Text("账本是一个文件，app 和 AI 用的 fin 读写同一份。AI 记完账，回到 app 就能看到。导出表格在「报表」右上角。")
            }
        }
        .formStyle(.grouped)
        .contentMargins(.bottom, 40, for: .scrollContent)
    }
    #endif
}

/// 加一个账户：名字、类型、现在有多少钱。
struct AddAccountView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = AccountKind.bank
    @State private var isPrivate = false
    @State private var balanceText = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("名字，如「Revolut」「店里收银盒」", text: $name)
                Picker("类型", selection: $kind) {
                    ForEach(AccountKind.allCases, id: \.self) { k in Label(k.label, systemImage: k.symbol).tag(k) }
                }
                TextField("现在里面有多少钱（可以空着）", text: $balanceText).decimalKeyboard().monospacedDigit()
            }
            Section {
                Toggle("这是私房钱", isOn: $isPrivate)
            } footer: { Text("私房钱平时不显示、不算进总览，只有在「设置」里打开开关才看得到。") }
        }
        .formStyle(.grouped)
        .navigationTitle("加账户")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .errorAlert($error)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let account = Account(id: model.ledger.newAccountID(for: trimmed), name: trimmed, kind: kind, isPrivate: isPrivate)
        do {
            try model.edit { try $0.createAccount(account, openingBalance: Money(parsing: balanceText), author: model.author) }
            if isPrivate { model.showPrivate = true }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 一个账户：余额、对余额、改名字和类型、看每一笔、删掉。
struct AccountDetailView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    @State private var name = ""
    @State private var kind = AccountKind.bank
    @State private var isPrivate = false
    @State private var realText = ""
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var error: String?

    private var account: Account? { model.ledger.accounts.first { $0.id == accountID } }
    private var balance: Money { model.balances[accountID] ?? .zero }

    var body: some View {
        Group {
            if let account {
                Form {
                    Section {
                        LabeledContent("账本里算出来的余额") { Text(balance.formatted).monospacedDigit().bold() }
                        NavigationLink("看这个账户的每一笔") {
                            TransactionsView(filter: TransactionFilter(accountID: accountID), title: account.name)
                        }
                    }
                    Section {
                        TextField("银行 app 里现在显示多少", text: $realText).decimalKeyboard().monospacedDigit()
                        if let real = Money(parsing: realText) {
                            let diff = real - balance
                            if diff.cents == 0 {
                                Label("对上了，一分不差。", systemImage: "checkmark.circle.fill").foregroundStyle(Color.income)
                            } else {
                                Text("差 \(diff.formatted)。可能是有几笔还没记，或者开账那天的余额没填对。").font(.footnote)
                                Button("把差的这 \(diff.formatted) 算进开账余额") { adjust(diff) }
                            }
                        }
                    } header: { Text("对一下余额") } footer: {
                        Text("打开银行 app 看一眼余额填在这里，就知道账本和银行差多少。如果是刚开始用、以前的流水没导进来，点上面的按钮把差额算进开账余额就对上了。它不算收入也不算支出。")
                    }
                    Section("这个账户") {
                        TextField("名字", text: $name)
                        Picker("类型", selection: $kind) {
                            ForEach(AccountKind.allCases, id: \.self) { k in Label(k.label, systemImage: k.symbol).tag(k) }
                        }
                        Toggle("这是私房钱", isOn: $isPrivate)
                        Button("保存修改", action: save)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                      || (name == account.name && kind == account.kind && isPrivate == account.isPrivate))
                    }
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("删掉这个账户", systemImage: "trash") }
                    } footer: { Text("里面还有流水的账户不能删，免得账对不上。") }
                }
                .formStyle(.grouped)
                .navigationTitle(account.name)
            } else {
                ContentUnavailableView("这个账户已经删掉了", systemImage: "creditcard")
            }
        }
        .onAppear {
            guard !loaded, let account else { return }
            loaded = true
            name = account.name; kind = account.kind; isPrivate = account.isPrivate
        }
        .confirmationDialog("删掉账户「\(account?.name ?? "")」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                do {
                    try model.edit { try $0.removeAccount(accountID, author: model.author) }
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
        }
        .alert("没做成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func save() {
        guard var a = account else { return }
        a.name = name.trimmingCharacters(in: .whitespaces); a.kind = kind; a.isPrivate = isPrivate
        let updated = a
        do {
            try model.edit { try $0.updateAccount(updated, author: model.author) }
            if updated.isPrivate { model.showPrivate = true }
        } catch { self.error = error.localizedDescription }
    }

    /// 把差额并进期初余额：没有期初余额就在最早一笔流水那天记一笔。
    private func adjust(_ diff: Money) {
        let opening = model.ledger.transactions.first { $0.accountID == accountID && $0.flow == .opening }
        let firstDay = model.ledger.transactions.filter { $0.accountID == accountID }.map(\.date).min() ?? .today
        let amount = (opening?.amount ?? .zero) + diff
        do {
            try model.edit { try $0.setOpeningBalance(accountID: accountID, amount: amount, date: opening?.date ?? firstDay, author: model.author) }
            realText = ""
        } catch { self.error = error.localizedDescription }
    }
}

/// 分类：每个分类有多少笔，点一个改名；改成已有的名字就是合并。
struct CategoriesView: View {
    @Environment(LedgerModel.self) private var model
    @State private var renaming: String?
    @State private var newName = ""

    private struct Count { var name: String; var count: Int }

    private var categoryCounts: [Count] {
        var tally: [String: Int] = [:]
        for t in model.ledger.transactions where t.flow == nil {
            if let c = t.category { tally[c, default: 0] += 1 }
        }
        let list: [Count] = tally.map { Count(name: $0.key, count: $0.value) }
        return list.sorted { (a: Count, b: Count) -> Bool in
            if a.count == b.count { return a.name < b.name }
            return a.count > b.count
        }
    }

    var body: some View {
        let counts = categoryCounts
        List {
            if counts.isEmpty {
                ContentUnavailableView("还没有分类", systemImage: "tag", description: Text("记一笔时选的分类会出现在这里。"))
            }
            Section {
                ForEach(counts, id: \.name) { c in
                    Button { newName = c.name; renaming = c.name } label: {
                        LabeledContent {
                            Text("\(c.count) 笔").foregroundStyle(.secondary)
                        } label: { Label(c.name, systemImage: CategoryStyle.symbol(c.name) ?? "tag") }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                if !counts.isEmpty { Text("点一个分类改名。改成另一个已有分类的名字，两个就合并成一个，比如把「吃饭」并进「餐饮」。") }
            }
        }
        .navigationTitle("分类")
        .alert("「\(renaming ?? "")」改成什么？", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("新名字", text: $newName)
            Button("取消", role: .cancel) { renaming = nil }
            Button("改") {
                if let old = renaming, newName.trimmingCharacters(in: .whitespaces) != old {
                    model.perform { try $0.renameCategory(old, to: newName, author: model.author) }
                }
                renaming = nil
            }
        }
    }
}
