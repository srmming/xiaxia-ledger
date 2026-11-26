import FinanceCore
import SwiftUI

/// 记一笔 / 改一笔。
/// - 支出 / 收入 / 转账（自己账户之间挪钱，不算收支）。
/// - 金额能写算式（12,50 + 3,20），iPhone 上是带 + − 的计算器键盘。
/// - 「常记的」一排：点一下金额、名称、分类、账户全填好。
/// - 从上到下：金额 → 账户 · 账本 · 日期（一行小标签）→ 分类（全部铺开，一页两行左右翻）→ 名称 → 备注、标签、重复。
/// - 「记下」后关掉；「再记一笔」记下后清空金额和名称，接着记。
/// 改一笔（model.editingID 有值）用同一张表，按钮变成「保存」。写入都标「你」、进改动记录，能撤销。
struct QuickAdd: View {
    @AppStorage(AILayer.storageKey) private var aiInPages = false
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
    @State var askAccount = false
    @State var askingFor: AccountSlot = .from
    @State var newName = ""
    @State var editing: FinanceCore.Transaction?
    @State var savedInARow = 0
    @State var didSetup = false
    /// 分类、名称提示、常记的、用过的标签：打开时和换方向 / 账本时算一次。
    /// 别每按一个键都把整本账翻一遍，账本大了打字会卡。
    @State var lists = Lists()
    /// iPhone：计算器键盘露着没。选好分类就收起来，露出账户、日期、备注；点金额再弹出来。
    @State var keypadUp = true
    /// 分类翻到第几页（一页两行，左右滑或点下面的小圆点翻）。
    @State var categoryPage: Int? = 0
    @FocusState var focus: Field?

    enum Field: Hashable { case amount, name, category, note, tag }
    enum AccountSlot { case from, to }

    struct Lists {
        var categories: [String] = []
        var names: [(name: String, category: String?)] = []
        var frequent: [FinanceCore.Transaction] = []
        var tags: [String] = []
    }

    private func refreshLists() {
        let visible = Set(model.visibleAccounts.map(\.id))
        lists = Lists(
            categories: model.categories(bookID: bookID, income: income, limit: 60),
            names: model.nameSuggestions("", income: income, limit: 500),
            // 常记的只拿这一边的（店里记一笔不出现咖啡、会员这些自己的东西）。
            frequent: model.ledger.frequentEntries(income: income, limit: 12).filter { t in
                visible.contains(t.accountID)
                    && (!model.businessOn || model.ledger.side(of: t) == (shopMode ? .business : .life))
            }.prefix(6).map { $0 },
            tags: model.ledger.allTags)
    }

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
            // 打字（名称、备注、标签）时收起计算器键盘，按钮一直在。
            VStack(spacing: 8) {
                if focus == nil && keypadUp { Keypad(text: $amountText) }
                actionButtons
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .keyboard) {
                HStack { Spacer(); Button(tr("完成")) { focus = nil }.fontWeight(.semibold) }
            }
        }
        #else
        // Mac 版（ming 2026-11-25 重做）：系统表单的排法，一行一项，键盘 Tab 走到底；按钮那排固定在底下。
        VStack(spacing: 0) {
            content
            Divider()
            actionButtons.padding(.horizontal, 20).padding(.vertical, 12)
        }
        #endif
    }

    // MARK: - 表单

    @ViewBuilder private var form: some View {
        #if os(macOS)
        macForm
        #else
        phoneForm
        #endif
    }

    private var phoneForm: some View {
        VStack(spacing: 14) {
            // 说一句 / 拍小票：不填表，先存成「待记录」，夏夏或自己之后补进账本（ming 2026-11-23）。
            if editing == nil { CaptureBar() }
            if editing == nil || editing?.isPlainEntry == false {
                Picker(tr("支出、收入还是转账"), selection: $kind) {
                    Text(tr("支出")).tag(Kind.expense)
                    Text(tr("收入")).tag(Kind.income)
                    Text(tr("转账")).tag(Kind.transfer)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                .accessibilityIdentifier("direction")
            } else {
                Picker(tr("支出还是收入"), selection: $kind) {
                    Text(tr("支出")).tag(Kind.expense)
                    Text(tr("收入")).tag(Kind.income)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 180)
            }

            #if os(iOS)
            if savedInARow > 0 { savedNotice }
            #endif

            amountDisplay

            if isTransfer {
                transferRows
            } else {
                // 账户、账本、日期紧挨着金额，一眼看到、不用往下翻。
                contextBar
                categoryGrid
                nameField
                if editing == nil && name.isEmpty { frequentRow }
                detailRows
            }

            if editing == nil && aiInPages {
                AskAIReader { ask in
                    (Text(tr("要记分期、借款、导对账单？")) + Text(tr("跟夏夏说更快")).foregroundColor(.ai))
                        .font(.caption).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                        .onTapGesture { ask("", page: "记一笔") }
                }
            }
        }
        .padding(20)
    }

    private var content: some View {
        form
        .navigationTitle(editing != nil ? tr("改这一笔") : shopMode ? tr("店里记一笔") : tr("记一笔"))
        .inlineTitle()
        .onAppear(perform: setup)
        .onDisappear { model.editingID = nil }
        .onChange(of: kind) { old, new in
            guard didSetup, old != new else { return }
            refreshLists()
            if old != .transfer && new != .transfer { category = nil; customCategory = nil }
        }
        .onChange(of: model.ledger.changes.count) { _, _ in if didSetup { refreshLists() } }
        .onChange(of: model.ledger.profile.categories.count) { _, _ in if didSetup { refreshLists() } }
        // 分类是点名字、常记的带出来的：翻到它那一页，让人看见选中了哪个。
        // 同一个值只挂一个 onChange（挂两个时 iPhone 上只有一个会跑）。
        .onChange(of: category) { _, c in
            guard let c else { return }
            #if os(iOS)
            // 选好分类、金额也有了：收起键盘，露出下面的名称、备注。
            if amount != nil { withAnimation(.snappy) { keypadUp = false } }
            #endif
            // 分类是点名字、常记的带出来的：翻到它那一页，让人看见选中了哪个。
            if let i = categoryPages.firstIndex(where: { $0.contains(c) }), i != categoryPage {
                withAnimation(.snappy) { categoryPage = i }
            }
        }
        .onChange(of: bookID) { _, _ in if didSetup { refreshLists() }; if let c = category, !allCategories.contains(c), c != customCategory { category = nil } }
        .alert(tr("新账户"), isPresented: $askAccount) {
            TextField(tr("名字，比如「现金」「银行卡」"), text: $newName)
            Button(tr("取消"), role: .cancel) {}
            Button(tr("加上")) { addAccount() }
        } message: { Text(tr("类型、余额以后可以在「设置 → 管理账户」里改。")) }
        .errorAlert($error)
        .sheet(isPresented: $addingCategory) {
            // 先挑图标再填名字；建好就直接选中。
            NavigationStack {
                CategoryCreator(income: income, showsDirection: false, allowExisting: true) { name in customCategory = name; category = name }
            }
        }
    }

    private var canSave: Bool {
        guard amount != nil, !accountID.isEmpty else { return false }
        if isTransfer { return !toAccountID.isEmpty && toAccountID != accountID }
        return category != nil
    }

    @ViewBuilder private var actionButtons: some View {
        if editing != nil {
            Button(action: { save(keepOpen: false) }) {
                Text(tr("保存")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(SolidButtonStyle(color: solidTint, large: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        } else {
            HStack(spacing: 10) {
                #if os(macOS)
                // 取消用系统默认的灰色，不跟着橙色 / 青色（审查 2026-11-26：店里记一笔的取消是橙字）。
                Button { dismiss() } label: { Text(tr("取消")).foregroundStyle(.primary) }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                // Mac 上放在按钮这一排，不往上加一行：面板不会变高、把按钮挤出窗口。
                if savedInARow > 0 { savedNotice.padding(.leading, 8) }
                Spacer()
                #endif
                Button(action: { save(keepOpen: true) }) {
                    Text(tr("再记一笔")).padding(.vertical, 6).padding(.horizontal, 4).lineLimit(1)
                }
                // 按不了时也看得清（淡一点的主色），不像系统灰按钮那样「隐形」。
                .buttonStyle(SoftButtonStyle(color: tint, background: tint.opacity(0.14)))
                .controlSize(.large)
                .fixedSize()
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!canSave)
                .help(tr("记下这笔，表单留着接着记（⌘⇧↩）"))
                Button(action: { save(keepOpen: false) }) {
                    Text(tr("记下")).font(.headline).padding(.vertical, 6)
                    #if os(iOS)
                        .frame(maxWidth: .infinity)
                    #else
                        .frame(minWidth: 100)
                    #endif
                }
                .buttonStyle(SolidButtonStyle(color: solidTint, large: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
    }

    @ViewBuilder private var savedNotice: some View {
        #if os(iOS)
        Label(tr("已记下 \(savedInARow) 笔，接着记下一笔"), systemImage: "checkmark.circle.fill")
            .font(.caption).foregroundStyle(Color.income)
        #else
        Label(tr("已记下 \(savedInARow) 笔"), systemImage: "checkmark.circle.fill")
            .font(.caption).foregroundStyle(Color.income).lineLimit(1).fixedSize()
        #endif
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
                    .onTapGesture { focus = nil; withAnimation(.snappy) { keypadUp = true } }
                #else
                // 不给标题：放在表单里时标题会变成左边一个灰色的「0」，像又一个空框（审查 2026-11-26）。
                TextField(tr("金额"), text: $amountText, prompt: Text(verbatim: "0"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(amountColor)
                    .focused($focus, equals: .amount)
                    .onSubmit { if let a = amount, Money.isExpression(amountText) { amountText = a.inputText } else { focus = .name } }
                    .fixedSize()
                    .frame(minWidth: 44)
                    .accessibilityLabel(tr("金额，可以写算式，比如 12,50+3,20"))
                #endif
                Text(Currencies.info(accountID.isEmpty ? model.ledger.baseCurrency : model.ledger.currency(ofAccount: accountID)).symbol).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Color.fg3)
            }
            #if os(iOS)
            // iPhone 上金额是一行字（键盘是自己的），合成一个元素读「金额 xx」。
            // Mac 上里面是能打字的输入框，不合并，不然 VoiceOver 和辅助功能拿不到输入框。
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tr("金额 \(amount?.spoken ?? tr("还没填"))"))
            .accessibilityAction { focus = nil; keypadUp = true }
            .accessibilityHint(keypadUp ? "" : tr("点一下弹出计算器键盘"))
            #endif
            #if os(iOS)
            if !keypadUp && focus == nil && !Money.isExpression(amountText) {
                Text(tr("点金额可以改")).font(.caption2).foregroundStyle(Color.fg3)
            }
            #endif
            if Money.isExpression(amountText) {
                Text(amount.map { "= \($0.formatted(in: accountID.isEmpty ? model.ledger.baseCurrency : model.ledger.currency(ofAccount: accountID)))" } ?? tr("算式还没写完"))
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
        let list = lists.frequent
        if !list.isEmpty {
            // 同一个名字只留一个（不同金额的公交卡别排两个一模一样的）。
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("常记的，点一下就填好")).font(.caption).foregroundStyle(Color.fg3)
                // Mac：放得下几个放几个，换行，不会把最后一个切掉一半（审查 2026-11-26）。
                #if os(macOS)
                FlowLayout(spacing: 6) { frequentChips(list) }
                #else
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { frequentChips(list) }.padding(.horizontal, 1)
                }
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func frequentChips(_ list: [FinanceCore.Transaction]) -> some View {
        ForEach(list.reduce(into: [FinanceCore.Transaction]()) { out, t in
            if !out.contains(where: { $0.description == t.description }) { out.append(t) }
        }) { t in
            Button { apply(t) } label: {
                HStack(spacing: 5) {
                    CategoryIcon(category: t.category, size: 18)
                    Text(t.description).lineLimit(1).truncationMode(.tail).frame(maxWidth: 150, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Text(t.amount.magnitude.formatted(in: model.ledger.currency(ofAccount: t.accountID))).foregroundStyle(Color.fg2).monospacedDigit()
                }
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.sunken, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(tr("再记一笔 \(t.description) \(t.amount.magnitude.formatted)"))
        }
    }

    private func apply(_ t: FinanceCore.Transaction) {
        amountText = t.amount.inputText
        name = t.description
        if let c = t.category {
            if !allCategories.contains(c) { customCategory = c }
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
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        // 没打字时下面有「常记的」，这里就不再排一行名字。
        let suggestions = q.isEmpty && editing == nil && !lists.frequent.isEmpty ? []
            : Array(lists.names.lazy.filter { q.isEmpty || ($0.name.lowercased().contains(q) && $0.name.lowercased() != q) }.prefix(5))
        return VStack(alignment: .leading, spacing: 6) {
            TextField(income ? tr("名称，比如「工资」") : tr("名称，比如「超市」"), text: $name)
                .textFieldStyle(.plain)
                .focused($focus, equals: .name)
                .submitLabel(.done)
                // 打的名字以前用过：回车就把上次的分类也带上（Mac 上不用摸鼠标就能记下）。
                .onSubmit {
                    let n = name.trimmingCharacters(in: .whitespaces).lowercased()
                    guard category == nil, !n.isEmpty else { return }
                    if let hit = lists.names.first(where: { $0.name.lowercased() == n }) { pick(hit) }
                    // 名字就是某个分类（「超市」「房租」）：直接选上这个分类。
                    else if let c = allCategories.first(where: { $0.lowercased() == n }) { category = c }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(tr("名称"))
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
                            .accessibilityLabel(tr("用「\(s.name)」") + (s.category.map { tr("，分类\($0)") } ?? ""))
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
            if !allCategories.contains(c) { customCategory = c }
            category = c
        }
    }

    // MARK: 分类

    /// 这个账本、这个方向能选的所有分类，常用的在前。
    private var allCategories: [String] { lists.categories }

    /// 一页 10 个（5 列 × 2 行），常用的在第一页。不再藏进「更多」：左右滑或点小圆点翻页。
    private static let perPage = 10
    private var categoryPages: [[String]] {
        var all = allCategories
        if let c = customCategory, !all.contains(c) { all.insert(c, at: 0) }
        return stride(from: 0, to: all.count, by: Self.perPage).map { Array(all[$0..<min($0 + Self.perPage, all.count)]) }
    }

    private var categoryGrid: some View {
        let pages = categoryPages
        return VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(pages.indices, id: \.self) { i in
                        // 不用 LazyVGrid：放在横向翻页里时 iPhone 上最后一格有时画不出来。
                        VStack(spacing: 4) {
                            ForEach(Array(stride(from: 0, to: pages[i].count, by: 5)), id: \.self) { start in
                                HStack(spacing: 4) {
                                    ForEach(pages[i][start..<min(start + 5, pages[i].count)], id: \.self) { c in categoryCell(c) }
                                    ForEach(0..<(5 - min(5, pages[i].count - start)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                                }
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .containerRelativeFrame(.horizontal)
                        .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $categoryPage)
            // 翻页圆点在中间，「新分类」一直在右边，翻到哪页都点得到。
            ZStack {
                if pages.count > 1 { pageDots(pages.count) }
                HStack { Spacer(); newCategoryButton }
            }
        }
    }

    private func categoryCell(_ c: String) -> some View {
        Button { category = c } label: {
            VStack(spacing: 3) {
                CategoryIcon(category: c, size: 28)
                Text(c).font(.caption2).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(category == c ? .primary : Color.fg2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(category == c ? Color.brandSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(category == c ? Color.brand.opacity(0.5) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(c)
        .accessibilityAddTraits(category == c ? .isSelected : [])
    }

    private var newCategoryButton: some View {
        Button { addingCategory = true } label: {
            Label(tr("新分类"), systemImage: "plus").font(.caption.weight(.medium)).foregroundStyle(Color.brand)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(tr("加一个新分类"))
    }

    /// 翻页的小圆点；Mac 上两边再加箭头（鼠标没法左右滑）。
    private func pageDots(_ count: Int) -> some View {
        let current = categoryPage ?? 0
        return HStack(spacing: 6) {
            #if os(macOS)
            Button { withAnimation(.snappy) { categoryPage = max(0, current - 1) } } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless).disabled(current == 0).accessibilityLabel(tr("上一页分类"))
            #endif
            ForEach(0..<count, id: \.self) { i in
                Button { withAnimation(.snappy) { categoryPage = i } } label: {
                    Circle().fill(i == current ? Color.brand : Color.fg3.opacity(0.4)).frame(width: 6, height: 6)
                        .padding(4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("分类第 \(i + 1) 页，共 \(count) 页"))
            }
            #if os(macOS)
            Button { withAnimation(.snappy) { categoryPage = min(count - 1, current + 1) } } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless).disabled(current >= count - 1).accessibilityLabel(tr("下一页分类"))
            #endif
        }
        .font(.caption.weight(.semibold)).foregroundStyle(Color.fg2)
    }

    // MARK: 金额下面那一行：账户、账本、日期

    private var contextBar: some View {
        // 字放大时一行放不下：账户、账本一行，日期换到下一行（审计 2026-11-26：大字号时整张单子被撑出屏幕）。
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { accountBookChips; dateChip }
            VStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { accountBookChips }
                    VStack(spacing: 6) { accountBookChips }
                }
                dateChip
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var accountBookChips: some View {
        chip { accountMenu(.from) }
        if model.ledger.books.count > 1 {
            chip {
                Menu {
                    ForEach(model.ledger.books) { b in Button(b.name) { bookID = b.id } }
                } label: {
                    Label(model.ledger.books.first { $0.id == bookID }?.name ?? tr("选账本"), systemImage: "books.vertical")
                }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                .accessibilityLabel(tr("账本：\(model.ledger.books.first { $0.id == bookID }?.name ?? tr("还没选"))"))
            }
        }
    }

    @ViewBuilder private var dateChip: some View {
        #if os(iOS)
        datePicker   // iPhone 的日期按钮自己就是胶囊，不再套一层
        #else
        chip { datePicker }
        #endif
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.sunken, in: Capsule())
    }

    // MARK: 账户、账本、日期、备注、标签、重复

    private var detailRows: some View {
        VStack(spacing: 0) {
            detailRow(tr("备注")) {
                TextField(tr("可不填"), text: $note)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .focused($focus, equals: .note)
                    .accessibilityLabel(tr("备注"))
            }
            Divider()
            tagRow
            if editing == nil {
                Divider()
                detailRow(tr("重复")) {
                    Menu {
                        Button(tr("不重复")) { frequency = nil }
                        Divider()
                        ForEach(Recurring.Frequency.allCases, id: \.self) { f in Button(f.label) { frequency = f } }
                    } label: {
                        Text(frequency?.label ?? tr("不重复")).foregroundStyle(frequency == nil ? Color.fg2 : Color.brand)
                    }
                    .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                    .accessibilityLabel(tr("重复：\(frequency?.label ?? tr("不重复"))"))
                }
                if let frequency {
                    Text(tr("以后每\(frequency == .weekly ? tr("周") : frequency == .monthly ? tr("月这一天") : tr("年这一天"))打开 app 时自动记上，能撤销；在流水页「重复记账」里能停掉。"))
                        .font(.caption).foregroundStyle(Color.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var datePicker: some View {
        DatePicker(tr("日期"), selection: $date, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden().fixedSize()
    }

    private func accountMenu(_ slot: AccountSlot) -> some View {
        let id = slot == .from ? accountID : toAccountID
        let label = slot == .from ? tr("账户") : tr("转到")
        return Menu {
            ForEach(pickableAccounts) { a in
                Button(a.name) { if slot == .from { accountID = a.id } else { toAccountID = a.id } }
            }
            if !pickableAccounts.isEmpty { Divider() }
            Button { newName = ""; askingFor = slot; askAccount = true } label: { Label(tr("新账户…"), systemImage: "plus") }
        } label: {
            Label(id.isEmpty ? tr("选账户") : model.accountName(id), systemImage: "creditcard")
                .foregroundStyle(id.isEmpty ? Color.alert : .primary)
        }
        .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        .accessibilityLabel("\(label)：\(id.isEmpty ? tr("还没选") : model.accountName(id))")
    }

    /// 标签：已经加上的显示成小胶囊（点 × 去掉），后面能打新的；下面提示以前用过的。
    private var tagRow: some View {
        let used = lists.tags.filter { t in !tags.contains(where: { $0.lowercased() == t.lowercased() }) }
        let q = tagDraft.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
        let hints = Array(used.filter { q.isEmpty || $0.lowercased().contains(q) }.prefix(6))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("标签")).foregroundStyle(Color.fg2)
                Spacer(minLength: 8)
                ForEach(tags, id: \.self) { t in
                    Button { tags.removeAll { $0 == t } } label: {
                        HStack(spacing: 2) { Text("#\(t)"); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.brandSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("去掉标签 \(t)"))
                }
                TextField(tags.isEmpty ? tr("可不填，如「旅行」") : tr("再加"), text: $tagDraft)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .focused($focus, equals: .tag)
                    .onSubmit(addDraftTag)
                    .frame(minWidth: 60)
                    .accessibilityLabel(tr("加标签"))
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
                            .accessibilityLabel(tr("加标签 \(t)"))
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
            detailRow(tr("从")) { accountMenu(.from) }
            Divider()
            detailRow(tr("转到")) { accountMenu(.to) }
            Divider()
            detailRow(tr("日期")) { datePicker }
            Divider()
            detailRow(tr("备注")) {
                TextField(tr("可不填，比如「取现」"), text: $note)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .focused($focus, equals: .note)
            }
            if !accountID.isEmpty && accountID == toAccountID {
                Text(tr("转出和转入要是两个不同的账户。")).font(.caption).foregroundStyle(Color.alert)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            } else {
                Text(tr("自己账户之间挪钱（取现、存进储蓄、还信用卡），不算收入也不算支出。"))
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

    // MARK: - Mac 版

    /// 记在生意账本上：店里自己的一版（店里的颜色、店里的账户、不问账本）。
    private var shopMode: Bool {
        model.businessOn && !bookID.isEmpty && bookID == model.ledger.businessBook?.id
    }

    /// 能选的账户：开着生意模式时只列这一边的（店里记就是店里的账户）。改一笔时原来那个账户一直在。
    private var pickableAccounts: [Account] {
        guard model.businessOn else { return model.visibleAccounts }
        let side: Side = shopMode ? .business : .life
        return model.visibleAccounts.filter { model.ledger.side(ofAccount: $0.id) == side || $0.id == accountID || $0.id == editing?.accountID }
    }

    private var tint: Color { shopMode ? .shop : .brand }
    private var solidTint: Color { shopMode ? .shopSolid : .brandSolid }

    #if os(macOS)
    private var macForm: some View {
        Form {
            Section {
                Picker(tr("支出、收入还是转账"), selection: $kind) {
                    Text(tr("支出")).tag(Kind.expense)
                    Text(shopMode ? tr("进账") : tr("收入")).tag(Kind.income)
                    if editing == nil || editing?.isPlainEntry == false { Text(tr("转账")).tag(Kind.transfer) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("direction")
                amountDisplay.padding(.vertical, 4)
            }
            if isTransfer {
                Section {
                    accountPicker(tr("从"), .from)
                    accountPicker(tr("转到"), .to)
                    macDateRow
                    TextField(tr("备注"), text: $note, prompt: Text(tr("可不填，比如「取现」")))
                        .focused($focus, equals: .note)
                } footer: {
                    Text(!accountID.isEmpty && accountID == toAccountID ? tr("转出和转入要是两个不同的账户。")
                         : tr("自己账户之间挪钱（取现、存进储蓄、还信用卡），不算收入也不算支出。"))
                        .font(.caption).foregroundStyle(!accountID.isEmpty && accountID == toAccountID ? Color.alert : Color.fg2)
                }
            } else {
                // 账户和日期挪到金额下面：一打开就看得到，不用往下滚（审查 2026-11-26）。
                Section {
                    accountPicker(tr("账户"), .from)
                    // 开着生意模式时不问账本：在哪边记就是哪边的（顶上「生活 | 生意」）。
                    if !model.businessOn && model.ledger.books.count > 1 {
                        Picker(tr("账本"), selection: $bookID) {
                            ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) }
                        }
                    }
                    macDateRow
                }
                Section {
                    TextField(tr("名称"), text: $name, prompt: Text(income ? tr("比如「工资」") : shopMode ? tr("比如「花材进货」") : tr("比如「超市」")))
                        .focused($focus, equals: .name)
                        .onSubmit {
                            let n = name.trimmingCharacters(in: .whitespaces).lowercased()
                            guard category == nil, !n.isEmpty else { return }
                            if let hit = lists.names.first(where: { $0.name.lowercased() == n }) { pick(hit) }
                            else if let c = allCategories.first(where: { $0.lowercased() == n }) { category = c }
                        }
                    macSuggestions
                } header: { Text(tr("记的是什么")) }
                Section {
                    macCategoryGrid
                } header: {
                    HStack {
                        Text(tr("分类"))
                        Spacer()
                        if let category { Text(category).foregroundStyle(tint) }
                    }
                }
                Section {
                    TextField(tr("备注"), text: $note, prompt: Text(tr("可不填")))
                        .focused($focus, equals: .note)
                    if editing == nil {
                        Picker(tr("重复"), selection: $frequency) {
                            Text(tr("不重复")).tag(Recurring.Frequency?.none)
                            ForEach(Recurring.Frequency.allCases, id: \.self) { f in Text(f.label).tag(Optional(f)) }
                        }
                    }
                    tagRow
                }
            }
        }
        .formStyle(.grouped)
        .tint(tint)
    }

    /// 以前记过的名字：打字时给几个，点一下名字和分类都带上；没打字时是「常记的」，金额也带上。
    @ViewBuilder private var macSuggestions: some View {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty && editing == nil && !lists.frequent.isEmpty {
            frequentRow
        } else {
            let hits = Array(lists.names.lazy.filter { !q.isEmpty && $0.name.lowercased().contains(q) && $0.name.lowercased() != q }.prefix(6))
            if !hits.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(hits, id: \.name) { s in
                            Button { pick(s) } label: {
                                HStack(spacing: 4) {
                                    if let c = s.category { CategoryIcon(category: c, size: 16) }
                                    Text(s.name).lineLimit(1)
                                }
                                .font(.caption).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color.sunken, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// 分类：全部铺开，一行放得下几个就放几个，多了上下滚（鼠标、触控板都能滚）。最后一格是自己加分类。
    private var macCategoryGrid: some View {
        var all = allCategories
        if let c = customCategory, !all.contains(c) { all.insert(c, at: 0) }
        return ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68, maximum: 90), spacing: 4)], spacing: 4) {
                ForEach(all, id: \.self) { c in
                    Button { category = c } label: {
                        VStack(spacing: 3) {
                            CategoryIcon(category: c, size: 26)
                            Text(c).font(.caption2).lineLimit(1).minimumScaleFactor(0.75)
                                .foregroundStyle(category == c ? .primary : Color.fg2)
                        }
                        .frame(maxWidth: .infinity).frame(height: Self.macCell)
                        .background(category == c ? tint.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(category == c ? tint.opacity(0.5) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c)
                    .accessibilityAddTraits(category == c ? .isSelected : [])
                }
                // 自己加一个：放最后、灰色，不抢眼（ming 2026-11-25）。
                Button { addingCategory = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.fg3, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        Text(tr("自定义")).font(.caption2)
                    }
                    .foregroundStyle(Color.fg3)
                    .frame(maxWidth: .infinity).frame(height: Self.macCell)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("自己加一个分类"))
            }
            .padding(2)
        }
        // 正好两行常用的，不切在半行；多了上下滚，底下渐隐提示还能滚（审查 2026-11-26）。
        .frame(height: Self.macCell * 2 + 4 + 4)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .black.opacity(all.count > 14 ? 0.35 : 1), location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
    private static let macCell: CGFloat = 54

    private func accountPicker(_ title: String, _ slot: AccountSlot) -> some View {
        let current = slot == .from ? accountID : toAccountID
        return Picker(title, selection: Binding(get: { current }, set: { v in
            if v == "__new__" { newName = ""; askingFor = slot; askAccount = true }
            else if slot == .from { accountID = v } else { toAccountID = v }
        })) {
            if current.isEmpty { Text(tr("选一个")).tag("") }
            ForEach(pickableAccounts) { a in Text(a.name).tag(a.id) }
            Divider()
            Text(tr("新账户…")).tag("__new__")
        }
        .accessibilityLabel("\(title)：\(current.isEmpty ? tr("还没选") : model.accountName(current))")
    }

    /// 日期：系统日期选择 + 「今天」「昨天」两个快捷。
    private var macDateRow: some View {
        LabeledContent(tr("日期")) {
            HStack(spacing: 6) {
                // 24 高的胶囊，好点（审查实测原来 26×16）。
                dayChip(tr("今天"), on: Calendar.current.isDateInToday(date)) { date = Date() }
                dayChip(tr("昨天"), on: Calendar.current.isDateInYesterday(date)) { date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date() }
                DatePicker(tr("日期"), selection: $date, displayedComponents: .date)
                    .datePickerStyle(.field).labelsHidden().fixedSize()
            }
        }
    }

    private func dayChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.callout.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? tint : Color.fg2)
                .padding(.horizontal, 10).frame(minHeight: 24)
                .background(on ? tint.opacity(0.14) : Color.sunken, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
    #endif

    // MARK: 打开、保存

    private func setup() {
        guard !didSetup else { return }
        if let id = model.editingID, let t = model.transaction(id) {
            editing = t
            kind = t.amount.isIncome ? .income : .expense
            amountText = t.amount.inputText
            name = t.description
            category = t.category
            bookID = t.bookID ?? model.defaultBookID
            accountID = t.accountID
            date = t.date.asDate
            note = t.note ?? ""
            tags = t.tagList
            refreshLists()
            if let c = t.category, !allCategories.contains(c) { customCategory = c }
        } else {
            // 生意首页的「记今天进账」、零碎开销按钮：先按预设填好方向、分类和账本。
            if let preset = model.addPreset {
                model.addPreset = nil
                kind = preset.income ? .income : .expense
                if let b = preset.bookID { bookID = b }
                category = preset.category
            }
            if bookID.isEmpty { bookID = model.defaultBookID }
            if accountID.isEmpty { accountID = model.defaultAccountID }
            // 开着生意模式：上次用的账户在另一边，就换成这一边的第一个。
            if !pickableAccounts.contains(where: { $0.id == accountID }) { accountID = pickableAccounts.first?.id ?? accountID }
            refreshLists()
            if let c = category, !allCategories.contains(c) { customCategory = c }
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
            model.claimNewAccount(a.id)
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
                    // 开着生意模式：看着明显记错了边（生意这边记了「书包」），夏夏马上挪过去，提示里能撤销。
                    model.checkSide(tx.id)
                }
            }
            model.lastAccountID = accountID
            if !bookID.isEmpty { model.lastBookID = bookID }
            if keepOpen {
                savedInARow += 1
                keypadUp = true
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
        case "⌫": tr("删除")
        case ",": tr("小数点")
        case "+": tr("加")
        case "−": tr("减")
        case "=": tr("等于")
        case "C": tr("清空")
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
