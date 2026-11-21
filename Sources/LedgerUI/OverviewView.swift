import Charts
import FinanceCore
import SwiftUI

/// 总览：这个月进了多少、花了多少、剩多少；要处理的事；钱花在哪；各账户余额；最近几笔。
/// 用系统自带的分组列表（和「设置」「提醒事项」一个样子），只有最上面的大数字和主色是夏夏账本自己的。
public struct OverviewView: View {
    @Environment(LedgerModel.self) private var model
    @State private var grown = false
    @State private var chartPick: String?
    @State private var paying: InstallmentStatus?
    @State private var repaying: DebtStatus?

    public init() {}

    private var chartMonths: Int {
        #if os(iOS)
        6
        #else
        12
        #endif
    }

    public var body: some View {
        Group {
            if model.isLoading {
                ProgressView("正在读账本…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("总览")
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { grown = true } }
        .onChange(of: model.selectedBookID) { regrow() }
        .sheet(item: $paying) { i in NavigationStack { PayInstallmentView(status: i) }.sheetSize() }
        .sheet(item: $repaying) { d in NavigationStack { RepayView(debt: d) }.sheetSize() }
    }

    private func regrow() {
        grown = false
        withAnimation(.easeOut(duration: 0.6)) { grown = true }
    }

    private var monthBinding: Binding<YearMonth> {
        Binding(get: { model.shownMonth }, set: { m in
            withAnimation(.snappy) { model.selectedMonth = m == model.currentMonth ? nil : m }
        })
    }

    /// 总览只回答一个问题：「我现在怎么样」。重心是最上面的大数字（这个月全部剩下多少）和一句大白话；
    /// 下面小一号是每个账本各一张「赚了 / 亏了」的卡；再往下才是要处理的事和明细。
    private var content: some View {
        let month = model.shownMonth
        let all = model.summaries([month], bookID: nil)[0]
        let previous = model.summaries([month.adding(months: -1)], bookID: nil)[0]
        let hasRealFlow = model.ledger.transactions.contains { $0.flow == nil }
        return Form {
            heroSection(month: month, s: all, previous: previous)
            if model.ledger.books.count > 1 { booksSection(month: month) }
            if !hasRealFlow { startSection }
            todoSection
            spendingSection(month: month, s: all)
            accountsSection
            recentSection
        }
        .formStyle(.grouped)
    }

    // MARK: 还没有流水时：从哪开始

    private var startSection: some View {
        Section {
            Button { model.sheet = .add } label: { Label("记第一笔", systemImage: "plus.circle.fill") }
            Button { model.sheet = .importer } label: { Label("导入银行对账单", systemImage: "tray.and.arrow.down") }
        } header: { Text("开始记账") } footer: {
            Text("平时随手记一笔，或者每个月把对账单导进来一次整理完。两条可以一起用，重复的会自动跳过。")
        }
    }

    // MARK: 视觉重心：这个月剩多少

    private func heroSection(month: YearMonth, s: MonthlySummary, previous: MonthlySummary) -> some View {
        Section {
            VStack(spacing: 10) {
                HStack {
                    MonthStepper(month: monthBinding)
                    if model.selectedMonth != nil {
                        Button("回到这个月") { withAnimation(.snappy) { model.selectedMonth = nil } }.buttonStyle(.borderless).font(.subheadline)
                    }
                }
                Text(s.net.isExpense ? "\(month.month) 月超支了" : "\(month.month) 月还剩").font(.headline).foregroundStyle(.secondary)
                BigAmount(money: grown ? s.net.magnitude : .zero, size: 56)
                    .foregroundStyle(s.net.isExpense ? Color.coral : Color.primary)
                Text(sentence(s, previous))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    /// 一句大白话：进了多少、花了多少、和上个月比。
    private func sentence(_ s: MonthlySummary, _ p: MonthlySummary) -> String {
        var line = "进账 \(s.income.formatted)，花掉 \(s.expense.magnitude.formatted)"
        if let more = compare(s, p) { line += "\n" + more }
        return line
    }

    // MARK: 每个账本赚了还是亏了

    private func booksSection(month: YearMonth) -> some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(model.ledger.books) { b in
                    let s = model.summaries([month], bookID: b.id)[0]
                    Button {
                        withAnimation(.snappy) { model.selectedBookID = b.id }
                        model.section = .reports
                    } label: { bookTile(b, s) }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func bookTile(_ b: Book, _ s: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(b.name).font(.subheadline.weight(.semibold))
            Text(s.net.isExpense ? "亏了" : "赚了").font(.caption).foregroundStyle(.secondary)
            Text(s.net.magnitude.formatted)
                .font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(s.net.isExpense ? Color.coral : Color.income)
                .minimumScaleFactor(0.6).lineLimit(1)
            if s.betweenBooks.cents != 0 {
                Text("\(Reports.betweenBooksLabel(s.betweenBooks, bookID: b.id, books: model.ledger.books)) \(s.betweenBooks.magnitude.formatted)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("看这个账本的报表")
    }

    private func amountRow(_ title: String, symbol: String, money: Money, color: Color) -> some View {
        LabeledContent {
            Text((grown ? money : .zero).formatted).monospacedDigit().foregroundStyle(color == .secondary ? Color.primary : color)
                .contentTransition(.numericText(value: Double(money.cents)))
        } label: {
            Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(color) }
        }
    }

    /// 和上个月比的一句话。
    private func compare(_ s: MonthlySummary, _ p: MonthlySummary) -> String? {
        guard p.expense.cents != 0 || p.income.cents != 0 else { return nil }
        let diff = s.expense.magnitude.cents - p.expense.magnitude.cents
        if diff == 0 { return "花的和上个月一样多。" }
        let amount = Money(cents: abs(diff)).formatted
        return diff > 0 ? "比上个月多花了 \(amount)。" : "比上个月少花了 \(amount)。"
    }

    static func compact(_ v: Double) -> String {
        abs(v) >= 1000 ? String(format: "%.0fk", v / 1000).replacingOccurrences(of: ".0k", with: "k") : String(format: "%.0f", v)
    }

    // MARK: 要处理的事

    @ViewBuilder
    private var todoSection: some View {
        let untidy = model.untidy.count
        // 选了某个账本时，只列这个账本的借款和分期（看 Miora 时不该冒出个人借给阿华的钱）。
        let book = model.selectedBookID
        let debtBooks = Dictionary(model.ledger.debts.map { ($0.id, $0.bookID) }, uniquingKeysWith: { a, _ in a })
        let planBooks = Dictionary(model.ledger.installments.map { ($0.id, $0.bookID) }, uniquingKeysWith: { a, _ in a })
        let debts = Plans.debts(model.ledger, today: .today).filter { $0.overdue && (book == nil || debtBooks[$0.id] == book) }
        let due = Plans.installments(model.ledger).filter {
            $0.paidCount < $0.count && ($0.nextDate?.daysFromToday ?? 99) <= 10 && (book == nil || planBooks[$0.id] == book)
        }
        if untidy > 0 || !debts.isEmpty || !due.isEmpty {
            Section("要处理的事") {
                if untidy > 0 {
                    todoRow(symbol: "tray.full.fill", title: "\(untidy) 笔还没分类",
                            detail: "同一个商户的一次改完", action: "去整理") { model.sheet = .triage }
                }
                ForEach(due, id: \.id) { i in
                    let days = i.nextDate?.daysFromToday ?? 0
                    todoRow(symbol: "calendar", title: "「\(i.name)」第 \(i.paidCount + 1)/\(i.count) 期 \(i.perPayment.formatted)",
                            detail: days < 0 ? "应该 \(i.nextDate?.short ?? "") 扣，已经过了 \(-days) 天" : days == 0 ? "今天扣款" : "\(i.nextDate?.short ?? "") 扣款，还有 \(days) 天",
                            action: "记这一期") { paying = i }
                }
                ForEach(debts, id: \.id) { d in
                    todoRow(symbol: "person.2.fill",
                            title: d.direction == .theyOweMe ? "\(d.counterparty) 还欠你 \(d.outstanding.formatted)" : "你还欠 \(d.counterparty) \(d.outstanding.formatted)",
                            detail: "约好 \(d.dueDate?.short ?? "") 前还，已经过了", action: "记还款") { repaying = d }
                }
            }
        }
    }

    private func todoRow(symbol: String, title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: symbol).foregroundStyle(Color.coral) }
            Spacer()
            Button(action, action: perform).buttonStyle(.bordered)
        }
    }

    // MARK: 钱花在哪

    @ViewBuilder
    private func spendingSection(month: YearMonth, s: MonthlySummary) -> some View {
        let cats = Reports.categoryTotals([s], expense: true)
        let total = max(s.expense.magnitude.cents, 1)
        Section {
            if cats.isEmpty {
                Text("这个月还没有支出。").foregroundStyle(.secondary)
            }
            ForEach(cats.prefix(6), id: \.name) { c in
                NavigationLink {
                    TransactionsView(filter: TransactionFilter(month: month, category: c.name, sign: .expense), title: c.name)
                } label: {
                    LabeledContent {
                        Text(c.amount.formatted).monospacedDigit()
                    } label: {
                        Label {
                            HStack(spacing: 6) {
                                Text(c.name)
                                Text("\(Int((Double(c.amount.cents) / Double(total) * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: CategoryStyle.symbol(c.name) ?? "tag").foregroundStyle(c.name == "未分类" ? Color.secondary : Color.coral)
                        }
                    }
                }
            }
            if !cats.isEmpty {
                Button("所有分类和全年报表") { model.section = .reports }
            }
        } header: { Text("\(month.month) 月钱花在哪") }
    }

    // MARK: 账户

    private var accountsSection: some View {
        let balances = model.balances
        return Section {
            ForEach(model.visibleAccounts) { a in
                let b = balances[a.id] ?? .zero
                NavigationLink {
                    TransactionsView(filter: TransactionFilter(accountID: a.id), title: a.name)
                } label: {
                    LabeledContent {
                        Text(b.formatted).monospacedDigit()
                            .foregroundStyle(b.isExpense && a.kind != .credit ? Color.coral : .primary)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name)
                                if a.kind == .credit, b.isExpense {
                                    Text("信用卡，还欠这么多").font(.caption).foregroundStyle(.secondary)
                                } else if b.isExpense {
                                    Text("余额是负的，可能少记了开账余额").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: { Image(systemName: a.isPrivate ? "lock.fill" : a.kind.symbol) }
                    }
                }
            }
        } header: { Text("账户") } footer: {
            Text("全部加起来 \(model.totalBalance.formatted)（信用卡欠的已经减掉）").monospacedDigit()
        }
    }

    // MARK: 最近几笔

    private var recentSection: some View {
        let recent = Array(model.visibleTransactions.filter { $0.flow != .opening }.prefix(5))
        return Section {
            if recent.isEmpty {
                Text("还没有流水。").foregroundStyle(.secondary)
            }
            ForEach(recent) { t in
                Button { model.sheet = .edit(t.id) } label: { TransactionRow(tx: t, showDate: true) }
                    .buttonStyle(.plain)
            }
            Button("看全部流水") { model.section = .transactions }
        } header: { Text("最近几笔") }
    }


}
