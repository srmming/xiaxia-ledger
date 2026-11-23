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
                Text(tr("进账")).font(.caption).foregroundStyle(Color.fg2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.display).font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit().contentTransition(.numericText(value: Double(expense.cents)))
                Text(tr("花掉")).font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("进账 \(income.spoken)，花掉 \(expense.magnitude.spoken)"))
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
    @Environment(LedgerModel.self) var model
    let title: String
    let section: AppSection
    var body: some View {
        SectionLink(section: section) {
            HStack(spacing: 2) { Text(model.xia(title)); Image(systemName: "chevron.right").font(.caption2.weight(.semibold)) }
                .font(.subheadline).foregroundStyle(Color.brand)
        }
    }
}

// MARK: - 图标

/// 分类图标：浅浅一层分类色的圆角方块，中间是夏夏自己画的分类图标（design/icon-kit）。
struct CategoryIcon: View {
    let category: String?
    var isMove = false
    /// 不算收支的那几种流水各用自己的图标：期初余额、借还款、存进目标、自己账户互转。
    var flow: Transaction.Flow? = nil
    var size: CGFloat = 32

    var body: some View {
        XiaTile(glyph: glyph, size: size)
    }

    private var glyph: XiaGlyph {
        switch flow {
        case .opening: .bank
        case .debt: .loan
        case .saving: .savings
        case .internal: .transfer
        case nil: isMove ? .transfer : CategoryStyle.glyph(category)
        }
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
        Text(raw ? text : Self.initial(text))
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: shape)
            .accessibilityHidden(true)
    }

    /// 第一个字：跳过开头的数字和符号（「12 | Ana López」取 A），全是数字符号就取第一个。
    static func initial(_ text: String) -> String {
        let c = text.first { $0.isLetter } ?? text.first
        return c.map { String($0).uppercased() } ?? ""
    }

    /// 作者头像：Claude 橙、Codex 黑、自己灰。
    static func author(_ name: String, isMe: Bool, size: CGFloat = 30) -> Monogram {
        let lower = name.lowercased()
        let color: Color = isMe ? .fg3 : lower.contains("claude") ? Color.kit(0xD97757, 0xD97757)
            : lower.contains("codex") ? Color.kit(0x1D1D1F, 0x3A3A3F) : .ai
        let label = isMe ? tr("你") : lower.contains("codex") ? "Cx" : name
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
            CategoryIcon(category: tx.category, isMove: internalMove, flow: tx.flow)
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
            AmountText(money: tx.amount, neutral: internalMove, currency: model.ledger.currency(ofAccount: tx.accountID))
        }
        .padding(.vertical, 7)
        .background {
            // 外面的 AI 刚记的那几笔：淡紫底，一眼看出来。
            if model.highlighted.contains(tx.id) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.aiSoft).padding(.horizontal, -6)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        #if os(macOS)
        .contextMenu {
            Button { model.askAbout(tx) } label: { Label(model.xia(tr("问夏夏这一笔")), systemImage: "sparkles") }
        }
        .accessibilityAction(named: "问夏夏这一笔") { model.askAbout(tx) }
        #endif
    }

    private var detail: String {
        var parts: [String] = []
        if showDate { parts.append(tx.date.friendly) }
        switch tx.flow {
        case .internal: parts.append(tr("自己账户间 · 不算收支"))
        case .debt: parts.append(tr("借款往来 · 不算收支"))
        case .saving: parts.append(tr("存钱 · 不算收支"))
        case .opening: parts.append(tr("期初余额"))
        case nil:
            parts.append(tx.category ?? tr("未分类"))
            if let b = tx.bookID { parts.append(model.bookName(b)) }
        }
        parts.append(model.accountName(tx.accountID))
        if let note = tx.note { parts.append(note) }
        if !tx.tagList.isEmpty { parts.append(tx.tagList.map { "#\($0)" }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 账本卡

struct BookCard: View {
    @Environment(LedgerModel.self) var model
    let book: Book

    var body: some View {
        let months = Reports.months(endingAt: model.shownMonth, count: 6)
        let list = Reports.summaries(model.baseTransactions, months: months, bookID: book.id, hiddenAccounts: model.hiddenAccounts)
        let now = list.last ?? Summaries.monthly(model.baseTransactions, month: model.shownMonth, bookID: book.id)
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
                    Text(now.net.isExpense ? tr("本月超支") : tr("本月剩下")).font(.caption).foregroundStyle(Color.fg2)
                    Text(now.net.balance)
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(now.net.isExpense ? Color.alert : .primary)
                        .contentTransition(.numericText(value: Double(now.net.cents)))
                }
                HStack(spacing: 14) {
                    (Text(tr("进账 ")).foregroundColor(.fg2) + Text(now.income.ui).fontWeight(.semibold))
                    (Text(tr("花掉 ")).foregroundColor(.fg2) + Text(now.expense.magnitude.ui).fontWeight(.semibold))
                }
                .font(.caption).monospacedDigit()
                if now.betweenBooks.cents != 0 {
                    Text(tr("另外\(Reports.betweenBooksLabel(now.betweenBooks, bookID: book.id, books: model.ledger.books)) \(now.betweenBooks.magnitude.ui)，不算收支"))
                        .font(.caption).foregroundStyle(Color.fg2)
                }
            }
            .kitCard()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(tr("\(book.name)：本月\(now.net.isExpense ? tr("超支") : tr("剩下")) \(now.net.magnitude.spoken)"))
        .accessibilityHint(tr("只看这个账本"))
    }
}

/// 小折线：账本卡右上角。
struct Sparkline: View {
    let values: [Double]
    var color: Color = .brand

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value(tr("月"), i), y: .value(tr("剩"), v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if let last = values.last {
                PointMark(x: .value(tr("月"), values.count - 1), y: .value(tr("剩"), last)).foregroundStyle(color).symbolSize(28)
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
    var caption = tr("已存")
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
        .accessibilityLabel(tr("第 \(done) / \(total) 期"))
    }
}

// MARK: - 空状态

/// 空的时候一律把人引去找 AI：一句说明 + 一个「复制这句话」按钮。
struct KitEmptyState: View {
    @Environment(LedgerModel.self) var model
    /// 旧写法：给一个 SF Symbol 名字，按它挑一张合适的夏夏插画（见 artFor）。
    var symbol: String? = nil
    /// 夏夏插画（160×120）：睡着的、在想事情的、出错的……不给就按 symbol 挑。
    var art: XiaGlyph? = nil
    let title: String
    let message: String
    var prompt: String? = nil
    var page = tr("总览")
    var buttonTitle = tr("复制好去问 AI")

    var body: some View {
        AskAIReader { ask in
            VStack(spacing: 10) {
                // 道具插画 + 站在旁边的夏夏（动作跟着这页的情况：空着在打盹、出错了担心、做完了庆祝…）
                let glyph = art ?? Self.artFor(symbol)
                HStack(alignment: .bottom, spacing: -18) {
                    MascotView(.xiaxia, pose: Self.poseFor(glyph), size: 96)
                    XiaxiaIllustration(glyph, width: 132)
                }
                .padding(.bottom, -2)
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                if let prompt {
                    Button { ask(prompt, page: page) } label: { Label(model.chatReady ? model.xia(tr("跟夏夏说")) : buttonTitle, systemImage: model.chatReady ? "sparkles" : "doc.on.doc") }
                        .buttonStyle(AISolidButtonStyle())
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 24).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
    }

    static func poseFor(_ art: XiaGlyph) -> MascotPose {
        switch art {
        case .illoError: .worried
        case .illoDone: .celebrate
        case .illoConnect: .hello
        case .illoSearch, .illoTrends, .illoLoading: .think
        case .illoPlans, .illoAccounts: .write
        default: .sleep
        }
    }

    static func artFor(_ symbol: String?) -> XiaGlyph {
        switch symbol {
        case "chart.bar", "chart.bar.fill", "chart.line.uptrend.xyaxis": .illoTrends
        case "chart.pie", "chart.pie.fill": .illoSpending
        case "building.columns", "creditcard", "banknote", "wallet.bifold": .illoAccounts
        case "target", "flag": .illoPlans
        case "calendar": .illoMonth
        case "magnifyingglass": .illoSearch
        case "link", "powerplug": .illoConnect
        case "exclamationmark.triangle", "exclamationmark.triangle.fill", "xmark.octagon": .illoError
        case "checkmark.circle", "checkmark.seal": .illoDone
        default: .illoLedger
        }
    }
}
