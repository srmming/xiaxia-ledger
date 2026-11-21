import FinanceCore
import SwiftUI

/// 总览：这个月我过得怎么样？视觉重心是「本月还剩多少」+ 一句结论 + 花钱速度线。
struct OverviewPage: View {
    @Environment(LedgerModel.self) var model

    var body: some View {
        if model.ledger.transactions.isEmpty {
            VStack(spacing: Kit.gap) {
                KitEmptyState(title: "账本还是空的",
                              message: "把银行对账单拖进 Claude，说一句「帮我导入夏夏账本」。哪家银行、什么格式都行，导好就会出现在这里。",
                              prompt: "这是我的银行对账单，帮我整理好导进夏夏账本", page: "总览")
                    .kitCard()
                AskAICard(page: "总览", prompts: model.prompts(for: .overview))
            }
            .kitPage()
        } else {
            content.kitPage()
        }
    }

    private var content: some View {
        let status = model.status(model.shownMonth)
        return VStack(alignment: .leading, spacing: Kit.gap) {
            Columns {
                heroCard(status)
                if model.selectedBookID == nil, model.ledger.books.count > 1 {
                    CardRow(items: model.ledger.books, minWidth: 230) { BookCard(book: $0) }
                }
            } side: {
                if let lead = model.leadInsight { InsightCard(insight: lead) }
                AskAICard(page: "总览", prompts: Array(model.prompts(for: .overview).prefix(3)))
                recentCard
            }
        }
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
                SpendingPaceChart(status: s)
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
        let recent = Array(model.visibleTransactions.prefix(5))
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
}
