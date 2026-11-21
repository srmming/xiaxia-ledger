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

    private var content: some View {
        let month = model.shownMonth
        let months = Reports.months(endingAt: max(month, model.currentMonth), count: chartMonths)
        let series = model.summaries(months)
        let s = model.summary(month)
        let previous = model.summary(month.adding(months: -1))
        let hasRealFlow = model.ledger.transactions.contains { $0.flow == nil }
        return Form {
            Section {
                BookPicker().frame(maxWidth: .infinity)
            }
            if !hasRealFlow { startSection }
            monthSection(month: month, s: s, previous: previous)
            todoSection
            spendingSection(month: month, s: s)
            chartSection(month: month, series: series)
            accountsSection
            recentSection
            plansSection
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

    // MARK: 这个月

    private func monthSection(month: YearMonth, s: MonthlySummary, previous: MonthlySummary) -> some View {
        Section {
            HStack {
                MonthStepper(month: monthBinding)
                Spacer()
                if model.selectedMonth != nil {
                    Button("回到这个月") { withAnimation(.snappy) { model.selectedMonth = nil } }.buttonStyle(.borderless)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.bookName(model.selectedBookID)) · \(month.month) 月剩下").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    BigAmount(money: grown ? s.net : .zero)
                        .foregroundStyle(s.net.isExpense ? Color.coral : Color.primary)
                    if let rate = Plans.savingsRate(s), rate > 0 {
                        Text("存下 \(rate)%").font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.income.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.income)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            NavigationLink {
                TransactionsView(filter: TransactionFilter(month: month, sign: .income), title: "\(month.month) 月进账")
            } label: {
                amountRow("进账", symbol: "arrow.down.left.circle.fill", money: s.income, color: .income)
            }
            NavigationLink {
                TransactionsView(filter: TransactionFilter(month: month, sign: .expense), title: "\(month.month) 月花掉")
            } label: {
                amountRow("花掉", symbol: "arrow.up.right.circle.fill", money: s.expense.magnitude, color: .coral)
            }
            if let bookID = model.selectedBookID, s.betweenBooks.cents != 0 {
                // 从店里拿回家的钱 / 老板从店里拿走的钱：不算收入也不算支出，单独一行说清楚。
                amountRow(Reports.betweenBooksLabel(s.betweenBooks, bookID: bookID, books: model.ledger.books),
                          symbol: "arrow.left.arrow.right.circle.fill", money: s.betweenBooks.magnitude, color: .secondary)
                    .help("自己账户之间挪的钱，不算收入也不算支出")
            }
        } footer: {
            if let line = compare(s, previous) { Text(line) }
        }
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

    // MARK: 近几个月

    private func chartSection(month: YearMonth, series: [MonthlySummary]) -> some View {
        Section {
            Chart {
                ForEach(series, id: \.month) { m in
                    BarMark(x: .value("月份", m.month.shortLabel), y: .value("金额", grown ? Double(m.income.cents) / 100 : 0), width: .ratio(0.7))
                        .foregroundStyle(by: .value("类型", "进账"))
                        .position(by: .value("类型", "进账"))
                        .opacity(m.month == month ? 1 : 0.4)
                    BarMark(x: .value("月份", m.month.shortLabel), y: .value("金额", grown ? Double(m.expense.magnitude.cents) / 100 : 0), width: .ratio(0.7))
                        .foregroundStyle(by: .value("类型", "花掉"))
                        .position(by: .value("类型", "花掉"))
                        .opacity(m.month == month ? 1 : 0.4)
                }
            }
            .chartForegroundStyleScale(["进账": Color.income, "花掉": Color.coral])
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Self.compact(v)).font(.caption2) }
                    }
                }
            }
            .chartXSelection(value: $chartPick)
            .frame(height: 170)
            .padding(.vertical, 8)
            .onChange(of: chartPick) { _, label in
                guard let label, let hit = series.first(where: { $0.month.shortLabel == label }) else { return }
                monthBinding.wrappedValue = hit.month
            }
            .accessibilityLabel("近 \(series.count) 个月每月进账和花掉的柱状图，点一个月可以切过去")
        } header: { Text("近 \(series.count) 个月") } footer: { Text("点一根柱子看那个月。") }
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

    // MARK: 借款、分期、存钱

    @ViewBuilder
    private var plansSection: some View {
        let debts = Plans.debts(model.ledger, today: .today)
        let owed = debts.filter { $0.direction == .theyOweMe }.reduce(Money.zero) { $0 + $1.outstanding }
        let owe = debts.filter { $0.direction == .iOweThem }.reduce(Money.zero) { $0 + $1.outstanding }
        let goals = Plans.goals(model.ledger)
        let insts = Plans.installments(model.ledger).filter { $0.paidCount < $0.count }
        if !debts.isEmpty || !goals.isEmpty || !insts.isEmpty {
            Section {
                if owed.cents != 0 {
                    LabeledContent { Text(owed.formatted).monospacedDigit().foregroundStyle(Color.income) } label: {
                        Label("别人欠我", systemImage: "arrow.down.left.circle")
                    }
                }
                if owe.cents != 0 {
                    LabeledContent { Text(owe.formatted).monospacedDigit() } label: { Label("我欠别人", systemImage: "arrow.up.right.circle") }
                }
                if !insts.isEmpty {
                    LabeledContent { Text(insts.reduce(Money.zero) { $0 + $1.remaining }.formatted).monospacedDigit() } label: {
                        Label("分期还没还完（\(insts.count) 个）", systemImage: "calendar")
                    }
                }
                ForEach(goals.prefix(3), id: \.id) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent {
                            Text("\(g.saved.formatted) / \(g.target.formatted)").monospacedDigit()
                        } label: {
                            Label(g.name, systemImage: g.locked ? "lock.fill" : "target")
                        }
                        ProgressView(value: grown ? Double(min(g.percent, 100)) : 0, total: 100).tint(Color.income)
                    }
                }
                Button("看借款、分期和存钱") { model.section = .plans }
            } header: { Text("借款、分期、存钱") }
        }
    }
}
