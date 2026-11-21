import FinanceCore
import SwiftUI

/// 整理：把还没分类、没分账本的流水一组一组过。同一个商户的几笔一次改完；
/// 以前分过类的商户会先猜好，看一眼点「就这样」就行。
struct TriageView: View {
    struct Batch: Identifiable {
        let id: String
        var transactions: [Transaction]
        var first: Transaction { transactions[0] }
        var total: Money { transactions.reduce(.zero) { $0 + $1.amount } }
    }

    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<String> = []
    @State private var bookID = ""
    @State private var category = ""
    @State private var custom = ""
    @State private var guessed = false
    @State private var shownGroup = ""
    @State private var done = 0
    @State private var startCount = 0
    @State private var error: String?

    /// 同一个商户（说明归一化后相同）、同一个方向的算一组，笔数多的排前面。
    private var groups: [Batch] {
        var order: [String] = []
        var map: [String: [Transaction]] = [:]
        for t in model.untidy {
            let key = Dedup.normalize(t.description) + (t.amount.isIncome ? "|+" : "|-")
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(t)
        }
        return order.map { Batch(id: $0, transactions: map[$0] ?? []) }
            .filter { !skipped.contains($0.id) }
            .sorted { $0.transactions.count > $1.transactions.count }
    }

    var body: some View {
        let list = groups
        VStack(spacing: 0) {
            if let g = list.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        progress(left: list.reduce(0) { $0 + $1.transactions.count })
                        card(g)
                        choices(g)
                    }
                    .padding(20)
                }
                Divider()
                footer(g)
            } else {
                finished
            }
        }
        .navigationTitle("整理")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .onAppear { startCount = model.untidy.count; prepare(list.first) }
        .onChange(of: list.first?.id) { prepare(list.first) }
        .errorAlert($error)
        .animation(.snappy, value: list.first?.id)
    }

    private func progress(left: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还剩 \(left) 笔 · 这次已整理 \(done) 笔").font(.subheadline).foregroundStyle(.secondary)
            Bar(fraction: startCount > 0 ? Double(done) / Double(max(done + left, 1)) : 0, color: .income)
        }
    }

    private func card(_ g: Batch) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(Merchant.display(g.first.description)).font(.title3.weight(.semibold)).lineLimit(2)
                Spacer()
                AmountText(money: g.total, font: .title3.weight(.semibold))
            }
            if g.transactions.count > 1 {
                Text("同名的有 \(g.transactions.count) 笔，一起改。").font(.subheadline).foregroundStyle(Color.coral)
            }
            ForEach(g.transactions.prefix(4)) { t in
                HStack {
                    Text(t.date.friendly)
                    Text(model.accountName(t.accountID))
                    Spacer()
                    Text(t.amount.formatted).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            if g.transactions.count > 4 { Text("还有 \(g.transactions.count - 4) 笔…").font(.caption).foregroundStyle(.tertiary) }
        }
        .id(g.id)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func choices(_ g: Batch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if guessed {
                Label("按以前的习惯先猜了一个，不对就改。", systemImage: "wand.and.stars").font(.footnote).foregroundStyle(.secondary)
            }
            Text("是谁的账？").font(.headline)
            Picker("账本", selection: $bookID.animation(.snappy)) {
                ForEach(model.ledger.books) { b in Text(b.name).tag(b.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(g.first.amount.isIncome ? "这笔钱是什么？" : "花在什么上？").font(.headline)
            CategoryChips(categories: chips(g), selection: $category)
            HStack {
                TextField("别的分类，自己写", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { useCustom() }
                Button("用这个", action: useCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            Button { markMove(g) } label: {
                Label("这不是收入也不是花销，是我自己账户之间转钱（取现、转到另一张卡）", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.borderless)
        }
    }

    private func footer(_ g: Batch) -> some View {
        HStack {
            Button("先跳过") { withAnimation { _ = skipped.insert(g.id) } }
            Spacer()
            Button { apply(g) } label: {
                Text(category.isEmpty ? "先选一个分类" : "就这样，下一个").frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(category.isEmpty || bookID.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var finished: some View {
        ContentUnavailableView {
            Label(skipped.isEmpty ? "都整理好了" : "剩下的你都跳过了", systemImage: skipped.isEmpty ? "checkmark.seal.fill" : "tray")
        } description: {
            Text(done > 0 ? "这次整理了 \(done) 笔。下次同样的商户会自动猜好分类。" : "没有需要整理的流水。")
        } actions: {
            if !skipped.isEmpty { Button("再看一遍跳过的") { skipped = [] } }
            Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chips(_ g: Batch) -> [String] {
        var list = model.categories(bookID: bookID.isEmpty ? nil : bookID, income: g.first.amount.isIncome, limit: 16)
        if !category.isEmpty, !list.contains(category) { list.insert(category, at: 0) }
        return list
    }

    /// 换到下一组时，把猜到的分类和账本先填上。
    private func prepare(_ g: Batch?) {
        guard let g, g.id != shownGroup else { return }
        shownGroup = g.id
        custom = ""
        let guess = model.suggester.guess(g.first.description)
        category = g.first.category ?? guess.category ?? ""
        let book = g.first.bookID ?? guess.bookID
        guessed = (g.first.category == nil && guess.category != nil) || (g.first.bookID == nil && guess.bookID != nil)
        bookID = book ?? (bookID.isEmpty ? model.defaultBookID : bookID)
    }

    private func useCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        category = name
    }

    private func apply(_ g: Batch) {
        guard !category.isEmpty, !bookID.isEmpty else { return }
        let ids = g.transactions.map(\.id)
        do {
            try model.edit(quiet: true) { try $0.classify(ids, category: category, bookID: bookID, author: model.author) }
            done += ids.count
            model.lastBookID = bookID
        } catch { self.error = error.localizedDescription }
    }

    private func markMove(_ g: Batch) {
        let ids = g.transactions.map(\.id)
        do {
            try model.edit(quiet: true) { try $0.markAsAccountTransfer(ids, author: model.author) }
            done += ids.count
        } catch { self.error = error.localizedDescription }
    }
}
