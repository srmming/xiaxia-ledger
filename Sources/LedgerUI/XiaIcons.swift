import FinanceCore
import SwiftUI

// 夏夏账本自己画的图标和小组件。图形数据在 XiaGlyphData.swift（由 design/icon-kit/build.py 生成），
// 这里只管怎么画：浅色 / 深色各一套颜色，跟着文字颜色的图标（导航、操作）用前景色。
//
// 组件一览（展示页 design/icon-kit/index.html 里每个都有）：
//   XiaIcon            单个图标，任意大小
//   XiaTile            分类方块：浅色底 + 图标（流水行、花销排行、记一笔）
//   AccountIcon        账户图标方块（家底、管理账户）
//   XiaxiaAvatar       夏夏头像（会眨眼的圆形头像，形象见 Mascot.swift）
//   XiaxiaIllustration 空状态 / 出错 / 加载插画
//   CategoryIconGrid / CategoryCreator / CategoryIconEditor  挑图标、新建分类、换图标（CategoryPicker.swift）
//   XiaBadge           小徽章：图标 + 几个字（AI 记的、留意、每月扣…）
//   XiaGlyph.image     做成 Image，给标签栏、侧栏、菜单这种只收 Image 的地方

// MARK: - 路径解析（只认 M L C Z，绝对坐标）

final class XiaPathCache: @unchecked Sendable {
    static let shared = XiaPathCache()
    private var cache: [String: Path] = [:]
    private let lock = NSLock()

    func path(_ d: String) -> Path {
        lock.lock()
        defer { lock.unlock() }
        if let p = cache[d] { return p }
        let p = Self.parse(d)
        cache[d] = p
        return p
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        var nums: [CGFloat] = []
        var cmd: Character = " "
        func flush() {
            switch cmd {
            case "M": if nums.count >= 2 { path.move(to: CGPoint(x: nums[0], y: nums[1])) }
            case "L": if nums.count >= 2 { path.addLine(to: CGPoint(x: nums[0], y: nums[1])) }
            case "C":
                if nums.count >= 6 {
                    path.addCurve(to: CGPoint(x: nums[4], y: nums[5]),
                                  control1: CGPoint(x: nums[0], y: nums[1]),
                                  control2: CGPoint(x: nums[2], y: nums[3]))
                }
            case "Z": path.closeSubpath()
            default: break
            }
            nums.removeAll(keepingCapacity: true)
        }
        for token in d.split(separator: " ") {
            if let c = token.first, token.count == 1, "MLCZ".contains(c) {
                flush()
                cmd = c
                if c == "Z" { flush(); cmd = " " }
            } else if let v = Double(token) {
                nums.append(CGFloat(v))
            }
        }
        flush()
        return path
    }
}

// MARK: - 颜色

enum XiaColor {
    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    /// 图标颜色：语义色名（brand、ai…）或 6 位十六进制（分类色）。
    static func tintHex(_ tint: String, dark: Bool) -> UInt32? {
        if let pair = XiaPalette.tints[tint] { return dark ? pair.1 : pair.0 }
        return UInt32(tint, radix: 16)
    }

    static func tint(_ tint: String, dark: Bool) -> Color {
        rgb(tintHex(tint, dark: dark) ?? 0x8C8C93)
    }
}

// MARK: - 画

enum XiaRenderer {
    /// 把一个图标画进 ctx 的 rect 里（等比缩放、居中）。
    /// - tint: 整个图标用的颜色；nil 就用图标自带的，还没有就跟着前景色（template）。
    static func draw(_ glyph: XiaGlyph, in ctx: GraphicsContext, rect: CGRect, dark: Bool,
                     tint: String? = nil, template: GraphicsContext.Shading = .foreground) {
        var ctx = ctx
        let canvas = glyph.canvas
        let s = min(rect.width / canvas.width, rect.height / canvas.height)
        ctx.translateBy(x: rect.minX + (rect.width - canvas.width * s) / 2, y: rect.minY + (rect.height - canvas.height * s) / 2)
        ctx.scaleBy(x: s, y: s)
        let baseTint = tint ?? glyph.tint
        ctx.drawLayer { layer in
            for (paint, d, width) in glyph.layers {
                let path = XiaPathCache.shared.path(d)
                let parts = paint.split(separator: ":", maxSplits: 1).map(String.init)
                let name = parts[0]
                let localTint = parts.count > 1 ? parts[1] : baseTint
                var shading: GraphicsContext.Shading
                var alpha = 1.0
                var cut = false
                if let named = XiaPalette.named[name] {
                    shading = .color(XiaColor.rgb(dark ? named.1 : named.0))
                    alpha = dark ? named.3 : named.2
                } else if name == "hi" {
                    shading = .color(.white); alpha = 0.9
                } else if name == "cut" {
                    shading = .color(.black); cut = true
                } else {
                    if let t = localTint, let hex = XiaColor.tintHex(t, dark: dark) {
                        shading = .color(XiaColor.rgb(hex))
                    } else {
                        shading = template
                    }
                    if name == "soft" { alpha = dark ? XiaPalette.softAlpha.1 : XiaPalette.softAlpha.0 }
                }
                layer.opacity = alpha
                layer.blendMode = cut ? .destinationOut : .normal
                if width > 0 {
                    layer.stroke(path, with: shading, style: StrokeStyle(lineWidth: CGFloat(width), lineCap: .round, lineJoin: .round))
                } else {
                    layer.fill(path, with: shading)
                }
            }
        }
    }
}

extension XiaGlyph {
    /// 做成 Image：给 TabView、侧栏 Label、菜单这种只收 Image 的地方。画成黑色，按 template 用，系统会自己上色。
    func image(size: CGFloat = 22) -> Image {
        let glyph = self
        return Image(size: CGSize(width: size, height: size), label: Text(label)) { ctx in
            XiaRenderer.draw(glyph, in: ctx, rect: CGRect(x: 0, y: 0, width: size, height: size), dark: false,
                             tint: nil, template: .color(.black))
        }
        .renderingMode(.template)
    }
}

// MARK: - 组件

/// 单个图标。跟着文字颜色的图标（导航、操作）用 .foregroundStyle 改色。
struct XiaIcon: View {
    let glyph: XiaGlyph
    var size: CGFloat = 24
    /// 换个颜色：语义色名（"brand"、"ai"）或十六进制（"FF7A59"）。
    var tint: String? = nil
    @Environment(\.colorScheme) private var scheme

    init(_ glyph: XiaGlyph, size: CGFloat = 24, tint: String? = nil) {
        self.glyph = glyph; self.size = size; self.tint = tint
    }

    var body: some View {
        let c = glyph.canvas
        Canvas { ctx, sz in
            XiaRenderer.draw(glyph, in: ctx, rect: CGRect(origin: .zero, size: sz), dark: scheme == .dark, tint: tint)
        }
        .frame(width: size, height: size * c.height / c.width)
        .accessibilityHidden(true)
    }
}

/// 分类方块：浅浅一层分类色的圆角方块，中间是图标。
struct XiaTile: View {
    let glyph: XiaGlyph
    var tint: String? = nil
    var size: CGFloat = 32
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = tint ?? glyph.tint ?? "fg3"
        XiaIcon(glyph, size: size * 0.66, tint: t)
            .frame(width: size, height: size)
            .background(XiaColor.tint(t, dark: scheme == .dark).opacity(scheme == .dark ? 0.20 : 0.14),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 夏夏头像。夏夏的正式形象由「用 ChatGPT 生成夏夏动态形象」那边做（design/xiaxia-mascot/），
/// 出图前先画一个中性占位：靛蓝浅底圆 + 小星星。以后换图只改这里的 body，调用的地方不用动。
struct XiaxiaAvatar: View {
    var persona: Persona? = nil
    var size: CGFloat = 28

    init(persona: Persona? = nil, size: CGFloat = 28) { self.persona = persona; self.size = size }

    /// 夏夏的圆形头像（会眨眼），按性格换表情。形象见 Mascot.swift。
    var body: some View {
        MascotView(.xiaxia, pose: persona?.mascotPose ?? .idle, size: size, face: true)
            .accessibilityLabel("夏夏")
    }
}

/// 空状态 / 出错 / 加载插画（160×120）。
struct XiaxiaIllustration: View {
    let art: XiaGlyph
    var width: CGFloat = 168

    init(_ art: XiaGlyph, width: CGFloat = 168) { self.art = art; self.width = width }

    var body: some View {
        XiaIcon(art, size: width)
            .accessibilityHidden(true)
    }
}

/// 小徽章：图标 + 几个字，颜色跟着图标的语义色（AI 靛蓝、留意黄、做到了绿…）。
struct XiaBadge: View {
    let glyph: XiaGlyph
    var text: String? = nil
    @Environment(\.colorScheme) private var scheme

    init(_ glyph: XiaGlyph, _ text: String? = nil) { self.glyph = glyph; self.text = text }

    var body: some View {
        let t = glyph.tint ?? "fg2"
        let color = XiaColor.tint(t, dark: scheme == .dark)
        HStack(spacing: 3) {
            XiaIcon(glyph, size: 13)
            Text(text ?? glyph.label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(t == "fg2" || t == "fg3" ? Color.fg2 : color)
        .padding(.leading, 4).padding(.trailing, 6).padding(.vertical, 2)
        .background(color.opacity(scheme == .dark ? 0.18 : 0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 对应关系

extension AppSection {
    var glyph: XiaGlyph {
        switch self {
        case .overview: .navOverview
        case .spending: .navSpending
        case .trends: .navTrends
        case .wealth: .navWealth
        case .plans: .navPlans
        case .subscriptions: .subscription
        case .debts: .debt
        case .reimburse: .reimburse
        case .insights: .navXiaxia
        case .changes: .navChanges
        case .transactions: .navTransactions
        case .settings: .navSettings
        }
    }
}

extension AccountKind {
    var glyph: XiaGlyph {
        switch self {
        case .bank: .bank
        case .credit: .credit
        case .cash: .cash
        case .wallet: .wallet
        case .savings: .savings
        }
    }
}

/// 账户图标：私房钱账户用「私房钱」罐子，其他按账户类型。
struct AccountIcon: View {
    let kind: AccountKind
    var isPrivate = false
    var size: CGFloat = 32

    var body: some View {
        XiaTile(glyph: isPrivate ? .stash : kind.glyph, size: size)
    }
}
