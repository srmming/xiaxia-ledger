import FinanceCore
import SwiftUI

/// 总览：这个月我过得怎么样？视觉重心是「本月还剩多少」+ 一句结论 + 花钱速度线。
struct OverviewPage: View {
    @Environment(LedgerModel.self) var model
    /// 窗口矮（比如最小的 1000×612）：速度图再收矮、最近流水少一条，尽量一屏放下。
    @State private var short = false

    var body: some View {
        if model.ledger.transactions.isEmpty {
            #if os(macOS)
            // 还没有一笔：照 ming 的稿（design/mockups/empty-overview-ming-2026-11-23.png）——「开始记账」+ 记第一笔 / 用 AI 导入旧账 + 一条问夏夏。
            StartLedgerView().kitPage()
            #else
            VStack(spacing: Kit.gap) {
                KitEmptyState(title: "账本还是空的",
                              message: "把银行对账单拖进 Claude，说一句「帮我导入夏夏账本」。哪家银行、什么格式都行，导好就会出现在这里。",
                              prompt: "这是我的银行对账单，帮我整理好导进夏夏账本", page: "总览")
                    .kitCard()
                AskAICard(page: "总览", prompts: model.prompts(for: .overview))
            }
            .kitPage()
            #endif
        } else {
            content.kitPage()
                .onGeometryChange(for: Bool.self) { $0.size.height < 700 } action: { short = $0 }
        }
    }

    private var content: some View {
        let status = model.status(model.shownMonth)
        // ming 2026-11-23：夏夏的点评放最上面、一整行拉过去；「跟 AI 说就行」那张卡不要了；尽量一屏看完不用往下滚。
        return VStack(alignment: .leading, spacing: Kit.gap) {
            // 一张卡说一件事，左右拖动看下一张（ming 2026-11-23）。看以前的月份、又没有 AI 点评时，照旧说一句。
            let nudges = model.overviewNudges(status)
            // 卡叠尽量有下一张（ming：「让用户知道下一页还有」）：总览点评在前，再接「夏夏建议」里这个月别的没看过的，最多 6 张。
            let book = model.selectedBookID
            let main = model.ledger.insight(forPage: "overview", month: model.shownMonth, bookID: book)
            let others = model.ledger.insights(month: model.shownMonth, bookID: book).filter { $0.id != main?.id }
            let insights = Array(([main].compactMap { $0 } + others).prefix(max(0, 6 - nudges.count)))
            if nudges.isEmpty && insights.isEmpty {
                XiaxiaSays(page: "overview", pageName: "总览", sentence: xiaxia(status),
                           question: "看看我 \(status.month.month) 月的账：花得怎么样、哪里要留意、月底大概剩多少？")
            } else {
                XiaxiaCards(nudges: nudges, insights: insights)
            }
            // 速度图收矮、最近流水 4 条：1280×800 一屏放得下（ming：「尽量不要上下拉」）。
            // 账本卡收成一行一个、放到右栏最近流水下面（右栏下面原来空着），左边只留结论和速度图。
            Columns {
                heroCard(status)
            } side: {
                recentCard
                // 窗口太矮就不放（上面账本切换也能看各个账本）。
                if !short, model.selectedBookID == nil, model.ledger.books.count > 1 { booksCard }
            }
        }
    }

    /// 夏夏先说的一句：月底大概剩多少（这个月），或者这个月剩了多少（以前的月）。
    private func xiaxia(_ s: MonthStatus) -> String {
        let m = s.month.month
        if s.summary.income.cents == 0 && s.summary.expense.cents == 0 {
            return model.voiced("\(m) 月还没有流水，导进来我再帮你看。", .neutral)
        }
        if s.isCurrent, let end = s.projectedEnd {
            return end.isExpense ? model.voiced("照这样下去，\(m) 月底大概会超支 \(end.magnitude.rounded)。", .bad)
                : model.voiced("照这样下去，\(m) 月底大概能剩 \(end.rounded)。", .good)
        }
        return s.net.isExpense ? model.voiced("\(m) 月花得比挣得多，超支了 \(s.net.magnitude.rounded)。", .bad)
            : model.voiced("\(m) 月剩下了 \(s.net.rounded)。", .good)
    }

    // MARK: 结论大数字

    private func heroCard(_ s: MonthStatus) -> some View {
        let m = s.month.month
        let over = s.net.isExpense
        let label = s.isCurrent ? "\(m) 月\(over ? "超支" : "还剩") · 截至 \(s.dayOfMonth) 日" : "\(m) 月\(over ? "超支了" : "剩了")"
        return VStack(alignment: .leading, spacing: 14) {
            if s.summary.income.cents == 0 && s.summary.expense.cents == 0 {
                KitEmptyState(symbol: "calendar", title: "\(m) 月还没有流水",
                              message: "新的流水导进来后，这里会画出花钱速度。跟 AI 说一句就能导。",
                              prompt: "这是我 \(m) 月的银行对账单，帮我整理好导进夏夏账本", page: "总览")
            } else {
                KeyFigure(label: label, money: s.net.magnitude, color: over ? .alert : .primary,
                          sentence: sentence(s), spoken: spoken(s, label: label)) {
                    InOutPair(income: s.summary.income, expense: s.summary.expense).padding(.top, 4)
                }
                SpendingPaceChart(status: s, height: short ? 84 : 170)
            }
        }
        .kitCard(padding: 20)
    }

    private func sentence(_ s: MonthStatus) -> Text {
        let delta = s.deltaVsLastMonth
        let lastName = "\(s.month.previous.month) 月"
        var t: Text
        if delta.cents == 0 {
            t = Text("和\(s.isCurrent ? "上月同期" : lastName)剩得一样。")
        } else if delta.isIncome {
            t = Text("比\(s.isCurrent ? "上月同期" : lastName)多剩 ") + em(delta.rounded, .good) + Text("。")
        } else {
            t = Text("比\(s.isCurrent ? "上月同期" : lastName)少剩 ") + em(delta.magnitude.rounded, .bad) + Text("。")
        }
        if s.isCurrent {
            t = t + Text("花钱速度\(s.paceWord)")
            if let end = s.projectedEnd {
                t = t + Text(end.isExpense ? "，照这样月底约超支 " : "，照这样月底约剩 ") + em(end.magnitude.rounded, end.isExpense ? .bad : .plain) + Text("。")
            } else {
                t = t + Text("。")
            }
        }
        if s.summary.betweenBooks.cents != 0, let book = model.selectedBookID {
            t = t + Text("另外\(Reports.betweenBooksLabel(s.summary.betweenBooks, bookID: book, books: model.ledger.books)) \(s.summary.betweenBooks.magnitude.rounded)，不算收支。")
                .foregroundColor(.fg2)
        }
        return t
    }

    private func spoken(_ s: MonthStatus, label: String) -> String {
        let delta = s.deltaVsLastMonth
        return "\(label) \(s.net.magnitude.spoken)，比上月同期\(delta.isExpense ? "少" : "多") \(delta.magnitude.rounded)。"
    }

    // MARK: 最近流水

    private var recentCard: some View {
        // 开账余额、自己账户之间互转不算收支，不占「最近流水」的位置（流水页里都还在）。
        let recent = Array(model.visibleTransactions.filter { $0.flow != .opening && $0.flow != .`internal` }.prefix(short ? 3 : 4))
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "最近流水") {
                MoreLink(title: "全部", section: .transactions)
            }
            .padding(.bottom, 4)
            ForEach(recent) { t in
                TxRow(tx: t, showDate: true)
                if t.id != recent.last?.id { Divider().padding(.leading, 44) }
            }
        }
        .kitCard()
    }

    // MARK: 各个账本

    /// 每个账本一行：名字、近 6 个月小折线、本月剩下多少。点一下只看这个账本。
    private var booksCard: some View {
        let months = Reports.months(endingAt: model.shownMonth, count: 6)
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader("各个账本").padding(.bottom, 4)
            ForEach(model.ledger.books) { book in
                let list = Reports.summaries(model.baseTransactions, months: months, bookID: book.id, hiddenAccounts: model.hiddenAccounts)
                let now = list.last ?? Summaries.monthly(model.baseTransactions, month: model.shownMonth, bookID: book.id)
                Button {
                    withAnimation(.snappy) { model.selectedBookID = book.id }
                } label: {
                    HStack(spacing: 10) {
                        Monogram(text: book.name, color: model.bookColor(book.id), size: 24)
                        Text(book.name).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Sparkline(values: list.map { Double($0.net.cents) / 100 }, color: model.bookColor(book.id))
                            .frame(width: 60, height: 22)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(now.net.balance).font(.kitAmount).foregroundStyle(now.net.isExpense ? Color.alert : .primary)
                            Text(now.net.isExpense ? "本月超支" : "本月剩下").font(.caption2).foregroundStyle(Color.fg2)
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(book.name)：本月\(now.net.isExpense ? "超支" : "剩下") \(now.net.magnitude.spoken)")
                .accessibilityHint("只看这个账本")
                if book.id != model.ledger.books.last?.id { Divider().padding(.leading, 34) }
            }
        }
        .kitCard()
    }
}
