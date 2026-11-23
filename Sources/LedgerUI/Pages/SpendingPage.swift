import Charts
import FinanceCore
import SwiftUI

/// 花销：钱都花在哪了？视觉重心是分类圆环，中间是本月花掉的总数。
struct SpendingPage: View {
    @Environment(LedgerModel.self) var model
    @State var byChange = false
    /// 主图样子：pie 圆饼 / bar 柱状，记住上次选的。
    @AppStorage("xiaxia.spendingChart") private var chartStyle = "pie"
    /// 页面能看到的大小（不算滚动）。窗口矮（比如 1000×612）：圆环小一点、排行少列三类；窗口窄：右栏收窄，仍然左右两栏，一屏放下。
    @State private var viewport = CGSize(width: 1000, height: 800)
    private var short: Bool { Viewport.isShort(viewport) }
    private var narrow: Bool { viewport.width < 900 }

    var body: some View {
        let month = model.shownMonth
        let now = model.summary(month)
        let totals = Reports.categoryTotals([now], expense: true)
        // 对比上个月（ming 2026-11-23）：看本月时比上月同期（1 号到今天），看以前的月就比整个上个月。
        let previous = previousByCategory(month)
        Group {
            if totals.isEmpty {
                KitEmptyState(symbol: "chart.pie", title: "\(month.month) 月还没花钱",
                              message: "有了花销，这里会按分类画一个圆环，告诉你钱都花在哪了。",
                              prompt: "这是我 \(month.month) 月的银行对账单，帮我整理好导进夏夏账本", page: "花销")
                    .kitCard()
            } else {
                VStack(alignment: .leading, spacing: Kit.gap) {
                    // ming 2026-11-23：夏夏卡放最上面，跟总览一样是一叠卡，专讲花销（哪类花多了、主要花在哪、怎么省）。
                    let nudges = Nudges.spending(month: month.month, current: totals, previous: previous, previousName: previousName(month),
                                                 transactions: model.expenseTransactions(month, bookID: model.selectedBookID),
                                                 currency: model.ledger.baseCurrency)
                    let insights = [model.ledger.insight(forPage: "spending", month: month, bookID: model.selectedBookID)].compactMap { $0 }
                    if nudges.isEmpty && insights.isEmpty {
                        XiaxiaSays(page: "spending", pageName: "花销", sentence: xiaxia(month: month, totals: totals, previous: previous),
                                   question: "\(month.month) 月钱主要花在哪了？哪些可以省？")
                    } else {
                        XiaxiaCards(nudges: nudges, insights: insights, page: "花销")
                    }
                    // 左边主图：本月和上月对比（圆饼 / 柱状）；右边分类排行。一屏放下。
                    Columns(sideWidth: 440) {
                        donutCard(month: month, now: now, totals: totals, previous: previous)
                    } side: {
                        rankingCard(month: month, totals: totals, previous: previous, total: now.expense.magnitude)
                    }
                }
            }
        }
        .kitPage()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
    }

    /// 看本月：上个月 1 号到同一天；看以前的月：整个上个月。
    private var sameDay: Int? {
        let today = LocalDate.today
        return model.shownMonth == today.yearMonth ? today.day : nil
    }

    /// 「上月同期」或「10 月」。
    private func previousName(_ month: YearMonth) -> String {
        sameDay == nil ? "\(month.previous.month) 月" : "上月同期"
    }

    private func previousByCategory(_ month: YearMonth) -> [String: Money] {
        let prev = month.previous
        var txs = model.baseTransactions
        if let day = sameDay { txs = txs.filter { $0.date.yearMonth != prev || $0.date.day <= day } }
        let summary = Summaries.monthly(txs, month: prev, bookID: model.selectedBookID, hiddenAccounts: model.hiddenAccounts)
        return Dictionary(Reports.categoryTotals([summary], expense: true).map { ($0.name, $0.amount) }, uniquingKeysWith: { a, _ in a })
    }

    /// 主图：本月和上个月（同期）的花销对比。ming 2026-11-23：「直接对比上个月和这个月的开支」「可以选择圆饼 柱状图」。
    /// 圆饼：两个圆环左右并排；柱状：每个分类上月灰柱、本月橙柱。顶上一句「比上月多/少花多少」，记住上次选的样子。
    private func donutCard(month: YearMonth, now: MonthlySummary, totals: [(name: String, amount: Money)], previous: [String: Money]) -> some View {
        let thisTotal = now.expense.magnitude
        let prevTotal = previous.values.reduce(Money.zero) { $0 + $1 }
        let prevTotals = previous.map { (name: $0.key, amount: $0.value) }.filter { $0.amount.cents > 0 }.sorted { $0.amount > $1.amount }
        let delta = thisTotal - prevTotal
        let top = totals.first { !["房租", "店租", "住房", "住房房租"].contains($0.name) } ?? totals[0]
        let topBefore = previous[top.name] ?? .zero
        let diff = top.amount - topBefore
        let prevLabel = sameDay.map { "\(month.previous.month) 月 1–\($0) 日" } ?? "\(month.previous.month) 月"
        return VStack(spacing: short ? 10 : 14) {
            SectionHeader(title: "和上个月比") {
                Picker("图表样子", selection: $chartStyle) {
                    Label("圆饼", systemImage: "chart.pie").tag("pie")
                    Label("柱状", systemImage: "chart.bar").tag("bar")
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .accessibilityIdentifier("spending.chartStyle")
            }
            Group {
                if prevTotal.cents == 0 {
                    Text("\(prevLabel)还没有记录，下个月起就能对比")
                } else if delta.magnitude.cents < 100 {
                    Text("和\(prevLabel)花得差不多")
                } else {
                    Text("比\(prevLabel)\(delta.isExpense ? "少花" : "多花") ") + Text(delta.magnitude.rounded).bold()
                }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(prevTotal.cents == 0 ? Color.fg3 : delta.isExpense ? Color.income : delta.magnitude.cents < 100 ? Color.fg2 : Color.alert)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(prevTotal.cents > 0 && delta.isExpense ? Color.incomeSoft : Color.sunken, in: Capsule())

            if chartStyle == "bar" {
                CompareBars(current: totals, previous: previous, currentName: "\(month.month) 月", previousName: prevLabel,
                            height: short ? 150 : 220)
                    .id(month)
            } else {
                let size: CGFloat = short ? 130 : narrow ? 160 : 190
                HStack(alignment: .top, spacing: short ? 16 : 28) {
                    VStack(spacing: 6) {
                        ZStack {
                            if prevTotal.cents == 0 {
                                Circle().stroke(Color.sunken, lineWidth: size * 0.15).padding(size * 0.075)
                            }
                            CategoryDonut(slices: CategoryDonut.slices(prevTotals), centerLabel: prevLabel, total: prevTotal, size: size)
                        }
                        .opacity(prevTotal.cents == 0 ? 0.6 : 0.85)
                        Text("上个月").font(.caption).foregroundStyle(Color.fg2)
                    }
                    .id("prev-\(month)")
                    VStack(spacing: 6) {
                        CategoryDonut(slices: CategoryDonut.slices(totals), centerLabel: "\(month.month) 月花掉", total: thisTotal, size: size)
                        Text("这个月").font(.caption.weight(.semibold))
                    }
                    .id(month)
                }
            }
            (Text(top.name == totals[0].name ? "" : "房租之外，") + em(top.name) + Text("是最大的一块")
             + Text(topBefore.cents == 0 ? "。" : diff.magnitude.cents < 100 ? "，和\(previousName(month))差不多。"
                    : "，比\(previousName(month))\(diff.isExpense ? "少" : "多") \(diff.magnitude.rounded)。"))
                .font(.body).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .kitCard(padding: short ? 16 : 24)
    }

    /// 夏夏先说的一句：比上个月多花最多的那一类（没有就说最大的一块）。
    private func xiaxia(month: YearMonth, totals: [(name: String, amount: Money)], previous: [String: Money]) -> String {
        let rises = totals.map { (name: $0.name, diff: $0.amount - (previous[$0.name] ?? .zero)) }
            .filter { !$0.diff.isExpense && $0.diff.cents >= 1000 && previous[$0.name] != nil }
            .sorted { $0.diff > $1.diff }
        if let up = rises.first {
            return model.voiced("\(up.name)比\(previousName(month))多花了 \(up.diff.rounded)，是涨得最多的一类。", .bad)
        }
        let top = totals[0]
        return previous.isEmpty ? model.voiced("\(month.month) 月花得最多的是\(top.name)，\(top.amount.rounded)。", .neutral)
            : model.voiced("各类都没比\(previousName(month))多花，最大的一块还是\(top.name)。", .good)
    }

    private func rankingCard(month: YearMonth, totals: [(name: String, amount: Money)], previous: [String: Money], total: Money) -> some View {
        let all = totals.map { CategorySlice(name: $0.name, amount: $0.amount) }
        let rows = byChange
            ? all.sorted { abs(($0.amount - (previous[$0.name] ?? .zero)).cents) > abs(($1.amount - (previous[$1.name] ?? .zero)).cents) }
            : all
        // 条的满格按这个月和上个月里最大的那个算，上个月的竖线不会跑出条外。
        let shownNames = Set(rows.prefix(short ? 5 : 8).map(\.name))
        let maxAmount = Double(max(totals.first?.amount.cents ?? 1, previous.filter { shownNames.contains($0.key) }.values.map(\.cents).max() ?? 0, 1))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "分类排行") {
                Picker("排序", selection: $byChange) {
                    Text("按金额").tag(false)
                    Text("按变化").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            ForEach(Array(rows.prefix(short ? 5 : 8))) { c in
                SectionLink(section: .transactions, filter: TransactionFilter(category: c.name)) {
                    HStack(spacing: 10) {
                        CategoryIcon(category: c.name, size: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(c.name).font(.callout)
                                Spacer()
                                Text("\(Int((Double(c.amount.cents) / Double(max(total.cents, 1)) * 100).rounded()))%")
                                    .font(.caption).foregroundStyle(Color.fg2).monospacedDigit()
                            }
                            Bar(fraction: Double(c.amount.cents) / maxAmount, color: CategoryStyle.color(c.name), height: 5)
                                .overlay(alignment: .leading) {
                                    // 上个月（同期）花到哪：一根细竖线。
                                    if let p = previous[c.name], p.cents > 0 {
                                        GeometryReader { g in
                                            Capsule().fill(Color.primary.opacity(0.7)).frame(width: 2, height: 11)
                                                .offset(x: min(g.size.width - 2, max(0, g.size.width * Double(p.cents) / maxAmount - 1)), y: -3)
                                        }
                                    }
                                }
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(c.amount.ui).font(.kitAmount)
                            change(c.amount, before: previous[c.name])
                        }
                        .frame(minWidth: narrow ? 70 : 86, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .hoverHighlight()
                .accessibilityLabel("\(c.name) \(c.amount.spoken)，\(changeWords(c.amount, before: previous[c.name], month: month))")
                .accessibilityHint("看这个分类的流水")
            }
            if !previous.isEmpty {
                HStack(spacing: 6) {
                    Capsule().fill(Color.primary.opacity(0.7)).frame(width: 2, height: 11)
                    Text(sameDay.map { "竖线是\(month.previous.month) 月 1–\($0) 日花到哪；右边是比那时多了还是少了" }
                         ?? "竖线是 \(month.previous.month) 月花到哪；右边是比 \(month.previous.month) 月多了还是少了")
                }
                .font(.caption).foregroundStyle(Color.fg2)
                .padding(.top, 4)
                .accessibilityHidden(true)
            }
        }
        .kitCard()
    }

    /// 金额下面一行：比上个月（同期）多了红色 ↑、少了绿色 ↓，上个月没有就写「上月没有」。
    @ViewBuilder private func change(_ now: Money, before: Money?) -> some View {
        if let before, before.cents > 0 {
            let d = now - before
            if d.magnitude.cents < 100 {
                Text("持平").font(.caption).foregroundStyle(Color.fg3)
            } else {
                Text("\(d.isExpense ? "↓" : "↑") \(d.magnitude.rounded)").font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(d.isExpense ? Color.income : Color.alert)
            }
        } else {
            Text("上月没有").font(.caption).foregroundStyle(Color.fg3)
        }
    }

    private func changeWords(_ now: Money, before: Money?, month: YearMonth) -> String {
        guard let before, before.cents > 0 else { return "\(previousName(month))没有" }
        let d = now - before
        if d.magnitude.cents < 100 { return "和\(previousName(month))差不多" }
        return "比\(previousName(month))\(d.isExpense ? "少" : "多") \(d.magnitude.rounded)"
    }
}

/// 每个分类上个月（灰）和这个月（橙）两根柱并排。最多 6 类，按这个月和上个月里大的那个排。
struct CompareBars: View {
    let current: [(name: String, amount: Money)]
    let previous: [String: Money]
    let currentName: String
    let previousName: String
    var height: CGFloat = 260

    private struct Bar: Identifiable {
        var category: String
        var period: String
        var value: Double
        var id: String { "\(category)-\(period)" }
    }

    var body: some View {
        var both: [String: (now: Money, before: Money)] = [:]
        for c in current { both[c.name, default: (.zero, .zero)].now = c.amount }
        for (k, v) in previous where v.cents > 0 { both[k, default: (.zero, .zero)].before = v }
        let names = both.sorted { max($0.value.now.cents, $0.value.before.cents) > max($1.value.now.cents, $1.value.before.cents) }
            .prefix(6).map(\.key)
        let bars = names.flatMap { n in
            [Bar(category: n, period: previousName, value: Double(both[n]!.before.cents) / 100),
             Bar(category: n, period: currentName, value: Double(both[n]!.now.cents) / 100)]
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(Color.fg3.opacity(0.55)).frame(width: 10, height: 10); Text(previousName) }
                HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(Color.brand).frame(width: 10, height: 10); Text(currentName) }
            }
            .font(.caption).foregroundStyle(Color.fg2)
            Chart(bars) { b in
                BarMark(x: .value("分类", b.category), y: .value("金额", b.value))
                    .position(by: .value("月份", b.period))
                    .foregroundStyle(b.period == currentName ? Color.brand : Color.fg3.opacity(0.55))
                    .cornerRadius(4)
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) €") } }
                }
            }
            .frame(height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(names.map { n in
            "\(n)：\(previousName) \(both[n]!.before.rounded)，\(currentName) \(both[n]!.now.rounded)"
        }.joined(separator: "；"))
    }
}
