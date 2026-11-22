import FinanceCore
import SwiftUI

// 管理账本、账户、分类。都用系统 Form，每一步写进改动记录，能撤销。

// MARK: - 账本

/// 账本：新建、改名、删除。删的时候里面有东西，先选一个账本挪过去。
struct BookManager: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var newName = ""
    @State var newKind: BookKind = .personal
    @State var renaming: Book?
    @State var renameText = ""
    @State var deleting: Book?
    @State var moveTo = ""
    @State var error: String?

    var body: some View {
        Form {
            Section {
                ForEach(model.ledger.books) { b in
                    row(b)
                }
            } header: { Text("账本") } footer: {
                Text("每个账本有自己的收支和报表，看板上可以只看一个，也可以看「全部」。账户可以在几个账本之间混用。")
            }
            Section("新建账本") {
                FormField("名字", "比如「家庭」「第二家店」", text: $newName)
                    .onSubmit(add)
                Picker("用来记", selection: $newKind) {
                    ForEach(BookKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("新建", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("管理账本")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .alert("给账本改名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("新名字", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("改名") { rename() }
        }
        .sheet(item: $deleting) { b in deleteSheet(b) }
        .errorAlert($error)
    }

    private func row(_ b: Book) -> some View {
        let usage = model.ledger.bookUsage(b.id)
        return HStack(spacing: 12) {
            Monogram(text: b.name, color: model.bookColor(b.id), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.name).font(.body.weight(.medium))
                Text("\(b.isBusiness ? "生意" : "生活") · \(usage.transactions) 笔流水\(usage.plans > 0 ? " · \(usage.plans) 个计划" : "")")
                    .font(.caption).foregroundStyle(Color.fg2)
            }
            Spacer()
            Menu {
                Button("改名…") { renameText = b.name; renaming = b }
                Button("删除…", role: .destructive) {
                    moveTo = model.ledger.books.first { $0.id != b.id }?.id ?? ""
                    deleting = b
                }
                .disabled(model.ledger.books.count < 2)
            } label: { Image(systemName: "ellipsis.circle").imageScale(.large) }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                .accessibilityLabel("\(b.name) 的操作")
        }
    }

    private func deleteSheet(_ b: Book) -> some View {
        let usage = model.ledger.bookUsage(b.id)
        let total = usage.transactions + usage.plans
        return NavigationStack {
            Form {
                Section {
                    if total == 0 {
                        Text("「\(b.name)」里还没有东西，删掉不影响别的账本。删错了可以在改动记录里撤销。")
                    } else {
                        Text("「\(b.name)」里有 \(usage.transactions) 笔流水\(usage.plans > 0 ? "、\(usage.plans) 个借款 / 分期 / 目标" : "")。删之前要把它们挪到另一个账本，钱不会丢。删错了可以在改动记录里撤销。")
                        Picker("挪到", selection: $moveTo) {
                            ForEach(model.ledger.books.filter { $0.id != b.id }) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("删除「\(b.name)」")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { deleting = nil } }
                ToolbarItem(placement: .destructiveAction) {
                    Button(total == 0 ? "删除" : "挪过去并删除", role: .destructive) { remove(b, move: total > 0) }
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 260)
        #else
        .presentationDetents([.medium])
        #endif
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try model.edit { try $0.addBook(name: name, kind: newKind, author: model.author) }
            newName = ""
        } catch { self.error = error.localizedDescription }
    }

    private func rename() {
        guard let b = renaming else { return }
        renaming = nil
        do { try model.edit { try $0.renameBook(b.id, to: renameText, author: model.author) } }
        catch { self.error = error.localizedDescription }
    }

    private func remove(_ b: Book, move: Bool) {
        deleting = nil
        do { try model.edit { try $0.removeBook(b.id, moveTo: move ? moveTo : nil, author: model.author) } }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - 账户

/// 账户：加、改名 / 类型 / 私房钱、删（里面有流水不让删）。
struct AccountManager: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var editing: AccountDraft?
    @State var error: String?

    var body: some View {
        let balances = model.balances
        Form {
            Section {
                if model.ledger.accounts.isEmpty {
                    Text("还没有账户。加一个银行卡、现金或信用卡，记一笔时就能选。").foregroundStyle(Color.fg2)
                }
                ForEach(model.ledger.accounts) { a in
                    Button { editing = AccountDraft(a) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: a.kind.symbol).foregroundStyle(Color.fg2).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).foregroundStyle(.primary)
                                Text([a.kind.label, a.institution == a.name ? nil : a.institution, a.isPrivate ? "私房钱" : nil].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Color.fg2)
                            }
                            Spacer()
                            Text(model.balanceText(a.id)).font(.kitAmount).foregroundStyle(Color.fg2)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.fg3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("账户") } footer: {
                Text("导入对账单时 AI 也会顺手建账户。私房钱账户默认不显示、不算进总数。")
            }
            Section {
                Button { editing = AccountDraft() } label: { Label("加一个账户", systemImage: "plus") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("管理账户")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(item: $editing) { d in
            NavigationStack { AccountEditor(draft: d) }
                .environment(model)
                #if os(macOS)
                .frame(width: 420, height: 420)
                #endif
        }
        .errorAlert($error)
    }
}

struct AccountDraft: Identifiable {
    var id = UUID()
    var original: Account?
    var name = ""
    var kind: AccountKind = .bank
    var institution = ""
    var isPrivate = false
    var opening = ""
    /// 空 = 主币种。
    var currency = ""

    init() {}
    init(_ a: Account) {
        original = a; name = a.name; kind = a.kind; institution = a.institution ?? ""; isPrivate = a.isPrivate; currency = a.currency ?? ""
    }
}

struct AccountEditor: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var draft: AccountDraft
    @State var error: String?
    @State var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TextField("名字", text: $draft.name)
                Picker("类型", selection: $draft.kind) {
                    ForEach(AccountKind.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                FormField("银行或机构", "可不填", text: $draft.institution)
                Toggle("私房钱", isOn: $draft.isPrivate)
                CurrencyPicker(title: "币种", selection: $draft.currency)
            } footer: {
                if !draft.currency.isEmpty && draft.currency != model.ledger.baseCurrency {
                    Text("这个账户的流水按\(Currencies.info(draft.currency).name)记，看板上按当天汇率换成\(Currencies.info(model.ledger.baseCurrency).name)。")
                }
            }
            if draft.original == nil {
                Section {
                    FormField("现在的余额", "可不填，比如 1.250,00", text: $draft.opening)
                        .decimalKeyboard()
                } footer: { Text("记成开账余额，不算收入。信用卡欠款写负数。") }
            } else {
                Section {
                    Button("删除这个账户", role: .destructive) { confirmDelete = true }
                } footer: { Text("里面还有流水时不能删，先把流水删掉或改到别的账户。") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.original == nil ? "加账户" : "改账户")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("删除「\(draft.name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: remove)
        } message: { Text("删错了可以在改动记录里撤销。") }
        .errorAlert($error)
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        let inst = draft.institution.trimmingCharacters(in: .whitespaces)
        do {
            if var a = draft.original {
                a.name = name; a.kind = draft.kind; a.institution = inst.isEmpty ? nil : inst; a.isPrivate = draft.isPrivate
                if a != draft.original { try model.edit { try $0.updateAccount(a, author: model.author) } }
                let newCode = draft.currency.isEmpty ? model.ledger.baseCurrency : draft.currency
                if newCode != model.ledger.currency(ofAccount: a.id) {
                    try model.edit { try $0.setAccountCurrency(a.id, newCode, author: model.author) }
                }
            } else {
                var opening: Money?
                let text = draft.opening.replacingOccurrences(of: " ", with: "")
                if !text.isEmpty {
                    guard let m = Money(parsing: text) else { error = "余额看不懂，写成 1.250,00 这样。"; return }
                    opening = m
                }
                let code = draft.currency.isEmpty || draft.currency == model.ledger.baseCurrency ? nil : draft.currency
                let a = Account(id: model.ledger.newAccountID(for: name), name: name, kind: draft.kind,
                                institution: inst.isEmpty ? nil : inst, isPrivate: draft.isPrivate, currency: code)
                try model.edit { try $0.createAccount(a, openingBalance: opening, author: model.author) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func remove() {
        guard let a = draft.original else { return }
        do {
            try model.edit { try $0.removeAccount(a.id, author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - 分类

/// 分类：看每个分类用了多少笔，改名或并进另一个分类，也能新建（记一笔里也能直接加）。
struct CategoryManager: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var renaming: String?
    @State var renameText = ""
    @State var newName = ""
    @State var newIncome = false
    @State var error: String?

    private var counts: [(name: String, count: Int)] {
        var c: [String: Int] = [:]
        for t in model.ledger.transactions where t.flow == nil { if let k = t.category { c[k, default: 0] += 1 } }
        for x in model.ledger.profile.categories where c[x.name] == nil { c[x.name] = 0 }
        return c.map { ($0.key, $0.value) }.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    var body: some View {
        Form {
            Section {
                let list = counts
                if list.isEmpty {
                    Text("还没有分类。记一笔或导入流水后，这里会列出用过的分类。").foregroundStyle(Color.fg2)
                }
                ForEach(list, id: \.name) { item in
                    Button { renameText = item.name; renaming = item.name } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: item.name, size: 26)
                            Text(item.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(item.count) 笔").foregroundStyle(Color.fg2).monospacedDigit()
                            Image(systemName: "pencil").font(.caption).foregroundStyle(Color.fg3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("改名或并进别的分类")
                }
            } header: { Text("分类") } footer: {
                Text("改成一个已有的名字，就是把两个分类并成一个。")
            }
            Section {
                FormField("名字", "比如「宠物」「学费」", text: $newName)
                    .onSubmit(add)
                Picker("用在", selection: $newIncome) {
                    Text("支出").tag(false)
                    Text("收入").tag(true)
                }
                .pickerStyle(.segmented)
                Button("新建", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: { Text("新建分类") } footer: { Text("记一笔时也能点「＋ 新分类」当场加。") }
        }
        .formStyle(.grouped)
        .navigationTitle("管理分类")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .alert("改分类名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("新名字", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("改名") {
                guard let old = renaming else { return }
                renaming = nil
                do { try model.edit { try $0.renameCategory(old, to: renameText, author: model.author) } }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("这个分类下的流水会一起改。") }
        .errorAlert($error)
    }

    private func add() {
        do {
            try model.edit { try $0.addCategory(newName, income: newIncome, author: model.author) }
            newName = ""
        } catch { self.error = error.localizedDescription }
    }
}
