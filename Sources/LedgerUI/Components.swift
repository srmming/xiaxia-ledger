import FinanceCore
import SwiftUI

/// SwiftUI 也有 Transaction（动画事务），在 LedgerUI 里 Transaction 一律指流水。
typealias Transaction = FinanceCore.Transaction

extension Money {
    /// 界面上用的金额：数字和 € 之间是不换行空格，「3.882,37 €」不会把 € 单独挤到下一行。
    /// 只在界面这层换；fin、MCP、复制给 AI 的文字仍用 formatted（普通空格），那边的测试和 AI 都按普通空格读。
    var ui: String { formatted.keepingAmountsTogether }
    func ui(in currency: String) -> String { formatted(in: currency).keepingAmountsTogether }

    /// 界面上的写法：进账「+1.850,00 €」，花掉「−23,40 €」（真正的减号），不带符号就是「500,00 €」。
    var display: String {
        if cents > 0 { return "+" + ui }
        if cents < 0 { return "\u{2212}" + magnitude.ui }
        return ui
    }
    /// 按某个币种的界面写法（外币账户的流水：「−20,00 US$」）。nil = 主币种。
    func display(in currency: String?) -> String {
        guard let currency, currency != Money.defaultCurrency else { return display }
        if cents > 0 { return "+" + ui(in: currency) }
        if cents < 0 { return "\u{2212}" + magnitude.ui(in: currency) }
        return ui(in: currency)
    }
    /// 不带小数的写法：「1.150 €」，给一句话里用。
    var rounded: String {
        let euros = (magnitude.cents + 50) / 100
        let text = Money(cents: euros * 100).ui.replacingOccurrences(of: ",00\u{00A0}", with: "\u{00A0}")
        return (cents < 0 ? "\u{2212}" : "") + text
    }
    /// 余额：负数（信用卡欠款）带减号，正数不带。
    var balance: String { cents < 0 ? "\u{2212}" + magnitude.ui : ui }
}

/// 列表里的金额：进账绿色带 +，花掉正常颜色带 −，自己账户间转账灰色不带符号。
struct AmountText: View {
    let money: Money
    var neutral = false
    var font: Font = .kitAmount
    /// 外币账户的流水按它自己的币种显示；nil = 主币种。
    var currency: String? = nil

    var body: some View {
        Text(neutral ? money.magnitude.ui(in: currency ?? Money.defaultCurrency) : money.display(in: currency))
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
        let sign = cents < 0 ? tr("负 ") : ""
        return c % 100 == 0 ? tr("\(sign)\(c / 100) 欧元") : tr("\(sign)\(c / 100) 欧元 \(c % 100) 分")
    }
}

/// 圆体大数字，小数和 € 小一号、灰一点：1.433,65 €。
struct BigMoney: View {
    let money: Money
    var size: CGFloat = 56
    var color: Color = .primary

    var body: some View {
        let text = money.balance
        // 金额格式里 € 前面是不换行空格（U+00A0），连空格一起去掉，不然会出现「,42 € €」。
        let parts = text.replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces)
            .split(separator: ",", maxSplits: 1)
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

/// 顶上的月份按钮：左右箭头一个月一个月切；点中间的月份弹出小面板，选年、点哪个月跳哪个月（ming 2026-11-23：「只能左右滑动有点问题」）。
/// 不在本月时旁边多一个「回到本月」。compact：iPhone 顶栏用，只有中间那个按钮。
struct MonthStepper: View {
    @Binding var month: YearMonth
    var latest: YearMonth = LocalDate.today.yearMonth
    /// 有记录的月份：面板里加小点。
    var recorded: Set<YearMonth> = []
    var compact = false
    @State private var picking = false

    var body: some View {
        HStack(spacing: 0) {
            if !compact {
                Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28).contentShape(Rectangle()) }
                    .accessibilityLabel(tr("上个月"))
            }
            Button { picking = true } label: {
                HStack(spacing: 3) {
                    Text(compact ? tr("\(month.month) 月") : month.label).font(.subheadline.weight(.semibold)).monospacedDigit()
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.fg3)
                }
                .frame(minWidth: compact ? nil : 110, minHeight: 28).contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(tr("\(month.label)，选月份"))
            .accessibilityIdentifier("month.pick")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                MonthPanel(month: $month, latest: latest, recorded: recorded) { picking = false }
                    .presentationCompactAdaptation(.popover)
            }
            if !compact {
                Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28).contentShape(Rectangle()) }
                    .accessibilityLabel(tr("下个月"))
                    .disabled(month >= latest)
                if month != latest {
                    Button { month = latest } label: { Text(tr("回到本月")).font(.caption.weight(.semibold)).padding(.horizontal, 6).frame(height: 28).contentShape(Rectangle()) }
                        .foregroundStyle(Color.brand)
                        .accessibilityIdentifier("month.today")
                }
            }
        }
        .buttonStyle(.borderless)
        // 截图用：-XiaxiaMonthPanel 1 一打开就弹出选月份的面板。
        .onAppear { if UserDefaults.standard.bool(forKey: "XiaxiaMonthPanel") { picking = true } }
    }
}

/// 选月份的小面板：上面切年份，下面 12 个月格子，有记录的月份带小点，最下面「回到本月」。还没到的月份点不了。
struct MonthPanel: View {
    @Binding var month: YearMonth
    let latest: YearMonth
    let recorded: Set<YearMonth>
    var done: () -> Void
    @State private var year = 0

    var body: some View {
        let y = year == 0 ? month.year : year
        let firstYear = min(recorded.map(\.year).min() ?? latest.year, month.year, latest.year)
        VStack(spacing: 12) {
            HStack {
                Button { year = y - 1 } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32).contentShape(Rectangle()) }
                    .disabled(y <= firstYear).accessibilityLabel(tr("上一年"))
                Spacer()
                Text(verbatim: tr("\(y) 年")).font(.headline).monospacedDigit()
                Spacer()
                Button { year = y + 1 } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32).contentShape(Rectangle()) }
                    .disabled(y >= latest.year).accessibilityLabel(tr("下一年"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(1...12, id: \.self) { m in
                    let ym = YearMonth(year: y, month: m)
                    let picked = ym == month
                    Button { month = ym; done() } label: {
                        VStack(spacing: 3) {
                            Text(tr("\(m) 月")).font(.callout.weight(picked ? .bold : .regular)).monospacedDigit()
                            Circle().fill(recorded.contains(ym) ? (picked ? Color.white : Color.brand) : Color.clear).frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(picked ? Color.white : ym > latest ? Color.fg3.opacity(0.5) : Color.primary)
                        .background(picked ? Color.brand : ym == latest ? Color.brandSoft : Color.sunken.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .disabled(ym > latest)
                    .accessibilityLabel(tr("\(y) 年 \(m) 月") + (recorded.contains(ym) ? tr("，有记录") : "") + (picked ? tr("，正在看") : ""))
                }
            }
            HStack {
                HStack(spacing: 4) { Circle().fill(Color.brand).frame(width: 4, height: 4); Text(tr("有记录")) }
                    .font(.caption).foregroundStyle(Color.fg2).accessibilityHidden(true)
                Spacer()
                Button { month = latest; done() } label: { Text(tr("回到本月")).font(.callout.weight(.semibold)) }
                    .foregroundStyle(Color.brand)
                    .disabled(month == latest)
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 268)
        .accessibilityIdentifier("month.panel")
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
    /// 常用叫法 → 图标（补在图标自己的中文名之外，比如「吃饭」「打车」）。
    private static let synonyms: [String: XiaGlyph] = [
        "餐饮": .dining, "吃饭": .dining, "超市": .grocery, "买菜": .grocery, "日用": .grocery,
        "交通": .transport, "打车": .taxi, "地铁": .metro, "公交": .metro, "房租": .housing, "住房": .housing, 
        "水电": .utilities, "购物": .shopping, "网购": .shopping, "娱乐": .entertainment, "游戏": .entertainment,
        "医疗": .medical, "药": .medical, "通讯": .phone, "话费": .phone, "旅行": .travel, "酒店": .travel,
        "宝宝": .baby, "孩子": .baby, "衣服": .clothing, "服饰": .clothing, "礼物": .gift, "红包": .gift,
        "咖啡": .coffee, "加油": .fuel, "宠物": .pets, "学习": .education, "教育": .education, "书": .education,
        "美容": .beauty, "护肤": .beauty, "美甲": .nails, "订阅": .subscription, "会员": .subscription,
        "保险": .insurance, "税费": .tax, "税": .tax, "社保": .social, "手续费": .fee, "利息": .fee,
        "退款": .refund, "工资": .salary, "奖金": .salary, "收入": .income, "营业收入": .revenue, "营业": .revenue,
        "店租": .shoprent, "耗材": .supplies, "进货": .supplies, "设备": .equipment, "员工工资": .staff,
        "营销": .marketing, "广告": .marketing, "充值": .topup, "转入": .transfer, "转出": .transfer, "转账": .transfer,
        "老板提款": .withdraw, "店收入": .revenue, "门店收入": .revenue, "储蓄": .savings, "存钱": .savings, "投资": .invest, "理财": .invest,
        "借款": .loan, "借出": .loan, "还款": .repay, "运动": .sport, "健身": .sport, "家居": .home, "家具": .home,
        "零食": .snacks, "甜品": .dessert, "奶茶": .bubbletea, "外卖": .delivery,
        "押金": .housing, "汇款": .remit, "转给": .remit, "亲友": .family, "取现": .cash, "现金": .cash, "软件": .software,
        "水电燃气": .utilities, "水电煤": .utilities, "期初余额": .bank, "期初": .bank, "花材": .plants, "鲜花": .plants, "原料": .supplies, "材料": .supplies, "推广": .marketing, "护理": .skincare, "燃气": .gas, "煤气": .gas, "电费": .power, "水费": .water, "网费": .internet, "宽带": .internet, "物业": .property,
        "机票": .flight, "火车": .train, "停车": .parking, "房贷": .mortgage, "理发": .haircut, "看牙": .dental, "数码": .digital, "电子": .digital, "未分类": .uncategorized, "其他": .other,
    ]

    /// 名字 → 图标：每个分类图标自己的中文名（138 个）加上面的常用叫法，叫法优先。
    static let glyphs: [String: XiaGlyph] = {
        var m: [String: XiaGlyph] = [:]
        for (name, label) in CategoryIcons.all { if m[label] == nil, let g = XiaGlyph(rawValue: name) { m[label] = g } }
        return m.merging(synonyms) { _, syn in syn }
    }()
    private static let generic: Set<String> = ["收入", "其他", "支出", "费用", "日用", "营业"]

    /// 名字里含着的最长那个；一样长取靠后的（中文的重点在后面：「美甲店收入」是收入，「住房水电」是水电）。
    private static func contained(in text: String) -> XiaGlyph? {
        var best: (len: Int, pos: Int, g: XiaGlyph)?
        for (key, g) in glyphs {
            guard let r = text.range(of: key, options: .backwards) else { continue }
            let pos = text.distance(from: text.startIndex, to: r.lowerBound)
            // 「收入」「其他」这种泛泛的词让给更具体的（「工资收入」是工资）。
            let len = key.count * 2 - (generic.contains(key) ? 1 : 0)
            if best == nil || len > best!.len || (len == best!.len && pos > best!.pos) { best = (len, pos, g) }
        }
        return best?.g
    }

    /// 用户自己给分类挑的图标（账本里存着，LedgerModel 读账本时更新）：分类名 → 图标名。
    nonisolated(unsafe) static var customIcons: [String: String] = [:] { didSet { matched.removeAll() } }
    /// 按名字找过的记一下（流水列表每行都要找，别每次都扫一遍）。
    nonisolated(unsafe) private static var matched: [String: XiaGlyph?] = [:]

    /// 分类名 → 图标。顺序：用户挑过的 → 名字完全一样 → 「大类·小类」这种从后半段往前找 →
    /// 名字里含着的最长那个（「住房·水电燃气」用水电，「转给亲友·汇款」用汇款）。都对不上用「其他」。
    static func glyph(_ category: String?) -> XiaGlyph {
        guard let category, !category.isEmpty else { return .uncategorized }
        return match(category) ?? .other
    }

    static func match(_ category: String) -> XiaGlyph? {
        if let picked = customIcons[category].flatMap(XiaGlyph.init(rawValue:)) { return picked }
        if let g = glyphs[category] { return g }
        if let hit = matched[category] { return hit }
        let g = guess(category)
        matched[category] = g
        return g
    }

    private static func guess(_ category: String) -> XiaGlyph? {
        let parts = category.split(whereSeparator: { "·・/|｜-—、 ".contains($0) }).map(String.init)
        var found: XiaGlyph?
        for part in parts.reversed() {
            if let g = glyphs[part] ?? contained(in: part) { found = g; break }
        }
        // 店里的房租、押金用店租，不用家里的房子；店里的收入（「美甲店·刷卡收入」）用营业收入。
        if category.contains("店") {
            if category.contains("收入") { return .revenue }
            if found == .housing { return .shoprent }
        }
        return found
    }

    /// 分类颜色：图标、圆环、排行条都用这一个（就是图标自带的颜色）。
    static func hex(_ category: String?) -> String? {
        guard let category, !category.isEmpty else { return nil }
        return match(category)?.tint
    }

    static func color(_ category: String?) -> Color {
        guard let category else { return .fg3 }
        guard let hex = hex(category).flatMap({ UInt32($0, radix: 16) }) else {
            // 没定图标的分类：按名字算一个固定的颜色，同一个分类每次都一样。
            let palette: [UInt32] = [0x24ABEB, 0x9C7CF4, 0x2FB7A4, 0xF7A21B, 0x7B7FF2, 0xC86EF0]
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
        case .bank: tr("银行卡")
        case .credit: tr("信用卡")
        case .cash: tr("现金")
        case .wallet: tr("电子钱包")
        case .savings: tr("储蓄")
        }
    }
}

extension LocalDate {
    /// 「11 月 20 日」
    var short: String { tr("\(month) 月 \(day) 日") }
    /// 今年的不写年份，往年的写上。
    var friendly: String {
        let today = LocalDate.today
        if self == today { return tr("今天") }
        if self == LocalDate(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) { return tr("昨天") }
        return year == today.year ? short : tr("\(year) 年 \(short)")
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
    var label: String { tr("\(year) 年 \(month) 月") }
    var shortLabel: String { tr("\(month)月") }
}

extension Money {
    /// 填进输入框的写法：12,50
    var inputText: String { magnitude.decimalString.replacingOccurrences(of: ".", with: ",") }
}

/// 出错提示：保存失败等。
struct ErrorBanner: ViewModifier {
    @Binding var error: String?
    func body(content: Content) -> some View {
        content.alert(tr("没保存成功"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(tr("好")) { error = nil }
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color.alert : Color.income)
            Text(toast.text).font(.subheadline).lineLimit(2)
            if toast.changeID != nil {
                Button(tr("撤销"), action: undo).font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
            }
            if let label = toast.actionLabel, let url = toast.actionURL {
                Button(label) {
                    openURL(url) { opened in
                        if !opened, let web = toast.fallbackURL { openURL(web) }
                    }
                }
                .font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
                .accessibilityIdentifier("toast.action")
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

/// 表单里的输入框：Mac 上左边写标题、框里写示例；iPhone 的表单不显示标题，就把两句合成一句放进框里。
struct FormField: View {
    let title: String
    let example: String
    @Binding var text: String
    init(_ title: String, _ example: String, text: Binding<String>) {
        self.title = title; self.example = example; self._text = text
    }
    var body: some View {
        #if os(macOS)
        TextField(title, text: $text, prompt: Text(example))
        #else
        TextField("\(title)，\(example)", text: $text)
        #endif
    }
}

/// 外面的 AI 刚改了账本：顶上弹一条「✦ Claude 刚记了 12 笔」，能「看看」、能「全部撤销」，不点就一直留着，点 ✕ 收起。
struct ActivityBanner: View {
    @Environment(LedgerModel.self) var model
    let activity: ExternalActivity

    var body: some View {
        HStack(spacing: 12) {
            // 哪个 AI 记的，就是哪个伙伴的头像（Claude → 小橘，Codex → 小紫…）
            MascotView(MascotCharacter.of(author: activity.authors.first ?? ""), size: 30, face: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.headline).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let last = activity.changes.last, activity.changes.count > 1 || !activity.transactionIDs.isEmpty {
                    Text(last.summary).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                }
            }
            if !activity.transactionIDs.isEmpty {
                Button(tr("看看")) { withAnimation(.snappy) { model.showActivity() } }
                    .font(.subheadline.weight(.semibold)).buttonStyle(.borderless).tint(Color.ai)
            }
            if !activity.undoableIDs.isEmpty {
                Button(tr("全部撤销")) { withAnimation(.snappy) { model.undoActivity() } }
                    .font(.subheadline).buttonStyle(.borderless)
            }
            Button { withAnimation(.snappy) { model.activity = nil } } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tr("知道了"))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.ai.opacity(0.35)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(activity.headline)
    }
}

extension String {
    /// 一段话里「数字 + 空格 + 币种」的空格换成不换行空格（AI 写的点评、对话里也有金额）。
    var keepingAmountsTogether: String {
        guard contains(" ") else { return self }
        return Self.amountSpace.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: "\u{00A0}")
    }
    private static let amountSpace = try! NSRegularExpression(pattern: "(?<=\\d) (?=(€|\\$|US\\$|£|¥|CHF|[A-Z]{3}\\b))")
}
