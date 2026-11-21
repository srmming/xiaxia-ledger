import FinanceCore
import SwiftUI

/// SwiftUI 也有 Transaction（动画事务），在 LedgerUI 里 Transaction 一律指流水。
typealias Transaction = FinanceCore.Transaction

extension Money {
    /// 界面上的写法：进账「+1.850,00 €」，花掉「−23,40 €」（真正的减号），不带符号就是「500,00 €」。
    var display: String {
        if cents > 0 { return "+" + formatted }
        if cents < 0 { return "\u{2212}" + magnitude.formatted }
        return formatted
    }
    /// 不带小数的写法：「1.150 €」，给一句话里用。
    var rounded: String {
        let euros = (magnitude.cents + 50) / 100
        let text = Money(cents: euros * 100).formatted.replacingOccurrences(of: ",00 €", with: " €")
        return (cents < 0 ? "\u{2212}" : "") + text
    }
    /// 余额：负数（信用卡欠款）带减号，正数不带。
    var balance: String { cents < 0 ? "\u{2212}" + magnitude.formatted : formatted }
}

/// 列表里的金额：进账绿色带 +，花掉正常颜色带 −，自己账户间转账灰色不带符号。
struct AmountText: View {
    let money: Money
    var neutral = false
    var font: Font = .kitAmount

    var body: some View {
        Text(neutral ? money.magnitude.formatted : money.display)
            .font(font)
            .foregroundStyle(neutral ? Color.fg3 : (money.isIncome ? Color.income : Color.primary))
            .contentTransition(.numericText(value: Double(money.cents)))
            .lineLimit(1)
            .accessibilityLabel(money.spoken)
    }
}

extension Money {
    /// VoiceOver 念法：「1433 欧元 65 分」。
    var spoken: String {
        let c = magnitude.cents
        let sign = cents < 0 ? "负 " : ""
        return c % 100 == 0 ? "\(sign)\(c / 100) 欧元" : "\(sign)\(c / 100) 欧元 \(c % 100) 分"
    }
}

/// 圆体大数字，小数和 € 小一号、灰一点：1.433,65 €。
struct BigMoney: View {
    let money: Money
    var size: CGFloat = 56
    var color: Color = .primary

    var body: some View {
        let text = money.balance
        let parts = text.replacingOccurrences(of: " €", with: "").split(separator: ",", maxSplits: 1)
        let whole = String(parts.first ?? "")
        let cents = parts.count > 1 ? "," + parts[1] : ""
        (Text(whole).foregroundColor(color)
         + Text(cents + " €").font(.system(size: size * 0.5, weight: .semibold, design: .rounded)).foregroundColor(.fg3))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .tracking(-0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: Double(money.cents)))
            .accessibilityLabel(money.spoken)
    }
}

extension View {
    /// Mac 上鼠标移到一行上时，底色轻轻亮一下，告诉你这行能点。iPhone 上什么都不做。
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

private struct HoverHighlight: ViewModifier {
    @State var hovering = false
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .padding(.horizontal, 6)
            .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, -6)
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        #else
        content
        #endif
    }
}

/// 上个月 / 下个月。
struct MonthStepper: View {
    @Binding var month: YearMonth
    var latest: YearMonth = LocalDate.today.yearMonth

    var body: some View {
        HStack(spacing: 0) {
            Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28).contentShape(Rectangle()) }
                .accessibilityLabel("上个月")
            Text(month.label).font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 110)
            Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28).contentShape(Rectangle()) }
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

    /// 名字完全一样的优先；不然看开头，比如「交通出行」用「交通」的图标、「超市日用」用「超市」的。
    static func symbol(_ category: String?) -> String? {
        guard let category else { return nil }
        if let s = symbols[category] { return s }
        return symbols.keys.filter { category.hasPrefix($0) }.max { $0.count < $1.count }.flatMap { symbols[$0] }
    }

    /// 分类颜色（设计稿那套）：图标底色、圆环、排行条。
    static let colors: [String: UInt32] = [
        "房租": 0xE8505B, "住房": 0xE8505B, "店租": 0xE8505B, "超市": 0x2E9E8F, "餐饮": 0xFF7A59, "美甲": 0xF472B6, "美容": 0xF472B6,
        "耗材": 0xF472B6, "交通": 0x3B82F6, "宝宝": 0xFB7185, "购物": 0xEC4899, "衣服": 0xEC4899, "服饰": 0xEC4899,
        "水电": 0xEAB308, "咖啡": 0xB7795A, "娱乐": 0xF97316, "工资": 0x16A34A, "收入": 0x16A34A, "营业收入": 0x16A34A,
        "旅行": 0x0EA5E9, "医疗": 0xEF4444, "通讯": 0x6366F1, "礼物": 0xD946EF, "税费": 0x64748B, "社保": 0x64748B,
        "员工工资": 0x8B5CF6, "设备": 0x0D9488, "订阅": 0x8B5CF6, "宠物": 0xA16207, "学习": 0x2563EB, "加油": 0xF59E0B,
    ]

    static func color(_ category: String?) -> Color {
        guard let category else { return .fg3 }
        let key = colors[category] != nil ? category : colors.keys.filter { category.hasPrefix($0) }.max { $0.count < $1.count }
        guard let key, let hex = colors[key] else {
            // 没定颜色的分类：按名字算一个固定的颜色，同一个分类每次都一样。
            let palette: [UInt32] = [0x0EA5E9, 0x8B5CF6, 0x14B8A6, 0xF59E0B, 0x6366F1, 0xA855F7]
            let h = category.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
            return Color.kit(palette[h % palette.count], palette[h % palette.count])
        }
        return Color.kit(hex, hex)
    }

    static func defaults(book: Book?, income: Bool) -> [String] {
        let shop = book?.isBusiness == true
        if income { return shop ? ["营业收入", "退款", "其他"] : ["工资", "收入", "退款", "礼物", "其他"] }  // 「退款」选了会冲减支出
        return shop ? ["耗材", "店租", "员工工资", "水电", "设备", "税费", "社保", "营销", "手续费", "其他"]
            : ["餐饮", "超市", "交通", "房租", "水电", "购物", "娱乐", "医疗", "通讯", "旅行", "宝宝", "其他"]
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

}

/// 底部冒出来的结果提示，带「撤销」。
struct ToastView: View {
    let toast: LedgerModel.Toast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color.alert : Color.income)
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
    var color: Color = .brand
    var height: CGFloat = 6
    @State var grown = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient)
                    .frame(width: max(height, geo.size.width * (grown || reduceMotion ? min(max(fraction, 0), 1) : 0)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        // 进度条从左边长出来；数字变了就滑到新位置。
        .animation(.easeOut(duration: 0.5), value: fraction)
        .onAppear {
            guard !grown else { return }
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) { grown = true }
        }
    }
}
