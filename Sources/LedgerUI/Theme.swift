import FinanceCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// UI 套件 v1 的设计规范：颜色、间距、圆角、字体。所有页面只从这里取，不各写一套。
/// 骨架用系统组件和系统颜色；夏夏账本自己的味道只有两处：圆体大数字和晨光橙。靛蓝只给 AI。
enum Kit {
    static let cardPadding: CGFloat = 16
    static let gap: CGFloat = 16
    #if os(iOS)
    static let side: CGFloat = 14
    static let cardRadius: CGFloat = 16
    #else
    static let side: CGFloat = 24
    static let cardRadius: CGFloat = 14
    #endif
    static let buttonRadius: CGFloat = 8
    static let tagRadius: CGFloat = 5
}

extension Color {
    /// 浅色、深色各一个值，跟着系统外观变。
    static func kit(_ light: UInt32, _ dark: UInt32, alpha: Double = 1, darkAlpha: Double? = nil) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha ?? alpha) : UIColor(hex: light, alpha: alpha)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkAlpha ?? alpha) : NSColor(hex: light, alpha: alpha)
        })
        #endif
    }

    /// 晨光橙：关键数字、选中状态、记一笔。
    static let brand = kit(0xB4441F, 0xFF8157)
    static let brandSoft = kit(0xC4502A, 0xFF8157, alpha: 0.11, darkAlpha: 0.16)
    /// 进账绿。
    static let income = kit(0x0E6B40, 0x36C77F)
    static let incomeSoft = kit(0x137A4A, 0x36C77F, alpha: 0.10, darkAlpha: 0.15)
    /// 留意（黄）。
    static let warn = kit(0x855500, 0xFFB72B)
    static let warnSoft = kit(0xE8A000, 0xFFB72B, alpha: 0.14, darkAlpha: 0.15)
    /// 真的要注意：超支、信用卡快到期。花钱本身不用红色。
    static let alert = kit(0xB8322A, 0xFF6A5F)
    static let alertSoft = kit(0xD33F35, 0xFF6A5F, alpha: 0.10, darkAlpha: 0.15)
    /// 青蓝 = 店里的钱（家底页）。不用黄色：黄色是「留意」，店里的钱不是坏事。
    static let shop = kit(0x0B6577, 0x2FA4BA)
    static let shopSoft = kit(0x0E7C92, 0x2FA4BA, alpha: 0.10, darkAlpha: 0.15)
    /// 靛蓝 = AI。
    static let ai = kit(0x4644C4, 0x8C89FF)
    static let aiSoft = kit(0x5856D6, 0x8C89FF, alpha: 0.09, darkAlpha: 0.14)
    static let aiLine = kit(0x5856D6, 0x8C89FF, alpha: 0.28, darkAlpha: 0.35)
    /// 「问 AI」实心按钮的底色（深色里稍亮一点，白字才看得清）。
    static let aiSolid = kit(0x4644C4, 0x5552D9)
    /// 实心按钮的底色：上面放白字。深色模式下比 brand 暗一档，白字才有 4.5:1（审查 2026-11-26：原来 2.5:1）。
    static let brandSolid = kit(0xB4441F, 0xC4502A)
    /// 店里那边的实心按钮底色（白字 4.6:1 以上）。
    static let shopSolid = kit(0x0B6577, 0x137F93)
    /// 图表里「花掉」「上月」的灰柱：和卡片底色至少 3:1（审查实测原来只有 1.6–2.2:1）。
    static let barExpense = kit(0x8C8C93, 0x7A7A82)
    static let fg2 = kit(0x5A5A62, 0xB0B0B7)
    static let fg3 = kit(0x68686F, 0x8C8C93)
    /// 页面底色和卡片底色。
    static let pageBackground = kit(0xF2F2F5, 0x0C0C0E)
    static let cardBackground = kit(0xFFFFFF, 0x1C1C1F)
    static let sunken = kit(0xEBEBEF, 0x232327)

    /// 旧名字，留给还没换掉的地方。
    static let coral = brand
}

#if os(iOS)
private extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#else
private extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#endif

extension Font {
    /// 分区标题 .headline 15 / 600。
    static let kitSection = Font.headline
    /// 列表正文和金额：圆体、等宽数字。
    static let kitAmount = Font.system(.callout, design: .rounded).weight(.semibold).monospacedDigit()
}

// MARK: - 卡片和按下反馈

/// 一块卡片：内边距 16，圆角 14（iPhone 16），白底。
struct KitCardModifier: ViewModifier {
    var padding: CGFloat = Kit.cardPadding
    var tint: Color? = nil
    var dashed = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous)
                if dashed {
                    shape.fill(Color.cardBackground.opacity(0.6))
                        .overlay(shape.strokeBorder(Color.aiLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                } else if let tint {
                    shape.fill(Color.cardBackground)
                        .overlay(shape.fill(LinearGradient(colors: [tint, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .overlay(shape.strokeBorder(Color.aiLine, lineWidth: 1))
                } else {
                    shape.fill(Color.cardBackground)
                        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                        .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
                }
            }
    }
}

extension View {
    func kitCard(padding: CGFloat = Kit.cardPadding) -> some View { modifier(KitCardModifier(padding: padding)) }
    /// AI 写的东西：靛蓝描边、淡淡的渐变。
    func aiCard() -> some View { modifier(KitCardModifier(tint: .aiSoft)) }
    /// 「问 AI」入口：虚线框。
    func askCard() -> some View { modifier(KitCardModifier(dashed: true)) }

    /// 页面外层：灰底、左右留白、内容最宽 1200。
    func kitPage() -> some View {
        ScrollView {
            self
                .padding(.horizontal, Kit.side)
                .padding(.vertical, Kit.side)
                .frame(maxWidth: 1240)
                .frame(maxWidth: .infinity)
        }
        // 打开页面时停在最上面：上面的卡片晚一点出现（比如连 AI 的提示）也不会把开头挤到工具栏下面。
        .defaultScrollAnchor(.top)
        .background(Color.pageBackground)
    }
}

// MARK: - 当前这边的主色

extension LedgerModel {
    /// 当前这边的点缀色：生活 = 晨光橙，生意 = 青色。按钮、箭头、选中、柱子都用它，别一个个写死橙色。
    var accent: Color { side == .business ? .shop : .brand }
    /// 当前这边的实心按钮底色（上面放白字）。
    var accentSolid: Color { side == .business ? .shopSolid : .brandSolid }
    var accentSoft: Color { side == .business ? .shopSoft : .brandSoft }
}

/// 页面里的主按钮：实心底、白字。按不了的时候用淡主色（40%），字仍然看得清，不会像系统的灰按钮那样「隐形」。
struct SolidButtonStyle: ButtonStyle {
    var color: Color
    var large = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .body.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.85))
            .padding(.horizontal, large ? 16 : 12)
            .frame(minHeight: large ? 32 : 26)
            .background(color.opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: Kit.buttonRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// 卡片、按钮按下缩到 97%，松手复原（不回弹）；打开「减弱动态效果」时只变淡。
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// 小标签：「AI」「你」「留意」「建议」……圆角 5。
struct KitTag: View {
    let text: String
    var color: Color = .fg2
    var background: Color = .sunken

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(background, in: RoundedRectangle(cornerRadius: Kit.tagRadius, style: .continuous))
    }

    static func ai() -> KitTag { KitTag(text: "AI", color: .ai, background: .aiSoft) }
    static func me() -> KitTag { KitTag(text: "你", color: .fg2, background: .sunken) }
}

/// 一行小按钮（接着问、知道了、撤销、删除）。
struct SoftButtonStyle: ButtonStyle {
    var color: Color = .primary
    var background: Color = .sunken
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .frame(minHeight: 24)
            .background(background, in: RoundedRectangle(cornerRadius: Kit.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : enabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
    static var softAI: SoftButtonStyle { SoftButtonStyle(color: .ai, background: .aiSoft) }
    static var softAlert: SoftButtonStyle { SoftButtonStyle(color: .alert, background: .alertSoft) }
}

/// 实心「问 AI」按钮：靛蓝底白字。
struct AISolidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.aiSolid, in: RoundedRectangle(cornerRadius: Kit.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - 点击区和悬停（审查 2026-11-26：30 多处点击区不到 20pt，188 个可点的只有 26 个悬停有反应）

extension View {
    /// 小图标按钮的点击区放到至少 size×size（默认 28），图标本身大小不变。
    func hitArea(_ size: CGFloat = 28) -> some View {
        frame(minWidth: size, minHeight: size).contentShape(Rectangle())
    }

    /// 小图标按钮：鼠标放上去时背后出一个淡淡的圆角底，告诉你能点。iPhone 上什么都不做。
    func hoverBubble(cornerRadius: CGFloat = 7) -> some View { modifier(HoverBubble(cornerRadius: cornerRadius)) }
}

private struct HoverBubble: ViewModifier {
    var cornerRadius: CGFloat
    @State private var hovering = false
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .background(Color.primary.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        #else
        content
        #endif
    }
}

extension View {
    /// 每行右边的「⋯」操作菜单：系统的带边框按钮（24 高、键盘 Tab 能走到、悬停有反应），不画下拉小三角。
    /// 审查 2026-11-26：原来是 36×17 的无边框小图标，Tab 也到不了。
    func actionMenuStyle() -> some View {
        self.menuStyle(.button).buttonStyle(.bordered).menuIndicator(.hidden).fixedSize()
    }
}

/// 实心按钮（.borderedProminent）的底色：跟着当前这边，用暗一档的实心色，白字够清楚。
struct SolidTint: ViewModifier {
    @Environment(LedgerModel.self) private var model: LedgerModel?
    func body(content: Content) -> some View {
        content.tint(model?.accentSolid ?? .brandSolid)
    }
}

extension View {
    func solidTint() -> some View { modifier(SolidTint()) }
    /// 弹窗底部的主按钮（记下、加上、建好了、保存……）：这一边的实心色；按不了时 40% 淡色，看得到在哪（审查 2026-11-26）。
    func sheetPrimary() -> some View { modifier(SheetPrimary()) }
}

struct SheetPrimary: ViewModifier {
    @Environment(LedgerModel.self) private var model: LedgerModel?
    func body(content: Content) -> some View {
        #if os(macOS)
        content.buttonStyle(SolidButtonStyle(color: model?.accentSolid ?? .brandSolid, large: true))
        #else
        content
        #endif
    }
}

/// 开了「减少动态效果」：这一层以下所有动画都换成 0.15 秒的淡入淡出，不弹、不循环。
private struct CalmWhenReduceMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.transaction { t in
            if reduceMotion, t.animation != nil { t.animation = .easeInOut(duration: 0.15) }
        }
    }
}

extension View {
    func calmWhenReduceMotion() -> some View { modifier(CalmWhenReduceMotion()) }
}
