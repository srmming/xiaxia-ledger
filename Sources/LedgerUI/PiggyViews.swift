import AVFoundation
import Combine
import FinanceCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

// 目标页的小金猪（ming 2026-11-23）：每个目标一只。存钱 = 一枚金币从上面掉进投币口，小猪弹一下、「叮」；
// 点小猪（Mac）或摇手机（iPhone）小猪会晃，里面的金币叮叮当当，钱越多声音越满。肚子上的小窗能看到金币堆到多高。
// 全是 SwiftUI 画的，不用图片；声音也是代码现做的（几个金属泛音叠在一起、很快衰减），不带音频文件。

/// 小猪的颜色：大目标金粉色，小目标各一种淡色，存够了是绿色。
struct PiggyPalette {
    var body: Color
    var dark: Color
    var light: Color

    static let main = PiggyPalette(body: .kit(0xF6A5B5, 0xE88DA0), dark: .kit(0xE07A90, 0xC9627A), light: .kit(0xFFD3DC, 0xF5B3C1))
    static let small: [PiggyPalette] = [
        PiggyPalette(body: .kit(0x9CCBF4, 0x6FA9DE), dark: .kit(0x6AA6DD, 0x4E86BE), light: .kit(0xCFE6FB, 0x9AC5EB)),
        PiggyPalette(body: .kit(0xC6B4F2, 0x9F89DD), dark: .kit(0x9D85DE, 0x7C64BF), light: .kit(0xE5DBFB, 0xC1B1EC)),
        PiggyPalette(body: .kit(0xF7C68E, 0xE0A562), dark: .kit(0xE29F55, 0xBF8240), light: .kit(0xFCE2C2, 0xF0C690)),
    ]
    static let done = PiggyPalette(body: .kit(0x9BD8B4, 0x5DB886), dark: .kit(0x5DB886, 0x3E9666), light: .kit(0xCDEEDB, 0x8BD3AA))
}

/// 一只小金猪。fraction = 存了几成（0…1）。dropTrigger 变一次就掉一枚金币进去；shakeTrigger 变一次就晃一下、叮当响。
struct PiggyBankView: View {
    var fraction: Double
    var palette: PiggyPalette = .main
    var size: CGFloat
    var dropTrigger: Int = 0
    var shakeTrigger: Int = 0
    /// 没存够时肚子窗口里的金币闪一下光（大猪用；小猪省电不闪）。
    var sparkle = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coinY: CGFloat = -1
    @State private var coinVisible = false
    @State private var bounce = false

    private var w: CGFloat { size }
    private var h: CGFloat { size * 0.82 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            pig
                .keyframeAnimator(initialValue: Wobble(), trigger: reduceMotion ? 0 : shakeTrigger) { content, v in
                    content
                        .rotationEffect(.degrees(v.angle), anchor: .bottom)
                        .offset(x: v.x, y: v.y)
                } keyframes: { _ in
                    KeyframeTrack(\.angle) {
                        CubicKeyframe(-9, duration: 0.09)
                        CubicKeyframe(8, duration: 0.11)
                        CubicKeyframe(-7, duration: 0.11)
                        CubicKeyframe(5, duration: 0.11)
                        CubicKeyframe(-3, duration: 0.1)
                        CubicKeyframe(0, duration: 0.12)
                    }
                    KeyframeTrack(\.y) {
                        CubicKeyframe(-6, duration: 0.1)
                        CubicKeyframe(0, duration: 0.12)
                        CubicKeyframe(-4, duration: 0.12)
                        CubicKeyframe(0, duration: 0.3)
                    }
                    KeyframeTrack(\.x) {
                        CubicKeyframe(-3, duration: 0.1)
                        CubicKeyframe(3, duration: 0.12)
                        CubicKeyframe(0, duration: 0.42)
                    }
                }
                .scaleEffect(bounce ? 1.06 : 1, anchor: .bottom)
            if coinVisible {
                Coin(size: w * 0.16)
                    .position(x: w * 0.5, y: h * coinY)
                    .transition(.opacity)
            }
        }
        .frame(width: w, height: h)
        .onChange(of: dropTrigger) { _, _ in drop() }
        .accessibilityHidden(true)
    }

    struct Wobble { var angle: Double = 0; var x: CGFloat = 0; var y: CGFloat = 0 }

    /// 一枚金币从上面掉进投币口，小猪弹一下。
    private func drop() {
        guard !reduceMotion else { return }
        coinY = -0.05
        coinVisible = true
        withAnimation(.easeIn(duration: 0.38)) { coinY = 0.2 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.easeOut(duration: 0.1)) { coinVisible = false }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { bounce = true }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { bounce = false }
        }
    }

    private var pig: some View {
        let f = min(max(fraction, 0), 1)
        return ZStack {
            // 地上的影子
            Ellipse().fill(Color.black.opacity(0.10))
                .frame(width: w * 0.62, height: h * 0.07)
                .position(x: w * 0.5, y: h * 0.96)
            // 后面两条腿（深一点）
            leg.fill(palette.dark).frame(width: w * 0.1, height: h * 0.2).position(x: w * 0.36, y: h * 0.84)
            leg.fill(palette.dark).frame(width: w * 0.1, height: h * 0.2).position(x: w * 0.7, y: h * 0.84)
            // 尾巴（左边一个小卷）
            Tail().stroke(palette.dark, style: StrokeStyle(lineWidth: max(2, w * 0.025), lineCap: .round))
                .frame(width: w * 0.12, height: h * 0.14)
                .position(x: w * 0.09, y: h * 0.44)
            // 后面那只耳朵
            Ear().fill(palette.dark).frame(width: w * 0.13, height: h * 0.15).position(x: w * 0.55, y: h * 0.18)
            // 身体
            Ellipse()
                .fill(LinearGradient(colors: [palette.light, palette.body, palette.dark.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.8, height: h * 0.66)
                .position(x: w * 0.48, y: h * 0.52)
            // 背上的高光
            Ellipse().fill(Color.white.opacity(0.35))
                .frame(width: w * 0.32, height: h * 0.1)
                .rotationEffect(.degrees(-8))
                .position(x: w * 0.4, y: h * 0.29)
            // 前面两条腿
            leg.fill(palette.body).frame(width: w * 0.11, height: h * 0.21).position(x: w * 0.27, y: h * 0.86)
            leg.fill(palette.body).frame(width: w * 0.11, height: h * 0.21).position(x: w * 0.62, y: h * 0.86)
            // 肚子上的小窗：看得到金币堆到哪
            BellyWindow(fraction: f, sparkle: sparkle && !reduceMotion)
                .frame(width: w * 0.42, height: h * 0.34)
                .position(x: w * 0.45, y: h * 0.58)
            // 前面那只耳朵
            Ear().fill(palette.body).overlay(Ear().inset(by: w * 0.025).fill(palette.dark.opacity(0.5)))
                .frame(width: w * 0.14, height: h * 0.17).position(x: w * 0.68, y: h * 0.2)
            // 投币口
            Capsule().fill(palette.dark.opacity(0.95))
                .frame(width: w * 0.2, height: max(3, h * 0.035))
                .position(x: w * 0.5, y: h * 0.2)
            // 眼睛
            Circle().fill(Color.kit(0x3A2A30, 0x2A1E23)).frame(width: w * 0.05, height: w * 0.05).position(x: w * 0.72, y: h * 0.4)
            Circle().fill(Color.white).frame(width: w * 0.017, height: w * 0.017).position(x: w * 0.728, y: h * 0.39)
            // 腮红
            Ellipse().fill(Color.kit(0xF26A86, 0xE85574).opacity(0.45))
                .frame(width: w * 0.08, height: h * 0.05).position(x: w * 0.7, y: h * 0.52)
            // 鼻子
            Ellipse().fill(palette.dark)
                .frame(width: w * 0.17, height: h * 0.21)
                .position(x: w * 0.88, y: h * 0.5)
            Ellipse().fill(palette.light.opacity(0.6))
                .frame(width: w * 0.12, height: h * 0.15)
                .position(x: w * 0.89, y: h * 0.49)
            Capsule().fill(palette.dark).frame(width: w * 0.022, height: h * 0.06).position(x: w * 0.865, y: h * 0.5)
            Capsule().fill(palette.dark).frame(width: w * 0.022, height: h * 0.06).position(x: w * 0.915, y: h * 0.5)
        }
        .frame(width: w, height: h)
    }

    private var leg: RoundedRectangle { RoundedRectangle(cornerRadius: w * 0.04, style: .continuous) }
}

/// 尾巴：一个小卷。
private struct Tail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.midY + r.height * 0.1))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.2),
                   control1: CGPoint(x: r.maxX - r.width * 0.3, y: r.midY + r.height * 0.3),
                   control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.5))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY),
                   control1: CGPoint(x: r.minX + r.width * 0.8, y: r.minY - r.height * 0.1),
                   control2: CGPoint(x: r.minX + r.width * 0.9, y: r.maxY))
        return p
    }
}

/// 耳朵：圆角三角形。
private struct Ear: InsettableShape {
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX + r.width * 0.15, y: r.minY), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.2))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.midY))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> Ear { Ear(inset: inset + amount) }
}

/// 肚子上的小窗：里面的金币一层层堆起来，存几成堆几成高。
private struct BellyWindow: View {
    var fraction: Double
    var sparkle: Bool
    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let coin = max(6, s.width / 6)
            let rows = Int(ceil(s.height / (coin * 0.55)))
            let filled = fraction <= 0 ? 0 : max(1, Int((Double(rows) * fraction).rounded()))
            ZStack(alignment: .bottom) {
                Ellipse().fill(Color.kit(0xFFF6F0, 0x2A2326).opacity(0.85))
                ForEach(0..<filled, id: \.self) { row in
                    HStack(spacing: -coin * 0.15) {
                        ForEach(0..<7, id: \.self) { _ in
                            Ellipse().fill(LinearGradient(colors: [Color.kit(0xFFE07A, 0xFFD45A), Color.kit(0xE6A817, 0xD4951A)],
                                                          startPoint: .top, endPoint: .bottom))
                                .overlay(Ellipse().stroke(Color.kit(0xC48A0E, 0xA87508), lineWidth: 0.8))
                                .frame(width: coin, height: coin * 0.55)
                        }
                    }
                    .offset(x: row.isMultiple(of: 2) ? 0 : coin * 0.4, y: -CGFloat(row) * coin * 0.42)
                }
                if sparkle && filled > 0 {
                    SparkleDot().frame(width: coin * 0.7, height: coin * 0.7)
                        .offset(x: coin * 0.6, y: -CGFloat(max(0, filled - 1)) * coin * 0.42 - coin * 0.2)
                }
                // 玻璃的反光
                Ellipse().stroke(Color.white.opacity(0.7), lineWidth: max(1.5, s.width * 0.03))
                Capsule().fill(Color.white.opacity(0.5))
                    .frame(width: s.width * 0.08, height: s.height * 0.35)
                    .rotationEffect(.degrees(20))
                    .offset(x: -s.width * 0.3, y: -s.height * 0.45)
            }
            .frame(width: s.width, height: s.height)
            .clipShape(Ellipse())
        }
    }
}

/// 金币上一闪一闪的小星光。
/// 只在出现后闪几下就停（审查 2026-11-26：小猪一直在动、停不下来）；开了「减少动态效果」就不闪。
private struct SparkleDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var done = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: done || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            let a = done || reduceMotion ? 0 : max(0, sin(t * 2.2))
            Image(systemName: "sparkle").resizable().scaledToFit()
                .foregroundStyle(Color.white)
                .opacity(a)
                .scaleEffect(0.6 + 0.4 * a)
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            done = true
        }
    }
}

/// 一枚金币（带 € 字）。
struct Coin: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color.kit(0xFFE58A, 0xFFDA66), Color.kit(0xE9A915, 0xD8961B)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(Color.kit(0xC48A0E, 0xA87508), lineWidth: max(1, size * 0.07))
            Text("€").font(.system(size: size * 0.55, weight: .heavy, design: .rounded)).foregroundStyle(Color.kit(0xB97E06, 0x8E6105))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

// MARK: - 叮叮当当

/// 小猪的声音：现做的金币声（不带音频文件）。设置里或目标页右上角能关（xiaxia.piggySound）。
@MainActor
enum PiggySound {
    static let storageKey = "xiaxia.piggySound"
    private static var players: [AVAudioPlayer] = []
    private static var cache: [String: Data] = [:]

    static var enabled: Bool { UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true }

    /// 投一枚币：「叮」一声。
    static func drop() {
        play(key: "drop") { wav(clinks: [(0.0, 1.0, 0)], length: 0.5, seed: 7) }
    }

    /// 摇一摇：fraction 越大，金币越多、声音越满；空猪只有一两下空空的声音。
    static func shake(fraction: Double) {
        let level = Int((min(max(fraction, 0), 1) * 4).rounded())   // 0…4
        play(key: "shake\(level)") {
            let count = [2, 5, 9, 14, 20][level]
            var rng = SoundRandom(seed: UInt64(11 + level))
            let clinks: [(Double, Double, Int)] = (0..<count).map { i in
                // 跟着晃的节奏：三下一组往两边撞
                let beat = Double(i % 3) * 0.04 + Double(i / 3) * 0.13
                return (beat + rng.unit() * 0.05, 0.35 + rng.unit() * 0.6, i)
            }
            return wav(clinks: clinks, length: 0.95, seed: UInt64(level))
        }
    }

    private static func play(key: String, make: () -> Data) {
        guard enabled else { return }
        #if os(iOS)
        // 跟着静音键走，不打断别的 app 放的音乐。
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        #endif
        let data = cache[key] ?? make()
        cache[key] = data
        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.volume = 0.6
        players.removeAll { !$0.isPlaying }
        players.append(p)
        p.play()
    }

    /// 几个金属泛音叠起来、很快衰减 = 一声「叮」。clinks：(什么时候, 多响, 第几个)。
    private static func wav(clinks: [(Double, Double, Int)], length: Double, seed: UInt64) -> Data {
        let rate = 44_100.0
        let n = Int(rate * length)
        var samples = [Double](repeating: 0, count: n)
        var rng = SoundRandom(seed: seed &+ 1)
        for (at, amp, _) in clinks {
            let base = 2_600 + rng.unit() * 1_400
            let partials: [(Double, Double, Double)] = [(1.0, 1.0, 0.07), (1.47, 0.6, 0.05), (2.09, 0.45, 0.035), (2.76, 0.3, 0.025)]
            let start = Int(at * rate)
            let span = min(n - start, Int(rate * 0.3))
            guard span > 0 else { continue }
            for k in 0..<span {
                let t = Double(k) / rate
                var v = 0.0
                for (mul, a, tau) in partials { v += a * exp(-t / tau) * sin(2 * .pi * base * mul * t) }
                // 一点点撞击的沙沙声
                if k < 120 { v += (rng.unit() - 0.5) * 0.6 * (1 - Double(k) / 120) }
                samples[start + k] += v * amp * 0.25
            }
        }
        let peak = max(1e-9, samples.map { abs($0) }.max() ?? 1)
        let pcm = samples.map { Int16(max(-1, min(1, $0 / peak * 0.8)) * Double(Int16.max)) }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count * 2))
        d.append(contentsOf: Array("WAVE".utf8)); d.append(contentsOf: Array("fmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count * 2))
        for s in pcm { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }
}

/// 声音里用的固定随机数（每次一样，听着不会忽大忽小）。
private struct SoundRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - 摇手机

#if os(iOS)
extension Notification.Name {
    static let deviceDidShake = Notification.Name("xiaxia.deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}
#endif

extension View {
    /// 摇手机时做点什么（只在 iPhone 上有）。
    func onShake(_ action: @escaping () -> Void) -> some View {
        #if os(iOS)
        onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in action() }
        #else
        self
        #endif
    }
}
