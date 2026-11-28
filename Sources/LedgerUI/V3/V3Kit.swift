#if os(macOS)
import AppKit
import FinanceCore
import SwiftUI

// 界面 v3 的公用零件（设计库 v2：晴空配色、贴纸卡、夏夏气泡、圆体数字）。只做浅色。
// 设计稿：design/mockups 里的「夏夏账本 Mac 界面 v3」，每个窗口 1280×800。

enum V3 {
    static func hex(_ h: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: a)
    }
    static let bg = hex(0xEEF3FF), card = Color.white, ink = hex(0x1F2550), ink2 = hex(0x6B7099), navy = hex(0x2E3A82)
    /// 金币金：每页最重要的那个数字。
    static let gold = hex(0xC98A1B), star = hex(0xF2B93B)
    static let soft = hex(0xDCE6FF), sky = hex(0x7FA3F0), line = hex(0xDDE4F6), side = hex(0xE3EAFD)
    static let red = hex(0xC4433A), green = hex(0x1E8A5A), teal = hex(0x1F8A9A)
    static let goodBG = hex(0xFDF1D2), warnBG = hex(0xFBE3E1), paper = hex(0xFFFBF0), debtBG = hex(0xFFF1EF)
    static let dash = hex(0xB9C4E8), tealSoft = hex(0xD8F0F2), greenSoft = hex(0xDDF3E7)

    /// 设计稿的窗口大小。窗口比它小就整体等比缩小，所以每页永远一屏看完。
    static let design = CGSize(width: 1280, height: 800)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight) }
    /// 圆体数字。
    static func num(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static let kai = "Kaiti SC"

    static func image(_ name: String) -> Image {
        for ext in ["png", "webp"] {
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "V3"), let img = NSImage(contentsOf: url) {
                return Image(nsImage: img)
            }
        }
        return Image(systemName: "face.smiling")
    }
}

extension Money {
    /// 「976」和「,61 €」分开，大数字用。
    var v3Parts: (whole: String, rest: String) {
        let text = magnitude.formatted.replacingOccurrences(of: " ", with: "\u{00A0}")
        guard let i = text.firstIndex(of: ",") else { return (text, "") }
        return ((cents < 0 ? "\u{2212}" : "") + String(text[..<i]), String(text[i...]))
    }
    /// 「1.496,61 €」
    var v3: String { (cents < 0 ? "\u{2212}" : "") + magnitude.formatted.replacingOccurrences(of: " ", with: "\u{00A0}") }
    /// 整数就不带小数：「181 €」「3,20 €」
    var v3Short: String {
        let t = v3
        return t.replacingOccurrences(of: ",00\u{00A0}", with: "\u{00A0}")
    }
    /// 带正负号：「+2.340,00 €」「−892,00 €」
    var v3Signed: String { (cents >= 0 ? "+" : "\u{2212}") + magnitude.v3 }
}

// MARK: - 卡片

/// 贴纸卡：深蓝粗描边 + 硬阴影。给每页最重要的东西用。
struct V3Sticker: ViewModifier {
    var fill: Color = V3.card
    var radius: CGFloat = 22
    var dashed = false
    var depth: CGFloat = 4
    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                shape.fill(V3.ink).offset(y: depth)
                shape.fill(fill)
                shape.strokeBorder(V3.ink, style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [7, 5] : []))
            }
        }
    }
}

/// 柔和卡：白底、淡投影。给列表用。
struct V3Soft: ViewModifier {
    var radius: CGFloat = 22
    var fill: Color = V3.card
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            .shadow(color: V3.navy.opacity(0.08), radius: 11, y: 6))
    }
}

extension View {
    func v3Sticker(fill: Color = V3.card, radius: CGFloat = 22, dashed: Bool = false, depth: CGFloat = 4) -> some View {
        modifier(V3Sticker(fill: fill, radius: radius, dashed: dashed, depth: depth))
    }
    func v3Soft(radius: CGFloat = 22, fill: Color = V3.card) -> some View { modifier(V3Soft(radius: radius, fill: fill)) }
    /// 柔和卡：带内边距、撑满宽度。
    func v3Card(h: CGFloat = 20, v: CGFloat = 18, radius: CGFloat = 22) -> some View {
        padding(.horizontal, h).padding(.vertical, v).frame(maxWidth: .infinity, alignment: .leading).v3Soft(radius: radius)
    }
}

/// 卡片底下那条海浪。
struct V3Wave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let h = r.height, w = r.width
        p.move(to: CGPoint(x: 0, y: h * 0.55))
        p.addCurve(to: CGPoint(x: w / 3, y: h * 0.45), control1: CGPoint(x: w * 0.1, y: 0), control2: CGPoint(x: w * 0.2, y: h))
        p.addCurve(to: CGPoint(x: w * 0.7, y: h * 0.55), control1: CGPoint(x: w * 0.47, y: 0), control2: CGPoint(x: w * 0.57, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h * 0.36), control1: CGPoint(x: w * 0.8, y: h), control2: CGPoint(x: w * 0.9, y: h * 0.9))
        p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
        return p
    }
}

extension View {
    /// 贴纸卡底部加一条海浪（卡要先留出底部空白）。
    func v3WaveBottom(color: Color = V3.soft, radius: CGFloat = 22) -> some View {
        overlay(alignment: .bottom) {
            V3Wave().fill(color).frame(height: 22).padding(.horizontal, 2.5).padding(.bottom, 2.5)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius - 2, bottomTrailingRadius: radius - 2, style: .continuous))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 按钮：按下去往下沉

struct V3ButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, danger, teal }
    enum Size { case small, regular, big }
    var kind: Kind = .primary
    var size: Size = .regular
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let depth: CGFloat = size == .small ? 2 : 3
        let border: CGFloat = size == .small ? 2 : 2.5
        let fill: Color = switch kind { case .primary: V3.navy; case .teal: V3.teal; default: .white }
        let fg: Color = switch kind { case .primary, .teal: .white; case .danger: V3.red; case .ghost: V3.ink }
        let down = configuration.isPressed
        return V3HoverLift(pressed: down) { configuration.label
            .font(V3.font(size == .big ? 17 : size == .small ? 13 : 14, .bold))
            .foregroundStyle(fg).lineLimit(1).fixedSize()
            .padding(.horizontal, size == .big ? 30 : size == .small ? 13 : 18)
            .padding(.vertical, size == .big ? 12 : size == .small ? 5 : 8)
            .background(Capsule().fill(fill).overlay(Capsule().strokeBorder(V3.ink, lineWidth: border)))
            .offset(y: down ? depth : 0)
            .background(Capsule().fill(V3.ink).offset(y: depth))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.08), value: down)
        }
    }
}

/// 鼠标移到按钮上：亮一点点。
private struct V3HoverLift<Content: View>: View {
    let pressed: Bool
    @ViewBuilder var content: Content
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        content
            .brightness(hover && enabled && !pressed ? 0.06 : 0)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

extension ButtonStyle where Self == V3ButtonStyle {
    static var v3: V3ButtonStyle { V3ButtonStyle() }
    static func v3(_ kind: V3ButtonStyle.Kind, _ size: V3ButtonStyle.Size = .regular) -> V3ButtonStyle { V3ButtonStyle(kind: kind, size: size) }
}

/// 整张卡当按钮：按下去沉一点。
struct V3SinkStyle: ButtonStyle {
    var depth: CGFloat = 3
    func makeBody(configuration: Configuration) -> some View { V3SinkBody(configuration: configuration, depth: depth) }
}

struct V3SinkBody: View {
    let configuration: ButtonStyleConfiguration
    let depth: CGFloat
    @State private var hover = false
    var body: some View {
        configuration.label.contentShape(Rectangle())
            // 鼠标移上去：轻轻抬起一点；按下去：沉下去
            .offset(y: configuration.isPressed ? depth : hover ? -1.5 : 0)
            .brightness(hover && !configuration.isPressed ? 0.012 : 0)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hover)
    }
}

// MARK: - 小零件

struct V3Tag: View {
    enum Tone { case blue, green, gold, red, teal }
    let text: String
    var tone: Tone = .blue
    var size: CGFloat = 11.5
    var body: some View {
        let (fg, bg): (Color, Color) = switch tone {
        case .blue: (V3.navy, V3.soft)
        case .green: (V3.green, V3.greenSoft)
        case .gold: (V3.gold, V3.goodBG)
        case .red: (V3.red, V3.warnBG)
        case .teal: (V3.teal, V3.tealSoft)
        }
        Text(text).font(V3.font(size, .bold)).foregroundStyle(fg).lineLimit(1).fixedSize()
            .padding(.horizontal, size * 0.7).padding(.vertical, 2).background(Capsule().fill(bg))
    }
}

/// 圆圈里的小图（账户、分类）。
struct V3Ico: View {
    let emoji: String
    var size: CGFloat = 38

    /// 设计库的贴纸图标（深蓝描边 + 柔和的颜色）。有对应的就用它，没有的才用表情符号。
    static let stickers: [String: String] = [
        "💳": "acct-credit", "🏦": "acct-bank", "⭐": "acct-stash", "💶": "acct-cash", "👛": "acct-wallet",
        "📱": "phone", "🧑": "loan", "🤝": "debt", "🛒": "grocery", "☕": "coffee", "🥗": "dining", "🍜": "dining",
        "🏠": "housing", "🔁": "subscription", "🚇": "transport", "🚌": "transport", "🚕": "taxi", "🚗": "taxi", "🎁": "gift",
        "💼": "salary", "🎬": "movie", "🎵": "music", "✂️": "software", "📦": "delivery", "🥡": "delivery", "☁️": "online",
        "📰": "books", "💊": "medical", "🏋️": "gym", "🛍": "shopping", "👟": "clothing", "⌚": "shopping", "💡": "utilities",
        "❓": "uncategorized", "🧾": "uncategorized", "✈️": "flight", "📚": "course",
    ]
    nonisolated(unsafe) private static var cache: [String: Image?] = [:]
    private static let lock = NSLock()
    static func sticker(_ emoji: String) -> Image? {
        guard let name = stickers[emoji] else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[name] { return hit }
        var img: Image?
        if let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "V3/icons"), let ns = NSImage(contentsOf: url) {
            img = Image(nsImage: ns)
        }
        cache[name] = img
        return img
    }

    var body: some View {
        Group {
            if let icon = Self.sticker(emoji) {
                icon.resizable().interpolation(.high).scaledToFit().padding(size * 0.19)
            } else {
                Text(emoji).font(.system(size: size * 0.47))
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(.white).overlay(Circle().strokeBorder(V3.ink, lineWidth: size < 34 ? 1.5 : 2)))
        .background(Circle().fill(V3.ink).offset(y: size < 34 ? 1.5 : 2))
        .accessibilityHidden(true)
    }
}

/// 夏夏的头像：calm 平静、talk 说话、happy 开心、celebrate 惊喜、worried 担心、think 在想。
struct V3Face: View {
    let face: String
    var width: CGFloat = 62
    var body: some View {
        V3.image("head-\(face)").resizable().scaledToFit().frame(width: width, height: width * 0.87).accessibilityHidden(true)
    }
}

/// 夏夏全身。
struct V3Xia: View {
    var width: CGFloat = 170
    @State private var bob = false
    @State private var hop = false
    @State private var said = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(V3State.self) private var state: V3State?
    private static let lines = ["我在呢。", "今天也一起把钱看清楚。", "不急，一步一步来。", "想问什么，点右上角「问夏夏」。", "戳我干嘛，去存一笔呀。"]
    var body: some View {
        V3.image("xia-full").resizable().interpolation(.high).scaledToFit().frame(width: width)
            .offset(y: (bob ? -3 : 0) + (hop ? -16 : 0))
            .rotationEffect(.degrees(hop ? -3 : 0), anchor: .bottom)
            .contentShape(Rectangle())
            .onTapGesture {
                state?.say(Self.lines[said % Self.lines.count])
                said += 1
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.18, bounce: 0.2)) { hop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { withAnimation(.spring(duration: 0.45, bounce: 0.55)) { hop = false } }
            }
            .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { bob = true } } }
            .accessibilityLabel("夏夏").accessibilityAddTraits(.isButton)
    }
}

/// 气泡：夏夏说的话，下面可以带按钮。
struct V3Bubble<Extra: View>: View {
    enum Tone { case plain, good, warn }
    let text: String
    var tone: Tone = .plain
    var kicker: String = ""
    var flat = false
    @ViewBuilder var extra: Extra
    var body: some View {
        let fill: Color = tone == .good ? V3.goodBG : tone == .warn ? V3.warnBG : V3.soft
        VStack(alignment: .leading, spacing: 8) {
            if !kicker.isEmpty {
                Text(kicker).font(V3.font(12.5, .heavy)).foregroundStyle(tone == .warn ? V3.red : tone == .good ? V3.gold : V3.navy)
            }
            Text(text).font(V3.font(14, .semibold)).foregroundStyle(V3.ink).fixedSize(horizontal: false, vertical: true)
            extra
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .v3Sticker(fill: fill, radius: 16, depth: flat ? 0 : 3)
    }
}

extension V3Bubble {
    init(_ text: String, tone: Tone = .plain, kicker: String = "", flat: Bool = false, @ViewBuilder extra: () -> Extra) {
        self.init(text: text, tone: tone, kicker: kicker, flat: flat, extra: extra)
    }
}

extension V3Bubble where Extra == EmptyView {
    init(_ text: String, tone: Tone = .plain, kicker: String = "", flat: Bool = false) {
        self.init(text: text, tone: tone, kicker: kicker, flat: flat) { EmptyView() }
    }
}

/// 夏夏要说的一句话（可以带按钮）。
/// 平常的页面上不画出来：夏夏像聊天助手，这句话从页面顶上滑下来，点开是和她聊天的那一页（见 V3Xia.swift）。
/// 只有大时刻（引导、到站的信、减半商量、每月小结）和弹出的纸里，才直接画成头像 + 气泡。
struct V3Ask<Extra: View>: View {
    let face: String
    let text: String
    var tone: V3Bubble<Extra>.Tone = .plain
    var kicker: String = ""
    @ViewBuilder var extra: Extra
    @Environment(\.v3InlineXia) private var inline
    var body: some View {
        if inline {
            HStack(alignment: .top, spacing: 10) {
                V3Face(face: face)
                V3Bubble(text: text, tone: tone, kicker: kicker) { extra }
            }
        } else {
            Color.clear.frame(width: 0, height: 0).padding(.vertical, -8)
                .preference(key: V3SayKey.self, value: V3Saying(id: text, face: face, text: text,
                                                                 tone: tone == .good ? 1 : tone == .warn ? 2 : 0, extra: AnyView(extra)))
                .accessibilityHidden(true)
        }
    }
}

extension V3Ask where Extra == EmptyView {
    init(face: String, text: String, tone: V3Bubble<EmptyView>.Tone = .plain, kicker: String = "") {
        self.init(face: face, text: text, tone: tone, kicker: kicker) { EmptyView() }
    }
}

/// 页面交上来的那句话。
struct V3Saying {
    var id: String
    var face: String
    var text: String
    /// 0 平常，1 好消息，2 要留意。
    var tone: Int
    var extra: AnyView
}

struct V3SayKey: PreferenceKey {
    static let defaultValue: V3Saying? = nil
    // 一页上有好几句时只说第一句
    static func reduce(value: inout V3Saying?, nextValue: () -> V3Saying?) { if value == nil { value = nextValue() } }
}

private struct V3InlineXiaKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// 这里的夏夏直接画出来（大时刻和弹出的纸）。
    var v3InlineXia: Bool {
        get { self[V3InlineXiaKey.self] }
        set { self[V3InlineXiaKey.self] = newValue }
    }
}

/// 卡片标题：左边标题（可带标签），右边小字。
struct V3CardTitle<Mid: View, Trail: View>: View {
    let title: String
    var size: CGFloat = 16
    @ViewBuilder var mid: Mid
    @ViewBuilder var trail: Trail
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(V3.font(size, .heavy)).foregroundStyle(V3.ink).lineLimit(1).fixedSize()
            mid
            Spacer(minLength: 6)
            trail
        }
    }
}

extension V3CardTitle where Mid == EmptyView, Trail == Text {
    init(_ title: String, note: String = "", size: CGFloat = 16) {
        self.init(title: title, size: size) { EmptyView() } trail: { Text(note).font(V3.font(13, .semibold)).foregroundStyle(V3.ink2) }
    }
}

extension V3CardTitle where Trail == Text {
    init(_ title: String, note: String = "", size: CGFloat = 16, @ViewBuilder mid: () -> Mid) {
        self.init(title: title, size: size, mid: mid) { Text(note).font(V3.font(13, .semibold)).foregroundStyle(V3.ink2) }
    }
}

struct V3Label: View {
    let text: String
    var size: CGFloat = 13.5
    var color: Color = V3.ink2
    var weight: Font.Weight = .regular
    init(_ text: String, size: CGFloat = 13.5, color: Color = V3.ink2, weight: Font.Weight = .regular) {
        self.text = text; self.size = size; self.color = color; self.weight = weight
    }
    var body: some View { Text(text).font(V3.font(size, weight)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true) }
}

/// 每页最重要的那个数：金币金，整数大、小数和 € 小。数字变的时候会滚一下。
struct V3Gold: View {
    let amount: Money
    var size: CGFloat = 72
    /// 不显示小数（「181 €」）。
    var whole = false
    @State private var shown: Money?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let value = shown ?? (reduceMotion ? amount : .zero)
        let p = value.v3Parts
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(p.whole).font(V3.num(size, .heavy)).foregroundStyle(V3.gold).contentTransition(.numericText(value: Double(value.cents)))
            Text(whole ? "\u{00A0}€" : p.rest).font(V3.num(size * 0.42, .bold)).foregroundStyle(V3.ink2)
                .contentTransition(.numericText(value: Double(value.cents)))
        }
        .lineLimit(1).fixedSize()
        .onAppear {
            // 刚出现时从 0 滚到这个数；截图时（-XiaxiaV3Still）直接显示
            if reduceMotion || V3Launch.still { shown = amount } else { withAnimation(.easeOut(duration: 0.55)) { shown = amount } }
        }
        .onChange(of: amount) { _, new in withAnimation(.snappy(duration: 0.35)) { shown = new } }
        .accessibilityElement().accessibilityLabel(amount.v3)
    }
}

/// 蓝 / 红 / 绿的金额。
struct V3Amount: View {
    let text: String
    var color: Color = V3.navy
    var size: CGFloat = 15.5
    var weight: Font.Weight = .bold
    init(_ text: String, color: Color = V3.navy, size: CGFloat = 15.5, weight: Font.Weight = .bold) {
        self.text = text; self.color = color; self.size = size; self.weight = weight
    }
    var body: some View {
        Text(text).font(V3.num(size, weight)).foregroundStyle(color).lineLimit(1).fixedSize().contentTransition(.numericText())
    }
}

/// 「数字 + 小字说明」一格。
struct V3KV: View {
    let value: String
    let label: String
    var color: Color = V3.navy
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            V3Amount(value, color: color, size: 17)
            Text(label).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1).fixedSize()
        }
    }
}

/// 进度条：蓝渐变、深蓝描边。
struct V3Bar: View {
    var fraction: Double
    var height: CGFloat = 10
    var color: Color? = nil
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(V3.soft)
                Capsule().fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient(colors: [V3.sky, V3.navy], startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(g.size.width * min(max(fraction, 0), 1), fraction > 0 ? height : 0))
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5))
        }
        .frame(height: height)
        .animation(.spring(duration: 0.5), value: fraction)
        .accessibilityElement().accessibilityLabel("进度").accessibilityValue("\(Int(fraction * 100))%")
    }
}

/// 一行：小图 + 名字和说明 + 右边金额。
struct V3Row: View {
    let emoji: String
    let name: String
    let meta: String
    let amount: String
    var color: Color = V3.navy
    var tag: String = ""
    var compact = false
    var tagTone: V3Tag.Tone = .blue
    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            V3Ico(emoji: emoji, size: compact ? 30 : 38)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(name).font(V3.font(14, .bold)).foregroundStyle(V3.ink).lineLimit(1)
                    if !tag.isEmpty { V3Tag(text: tag, tone: tagTone) }
                }
                Text(meta).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !amount.isEmpty { V3Amount(amount, color: color, size: compact ? 14.5 : 15.5) }
        }
        .padding(.vertical, compact ? 5 : 9)
        .accessibilityElement(children: .combine)
    }
}

struct V3Divider: View { var body: some View { Rectangle().fill(V3.line).frame(height: 1) } }

/// 几行之间加细线。
struct V3Rows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder var row: (Data.Element) -> Row
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { i, item in
                if i > 0 { V3Divider() }
                row(item)
            }
        }
    }
}

/// 浅底小格：上面小字，下面数字。
struct V3Tile: View {
    let label: String
    let value: String
    var color: Color = V3.ink
    var valueFirst = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if valueFirst {
                Text(value).font(V3.num(20)).foregroundStyle(color)
                Text(label).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
            } else {
                Text(label).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                Text(value).font(V3.num(20)).foregroundStyle(color).contentTransition(.numericText())
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(V3.bg))
    }
}

/// 可以选的卡（三选一那种）。选中的是金色底 + 硬阴影。
struct V3Option<Content: View>: View {
    let picked: Bool
    var action: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        Button(action: action) {
            content.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .v3Sticker(fill: picked ? V3.goodBG : .white, radius: 18, depth: picked ? 4 : 0)
        }
        .buttonStyle(V3SinkStyle())
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// 小药丸选项（例子、再加一个）。
struct V3Chip: View {
    let text: String
    var size: CGFloat = 14
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(V3.font(size, .bold)).foregroundStyle(V3.ink).lineLimit(1).fixedSize()
                .padding(.horizontal, size).padding(.vertical, size * 0.5)
                .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
        }
        .buttonStyle(V3SinkStyle(depth: 2))
    }
}

// MARK: - 星星瓶

/// 星星瓶：存一笔掉一颗星。`drops` 每加 1 就掉一颗。
struct V3Jar: View {
    var level: Double
    var width: CGFloat = 118
    var drops: Int = 0
    @State private var falling: [UUID] = []

    var body: some View {
        let s = width / 120
        Canvas { ctx, _ in
            ctx.scaleBy(x: s, y: s)
            let ink = GraphicsContext.Shading.color(V3.ink)
            // 木塞、瓶口
            let cork = Path(roundedRect: CGRect(x: 40, y: 4, width: 40, height: 14), cornerRadius: 4)
            ctx.fill(cork, with: .color(V3.hex(0xC98A5A))); ctx.stroke(cork, with: ink, lineWidth: 3)
            let neck = Path(roundedRect: CGRect(x: 34, y: 16, width: 52, height: 12), cornerRadius: 6)
            ctx.fill(neck, with: .color(.white)); ctx.stroke(neck, with: ink, lineWidth: 3)
            // 瓶身
            var body = Path()
            body.move(to: CGPoint(x: 30, y: 28))
            body.addQuadCurve(to: CGPoint(x: 10, y: 66), control: CGPoint(x: 10, y: 40))
            body.addLine(to: CGPoint(x: 10, y: 118))
            body.addQuadCurve(to: CGPoint(x: 36, y: 144), control: CGPoint(x: 10, y: 144))
            body.addLine(to: CGPoint(x: 84, y: 144))
            body.addQuadCurve(to: CGPoint(x: 110, y: 118), control: CGPoint(x: 110, y: 144))
            body.addLine(to: CGPoint(x: 110, y: 66))
            body.addQuadCurve(to: CGPoint(x: 90, y: 28), control: CGPoint(x: 110, y: 40))
            body.closeSubpath()
            ctx.fill(body, with: .color(.white))
            // 里面的星星
            let lv = min(max(level, 0), 1)
            ctx.drawLayer { inner in
                inner.clip(to: body)
                inner.fill(Path(CGRect(x: 0, y: 138 - lv * 96, width: 120, height: 150)), with: .color(V3.hex(0xFFF3D6)))
                var r: Double = 7
                let n = Int((lv * 28).rounded())
                for i in 0..<n {
                    r = (r * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
                    let x = 22 + (r / 233280) * 76
                    r = (r * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
                    let y = 132 - (r / 233280) * (lv * 86)
                    let text = Text("★").font(.system(size: 15)).foregroundColor(i % 4 == 0 ? V3.sky : V3.star)
                    let edge = Text("★").font(.system(size: 17)).foregroundColor(V3.ink)
                    inner.draw(edge, at: CGPoint(x: x + 6, y: y - 5))
                    inner.draw(text, at: CGPoint(x: x + 6, y: y - 5))
                }
            }
            ctx.stroke(body, with: ink, lineWidth: 3)
            // 高光
            ctx.fill(Path(roundedRect: CGRect(x: 20, y: 52, width: 6, height: 34), cornerRadius: 3), with: .color(.white.opacity(0.9)))
        }
        .frame(width: width, height: width * 1.25)
        .overlay {
            ForEach(falling, id: \.self) { id in
                V3FallingStar(width: width).id(id)
            }
        }
        .onChange(of: drops) { old, new in
            guard new > old else { return }
            let id = UUID()
            falling.append(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { falling.removeAll { $0 == id } }
        }
        .animation(.spring(duration: 0.6), value: level)
        .accessibilityElement().accessibilityLabel("星星瓶").accessibilityValue("装了 \(Int(level * 100))%")
    }
}

private struct V3FallingStar: View {
    let width: CGFloat
    @State private var t: CGFloat = 0
    @State private var x = CGFloat.random(in: -0.18...0.18)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Text("★").font(.system(size: width * 0.2)).foregroundStyle(V3.star)
            .shadow(color: V3.ink, radius: 0, x: 0.8, y: 0.8)
            .rotationEffect(.degrees(Double(t) * 230))
            .offset(x: x * width, y: -width * 1.1 + t * width * 1.25)
            .opacity(t < 0.05 ? 0 : (t >= 1 ? 0 : 1))
            .onAppear {
                if reduceMotion { t = 1 } else { withAnimation(.timingCurve(0.3, 0, 0.7, 1, duration: 0.7)) { t = 0.999 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { withAnimation(.easeOut(duration: 0.15)) { t = 1 } }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - 按设计尺寸画，再等比放进去

/// 里面的东西按 `design` 这么大来排，然后整体缩放到放得下。
struct V3Fit<Content: View>: View {
    let design: CGSize
    var alignment: Alignment = .center
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { g in
            let s = max(min(g.size.width / design.width, g.size.height / design.height), 0.01)
            content.frame(width: design.width, height: design.height)
                .scaleEffect(s, anchor: .center)
                .frame(width: g.size.width, height: g.size.height, alignment: alignment)
        }
    }
}

// MARK: - 排页面用的

/// 左右两栏，按比例分宽度。
struct V3Cols<Left: View, Right: View>: View {
    var left: CGFloat = 1
    var right: CGFloat = 1
    var gap: CGFloat = 18
    @ViewBuilder var leading: Left
    @ViewBuilder var trailing: Right
    var body: some View {
        GeometryReader { g in
            let w = (g.size.width - gap) * left / (left + right)
            HStack(alignment: .top, spacing: gap) {
                leading.frame(width: w).frame(maxHeight: .infinity, alignment: .top)
                trailing.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

/// 贴纸大卡：小字 + 金色大数字 + 下面的说明，底下一条海浪。
struct V3KeyCard<Extra: View>: View {
    let label: String
    let whole: String
    var rest: String = ""
    var size: CGFloat = 72
    var wave: Color = V3.soft
    @ViewBuilder var extra: Extra
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3Label(label)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(whole).font(V3.num(size, .heavy)).foregroundStyle(V3.gold).contentTransition(.numericText())
                Text(rest).font(V3.num(size * 0.42, .bold)).foregroundStyle(V3.ink2).contentTransition(.numericText())
            }
            .lineLimit(1).fixedSize()
            extra
        }
        .padding(.init(top: 18, leading: 22, bottom: 34, trailing: 22))
        .frame(maxWidth: .infinity, alignment: .leading)
        .v3Sticker().v3WaveBottom(color: wave)
        .accessibilityElement(children: .combine)
    }
}

extension V3KeyCard {
    init(label: String, amount: Money, size: CGFloat = 72, wave: Color = V3.soft, @ViewBuilder extra: () -> Extra) {
        let p = amount.v3Parts
        self.init(label: label, whole: p.whole, rest: p.rest, size: size, wave: wave, extra: extra)
    }
}

/// 撑满剩下高度的柔和卡。
struct V3GrowCard<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .v3Soft()
    }
}

/// 不撑高的柔和卡。
struct V3Card<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }.v3Card()
    }
}

/// 设计稿里那种简单的折线图：点按 560×高 的画布给，自动拉伸。
struct V3Lines: View {
    struct Line {
        var points: [(Double, Double)]
        var color: Color
        var width: CGFloat = 4
        var dash: [CGFloat] = []
        var fill: Color? = nil
    }
    var height: Double = 220
    var grid: [Double] = []
    var lines: [Line]
    var dot: (Double, Double)? = nil
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 560, sy = size.height / height
            func pt(_ p: (Double, Double)) -> CGPoint { CGPoint(x: p.0 * sx, y: p.1 * sy) }
            for y in grid { ctx.fill(Path(CGRect(x: 0, y: y * sy, width: size.width, height: 1)), with: .color(V3.line)) }
            for l in lines {
                guard let first = l.points.first, let last = l.points.last else { continue }
                var path = Path()
                path.move(to: pt(first))
                l.points.dropFirst().forEach { path.addLine(to: pt($0)) }
                if let fill = l.fill {
                    var area = path
                    area.addLine(to: CGPoint(x: last.0 * sx, y: size.height)); area.addLine(to: CGPoint(x: first.0 * sx, y: size.height)); area.closeSubpath()
                    ctx.fill(area, with: .color(fill))
                }
                ctx.stroke(path, with: .color(l.color), style: StrokeStyle(lineWidth: l.width, lineCap: .round, lineJoin: .round, dash: l.dash))
            }
            if let dot {
                let c = pt(dot)
                let circle = Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
                ctx.fill(circle, with: .color(V3.star)); ctx.stroke(circle, with: .color(V3.ink), lineWidth: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 开关：深蓝描边的小药丸。
struct V3Switch: View {
    @Binding var on: Bool
    var label: String
    var tint: Color = V3.navy
    var body: some View {
        Button { withAnimation(.snappy(duration: 0.18)) { on.toggle() } } label: {
            Capsule().fill(on ? tint : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2))
                .frame(width: 44, height: 26)
                .overlay(alignment: on ? .trailing : .leading) { Circle().fill(on ? .white : V3.ink).frame(width: 18, height: 18).padding(4) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityValue(on ? "开着" : "关着").accessibilityAddTraits(.isButton)
    }
}

/// 分期那种一格一格的进度。
struct V3Periods: View {
    let total: Int
    let done: Int
    var color: Color = V3.navy
    var height: CGFloat = 16
    var body: some View {
        HStack(spacing: total > 20 ? 4 : 5) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: total > 20 ? 4 : 5).fill(i < done ? color : .white)
                    .overlay(RoundedRectangle(cornerRadius: total > 20 ? 4 : 5).strokeBorder(V3.ink, lineWidth: total > 20 ? 1.5 : 2))
                    .frame(height: height)
            }
        }
        .accessibilityElement().accessibilityLabel("\(total) 期还了 \(done) 期")
    }
}

/// 圆环进度（回本）。
struct V3Ring: View {
    var fraction: Double
    var size: CGFloat = 86
    var color: Color = V3.teal
    var body: some View {
        ZStack {
            Circle().stroke(V3.tealSoft, lineWidth: size * 0.14)
            Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))%").font(V3.num(size * 0.21, .heavy)).foregroundStyle(V3.ink)
        }
        .padding(size * 0.07).frame(width: size, height: size)
        .accessibilityElement().accessibilityLabel("走了 \(Int((fraction * 100).rounded()))%")
    }
}

/// 输入框：药丸形、深蓝描边。
struct V3Field: View {
    let prompt: String
    @Binding var text: String
    var size: CGFloat = 15
    var rounded = false
    var onSubmit: () -> Void = {}
    var body: some View {
        TextField(prompt, text: $text).textFieldStyle(.plain)
            .font(rounded ? V3.num(size, .heavy) : V3.font(size, .bold)).foregroundStyle(V3.ink)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2)))
            .onSubmit(onSubmit)
    }
}

/// 麦克风按钮：点一下开始说，再点一下停；字边说边出。停顿够了自动交出去（多久在设置里选）。⌥Space 也能开关。
/// 权限被拒时变灰，鼠标移上去说去哪打开。
struct V3MicButton: View {
    /// 每出几个字叫一次（填进输入框）。
    let live: (String) -> Void
    /// 说完叫一次；`auto` 是因为停顿够了自动说完的（这时才自动发出去）。
    let done: (String) -> Void
    var shortcut = true
    @Environment(V3State.self) private var state
    @State private var voice = SpeechDictation()

    var body: some View {
        let b = Button {
            voice.pause = VoiceRules.pause(state.prefs.voicePause).map { Duration.seconds($0) }
            voice.toggle(live: live, done: done)
        } label: {
            Image(systemName: voice.listening ? "waveform" : voice.blocked ? "mic.slash" : "mic")
                .font(.system(size: 15, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: voice.listening)
                .foregroundStyle(voice.listening ? .white : V3.navy)
                .frame(width: 40, height: 40)
                .background(Circle().fill(voice.listening ? V3.red : .white).overlay(Circle().strokeBorder(V3.ink, lineWidth: 2)))
        }
        .buttonStyle(V3SinkStyle(depth: 2))
        .disabled(voice.blocked).opacity(voice.blocked ? 0.45 : 1)
        .help(voice.blocked ? SpeechDictation.whereToAllow : voice.listening ? "再点一下说完（⌥Space）" : "点一下，说一句（⌥Space）")
        .accessibilityLabel(voice.listening ? "说完了" : "说一句")
        .onChange(of: voice.error) { _, e in if let e, !voice.listening { state.fail(e) } }
        if shortcut { b.keyboardShortcut(.space, modifiers: .option) } else { b }
    }
}
#endif
