import FinanceCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 夏夏会动的形象。整个 app 只有夏夏一个角色（2026-11-25 ming 定：去掉小橘、小紫、小星），
// 用户可以挑她的样子（MascotLook）：女孩、男孩、成年女、成年男、金渐层猫、西高地白㹴、水豚。名字和性格不变。
//
//   MascotView(pose: .cheer, size: 96)                    全身，会呼吸、摆动、眨眼，带小特效
//   MascotView(size: 28, face: true)                      圆形头像（只露脸），也会眨眼
//   MascotView(size: 64, talking: true)                   说话：嘴一张一合
//   MascotView(pose: base, size: 120, interactive: true)  像宠物：点它有反应、闲着有小动作、没人理会睡着（见 MascotMood）
//
// 图在 Resources/Mascot（原创角色，见 design/mascot/README.md）。某张图缺了就退回同一套的待机图；
// 某个样子整套还没有就用女孩版，所以以后加图只要放进去。打开「减弱动态效果」时不动，只显示静止的图。

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

/// 夏夏的样子（设置里挑，只存在这台设备上，不进账本）。
/// 原始值沿用旧设置 `mascotLook` 里的 girl / boy，所以老用户升级后样子不变，不用搬数据。
enum MascotLook: String, CaseIterable, Identifiable {
    case girl, boy, woman, man, cat, westie, capy

    var id: String { rawValue }
    static let storageKey = "mascotLook"
    /// 用户自己挑过样子（挑过就不再自动换，比如开生意模式时）。
    static let chosenKey = "mascotLookChosen"

    var label: String {
        switch self {
        case .girl: tr("女孩")
        case .boy: tr("男孩")
        case .woman: tr("成年女")
        case .man: tr("成年男")
        case .cat: tr("金渐层猫")
        case .westie: tr("西高地白㹴")
        case .capy: tr("水豚")
        }
    }

    /// 图名前缀：`<前缀>-<动作>.webp`。
    var prefix: String {
        switch self {
        case .girl: "xiaxia"
        case .boy: "xiaxia-boy"
        default: "xiaxia-\(rawValue)"
        }
    }

    var isPet: Bool { self == .cat || self == .westie || self == .capy }
    var isAdult: Bool { self == .woman || self == .man }

    /// 图到了的样子才能挑（宠物画齐前不出现在列表里）。
    static var available: [MascotLook] { allCases.filter { MascotImages.has("\($0.prefix)-idle") } }
    /// 挑样子的界面做好之前，设置和引导里还是只有女孩 / 男孩两个。
    static var kidChoices: [MascotLook] { [.girl, .boy].filter { MascotImages.has("\($0.prefix)-idle") } }
    /// 男生版的图在不在（还没画好时设置里不显示这个开关）。
    static var boyAvailable: Bool { MascotImages.has("xiaxia-boy-idle") }

    /// 存着的值 → 样子。认不出来（比如以后的新样子被旧版写进去）或者图不在，就是女孩。
    static func stored(_ raw: String) -> MascotLook {
        guard let look = MascotLook(rawValue: raw), MascotImages.has("\(look.prefix)-idle") else { return .girl }
        return look
    }

    /// 用户自己挑过样子没有：挑样子的地方会记 `chosenKey`；老版本没有这个记号，但只要存过样子（设置里点过女生 / 男生）
    /// 也算挑过——没动过的人这个键根本不存在。
    static func userChose(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: chosenKey) || defaults.object(forKey: storageKey) != nil
    }

    /// 用户在挑样子的地方选了一个：存下来，并记「自己挑过」。
    static func choose(_ look: MascotLook, _ defaults: UserDefaults = .standard) {
        defaults.set(look.rawValue, forKey: storageKey)
        defaults.set(true, forKey: chosenKey)
    }

    /// 开生意模式时推荐的样子：没自己挑过的女孩 / 男孩换成同性别的成年版；挑过的、宠物、已经是成年版的不动。
    static func businessSuggestion(current: MascotLook, chosen: Bool) -> MascotLook? {
        guard !chosen else { return nil }
        let target: MascotLook? = switch current {
        case .girl: .woman
        case .boy: .man
        default: nil
        }
        guard let target, MascotImages.has("\(target.prefix)-idle") else { return nil }
        return target
    }

    /// 打开生意模式时调用：该换就换，返回换之前的样子（给「换回来」用）；不该换返回 nil。
    @discardableResult
    static func applyBusinessDefault(_ defaults: UserDefaults = .standard) -> MascotLook? {
        let current = stored(defaults.string(forKey: storageKey) ?? MascotLook.girl.rawValue)
        guard let target = businessSuggestion(current: current, chosen: userChose(defaults)) else { return nil }
        defaults.set(target.rawValue, forKey: storageKey)
        return current
    }
}

/// 读图（带缓存，读一次就留着）。
enum MascotImages {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Image?] = [:]

    /// key 是 Resources/Mascot 下的相对路径（不带 .webp），比如 `xiaxia-idle`、`clips/xiaxia-hello/01`。
    static func image(_ key: String) -> Image? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let img = load(key)
        cache[key] = img
        return img
    }

    static func url(_ key: String, ext: String = "webp") -> URL? {
        let parts = key.split(separator: "/").map(String.init)
        let dir = (["Mascot"] + parts.dropLast()).joined(separator: "/")
        return Bundle.module.url(forResource: parts.last, withExtension: ext, subdirectory: dir)
    }

    private static func load(_ key: String) -> Image? {
        guard let url = url(key) else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #else
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #endif
    }

    static func has(_ key: String) -> Bool { image(key) != nil }

    /// 这个样子实际用哪套图：整套还没有就用女孩版。
    static func prefix(_ look: MascotLook) -> String {
        has("\(look.prefix)-idle") ? look.prefix : MascotLook.girl.prefix
    }

    /// 这个样子这个动作实际用哪张图：没有就退回同一套的待机图，不混进别的画风。
    static func key(_ pose: MascotPose, look: MascotLook = .girl) -> String {
        let p = prefix(look)
        let k = "\(p)-\(pose.rawValue)"
        return has(k) ? k : "\(p)-idle"
    }
}

/// 一段逐帧动画（比如女孩版的「打招呼」8 帧）：Resources/Mascot/clips/<名字>/ 里的 01.webp… 和 clip.json。
struct MascotClip: Equatable {
    let name: String
    /// 每一帧的图 key 和停多久（秒）。
    let frames: [(key: String, seconds: Double)]
    var duration: Double { frames.reduce(0) { $0 + $1.seconds } }

    static func == (a: MascotClip, b: MascotClip) -> Bool { a.name == b.name }

    private struct Info: Decodable { let frame_ms: [Int] }
    nonisolated(unsafe) private static var cache: [String: MascotClip?] = [:]
    private static let lock = NSLock()

    static func named(_ name: String) -> MascotClip? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[name] { return hit }
        var clip: MascotClip?
        if let url = MascotImages.url("clips/\(name)/clip", ext: "json"),
           let info = try? JSONDecoder().decode(Info.self, from: Data(contentsOf: url)) {
            let frames = info.frame_ms.enumerated().map { (key: String(format: "clips/\(name)/%02d", $0.offset + 1), seconds: Double($0.element) / 1000) }
            clip = frames.isEmpty ? nil : MascotClip(name: name, frames: frames)
        }
        cache[name] = clip
        return clip
    }

    /// 这个样子做这个动作有没有逐帧动画（现在只有女孩版的 hello、cheer、celebrate〔接金币〕、write）。
    static func `for`(_ pose: MascotPose, look: MascotLook) -> MascotClip? {
        named("\(MascotImages.prefix(look))-\(pose.rawValue)")
    }

    /// 播到 t 秒时是哪一帧；播完停在最后一帧。
    func frame(at t: Double) -> String {
        var left = max(0, t)
        for f in frames {
            if left < f.seconds { return f.key }
            left -= f.seconds
        }
        return frames[frames.count - 1].key
    }
}

struct MascotView: View {
    var pose: MascotPose = .idle
    var size: CGFloat
    /// 只露脸的圆形头像。
    var face = false
    /// 嘴巴一张一合（有说话帧的样子）。
    var talking = false
    /// 关掉就是一张静止的图（列表里很多个头像时用，省电）。
    var animated = true
    /// 像宠物一样能互动：点它、闲着的小动作、没人理会睡着、记账和存钱时的反应（见 MascotMood）。
    /// 只给页面上那个大的夏夏开，小头像不开。
    var interactive = false

    /// 头像圆底的颜色（夏夏的蓝）。
    static let tint = Color(red: 0.30, green: 0.55, blue: 0.90)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MascotLook.storageKey) private var lookRaw = MascotLook.girl.rawValue
    private var look: MascotLook { MascotLook.stored(lookRaw) }
    private var prefix: String { MascotImages.prefix(look) }
    /// 每个形象的节奏错开一点，几个一起出现时不会齐步走。
    @State private var seed = Double.random(in: 0...10)

    init(pose: MascotPose = .idle, size: CGFloat, face: Bool = false,
         talking: Bool = false, animated: Bool = true, interactive: Bool = false) {
        self.pose = pose
        self.size = size
        self.face = face
        self.talking = talking
        self.animated = animated
        self.interactive = interactive
    }

    private var mood: MascotMood? { interactive && animated && !reduceMotion ? MascotMood.shared : nil }
    /// 现在显示的动作：互动的夏夏可能被「点了一下」「记了一笔」「睡着了」临时盖过去。
    private var shownPose: MascotPose { mood?.pose(base: pose) ?? pose }

    var body: some View {
        let still = reduceMotion || !animated
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate + seed
            Group {
                if face { faceView(t) } else { bodyView(t, now: context.date) }
            }
        }
        .frame(width: size, height: size)
        .id("\(prefix)-\(shownPose.rawValue)-\(face)")
        .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))
        .contentShape(Rectangle())
        // 互动的夏夏是一个按钮（读屏和键盘也能「摸摸夏夏」）；别的地方只是装饰，读屏跳过。
        .modifier(MascotInteraction(mood: mood, look: look))
    }

    // MARK: 用哪一帧

    private var baseKey: String { MascotImages.key(shownPose, look: look) }

    /// 眨眼：大约每 3.7 秒眨一下，偶尔连眨两下。只有待机图有闭眼帧。
    private func blinking(_ t: Double) -> Bool {
        guard t > 0 else { return false }
        let cycle = 3.7
        let p = t.truncatingRemainder(dividingBy: cycle)
        let n = Int(t / cycle)
        if p < 0.12 { return true }
        return n % 3 == 0 && p > 0.24 && p < 0.34
    }

    private var talkKeyAvailable: Bool { MascotImages.has("\(prefix)-talk") && baseKey.hasSuffix("-idle") }

    /// 说话：不规则地一张一合，像在念字。
    private func mouthOpen(_ t: Double) -> Bool {
        guard talking, t > 0, talkKeyAvailable else { return false }
        let s = sin(t * 13) + 0.6 * sin(t * 7.3 + 1)
        return s > 0.15
    }

    private func frameKey(_ t: Double, now: Date = Date()) -> String {
        if let m = mood?.moment, let clip = m.clip, t > 0 { return clip.frame(at: now.timeIntervalSince(m.start)) }
        if mouthOpen(t) { return "\(prefix)-talk" }
        if blinking(t), MascotImages.has("\(prefix)-blink"), baseKey.hasSuffix("-idle") {
            return "\(prefix)-blink"
        }
        return baseKey
    }

    // MARK: 动起来

    /// 每个动作的精神头：跳多高、晃多大。
    private var energy: (hop: Double, sway: Double, breath: Double, speed: Double) {
        let e: (hop: Double, sway: Double, breath: Double, speed: Double) = switch shownPose {
        case .cheer, .celebrate, .hello: (0.05, 3.0, 0.016, 1.6)
        case .worried: (0.0, 1.0, 0.012, 2.4)
        case .sleep: (0.0, 0.6, 0.03, 0.55)
        case .calm, .write: (0.0, 0.8, 0.012, 0.8)
        case .sharp: (0.0, 1.6, 0.012, 1.0)
        default: (0.012, 1.4, 0.014, 1.0)
        }
        // 各个样子的脾气：猫慢一点轻一点，狗蹦得高、快，水豚几乎不动。
        let k: (hop: Double, sway: Double, speed: Double) = switch look {
        case .cat: (0.6, 0.8, 0.7)
        case .westie: (1.5, 1.2, 1.3)
        case .capy: (0.2, 0.3, 0.6)
        default: (1, 1, 1)
        }
        return (e.hop * k.hop, e.sway * k.sway, e.breath, e.speed * k.speed)
    }

    /// 成年版是细长的全身图，放进小地方会缩成一条：小于 200 时只露到膝盖，小于 100（卡片角落）只露到腰（放大、顶端对齐）。
    private var zoom: CGFloat { guard look.isAdult else { return 1 }; return size < 100 ? 2.1 : size < 200 ? 1.5 : 1 }

    @ViewBuilder
    private func bodyView(_ t: Double, now: Date) -> some View {
        let e = energy
        let w = t * e.speed
        let playingClip = mood?.moment?.clip != nil
        let breath = playingClip ? 1 : 1 + e.breath * sin(w * 2 * .pi / 3.2)
        let hop = playingClip ? 0 : e.hop > 0 ? -abs(sin(w * .pi / 0.9)) * e.hop * size : -0.012 * size * sin(w * 2 * .pi / 3.2)
        let sway = playingClip ? 0 : e.sway * sin(w * 2 * .pi / 4.4)
        let shiver = shownPose == .worried ? sin(t * 40) * size * 0.004 : 0
        ZStack {
            MascotEffects(pose: shownPose, t: t, size: size).zIndex(0)
            if let img = MascotImages.image(frameKey(t, now: now)) {
                img.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * zoom, height: size * zoom)
                    .offset(y: (zoom - 1) * size / 2)
                    .scaleEffect(x: 2 - breath, y: breath, anchor: .bottom)
                    .rotationEffect(.degrees(sway), anchor: .bottom)
                    .offset(x: shiver, y: hop)
                    .frame(width: size, height: size)
                    .clipped()
            }
            MascotEffects(pose: shownPose, t: t, size: size, front: true)
        }
    }

    @ViewBuilder
    private func faceView(_ t: Double) -> some View {
        let key = frameKey(t)
        let f = MascotData.faces[baseKey] ?? MascotData.faces["\(prefix)-idle"] ?? (0.5, 0.4, 0.4)
        let scale = 1 / f.size
        let tilt = t > 0 ? 2.5 * sin(t * 2 * .pi / 5) : 0
        ZStack {
            Circle().fill(Self.tint.opacity(0.18))
            if let img = MascotImages.image(key) {
                img.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * scale, height: size * scale)
                    .offset(x: (0.5 - f.x) * size * scale, y: (0.5 - f.y) * size * scale)
                    .rotationEffect(.degrees(tilt))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Self.tint.opacity(0.45), lineWidth: max(1, size / 28)))
    }
}

/// 互动的夏夏：点它、鼠标移上去会醒；出现时开始计时（闲着的小动作、没人理会睡着）。
private struct MascotInteraction: ViewModifier {
    let mood: MascotMood?
    let look: MascotLook

    func body(content: Content) -> some View {
        if let mood {
            Button { withAnimation(.spring(duration: 0.35, bounce: 0.4)) { mood.poke() } } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("摸摸夏夏"))
                .accessibilityHint(tr("夏夏会回应你一下"))
                #if os(macOS)
                .onHover { inside in if inside { mood.wake() } }
                #endif
                .onAppear { mood.start() }
        } else {
            content.accessibilityHidden(true)
        }
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
