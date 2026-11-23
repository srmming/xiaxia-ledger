import FinanceCore
import SwiftUI

/// 趋势：只回答一个问题——我这几个月是越过越好，还是越过越差？（ming 2026-11-23 重做）
/// 一屏三样：每月存下多少（最核心）、家底曲线、悄悄变多的开销；最上面夏夏一句总结。
struct TrendsPage: View {
    @Environment(LedgerModel.self) var model
    @State private var viewport = CGSize(width: 1000, height: 800)
    /// 看近 6 个月还是 12 个月，记住上次选的。
    @AppStorage("xiaxia.trendsSpan") private var span = 6
    private var short: Bool { Viewport.isShort(viewport) }

    var body: some View {
        let months = Reports.months(endingAt: model.shownMonth, count: 12)
        let all = model.summaries(months).filter { $0.income.cents != 0 || $0.expense.cents != 0 }
        Group {
            if all.count < 2 {
                KitEmptyState(symbol: "chart.bar", title: "流水还不够看趋势",
                              message: "有两个月以上的流水，这里会画出每个月存下多少，看出是越过越好还是越差。",
                              prompt: "帮我把以前几个月的银行对账单也导进夏夏账本", page: "趋势")
                    .kitCard()
            } else {
                content(all)
            }
        }
        .kitPage()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
    }

    private func content(_ all: [MonthlySummary]) -> some View {
        let list = Array(all.suffix(span == 12 ? 12 : 6))
        // 平均、悄悄变多都只看过完的整月：正在过的这个月还没花完，不能比。
        let today = LocalDate.today.yearMonth
        let full = list.filter { $0.month < today }
        let basis = full.isEmpty ? list : full
        let avg = Trends.averageSaved(basis)
        let creeping = Trends.creeping(all.filter { $0.month < today })
        let nudges = Nudges.trends(months: basis, creeping: creeping, currency: model.ledger.baseCurrency)
        let insights = [model.ledger.insight(forPage: "trends", month: model.shownMonth, bookID: model.selectedBookID)].compactMap { $0 }
        let saved = basis.filter { !$0.net.isExpense }.count
        let sentence = Text("\(basis.count) 个月里 ") + em("\(saved) 个月", .good) + Text("存下了钱")
            + (basis.count - saved > 0 ? Text("，") + em("\(basis.count - saved) 个月", .bad) + Text("花得比挣得多。") : Text("。"))
        return VStack(alignment: .leading, spacing: Kit.gap) {
            XiaxiaCards(nudges: nudges, insights: insights, page: "趋势")
            Columns(sideWidth: 400) {
                VStack(alignment: .leading, spacing: short ? 10 : 14) {
                    SectionHeader(title: "每月存下多少") {
                        Picker("看几个月", selection: $span) {
                            Text("6 个月").tag(6)
                            Text("12 个月").tag(12)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .accessibilityIdentifier("trends.span")
                    }
                    KeyFigure(label: "\(full.isEmpty ? "近 \(basis.count) 个月" : "过完的 \(basis.count) 个月（不算还没过完的这个月）")，平均每月\(avg.isExpense ? "超支" : "存下")", money: avg.magnitude,
                              color: avg.isExpense ? .alert : .primary, sentence: sentence,
                              spoken: "近 \(basis.count) 个月平均每月\(avg.isExpense ? "超支" : "存下") \(avg.magnitude.spoken)")
                    SavedBars(summaries: list, average: avg, height: short ? 92 : 210)
                        .id(span)
                    if !short {
                    HStack(spacing: 14) {
                        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(Color.income).frame(width: 10, height: 10); Text("存下") }
                        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(Color.alert).frame(width: 10, height: 10); Text("花得比挣得多") }
                        if list.contains(where: { $0.month == today }) { Text("浅色是这个月，还没过完") }
                    }
                    .font(.caption).foregroundStyle(Color.fg2)
                    .accessibilityHidden(true)
                    }
                }
                .kitCard(padding: short ? 16 : 20)
            } side: {
                wealthCard
                creepCard(creeping)
            }
        }
    }

    /// 家底曲线：总资产减欠款，每月一个点，从第一笔记录的月份画起；不够两个月不画。
    private var wealthCard: some View {
        let first = model.recordedMonths.min() ?? model.shownMonth
        let months = Reports.months(endingAt: model.shownMonth, count: 12).filter { $0 >= first }
        let series = model.netWorthSeries(months: months)
        let now = series.last?.value ?? .zero
        let diff = series.count >= 2 ? now - series[0].value : nil
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "家底曲线") { MoreLink(title: "家底", section: .wealth) }
            if series.count >= 2, let diff {
                (Text("现在 ") + em(now.rounded) + Text("，比 \(series[0].month.month) 月底")
                 + em("\(diff.isExpense ? "少" : "多")了 \(diff.magnitude.rounded)", diff.isExpense ? .bad : .good) + Text("。"))
                    .font(.callout)
                NetWorthChart(points: series, height: short ? 64 : 120, labelEvery: series.count <= 6 ? 1 : 2)
            } else {
                Text("记满两个月，这里会画出家底（所有的钱减掉欠款）每个月的变化。")
                    .font(.callout).foregroundStyle(Color.fg2)
                    .frame(maxWidth: .infinity, minHeight: short ? 60 : 100, alignment: .leading)
            }
        }
        .kitCard()
    }

    /// 悄悄变多的开销：连续几个月在涨的分类，最多 3 条。
    private func creepCard(_ creeping: [Trends.Creep]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("悄悄变多的开销")
            if creeping.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                    Text("没有哪类开销连着几个月在涨。").font(.callout).foregroundStyle(Color.fg2)
                }
                .padding(.vertical, 4)
            }
            ForEach(creeping.prefix(short ? 2 : 3)) { c in
                SectionLink(section: .transactions, filter: TransactionFilter(category: c.category)) {
                    HStack(spacing: 10) {
                        CategoryIcon(category: c.category, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(c.category)连涨 \(c.months) 个月").font(.callout.weight(.medium))
                            Text("\(c.since.month) 月 \(c.before.rounded)，现在一个月 \(c.now.rounded)").font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("↑ \(c.extra.rounded)").font(.kitAmount).foregroundStyle(Color.alert)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .hoverHighlight()
                .accessibilityLabel("\(c.category)连涨 \(c.months) 个月，比 \(c.since.month) 月多 \(c.extra.spoken)")
                .accessibilityHint("看这个分类的流水")
            }
        }
        .kitCard()
    }
}

extension Tone: Equatable {}
