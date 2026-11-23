import Charts
import FinanceCore
import SwiftUI

/// 趋势：只回答一个问题——照现在这样花下去，月底和年底还剩多少钱？（ming 2026-11-23 改版）
/// 「剩多少」和家底页的大数字一个口径：能随便花的钱。
/// 一屏：最上面夏夏一句话；左边两个大数字（预计月底剩、预计年底剩）+ 一条线（实线是已经发生的，虚线是照这样花）；
/// 右边「想年底多剩一点」：最能省的几样开销，少花一半年底多剩多少；下面一句「怎么算的」。
struct TrendsPage: View {
    @Environment(LedgerModel.self) var model
    @State private var viewport = CGSize(width: 1000, height: 800)
    @State private var heroWidth: CGFloat = 560
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone 竖屏：一屏放下（ming 2026-11-23「页面一律一屏看完」）——图矮一点，「想年底多剩一点」收进主卡片，「怎么算的」不放。
    private var phone: Bool { sizeClass == .compact }
    private var short: Bool { Viewport.isShort(viewport) }

    var body: some View {
        Group {
            if let f = model.cashForecast() {
                content(f)
            } else {
                KitEmptyState(symbol: "chart.bar", title: tr("记满一个月就能算"),
                              message: tr("有一整个月的进出，这里就能算出照这样花下去，月底和年底还剩多少钱。"),
                              prompt: "帮我把上个月的银行对账单导进夏夏账本", page: "趋势")
                    .kitCard()
            }
        }
        .kitPage()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
    }

    private func content(_ f: CashForecast.Result) -> some View {
        let nudges = Nudges.forecast(f, currency: model.ledger.baseCurrency)
        let insights = [model.ledger.insight(forPage: "trends", month: model.shownMonth, bookID: nil)].compactMap { $0 }
        return VStack(alignment: .leading, spacing: Kit.gap) {
            XiaxiaCards(nudges: nudges, insights: insights, page: "趋势")
            Columns(sideWidth: 360) {
                heroCard(f)
            } side: {
                if !phone {
                    leversCard(f)
                    howCard(f)
                }
            }
        }
    }

    // MARK: 两个大数字 + 线

    private func heroCard(_ f: CashForecast.Result) -> some View {
        let year = f.isNextYear ? tr("明年年底") : tr("年底")
        let narrow = heroWidth < 470
        let size: CGFloat = narrow ? 34 : (short ? 40 : 48)
        let change = f.change
        let monthEndDate = LocalDate(year: f.today.year, month: f.today.month, day: f.today.yearMonth.dayCount)
        return VStack(alignment: .leading, spacing: short ? 10 : 14) {
            HStack(alignment: .top, spacing: narrow ? 14 : 28) {
                figure(label: tr("预计月底剩"), money: f.monthEnd, size: size,
                       sentence: Text(tr("\(f.today.month) 月 \(monthEndDate.day) 日，现在 ")) + em(f.now.rounded),
                       spoken: tr("照这样花，预计 \(f.today.month) 月底能随便花的钱剩 \(f.monthEnd.spoken)，现在是 \(f.now.spoken)"))
                figure(label: tr("预计\(year)剩"), money: f.yearEnd, size: size,
                       sentence: change.magnitude.cents < 1000 ? Text(tr("和现在差不多"))
                           : Text(tr("比现在")) + em("\(change.isExpense ? tr("少") : tr("多")) \(change.magnitude.rounded)", change.isExpense ? .bad : .good),
                       spoken: tr("照这样花，预计\(year)剩 \(f.yearEnd.spoken)，比现在\(change.isExpense ? tr("少") : tr("多")) \(change.magnitude.spoken)"))
            }
            ForecastChart(f: f, height: phone ? 112 : (short ? 130 : (narrow ? 170 : 230)))
            legend(f)
            if phone && !f.levers.isEmpty { phoneLevers(f) }
        }
        .kitCard(padding: short || phone ? 16 : 20)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { heroWidth = $0 }
    }

    private func figure(label: String, money: Money, size: CGFloat, sentence: Text, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(Color.fg2)
            BigMoney(money: money, size: size, color: money.cents < 0 ? .alert : .primary)
            sentence.font(.callout).foregroundStyle(Color.fg2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func legend(_ f: CashForecast.Result) -> some View {
        HStack(spacing: 14) {
            ForecastChart.key(Color.brand, tr("已经发生"), dashed: false)
            ForecastChart.key(Color.brand, tr("照这样花"), dashed: true)
            if f.thriftyYearEnd != f.yearEnd {
                ForecastChart.key(Color.income, tr("每月少花 10%（\(f.isNextYear ? tr("明年年底") : tr("年底")) \(f.thriftyYearEnd.rounded)）"), dashed: true)
            }
        }
        .font(.caption).foregroundStyle(Color.fg2)
        .lineLimit(1).minimumScaleFactor(0.8)
        .accessibilityHidden(true)
    }

    // MARK: 想年底多剩一点

    private func leversCard(_ f: CashForecast.Result) -> some View {
        let year = f.isNextYear ? tr("明年年底") : tr("年底")
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(tr("想\(year)多剩一点"))
            if f.levers.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                    Text(tr("花的基本都是房租、还款这类固定开销，没什么能省的。")).font(.callout).foregroundStyle(Color.fg2)
                }
                .padding(.vertical, 4)
            } else {
                Text(tr("这几样花得最多。少花一半，\(year)能多剩：")).font(.caption).foregroundStyle(Color.fg2)
            }
            ForEach(f.levers.prefix(short ? 2 : 3)) { l in
                SectionLink(section: .transactions, filter: TransactionFilter(category: l.category)) {
                    HStack(spacing: 10) {
                        CategoryIcon(category: l.category, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.category).font(.callout.weight(.medium))
                            (Text(tr("每月约 \(l.monthly.rounded)")) + (l.rising ? Text(tr(" · 还在涨")).foregroundColor(.alert) : Text("")))
                                .font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("+\(l.halfSaves.rounded)").font(.kitAmount).foregroundStyle(Color.income)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .hoverHighlight()
                .accessibilityLabel(tr("\(l.category)每月约 \(l.monthly.spoken)\(l.rising ? tr("，还在涨") : "")。少花一半，\(year)能多剩 \(l.halfSaves.spoken)"))
                .accessibilityHint(tr("看这个分类的流水"))
            }
        }
        .kitCard()
    }

    /// iPhone：主卡片底下两行「少花一半能多剩」。
    private func phoneLevers(_ f: CashForecast.Result) -> some View {
        let year = f.isNextYear ? tr("明年年底") : tr("年底")
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(tr("想\(year)多剩一点：这几样少花一半")).font(.caption.weight(.semibold)).foregroundStyle(Color.fg2)
            ForEach(f.levers.prefix(2)) { l in
                SectionLink(section: .transactions, filter: TransactionFilter(category: l.category)) {
                    HStack(spacing: 8) {
                        CategoryIcon(category: l.category, size: 22)
                        Text(l.category).font(.callout.weight(.medium)).lineLimit(1)
                        Text(tr("每月约 \(l.monthly.rounded)\(l.rising ? tr(" · 还在涨") : "")")).font(.caption).foregroundStyle(l.rising ? Color.alert : Color.fg2).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("+\(l.halfSaves.rounded)").font(.callout.weight(.semibold)).foregroundStyle(Color.income)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(tr("\(l.category)每月约 \(l.monthly.spoken)\(l.rising ? tr("，还在涨") : "")。少花一半，\(year)能多剩 \(l.halfSaves.spoken)"))
                .accessibilityHint(tr("看这个分类的流水"))
            }
        }
    }

    // MARK: 怎么算的

    private func howCard(_ f: CashForecast.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: tr("怎么算的")) { MoreLink(title: tr("家底"), section: .wealth) }
            line("banknote", Text(tr("现在能随便花 ")) + em(f.now.rounded) + Text(tr("，和家底页的大数字一样")))
            line("calendar", Text(tr("最近 \(f.basisMonths) 个月平均每月进 ")) + em(f.monthlyIncome.rounded) + Text(tr("、花 ")) + em(f.monthlySpend.rounded))
            if !short {
                line("clock", Text(tr("这个月剩下的日子大概还要花 ")) + em(f.restSpend.rounded)
                     + (f.restIncome.cents > 0 ? Text(tr("，还会进 ")) + em(f.restIncome.rounded) : Text("")))
            }
        }
        .font(.callout)
        .kitCard()
    }

    private func line(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Color.fg3).frame(width: 18)
            text.foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 能随便花的钱：实线是已经发生的（前几个月底 + 今天），虚线是照这样花到年底，绿色细虚线是每月少花 10%。
struct ForecastChart: View {
    let f: CashForecast.Result
    var height: CGFloat = 230

    private struct Mark: Identifiable {
        var x: Int
        var y: Double
        var series: String
        var id: String { "\(series)-\(x)" }
    }

    var body: some View {
        let past = f.past.map { Mark(x: $0.date.dayNumber, y: Double($0.value.cents) / 100, series: tr("已经发生")) }
        let ahead = f.ahead.map { Mark(x: $0.date.dayNumber, y: Double($0.value.cents) / 100, series: tr("照这样花")) }
        let thrifty = f.thriftyYearEnd == f.yearEnd ? []
            : f.thrifty.map { Mark(x: $0.date.dayNumber, y: Double($0.value.cents) / 100, series: tr("少花一点")) }
        let ys = (past + ahead + thrifty).map(\.y)
        let lo = min(ys.min() ?? 0, 0), hi = max(ys.max() ?? 1, 1)
        let pad = max((hi - lo) * 0.15, 50)
        let today = f.today.dayNumber
        let first = past.first?.x ?? today, last = ahead.last?.x ?? today
        let ticks = Self.ticks(f)
        Chart {
            ForEach(past) { p in
                AreaMark(x: .value(tr("日"), p.x), yStart: .value(tr("底"), lo < 0 ? lo - pad : 0), yEnd: .value(tr("剩"), p.y))
                    .foregroundStyle(LinearGradient(colors: [Color.brand.opacity(0.20), Color.brand.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            }
            if lo < 0 {
                RuleMark(y: .value(tr("零"), 0))
                    .foregroundStyle(Color.alert.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            RuleMark(x: .value(tr("今天"), today)).foregroundStyle(Color.fg3.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(thrifty) { p in
                LineMark(x: .value(tr("日"), p.x), y: .value(tr("剩"), p.y), series: .value(tr("线"), p.series))
                    .foregroundStyle(Color.income.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [2, 3]))
            }
            ForEach(ahead) { p in
                LineMark(x: .value(tr("日"), p.x), y: .value(tr("剩"), p.y), series: .value(tr("线"), p.series))
                    .foregroundStyle(Color.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [6, 4]))
            }
            ForEach(past) { p in
                LineMark(x: .value(tr("日"), p.x), y: .value(tr("剩"), p.y), series: .value(tr("线"), p.series))
                    .foregroundStyle(Color.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
            PointMark(x: .value(tr("日"), today), y: .value(tr("剩"), Double(f.now.cents) / 100))
                .foregroundStyle(Color.brand).symbolSize(55)
                .annotation(position: .topLeading, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    tag(tr("现在 \(f.now.rounded)"), color: .primary)
                }
            if let end = ahead.last, end.x != today {
                PointMark(x: .value(tr("日"), end.x), y: .value(tr("剩"), end.y))
                    .foregroundStyle(f.yearEnd.cents < 0 ? Color.alert : Color.brand).symbolSize(55)
                    .annotation(position: .topTrailing, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        tag("\(f.isNextYear ? tr("明年年底") : tr("年底")) \(f.yearEnd.rounded)", color: f.yearEnd.cents < 0 ? .alert : .primary)
                    }
            }
        }
        .chartXScale(domain: first...max(last, first + 1), range: .plotDimension(startPadding: 6, endPadding: 12))
        .chartYScale(domain: (lo < 0 ? lo - pad : 0)...(hi + pad))
        .chartXAxis {
            AxisMarks(values: ticks.map { $0.x }) { v in
                AxisValueLabel(collisionResolution: .disabled) {
                    if let x = v.as(Int.self), let t = ticks.first(where: { $0.x == x }) { Text(t.label).fixedSize() }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: height < 150 ? 2 : 4)) { v in
                AxisGridLine().foregroundStyle(Color.fg3.opacity(0.18))
                AxisValueLabel { if let d = v.as(Double.self) { Text(Money(cents: Int64(d * 100)).rounded.replacingOccurrences(of: " €", with: "")) } }
            }
        }
        .frame(height: height)
        .revealFromLeading()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("能随便花的钱：现在 \(f.now.spoken)，照这样花\(f.isNextYear ? tr("明年年底") : tr("年底")) \(f.yearEnd.spoken)")
                            + (f.thriftyYearEnd != f.yearEnd ? tr("；每月少花 10% 的话是 \(f.thriftyYearEnd.spoken)") : "") + tr("。"))
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .fixedSize()
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Color.cardBackground.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
    }

    /// 横轴：每个月底标「11月」，今天标「今天」；离今天太近的月底不标（会叠在一起）；月份多时隔一个标一个，最后一个一定标。
    struct Tick { var x: Int; var label: String }
    static func ticks(_ f: CashForecast.Result) -> [Tick] {
        let today = f.today.dayNumber
        let ends = (f.past + f.ahead).map(\.date).filter { $0 != f.today && abs($0.dayNumber - today) > 12 }
        var list = Array(Set(ends)).sorted()
        if list.count > 8 {
            let lastOne = list.last, parity = (list.count - 1) % 2
            list = list.enumerated().filter { $0.offset % 2 == parity }.map(\.element)
            if let lastOne, list.last != lastOne { list.append(lastOne) }
        }
        return (list.map { Tick(x: $0.dayNumber, label: tr("\($0.month)月")) } + [Tick(x: today, label: tr("今天"))]).sorted { $0.x < $1.x }
    }

    /// 图例里的一小段线。
    static func key(_ color: Color, _ text: String, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 16, y: 4)) }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [4, 3] : []))
                .frame(width: 16, height: 8)
            Text(text)
        }
    }
}

extension Tone: Equatable {}
