import Charts
import FinanceCore
import SwiftUI

// MARK: - 结论大数字

/// 每页最多一个：上面一行小字说「这是什么」，中间圆体大数字，下面一句人话说「好还是不好」。
struct KeyFigure<Extra: View>: View {
    let label: String
    let money: Money
    var color: Color = .primary
    let sentence: Text
    var spoken: String? = nil
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(Color.fg2)
            BigMoney(money: money, color: color)
                .animation(.easeOut(duration: 0.3), value: money)
            sentence.font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            extra()
        }
        .accessibilityElement(children: .combine)
        .modifier(OptionalLabel(label: spoken))
    }
}

struct OptionalLabel: ViewModifier {
    let label: String?
    func body(content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }
}

extension KeyFigure where Extra == EmptyView {
    init(label: String, money: Money, color: Color = .primary, sentence: Text, spoken: String? = nil) {
        self.init(label: label, money: money, color: color, sentence: sentence, spoken: spoken) { EmptyView() }
    }
}

/// 一句话里的重点：加粗；good = 绿，bad = 红。
func em(_ s: String, _ tone: Tone = .plain) -> Text {
    let t = Text(s).fontWeight(.semibold)
    switch tone {
    case .plain: return t
    case .good: return t.foregroundColor(.income)
    case .bad: return t.foregroundColor(.alert)
    }
}
enum Tone { case plain, good, bad }

/// 进账 / 花掉两个小数字。
struct InOutPair: View {
    let income: Money
    let expense: Money
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 2) {
                Text(income.display).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Color.income)
                    .monospacedDigit().contentTransition(.numericText(value: Double(income.cents)))
                Text("进账").font(.caption).foregroundStyle(Color.fg2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.display).font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit().contentTransition(.numericText(value: Double(expense.cents)))
                Text("花掉").font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("进账 \(income.spoken)，花掉 \(expense.magnitude.spoken)")
    }
}

// MARK: - 分区标题

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.kitSection).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing().font(.subheadline)
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// 右上角的「全部 ›」小链接：去另一页。
struct MoreLink: View {
    let title: String
    let section: AppSection
    var body: some View {
        SectionLink(section: section) {
            HStack(spacing: 2) { Text(title); Image(systemName: "chevron.right").font(.caption2.weight(.semibold)) }
                .font(.subheadline).foregroundStyle(Color.brand)
        }
    }
}

// MARK: - 图标

/// 分类图标：彩色小方块里一个 SF Symbol。
struct CategoryIcon: View {
    let category: String?
    var isMove = false
    var size: CGFloat = 32

    var body: some View {
        let color = isMove ? Color.kit(0x0A64D6, 0x5AA0FF) : CategoryStyle.color(category)
        Image(systemName: isMove ? "arrow.left.arrow.right" : (CategoryStyle.symbol(category) ?? "tag"))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 字母头像：账本、商户、改动记录里的作者。
struct Monogram: View {
    let text: String
    var color: Color = .fg2
    var size: CGFloat = 30
    var circle = false
    /// true = 整个 text 照写（「Cx」「你」），否则只取第一个字。
    var raw = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: circle ? size / 2 : size * 0.28, style: .continuous)
        Text(raw ? text : String(text.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: shape)
            .accessibilityHidden(true)
    }

    /// 作者头像：Claude 橙、Codex 黑、自己灰。
    static func author(_ name: String, isMe: Bool, size: CGFloat = 30) -> Monogram {
        let lower = name.lowercased()
        let color: Color = isMe ? .fg3 : lower.contains("claude") ? Color.kit(0xD97757, 0xD97757)
            : lower.contains("codex") ? Color.kit(0x1D1D1F, 0x3A3A3F) : .ai
        let label = isMe ? "你" : lower.contains("codex") ? "Cx" : name
        return Monogram(text: label, color: color, size: size, circle: true, raw: isMe || lower.contains("codex"))
    }
}

/// 账本的小方块颜色：第一个账本用品牌橙，其它按顺序。
extension LedgerModel {
    func bookColor(_ id: String?) -> Color {
        guard let id, let i = ledger.books.firstIndex(where: { $0.id == id }) else { return .fg3 }
        let palette: [Color] = [.brand, Color.kit(0xA23B72, 0xE07AB0), Color.kit(0x0A64D6, 0x5AA0FF), Color.kit(0x0E7C6B, 0x3CC9B3)]
        return palette[i % palette.count]
    }
}

// MARK: - 流水行

/// 一笔流水：图标、商户名、「AI / 你」小标签 + 分类 · 账本 · 账户、金额。
struct TxRow: View {
    @Environment(LedgerModel.self) var model
    let tx: Transaction
    var showDate = false

    var body: some View {
        let internalMove = tx.flow != nil
        HStack(spacing: 12) {
            CategoryIcon(category: tx.category, isMove: internalMove)
            VStack(alignment: .leading, spacing: 3) {
                Text(Merchant.display(tx.description)).font(.callout.weight(.medium)).lineLimit(1)
                HStack(spacing: 5) {
                    if let author = model.authors[tx.id] {
                        if model.isMe(author) { KitTag.me() } else { KitTag.ai() }
                    }
                    Text(detail).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            AmountText(money: tx.amount, neutral: internalMove)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if showDate { parts.append(tx.date.friendly) }
        switch tx.flow {
        case .internal: parts.append("自己账户间 · 不算收支")
        case .debt: parts.append("借款往来 · 不算收支")
        case .saving: parts.append("存钱 · 不算收支")
        case .opening: parts.append("期初余额")
        case nil:
            parts.append(tx.category ?? "未分类")
            if let b = tx.bookID { parts.append(model.bookName(b)) }
        }
        parts.append(model.accountName(tx.accountID))
        return parts.joined(separator: " · ")
    }
}

// MARK: - 账本卡

struct BookCard: View {
    @Environment(LedgerModel.self) var model
    let book: Book

    var body: some View {
        let months = Reports.months(endingAt: model.shownMonth, count: 6)
        let list = Reports.summaries(model.ledger.transactions, months: months, bookID: book.id, hiddenAccounts: model.hiddenAccounts)
        let now = list.last ?? Summaries.monthly(model.ledger.transactions, month: model.shownMonth, bookID: book.id)
        Button {
            withAnimation(.snappy) { model.selectedBookID = book.id }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Monogram(text: book.name, color: model.bookColor(book.id), size: 24)
                    Text(book.name).font(.kitSection).lineLimit(1)
                    Spacer(minLength: 12)
                    Sparkline(values: list.map { Double($0.net.cents) / 100 }, color: model.bookColor(book.id))
                        .frame(width: 110, height: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.net.isExpense ? "本月超支" : "本月剩下").font(.caption).foregroundStyle(Color.fg2)
                    Text(now.net.balance)
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(now.net.isExpense ? Color.alert : .primary)
                        .contentTransition(.numericText(value: Double(now.net.cents)))
                }
                HStack(spacing: 14) {
                    (Text("进账 ").foregroundColor(.fg2) + Text(now.income.formatted).fontWeight(.semibold))
                    (Text("花掉 ").foregroundColor(.fg2) + Text(now.expense.magnitude.formatted).fontWeight(.semibold))
                }
                .font(.caption).monospacedDigit()
                if now.betweenBooks.cents != 0 {
                    Text("另外\(Reports.betweenBooksLabel(now.betweenBooks, bookID: book.id, books: model.ledger.books)) \(now.betweenBooks.magnitude.formatted)，不算收支")
                        .font(.caption).foregroundStyle(Color.fg2)
                }
            }
            .kitCard()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(book.name)：本月\(now.net.isExpense ? "超支" : "剩下") \(now.net.magnitude.spoken)")
        .accessibilityHint("只看这个账本")
    }
}

/// 小折线：账本卡右上角。
struct Sparkline: View {
    let values: [Double]
    var color: Color = .brand

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("月", i), y: .value("剩", v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if let last = values.last {
                PointMark(x: .value("月", values.count - 1), y: .value("剩", last)).foregroundStyle(color).symbolSize(28)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

// MARK: - 进度

/// 大进度环：中间写百分比。
struct GoalRing: View {
    let fraction: Double
    var color: Color = Color.kit(0xF4607A, 0xFF7A90)
    var lineWidth: CGFloat = 16
    var caption = "已存"
    @State var shown = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        let f = min(max(fraction, 0), 1)
        ZStack {
            Circle().stroke(Color.sunken, lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown || reduceMotion ? f : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((f * 100).rounded()))%").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text(caption).font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .onAppear { withAnimation(.smooth(duration: 0.8)) { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption) \(Int((f * 100).rounded()))%")
    }
}

/// 分期：一格一期。
struct SegmentedProgress: View {
    let done: Int
    let total: Int
    var color: Color = .brand
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule().fill(i < done ? color : Color.sunken).frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(done) / \(total) 期")
    }
}

// MARK: - 空状态

/// 空的时候一律把人引去找 AI：一句说明 + 一个「复制这句话」按钮。
struct KitEmptyState: View {
    var symbol = "sparkles"
    let title: String
    let message: String
    var prompt: String? = nil
    var page = "总览"
    var buttonTitle = "复制这句话"

    var body: some View {
        AskAIReader { ask in
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 30, weight: .medium))
                    .foregroundStyle(symbol == "sparkles" ? Color.ai : Color.fg3)
                    .symbolRenderingMode(.hierarchical)
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                if let prompt {
                    Button { ask(prompt, page: page) } label: { Label(buttonTitle, systemImage: "doc.on.doc") }
                        .buttonStyle(AISolidButtonStyle())
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 28).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
    }
}
