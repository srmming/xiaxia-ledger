import Foundation
import Observation

/// 夏夏像宠物一样的反应（第一版 6 个，2026-11-25 ming 定）。全 app 一个，界面上互动的那个夏夏读它：
/// 1. 点它：蹦一下，换成打招呼或欢呼；3 秒里连点 5 下，换成毒舌瞪你。
/// 2. 闲着时：每隔 9–16 秒做个小动作（歪头想一想、安静一下）。
/// 3. 没人理：2 分钟没动静就睡着（冒 Zzz）；点它、鼠标移上去、记账就醒，先打个招呼。
/// 4. 记账：记下一笔后拿笔写一下，再点头欢呼。
/// 5. 存钱或回本：跳起来撒金币。
/// 6. 花超了：页面本来就给「担心」这个动作（基础动作），这里不盖过它，只在上面叠临时反应。
/// 不做喂食、心情值：不存任何数据，退出 app 就忘。打开「减弱动态效果」时界面不读它（MascotView 里判断）。
@MainActor @Observable
final class MascotMood {
    static let shared = MascotMood()

    /// 一个临时反应：显示哪个动作、有没有逐帧动画、从什么时候到什么时候。
    struct Moment: Equatable {
        var pose: MascotPose
        var clip: MascotClip?
        var start: Date
        var until: Date
    }

    enum Event: Hashable {
        /// 记了一笔。
        case recorded
        /// 存进目标、目标存满。
        case saved
        /// 生意回本。
        case recovered
    }

    private(set) var moment: Moment?
    private(set) var asleep = false
    private(set) var lastActivity: Date

    /// 测试里换成假的钟和固定的随机数。
    var now: () -> Date
    var random: (ClosedRange<Double>) -> Double
    /// 现在是哪个样子（决定有没有逐帧动画可播）。
    var look: () -> MascotLook = { MascotLook.stored(UserDefaults.standard.string(forKey: MascotLook.storageKey) ?? "") }

    static let sleepAfter: TimeInterval = 120
    /// 同一类事件 3 秒内只反应一次（导入 100 笔时不会庆祝 100 次）。
    static let cooldown: TimeInterval = 3

    private var queue: [(pose: MascotPose, seconds: Double)] = []
    private var pokes: [Date] = []
    private var lastEvent: [Event: Date] = [:]
    private var nextFidget: Date
    private var timer: Timer?

    init(now: @escaping () -> Date = Date.init, random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.now = now
        self.random = random
        let t = now()
        lastActivity = t
        nextFidget = t.addingTimeInterval(12)
    }

    /// 页面给的基础动作，被临时反应或睡着盖过。
    func pose(base: MascotPose) -> MascotPose {
        if let moment { return moment.pose }
        return asleep ? .sleep : base
    }

    // MARK: 事件

    /// 点了它一下。
    func poke() {
        let t = now()
        pokes = pokes.filter { t.timeIntervalSince($0) < 3 } + [t]
        let wasAsleep = asleep
        touch(t)
        if wasAsleep { return } // 醒来时已经在打招呼了
        if moment?.pose == .sharp { return } // 正瞪着你呢，再点也不换
        if pokes.count >= 5 {
            pokes = []
            show([(.sharp, 1.8)])
        } else {
            show([(random(0...1) < 0.5 ? .hello : .cheer, 1.5)])
        }
    }

    /// 鼠标移上去、页面有动静：只是把它叫醒，不另外做动作。
    func wake() { touch(now()) }

    /// 账本里发生的事。
    func note(_ event: Event) {
        let t = now()
        if let last = lastEvent[event], t.timeIntervalSince(last) < Self.cooldown { return }
        lastEvent[event] = t
        touch(t)
        switch event {
        case .recorded: show([(.write, 1.0), (.cheer, 1.0)])
        case .saved, .recovered: show([(.celebrate, 2.5)])
        }
    }

    // MARK: 时间往前走

    /// 每秒走一次：反应播完换下一个、闲着做小动作、没人理就睡。
    func tick() {
        let t = now()
        if let m = moment, t >= m.until {
            moment = nil
            if !queue.isEmpty { begin(queue.removeFirst(), at: t) }
        }
        if !asleep, moment == nil, t.timeIntervalSince(lastActivity) >= Self.sleepAfter {
            asleep = true
            queue = []
            return
        }
        if !asleep, moment == nil, t >= nextFidget {
            let fidgets: [MascotPose] = [.think, .calm, .hello]
            let i = min(fidgets.count - 1, Int(random(0...Double(fidgets.count - 1)).rounded()))
            begin((fidgets[i], 1.6), at: t)
            nextFidget = t.addingTimeInterval(random(9...16))
        }
    }

    /// 界面上出现互动的夏夏时开始每秒走一次（只开一个计时器）。
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: 内部

    private func touch(_ t: Date) {
        lastActivity = t
        nextFidget = t.addingTimeInterval(random(9...16))
        if asleep {
            asleep = false
            show([(.hello, 1.4)])
        }
    }

    private func show(_ steps: [(pose: MascotPose, seconds: Double)]) {
        guard let first = steps.first else { return }
        queue = Array(steps.dropFirst())
        begin(first, at: now())
    }

    private func begin(_ step: (pose: MascotPose, seconds: Double), at t: Date) {
        // 有逐帧动画的就播动画，时长按动画来（不短于原定的）。
        let clip = MascotClip.for(step.pose, look: look())
        let seconds = max(step.seconds, clip?.duration ?? 0)
        moment = Moment(pose: step.pose, clip: clip, start: t, until: t.addingTimeInterval(seconds))
    }
}
