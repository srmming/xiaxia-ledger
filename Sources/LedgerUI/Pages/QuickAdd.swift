import FinanceCore
import SwiftUI

/// 记一笔：支出 / 收入、金额、名称（以前用过的会提示，分类跟着带出来）、分类（能原地加新的）、
/// 账户、账本、日期（任意一天）、备注。拆单、分期、导对账单交给夏夏。记下的这笔标「你」，写进改动记录，能撤销。
struct QuickAdd: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var income = false
    @State var amountText = ""
    @State var name = ""
    @State var category: String?
    @State var bookID = ""
    @State var accountID = ""
    @State var date = Date()
    @State var note = ""
    @State var error: String?
    @State var customCategory: String?
    @State var addingCategory = false
    @State var askAccount = false
    @State var newName = ""
    @FocusState var focus: Field?

    enum Field: Hashable { case amount, name, category, note }

    private var amount: Money? {
        guard let m = Money(parsing: amountText.replacingOccurrences(of: " ", with: "")), m.cents != 0 else { return nil }
        return m.magnitude
    }

    var body: some View {
        #if os(iOS)
        ScrollView { content }
            .scrollDismissesKeyboard(.interactively)
            // 「记下」钉在底部，键盘和数字键盘再长也不用往下翻才找得到。
            // 数字键盘和「记下」钉在底部，上面的名称、分类、账户可以滑动；不用往下翻才找得到按钮。
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if focus == nil { Keypad(text: $amountText) }
                    Button(action: save) {
                        Text("记下").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(.brand).controlSize(.large)
                    .disabled(!canSave)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)
                .background(.bar)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        #else
        content
        #endif
    }

    private var content: some View {
        VStack(spacing: 14) {
            Picker("支出还是收入", selection: $income) {
                Text("支出").tag(false)
                Text("收入").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            .accessibilityIdentifier("direction")

            amountDisplay

            nameField

            categoryGrid

            VStack(spacing: 0) {
                detailRow("账户") {
                    Menu {
                        ForEach(model.visibleAccounts) { a in Button(a.name) { accountID = a.id } }
                        if !model.visibleAccounts.isEmpty { Divider() }
                        Button { newName = ""; askAccount = true } label: { Label("新账户…", systemImage: "plus") }
                    } label: {
                        Text(accountID.isEmpty ? "选账户" : model.accountName(accountID))
                            .foregroundStyle(accountID.isEmpty ? Color.alert : .primary)
                    }
                    .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                    .accessibilityLabel("账户：\(accountID.isEmpty ? "还没选" : model.accountName(accountID))")
                }
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
                detailRow("日期") {
                    DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        .labelsHidden().fixedSize()
                }
                Divider()
                detailRow("备注") {
                    TextField("可不填", text: $note)
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .focused($focus, equals: .note)
                }
            }
            .padding(.horizontal, 12)
            .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            #if os(macOS)
            HStack(spacing: 10) {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Spacer()
                Button(action: save) { Text("记下").frame(minWidth: 120) }
                    .buttonStyle(.borderedProminent).tint(.brand).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            #endif

            AskAIReader { ask in
                (Text("要拆单、记分期、导对账单？") + Text("跟夏夏说更快").foregroundColor(.ai))
                    .font(.caption).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                    .onTapGesture { ask("", page: "记一笔") }
            }
        }
        .padding(20)
        .navigationTitle("记一笔")
        .inlineTitle()
        .onAppear(perform: setup)
        .onChange(of: income) { _, _ in category = nil; customCategory = nil }
        .alert("新账户", isPresented: $askAccount) {
            TextField("名字，比如「现金」「银行卡」", text: $newName)
            Button("取消", role: .cancel) {}
            Button("加上") { addAccount() }
        } message: { Text("类型、余额以后可以在「设置 → 管理账户」里改。") }
        .onChange(of: bookID) { _, _ in if let c = category, !categories.contains(c) { category = nil } }
        .errorAlert($error)
        .sheet(isPresented: $addingCategory) {
            // 先挑图标再填名字；建好就直接选中。
            NavigationStack {
                CategoryCreator(income: income, showsDirection: false, allowExisting: true) { name in customCategory = name; category = name }
            }
        }
    }

    private var canSave: Bool { amount != nil && category != nil && !accountID.isEmpty }

    /// 格子里直接显示的分类：常用的 6 个（选过「更多」里的或新建的，就把它也放进来）。
    private var categories: [String] {
        let list = Array(allCategories.prefix(customCategory == nil ? 6 : 5))
        return list + [customCategory].compactMap { $0 }.filter { !list.contains($0) }
    }

    /// 这个账本、这个方向能选的所有分类；格子里放不下的进「更多」。
    private var allCategories: [String] { model.categories(bookID: bookID, income: income, limit: 60) }
    private var moreCategories: [String] { allCategories.filter { !categories.contains($0) } }

    private func detailRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.fg2)
            Spacer(minLength: 12)
            content()
        }
        .font(.callout)
        .frame(minHeight: 36)
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            #if os(iOS)
            Text(amountText.isEmpty ? "0" : amountText)
                .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(amountText.isEmpty ? Color.fg3 : (income ? Color.income : .primary))
                .onTapGesture { focus = nil }
            #else
            TextField("0", text: $amountText)
                .textFieldStyle(.plain)
                .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(income ? Color.income : .primary)
                .focused($focus, equals: .amount)
                .onSubmit { focus = .name }
                .fixedSize()
                .frame(minWidth: 90)
            #endif
            Text(Currencies.info(accountID.isEmpty ? model.ledger.baseCurrency : model.ledger.currency(ofAccount: accountID)).symbol).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Color.fg3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("金额 \(amount?.spoken ?? "还没填")")
    }

    /// 名称：买了什么 / 在哪花的。下面一排是以前用过的名字，点一下填好，分类也带出来。
    private var nameField: some View {
        let suggestions = model.nameSuggestions(name, income: income)
        return VStack(alignment: .leading, spacing: 6) {
            TextField(income ? "名称：比如「工资」「退款」" : "名称：买了什么、在哪花的，比如「超市」", text: $name)
                .textFieldStyle(.plain)
                .focused($focus, equals: .name)
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
            if !moreCategories.isEmpty {
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
            Group {
                Button { addingCategory = true } label: {
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

    private func setup() {
        if bookID.isEmpty { bookID = model.defaultBookID }
        if accountID.isEmpty { accountID = model.defaultAccountID }
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
            accountID = a.id
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard let amount, let category, !accountID.isEmpty else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        let text = note.trimmingCharacters(in: .whitespaces)
        let description = n.isEmpty ? (text.isEmpty ? category : text) : (text.isEmpty ? n : "\(n)（\(text)）")
        let tx = Transaction(date: LocalDate(date), amount: income ? amount : -amount, description: description,
                             accountID: accountID, bookID: bookID, category: category, source: "手记")
        do {
            try model.edit { try $0.addTransaction(tx, author: model.author) }
            model.lastAccountID = accountID
            model.lastBookID = bookID
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if os(iOS)
/// iPhone 上的数字键盘：1–9、逗号、0、删除。
struct Keypad: View {
    @Binding var text: String

    var body: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(keys, id: \.self) { k in
                Button { press(k) } label: {
                    Group {
                        if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) }
                    }
                    .font(.title3.weight(.medium))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(k == "⌫" ? "删除" : k == "," ? "小数点" : k)
            }
        }
        .sensoryFeedback(.selection, trigger: text)
    }

    private func press(_ k: String) {
        switch k {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case ",":
            if !text.contains(",") { text += text.isEmpty ? "0," : "," }
        default:
            if let comma = text.firstIndex(of: ","), text.distance(from: comma, to: text.endIndex) > 2 { return }
            if text.count >= 9 { return }
            text = text == "0" ? k : text + k
        }
    }
}
#endif
