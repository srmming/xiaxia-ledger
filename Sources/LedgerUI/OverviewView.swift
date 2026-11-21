import Charts
import FinanceCore
import SwiftUI

/// 总览：这个月进了多少、花了多少、剩多少；要处理的事；各账户余额；钱花在哪；最近几笔。
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
        return VStack(alignment: .leading, spacing: 16) {
            BookPicker()
            if !hasRealFlow { startCard }
            monthCard(month: month, s: s, previous: previous, series: series)
            todoCard
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                accountsCard
                spendingCard(month: month, s: s)
                recentCard
                plansCard
            }
        }
        .padding(.bottom, 70)   // iPhone 底部标签栏会盖住最后几行
        .pageScroll(maxWidth: 1040)
    }

    // MARK: 还没有流水时：从哪开始

    private var startCard: some View {
        Card {
            CardHeader("账户建好了，接下来")
            Text("记账有两条路：平时随手记一笔；或者每个月把银行对账单导进来，一次整理完。两条可以一起用，重复的会自动跳过。")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button { model.sheet = .add } label: { Label("记第一笔", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Button { model.sheet = .importer } label: { Label("导入对账单", systemImage: "tray.and.arrow.down") }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: 这个月

    private func monthCard(month: YearMonth, s: MonthlySummary, previous: MonthlySummary, series: [MonthlySummary]) -> some View {
        Card {
            HStack {
                MonthStepper(month: monthBinding)
                Spacer()
                if model.selectedMonth != nil {
                    Button("回到最新") { withAnimation(.snappy) { model.selectedMonth = nil } }.font(.caption).buttonStyle(.borderless)
                }
            }
            Text("\(model.bookName(model.selectedBookID)) · 这个月剩下").font(.subheadline).foregroundStyle(.secondary)
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
            HStack(spacing: 20) {
                figure("进账", money: s.income, color: .income, symbol: "arrow.down.left") {
                    model.showTransactions(TransactionFilter(month: month, sign: .income))
                }
                figure("花掉", money: s.expense.magnitude, color: .coral, symbol: "arrow.up.right") {
                    model.showTransactions(TransactionFilter(month: month, sign: .expense))
                }
            }
            if let line = compare(s, previous) {
                Text(line).font(.footnote).foregroundStyle(.secondary)
            }
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
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Self.compact(v)).font(.caption2) }
                    }
                }
            }
            .chartXSelection(value: $chartPick)
            .frame(height: 150)
            .onChange(of: chartPick) { _, label in
                guard let label, let hit = series.first(where: { $0.month.shortLabel == label }) else { return }
                monthBinding.wrappedValue = hit.month
            }
            .accessibilityLabel("近 \(series.count) 个月每月进账和花掉的柱状图，点一个月可以切过去")
            Text("绿色是进账，橙色是花掉。点一根柱子看那个月。").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func figure(_ title: String, money: Money, color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.caption.bold()).foregroundStyle(color)
                    .frame(width: 24, height: 24).background(color.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text((grown ? money : .zero).formatted).font(.body.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(money.cents)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("看这些流水")
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
    private var todoCard: some View {
        let untidy = model.untidy.count
        let debts = Plans.debts(model.ledger, today: .today).filter(\.overdue)
        let due = Plans.installments(model.ledger).filter { $0.paidCount < $0.count && ($0.nextDate?.daysFromToday ?? 99) <= 10 }
        if untidy > 0 || !debts.isEmpty || !due.isEmpty {
            Card {
                CardHeader("要处理的事")
                if untidy > 0 {
                    todoRow(symbol: "tray.full", title: "\(untidy) 笔流水还没分类或没分账本",
                            detail: "一笔一笔过，同名的一次改完", action: "去整理") { model.sheet = .triage }
                }
                ForEach(due, id: \.id) { i in
                    let days = i.nextDate?.daysFromToday ?? 0
                    todoRow(symbol: "calendar", title: "「\(i.name)」第 \(i.paidCount + 1)/\(i.count) 期 \(i.perPayment.formatted)",
                            detail: days < 0 ? "应该 \(i.nextDate?.short ?? "") 扣，已经过了 \(-days) 天" : days == 0 ? "今天扣款" : "\(i.nextDate?.short ?? "") 扣款，还有 \(days) 天",
                            action: "记这一期") { paying = i }
                }
                ForEach(debts, id: \.id) { d in
                    todoRow(symbol: "person.2",
                            title: d.direction == .theyOweMe ? "\(d.counterparty) 还欠你 \(d.outstanding.formatted)" : "你还欠 \(d.counterparty) \(d.outstanding.formatted)",
                            detail: "约好 \(d.dueDate?.short ?? "") 前还，已经过了", action: "记还款") { repaying = d }
                }
            }
        }
    }

    private func todoRow(symbol: String, title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.coral)
                .frame(width: 30, height: 30).background(Color.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action, action: perform).buttonStyle(.bordered).controlSize(.small)
        }
    }

    // MARK: 账户

    private var accountsCard: some View {
        let balances = model.balances
        return Card {
            CardHeader(title: "账户") {
                (Text("一共 ").foregroundStyle(.secondary) + Text(model.totalBalance.formatted).bold()).monospacedDigit()
            }
            ForEach(model.visibleAccounts) { a in
                let b = balances[a.id] ?? .zero
                NavigationLink {
                    TransactionsView(filter: TransactionFilter(accountID: a.id), title: a.name)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: a.isPrivate ? "lock.fill" : a.kind.symbol)
                            .frame(width: 30, height: 30)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        Text(a.name)
                        Spacer()
                        Text(b.formatted).monospacedDigit().fontWeight(.medium)
                            .foregroundStyle(b.isExpense ? Color.coral : .primary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            if model.visibleAccounts.count > 1 {
                Button { model.sheet = .add } label: {
                    Label("账户之间转了钱（取现、转到另一张卡）？记一笔「转账」", systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: 钱花在哪

    @ViewBuilder
    private func spendingCard(month: YearMonth, s: MonthlySummary) -> some View {
        let cats = Reports.categoryTotals([s], expense: true)
        let total = max(s.expense.magnitude.cents, 1)
        Card {
            CardHeader(title: "\(month.month) 月钱花在哪") {
                Button("看报表") { model.section = .reports }.buttonStyle(.borderless)
            }
            if cats.isEmpty {
                Text("这个月还没有支出。").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach(cats.prefix(7), id: \.name) { c in
                NavigationLink {
                    TransactionsView(filter: TransactionFilter(month: month, category: c.name, sign: .expense), title: c.name)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: CategoryStyle.symbol(c.name) ?? "tag").font(.caption).foregroundStyle(Color.coral).frame(width: 18)
                            Text(c.name)
                            Text("\(Int((Double(c.amount.cents) / Double(total) * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(c.amount.formatted).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        Bar(fraction: grown ? Double(c.amount.cents) / Double(max(cats.first?.amount.cents ?? 1, 1)) : 0,
                            color: c.name == "未分类" ? .gray : .coral)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if cats.count > 7 {
                Text("还有 \(cats.count - 7) 个分类，在报表里看全部。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 最近几笔

    private var recentCard: some View {
        let recent = Array(model.visibleTransactions.filter { $0.flow != .opening }.prefix(6))
        return Card(spacing: 6) {
            CardHeader(title: "最近几笔") {
                Button("全部流水") { model.section = .transactions }.buttonStyle(.borderless)
            }
            if recent.isEmpty {
                Text("还没有流水。点右上角 ＋ 记一笔。").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach(recent) { t in
                Button { model.sheet = .edit(t.id) } label: { TransactionRow(tx: t, showDate: true) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: 计划

    @ViewBuilder
    private var plansCard: some View {
        let debts = Plans.debts(model.ledger, today: .today)
        let owed = debts.filter { $0.direction == .theyOweMe }.reduce(Money.zero) { $0 + $1.outstanding }
        let owe = debts.filter { $0.direction == .iOweThem }.reduce(Money.zero) { $0 + $1.outstanding }
        let goals = Plans.goals(model.ledger)
        let insts = Plans.installments(model.ledger).filter { $0.paidCount < $0.count }
        if !debts.isEmpty || !goals.isEmpty || !insts.isEmpty {
            Card {
                CardHeader(title: "计划") {
                    Button("全部计划") { model.section = .plans }.buttonStyle(.borderless)
                }
                if !debts.isEmpty {
                    HStack {
                        LabeledContent("别人欠我") { Text(owed.formatted).monospacedDigit().foregroundStyle(Color.income) }
                        Divider().frame(height: 16)
                        LabeledContent("我欠别人") { Text(owe.formatted).monospacedDigit() }
                    }
                    .font(.subheadline)
                }
                if !insts.isEmpty {
                    let left = insts.reduce(Money.zero) { $0 + $1.remaining }
                    LabeledContent("分期还剩（\(insts.count) 个）") { Text(left.formatted).monospacedDigit() }.font(.subheadline)
                }
                ForEach(goals.prefix(3), id: \.id) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if g.locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                            Text(g.name)
                            Spacer()
                            Text("\(g.saved.formatted) / \(g.target.formatted)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        Bar(fraction: grown ? Double(g.percent) / 100 : 0, color: .income)
                    }
                }
            }
        }
    }
}
