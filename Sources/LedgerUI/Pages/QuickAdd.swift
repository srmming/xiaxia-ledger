import FinanceCore
import SwiftUI

/// 记一笔 / 改一笔。
/// - 支出 / 收入 / 转账（自己账户之间挪钱，不算收支）。
/// - 金额能写算式（12,50 + 3,20），iPhone 上是带 + − 的计算器键盘。
/// - 「常记的」一排：点一下金额、名称、分类、账户全填好。
/// - 名称（以前用过的会提示，分类跟着带出来）、分类（能原地加新的）、账户、账本、日期、备注、标签、重复。
/// - 「记下」后关掉；「再记一笔」记下后清空金额和名称，接着记。
/// 改一笔（model.editingID 有值）用同一张表，按钮变成「保存」。写入都标「你」、进改动记录，能撤销。
struct QuickAdd: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss

    enum Kind: Hashable { case expense, income, transfer }

    @State var kind: Kind = .expense
    @State var amountText = ""
    @State var name = ""
    @State var category: String?
    @State var bookID = ""
    @State var accountID = ""
    @State var toAccountID = ""
    @State var date = Date()
    @State var note = ""
    @State var tags: [String] = []
    @State var tagDraft = ""
    @State var frequency: Recurring.Frequency?
    @State var error: String?
    @State var customCategory: String?
    @State var addingCategory = false
    @State var newCategory = ""
    @State var askAccount = false
    @State var askingFor: AccountSlot = .from
    @State var newName = ""
    @State var editing: FinanceCore.Transaction?
    @State var savedInARow = 0
    @State var didSetup = false
    @FocusState var focus: Field?

    enum Field: Hashable { case amount, name, category, note, tag }
    enum AccountSlot { case from, to }

    private var income: Bool { kind == .income }
    private var isTransfer: Bool { kind == .transfer }

    /// 算出来的金额（正数）。算式看不懂或者是 0 就是 nil。
    private var amount: Money? {
        guard let m = Money.evaluate(amountText), m.cents != 0 else { return nil }
        return m.magnitude
    }

    var body: some View {
        #if os(iOS)
        // 表单在上面能滑；计算器键盘和按钮固定在下面，谁也不挡谁。
        VStack(spacing: 0) {
            ScrollView { content.padding(.bottom, 12) }
                .scrollDismissesKeyboard(.interactively)
            if focus == nil {
                VStack(spacing: 8) {
                    Keypad(text: $amountText)
                    actionButtons
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .keyboard) {
                HStack { Spacer(); Button("完成") { focus = nil }.fontWeight(.semibold) }
            }
        }
        #else
        VStack(spacing: 0) {
            content
            actionButtons.padding(.horizontal, 20).padding(.bottom, 16)
        }
        #endif
    }

    // MARK: - 表单

    private var content: some View {
        VStack(spacing: 14) {
            if editing == nil || editing?.isPlainEntry == false {
                Picker("支出、收入还是转账", selection: $kind) {
                    Text("支出").tag(Kind.expense)
                    Text("收入").tag(Kind.income)
                    Text("转账").tag(Kind.transfer)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                .accessibilityIdentifier("direction")
            } else {
                Picker("支出还是收入", selection: $kind) {
                    Text("支出").tag(Kind.expense)
                    Text("收入").tag(Kind.income)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 180)
            }

            if savedInARow > 0 {
                Label("已记下 \(savedInARow) 笔，接着记下一笔", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Color.income)
            }

            amountDisplay

            if editing == nil && !isTransfer { frequentRow }

            if isTransfer {
                transferRows
            } else {
                nameField
                categoryGrid
                detailRows
            }

            if editing == nil {
                AskAIReader { ask in
                    (Text("要记分期、借款、导对账单？") + Text("跟夏夏说更快").foregroundColor(.ai))
                        .font(.caption).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                        .onTapGesture { ask("", page: "记一笔") }
                }
            }
        }
        .padding(20)
        .navigationTitle(editing == nil ? "记一笔" : "改这一笔")
        .inlineTitle()
        .onAppear(perform: setup)
        .onDisappear { model.editingID = nil }
        .onChange(of: kind) { old, new in
            guard didSetup, old != new else { return }
            if old != .transfer && new != .transfer { category = nil; customCategory = nil }
        }
        .onChange(of: bookID) { _, _ in if let c = category, !allCategories.contains(c), c != customCategory { category = nil } }
        .alert("新账户", isPresented: $askAccount) {
            TextField("名字，比如「现金」「银行卡」", text: $newName)
            Button("取消", role: .cancel) {}
            Button("加上") { addAccount() }
        } message: { Text("类型、余额以后可以在「设置 → 管理账户」里改。") }
        .errorAlert($error)
    }

    private var canSave: Bool {
        guard amount != nil, !accountID.isEmpty else { return false }
        if isTransfer { return !toAccountID.isEmpty && toAccountID != accountID }
        return category != nil
    }

    @ViewBuilder private var actionButtons: some View {
        if editing != nil {
            Button(action: { save(keepOpen: false) }) {
                Text("保存").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(.brand).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        } else {
            HStack(spacing: 10) {
                #if os(macOS)
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Spacer()
                #endif
                Button(action: { save(keepOpen: true) }) {
                    Text("再记一笔").padding(.vertical, 6).padding(.horizontal, 4)
                    #if os(iOS)
                        .frame(maxWidth: .infinity)
                    #endif
                }
                .buttonStyle(.bordered).controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!canSave)
                .help("记下这笔，表单留着接着记（⌘⇧↩）")
                Button(action: { save(keepOpen: false) }) {
                    Text("记下").font(.headline).padding(.vertical, 6)
                    #if os(iOS)
                        .frame(maxWidth: .infinity)
                    #else
                        .frame(minWidth: 100)
                    #endif
                }
                .buttonStyle(.borderedProminent).tint(.brand).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                #if os(iOS)
                .layoutPriority(1)
                #endif
            }
        }
    }

    // MARK: 金额

    private var amountDisplay: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                #if os(iOS)
                Text(amountText.isEmpty ? "0" : amountText.replacingOccurrences(of: "+", with: " + ").replacingOccurrences(of: "-", with: " − "))
                    .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(amountText.isEmpty ? Color.fg3 : amountColor)
                    .onTapGesture { focus = nil }
                #else
                TextField("0", text: $amountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(amountColor)
                    .focused($focus, equals: .amount)
                    .onSubmit { if let a = amount, Money.isExpression(amountText) { amountText = a.inputText } else { focus = .name } }
                    .fixedSize()
                    .frame(minWidth: 90)
                    .accessibilityLabel("金额，可以写算式，比如 12,50+3,20")
                #endif
                Text("€").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Color.fg3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("金额 \(amount?.spoken ?? "还没填")")
            if Money.isExpression(amountText) {
                Text(amount.map { "= \($0.formatted)" } ?? "算式还没写完")
                    .font(.callout.weight(.medium)).monospacedDigit()
                    .foregroundStyle(amount == nil ? Color.fg3 : Color.fg2)
                    .accessibilityIdentifier("amountResult")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var amountColor: Color { income ? .income : isTransfer ? .fg2 : .primary }

    // MARK: 常记的

    /// 最近常记的几笔：点一下全填好（金额、名称、分类、账户、账本），日期是今天。
    @ViewBuilder private var frequentRow: some View {
        let list = model.ledger.frequentEntries(income: income, limit: 6)
            .filter { model.visibleAccounts.contains(where: { a in a.id == $0.accountID }) }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("常记的，点一下就填好").font(.caption).foregroundStyle(Color.fg3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(list) { t in
                            Button { apply(t) } label: {
                                HStack(spacing: 5) {
                                    CategoryIcon(category: t.category, size: 18)
                                    Text(t.description).lineLimit(1)
                                    Text(t.amount.magnitude.formatted).foregroundStyle(Color.fg2).monospacedDigit()
                                }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.sunken, in: Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("再记一笔 \(t.description) \(t.amount.magnitude.formatted)")
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func apply(_ t: FinanceCore.Transaction) {
        amountText = t.amount.inputText
        name = t.description
        if let c = t.category {
            if !categories.contains(c) { customCategory = c }
            category = c
        }
        if model.visibleAccounts.contains(where: { $0.id == t.accountID }) { accountID = t.accountID }
        if let b = t.bookID, model.ledger.books.contains(where: { $0.id == b }) { bookID = b }
        note = t.note ?? ""
        tags = t.tagList
    }

    // MARK: 名称

    /// 名称：买了什么 / 在哪花的。下面一排是以前用过的名字，点一下填好，分类也带出来。
    private var nameField: some View {
        let suggestions = model.nameSuggestions(name, income: income)
        return VStack(alignment: .leading, spacing: 6) {
            TextField(income ? "名称：比如「工资」「退款」" : "名称：买了什么、在哪花的，比如「超市」", text: $name)
                .textFieldStyle(.plain)
                .focused($focus, equals: .name)
                .submitLabel(.done)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("名称")
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.name) { s in
                            Button { pick(s) } label: {
                                Text(s.name).font(.caption).lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.sunken, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("用「\(s.name)」" + (s.category.map { "，分类\($0)" } ?? ""))
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func pick(_ s: (name: String, category: String?)) {
        name = s.name
        if let c = s.category {
            if !categories.contains(c) { customCategory = c }
            category = c
        }
    }

    // MARK: 分类

    /// 格子里直接显示的分类：常用的 6 个（选过「更多」里的或新建的，就把它也放进来）。
    private var categories: [String] {
        let list = Array(allCategories.prefix(customCategory == nil ? 6 : 5))
        return list + [customCategory].compactMap { $0 }.filter { !list.contains($0) }
    }

    /// 这个账本、这个方向能选的所有分类；格子里放不下的进「更多」。
    private var allCategories: [String] { model.categories(bookID: bookID, income: income, limit: 60) }
    private var moreCategories: [String] { allCategories.filter { !categories.contains($0) } }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(categories, id: \.self) { c in
                Button { category = c } label: {
                    VStack(spacing: 4) {
                        CategoryIcon(category: c, size: 30)
                        Text(c).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(category == c ? .primary : Color.fg2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(category == c ? Color.brandSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(category == c ? Color.brand.opacity(0.5) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(category == c ? .isSelected : [])
            }
            if !moreCategories.isEmpty && !addingCategory {
                Menu {
                    ForEach(moreCategories, id: \.self) { c in
                        Button(c) { customCategory = c; category = c }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.fg2)
                            .frame(width: 30, height: 30).background(Color.sunken, in: Circle())
                        Text("更多").font(.caption).foregroundStyle(Color.fg2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.pressable).menuIndicator(.hidden)
                .accessibilityLabel("更多分类")
            }
            if addingCategory {
                VStack(spacing: 4) {
                    TextField("新分类", text: $newCategory)
                        .textFieldStyle(.plain).font(.caption).multilineTextAlignment(.center)
                        .focused($focus, equals: .category)
                        .onSubmit(useNewCategory)
                        .frame(height: 30)
                        .accessibilityLabel("新分类的名字")
                    HStack(spacing: 10) {
                        Button("取消") { addingCategory = false; focus = nil }.font(.caption).buttonStyle(.borderless)
                        Button("用") { useNewCategory() }.font(.caption.weight(.semibold)).buttonStyle(.borderless)
                            .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Button { newCategory = ""; addingCategory = true; focus = .category } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.brand)
                            .frame(width: 30, height: 30).background(Color.brandSoft, in: Circle())
                        Text("新分类").font(.caption).foregroundStyle(Color.brand)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("加一个新分类")
            }
        }
    }

    private func useNewCategory() {
        let n = newCategory.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        customCategory = n
        category = n
        addingCategory = false
        focus = nil
    }

    // MARK: 账户、账本、日期、备注、标签、重复

    private var detailRows: some View {
        VStack(spacing: 0) {
            detailRow("账户") { accountMenu(.from) }
            if model.ledger.books.count > 1 {
                Divider()
                detailRow("账本") {
                    Picker("账本", selection: $bookID) {
                        ForEach(model.ledger.books) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            Divider()
            detailRow("日期") { datePicker }
            Divider()
            detailRow("备注") {
                TextField("可不填，比如「和小王 AA」", text: $note)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .focused($focus, equals: .note)
                    .accessibilityLabel("备注")
            }
            Divider()
            tagRow
            if editing == nil {
                Divider()
                detailRow("重复") {
                    Menu {
                        Button("不重复") { frequency = nil }
                        Divider()
                        ForEach(Recurring.Frequency.allCases, id: \.self) { f in Button(f.label) { frequency = f } }
                    } label: {
                        Text(frequency?.label ?? "不重复").foregroundStyle(frequency == nil ? Color.fg2 : Color.brand)
                    }
                    .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                    .accessibilityLabel("重复：\(frequency?.label ?? "不重复")")
                }
                if let frequency {
                    Text("以后每\(frequency == .weekly ? "周" : frequency == .monthly ? "月这一天" : "年这一天")打开 app 时自动记上，能撤销；在流水页「重复记账」里能停掉。")
                        .font(.caption).foregroundStyle(Color.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var datePicker: some View {
        DatePicker("日期", selection: $date, displayedComponents: .date)
            .labelsHidden().fixedSize()
    }

    private func accountMenu(_ slot: AccountSlot) -> some View {
        let id = slot == .from ? accountID : toAccountID
        let label = slot == .from ? "账户" : "转到"
        return Menu {
            ForEach(model.visibleAccounts) { a in
                Button(a.name) { if slot == .from { accountID = a.id } else { toAccountID = a.id } }
            }
            if !model.visibleAccounts.isEmpty { Divider() }
            Button { newName = ""; askingFor = slot; askAccount = true } label: { Label("新账户…", systemImage: "plus") }
        } label: {
            Text(id.isEmpty ? "选账户" : model.accountName(id))
                .foregroundStyle(id.isEmpty ? Color.alert : .primary)
        }
        .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        .accessibilityLabel("\(label)：\(id.isEmpty ? "还没选" : model.accountName(id))")
    }

    /// 标签：已经加上的显示成小胶囊（点 × 去掉），后面能打新的；下面提示以前用过的。
    private var tagRow: some View {
        let used = model.ledger.allTags.filter { t in !tags.contains(where: { $0.lowercased() == t.lowercased() }) }
        let q = tagDraft.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
        let hints = Array(used.filter { q.isEmpty || $0.lowercased().contains(q) }.prefix(6))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("标签").foregroundStyle(Color.fg2)
                Spacer(minLength: 8)
                ForEach(tags, id: \.self) { t in
                    Button { tags.removeAll { $0 == t } } label: {
                        HStack(spacing: 2) { Text("#\(t)"); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.brandSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("去掉标签 \(t)")
                }
                TextField(tags.isEmpty ? "可不填，比如「旅行」" : "再加", text: $tagDraft)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .focused($focus, equals: .tag)
                    .onSubmit(addDraftTag)
                    .frame(minWidth: 60)
                    .accessibilityLabel("加标签")
            }
            .font(.callout)
            .frame(minHeight: 36)
            if !hints.isEmpty && (focus == .tag || tags.isEmpty) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(hints, id: \.self) { t in
                            Button { tags.append(t); tagDraft = "" } label: {
                                Text("#\(t)").font(.caption).padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Color.cardBackground, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("加标签 \(t)")
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func addDraftTag() {
        for t in Tags.clean([tagDraft]) where !tags.contains(where: { $0.lowercased() == t.lowercased() }) { tags.append(t) }
        tagDraft = ""
    }

    // MARK: 转账

    private var transferRows: some View {
        VStack(spacing: 0) {
            detailRow("从") { accountMenu(.from) }
            Divider()
            detailRow("转到") { accountMenu(.to) }
            Divider()
            detailRow("日期") { datePicker }
            Divider()
            detailRow("备注") {
                TextField("可不填，比如「取现」", text: $note)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .focused($focus, equals: .note)
            }
            if !accountID.isEmpty && accountID == toAccountID {
                Text("转出和转入要是两个不同的账户。").font(.caption).foregroundStyle(Color.alert)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            } else {
                Text("自己账户之间挪钱（取现、存进储蓄、还信用卡），不算收入也不算支出。")
                    .font(.caption).foregroundStyle(Color.fg2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 12)
        .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.fg2)
            Spacer(minLength: 12)
            content()
        }
        .font(.callout)
        .frame(minHeight: 36)
    }

    // MARK: 打开、保存

    private func setup() {
        guard !didSetup else { return }
        if let id = model.editingID, let t = model.transaction(id) {
            editing = t
            kind = t.amount.isIncome ? .income : .expense
            amountText = t.amount.inputText
            name = t.description
            category = t.category
            if let c = t.category, !categories.contains(c) { customCategory = c }
            bookID = t.bookID ?? model.defaultBookID
            accountID = t.accountID
            date = t.date.asDate
            note = t.note ?? ""
            tags = t.tagList
        } else {
            if bookID.isEmpty { bookID = model.defaultBookID }
            if accountID.isEmpty { accountID = model.defaultAccountID }
        }
        DispatchQueue.main.async { didSetup = true }
        #if os(macOS)
        // 稍等一下再把光标放进金额框：面板刚弹出来时系统还在给它找焦点。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focus = .amount }
        #endif
    }

    private func addAccount() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let a = Account(id: model.ledger.newAccountID(for: name), name: name, kind: name.contains("现金") ? .cash : .bank)
        do {
            try model.edit(quiet: true) { try $0.createAccount(a, author: model.author) }
            if askingFor == .from { accountID = a.id } else { toAccountID = a.id }
        } catch { self.error = error.localizedDescription }
    }

    private func save(keepOpen: Bool) {
        guard canSave, let amount else { return }
        if !tagDraft.trimmingCharacters(in: .whitespaces).isEmpty { addDraftTag() }
        let n = name.trimmingCharacters(in: .whitespaces)
        let text = note.trimmingCharacters(in: .whitespaces)
        let day = LocalDate(date)
        do {
            if isTransfer {
                try model.edit {
                    try $0.addAccountTransfer(amount: amount, from: accountID, to: toAccountID, date: day,
                                              note: text.isEmpty ? nil : text, author: model.author)
                }
            } else {
                guard let category else { return }
                let description = n.isEmpty ? category : n
                var tx = FinanceCore.Transaction(date: day, amount: income ? amount : -amount, description: description,
                                                 accountID: accountID, bookID: bookID.isEmpty ? nil : bookID, category: category,
                                                 source: "手记", note: text.isEmpty ? nil : text, tags: tags.isEmpty ? nil : tags)
                if let old = editing {
                    tx.id = old.id
                    tx.source = old.source
                    try model.edit { try $0.editTransaction(tx, author: model.author) }
                } else if let frequency {
                    try model.edit { try $0.addRecurring(tx, frequency: frequency, author: model.author) }
                } else {
                    try model.edit { try $0.addTransaction(tx, author: model.author) }
                }
            }
            model.lastAccountID = accountID
            if !bookID.isEmpty { model.lastBookID = bookID }
            if keepOpen {
                savedInARow += 1
                amountText = ""; name = ""; note = ""; tags = []; tagDraft = ""; frequency = nil
                category = nil; customCategory = nil
            } else {
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if os(iOS)
/// iPhone 上的计算器键盘：数字、逗号、加减、删除、清空、等于。
/// 例子：按 12,50 + 3,20，上面显示「= 15,70 €」，直接记下就是 15,70；按「=」把算式换成结果。
struct Keypad: View {
    @Binding var text: String

    static let rows: [[String]] = [["1", "2", "3", "⌫"], ["4", "5", "6", "+"], ["7", "8", "9", "−"], [",", "0", "C", "="]]

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { k in key(k) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: text)
    }

    private func key(_ k: String) -> some View {
        let isOp = ["+", "−", "=", "⌫", "C"].contains(k)
        return Button { press(k) } label: {
            Group {
                if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) }
            }
            .font(isOp ? .title3.weight(.semibold) : .title3.weight(.medium))
            .frame(maxWidth: .infinity).frame(height: 42)
            .background(isOp ? Color.sunken : Color.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .foregroundStyle(k == "=" || k == "+" || k == "−" ? Color.brand : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Self.spoken(k))
        .accessibilityIdentifier("key-\(k)")
    }

    static func spoken(_ k: String) -> String {
        switch k {
        case "⌫": "删除"
        case ",": "小数点"
        case "+": "加"
        case "−": "减"
        case "=": "等于"
        case "C": "清空"
        default: k
        }
    }

    /// 现在正在输的那一个数（最后一个加减号后面的部分）。
    private var currentTerm: Substring {
        if let i = text.lastIndex(where: { $0 == "+" || $0 == "-" }) { return text[text.index(after: i)...] }
        return text[...]
    }

    func press(_ k: String) {
        switch k {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case "C": text = ""
        case "=":
            if let m = Money.evaluate(text) { text = m.cents == 0 ? "" : m.magnitude.inputText }
        case "+", "−":
            let op: Character = k == "+" ? "+" : "-"
            guard !text.isEmpty else { return }
            if let last = text.last, last == "+" || last == "-" || last == "," { text.removeLast() }
            if !text.isEmpty { text.append(op) }
        case ",":
            if !currentTerm.contains(",") { text += currentTerm.isEmpty ? "0," : "," }
        default:
            let term = currentTerm
            if let comma = term.firstIndex(of: ","), term.distance(from: comma, to: term.endIndex) > 2 { return }
            if term.count >= 8 || text.count >= 24 { return }
            if term == "0" { text.removeLast() }
            text += k
        }
    }
}
#endif
