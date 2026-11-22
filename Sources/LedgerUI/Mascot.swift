import FinanceCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 夏夏和三个 AI 伙伴的会动的形象。
//
//   MascotView(.xiaxia, pose: .cheer, size: 96)          全身，会呼吸、摆动、眨眼，带小特效
//   MascotView(.orange, size: 28, face: true)            圆形头像（只露脸），也会眨眼
//   MascotView(.xiaxia, size: 64, talking: true)         说话：嘴一张一合
//
// 图在 Resources/Mascot（ChatGPT 画的原创角色，见 design/mascot/README.md）。
// 一张图缺了就退回这个角色的待机图，所以以后加动作只要放图进去。
// 打开「减弱动态效果」时不动，只显示静止的图。

/// 谁。夏夏是主角；另外三个是 AI 工具的小伙伴，哪个 AI 在干活就出来哪个。
enum MascotCharacter: String, CaseIterable, Identifiable {
    /// 夏夏：蓝发鲸鱼娘，抱着小算盘。
    case xiaxia
    /// 小橘：橘发书本少女，Claude 系的伙伴。
    case orange
    /// 小星：星空少女，Gemini 和其它 AI 的伙伴。
    case star
    /// 小紫：小龙角少女，Codex / GPT 的伙伴。
    case lilac

    var id: String { rawValue }

    var name: String {
        switch self {
        case .xiaxia: "夏夏"
        case .orange: "小橘"
        case .star: "小星"
        case .lilac: "小紫"
        }
    }

    /// 头像圆底的颜色。
    var tint: Color {
        switch self {
        case .xiaxia: Color(red: 0.30, green: 0.55, blue: 0.90)
        case .orange: Color(red: 0.95, green: 0.55, blue: 0.24)
        case .star: Color(red: 0.48, green: 0.36, blue: 0.88)
        case .lilac: Color(red: 0.72, green: 0.61, blue: 0.91)
        }
    }

    #if os(macOS)
    /// 对话栏用哪个 AI 回答，就由哪个伙伴陪着。
    static func of(_ engine: ChatEngine) -> MascotCharacter {
        switch engine {
        case .claude: .orange
        case .codex: .lilac
        case .hermes: .star
        }
    }
    #endif

    static func of(_ app: AIApp) -> MascotCharacter {
        switch app {
        case .claudeDesktop, .claudeCode: .orange
        case .codex: .lilac
        case .cursor, .gemini: .star
        }
    }

    /// 改动记录上的作者名（「Claude」「Codex」「Hermes」…）对应的伙伴；认不出来就是夏夏自己。
    static func of(author: String) -> MascotCharacter {
        let a = author.lowercased()
        if a.contains("claude") { return .orange }
        if a.contains("codex") || a.contains("gpt") || a.contains("openai") { return .lilac }
        if a.contains("gemini") || a.contains("hermes") || a.contains("cursor") || a.contains("deepseek") { return .star }
        return .xiaxia
    }
}

/// 什么动作。
enum MascotPose: String, CaseIterable {
    /// 待机：抱着算盘微笑（会眨眼）。
    case idle
    /// 文静：安静看账本。
    case calm
    /// 打气：举拳头。
    case cheer
    /// 毒舌：抱手斜眼。
    case sharp
    /// 在想：托下巴。
    case think
    /// 在记账：拿笔写本子。
    case write
    /// 担心：钱花超了，抱着空钱包。
    case worried
    /// 庆祝：存钱成功，举着存钱罐。
    case celebrate
    /// 睡着了：没数据、空页面。
    case sleep
    /// 打招呼。
    case hello
}

extension Persona {
    /// 四种性格各自的样子。
    var mascotPose: MascotPose {
        switch self {
        case .gentle: .idle
        case .sharp: .sharp
        case .calm: .calm
        case .cheer: .cheer
        }
    }
}

/// 读图（带缓存，读一次就留着）。
enum MascotImages {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Image?] = [:]

    static func image(_ key: String) -> Image? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let img = load(key)
        cache[key] = img
        return img
    }

    private static func load(_ key: String) -> Image? {
        guard let url = Bundle.module.url(forResource: key, withExtension: "webp", subdirectory: "Mascot") else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #else
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #endif
    }

    static func has(_ key: String) -> Bool { image(key) != nil }

    /// 这个角色这个动作实际用哪张图：没有就退回待机图。
    static func key(_ character: MascotCharacter, _ pose: MascotPose) -> String {
        let k = "\(character.rawValue)-\(pose.rawValue)"
        return has(k) ? k : "\(character.rawValue)-idle"
    }
}

struct MascotView: View {
    var character: MascotCharacter = .xiaxia
    var pose: MascotPose = .idle
    var size: CGFloat
    /// 只露脸的圆形头像。
    var face = false
    /// 嘴巴一张一合（有说话帧的角色）。
    var talking = false
    /// 关掉就是一张静止的图（列表里很多个头像时用，省电）。
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 每个形象的节奏错开一点，几个一起出现时不会齐步走。
    @State private var seed = Double.random(in: 0...10)

    init(_ character: MascotCharacter = .xiaxia, pose: MascotPose = .idle, size: CGFloat, face: Bool = false,
         talking: Bool = false, animated: Bool = true) {
        self.character = character
        self.pose = pose
        self.size = size
        self.face = face
        self.talking = talking
        self.animated = animated
    }

    var body: some View {
        let still = reduceMotion || !animated
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate + seed
            Group {
                if face { faceView(t) } else { bodyView(t) }
            }
        }
        .frame(width: size, height: size)
        .id("\(character.rawValue)-\(pose.rawValue)-\(face)")
        .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))
        .accessibilityHidden(true)
    }

    // MARK: 用哪一帧

    private var baseKey: String { MascotImages.key(character, pose) }

    /// 眨眼：大约每 3.7 秒眨一下，偶尔连眨两下。只有待机图有闭眼帧。
    private func blinking(_ t: Double) -> Bool {
        guard t > 0 else { return false }
        let cycle = 3.7
        let p = t.truncatingRemainder(dividingBy: cycle)
        let n = Int(t / cycle)
        if p < 0.12 { return true }
        return n % 3 == 0 && p > 0.24 && p < 0.34
    }

    private var talkKeyAvailable: Bool { MascotImages.has("\(character.rawValue)-talk") && baseKey.hasSuffix("-idle") }

    /// 说话：不规则地一张一合，像在念字。
    private func mouthOpen(_ t: Double) -> Bool {
        guard talking, t > 0, talkKeyAvailable else { return false }
        let s = sin(t * 13) + 0.6 * sin(t * 7.3 + 1)
        return s > 0.15
    }

    private func frameKey(_ t: Double) -> String {
        if mouthOpen(t) { return "\(character.rawValue)-talk" }
        if blinking(t), MascotImages.has("\(character.rawValue)-blink"), baseKey.hasSuffix("-idle") {
            return "\(character.rawValue)-blink"
        }
        return baseKey
    }

    // MARK: 动起来

    /// 每个动作的精神头：跳多高、晃多大。
    private var energy: (hop: Double, sway: Double, breath: Double, speed: Double) {
        switch pose {
        case .cheer, .celebrate, .hello: (0.05, 3.0, 0.016, 1.6)
        case .worried: (0.0, 1.0, 0.012, 2.4)
        case .sleep: (0.0, 0.6, 0.03, 0.55)
        case .calm, .write: (0.0, 0.8, 0.012, 0.8)
        case .sharp: (0.0, 1.6, 0.012, 1.0)
        default: (0.012, 1.4, 0.014, 1.0)
        }
    }

    @ViewBuilder
    private func bodyView(_ t: Double) -> some View {
        let e = energy
        let w = t * e.speed
        let breath = 1 + e.breath * sin(w * 2 * .pi / 3.2)
        let hop = e.hop > 0 ? -abs(sin(w * .pi / 0.9)) * e.hop * size : -0.012 * size * sin(w * 2 * .pi / 3.2)
        let sway = e.sway * sin(w * 2 * .pi / 4.4)
        let shiver = pose == .worried ? sin(t * 40) * size * 0.004 : 0
        ZStack {
            MascotEffects(pose: pose, t: t, size: size).zIndex(0)
            if let img = MascotImages.image(frameKey(t)) {
                img.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .scaleEffect(x: 2 - breath, y: breath, anchor: .bottom)
                    .rotationEffect(.degrees(sway), anchor: .bottom)
                    .offset(x: shiver, y: hop)
            }
            MascotEffects(pose: pose, t: t, size: size, front: true)
        }
    }

    @ViewBuilder
    private func faceView(_ t: Double) -> some View {
        let key = frameKey(t)
        let f = MascotData.faces[baseKey] ?? MascotData.faces["\(character.rawValue)-idle"] ?? (0.5, 0.4, 0.4)
        let scale = 1 / f.size
        let tilt = t > 0 ? 2.5 * sin(t * 2 * .pi / 5) : 0
        ZStack {
            Circle().fill(character.tint.opacity(0.18))
            if let img = MascotImages.image(key) {
                img.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * scale, height: size * scale)
                    .offset(x: (0.5 - f.x) * size * scale, y: (0.5 - f.y) * size * scale)
                    .rotationEffect(.degrees(tilt))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(character.tint.opacity(0.45), lineWidth: max(1, size / 28)))
    }
}

/// 形象身边飘的小东西：星星、金币、汗珠、Zzz、泡泡。只在全身形象、够大时画。
private struct MascotEffects: View {
    let pose: MascotPose
    let t: Double
    let size: CGFloat
    var front = false

    private struct Particle {
        var symbol: String
        var color: Color
        var x: CGFloat      // 起点（-0.5…0.5，按宽）
        var y: CGFloat
        var rise: CGFloat   // 一轮往上飘多少（负数往下掉）
        var drift: CGFloat
        var period: Double
        var phase: Double
        var scale: CGFloat
    }

    private static let gold = Color(red: 0.98, green: 0.76, blue: 0.24)
    private static let pink = Color(red: 0.98, green: 0.52, blue: 0.66)
    private static let aqua = Color(red: 0.45, green: 0.78, blue: 0.98)

    private var particles: [Particle] {
        switch pose {
        case .cheer, .hello:
            return [
                .init(symbol: "sparkle", color: Self.gold, x: -0.38, y: -0.2, rise: 0.12, drift: 0.02, period: 1.6, phase: 0, scale: 0.11),
                .init(symbol: "sparkle", color: Self.gold, x: 0.36, y: -0.28, rise: 0.12, drift: -0.02, period: 1.9, phase: 0.6, scale: 0.09),
                .init(symbol: pose == .hello ? "heart.fill" : "star.fill", color: pose == .hello ? Self.pink : Self.gold,
                      x: 0.32, y: 0.05, rise: 0.2, drift: 0.03, period: 2.3, phase: 1.1, scale: 0.08),
            ]
        case .celebrate:
            var list: [Particle] = []
            for i in 0..<6 {
                let even = i % 2 == 0
                let x: CGFloat = CGFloat(i) / 5.0 - 0.5
                let period: Double = 2.2 + Double(i % 3) * 0.3
                let phase: Double = Double(i) * 0.37
                list.append(Particle(symbol: even ? "eurosign.circle.fill" : "sparkle", color: Self.gold,
                                     x: x, y: -0.48, rise: -0.7, drift: even ? 0.04 : -0.04,
                                     period: period, phase: phase, scale: even ? 0.1 : 0.08))
            }
            return list
        case .worried:
            return [.init(symbol: "drop.fill", color: Self.aqua, x: 0.2, y: -0.3, rise: -0.1, drift: 0, period: 1.4, phase: 0, scale: 0.08)]
        case .sleep:
            return [
                .init(symbol: "zzz", color: Color.fg2, x: 0.22, y: -0.18, rise: 0.22, drift: 0.08, period: 3.0, phase: 0, scale: 0.12),
                .init(symbol: "zzz", color: Color.fg3, x: 0.22, y: -0.18, rise: 0.22, drift: 0.08, period: 3.0, phase: 1.5, scale: 0.09),
            ]
        case .think:
            return [
                .init(symbol: "circle.fill", color: Self.aqua.opacity(0.7), x: 0.28, y: -0.15, rise: 0.18, drift: 0.04, period: 2.4, phase: 0, scale: 0.045),
                .init(symbol: "circle.fill", color: Self.aqua.opacity(0.6), x: 0.34, y: -0.1, rise: 0.2, drift: 0.02, period: 2.4, phase: 1.2, scale: 0.035),
            ]
        case .calm, .idle:
            return [
                .init(symbol: "circle", color: Self.aqua.opacity(0.8), x: -0.36, y: 0.1, rise: 0.3, drift: 0.03, period: 3.4, phase: 0, scale: 0.05),
                .init(symbol: "circle", color: Self.aqua.opacity(0.6), x: 0.38, y: 0.2, rise: 0.3, drift: -0.03, period: 3.9, phase: 1.7, scale: 0.04),
            ]
        case .write:
            return [.init(symbol: "eurosign.circle.fill", color: Self.gold, x: 0.36, y: -0.05, rise: 0.15, drift: 0.02, period: 2.6, phase: 0.4, scale: 0.08)]
        case .sharp:
            return [.init(symbol: "exclamationmark", color: Color.alert, x: 0.34, y: -0.3, rise: 0.03, drift: 0, period: 1.2, phase: 0, scale: 0.09)]
        }
    }

    var body: some View {
        if size >= 64, t > 0 {
            ZStack {
                ForEach(Array(particles.enumerated()), id: \.offset) { i, p in
                    // 前后两层：一半画在人物前面、一半在后面，看起来有纵深
                    if (i % 2 == 1) == front {
                        let k = ((t + p.phase).truncatingRemainder(dividingBy: p.period)) / p.period
                        let fade = sin(k * .pi)
                        Image(systemName: p.symbol)
                            .font(.system(size: size * p.scale, weight: .bold))
                            .foregroundStyle(p.color)
                            .opacity(fade)
                            .scaleEffect(0.6 + 0.4 * fade)
                            .rotationEffect(.degrees(p.symbol == "eurosign.circle.fill" ? k * 360 : 0))
                            .offset(x: (p.x + p.drift * sin(k * 2 * .pi)) * size, y: (p.y - p.rise * k) * size)
                    }
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
    }
}
