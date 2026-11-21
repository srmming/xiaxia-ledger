import FinanceCore
import SwiftUI

/// 流水筛选条件。从总览点一个分类进来时会带上分类和月份。
public struct TransactionFilter: Hashable {
    public var month: YearMonth?
    public var category: String?
    public var accountID: String?
    public var onlyUncategorized = false
    public var onlyUnassigned = false
    public init(month: YearMonth? = nil, category: String? = nil, accountID: String? = nil) {
        self.month = month; self.category = category; self.accountID = accountID
    }
    var isEmpty: Bool { month == nil && category == nil && accountID == nil && !onlyUncategorized && !onlyUnassigned }
}

/// 流水：按日期分组，能搜索、按账本、账户、分类、月份筛选，一键看还没分类 / 还没分账本的。点一笔能改、能删。
public struct TransactionsView: View {
    @Environment(LedgerModel.self) private var model
    @State private var query = ""
    @State private var selected: Transaction?
    @State private var filter: TransactionFilter
    private let title: String

    public init(filter: TransactionFilter = .init(), title: String = "流水") {
        _filter = State(initialValue: filter)
        self.title = title
    }

    private var filtered: [Transaction] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let f = filter
        return model.visibleTransactions.filter { t in
            if let m = f.month, t.date.yearMonth != m { return false }
            if let c = f.category, (t.category ?? "未分类") != c { return false }
            if let a = f.accountID, t.accountID != a { return false }
            if f.onlyUncategorized, t.category != nil || t.flow != nil { return false }
            if f.onlyUnassigned, t.bookID != nil { return false }
            guard !q.isEmpty else { return true }
            return t.description.lowercased().contains(q) || (t.category ?? "").lowercased().contains(q)
                || model.accountName(t.accountID).lowercased().contains(q) || t.amount.formatted.contains(q)
        }
    }

    public var body: some View {
        let list = filtered
        let groups = Dictionary(grouping: list, by: \.date).sorted { $0.key > $1.key }
        let total = list.filter { $0.flow == nil }.reduce(Money.zero) { $0 + $1.amount }
        List {
            Section {
                BookPicker()
                if !filter.isEmpty {
                    HStack {
                        Text(filterLabel).font(.subheadline)
                        Spacer()
                        Button("清除筛选") { withAnimation { filter = .init() } }.font(.subheadline)
                    }
                }
                if !list.isEmpty {
                    LabeledContent("\(list.count) 笔，合计") { AmountText(money: total) }
                        .font(.subheadline)
                }
            }
            if groups.isEmpty {
                ContentUnavailableView(query.isEmpty ? (filter.isEmpty ? "还没有流水" : "没有符合条件的流水") : "没找到「\(query)」",
                                       systemImage: query.isEmpty ? "tray" : "magnifyingglass")
            }
            ForEach(groups, id: \.key) { date, txs in
                Section(date.short) {
                    ForEach(txs) { t in
                        Button { selected = t } label: { TransactionRow(tx: t) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("改一笔") { selected = t }
                                Button("删掉", role: .destructive) { delete(t) }
                            }
                            .swipeActions {
                                Button("删掉", role: .destructive) { delete(t) }
                            }
                    }
                }
            }
        }
        // 不用常驻搜索框：iOS 上常驻会把大标题压成小标题。往下拉就出现搜索框。
        .searchable(text: $query, prompt: "搜索说明、分类、账户、金额")
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .automatic) { filterMenu }
        }
        .sheet(item: $selected) { t in
            NavigationStack { TransactionDetail(tx: t) }.sheetSize()
        }
    }

    private var filterLabel: String {
        var parts: [String] = []
        if let m = filter.month { parts.append(m.label) }
        if let c = filter.category { parts.append(c) }
        if let a = filter.accountID { parts.append(model.accountName(a)) }
        if filter.onlyUncategorized { parts.append("还没分类") }
        if filter.onlyUnassigned { parts.append("还没分账本") }
        return "筛选：" + parts.joined(separator: " · ")
    }

    private var filterMenu: some View {
        Menu {
            Toggle("只看还没分类的", isOn: $filter.onlyUncategorized)
            Toggle("只看还没分账本的", isOn: $filter.onlyUnassigned)
            Picker("月份", selection: $filter.month) {
                Text("全部月份").tag(YearMonth?.none)
                ForEach(Array(model.recentMonths(12).reversed()), id: \.self) { m in Text(m.label).tag(Optional(m)) }
            }
            Picker("账户", selection: $filter.accountID) {
                Text("全部账户").tag(String?.none)
                ForEach(model.visibleAccounts) { a in Text(a.name).tag(Optional(a.id)) }
            }
            Picker("分类", selection: $filter.category) {
                Text("全部分类").tag(String?.none)
                ForEach(model.usedCategories, id: \.self) { c in Text(c).tag(Optional(c)) }
            }
            if !filter.isEmpty { Button("清除筛选") { filter = .init() } }
        } label: {
            Label("筛选", systemImage: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func delete(_ t: Transaction) {
        try? model.edit { try $0.removeTransactions([t.id], author: model.author) }
    }
}

struct TransactionRow: View {
    @Environment(LedgerModel.self) private var model
    let tx: Transaction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tx.flow == nil ? Color.coral : .secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.description).lineLimit(1)
                Text([tx.category ?? "未分类", model.accountName(tx.accountID), model.bookName(tx.bookID)].joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            AmountText(money: tx.amount)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static let categorySymbols: [String: String] = [
        "餐饮": "fork.knife", "超市": "cart", "交通": "tram", "房租": "house", "店租": "storefront",
        "水电": "bolt", "耗材": "paintbrush", "设备": "wrench.and.screwdriver", "员工工资": "person.crop.rectangle",
        "工资": "person.crop.rectangle", "收入": "arrow.down.circle", "营业收入": "sparkles", "其他": "tag",
    ]

    private var icon: String {
        switch tx.flow {
        case .debt: return "person.2"
        case .saving: return "dollarsign.circle"
        case .opening: return "flag"
        case nil:
            if tx.isTransfer { return "arrow.left.arrow.right" }
            if let symbol = Self.categorySymbols[tx.category ?? ""] { return symbol }
            return tx.amount.isIncome ? "arrow.down.circle" : "tag"
        }
    }
}

struct TransactionDetail: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tx: Transaction
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        let change = model.ledger.changes.last { $0.transactionIDs.contains(tx.id) }
        Form {
            Section {
                LabeledContent("金额") { AmountText(money: tx.amount, font: .title3.bold()) }
                LabeledContent("说明", value: tx.description)
                LabeledContent("日期", value: tx.date.description)
                LabeledContent("账户", value: model.accountName(tx.accountID))
                LabeledContent("账本", value: model.bookName(tx.bookID))
                LabeledContent("分类", value: tx.category ?? "未分类")
                if let flow = tx.flow {
                    LabeledContent("性质", value: flow == .debt ? "借款往来（不算收支）" : flow == .saving ? "转进储蓄（不算收支）" : "期初余额（不算收支）")
                }
                if let source = tx.source { LabeledContent("来源", value: source) }
            }
            if let change {
                Section("谁记的") {
                    LabeledContent(change.author, value: change.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text(change.summary).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
            Section {
                if tx.flow == nil && !tx.isTransfer {
                    Button { editing = true } label: { Label("改这一笔", systemImage: "pencil") }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("删掉这一笔", systemImage: "trash") }
            } footer: {
                Text("删错了可以在「改动记录」里撤销。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("这一笔")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(isPresented: $editing, onDismiss: { dismiss() }) {
            NavigationStack { AddTransactionView(editing: tx) }.sheetSize()
        }
        .confirmationDialog("删掉这一笔？", isPresented: $confirmDelete) {
            Button("删掉", role: .destructive) {
                do {
                    try model.edit { try $0.removeTransactions([tx.id], author: model.author) }
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
        } message: { Text("\(tx.description) \(tx.amount.formatted)") }
        .errorAlert($error)
    }
}
