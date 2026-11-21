import FinanceCore
import SwiftUI

/// 花销：钱都花在哪了？视觉重心是分类圆环，中间是本月花掉的总数。
struct SpendingPage: View {
    @Environment(LedgerModel.self) var model
    @State var byChange = false

    var body: some View {
        let month = model.shownMonth
        let now = model.summary(month)
        let before = model.summary(month.previous)
        let totals = Reports.categoryTotals([now], expense: true)
        let previous = Dictionary(Reports.categoryTotals([before], expense: true).map { ($0.name, $0.amount) }, uniquingKeysWith: { a, _ in a })
        Group {
            if totals.isEmpty {
                KitEmptyState(symbol: "chart.pie", title: "\(month.month) 月还没花钱",
                              message: "有了花销，这里会按分类画一个圆环，告诉你钱都花在哪了。",
                              prompt: "这是我 \(month.month) 月的银行对账单，帮我整理好导进夏夏账本", page: "花销")
                    .kitCard()
            } else {
                VStack(alignment: .leading, spacing: Kit.gap) {
                    Columns(sideWidth: 440, breakpoint: 760) {
                        donutCard(month: month, now: now, totals: totals, previous: previous)
                    } side: {
                        rankingCard(totals: totals, previous: previous, total: now.expense.magnitude)
                    }
                    merchantsCard(month: month)
                }
            }
        }
        .kitPage()
    }

    private func donutCard(month: YearMonth, now: MonthlySummary, totals: [(name: String, amount: Money)], previous: [String: Money]) -> some View {
        let status = model.status(month)
        let delta = status.spentSoFar - status.lastMonthSameDaySpent
        let top = totals.first { !["房租", "店租", "住房", "住房房租"].contains($0.name) } ?? totals[0]
        let topBefore = previous[top.name] ?? .zero
        let diff = top.amount - topBefore
        return VStack(spacing: 14) {
            CategoryDonut(slices: CategoryDonut.slices(totals), centerLabel: "\(month.month) 月花掉", total: now.expense.magnitude, size: 250)
            if status.lastMonthSameDaySpent.cents > 0 {
                Text(delta.isExpense ? "比上月同期少花 \(delta.magnitude.rounded)" : "比上月同期多花 \(delta.rounded)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(delta.isExpense ? Color.income : Color.fg2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(delta.isExpense ? Color.incomeSoft : Color.sunken, in: Capsule())
            }
            (Text(top.name == totals[0].name ? "" : "房租之外，") + em(top.name) + Text("是最大的一块")
             + Text(topBefore.cents > 0 ? "，比 \(month.previous.month) 月\(diff.isExpense ? "少" : "多") \(diff.magnitude.rounded)。" : "。"))
                .font(.body).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .kitCard(padding: 24)
    }

    private func rankingCard(totals: [(name: String, amount: Money)], previous: [String: Money], total: Money) -> some View {
        let all = totals.map { CategorySlice(name: $0.name, amount: $0.amount) }
        let rows = byChange
            ? all.sorted { abs(($0.amount - (previous[$0.name] ?? .zero)).cents) > abs(($1.amount - (previous[$1.name] ?? .zero)).cents) }
            : all
        let maxAmount = Double(totals.first?.amount.cents ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "分类排行") {
                Picker("排序", selection: $byChange) {
                    Text("按金额").tag(false)
                    Text("按变化").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            ForEach(Array(rows.prefix(10))) { c in
                SectionLink(section: .transactions, filter: TransactionFilter(category: c.name)) {
                    HStack(spacing: 10) {
                        CategoryIcon(category: c.name, size: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(c.name).font(.callout)
                                Spacer()
                                if byChange {
                                    let d = c.amount - (previous[c.name] ?? .zero)
                                    Text(d.isExpense ? "少 \(d.magnitude.rounded)" : "多 \(d.rounded)").font(.caption)
                                        .foregroundStyle(d.isExpense ? Color.income : Color.fg2)
                                } else {
                                    Text("\(Int((Double(c.amount.cents) / Double(max(total.cents, 1)) * 100).rounded()))%")
                                        .font(.caption).foregroundStyle(Color.fg2).monospacedDigit()
                                }
                            }
                            Bar(fraction: Double(c.amount.cents) / maxAmount, color: CategoryStyle.color(c.name), height: 5)
                        }
                        Text(c.amount.formatted).font(.kitAmount).frame(minWidth: 86, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .hoverHighlight()
                .accessibilityLabel("\(c.name) \(c.amount.spoken)")
                .accessibilityHint("看这个分类的流水")
            }
        }
        .kitCard()
    }

    private func merchantsCard(month: YearMonth) -> some View {
        let list = model.topMerchants(month)
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader("花得最多的商户").padding(.bottom, 6)
            ForEach(list) { m in
                HStack(spacing: 12) {
                    Monogram(text: m.name, color: Color.fg3.opacity(0.6), size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text("\(m.category ?? "未分类") · \(m.count) 笔").font(.caption).foregroundStyle(Color.fg2)
                    }
                    Spacer()
                    Text(m.amount.formatted).font(.kitAmount)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                if m.id != list.last?.id { Divider().padding(.leading, 42) }
            }
        }
        .kitCard()
    }
}
