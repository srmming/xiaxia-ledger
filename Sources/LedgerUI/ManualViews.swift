import FinanceCore
import SwiftUI

// 自己动手改账用的几块：重复记账自动记、改一笔、拆开、多选批量改、重复记账管理。
// 规则都在 FinanceCore（ManualEntry.swift），这里只是界面。

extension LedgerModel {
    /// 打开 app 时把到日子的重复记账记上（房租每月 1 号……）。底部提示能撤销。
    func postDueRecurring() {
        struct NothingDue: Error {}
        guard loadError == nil, ledger.recurring.contains(where: { !$0.paused && $0.nextDate <= .today }) else { return }
        _ = try? edit { l in
            guard let change = l.postDueRecurring(author: author) else { throw NothingDue() }
            return change
        }
    }

    /// 打开「改这一笔」。
    public func startEditing(_ id: UUID) {
        editingID = id
        sheet = .add
    }
}

// MARK: - 一笔的操作按钮（详情里用）

/// 改、复制、拆开、记退款、设成重复、删除。iPhone 和 Mac 一样。
struct TransactionActions: View {
    @Environment(LedgerModel.self) var model
    let tx: FinanceCore.Transaction
    private var isRecurring: Bool {
        model.ledger.recurring.contains { $0.template.description == tx.description && $0.template.amount == tx.amount && $0.template.accountID == tx.accountID }
    }
    @State var confirmDelete = false
    @State var splitting = false
    @State var askRefund = false
    @State var refundText = ""

    var body: some View {
        // 最常用的两个（改、删）直接摆出来；复制、拆开、退款、设成重复放进「更多」，不让详情页一排按钮。
        HStack(spacing: 8) {
            if tx.isPlainEntry {
                Button { model.startEditing(tx.id) } label: { Label(tr("改"), systemImage: "pencil").frame(maxWidth: .infinity) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("tx-edit")
                Menu {
                    Button { model.perform { try $0.duplicateTransaction(tx.id, author: model.author) } } label: {
                        Label(tr("复制一笔（日期是今天）"), systemImage: "plus.square.on.square")
                    }
                    Button { splitting = true } label: { Label(tr("拆开成几笔…"), systemImage: "square.split.2x1") }
                    if tx.amount.isExpense {
                        Button { refundText = tx.amount.inputText; askRefund = true } label: { Label(tr("记退款…"), systemImage: "arrow.uturn.left.circle") }
                    }
                    if !isRecurring {
                        Menu {
                            ForEach(Recurring.Frequency.allCases, id: \.self) { f in
                                Button(f.label) { model.perform { try $0.makeRecurring(tx.id, frequency: f, author: model.author) } }
                            }
                        } label: { Label(tr("设成重复"), systemImage: "repeat") }
                    }
                } label: { Label(tr("更多"), systemImage: "ellipsis.circle").frame(maxWidth: .infinity) }
                    .menuStyle(.button).buttonStyle(.soft).menuIndicator(.hidden)
                    .accessibilityIdentifier("tx-more")
            }
            Button { confirmDelete = true } label: { Label(tr("删除"), systemImage: "trash").frame(maxWidth: tx.isPlainEntry ? .infinity : nil) }
                .buttonStyle(.softAlert)
        }
        .font(.callout)
        .sheet(isPresented: $splitting) {
            NavigationStack { SplitSheet(tx: tx) }
                .environment(model)
                #if os(macOS)
                .frame(width: 460, height: 460)
                #endif
        }
        .alert(tr("记退款"), isPresented: $askRefund) {
            TextField(tr("退了多少"), text: $refundText)
            Button(tr("取消"), role: .cancel) {}
            Button(tr("记下")) {
                let m = Money.evaluate(refundText)?.magnitude
                model.perform { try $0.addRefund(of: tx.id, amount: m, author: model.author) }
            }
        } message: {
            Text(tr("钱回到「\(model.accountName(tx.accountID))」，分类「退款」，会从支出里减掉。原来这笔 \(tx.amount.magnitude.formatted(in: model.ledger.currency(ofAccount: tx.accountID)))。"))
        }
        .confirmationDialog(tr("删除这一笔？"), isPresented: $confirmDelete) {
            Button(tr("删除"), role: .destructive) {
                let ids = model.ledger.pairedIDs(of: tx.id)
                model.perform { try $0.removeTransactions(ids, author: model.author) }
            }
        } message: {
            Text(tr("\(Merchant.display(tx.description)) \(tx.amount.display)。删了能在改动记录里撤销。"))
        }
    }
}

// MARK: - 拆开

/// 一笔拆成几笔：每行一个金额 + 分类，最后一行自动算剩下的。合计对上了才能保存。
struct SplitSheet: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    let tx: FinanceCore.Transaction

    struct Part: Identifiable { let id = UUID(); var amount = ""; var category: String? }
    @State var parts: [Part] = []
    @State var error: String?

    private var total: Money { tx.amount.magnitude }
    private var values: [Money?] { parts.map { Money.evaluate($0.amount).map(\.magnitude) } }
    private var sum: Money { values.compactMap { $0 }.reduce(.zero, +) }
    private var left: Money { total - sum }
    private var canSave: Bool {
        parts.count >= 2 && left == .zero && values.allSatisfy { ($0?.cents ?? 0) > 0 } && parts.allSatisfy { $0.category != nil }
    }
    private var categories: [String] { model.categories(bookID: tx.bookID, income: tx.amount.isIncome, limit: 40) }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(Merchant.display(tx.description))
                    Spacer()
                    Text(total.formatted).monospacedDigit().foregroundStyle(Color.fg2)
                }
            } footer: { Text(tr("比如超市 48,30 € 拆成「超市 30 €」和「日用品 18,30 €」。拆完合计不变，能撤销。")) }
            Section(tr("拆成")) {
                ForEach($parts) { $p in
                    HStack {
                        TextField(tr("金额"), text: $p.amount)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(maxWidth: 110)
                            .accessibilityLabel(tr("这一份的金额"))
                        Spacer()
                        Picker(tr("分类"), selection: $p.category) {
                            Text(tr("选分类")).tag(String?.none)
                            ForEach(categories, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        .labelsHidden()
                    }
                }
                .onDelete { parts.remove(atOffsets: $0) }
                Button { addPart() } label: { Label(tr("再加一份"), systemImage: "plus") }
            }
            Section {
                HStack {
                    Text(left == .zero ? tr("合计对上了") : left.cents > 0 ? tr("还差") : tr("多了"))
                    Spacer()
                    Text(left.magnitude.formatted).monospacedDigit()
                }
                .foregroundStyle(left == .zero ? Color.income : Color.alert)
                if left.cents > 0, let last = parts.indices.last {
                    Button(tr("剩下的 \(left.formatted) 都放进最后一份")) {
                        let lastValue = values[last] ?? .zero
                        parts[last].amount = (lastValue + left).inputText
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("拆开这一笔"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(tr("拆开"), action: save).disabled(!canSave) }
        }
        .onAppear {
            guard parts.isEmpty else { return }
            parts = [Part(amount: total.inputText, category: tx.category), Part()]
        }
        .errorAlert($error)
    }

    private func addPart() { parts.append(Part()) }

    private func save() {
        let list = zip(parts, values).map { SplitPart(amount: $1 ?? .zero, category: $0.category) }
        do {
            try model.edit { try $0.splitTransaction(tx.id, parts: list, author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - 多选后一起改

/// 选了好几笔时显示：一起改分类、改账本、加标签、删除。
struct BulkActions: View {
    @Environment(LedgerModel.self) var model
    let ids: Set<UUID>
    var onDone: () -> Void = {}
    @State var askTag = false
    @State var tagText = ""
    @State var confirmDelete = false

    private var txs: [FinanceCore.Transaction] { model.ledger.transactions.filter { ids.contains($0.id) } }
    private var plain: [UUID] { txs.filter(\.isPlainEntry).map(\.id) }

    var body: some View {
        let list = txs
        let income = list.filter { $0.amount.isIncome }.count > list.count / 2
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("选了 \(list.count) 笔")).font(.headline)
            Text(tr("合计 \(list.reduce(Money.zero) { $0 + $1.amount }.display)")).font(.subheadline).foregroundStyle(Color.fg2).monospacedDigit()
            VStack(spacing: 8) {
                Menu {
                    ForEach(model.categories(bookID: model.selectedBookID, income: income, limit: 40), id: \.self) { c in
                        Button(c) { model.perform { try $0.classify(plain, category: c, bookID: nil, author: model.author) } }
                    }
                } label: { Label(tr("改分类"), systemImage: "square.grid.2x2").frame(maxWidth: .infinity) }
                    .menuStyle(.button).buttonStyle(.soft).menuIndicator(.hidden)
                    .disabled(plain.isEmpty)
                if model.ledger.books.count > 1 {
                    Menu {
                        ForEach(model.ledger.books) { b in
                            Button(b.name) { model.perform { try $0.classify(plain, category: nil, bookID: b.id, author: model.author) } }
                        }
                    } label: { Label(tr("改账本"), systemImage: "books.vertical").frame(maxWidth: .infinity) }
                        .menuStyle(.button).buttonStyle(.soft).menuIndicator(.hidden)
                        .disabled(plain.isEmpty)
                }
                Button { tagText = ""; askTag = true } label: { Label(tr("加标签"), systemImage: "number").frame(maxWidth: .infinity) }
                    .buttonStyle(.soft)
                Button { confirmDelete = true } label: { Label(tr("删除这 \(list.count) 笔"), systemImage: "trash").frame(maxWidth: .infinity) }
                    .buttonStyle(.softAlert)
            }
            if plain.count < list.count {
                Text(tr("其中 \(list.count - plain.count) 笔是转账、借款、分期或存钱，不改分类和账本。"))
                    .font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .alert(tr("给这 \(list.count) 笔加标签"), isPresented: $askTag) {
            TextField(tr("比如「旅行」"), text: $tagText)
            Button(tr("取消"), role: .cancel) {}
            Button(tr("加上")) {
                let ids = list.map(\.id)
                model.perform { try $0.tagTransactions(ids, add: [tagText], author: model.author) }
            }
        }
        .confirmationDialog(tr("删除选中的 \(list.count) 笔？"), isPresented: $confirmDelete) {
            Button(tr("删除"), role: .destructive) {
                let all = Array(Set(list.flatMap { model.ledger.pairedIDs(of: $0.id) }))
                model.perform { try $0.removeTransactions(all, author: model.author) }
                onDone()
            }
        } message: { Text(tr("转账会连另一半一起删。删了能在改动记录里一次撤销。")) }
    }
}

// MARK: - 重复记账管理

/// 所有重复记账：多久一次、下次哪天；能暂停、继续、停掉。
struct RecurringManager: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            if model.ledger.recurring.isEmpty {
                Text(tr("还没有重复记账。记一笔时把「重复」选成每周、每月或每年，以后到日子就自动记上。"))
                    .font(.callout).foregroundStyle(Color.fg2)
            }
            ForEach(model.ledger.recurring) { r in
                HStack(spacing: 12) {
                    CategoryIcon(category: r.template.category, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.summary).font(.callout.weight(.medium)).lineLimit(2)
                        Text(r.paused ? tr("暂停中") : tr("下次 \(r.nextDate.friendly)") + (r.until.map { tr("，到 \($0.friendly) 为止") } ?? ""))
                            .font(.caption).foregroundStyle(r.paused ? Color.alert : Color.fg2)
                    }
                    Spacer()
                    Menu {
                        Button(r.paused ? tr("继续") : tr("暂停")) {
                            var x = r
                            x.paused.toggle()
                            model.perform { try $0.updateRecurring(x, author: model.author) }
                        }
                        Button(tr("停掉（已经记的不动）"), role: .destructive) {
                            model.perform { try $0.removeRecurring(r.id, author: model.author) }
                        }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden)
                        .accessibilityLabel(tr("\(r.template.description) 的操作"))
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(tr("重复记账"))
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("好")) { dismiss() } } }
    }
}
