import FinanceCore
import SwiftUI

/// 流水筛选条件。从花销页点一个分类进来时会带上分类。
public struct TransactionFilter: Hashable {
    public var category: String?
    public var accountID: String?
    public var onlyAI = false
    /// 只看这几笔（「Claude 刚记了 12 笔 → 看看」），不管月份。
    public var ids: Set<UUID>?

    public init(category: String? = nil, accountID: String? = nil, onlyAI: Bool = false, ids: Set<UUID>? = nil) {
        self.category = category; self.accountID = accountID; self.onlyAI = onlyAI; self.ids = ids
    }
}

/// 流水：这一笔是怎么回事？搜索框 + 按天分组的列表，Mac 右边是详情（能改分类、账本，能删、能撤销）。
struct TransactionsPage: View {
    @Environment(LedgerModel.self) var model
    @State var query = ""
    @State var filter: TransactionFilter

    init(filter: TransactionFilter = TransactionFilter()) { _filter = State(initialValue: filter) }
    @State var selected: UUID?
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.pageBackground)
                .background { WidthReader(width: $width) }
                #else
                List {
                    Section { filters }
                    ForEach(groups(list), id: \.date) { g in
                        Section {
                            ForEach(g.items) { t in
                                NavigationLink { TransactionDetail(tx: t).kitPage().navigationTitle("这一笔") } label: { TxRow(tx: t) }
                            }
                        } header: { dayHeader(g) }
                    }
                }
                .searchable(text: $query, prompt: "搜商户、分类、金额…")
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
            guard !q.isEmpty else { return true }
            return t.description.lowercased().contains(q) || Merchant.display(t.description).lowercased().contains(q)
                || (t.category ?? "").lowercased().contains(q) || model.accountName(t.accountID).lowercased().contains(q)
                || t.amount.formatted.contains(q) || t.amount.display.contains(q)
        }
    }

    struct DayGroup { var date: LocalDate; var items: [Transaction]; var total: Money }

    private func groups(_ list: [Transaction]) -> [DayGroup] {
        Dictionary(grouping: list, by: \.date).map { d, items in
            DayGroup(date: d, items: items, total: items.filter { $0.flow == nil }.reduce(.zero) { $0 + $1.amount })
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
                chip("只看 AI 记的", symbol: "sparkles", on: filter.onlyAI) { filter.onlyAI.toggle() }
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
                TextField("搜商户、分类、金额…", text: $query).textFieldStyle(.plain)
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
        .onAppear { if selected == nil { selected = list.first?.id } }
        .onChange(of: selected, initial: true) { _, id in model.selectedTransactionID = id }
        .onDisappear { model.selectedTransactionID = nil }
    }

    @ViewBuilder private var detail: some View {
        if let id = selected, let t = model.transaction(id) {
            TransactionDetail(tx: t)
        } else {
            Text("点左边一笔看详情").font(.subheadline).foregroundStyle(Color.fg2)
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
            .navigationTitle(section.rawValue)
        } label: { label() }
        .buttonStyle(.plain)
        #endif
    }
}

/// 一笔流水的详情。Mac 上能改分类、账本，能删、能撤销；iPhone 上只看。
struct TransactionDetail: View {
    @Environment(LedgerModel.self) var model
    let tx: Transaction
    @State var confirmDelete = false

    /// 外币流水换成主币种：「≈ 18,40 € · 按 11 月 2 日欧洲央行汇率」。
    private func fxLine(_ code: String) -> String {
        let l = model.ledger
        let base = l.baseAmount(tx).magnitude.formatted(in: l.baseCurrency)
        if let fx = tx.fx, fx.base == l.baseCurrency {
            return "≈ \(base) · \(fx.source == "ecb" ? "\(fx.date.month) 月 \(fx.date.day) 日\(fx.sourceLabel)汇率" : fx.sourceLabel)"
        }
        if let r = l.rateToBase(code, on: tx.date) { return "≈ \(base) · \(r.date.month) 月 \(r.date.day) 日欧洲央行汇率" }
        return "还没有汇率，先按 1:1 算"
    }

    private var editable: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        let change = model.ledger.changes.filter { $0.transactionIDs.contains(tx.id) && !$0.undone }.max { $0.createdAt < $1.createdAt }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Merchant.display(tx.description)).font(.headline)
                Text(tx.date.friendly == "今天" ? "今天 · \(tx.date.short)" : tx.date.friendly).font(.caption).foregroundStyle(Color.fg2)
            }
            let code = model.ledger.currency(ofAccount: tx.accountID)
            Text(tx.flow == nil ? tx.amount.display(in: code) : tx.amount.magnitude.formatted(in: code))
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
                    row("原价") { Text(o.formatted).monospacedDigit() }
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
            if editable {
                HStack {
                    if let change, change.canUndo {
                        Button { model.undo(change.id) } label: { Label(change.transactionIDs.count > 1 ? "撤销这次改动（\(change.transactionIDs.count) 笔）" : "撤销这次改动", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(.soft)
                    }
                    Spacer()
                    Button("删除这笔") { confirmDelete = true }.buttonStyle(.softAlert)
                }
            } else {
                Text("要改这一笔，在 Mac 上改，或者跟 AI 说。").font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .kitCard()
        .confirmationDialog("删除这一笔？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                model.perform { try $0.removeTransactions([tx.id], author: model.author) }
            }
        } message: {
            Text("\(Merchant.display(tx.description)) \(tx.amount.display)。删了能在改动记录里撤销。")
        }
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
