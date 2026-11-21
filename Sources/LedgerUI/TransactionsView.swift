import FinanceCore
import SwiftUI

/// 流水：按日期分组，能搜索、按账本筛选。点一笔看详情和是谁记的。
public struct TransactionsView: View {
    @Environment(LedgerModel.self) private var model
    @State private var query = ""
    @State private var selected: Transaction?

    public init() {}

    private var filtered: [Transaction] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.visibleTransactions }
        return model.visibleTransactions.filter {
            $0.description.lowercased().contains(q) || ($0.category ?? "").lowercased().contains(q)
                || model.accountName($0.accountID).lowercased().contains(q) || $0.amount.formatted.contains(q)
        }
    }

    public var body: some View {
        let groups = Dictionary(grouping: filtered, by: \.date).sorted { $0.key > $1.key }
        List {
            Section { BookPicker() }
            if groups.isEmpty {
                ContentUnavailableView(query.isEmpty ? "还没有流水" : "没找到「\(query)」",
                                       systemImage: query.isEmpty ? "tray" : "magnifyingglass")
            }
            ForEach(groups, id: \.key) { date, txs in
                Section(date.short) {
                    ForEach(txs) { t in
                        Button { selected = t } label: { TransactionRow(tx: t) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索说明、分类、账户、金额")
        .navigationTitle("流水")
        .sheet(item: $selected) { t in
            NavigationStack { TransactionDetail(tx: t) }
                #if os(macOS)
                .frame(minWidth: 380, minHeight: 360)
                #endif
        }
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

    private var icon: String {
        switch tx.flow {
        case .debt: "person.2"
        case .saving: "dollarsign.circle"
        case nil: tx.isTransfer ? "arrow.left.arrow.right" : (tx.amount.isIncome ? "arrow.down.circle" : "cart")
        }
    }
}

struct TransactionDetail: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tx: Transaction

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
                    LabeledContent("性质", value: flow == .debt ? "借款往来（不算收支）" : "转进储蓄（不算收支）")
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
        .formStyle(.grouped)
        .navigationTitle("这一笔")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}
