import FinanceCore
import SwiftUI

/// 花销：钱都花在哪了？视觉重心是分类圆环，中间是本月花掉的总数。
struct SpendingPage: View {
    @Environment(LedgerModel.self) var model
    @State var byChange = false
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
                    // ming 2026-11-23：「花得最多的商户」不要了，一屏放下：左边圆环 + 夏夏，右边分类排行（带上月对比）。
                    Columns(sideWidth: 440) {
                        donutCard(month: month, now: now, totals: totals, previous: previous)
                        XiaxiaSays(page: "spending", pageName: "花销", sentence: xiaxia(month: month, totals: totals, previous: previous),
                                   question: "\(month.month) 月钱主要花在哪了？哪些可以省？")
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

    private func donutCard(month: YearMonth, now: MonthlySummary, totals: [(name: String, amount: Money)], previous: [String: Money]) -> some View {
        let status = model.status(month)
        let delta = status.spentSoFar - status.lastMonthSameDaySpent
        let top = totals.first { !["房租", "店租", "住房", "住房房租"].contains($0.name) } ?? totals[0]
        let topBefore = previous[top.name] ?? .zero
        let diff = top.amount - topBefore
        return VStack(spacing: 14) {
            CategoryDonut(slices: CategoryDonut.slices(totals), centerLabel: "\(month.month) 月花掉", total: now.expense.magnitude, size: short ? 180 : 250)
                .id(month)
            if status.lastMonthSameDaySpent.cents > 0 {
                Text(delta.isExpense ? "比上月同期少花 \(delta.magnitude.rounded)" : "比上月同期多花 \(delta.rounded)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(delta.isExpense ? Color.income : Color.fg2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(delta.isExpense ? Color.incomeSoft : Color.sunken, in: Capsule())
            } else {
                // 新账本上个月没记录时也让人知道这里会对比（ming 2026-11-23 新装后问「花销对比有了吗」）。
                Text("\(previousName(month))还没有记录，记满两个月就能对比")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.fg3)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.sunken, in: Capsule())
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
        let shownNames = Set(rows.prefix(short ? 7 : 10).map(\.name))
        let maxAmount = Double(max(totals.first?.amount.cents ?? 1, previous.filter { shownNames.contains($0.key) }.values.map(\.cents).max() ?? 0, 1))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "分类排行") {
                Picker("排序", selection: $byChange) {
                    Text("按金额").tag(false)
                    Text("按变化").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            ForEach(Array(rows.prefix(short ? 7 : 10))) { c in
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
