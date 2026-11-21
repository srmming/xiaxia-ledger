import Charts
import FinanceCore
import SwiftUI

/// 图表打开时从左往右画出来；系统开了「减弱动态效果」就直接显示。
private struct RevealFromLeading: ViewModifier {
    @State var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * (reduceMotion ? 1 : progress))
                }
            }
            .onAppear {
                guard progress == 0 else { return }
                withAnimation(.easeOut(duration: 0.7)) { progress = 1 }
            }
    }
}

extension View {
    func revealFromLeading() -> some View { modifier(RevealFromLeading()) }
}

private func euroAxis(_ v: Double) -> String { Money(cents: Int64(v * 100)).rounded.replacingOccurrences(of: " €", with: "") }

// MARK: - 花钱速度线

/// 实线是这个月累计花掉，虚线是上个月同一天，浅色虚线是照现在的速度到月底。
struct SpendingPaceChart: View {
    let status: MonthStatus
    var height: CGFloat = 210

    var body: some View {
        let days = status.month.dayCount
        let today = status.pace.last
        let lastSameDay = status.lastPace.first { $0.day == min(status.dayOfMonth, status.lastPace.count - 1) }
        let projection: [PacePoint] = {
            guard status.isCurrent, let t = today, t.day >= 3 else { return [] }
            let perDay = t.amount / Double(t.day)
            return [PacePoint(day: t.day, amount: t.amount, series: "预估"), PacePoint(day: days, amount: perDay * Double(days), series: "预估")]
        }()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                legend(Color.brand, "本月累计花掉", dashed: false)
                legend(Color.fg3, "上月同期", dashed: true)
                if !projection.isEmpty { legend(Color.brand.opacity(0.5), "照现在速度到月底", dashed: true) }
            }
            .font(.caption).foregroundStyle(Color.fg2)

            Chart {
                ForEach(status.lastPace) { p in
                    LineMark(x: .value("日", p.day), y: .value("花掉", p.amount), series: .value("线", "上月"))
                        .foregroundStyle(Color.fg3)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                ForEach(status.pace) { p in
                    AreaMark(x: .value("日", p.day), y: .value("花掉", p.amount))
                        .foregroundStyle(LinearGradient(colors: [Color.brand.opacity(0.22), Color.brand.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("日", p.day), y: .value("花掉", p.amount), series: .value("线", "本月"))
                        .foregroundStyle(Color.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                ForEach(projection) { p in
                    LineMark(x: .value("日", p.day), y: .value("花掉", p.amount), series: .value("线", "预估"))
                        .foregroundStyle(Color.brand.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                }
                if let t = today, t.day > 0 {
                    RuleMark(x: .value("今天", t.day)).foregroundStyle(Color.fg3.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("日", t.day), y: .value("花掉", t.amount))
                        .foregroundStyle(Color.brand).symbolSize(50)
                        .annotation(position: .topLeading, spacing: 4) {
                            Text("\(status.isCurrent ? "今天" : "月底") \(Money(cents: Int64(t.amount * 100)).rounded)")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.primary)
                        }
                    if let l = lastSameDay, status.isCurrent {
                        PointMark(x: .value("日", t.day), y: .value("花掉", l.amount))
                            .symbolSize(0)
                            .annotation(position: .bottomTrailing, spacing: 2) {
                                Text("上月这天 \(Money(cents: Int64(l.amount * 100)).rounded)").font(.caption2).foregroundStyle(Color.fg2)
                            }
                    }
                }
            }
            .chartXScale(domain: 1...days)
            .chartXAxis {
                AxisMarks(values: [1, 10, 20, days]) { v in
                    AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)日") } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(Color.fg3.opacity(0.18))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(euroAxis(d)) } }
                }
            }
            .frame(height: height)
            .revealFromLeading()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
        }
    }

    private var summary: String {
        let spent = status.spentSoFar.rounded
        let before = status.lastMonthSameDaySpent.rounded
        return "花钱速度：到今天花了 \(spent)，上月同一天花了 \(before)，速度\(status.paceWord)。"
    }

    private func legend(_ color: Color, _ title: String, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: dashed ? 8 : 12, height: 2.5)
            Text(title)
        }
    }
}

// MARK: - 分类圆环

struct CategorySlice: Identifiable {
    var name: String
    var amount: Money
    var id: String { name }
}

/// 只画前 6 类，其余合成「其它」。中间写总数。
struct CategoryDonut: View {
    let slices: [CategorySlice]
    let centerLabel: String
    let total: Money
    var size: CGFloat = 240
    @State var shown = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    static func slices(_ totals: [(name: String, amount: Money)]) -> [CategorySlice] {
        let top = totals.prefix(6).map { CategorySlice(name: $0.name, amount: $0.amount) }
        let rest = totals.dropFirst(6).reduce(Money.zero) { $0 + $1.amount }
        return rest.cents > 0 ? top + [CategorySlice(name: "其它", amount: rest)] : top
    }

    var body: some View {
        Chart(slices) { s in
            SectorMark(angle: .value("金额", shown || reduceMotion ? Double(s.amount.cents) : (s.id == slices.first?.id ? 1 : 0.0001)),
                       innerRadius: .ratio(0.7), angularInset: 1.2)
                .foregroundStyle(s.name == "其它" ? Color.fg3 : CategoryStyle.color(s.name))
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .frame(width: size, height: size)
        .overlay {
            VStack(spacing: 2) {
                Text(centerLabel).font(.caption).foregroundStyle(Color.fg2)
                Text(total.rounded).font(.system(size: size * 0.11, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(total.cents)))
            }
        }
        .onAppear { withAnimation(.smooth(duration: 0.7)) { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(centerLabel) \(total.spoken)。" + slices.prefix(3).map { "\($0.name) \($0.amount.rounded)" }.joined(separator: "，"))
    }
}

// MARK: - 12 个月进账 / 花掉

struct MonthBars: View {
    let summaries: [MonthlySummary]
    var height: CGFloat = 230

    private struct Bar: Identifiable {
        var month: YearMonth
        var kind: String
        var value: Double
        var id: String { "\(month)-\(kind)" }
    }

    var body: some View {
        let current = LocalDate.today.yearMonth
        let bars = summaries.flatMap { s in
            [Bar(month: s.month, kind: "进账", value: Double(s.income.cents) / 100),
             Bar(month: s.month, kind: "花掉", value: Double(s.expense.magnitude.cents) / 100)]
        }
        let top = bars.map(\.value).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                HStack(spacing: 5) { Capsule().fill(Color.income).frame(width: 10, height: 3); Text("进账") }
                HStack(spacing: 5) { Capsule().fill(Color.barExpense).frame(width: 10, height: 3); Text("花掉") }
                HStack(spacing: 5) { Circle().fill(Color.alert).frame(width: 5, height: 5); Text("花得比挣得多") }
            }
            .font(.caption).foregroundStyle(Color.fg2)
            Chart {
                ForEach(bars) { b in
                    BarMark(x: .value("月", b.month.shortLabel), y: .value("金额", b.value), width: .ratio(0.8))
                        .position(by: .value("类", b.kind))
                        .foregroundStyle(b.kind == "进账" ? Color.income : Color.barExpense)
                        .opacity(b.month == current ? 0.55 : 1)
                        .cornerRadius(3)
                }
                ForEach(summaries.filter { $0.net.isExpense }, id: \.month) { s in
                    PointMark(x: .value("月", s.month.shortLabel), y: .value("金额", top * 1.07))
                        .foregroundStyle(Color.alert).symbolSize(22)
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(Color.fg3.opacity(0.18))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(euroAxis(d)) } }
                }
            }
            .frame(height: height)
            .revealFromLeading()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("近 \(summaries.count) 个月进账和花掉的柱状图，其中 \(summaries.filter { $0.net.isExpense }.count) 个月花得比挣得多。")
        }
    }
}

// MARK: - 净资产曲线

struct NetWorthChart: View {
    let points: [NetWorthPoint]
    var height: CGFloat = 200

    var body: some View {
        let values = points.map { Double($0.value.cents) / 100 }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, 100)
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("月", p.month.shortLabel), yStart: .value("底", lo - pad), yEnd: .value("家底", Double(p.value.cents) / 100))
                    .foregroundStyle(LinearGradient(colors: [Color.income.opacity(0.22), Color.income.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("月", p.month.shortLabel), y: .value("家底", Double(p.value.cents) / 100))
                    .foregroundStyle(Color.income)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("月", last.month.shortLabel), y: .value("家底", Double(last.value.cents) / 100))
                    .foregroundStyle(Color.income).symbolSize(50)
                    .annotation(position: .topLeading, spacing: 4) {
                        Text(last.value.rounded).font(.caption2.weight(.semibold))
                    }
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Color.fg3.opacity(0.18))
                AxisValueLabel { if let d = v.as(Double.self) { Text(euroAxis(d)) } }
            }
        }
        .frame(height: height)
        .revealFromLeading()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("近 \(points.count) 个月家底曲线，从 \(points.first?.value.rounded ?? "") 到 \(points.last?.value.rounded ?? "")。")
    }
}
