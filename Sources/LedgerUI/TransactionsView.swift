import FinanceCore
import SwiftUI

/// 流水筛选条件。从总览点一个分类进来时会带上分类和月份。
public struct TransactionFilter: Hashable {
    public enum Sign: Hashable { case income, expense }

    public var month: YearMonth?
    public var year: Int?
    public var category: String?
    public var accountID: String?
    public var sign: Sign?
    /// 只看还没分类或没分账本的。
    public var onlyUntidy = false

    public init(month: YearMonth? = nil, year: Int? = nil, category: String? = nil, accountID: String? = nil, sign: Sign? = nil) {
        self.month = month; self.year = year; self.category = category; self.accountID = accountID; self.sign = sign
    }

    var isEmpty: Bool { self == TransactionFilter() }

    func matches(_ t: FinanceCore.Transaction) -> Bool {
        if let m = month, t.date.yearMonth != m { return false }
        if let y = year, t.date.year != y { return false }
        if let c = category, (t.category ?? "未分类") != c { return false }
        if let a = accountID, t.accountID != a { return false }
        if let s = sign {
            guard t.flow == nil else { return false }
            if (s == .income) != t.amount.isIncome { return false }
        }
        if onlyUntidy, t.flow != nil || t.isTransfer || (t.category != nil && t.bookID != nil) { return false }
        return true
    }
}

/// 流水：按日期分组，能搜索、筛选。点一笔直接改；选中几笔能一起改分类、分账本、删掉。
public struct TransactionsView: View {
    @Environment(LedgerModel.self) private var model
    @State private var query = ""
    @State private var filter: TransactionFilter
    @State private var selection: Set<UUID> = []
    @State private var selecting = false
    @State private var customCategoryFor: Set<UUID>?
    @State private var customCategory = ""
    private let title: String
    private let isRoot: Bool

    public init() {
        _filter = State(initialValue: .init())
        title = "流水"
        isRoot = true
    }

    public init(filter: TransactionFilter, title: String) {
        _filter = State(initialValue: filter)
        self.title = title
        isRoot = false
    }

    private var filtered: [Transaction] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let f = filter
        return model.visibleTransactions.filter { t in
            guard f.matches(t) else { return false }
            guard !q.isEmpty else { return true }
            return t.description.lowercased().contains(q) || (t.category ?? "").lowercased().contains(q)
                || model.accountName(t.accountID).lowercased().contains(q) || t.amount.formatted.contains(q)
        }
    }

    public var body: some View {
        let list = filtered
        let groups = Dictionary(grouping: list, by: \.date).sorted { $0.key > $1.key }
        let real = list.filter { $0.flow == nil }
        let spending = Summaries.expenseCategories(model.ledger.transactions)
        let income = real.filter { Summaries.countsAsIncome($0, expenseCategories: spending) }.reduce(Money.zero) { $0 + $1.amount }
        let expense = real.filter { !Summaries.countsAsIncome($0, expenseCategories: spending) }.reduce(Money.zero) { $0 + $1.amount }
        container {
            Section {
                BookPicker()
                filterBar
                if !list.isEmpty {
                    HStack(spacing: 14) {
                        Text("\(list.count) 笔").fixedSize()
                        Spacer(minLength: 4)
                        Label { Text(income.formatted).monospacedDigit() } icon: { Image(systemName: "arrow.down.left") }
                            .foregroundStyle(Color.income)
                        Label { Text(expense.magnitude.formatted).monospacedDigit() } icon: { Image(systemName: "arrow.up.right") }
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
            .selectionDisabled()
            if groups.isEmpty {
                emptyState.selectionDisabled()
            }
            ForEach(groups, id: \.key) { date, txs in
                Section {
                    ForEach(txs) { t in row(t) }
                } header: {
                    HStack {
                        Text(date.friendly)
                        Spacer()
                        let net = txs.filter { $0.flow == nil }.reduce(Money.zero) { $0 + $1.amount }
                        if txs.count > 1, net.cents != 0 { Text(net.formatted).monospacedDigit() }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索说明、分类、账户、金额")
        .navigationTitle(title)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(selecting ? "完成" : "选择") {
                    withAnimation { selecting.toggle(); if !selecting { selection = [] } }
                }
            }
        }
        #endif
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty { bulkBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.snappy, value: selection.isEmpty)
        .alert("改成什么分类？", isPresented: Binding(get: { customCategoryFor != nil }, set: { if !$0 { customCategoryFor = nil } })) {
            TextField("分类名", text: $customCategory)
            Button("取消", role: .cancel) { customCategoryFor = nil }
            Button("改") {
                let name = customCategory.trimmingCharacters(in: .whitespaces)
                if let ids = customCategoryFor, !name.isEmpty { setCategory(name, ids) }
                customCategoryFor = nil; customCategory = ""
            }
        }
        .onAppear(perform: adoptPendingFilter)
        .onChange(of: model.pendingFilter) { adoptPendingFilter() }
        .onChange(of: model.ledger.transactions.count) { selection = selection.filter { id in model.transaction(id) != nil } }
    }

    private func adoptPendingFilter() {
        guard isRoot, let f = model.pendingFilter else { return }
        filter = f
        query = ""
        model.pendingFilter = nil
    }

    // MARK: 列表外壳：Mac 上能点选、按住 ⌘ 或 ⇧ 多选、双击打开；iPhone 上点一下打开，点「选择」多选。

    @ViewBuilder
    private func container<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        #if os(macOS)
        List(selection: $selection, content: content)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty { actions(ids) }
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first { model.sheet = .edit(id) }
            }
            .onDeleteCommand { if !selection.isEmpty { delete(selection) } }
        #else
        List(content: content)
        #endif
    }

    @ViewBuilder
    private func row(_ t: Transaction) -> some View {
        #if os(macOS)
        TransactionRow(tx: t)
        #else
        Button {
            if selecting {
                if selection.contains(t.id) { selection.remove(t.id) } else { selection.insert(t.id) }
            } else {
                model.sheet = .edit(t.id)
            }
        } label: {
            HStack(spacing: 10) {
                if selecting {
                    Image(systemName: selection.contains(t.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(t.id) ? Color.coral : Color.secondary)
                }
                TransactionRow(tx: t)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { actions([t.id]) }
        .swipeActions(edge: .trailing) {
            Button("删掉", role: .destructive) { delete([t.id]) }
        }
        .swipeActions(edge: .leading) {
            Button { selecting = true; selection.insert(t.id) } label: { Label("选择", systemImage: "checkmark.circle") }
                .tint(.blue)
        }
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if !filter.isEmpty {
            ContentUnavailableView {
                Label("没有符合条件的流水", systemImage: "line.3.horizontal.decrease.circle")
            } description: { Text(filterLabel) } actions: {
                Button("清除筛选") { withAnimation { filter = .init() } }
            }
        } else {
            ContentUnavailableView {
                Label("还没有流水", systemImage: "tray")
            } description: {
                Text("随手记一笔，或者把银行对账单导进来。")
            } actions: {
                Button("记一笔") { model.sheet = .add }.buttonStyle(.borderedProminent)
                Button("导入对账单") { model.sheet = .importer }
            }
        }
    }

    // MARK: 筛选

    private var filterLabel: String {
        var parts: [String] = []
        if let m = filter.month { parts.append(m.label) }
        if let y = filter.year { parts.append("\(y) 年") }
        if let c = filter.category { parts.append(c) }
        if let a = filter.accountID { parts.append(model.accountName(a)) }
        if let s = filter.sign { parts.append(s == .income ? "只看进账" : "只看花掉") }
        if filter.onlyUntidy { parts.append("还没整理") }
        return parts.joined(separator: " · ")
    }

    /// 一排筛选小按钮：现在筛了什么一眼能看到，点一下就能改。
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(filter.month?.label ?? filter.year.map { "\($0) 年" } ?? "全部时间", on: filter.month != nil || filter.year != nil, symbol: "calendar") {
                    Button("全部时间") { filter.month = nil; filter.year = nil }
                    Divider()
                    ForEach(Array(model.recentMonths(12).reversed()), id: \.self) { m in
                        Button(m.label) { filter.month = m; filter.year = nil }
                    }
                    Divider()
                    ForEach(model.years, id: \.self) { y in
                        Button("\(y) 年全年") { filter.year = y; filter.month = nil }
                    }
                }
                chip(filter.accountID.map { model.accountName($0) } ?? "全部账户", on: filter.accountID != nil, symbol: "creditcard") {
                    Button("全部账户") { filter.accountID = nil }
                    Divider()
                    ForEach(model.visibleAccounts) { a in Button(a.name) { filter.accountID = a.id } }
                }
                chip(filter.category ?? "全部分类", on: filter.category != nil, symbol: "tag") {
                    Button("全部分类") { filter.category = nil }
                    Divider()
                    ForEach(model.usedCategories, id: \.self) { c in Button(c) { filter.category = c } }
                }
                chip(filter.sign == nil ? "进账和花掉" : filter.sign == .income ? "只看进账" : "只看花掉", on: filter.sign != nil, symbol: "arrow.up.arrow.down") {
                    Button("进账和花掉都看") { filter.sign = nil }
                    Button("只看进账") { filter.sign = .income }
                    Button("只看花掉") { filter.sign = .expense }
                }
                Button { withAnimation { filter.onlyUntidy.toggle() } } label: {
                    chipLabel("还没整理的", on: filter.onlyUntidy, symbol: "tray.full", menu: false)
                }
                .buttonStyle(.plain)
                if !filter.isEmpty {
                    Button("清除") { withAnimation { filter = .init() } }.font(.subheadline).buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip<M: View>(_ text: String, on: Bool, symbol: String, @ViewBuilder menu: () -> M) -> some View {
        Menu(content: menu) { chipLabel(text, on: on, symbol: symbol, menu: true) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
    }

    private func chipLabel(_ text: String, on: Bool, symbol: String, menu: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption)
            Text(text)
            if menu { Image(systemName: "chevron.down").font(.caption2) }
        }
        .font(.subheadline)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(on ? Color.white : Color.primary)
        .background(on ? AnyShapeStyle(Color.coral) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
        .contentShape(Capsule())
    }

    // MARK: 对选中的流水做事

    private var menuCategories: [String] {
        var out = model.categories(bookID: model.selectedBookID, income: false, limit: 12)
        for c in model.categories(bookID: model.selectedBookID, income: true, limit: 4) where !out.contains(c) { out.append(c) }
        return out
    }

    @ViewBuilder
    private func actions(_ ids: Set<UUID>) -> some View {
        if ids.count == 1, let id = ids.first {
            Button { model.sheet = .edit(id) } label: { Label("打开改这一笔", systemImage: "pencil") }
        }
        Menu {
            ForEach(menuCategories, id: \.self) { c in Button(c) { setCategory(c, ids) } }
            Divider()
            Button("别的分类…") { customCategory = ""; customCategoryFor = ids }
        } label: { Label("改分类", systemImage: "tag") }
        Menu {
            ForEach(model.ledger.books) { b in Button(b.name) { setBook(b.id, ids) } }
        } label: { Label("分到账本", systemImage: "books.vertical") }
        Button { markMove(ids) } label: { Label("这是自己账户间转账，不算收支", systemImage: "arrow.left.arrow.right") }
        Divider()
        Button(role: .destructive) { delete(ids) } label: { Label(ids.count > 1 ? "删掉这 \(ids.count) 笔" : "删掉", systemImage: "trash") }
    }

    private var bulkBar: some View {
        let picked = model.ledger.transactions.filter { selection.contains($0.id) }
        let total = picked.reduce(Money.zero) { $0 + $1.amount }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("选中 \(picked.count) 笔").font(.subheadline.weight(.semibold))
                Text("合计 \(total.formatted)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if picked.count == 1, let one = picked.first {
                Button("打开") { model.sheet = .edit(one.id) }
            }
            Menu {
                ForEach(menuCategories, id: \.self) { c in Button(c) { setCategory(c, selection) } }
                Divider()
                Button("别的分类…") { customCategory = ""; customCategoryFor = selection }
            } label: { Label("分类", systemImage: "tag") }
            Menu {
                ForEach(model.ledger.books) { b in Button(b.name) { setBook(b.id, selection) } }
            } label: { Label("账本", systemImage: "books.vertical") }
            Button(role: .destructive) { delete(selection) } label: { Label("删掉", systemImage: "trash") }
            Button { selection = []; selecting = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .accessibilityLabel("取消选择")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        .padding(.horizontal).padding(.bottom, 8)
    }

    /// 只有普通收支能改分类和账本；借款、储蓄这些跳过。
    private func plain(_ ids: Set<UUID>) -> [UUID] {
        model.ledger.transactions.filter { ids.contains($0.id) && $0.flow == nil }.map(\.id)
    }

    private func setCategory(_ c: String, _ ids: Set<UUID>) {
        let target = plain(ids)
        guard !target.isEmpty else { return }
        model.perform { try $0.classify(target, category: c, bookID: nil, author: model.author) }
    }

    private func setBook(_ b: String, _ ids: Set<UUID>) {
        let target = Array(ids)
        model.perform { try $0.classify(target, category: nil, bookID: b, author: model.author) }
    }

    private func markMove(_ ids: Set<UUID>) {
        let target = plain(ids)
        guard !target.isEmpty else { return }
        model.perform { try $0.markAsAccountTransfer(target, author: model.author) }
    }

    private func delete(_ ids: Set<UUID>) {
        let all = Array(Set(ids.flatMap { model.ledger.pairedIDs(of: $0) }))
        model.perform { try $0.removeTransactions(all, author: model.author) }
        selection.subtract(ids)
    }
}

/// 一行流水：图标、说明、分类 · 账户 · 账本、金额。
struct TransactionRow: View {
    @Environment(LedgerModel.self) private var model
    let tx: Transaction
    var showDate = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tx.flow == nil && !tx.isTransfer ? Color.coral : .secondary)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.description).lineLimit(1)
                HStack(spacing: 4) {
                    if untidy {
                        Text(tx.category == nil ? "没分类" : "没分账本")
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.coral.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.coral)
                    }
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.caption)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(money: tx.amount)
                    .foregroundStyle(tx.flow != nil ? .secondary : .primary)
                if tx.flow != nil || tx.isTransfer {
                    Text("不算收支").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var untidy: Bool { tx.flow == nil && !tx.isTransfer && (tx.category == nil || tx.bookID == nil) }

    private var subtitle: String {
        var parts: [String] = []
        if showDate { parts.append(tx.date.friendly) }
        if let c = tx.category { parts.append(c) }
        parts.append(model.accountName(tx.accountID))
        if let b = tx.bookID { parts.append(model.bookName(b)) }
        return parts.joined(separator: " · ")
    }

    private var icon: String {
        switch tx.flow {
        case .debt:
            // 分期还款也是「还债」，但用日历图标，和借给朋友的钱分开。
            return model.ledger.installments.contains { $0.paidIDs.contains(tx.id) || $0.purchaseID == tx.id } ? "calendar" : "person.2"
        case .saving: return "target"
        case .opening: return "flag"
        case .internal: return "arrow.left.arrow.right"
        case nil:
            if tx.isTransfer { return "arrow.left.arrow.right" }
            if let symbol = CategoryStyle.symbol(tx.category) { return symbol }
            return tx.amount.isIncome ? "arrow.down.left" : "tag"
        }
    }
}
