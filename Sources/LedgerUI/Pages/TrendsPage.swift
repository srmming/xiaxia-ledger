import FinanceCore
import SwiftUI

/// 趋势：比以前好还是差？视觉重心是近 12 个月进账 / 花掉柱状图上面的「平均每月剩多少」。
struct TrendsPage: View {
    @Environment(LedgerModel.self) var model

    var body: some View {
        let months = Reports.months(endingAt: model.shownMonth, count: 12)
        let list = model.summaries(months).filter { $0.income.cents != 0 || $0.expense.cents != 0 }
        Group {
            if list.count < 2 {
                KitEmptyState(symbol: "chart.bar", title: "流水还不够看趋势",
                              message: "有两个月以上的流水，这里会画出每个月进账和花掉，看出比以前好还是差。",
                              prompt: "帮我把以前几个月的银行对账单也导进夏夏账本", page: "趋势")
                    .kitCard()
            } else {
                content(list)
            }
        }
        .kitPage()
    }

    private func content(_ list: [MonthlySummary]) -> some View {
        let total = list.reduce(Money.zero) { $0 + $1.net }
        let avg = Money(cents: total.cents / Int64(list.count))
        let positive = list.filter { !$0.net.isExpense }.count
        let losing = list.filter { $0.net.isExpense }
        let best = list.max { $0.net < $1.net }
        let worst = list.max { $0.expense.magnitude < $1.expense.magnitude }
        let year = model.shownMonth.year
        let thisYear = list.filter { $0.month.year == year }.reduce(Money.zero) { $0 + $1.net }
        let losingNames = losing.prefix(3).map { "\($0.month.month) 月" }.joined(separator: "和")
        let sentence = Text("\(list.count) 个月里有 ") + em("\(positive) 个月") + Text("是剩钱的。")
            + Text(losing.isEmpty ? "没有哪个月花得比挣得多。" : "花得比挣得多的是 \(losingNames)。")
        return VStack(alignment: .leading, spacing: Kit.gap) {
            VStack(alignment: .leading, spacing: 16) {
                KeyFigure(label: "近 \(list.count) 个月，平均每月\(avg.isExpense ? "超支" : "剩下")", money: avg.magnitude,
                          color: avg.isExpense ? .alert : .primary, sentence: sentence,
                          spoken: "近 \(list.count) 个月平均每月\(avg.isExpense ? "超支" : "剩下") \(avg.magnitude.spoken)")
                MonthBars(summaries: list)
            }
            .kitCard(padding: 20)

            XiaxiaSays(page: "trends", pageName: "趋势", sentence: xiaxia(list),
                       question: "最近 \(list.count) 个月我花钱的趋势怎么样？是在变好还是变差？")

            CardRow(items: [
                Stat(title: "剩得最多", value: best.map { "\($0.month.month) 月 · \($0.net.display.replacingOccurrences(of: ",00", with: ""))" } ?? "—"),
                Stat(title: "花得最多", value: worst.map { "\($0.month.month) 月 · \($0.expense.magnitude.rounded)" } ?? "—"),
                Stat(title: "\(year) 年一共\(thisYear.isExpense ? "超支" : "剩下")", value: thisYear.isExpense ? thisYear.magnitude.rounded : "+" + thisYear.rounded,
                     tone: thisYear.isExpense ? .bad : .good),
            ], minWidth: 200) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.title).font(.caption).foregroundStyle(Color.fg2)
                    Text(stat.value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                        .foregroundStyle(stat.tone == .good ? Color.income : stat.tone == .bad ? Color.alert : .primary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .kitCard()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension TrendsPage {
    /// 夏夏先说的一句：最近三个月和之前比，在变好还是变差。
    func xiaxia(_ list: [MonthlySummary]) -> String {
        let recent = list.suffix(3)
        let earlier = list.dropLast(3)
        let avg = { (xs: ArraySlice<MonthlySummary>) in Money(cents: xs.reduce(Int64(0)) { $0 + $1.net.cents } / Int64(max(xs.count, 1))) }
        let r = avg(recent)
        guard !earlier.isEmpty else {
            return r.isExpense ? model.voiced("最近平均每月超支 \(r.magnitude.rounded)。", .bad)
                : model.voiced("最近平均每月剩 \(r.rounded)。", .good)
        }
        let diff = r - avg(earlier)
        if diff.magnitude.cents < 5000 { return model.voiced("最近 3 个月和之前差不多，平均每月\(r.isExpense ? "超支" : "剩") \(r.magnitude.rounded)。", .neutral) }
        return diff.isExpense ? model.voiced("最近 3 个月平均每月比之前少剩 \(diff.magnitude.rounded)，在变差。", .bad)
            : model.voiced("最近 3 个月平均每月比之前多剩 \(diff.rounded)，在变好。", .good)
    }
}

struct Stat: Identifiable {
    var title: String
    var value: String
    var tone: Tone = .plain
    var id: String { title }
}

extension Tone: Equatable {}
