#if os(iOS)
import FinanceCore
import SwiftUI
import UIKit

// iPhone 界面 v3 的公用零件。样子照 Mac v3（设计库 v2：晴空配色、贴纸卡、圆体数字），按手指的大小重排。
// 设计稿：「夏夏账本 iPhone 组件」（2026-11-27）。只做浅色。

enum P3 {
    static func hex(_ h: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: a)
    }
    static let bg = hex(0xEEF3FF), card = Color.white, ink = hex(0x1F2550), ink2 = hex(0x6B7099), navy = hex(0x2E3A82)
    static let gold = hex(0xC98A1B), star = hex(0xF2B93B)
    static let soft = hex(0xDCE6FF), sky = hex(0x7FA3F0), line = hex(0xDDE4F6), side = hex(0xE3EAFD)
    static let red = hex(0xC4433A), green = hex(0x1E8A5A), teal = hex(0x1F8A9A)
    static let goodBG = hex(0xFDF1D2), warnBG = hex(0xFBE3E1), paper = hex(0xFFFBF0), debtBG = hex(0xFFF1EF)
    static let dash = hex(0xB9C4E8), tealSoft = hex(0xD8F0F2), greenSoft = hex(0xDDF3E7)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight) }
    static func num(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded).monospacedDigit() }

    /// 夏夏的头像：calm / talk / happy / celebrate / worried / think。
    static func face(_ name: String) -> Image {
        if let url = Bundle.module.url(forResource: "head-\(name)", withExtension: "png", subdirectory: "V3"),
           let img = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: img)
        }
        return Image(systemName: "face.smiling")
    }
}

extension Money {
    var p3: String { (cents < 0 ? "\u{2212}" : "") + magnitude.formatted.replacingOccurrences(of: " ", with: "\u{00A0}") }
    var p3Short: String { p3.replacingOccurrences(of: ",00\u{00A0}", with: "\u{00A0}") }
    var p3Signed: String { (cents >= 0 ? "+" : "\u{2212}") + magnitude.p3 }
    var p3Parts: (whole: String, rest: String) {
        let text = magnitude.formatted.replacingOccurrences(of: " ", with: "\u{00A0}")
        guard let i = text.firstIndex(of: ",") else { return (text, "") }
        return ((cents < 0 ? "\u{2212}" : "") + String(text[..<i]), String(text[i...]))
    }
}

// MARK: - 卡片

extension View {
    /// 贴纸卡：深蓝粗描边 + 硬阴影。每页最要紧的那块用。
    func p3Sticker(fill: Color = P3.card, radius: CGFloat = 20, depth: CGFloat = 4) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                shape.fill(P3.ink).offset(y: depth)
                shape.fill(fill)
                shape.strokeBorder(P3.ink, lineWidth: 2.5)
            }
        }
    }
    /// 柔和卡：白底、淡投影。
    func p3Soft(radius: CGFloat = 20, fill: Color = P3.card) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill).shadow(color: P3.navy.opacity(0.08), radius: 11, y: 6))
    }
    func p3Card(h: CGFloat = 16, v: CGFloat = 14, radius: CGFloat = 20) -> some View {
        padding(.horizontal, h).padding(.vertical, v).frame(maxWidth: .infinity, alignment: .leading).p3Soft(radius: radius)
    }
}

// MARK: - 按钮：按下去往下沉

struct P3ButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, danger, teal, text }
    enum Size { case small, regular, wide }
    var kind: Kind = .primary
    var size: Size = .regular
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        if kind == .text {
            return AnyView(configuration.label.font(P3.font(16, .bold)).foregroundStyle(P3.navy)
                .frame(maxWidth: size == .wide ? .infinity : nil, minHeight: 44).contentShape(Rectangle()).opacity(down ? 0.6 : 1))
        }
        let depth: CGFloat = size == .small ? 2 : 3
        let border: CGFloat = size == .small ? 2 : 2.5
        let fill: Color = switch kind { case .primary: P3.navy; case .teal: P3.teal; default: .white }
        let fg: Color = switch kind { case .primary, .teal: .white; case .danger: P3.red; default: P3.ink }
        return AnyView(configuration.label
            .font(P3.font(size == .wide ? 17 : size == .small ? 13.5 : 15, .bold))
            .foregroundStyle(fg).lineLimit(1)
            .padding(.horizontal, size == .small ? 13 : 18)
            .frame(maxWidth: size == .wide ? .infinity : nil)
            .frame(height: size == .wide ? 50 : size == .small ? 32 : 40)
            .background(Capsule().fill(fill).overlay(Capsule().strokeBorder(P3.ink, lineWidth: border)))
            .offset(y: down ? depth : 0)
            .background(Capsule().fill(P3.ink).offset(y: depth))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
            .animation(.easeOut(duration: down ? 0.08 : 0.18), value: down))
    }
}

extension ButtonStyle where Self == P3ButtonStyle {
    static var p3: P3ButtonStyle { P3ButtonStyle() }
    static func p3(_ kind: P3ButtonStyle.Kind, _ size: P3ButtonStyle.Size = .regular) -> P3ButtonStyle { P3ButtonStyle(kind: kind, size: size) }
}

/// 整张卡当按钮：按下去沉一点。
struct P3Sink: ButtonStyle {
    var depth: CGFloat = 2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
            .offset(y: configuration.isPressed ? depth : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 小零件

struct P3Tag: View {
    enum Tone { case blue, green, gold, red, teal }
    let text: String
    var tone: Tone = .blue
    var body: some View {
        let (fg, bg): (Color, Color) = switch tone {
        case .blue: (P3.navy, P3.soft)
        case .green: (P3.green, P3.greenSoft)
        case .gold: (P3.gold, P3.goodBG)
        case .red: (P3.red, P3.warnBG)
        case .teal: (P3.teal, P3.tealSoft)
        }
        Text(text).font(P3.font(11.5, .bold)).foregroundStyle(fg).lineLimit(1).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(bg))
    }
}

struct P3Label: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = P3.ink2
    init(_ text: String, size: CGFloat = 13, color: Color = P3.ink2) { self.text = text; self.size = size; self.color = color }
    var body: some View { Text(text).font(P3.font(size, .semibold)).foregroundStyle(color) }
}

/// 金币金的大数字：「412」大，「,60 €」小。
struct P3Gold: View {
    let amount: Money
    var size: CGFloat = 56
    var body: some View {
        let p = amount.p3Parts
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(p.whole).font(P3.num(size, .heavy)).foregroundStyle(P3.gold)
            Text(p.rest).font(P3.num(size * 0.42, .bold)).foregroundStyle(P3.ink2)
        }
        .lineLimit(1).minimumScaleFactor(0.6)
        .contentTransition(.numericText())
    }
}

struct P3Bar: View {
    let fraction: Double
    var height: CGFloat = 10
    var color: Color = P3.navy
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(P3.soft)
                Capsule().fill(LinearGradient(colors: [P3.sky, color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * min(max(fraction, 0), 1)))
            }
            .overlay(Capsule().strokeBorder(P3.ink, lineWidth: 1.5))
        }
        .frame(height: height)
        .animation(.spring(duration: 0.5), value: fraction)
    }
}

struct P3SectionTitle: View {
    let title: String
    var trail: String = ""
    var body: some View {
        HStack {
            Text(title).font(P3.font(16, .heavy)).foregroundStyle(P3.ink)
            Spacer()
            if !trail.isEmpty { Text(trail).font(P3.font(13, .semibold)).foregroundStyle(P3.ink2) }
        }
    }
}

/// 一行流水 / 账户：圆圈图标 + 名字 + 小字 + 右边金额。
struct P3Row: View {
    let emoji: String
    let name: String
    var meta: String = ""
    var amount: String = ""
    var color: Color = P3.navy
    var tag: String = ""
    var tagTone: P3Tag.Tone = .blue
    var body: some View {
        HStack(spacing: 12) {
            P3Icon(emoji: emoji)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name).font(P3.font(15.5, .bold)).foregroundStyle(P3.ink).lineLimit(1)
                    if !tag.isEmpty { P3Tag(text: tag, tone: tagTone) }
                }
                if !meta.isEmpty { Text(meta).font(P3.font(12.5, .regular)).foregroundStyle(P3.ink2).lineLimit(1) }
            }
            Spacer(minLength: 6)
            if !amount.isEmpty {
                Text(amount).font(P3.num(16, .bold)).foregroundStyle(color).lineLimit(1).fixedSize()
            }
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())   // 整行都能点，不只是字和数
        .accessibilityElement(children: .combine)
    }
}

struct P3Divider: View {
    var body: some View { Rectangle().fill(P3.line).frame(height: 1) }
}

/// 夏夏的气泡：头像 + 一句话 + 底下几个小按钮。
struct P3Bubble<Actions: View>: View {
    var face = "talk"
    let text: String
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            P3.face(face).resizable().scaledToFit().frame(width: 46, height: 40).blendMode(.multiply)
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(P3.font(14.5, .bold)).foregroundStyle(P3.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { actions }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .p3Sticker(fill: P3.soft, radius: 18, depth: 3)
        }
    }
}

extension P3Bubble where Actions == EmptyView {
    init(face: String = "talk", text: String) { self.face = face; self.text = text; self.actions = EmptyView() }
}

// MARK: - 贴纸图标（设计库的 SVG，只用到 path 的 M / L / C / Z，自己画）

struct P3Icon: View {
    let emoji: String
    var size: CGFloat = 36

    static let stickers: [String: String] = [
        "💳": "acct-credit", "🏦": "acct-bank", "⭐": "acct-stash", "💶": "acct-cash", "👛": "acct-wallet", "🏪": "acct-bank",
        "📱": "phone", "🧑": "loan", "🤝": "debt", "🛒": "grocery", "☕": "coffee", "🥗": "dining", "🍜": "dining",
        "🏠": "housing", "🔁": "subscription", "🚇": "transport", "🚌": "transport", "🚕": "taxi", "🚗": "taxi", "🎁": "gift",
        "💼": "salary", "💰": "salary", "🎬": "movie", "🎵": "music", "✂️": "software", "📦": "delivery", "🥡": "delivery", "☁️": "online",
        "📰": "books", "💊": "medical", "🏋️": "gym", "🛍": "shopping", "👟": "clothing", "👕": "clothing", "⌚": "shopping", "💡": "utilities",
        "❓": "uncategorized", "✈️": "flight", "📚": "course", "🎉": "gift", "🧧": "gift", "↩️": "transfer",
        "🎀": "gift", "🚚": "transport", "🎮": "shopping", "✋": "savings",
        // 正式账本的分类图标（LedgerBridge.categoryEmoji）里有贴纸的；没有贴纸的直接显示 emoji，不再用问号
        "🛍️": "shopping", "💅": "beauty", "💄": "beauty", "💇": "beauty", "💆": "beauty", "🐾": "pets", "💻": "software",
        "🚆": "transport", "🚲": "transport", "📖": "books", "🎓": "course", "🩺": "medical", "🦷": "medical", "🍲": "dining",
        "🥐": "dining", "🧋": "coffee", "🍺": "dining", "🍸": "dining", "🔀": "transfer",
    ]
    nonisolated(unsafe) private static var cache: [String: [SVGPath]] = [:]
    private static let lock = NSLock()

    static func paths(_ emoji: String) -> [SVGPath]? {
        guard let name = stickers[emoji] else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[name] { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "V3/icons"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parsed = SVGPath.parseAll(text)
        cache[name] = parsed
        return parsed
    }

    var body: some View {
        Group {
            if let paths = Self.paths(emoji) {
                Canvas { ctx, sz in
                    let s = sz.width / 24
                    ctx.scaleBy(x: s, y: s)
                    for p in paths { p.draw(in: &ctx) }
                }
                .padding(size * 0.19)
            } else {
                Text(emoji).font(.system(size: size * 0.47))
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(.white).overlay(Circle().strokeBorder(P3.ink, lineWidth: size < 34 ? 1.5 : 2)))
        .background(Circle().fill(P3.ink).offset(y: size < 34 ? 1.5 : 2))
        .accessibilityHidden(true)
    }
}

struct SVGPath: Sendable {
    var path: Path
    var fill: Color?
    var stroke: Color?
    var width: CGFloat = 1
    var opacity: Double = 1
    var cap: CGLineCap = .butt
    var join: CGLineJoin = .miter

    func draw(in ctx: inout GraphicsContext) {
        var c = ctx
        c.opacity = opacity
        if let fill { c.fill(path, with: .color(fill)) }
        if let stroke { c.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: join)) }
    }

    static func parseAll(_ svg: String) -> [SVGPath] {
        var out: [SVGPath] = []
        var rest = svg[...]
        while let start = rest.range(of: "<path"), let end = rest[start.upperBound...].range(of: "/>") {
            let tag = String(rest[start.upperBound..<end.lowerBound])
            rest = rest[end.upperBound...]
            func attr(_ name: String) -> String? {
                guard let r = tag.range(of: " \(name)=\"") else { return nil }
                let after = tag[r.upperBound...]
                guard let q = after.firstIndex(of: "\"") else { return nil }
                return String(after[..<q])
            }
            guard let d = attr("d") else { continue }
            var p = SVGPath(path: parsePath(d))
            p.fill = color(attr("fill") ?? "#000")
            p.stroke = attr("stroke").flatMap(color)
            p.width = CGFloat(Double(attr("stroke-width") ?? "1") ?? 1)
            p.opacity = Double(attr("opacity") ?? "1") ?? 1
            p.cap = attr("stroke-linecap") == "round" ? .round : .butt
            p.join = attr("stroke-linejoin") == "round" ? .round : .miter
            out.append(p)
        }
        return out
    }

    static func color(_ s: String) -> Color? {
        guard s.hasPrefix("#"), let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        if s.count == 4 {
            let r = (v >> 8) & 0xF, g = (v >> 4) & 0xF, b = v & 0xF
            return P3.hex((r * 17) << 16 | (g * 17) << 8 | (b * 17))
        }
        return P3.hex(v)
    }

    static func parsePath(_ d: String) -> Path {
        var tokens: [String] = []
        var cur = ""
        for ch in d {
            if ch.isLetter { if !cur.isEmpty { tokens.append(cur); cur = "" }; tokens.append(String(ch)) }
            else if ch == " " || ch == "," { if !cur.isEmpty { tokens.append(cur); cur = "" } }
            else if ch == "-", !cur.isEmpty, cur.last != "e" { tokens.append(cur); cur = "-" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        var p = Path()
        var i = 0
        var cmd = "M"
        var pt = CGPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0 }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = tokens[i]; i += 1; if cmd == "Z" || cmd == "z" { p.closeSubpath(); continue } }
            let rel = cmd == cmd.lowercased()
            func point() -> CGPoint { let x = num(), y = num(); return rel ? CGPoint(x: pt.x + x, y: pt.y + y) : CGPoint(x: x, y: y) }
            switch cmd.uppercased() {
            case "M": pt = point(); p.move(to: pt); cmd = rel ? "l" : "L"
            case "L": pt = point(); p.addLine(to: pt)
            case "C":
                let a = point(), b = point(), e = point()
                p.addCurve(to: e, control1: a, control2: b); pt = e
            default: i += 1
            }
        }
        return p
    }
}

// MARK: - 提示条

struct P3ToastView: View {
    let text: String
    var canUndo = false
    var isError = false
    var undo: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text(text).font(P3.font(14.5, .bold)).foregroundStyle(.white).lineLimit(2)
            if canUndo {
                Button("撤销", action: undo).font(P3.font(14.5, .heavy)).foregroundStyle(P3.star)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Capsule().fill(isError ? P3.red : P3.ink))
        .shadow(color: P3.ink.opacity(0.25), radius: 10, y: 4)
    }
}
#endif
