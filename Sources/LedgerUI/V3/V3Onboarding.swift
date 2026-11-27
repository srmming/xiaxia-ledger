#if os(macOS)
import FinanceCore
import SwiftUI

/// 引导 5 步：为什么 → 管哪边 → 想要的 → 有多少 → 连接 AI。每一步都能跳过，前四步不用 AI。
struct V3Onboarding: View {
    @Environment(V3State.self) private var state

    var body: some View {
        let step = state.onboardingStep ?? 0
        ZStack(alignment: .top) {
            LinearGradient(stops: [.init(color: V3.soft, location: 0), .init(color: V3.bg, location: 0.55), .init(color: .white, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            Group {
                switch step {
                case 0: V3IntroStep()
                case 1: V3ChooseStep()
                case 2: V3WishStep()
                case 3: V3AccountsStep()
                default: V3ConnectStep()
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            V3StepBar(step: step).padding(.top, V3Launch.overTitleBar ? 22 : 8)
        }
        .clipped()
    }
}

extension V3State {
    func nextStep() {
        withAnimation(.snappy(duration: 0.3)) {
            if let s = onboardingStep { onboardingStep = s >= 4 ? nil : s + 1 }
        }
        // 走完直接进总览（只管生意的进生意首页）。不替人定目标，想定自己去「目标」页（ming 2026-11-28）。
        if onboardingStep == nil { settleSide() }
    }
    func previousStep() {
        withAnimation(.snappy(duration: 0.3)) {
            if let s = onboardingStep, s > 0 { onboardingStep = s - 1 }
        }
    }
}

private struct V3StepBar: View {
    let step: Int
    static let names = ["为什么", "管哪边", "想要的", "有多少", "连接 AI"]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.names.enumerated()), id: \.offset) { i, name in
                Text((i < step ? "✓ " : "") + name).font(V3.font(13, .bold))
                    .foregroundStyle(i == step ? .white : i < step ? V3.navy : V3.ink2)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(i == step ? V3.navy : .white.opacity(0.7)))
            }
        }
        .accessibilityElement().accessibilityLabel("第 \(step + 1) 步，共 5 步：\(Self.names[step])")
    }
}

/// 引导每一步下面那排按钮：中间只有一个实心的主按钮（旁边可以有「跳过」），「返回」是左边的文字按钮。五步都一样。
private struct V3StepButtons: View {
    @Environment(V3State.self) private var state
    var back = true
    var skipText: String? = "跳过"
    var skipSay = "好，先跳过"
    let next: String
    var nextEnabled = true
    var onNext: () -> Void
    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                if let skipText {
                    Button(skipText) { state.say(skipSay); state.nextStep() }.buttonStyle(.v3(.ghost, .big))
                }
                Button(next, action: onNext).buttonStyle(.v3(.primary, .big)).disabled(!nextEnabled).keyboardShortcut(.defaultAction)
            }
            if back {
                Button { state.previousStep() } label: {
                    Label("返回", systemImage: "chevron.left").font(V3.font(15, .bold)).foregroundStyle(V3.ink2)
                        .padding(.horizontal, 6).padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 1040)
    }
}

private struct V3StepTitle: View {
    let title: String
    let sub: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(V3.font(34, .heavy)).foregroundStyle(V3.ink).multilineTextAlignment(.center)
            if !sub.isEmpty { Text(sub).font(V3.font(16, .regular)).foregroundStyle(V3.ink2).multilineTextAlignment(.center) }
        }
    }
}

// MARK: - 1 开场动画

private struct V3IntroStep: View {
    @Environment(V3State.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    private static let thoughts: [(String, CGFloat, CGFloat, Int)] = [
        ("想换台电脑", -380, -215, 1), ("月底总是不够", 300, -235, 0), ("钱到底花哪了", -455, -70, 2), ("想早点还完信用卡", 410, -95, 3),
        ("想给爸妈换个沙发", -340, 105, 0), ("想有底气辞职", 395, 75, 1), ("存下第一个一万", -80, -285, 2), ("不想再为钱吵架", 130, 170, 3),
        ("想清楚自己有多少", -140, 205, 1), ("想去一次冰岛", 20, -170, 0), ("想财务自由", -500, 235, 3), ("想赚 100 万", 470, 215, 2),
        ("无所谓，先看看", -250, -120, 0), ("不想被账单吓到", 250, -10, 1),
    ]
    private static let chipColors: [Color] = [.white, V3.soft, V3.goodBG, V3.hex(0xFCE4EA)]
    private static let answerDelays: [Double] = [5.5, 6.6, 7.8, 8.8, 9.2]

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished)) { timeline in
                let t = finished ? 99 : timeline.date.timeIntervalSince(start)
                ZStack {
                    // 念头一个个冒出来，再往中间靠拢
                    ForEach(Array(Self.thoughts.enumerated()), id: \.offset) { i, th in
                        let p = min(max((t - Double(i) * 0.09) / 7, 0), 1)
                        let k = Self.kf(p, [(0, 1.15), (0.12, 1), (0.55, 0.93), (0.78, 0.15), (0.86, 0), (1, 0)])
                        Text(th.0).font(V3.font(16, .bold)).foregroundStyle(V3.ink).fixedSize()
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Capsule().fill(Self.chipColors[th.3]).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2)))
                            .background(Capsule().fill(V3.ink).offset(y: 3))
                            .scaleEffect(Self.kf(p, [(0, 0.8), (0.12, 1), (0.55, 1), (0.78, 0.5), (0.86, 0.2), (1, 0.2)]))
                            .opacity(Self.kf(p, [(0, 0), (0.12, 1), (0.55, 1), (0.78, 0.5), (0.86, 0), (1, 0)]))
                            .position(x: g.size.width / 2 + th.1 * k,
                                      y: g.size.height * 0.44 + th.2 * k + Self.kf(p, [(0, 0), (0.12, 0), (0.55, -8), (0.78, 0), (1, 0)]))
                            .accessibilityHidden(true)
                    }
                    Text("你为什么想管钱？").font(V3.font(40, .heavy)).foregroundStyle(V3.ink)
                        .opacity(Self.kf(min(t / 7, 1), [(0, 0), (0.08, 1), (0.62, 1), (0.78, 0), (1, 0)]))
                        .position(x: g.size.width / 2, y: g.size.height * 0.36 + 28)
                    // 一句一句出字，落到使命那句
                    VStack(spacing: 0) {
                        line("分清什么才是你真正想要的，", t, 0).padding(.bottom, 6)
                        line("剩下的，就随它去。", t, 1).padding(.bottom, 20)
                        (Text("找到你") + Text("真正想要的生活").foregroundColor(V3.gold) + Text("，\n再让钱一步步带你过去。"))
                            .font(V3.font(52, .heavy)).foregroundStyle(V3.ink).multilineTextAlignment(.center).lineSpacing(4)
                            .modifier(Appear(p: Self.appear(t, 2))).padding(.bottom, 14)
                        Color.clear.frame(height: 12)
                        Button("开始") { state.say("好，我们聊聊"); state.nextStep() }
                            .buttonStyle(.v3(.primary, .big)).keyboardShortcut(.defaultAction)
                            .modifier(Appear(p: Self.appear(t, 4))).allowsHitTesting(Self.appear(t, 4) > 0.5)
                    }
                    .position(x: g.size.width / 2, y: g.size.height * 0.23 + 170)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(finished ? "再看一遍" : "跳过动画") {
                    if finished { start = Date(); finished = false; scheduleEnd() } else { finished = true }
                }
                .buttonStyle(.v3(.ghost, .small)).padding(.top, V3Launch.overTitleBar ? 20 : 8).padding(.trailing, 26)
            }
        }
        .onAppear {
            if reduceMotion || V3Launch.value("-XiaxiaV3Intro") == "end" { finished = true } else { scheduleEnd() }
        }
    }

    private func scheduleEnd() {
        let began = start
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.4) { if start == began { finished = true } }
    }

    private func line(_ text: String, _ t: Double, _ i: Int) -> some View {
        Text(text).font(V3.font(24, .bold)).foregroundStyle(V3.ink2).modifier(Appear(p: Self.appear(t, i)))
    }

    private static func appear(_ t: Double, _ i: Int) -> Double { min(max((t - answerDelays[i]) / 0.7, 0), 1) }

    private struct Appear: ViewModifier {
        let p: Double
        func body(content: Content) -> some View { content.opacity(p).offset(y: 14 * (1 - p)) }
    }

    /// 关键帧之间平滑过渡。
    static func kf(_ t: Double, _ pts: [(Double, Double)]) -> Double {
        guard let first = pts.first, let last = pts.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for i in 1..<pts.count where t <= pts[i].0 {
            let a = pts[i - 1], b = pts[i]
            let u = (t - a.0) / max(b.0 - a.0, 0.0001)
            let e = u * u * (3 - 2 * u)
            return a.1 + (b.1 - a.1) * e
        }
        return last.1
    }
}

// MARK: - 2 管哪边

private struct V3ChooseStep: View {
    @Environment(V3State.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            // 上下各留一样多的空，内容落在窗口中间偏上
            Spacer(minLength: 0)
            V3StepTitle(title: "你想让我帮你管哪边的钱？", sub: "").padding(.top, V3Launch.overTitleBar ? 70 : 50)
            HStack(spacing: 18) {
                option(.life, "生活为主", "工资、日常花销、存钱、欠款。打开先看「这个月还能随便花多少」。") { V3SceneLife() }
                option(.biz, "生意为主", "一个人开店的小老板。打开先看「这个月真正赚了多少」。") { V3SceneBiz() }
                option(.both, "两边都管", "自己的钱和店里的钱都管，两边分开记，家底加在一起看。") { V3SceneBoth() }
            }
            .frame(width: 1100, height: 350).padding(.top, 20)
            V3StepButtons(skipSay: "好，先两边都管，以后随时能改", next: "下一步") {
                state.say(state.mode == .life ? "好，以生活为主" : state.mode == .biz ? "好，以生意为主" : "小孩子才做选择。两边都管")
                state.nextStep()
            }
            .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func option<Scene: View>(_ mode: V3State.Mode, _ title: String, _ text: String, @ViewBuilder scene: () -> Scene) -> some View {
        V3Option(picked: state.mode == mode) {
            withAnimation(.snappy(duration: 0.18)) { state.mode = mode }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                scene().frame(height: 270).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(V3.ink, lineWidth: 2))
                Text(title).font(V3.font(22, .heavy)).foregroundStyle(V3.ink)
            }
        }
        .help(text)
        .accessibilityLabel("\(title)。\(text)")
    }
}

/// 「管哪边」三张卡上的画：ming 给的三张图。
private struct V3SceneLife: View {
    var body: some View {
        // ming 给的画（2026-11-28）。
        Color.clear.overlay { V3.image("ob-life").resizable().scaledToFill() }
    }
}

private struct V3SceneBiz: View {
    var body: some View {
        // ming 给的画（2026-11-28）。
        Color.clear.overlay { V3.image("ob-biz").resizable().scaledToFill() }
    }
}

private struct V3SceneBoth: View {
    var body: some View {
        // ming 给的画（2026-11-28）。
        Color.clear.overlay { V3.image("ob-both").resizable().scaledToFill() }
    }
}

private struct V3HouseSketch: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 200, y: size.height / 170)
            let ink = GraphicsContext.Shading.color(V3.ink)
            var house = Path()
            house.move(to: CGPoint(x: 34, y: 76)); house.addLine(to: CGPoint(x: 34, y: 160)); house.addLine(to: CGPoint(x: 166, y: 160))
            house.addLine(to: CGPoint(x: 166, y: 76)); house.addLine(to: CGPoint(x: 100, y: 26)); house.closeSubpath()
            ctx.fill(house, with: .color(.white)); ctx.stroke(house, with: ink, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
            var roof = Path()
            roof.move(to: CGPoint(x: 20, y: 84)); roof.addLine(to: CGPoint(x: 100, y: 22)); roof.addLine(to: CGPoint(x: 180, y: 84))
            ctx.stroke(roof, with: ink, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            let win = Path(roundedRect: CGRect(x: 52, y: 96, width: 38, height: 34), cornerRadius: 4)
            ctx.fill(win, with: .color(V3.soft)); ctx.stroke(win, with: ink, lineWidth: 3.5)
            var cross = Path()
            cross.move(to: CGPoint(x: 71, y: 96)); cross.addLine(to: CGPoint(x: 71, y: 130))
            cross.move(to: CGPoint(x: 52, y: 113)); cross.addLine(to: CGPoint(x: 90, y: 113))
            ctx.stroke(cross, with: ink, lineWidth: 2.5)
            let door = Path(roundedRect: CGRect(x: 112, y: 104, width: 34, height: 56), cornerRadius: 4)
            ctx.fill(door, with: .color(V3.sky)); ctx.stroke(door, with: ink, lineWidth: 3.5)
            ctx.fill(Path(ellipseIn: CGRect(x: 135, y: 131, width: 6, height: 6)), with: ink)
        }
        .accessibilityHidden(true)
    }
}

private struct V3ShopSketch: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 200, y: size.height / 170)
            let ink = GraphicsContext.Shading.color(V3.ink)
            let body = Path(roundedRect: CGRect(x: 22, y: 62, width: 156, height: 100), cornerRadius: 6)
            ctx.fill(body, with: .color(.white)); ctx.stroke(body, with: ink, lineWidth: 4)
            var awning = Path()
            awning.move(to: CGPoint(x: 12, y: 30)); awning.addLine(to: CGPoint(x: 188, y: 30)); awning.addLine(to: CGPoint(x: 196, y: 64))
            awning.addLine(to: CGPoint(x: 4, y: 64)); awning.closeSubpath()
            ctx.fill(awning, with: .color(.white))
            for (a, b, c, d) in [(34.0, 56.0, 52.0, 28.0), (78, 100, 100, 78), (122, 144, 148, 126), (166, 188, 196, 174)] {
                var stripe = Path()
                stripe.move(to: CGPoint(x: a, y: 30)); stripe.addLine(to: CGPoint(x: b, y: 30)); stripe.addLine(to: CGPoint(x: c, y: 64))
                stripe.addLine(to: CGPoint(x: d, y: 64)); stripe.closeSubpath()
                ctx.fill(stripe, with: .color(V3.teal))
            }
            ctx.stroke(awning, with: ink, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
            var scallop = Path()
            scallop.move(to: CGPoint(x: 4, y: 64))
            for i in 0..<6 { scallop.addQuadCurve(to: CGPoint(x: 4 + Double(i + 1) * 32, y: 64), control: CGPoint(x: 20 + Double(i) * 32, y: 80)) }
            ctx.fill(scallop, with: .color(.white)); ctx.stroke(scallop, with: ink, lineWidth: 4)
            let win = Path(roundedRect: CGRect(x: 36, y: 92, width: 52, height: 42), cornerRadius: 4)
            ctx.fill(win, with: .color(V3.tealSoft)); ctx.stroke(win, with: ink, lineWidth: 3.5)
            let door = Path(roundedRect: CGRect(x: 116, y: 92, width: 40, height: 70), cornerRadius: 4)
            ctx.fill(door, with: .color(V3.hex(0xA9D9DF))); ctx.stroke(door, with: ink, lineWidth: 3.5)
            ctx.fill(Path(ellipseIn: CGRect(x: 145, y: 127, width: 6, height: 6)), with: ink)
            let sign = Path(roundedRect: CGRect(x: 44, y: 140, width: 36, height: 14), cornerRadius: 4)
            ctx.fill(sign, with: .color(V3.goodBG)); ctx.stroke(sign, with: ink, lineWidth: 2.5)
            ctx.draw(Text("营业中").font(.system(size: 9, weight: .heavy)).foregroundColor(V3.ink), at: CGPoint(x: 62, y: 147))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 3 随便写一句想要的

private struct V3WishStep: View {
    @Environment(V3State.self) private var state
    @State private var text = ""
    @FocusState private var focused: Bool
    private static let examples = ["三年后不用为钱发愁", "想财务自由", "赚到 100 万", "换台好电脑", "把信用卡还清", "开一家自己的店", "无所谓，先看看"]

    var body: some View {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 0) {
            // 上下各留一样多的空，内容落在窗口中间偏上
            Spacer(minLength: 0)
            V3StepTitle(title: "随便写一句你想要的", sub: "").padding(.top, V3Launch.overTitleBar ? 82 : 62)
            TextField("比如：三年后不用为钱发愁", text: $text)
                .textFieldStyle(.plain).font(V3.font(26, .heavy)).foregroundStyle(V3.ink).focused($focused)
                .padding(.horizontal, 26).padding(.vertical, 20)
                .frame(width: 760).v3Sticker().padding(.top, 26)
                .onSubmit { if !clean.isEmpty { save(clean) } }
                .accessibilityLabel("你想要的")
            HStack(spacing: 8) {
                ForEach(Self.examples, id: \.self) { e in
                    V3Chip(text: e, size: 14.5) {
                        withAnimation(.snappy(duration: 0.15)) { text = e }
                        state.say("填好了：\(e)")
                    }
                }
            }
            .frame(width: 900).padding(.top, 18)
            HStack(alignment: .center, spacing: 26) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        V3Ico(emoji: "🧠")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("存进夏夏的记忆").font(V3.font(14, .bold)).foregroundStyle(V3.ink)
                            if !clean.isEmpty { Text("「\(clean)」").font(V3.font(13.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1) }
                        }
                        Spacer(minLength: 6)
                        V3Tag(text: "只留在这台 Mac", tone: .green)
                    }
                    .v3Card(h: 18, v: 14)
                }
            }
            .frame(width: 760).padding(.top, 30)
            V3StepButtons(skipSay: "好，先跳过。哪天想到了再写", next: "记下，下一步", nextEnabled: !clean.isEmpty) { save(clean) }
                .padding(.top, 28)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear { text = state.wish }
    }

    private func save(_ clean: String) {
        state.wish = clean
        // 存进夏夏的记忆，不追问。
        state.patch { try? $0.remember(.topic, topic: "我想要的", line: clean) }
        state.say("记下了：「\(clean)」")
        state.nextStep()
    }
}

// MARK: - 4 先看清你现在有多少

private struct V3AccountsStep: View {
    @Environment(V3State.self) private var state
    /// 账户单子：哪些算有的、哪些算欠的、合计怎么算，都在核心（FinanceCore/StartingAccounts.swift）里。
    @State private var list = StartingAccounts.sample
    @FocusState private var focus: UUID?

    static let symbols: [StartingAccounts.Kind: String] = [
        .daily: "creditcard", .cash: "banknote", .savings: "building.columns", .jar: "star", .lent: "arrow.down.left.circle",
        .credit: "creditcard.and.123", .installment: "calendar", .borrowed: "arrow.up.right.circle", .custom: "plus",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            V3StepTitle(title: "先看清你现在有多少", sub: "")
            HStack(alignment: .top, spacing: 26) {
                left.frame(width: 640)
                right
            }
            .frame(width: 1040).fixedSize(horizontal: false, vertical: true).padding(.top, 22)
            V3StepButtons(skipSay: "好，先跳过。进去以后在「家底」里随时能加", next: "下一步") {
                state.say(list.rows.isEmpty ? "好，先空着" : "好，记下了 \(list.rows.count) 个账户")
                state.nextStep()
            }
            .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var left: some View {
        VStack(spacing: 12) {
            if !list.rows.isEmpty {
                let two = list.rows.count > 4
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: two ? 2 : 1), spacing: two ? 8 : 10) {
                    ForEach(list.rows) { r in row(r, compact: two) }
                }
            }
            if list.hasUnreadable {
                V3Label("有一个数没看懂，写成 1500 这样就行。", size: 13, color: V3.red, weight: .semibold).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                group("我有的", StartingAccounts.Kind.have, trailing: nil)
                group("我欠的", StartingAccounts.Kind.owe, trailing: .custom)
            }
            .v3Card(h: 16, v: 14, radius: 18)
        }
    }

    /// 一组按钮：小标题 + 一行五格等宽的按钮（不够五个的空着；最后一格可以放「自己起名」）。
    private func group(_ title: String, _ kinds: [StartingAccounts.Kind], trailing: StartingAccounts.Kind?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(V3.font(13, .heavy)).foregroundStyle(V3.ink2)
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    if i < kinds.count { addButton(kinds[i]) }
                    else if i == 4, let trailing { addButton(trailing) }
                    else { Color.clear.frame(maxWidth: .infinity).frame(height: 1) }
                }
            }
        }
    }

    private func addButton(_ kind: StartingAccounts.Kind) -> some View {
        Button { add(kind) } label: {
            VStack(spacing: 4) {
                Image(systemName: Self.symbols[kind] ?? "plus").font(.system(size: 17, weight: .semibold)).frame(height: 20)
                Text(kind.title).font(V3.font(12.5, .bold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(V3.navy)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(V3.ink, style: StrokeStyle(lineWidth: 1.5, dash: kind == .custom ? [5, 4] : []))))
            .contentShape(Rectangle())
        }
        .buttonStyle(V3SinkStyle(depth: 2))
        .accessibilityLabel("加一个\(kind.title)")
    }

    private func add(_ kind: StartingAccounts.Kind) {
        do {
            var id: UUID?
            try withAnimation(.spring(duration: 0.35)) { id = try list.add(kind) }
            // 新加的那一行：要自己填名字的先填名字，别的直接填金额
            focus = id
        } catch let e as TrialError { state.fail(e.message) } catch { state.fail("没加上，再试一次") }
    }

    private func row(_ r: StartingAccounts.Row, compact: Bool) -> some View {
        let name = Binding(get: { r.name }, set: { list.rename(r.id, to: $0) })
        let text = Binding(get: { r.text }, set: { list.setText(r.id, $0) })
        return HStack(spacing: 8) {
            V3Ico(emoji: r.kind.emoji, size: compact ? 28 : 36)
            TextField(r.kind.namePrompt, text: name)
                .textFieldStyle(.plain).font(V3.font(14, .bold)).foregroundStyle(V3.ink)
                .frame(minWidth: 40)
                .accessibilityLabel("名字")
                .modifier(V3NameFocus(focus: $focus, id: r.id, on: r.kind.asksName))
            if r.kind == .custom {
                HStack(spacing: 0) {
                    side("有的", !r.owes) { list.setOwes(r.id, false) }
                    side("欠的", r.owes) { list.setOwes(r.id, true) }
                }
                .overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)).clipShape(Capsule())
            }
            Spacer(minLength: 2)
            TextField("0", text: text)
                .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                .font(V3.num(compact ? 17 : 21, .heavy)).foregroundStyle(r.amount == nil ? V3.ink2 : r.owes ? V3.red : V3.navy)
                .frame(width: compact ? 74 : 120)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 9).fill(V3.bg.opacity(0.9)))
                .accessibilityLabel("\(r.displayName)\(r.owes ? "欠多少" : "有多少")")
                .modifier(V3NameFocus(focus: $focus, id: r.id, on: !r.kind.asksName))
            Text("€").font(V3.num(compact ? 15 : 18)).foregroundStyle(r.owes ? V3.red : V3.navy)
            Button { remove(r) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 20, height: 20) }
                .buttonStyle(.plain).accessibilityLabel("删掉\(r.displayName)")
        }
        .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 7 : 11)
        .v3Soft(radius: 18, fill: r.owes ? V3.hex(0xFFF6F5) : .white)
    }

    private func side(_ title: String, _ on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy(duration: 0.15)) { pick() } } label: {
            Text(title).font(V3.font(11.5, .bold)).foregroundStyle(on ? .white : V3.ink)
                .padding(.horizontal, 8).padding(.vertical, 4).background(on ? (title == "欠的" ? V3.red : V3.navy) : .white)
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    private func remove(_ r: StartingAccounts.Row) {
        var gone: (row: StartingAccounts.Row, index: Int)?
        withAnimation(.spring(duration: 0.3)) { gone = list.remove(r.id) }
        guard let gone else { return }
        state.say("删掉了 \(gone.row.displayName)") { list.restore(gone.row, at: gone.index) }
    }

    private var right: some View {
        let totals = list.totals
        return VStack(alignment: .leading, spacing: 6) {
            V3Label("净剩")
            V3Gold(amount: totals.net, size: 64, whole: totals.net.cents % 100 == 0)
            HStack(spacing: 26) {
                V3KV(value: totals.have.v3Short, label: "一共有")
                V3KV(value: totals.owe.v3Short, label: "欠别人", color: V3.red)
            }
            .padding(.top, 4)
        }
        .padding(.init(top: 20, leading: 24, bottom: 34, trailing: 24))
        .frame(maxWidth: .infinity, alignment: .leading)
        .v3Sticker().v3WaveBottom()
        .animation(.snappy(duration: 0.3), value: totals)
    }
}

/// 新加的一行：把光标放进该先填的那一格。
private struct V3NameFocus: ViewModifier {
    var focus: FocusState<UUID?>.Binding
    let id: UUID
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.focused(focus, equals: id) } else { content }
    }
}

// MARK: - 5 连接 AI

private struct V3ConnectStep: View {
    @Environment(V3State.self) private var state
    @State private var checking: String?
    @State private var missing: String?
    private static let options: [(name: String, symbol: String)] = [
        ("Claude", "sparkles"), ("ChatGPT", "bubble.left.and.bubble.right"), ("Gemini", "diamond"), ("别的", "square.grid.2x2"),
        (V3State.aiOwnAPI, "key"), ("还没用过", "leaf"),
    ]
    /// 点了「自己的 API」：下面那一行换成填密钥的。
    @State private var ownOpen = false
    @State private var provider = AIKeyProvider.anthropic
    @State private var key = ""
    @State private var address = ""

    private func picked(_ n: String) -> Bool {
        if n == V3State.aiOwnAPI { return ownOpen || state.ai == n }
        return !ownOpen && (n == "还没用过" ? state.ai == "夏夏自带的" : state.ai == n)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            V3StepTitle(title: "你平时用哪个 AI？", sub: "")
            HStack(spacing: 14) {
                ForEach(Self.options, id: \.name) { o in card(o.name, o.symbol) }
            }
            .padding(.top, 30)
            ZStack {
                if let checking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在看 \(checking) 连上没有…").font(V3.font(15, .bold)).foregroundStyle(V3.ink)
                    }
                } else if let missing {
                    HStack(spacing: 12) {
                        Text("没连上 \(missing)，可能它还没打开。").font(V3.font(15, .bold)).foregroundStyle(V3.red)
                        Button("再试一次") { let m = missing; self.missing = nil; connect(m, retry: true) }.buttonStyle(.v3(.ghost, .small))
                    }
                } else if ownOpen || state.ai == V3State.aiOwnAPI {
                    let _ = state.keyRevision
                    if let saved = state.apiProvider {
                        HStack(spacing: 10) {
                            V3Tag(text: "已填", tone: .green)
                            Text(saved.shortTitle).font(V3.font(15, .bold)).foregroundStyle(V3.ink)
                            Button("删掉") { state.deleteAPIKey() }.buttonStyle(.v3(.ghost, .small))
                        }
                    } else {
                        HStack(spacing: 10) {
                            V3APIKeyFields(provider: $provider, key: $key, address: $address) { saveKey() }
                            Button("存好") { saveKey() }.buttonStyle(.v3(.primary, .small)).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                } else {
                    Text("连上以后，记账、查账都能直接问它").font(V3.font(15, .bold)).foregroundStyle(V3.ink2)
                }
            }
            .frame(height: 40).padding(.top, 30)
            V3StepButtons(skipText: nil, next: "出发") {
                // 没选也能走：等于「还没用过」
                // 「自己的 API」没存密钥也不卡人：当成还没用过，进去以后在设置里再填
                if state.ai == nil || (state.ai == V3State.aiOwnAPI && state.apiProvider == nil) { state.ai = "夏夏自带的" }
                key = ""
                state.say("出发！")
                state.nextStep()
            }
            .padding(.top, 30)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func saveKey() {
        if state.saveAPIKey(key, provider: provider, address: address) { key = "" }
    }

    private func card(_ name: String, _ symbol: String) -> some View {
        let on = picked(name)
        return Button {
            if name == V3State.aiOwnAPI {
                checking = nil; missing = nil
                withAnimation(.snappy) { ownOpen = true; if state.apiProvider != nil { state.ai = name } }
            } else if name == "还没用过" {
                checking = nil; missing = nil
                withAnimation(.snappy) { ownOpen = false; state.ai = "夏夏自带的" }
            } else { ownOpen = false; connect(name) }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).frame(height: 32)
                Text(name).font(V3.font(16, .bold)).lineLimit(1)
            }
            .foregroundStyle(on ? .white : V3.navy)
            .frame(width: 156, height: 124)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(on ? V3.navy : .white)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(V3.ink, lineWidth: 2.5)))
            .overlay(alignment: .topTrailing) {
                if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).padding(10) }
                else if checking == name { ProgressView().controlSize(.small).padding(10) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(V3SinkStyle(depth: 3))
        .accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 试用版里连接是演出来的：不碰这台 Mac 上任何 AI 的设置。Gemini 第一次故意连不上，看看出错时怎么说。
    private func connect(_ name: String, retry: Bool = false) {
        guard checking == nil else { return }
        if name == "别的" {
            missing = nil
            state.say("别的 AI 也行：进去以后在「设置」里连")
            return
        }
        missing = nil
        withAnimation(.snappy) { checking = name; if state.ai == name { state.ai = nil } }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) {
                checking = nil
                if name == "Gemini" && !retry { missing = name } else { state.ai = name }
            }
            if state.ai == name { state.say("连上 \(name) 了") }
        }
    }
}
#endif
