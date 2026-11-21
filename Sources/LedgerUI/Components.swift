import FinanceCore
import SwiftUI

/// SwiftUI 也有 Transaction（动画事务），在 LedgerUI 里 Transaction 一律指流水。
typealias Transaction = FinanceCore.Transaction

/// logo 的珊瑚色，只用在重点处。
public extension Color {
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.29)
    static let income = Color(red: 0.12, green: 0.54, blue: 0.36)
}

extension Color {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

/// 金额：等宽数字，收入绿色，支出正常色。
struct AmountText: View {
    let money: Money
    var signed = true
    var font: Font = .body

    var body: some View {
        Text(signed ? money.formatted : money.magnitude.formatted)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(money.isIncome && signed ? Color.income : Color.primary)
            .contentTransition(.numericText(value: Double(money.cents)))
            .accessibilityLabel(money.formatted)
    }
}

/// 大数字（总览顶部）：圆体。
struct BigAmount: View {
    let money: Money
    var size: CGFloat = 38
    var body: some View {
        Text(money.formatted)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(money.cents)))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

/// 卡片：总览、报表里一块一块的内容。
struct Card<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// 卡片标题行：左边标题，右边一个小动作。
struct CardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            trailing().font(.subheadline)
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// 账本切换：全部 / 个人 / Miora 美甲店。
struct BookPicker: View {
    @Environment(LedgerModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Picker("账本", selection: $model.selectedBookID.animation(.snappy)) {
            Text("全部").tag(String?.none)
            ForEach(model.ledger.books) { b in Text(b.name).tag(Optional(b.id)) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
        .accessibilityLabel("看哪个账本")
    }
}

/// 上个月 / 下个月。
struct MonthStepper: View {
    @Binding var month: YearMonth
    var latest: YearMonth = LocalDate.today.yearMonth

    var body: some View {
        HStack(spacing: 6) {
            Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("上个月")
            Text(month.label).font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 110)
            Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("下个月")
                .disabled(month >= latest)
        }
        .buttonStyle(.borderless)
    }
}

/// 自动换行的一排小按钮（分类）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 分类的图标和常用分类表。
enum CategoryStyle {
    static let symbols: [String: String] = [
        "餐饮": "fork.knife", "超市": "cart", "交通": "tram", "房租": "house", "店租": "storefront",
        "水电": "bolt", "耗材": "paintbrush", "设备": "wrench.and.screwdriver", "员工工资": "person.crop.rectangle",
        "工资": "briefcase", "收入": "arrow.down.circle", "营业收入": "sparkles", "其他": "tag",
        "购物": "bag", "娱乐": "gamecontroller", "医疗": "cross.case", "通讯": "phone", "旅行": "airplane",
        "衣服": "tshirt", "宝宝": "figure.and.child.holdinghands", "礼物": "gift", "咖啡": "cup.and.saucer",
        "加油": "fuelpump", "宠物": "pawprint", "学习": "book", "美容": "scissors", "税费": "building.columns",
        "社保": "shield", "营销": "megaphone", "手续费": "percent", "保险": "umbrella", "退款": "arrow.uturn.backward.circle",
        "老板提款": "arrow.left.arrow.right", "转入": "arrow.left.arrow.right", "转出": "arrow.left.arrow.right",
        "充值": "arrow.down.to.line", "订阅": "repeat", "未分类": "questionmark.circle",
    ]

    static func symbol(_ category: String?) -> String? { category.flatMap { symbols[$0] } }

    static func defaults(bookID: String?, income: Bool) -> [String] {
        let shop = bookID == "miora"
        if income { return shop ? ["营业收入", "退款", "其他"] : ["工资", "收入", "退款", "礼物", "其他"] }  // 「退款」选了会冲减支出
        return shop ? ["耗材", "店租", "员工工资", "水电", "设备", "税费", "社保", "营销", "手续费", "其他"]
            : ["餐饮", "超市", "交通", "房租", "水电", "购物", "娱乐", "医疗", "通讯", "旅行", "宝宝", "其他"]
    }
}

/// 一排分类小按钮，点一个就选中。
struct CategoryChips: View {
    let categories: [String]
    @Binding var selection: String
    var onPick: ((String) -> Void)? = nil

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(categories, id: \.self) { c in
                let on = selection == c
                Button {
                    selection = c
                    onPick?(c)
                } label: {
                    HStack(spacing: 4) {
                        if let s = CategoryStyle.symbol(c) { Image(systemName: s).font(.caption) }
                        Text(c)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? AnyShapeStyle(Color.coral) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.15), value: selection)
    }
}

extension AccountKind {
    var symbol: String {
        switch self {
        case .bank: "building.columns"
        case .credit: "creditcard"
        case .cash: "banknote"
        case .wallet: "wallet.bifold"
        case .savings: "dollarsign.bank.building"
        }
    }
    var label: String {
        switch self {
        case .bank: "银行卡"
        case .credit: "信用卡"
        case .cash: "现金"
        case .wallet: "电子钱包"
        case .savings: "储蓄"
        }
    }
}

extension LocalDate {
    /// 「11 月 20 日」
    var short: String { "\(month) 月 \(day) 日" }
    /// 今年的不写年份，往年的写上。
    var friendly: String {
        let today = LocalDate.today
        if self == today { return "今天" }
        if self == LocalDate(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) { return "昨天" }
        return year == today.year ? short : "\(year) 年 \(short)"
    }
    var asDate: Date { Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date() }
    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1)
    }
    /// 离今天还有几天（负数 = 已经过了）。
    var daysFromToday: Int {
        Calendar.current.dateComponents([.day], from: LocalDate.today.asDate, to: asDate).day ?? 0
    }
}

extension YearMonth {
    var label: String { "\(year) 年 \(month) 月" }
    var shortLabel: String { "\(month)月" }
}

extension Money {
    /// 填进输入框的写法：12,50
    var inputText: String { magnitude.decimalString.replacingOccurrences(of: ".", with: ",") }
}

/// 出错提示：保存失败等。
struct ErrorBanner: ViewModifier {
    @Binding var error: String?
    func body(content: Content) -> some View {
        content.alert("没保存成功", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
}

extension View {
    func errorAlert(_ error: Binding<String?>) -> some View { modifier(ErrorBanner(error: error)) }

    /// 只在 iOS 上用数字键盘。
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func sheetSize(width: CGFloat = 460, height: CGFloat = 540) -> some View {
        #if os(macOS)
        // 固定大小，而且不超过主窗口最小高度（620）能放下的范围：
        // 内容多就在面板里滚动，取消和保存按钮永远留在面板里，不会跑到窗口外面。
        frame(width: width, height: min(height, 540))
        #else
        self
        #endif
    }

    /// 页面内容：居中、限宽、滚动。
    func pageScroll(maxWidth: CGFloat = 900) -> some View {
        ScrollView {
            self.padding()
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
    }
}

/// 金额输入框：大号圆体，前面带正负号提示。
struct AmountField: View {
    let prompt: String
    @Binding var text: String
    var color: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField(prompt, text: $text)
                .decimalKeyboard()
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                #if os(macOS)
                .textFieldStyle(.plain)
                #endif
            Text("€").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
        .accessibilityLabel("金额")
    }
}

/// 底部冒出来的结果提示，带「撤销」。
struct ToastView: View {
    let toast: LedgerModel.Toast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color.coral : Color.income)
            Text(toast.text).font(.subheadline).lineLimit(2)
            if toast.changeID != nil {
                Button("撤销", action: undo).font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

/// 进度条：圆角，带颜色。
struct Bar: View {
    let fraction: Double
    var color: Color = .coral
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
