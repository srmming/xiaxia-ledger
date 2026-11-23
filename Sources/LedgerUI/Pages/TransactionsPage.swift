import FinanceCore
import SwiftUI

/// 流水筛选条件。从花销页点一个分类进来时会带上分类。
public struct TransactionFilter: Hashable {
    public var category: String?
    public var accountID: String?
    public var onlyAI = false
    /// nil = 支出收入都看；true 只看收入；false 只看支出。
    public var income: Bool?
    /// 只看带这个标签的。
    public var tag: String?
    /// 只看这几笔（「Claude 刚记了 12 笔 → 看看」），不管月份。
    public var ids: Set<UUID>?

    public init(category: String? = nil, accountID: String? = nil, onlyAI: Bool = false, income: Bool? = nil, tag: String? = nil,
                ids: Set<UUID>? = nil) {
        self.category = category; self.accountID = accountID; self.onlyAI = onlyAI; self.income = income; self.tag = tag
        self.ids = ids
    }
}

/// 流水：这一笔是怎么回事？搜索框 + 按天分组的列表，Mac 右边是详情（能改分类、账本，能删、能撤销）。
struct TransactionsPage: View {
    @Environment(LedgerModel.self) var model
    @State var query = ""
    @State var filter: TransactionFilter

    init(filter: TransactionFilter = TransactionFilter()) { _filter = State(initialValue: filter) }
    @State var selected: Set<UUID> = []
    @State var selecting = false
    @State var showBulk = false
    @State var showRecurring = false
    @State var width: CGFloat = 1000
    @FocusState var searchFocused: Bool

    var body: some View {
        let list = filtered
        let wide = width >= 760
        Group {
            if model.ledger.transactions.isEmpty {
                KitEmptyState(title: "还没有流水", message: "把银行对账单拖进 Claude，说一句「帮我导入夏夏账本」，导好就会出现在这里。",
                              prompt: "这是我的银行对账单，帮我整理好导进夏夏账本", page: "流水")
                    .kitCard()
                    .kitPage()
            } else {
                #if os(macOS)
                HStack(alignment: .top, spacing: Kit.gap) {
                    listCard(list)
                    if wide {
                        ScrollView { detail.padding(.bottom, Kit.side) }
                            .frame(width: 340)
                    }
                }
                .padding(Kit.side)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                // 最小宽度别跟着「有没有右边详情」变：不然 Mac 上对话栏开着时，详情一出一收会让分栏反复重排，AppKit 直接 abort（实测点「看看」闪退）。
                .clipped()
                .background(Color.pageBackground)
                .background { WidthReader(width: $width) }
                #else
                List {
                    Section { filters }
                    ForEach(groups(list), id: \.date) { g in
                        Section {
                            ForEach(g.items) { t in
                                // 选择的时候整行就是勾选，不再点进详情。
                                Group {
                                    if selecting {
                                        // 自己画勾选：点整行选上 / 取消。
                                        Button {
                                            if selected.contains(t.id) { selected.remove(t.id) } else { selected.insert(t.id) }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: selected.contains(t.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.title3)
                                                    .foregroundStyle(selected.contains(t.id) ? Color.brand : Color.fg3)
                                                TxRow(tx: t)
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityAddTraits(selected.contains(t.id) ? .isSelected : [])
                                    } else {
                                        NavigationLink { TransactionDetail(tx: t).kitPage().navigationTitle("这一笔") } label: { TxRow(tx: t) }
                                    }
                                }
                                    .tag(t.id)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            let ids = model.ledger.pairedIDs(of: t.id)
                                            model.perform { try $0.removeTransactions(ids, author: model.author) }
                                        } label: { Label("删除", systemImage: "trash") }
                                        if t.isPlainEntry {
                                            Button { model.startEditing(t.id) } label: { Label("改", systemImage: "pencil") }.tint(.brand)
                                        }
                                    }
                                    .contextMenu { rowMenu(t) }
                            }
                        } header: { dayHeader(g) }
                    }
                }
                .searchable(text: $query, prompt: "搜商户、备注、#标签、金额…")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selecting ? "完成" : "选择") { selecting.toggle(); selected = [] }
                            .accessibilityIdentifier("select-toggle")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if selecting {
                        HStack {
                            Text(selected.isEmpty ? "点几笔选中，一起改" : "选了 \(selected.count) 笔").font(.subheadline).foregroundStyle(Color.fg2)
                            Spacer()
                            Button("一起改…") { showBulk = true }
                                .buttonStyle(.borderedProminent).tint(.brand)
                                .disabled(selected.isEmpty)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.bar)
                    }
                }
                .sheet(isPresented: $showBulk) {
                    NavigationStack {
                        ScrollView {
                            BulkActions(ids: selected) { selected = []; selecting = false; showBulk = false }
                                .padding(20)
                        }
                        .navigationTitle("一起改").inlineTitle()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { showBulk = false } } }
                    }
                    .environment(model)
                    .presentationDetents([.medium, .large])
                }
                #endif
            }
        }
        .onAppear {
            if let f = model.pendingFilter { filter = f; model.pendingFilter = nil }
            // Mac 打开页面时系统会把光标自动放进搜索框，敲键盘就打进去了；除非是按 ⌘F 来的，先让出来。
            let wantSearch = model.focusSearch
            model.focusSearch = false
            DispatchQueue.main.async { searchFocused = wantSearch }
        }
        .onChange(of: model.focusSearch) { _, on in
            if on { searchFocused = true; model.focusSearch = false }
        }
        .onChange(of: model.pendingFilter) { _, f in
            if let f { filter = f; model.pendingFilter = nil }
        }
        .onChange(of: model.ledger.transactions.count) { _, _ in
            // 删掉的那几笔从选中里拿掉。
            let ids = Set(model.ledger.transactions.map(\.id))
            selected = selected.filter { ids.contains($0) }
        }
        .sheet(isPresented: $showRecurring) {
            NavigationStack { RecurringManager() }
                .environment(model)
                #if os(macOS)
                .frame(width: 480, height: 440)
                #endif
        }
    }

    // MARK: 数据

    private var filtered: [Transaction] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let month = model.shownMonth
        let authors = model.authors
        if let ids = filter.ids { return model.visibleTransactions.filter { ids.contains($0.id) } }
        return model.visibleTransactions.filter { t in
            // 搜的时候不限月份；不搜就看工具栏选的那个月。
            if q.isEmpty, t.date.yearMonth != month { return false }
            if let c = filter.category, (t.category ?? "未分类") != c { return false }
            if let a = filter.accountID, t.accountID != a { return false }
            if filter.onlyAI { guard let who = authors[t.id], !model.isMe(who) else { return false } }
            if let income = filter.income, t.amount.isIncome != income || t.flow != nil { return false }
            if let tag = filter.tag, !t.tagList.contains(tag) { return false }
            guard !q.isEmpty else { return true }
            return t.matches(q) || model.accountName(t.accountID).lowercased().contains(q) || t.amount.display.contains(q)
        }
    }

    struct DayGroup { var date: LocalDate; var items: [Transaction]; var total: Money }

    private func groups(_ list: [Transaction]) -> [DayGroup] {
        Dictionary(grouping: list, by: \.date).map { d, items in
            // 外币账户的流水先换成主币种再加，不把美元和欧元直接相加。
            DayGroup(date: d, items: items, total: items.filter { $0.flow == nil }.reduce(.zero) { $0 + model.ledger.baseAmount($1) })
        }
        .sorted { $0.date > $1.date }
    }

    private func dayHeader(_ g: DayGroup) -> some View {
        HStack {
            Text(g.date == .today ? "今天 · \(g.date.short)" : g.date.friendly)
            Spacer()
            Text(g.total.display).monospacedDigit()
        }
        .font(.caption).foregroundStyle(Color.fg2)
    }

    /// 右键（Mac）/ 长按（iPhone）一笔：改、复制、删除。删了底部能撤销。
    @ViewBuilder private func rowMenu(_ t: Transaction) -> some View {
        if t.isPlainEntry {
            Button { model.startEditing(t.id) } label: { Label("改…", systemImage: "pencil") }
            Button { model.perform { try $0.duplicateTransaction(t.id, author: model.author) } } label: {
                Label("复制一笔", systemImage: "plus.square.on.square")
            }
        }
        Button(role: .destructive) {
            let ids = model.ledger.pairedIDs(of: t.id)
            model.perform { try $0.removeTransactions(ids, author: model.author) }
        } label: { Label("删除", systemImage: "trash") }
    }

    // MARK: 筛选

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let ids = filter.ids {
                    chip("刚改的 \(ids.count) 笔  ✕", symbol: "sparkles", on: true) { filter.ids = nil; model.highlighted = [] }
                        .accessibilityLabel("只看刚改的 \(ids.count) 笔，点一下看全部")
                }
                chip("全部", on: filter == TransactionFilter()) { filter = TransactionFilter(); model.highlighted = [] }
                Menu {
                    Button("全部分类") { filter.category = nil }
                    Divider()
                    ForEach(model.usedCategories, id: \.self) { c in Button(c) { filter.category = c } }
                } label: { chipLabel((filter.category ?? "分类") + " ▾", on: filter.category != nil) }
                    .menuStyle(.button).buttonStyle(.plain).fixedSize()
                Menu {
                    Button("全部账户") { filter.accountID = nil }
                    Divider()
                    ForEach(model.visibleAccounts) { a in Button(a.name) { filter.accountID = a.id } }
                } label: { chipLabel((filter.accountID.map { model.accountName($0) } ?? "账户") + " ▾", on: filter.accountID != nil) }
                    .menuStyle(.button).buttonStyle(.plain).fixedSize()
                Menu {
                    Button("支出和收入") { filter.income = nil }
                    Divider()
                    Button("只看支出") { filter.income = false }
                    Button("只看收入") { filter.income = true }
                } label: { chipLabel((filter.income.map { $0 ? "只看收入" : "只看支出" } ?? "收支") + " ▾", on: filter.income != nil) }
                    .menuStyle(.button).buttonStyle(.plain).fixedSize()
                if !model.ledger.allTags.isEmpty {
                    Menu {
                        Button("全部标签") { filter.tag = nil }
                        Divider()
                        ForEach(model.ledger.allTags, id: \.self) { t in Button("#\(t)") { filter.tag = t } }
                    } label: { chipLabel((filter.tag.map { "#\($0)" } ?? "标签") + " ▾", on: filter.tag != nil) }
                        .menuStyle(.button).buttonStyle(.plain).fixedSize()
                }
                chip("只看 AI 记的", symbol: "sparkles", on: filter.onlyAI) { filter.onlyAI.toggle() }
                chip(model.ledger.recurring.isEmpty ? "重复记账" : "重复记账 \(model.ledger.recurring.count)", symbol: "repeat", on: false) { showRecurring = true }
            }
        }
    }

    private func chip(_ title: String, symbol: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, symbol: symbol, on: on) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chipLabel(_ title: String, symbol: String? = nil, on: Bool) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).foregroundStyle(on ? Color.white : Color.ai) }
            Text(title)
        }
        .font(.subheadline)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .foregroundStyle(on ? Color.white : Color.primary)
        .background(on ? AnyShapeStyle(Color.primary.opacity(0.85)) : AnyShapeStyle(Color.cardBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
        .contentShape(Capsule())
    }

    // MARK: Mac 列表 + 详情

    #if os(macOS)
    private func listCard(_ list: [Transaction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.fg3)
                TextField("搜商户、备注、#标签、金额…", text: $query).textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.fg3) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            filters
            if list.isEmpty {
                Text(query.isEmpty ? "\(model.shownMonth.month) 月没有符合的流水。" : "没找到「\(query)」。")
                    .font(.subheadline).foregroundStyle(Color.fg2).padding(.vertical, 20).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $selected) {
                    ForEach(groups(list), id: \.date) { g in
                        Section {
                            ForEach(g.items) { t in
                                TxRow(tx: t).tag(t.id)
                                    .listRowSeparator(.visible)
                                    .contextMenu { rowMenu(t) }
                            }
                        } header: { dayHeader(g) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .kitCard()
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { if selected.isEmpty, let first = list.first?.id { selected = [first] } }
        // 筛选变了（比如从「刚改的 N 笔」跳进来），右边详情别还停在列表里看不到的那一笔。
        .onChange(of: list.map(\.id)) { _, ids in if !selected.contains(where: ids.contains) { selected = ids.first.map { [$0] } ?? [] } }
        .onChange(of: selected, initial: true) { _, ids in model.selectedTransactionID = ids.count == 1 ? ids.first : nil }
        .onDisappear { model.selectedTransactionID = nil }
    }

    @ViewBuilder private var detail: some View {
        if selected.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                BulkActions(ids: selected) { selected = [] }
                Text("按住 ⌘ 点可以多选或取消，按住 ⇧ 点选一段。").font(.caption).foregroundStyle(Color.fg3)
            }
            .kitCard()
        } else if let id = selected.first, let t = model.transaction(id) {
            TransactionDetail(tx: t)
        } else {
            Text("点左边一笔看详情；按住 ⌘ 点能选好几笔一起改。").font(.subheadline).foregroundStyle(Color.fg2)
                .frame(maxWidth: .infinity, minHeight: 120).kitCard()
        }
    }
    #endif
}

/// 去别的页面：Mac 上切侧栏，iPhone 上推进去。
struct SectionLink<L: View>: View {
    @Environment(LedgerModel.self) var model
    let section: AppSection
    var filter: TransactionFilter? = nil
    @ViewBuilder var label: () -> L

    var body: some View {
        #if os(macOS)
        Button {
            if let filter { model.showTransactions(filter) } else { model.section = section }
        } label: { label() }
        .buttonStyle(.plain)
        #else
        NavigationLink {
            Group {
                if section == .transactions { TransactionsPage(filter: filter ?? TransactionFilter()) } else { section.screen }
            }
            .navigationTitle(section.title)
        } label: { label() }
        .buttonStyle(.plain)
        #endif
    }
}

/// 一笔流水的详情。iPhone 和 Mac 一样：能直接换分类、账本，能改、复制、拆开、记退款、设成重复、删除、撤销。
struct TransactionDetail: View {
    @Environment(LedgerModel.self) var model
    let tx: Transaction

    private let editable = true

    /// 外币流水换成主币种：「≈ 18,40 € · 按 11 月 2 日欧洲央行汇率」。
    private func fxLine(_ code: String) -> String {
        let l = model.ledger
        let base = l.baseAmount(tx).magnitude.ui(in: l.baseCurrency)
        if let fx = tx.fx, fx.base == l.baseCurrency {
            return "≈ \(base) · \(fx.source == "ecb" ? "\(fx.date.month) 月 \(fx.date.day) 日\(fx.sourceLabel)汇率" : fx.sourceLabel)"
        }
        if let r = l.rateToBase(code, on: tx.date) { return "≈ \(base) · \(r.date.month) 月 \(r.date.day) 日欧洲央行汇率" }
        return "还没有汇率，先按 1:1 算"
    }


    var body: some View {
        // 改过之后用账本里最新的样子（iPhone 上推进来的详情不会自己换）。
        let tx = model.transaction(self.tx.id) ?? self.tx
        let change = model.ledger.changes.filter { $0.transactionIDs.contains(tx.id) && !$0.undone }.max { $0.createdAt < $1.createdAt }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Merchant.display(tx.description)).font(.headline)
                Text(tx.date.friendly == "今天" ? "今天 · \(tx.date.short)" : tx.date.friendly).font(.caption).foregroundStyle(Color.fg2)
            }
            let code = model.ledger.currency(ofAccount: tx.accountID)
            Text(tx.flow == nil ? tx.amount.display(in: code) : tx.amount.magnitude.ui(in: code))
                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tx.flow != nil ? Color.fg3 : tx.amount.isIncome ? Color.income : .primary)
            VStack(spacing: 0) {
                row("分类") {
                    if editable && tx.flow == nil {
                        Menu {
                            ForEach(model.categories(bookID: tx.bookID, income: tx.amount.isIncome, limit: 20), id: \.self) { c in
                                Button(c) { set(category: c) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                CategoryIcon(category: tx.category, size: 18)
                                Text(tx.category ?? "未分类")
                            }
                        }
                        .menuStyle(.button).fixedSize()
                    } else {
                        Text(tx.flow == nil ? (tx.category ?? "未分类") : "不算收支")
                    }
                }
                Divider()
                row("账本") {
                    if editable && tx.flow == nil && model.ledger.books.count > 1 {
                        Menu {
                            ForEach(model.ledger.books) { b in Button(b.name) { set(book: b.id) } }
                        } label: { Text(tx.bookID.map { model.bookName($0) } ?? "没分账本") }
                            .menuStyle(.button).fixedSize()
                    } else {
                        Text(tx.bookID.map { model.bookName($0) } ?? "—")
                    }
                }
                Divider()
                row("账户") { Text(model.accountName(tx.accountID)) }
                if let o = tx.original {
                    Divider()
                    row("原价") { Text(o.amount.ui(in: o.currency)).monospacedDigit() }
                }
                if code != model.ledger.baseCurrency {
                    Divider()
                    row("约合") {
                        Text(fxLine(code)).monospacedDigit().multilineTextAlignment(.trailing)
                    }
                }
                if Merchant.display(tx.description) != tx.description {
                    Divider()
                    row("银行原文") { Text(tx.description).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }
                if let note = tx.note {
                    Divider()
                    row("备注") { Text(note).multilineTextAlignment(.trailing).textSelection(.enabled) }
                }
                if !tx.tagList.isEmpty {
                    Divider()
                    row("标签") {
                        HStack(spacing: 4) {
                            ForEach(tx.tagList, id: \.self) { t in
                                Button { model.showTransactions(TransactionFilter(tag: t)) } label: {
                                    Text("#\(t)").font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Color.brandSoft, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let r = model.ledger.recurring.first(where: { $0.template.description == tx.description && $0.template.amount == tx.amount && $0.template.accountID == tx.accountID }) {
                    Divider()
                    row("重复") { Text(r.paused ? "\(r.frequency.label)（暂停中）" : "\(r.frequency.label)，下次 \(r.nextDate.friendly)") }
                }
                if let source = tx.source {
                    Divider()
                    row("来源") { Text(source).lineLimit(1) }
                }
            }
            .font(.callout)
            if let change {
                HStack(spacing: 6) {
                    Image(systemName: model.isMe(change.author) ? "person.fill" : "sparkles")
                        .foregroundStyle(model.isMe(change.author) ? Color.fg2 : Color.ai)
                    Text("\(model.isMe(change.author) ? "你" : change.author) \(change.createdAt.friendly)：\(change.summary)")
                        .lineLimit(2)
                }
                .font(.caption)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(model.isMe(change.author) ? Color.sunken : Color.aiSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack {
                if let change, change.canUndo {
                    Button { model.undo(change.id) } label: { Label(change.transactionIDs.count > 1 ? "撤销这次改动（\(change.transactionIDs.count) 笔）" : "撤销这次改动", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.soft)
                }
                Spacer()
                #if os(macOS)
                Button { model.askAbout(tx) } label: { Label("问夏夏", systemImage: "sparkles") }
                    .buttonStyle(.soft).help("在右边的对话栏里问夏夏这一笔")
                #endif
            }
            PaperworkSection(tx: tx)
            TransactionActions(tx: tx)
        }
        .kitCard()
    }

    private func row(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.fg2)
            Spacer(minLength: 12)
            value()
        }
        .padding(.vertical, 9)
    }

    private func set(category: String) {
        model.perform { try $0.classify([tx.id], category: category, bookID: nil, author: model.author) }
    }

    private func set(book: String) {
        model.perform { try $0.classify([tx.id], category: nil, bookID: book, author: model.author) }
    }
}
