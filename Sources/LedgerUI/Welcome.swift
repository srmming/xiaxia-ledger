import FinanceCore
import SwiftUI

// 第一次打开（账本里还没有账户、没有流水）的开始引导。样子照 ming 给的稿（design/mockups/welcome-ming-2026-11-22.png）：
// 左边一大块是夏夏（会动、会说话的气泡、飘着的泡泡），右边是三步：① 账本 ② 账户 ③ 连接 AI（只在 Mac）。
// 每一步点选就行，也能自己加。选的账本和账户在进第三步前写进账本（进改动记录，能撤销）。「以后再说」随时能跳过。
// 第三步问「你平时用哪个 AI」，夏夏自己看连没连上；给一段指令粘给 AI，由 AI 连上、问「今天花了什么」记第一笔；
// app 等到 AI 真的来读账本、记下第一笔，就撒花说恭喜。

extension LedgerModel {
    static let welcomeDoneKey = "xiaxia.welcomeDone"

    /// 要不要出开始引导：真账本、还是空的、以前没走过。启动参数 -XiaxiaWelcome 强制出（截图、检查用）。
    func showWelcomeIfNeeded() {
        if ProcessInfo.processInfo.arguments.contains("-XiaxiaWelcome") { showWelcome = true; return }
        guard !usesSampleData, loadError == nil, sheet == nil,
              !UserDefaults.standard.bool(forKey: Self.welcomeDoneKey),
              ledger.accounts.isEmpty, ledger.transactions.isEmpty else { return }
        showWelcome = true
    }

    func finishWelcome() {
        UserDefaults.standard.set(true, forKey: Self.welcomeDoneKey)
        // 引导里已经问过连 AI 了，别再弹一次。
        UserDefaults.standard.set(true, forKey: "xiaxia.aiSetupShown")
        showWelcome = false
    }
}

struct WelcomeView: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    enum Step: Int { case hello, books, accounts, ai, done }

    struct Choice: Identifiable, Hashable {
        var name: String
        var glyph: XiaGlyph?
        var symbol: String = "circle"
        var bookKind: BookKind = .personal
        var accountKind: AccountKind = .bank
        var id: String { name }
    }

    /// 第三步问的是「你平时用哪个 AI」，不是「用哪种接法」：接法（写哪个工具的设置）由夏夏自己决定。
    enum AIFamily: String, CaseIterable, Identifiable {
        case claude, chatgpt, gemini, other, newbie
        var id: String { rawValue }
        var title: String {
            switch self {
            case .claude: "Claude"
            case .chatgpt: "ChatGPT"
            case .gemini: "Gemini"
            case .other: "DeepSeek 或别的"
            case .newbie: "还没用过 AI"
            }
        }
        /// 这一家在 Mac 上能接本机账本的工具。
        var apps: [AIApp] {
            switch self {
            case .claude, .newbie: [.claudeDesktop, .claudeCode]
            case .chatgpt: [.codex]
            case .gemini: [.gemini]
            case .other: [.hermes, .cursor]
            }
        }
        /// 出来打招呼的伙伴。
        var partner: MascotCharacter {
            switch self {
            case .claude, .newbie: .orange
            case .chatgpt: .lilac
            case .gemini, .other: .star
            }
        }
        /// 没装的话装哪个、去哪下。
        var install: (name: String, url: String) {
            switch self {
            case .claude, .newbie: ("Claude 桌面版", "https://claude.ai/download")
            case .chatgpt: ("Codex", "https://openai.com/codex/")
            case .gemini: ("Gemini CLI", "https://github.com/google-gemini/gemini-cli")
            case .other: ("Hermes Agent", "https://hermes-agent.nousresearch.com")
            }
        }
    }

    enum AIMode: Hashable { case choose, trying }

    @State private var step: Step = .hello
    @State private var pose: MascotPose = .hello
    /// 夏夏头上的气泡。
    @State private var speech = ""
    @State private var thinking = false

    @State private var bookChoices: [Choice] = [
        Choice(name: "家庭", symbol: "house"),
        Choice(name: "我的小店", symbol: "storefront", bookKind: .business),
        Choice(name: "旅行", symbol: "airplane"),
    ]
    @State private var pickedBooks: Set<String> = []
    @State private var accountChoices: [Choice] = [
        Choice(name: "现金", glyph: AccountKind.cash.glyph, accountKind: .cash),
        Choice(name: "银行卡", glyph: AccountKind.bank.glyph, accountKind: .bank),
        Choice(name: "信用卡", glyph: AccountKind.credit.glyph, accountKind: .credit),
        Choice(name: "支付宝", glyph: AccountKind.wallet.glyph, accountKind: .wallet),
        Choice(name: "微信支付", glyph: AccountKind.wallet.glyph, accountKind: .wallet),
        Choice(name: "PayPal", glyph: AccountKind.wallet.glyph, accountKind: .wallet),
        Choice(name: "存钱罐", glyph: AccountKind.savings.glyph, accountKind: .savings),
    ]
    @State private var pickedAccounts: Set<String> = ["现金", "银行卡"]
    @State private var custom = ""

    @State private var aiMode: AIMode = .choose
    @State private var family: AIFamily?
    /// 这一家的工具里已经连着的（设置里有夏夏账本）。
    @State private var linked: [AIApp] = []
    /// 这台 Mac 上有、还没连的。
    @State private var toConnect: [AIApp] = []
    @State private var partner: MascotCharacter?
    @State private var tryStartedAt = Date()
    /// AI 真的来读过账本了（fin 握手）。
    @State private var handshakeSeen = false
    @State private var knownTransactions: Set<UUID> = []
    @State private var knownGoals: Set<UUID> = []
    /// AI 连上了：结尾是庆祝，不是「记第一笔试试」。
    @State private var celebrated = false
    @State private var celebrationNote: String?
    @State private var celebrationGoal: String?
    @State private var confetti = false

    /// 示例账本、假装新电脑时 AI 不会真的来：给一个「演示」入口看连上之后的样子。
    private var isPretend: Bool {
        model.usesSampleData || ProcessInfo.processInfo.arguments.contains("-XiaxiaFreshAI")
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 760
            Group {
                if wide {
                    HStack(spacing: 0) {
                        hero(mascot: min(280, geo.size.height * 0.42))
                            .frame(width: min(geo.size.width * 0.4, 520))
                        content(padding: 44)
                    }
                } else {
                    VStack(spacing: 0) {
                        hero(mascot: 120).frame(height: min(250, geo.size.height * 0.32))
                        content(padding: 20)
                    }
                }
            }
        }
        .background(Color.cardBackground.ignoresSafeArea())
        .overlay {
            if confetti && !reduceMotion { ConfettiView().allowsHitTesting(false).transition(.opacity) }
        }
        .task { await start() }
        .task(id: aiMode) { await watchAI() }
    }

    // MARK: 左边：夏夏

    private func hero(mascot size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color.ai.opacity(0.08), Color.ai.opacity(0.22)], startPoint: .top, endPoint: .bottom)
            WelcomeBubbles(paused: reduceMotion)
            VStack(spacing: 6) {
                speechBubble
                ZStack(alignment: .bottom) {
                    // 脚下的水波
                    ForEach(0..<3, id: \.self) { i in
                        Ellipse().stroke(Color.white.opacity(0.55 - Double(i) * 0.15), lineWidth: 1.5)
                            .frame(width: size * (0.9 + CGFloat(i) * 0.35), height: size * (0.16 + CGFloat(i) * 0.06))
                            .offset(y: size * 0.03 * CGFloat(i))
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        MascotView(.xiaxia, pose: pose, size: size, talking: thinking)
                            .id(pose)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        if let partner {
                            // 选了哪家 AI，哪家的小伙伴就跳出来。
                            MascotView(partner, pose: .idle, size: size * 0.62)
                                .id(partner)
                                .transition(.move(edge: .trailing).combined(with: .scale(scale: 0.6, anchor: .bottom)).combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, size * 0.05)
                }
            }
            .padding(16)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speech.isEmpty ? "夏夏" : "夏夏说：\(speech)")
    }

    private var speechBubble: some View {
        ZStack {
            if thinking {
                TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(Color.fg3).frame(width: 7, height: 7)
                                .offset(y: reduceMotion ? 0 : -3 * max(0, sin(t * 6 - Double(i) * 0.9)))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.opacity)
            } else if !speech.isEmpty {
                Text(speech)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.ai.opacity(0.12), radius: 10, y: 4)
                    .id(speech)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(minHeight: 48)
    }

    // MARK: 右边：三步

    private func content(padding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                stepper
                Spacer(minLength: 12)
                if step != .done {
                    Button("以后再说") { model.finishWelcome() }
                        .buttonStyle(.borderless).foregroundStyle(Color.fg2)
                        .accessibilityIdentifier("welcome.skip")
                }
            }
            ScrollView {
                page
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, padding * 0.9)
                    .id(pageKey)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollBounceBehavior(.basedOnSize)
            if canGoBack {
                Button { goBack() } label: { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).foregroundStyle(Color.fg2)
                    .padding(.top, 10)
                    .accessibilityIdentifier("welcome.back")
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pageKey: String { "\(step.rawValue)-\(aiMode == .choose ? "a" : "b")-\(celebrated)" }

    private var stepNames: [String] { aiStepAvailable ? ["账本", "账户", "连接 AI"] : ["账本", "账户"] }

    private var stepper: some View {
        HStack(spacing: 10) {
            ForEach(Array(stepNames.enumerated()), id: \.offset) { i, name in
                let number = i + 1
                let done = step.rawValue > number
                let current = step.rawValue == number
                if i > 0 {
                    Capsule().fill(step.rawValue >= number ? Color.ai.opacity(0.45) : Color.fg3.opacity(0.22))
                        .frame(height: 2).frame(maxWidth: 64)
                }
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(current ? Color.aiSolid : done ? Color.ai.opacity(0.18) : Color.fg3.opacity(0.15))
                        if done {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.ai)
                        } else {
                            Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(current ? Color.white : Color.fg2)
                        }
                    }
                    .frame(width: 26, height: 26)
                    Text(name).font(.subheadline.weight(current ? .semibold : .regular))
                        .foregroundStyle(current ? Color.ai : Color.fg2)
                        .lineLimit(1).fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("第 \(number) 步，\(name)" + (done ? "，完成" : current ? "，正在这一步" : ""))
            }
        }
        .animation(.snappy, value: step)
        .opacity(step == .hello ? 0 : 1)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .hello:
            pageBody("让我们开始记账吧", "我是夏夏，以后陪你记账。先问你\(aiStepAvailable ? "三" : "两")个小问题，一分钟就好。") {
                EmptyView()
            } buttons: {
                primary("开始", id: "welcome.start") { Task { await toBooks() } }
            }
        case .books:
            pageBody("你需要几个账本？", "一个账本就是一摊分开算的钱。生活和开店的钱不想混在一起，就开两个。") {
                FlowLayout(spacing: 8) {
                    chip("个人", symbol: "person", on: true, locked: true) {}
                    ForEach(bookChoices) { c in
                        let made = model.ledger.books.contains { $0.name == c.name }
                        chip(c.name, symbol: c.symbol, on: made || pickedBooks.contains(c.name), locked: made) { toggle(&pickedBooks, c.name) }
                    }
                }
                customField("自己加一个账本，比如「副业」") { name in
                    if !bookChoices.contains(where: { $0.name == name }) { bookChoices.append(Choice(name: name, symbol: "book.closed")) }
                    pickedBooks.insert(name)
                }
            } buttons: {
                primary("下一步", id: "welcome.books.next") { Task { await toAccounts() } }
            }
        case .accounts:
            pageBody("钱平时放在哪？", "有的就点一下，没有的可以自己加。余额以后随时能填。") {
                FlowLayout(spacing: 8) {
                    ForEach(accountChoices) { c in
                        let made = model.ledger.accounts.contains { $0.name == c.name }
                        chip(c.name, glyph: c.glyph, on: made || pickedAccounts.contains(c.name), locked: made) { toggle(&pickedAccounts, c.name) }
                    }
                }
                customField("自己加一个，比如某家银行的名字") { name in
                    if !accountChoices.contains(where: { $0.name == name }) {
                        accountChoices.append(Choice(name: name, glyph: AccountKind.bank.glyph, accountKind: .bank))
                    }
                    pickedAccounts.insert(name)
                }
            } buttons: {
                primary("下一步", id: "welcome.accounts.next") { Task { await toAI() } }
            }
        case .ai:
            if aiMode == .choose {
                pageBody("连接你的 AI", "连接后，用一句话就能记账、查账。你平时用哪个？") {
                    FlowLayout(spacing: 8) {
                        ForEach(AIFamily.allCases) { f in
                            chip(f.title, symbol: f == .newbie ? "questionmark.circle" : "sparkles", on: false) { Task { await choose(f) } }
                        }
                    }
                } buttons: {
                    secondary("先跳过") { Task { await skipAI() } }
                }
            } else {
                pageBody(tryTitle, trySubtitle) {
                    // 交给 AI 的那段话：卡片上是一句话的意思，复制的是完整指令。
                    VStack(alignment: .leading, spacing: 6) {
                        Text("「帮我连上夏夏账本，再问我今天花了什么」")
                            .font(.title3.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("复制的是一段完整的指令：它会自己连上账本，带你记下第一笔；连不上也会告诉你为什么。")
                            .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.aiLine, lineWidth: 1))

                    HStack(spacing: 8) {
                        if handshakeSeen {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                            Text("已经读到账本，等它帮你记第一笔").font(.subheadline).foregroundStyle(Color.fg2)
                        } else {
                            ProgressView().controlSize(.small)
                            Text("等待你的 AI 读取账本").font(.subheadline).foregroundStyle(Color.fg2)
                        }
                    }
                } buttons: {
                    primary("复制指令", symbol: "doc.on.doc", id: "welcome.ai.copyPrompt") {
                        Clipboard.copy(model.aiWelcomePrompt)
                        model.toast = .init(text: "已复制，去你的 AI 里粘贴发出去", changeID: nil)
                    }
                    if handshakeSeen {
                        secondary("好了，进账本") { Task { await celebrate(who: nil, note: nil, goal: nil) } }
                    } else {
                        secondary("先跳过") { Task { await skipAI() } }
                    }
                } extras: {
                    if !toConnect.isEmpty {
                        link("夏夏直接帮我连上", symbol: "link") { Task { await connectFound() } }
                            .accessibilityIdentifier("welcome.ai.connect")
                    } else if linked.isEmpty, let f = family {
                        link("去下载 \(f.install.name)", symbol: "arrow.down.circle") {
                            if let u = URL(string: f.install.url) { openURL(u) }
                        }
                    }
                    if isPretend {
                        link("演示：假装 AI 记了一笔", symbol: "wand.and.stars") {
                            Task { await celebrate(who: family?.title ?? "AI", note: "咖啡 -3,50 €", goal: nil) }
                        }
                    }
                }
            }
        case .done:
            if celebrated {
                pageBody("🎉 恭喜，连接成功！", celebrationText) {
                    EmptyView()
                } buttons: {
                    primary("进入夏夏账本", id: "welcome.done.enter") { finish(openAdd: false) }
                }
            } else {
                pageBody("都准备好了！", "现在记第一笔试试？\(aiStepAvailable ? "想连 AI 的时候，去「设置」里点「连上你的 AI」。" : "")") {
                    EmptyView()
                } buttons: {
                    primary("记第一笔", id: "welcome.done.add") { finish(openAdd: true) }
                    secondary("先逛逛") { finish(openAdd: false) }
                }
            }
        }
    }

    private var tryTitle: String {
        guard let f = family else { return "连接你的 AI" }
        if !linked.isEmpty { return "\(f == .newbie ? "Claude" : f.title) 连接上了" }
        return f == .newbie ? "先装一个 AI" : "还没有连接上"
    }

    private var trySubtitle: String {
        guard let f = family else { return "" }
        if let first = linked.first {
            return "复制下面的指令，粘给 \(first.name)。它会问你今天花了什么，帮你记下第一笔。"
        }
        if !toConnect.isEmpty {
            return "这台 Mac 上有 \(toConnect.map(\.name).joined(separator: "、"))。复制指令粘给它，它会自己连上账本，再问你今天花了什么。"
        }
        if f == .newbie {
            return "推荐从 Claude 桌面版开始，最省事。装好、登录，再把下面的指令粘给它。"
        }
        return "这台 Mac 上没找到 \(f.install.name)。已经在用的话，复制指令粘给它，它会告诉你怎么连；如果它是网页版、连不到这台电脑，也会直接告诉你。"
    }

    private var celebrationText: String {
        var parts: [String] = []
        if let celebrationNote { parts.append("第一笔记下了：\(celebrationNote)。") }
        if let celebrationGoal {
            parts.append("祝你早日达成「\(celebrationGoal)」！")
        } else {
            parts.append("祝你想存的钱都存到，心愿一个个达成。")
        }
        parts.append("让我们一起努力吧！")
        return parts.joined(separator: "\n")
    }

    // MARK: 小零件

    /// 一页：大标题、一句说明、中间的选项、底下一排按钮、再底下几个小链接。
    private func pageBody<Body: View, Buttons: View, Extras: View>(
        _ title: String, _ subtitle: String,
        @ViewBuilder body: () -> Body, @ViewBuilder buttons: () -> Buttons, @ViewBuilder extras: () -> Extras
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 38, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.title3).foregroundStyle(Color.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            body()
            FlowLayout(spacing: 10) { buttons() }.padding(.top, 4)
            FlowLayout(spacing: 16) { extras() }
        }
    }

    private func pageBody<Body: View, Buttons: View>(
        _ title: String, _ subtitle: String,
        @ViewBuilder body: () -> Body, @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        pageBody(title, subtitle, body: body, buttons: buttons, extras: { EmptyView() })
    }

    private func toggle(_ set: inout Set<String>, _ name: String) {
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
    }

    private func chip(_ title: String, glyph: XiaGlyph? = nil, symbol: String = "circle", on: Bool, locked: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 6) {
                if on {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).transition(.scale.combined(with: .opacity))
                } else if let glyph {
                    glyph.image(size: 16)
                } else {
                    Image(systemName: symbol).font(.subheadline)
                }
                Text(title).font(.body.weight(.medium))
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(on ? Color.aiSolid : Color.pageBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : Color.fg3.opacity(0.22), lineWidth: 1))
            .scaleEffect(on ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(title)
        .accessibilityValue(locked ? "已经有了" : on ? "已选" : "没选")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("welcome.chip.\(title)")
    }

    private func customField(_ prompt: String, add: @escaping (String) -> Void) -> some View {
        let submit = {
            let name = custom.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            withAnimation(.snappy) { add(name) }
            custom = ""
        }
        return HStack(spacing: 8) {
            TextField(prompt, text: $custom)
                .textFieldStyle(.plain)
                .onSubmit(submit)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.pageBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.fg3.opacity(0.22), lineWidth: 1))
                .accessibilityIdentifier("welcome.custom")
            Button(action: submit) { Label("加上", systemImage: "plus") }
                .buttonStyle(.softAI)
                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: 420)
    }

    private func primary(_ title: String, symbol: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.body.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 26).padding(.vertical, 13)
            .frame(minWidth: 150)
            .background(Color.aiSolid, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier(id)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.medium)).foregroundStyle(Color.primary)
                .padding(.horizontal, 26).padding(.vertical, 13)
                .background(Color.cardBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.fg3.opacity(0.3), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func link(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(Color.ai)
        }
        .buttonStyle(.plain)
    }

    // MARK: 怎么走

    /// 夏夏说一句：先冒三个点，再出字。
    private func say(_ text: String, pose newPose: MascotPose? = nil) async {
        if let newPose { withAnimation(.bouncy) { pose = newPose } }
        withAnimation(.snappy) { thinking = true }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.1 : 0.55))
        withAnimation(.bouncy(duration: 0.4)) {
            speech = text
            thinking = false
        }
    }

    private func go(_ next: Step) {
        custom = ""
        withAnimation(.smooth(duration: 0.35)) { step = next }
    }

    private var canGoBack: Bool { step == .books || step == .accounts || step == .ai }

    private func goBack() {
        switch step {
        case .books: go(.hello)
        case .accounts: go(.books)
        case .ai:
            if aiMode == .trying {
                withAnimation(.smooth(duration: 0.35)) { aiMode = .choose; partner = nil; family = nil }
                Task { await say("换一个也行，你平时用哪个？", pose: .think) }
            } else {
                go(.accounts)
            }
        case .hello, .done: break
        }
    }

    private func start() async {
        guard speech.isEmpty else { return }
        await say("嗨，我是夏夏！", pose: .hello)
    }

    private func toBooks() async {
        go(.books)
        await say("「个人」我已经帮你建好了。", pose: .idle)
    }

    private func toAccounts() async {
        go(.accounts)
        await say(pickedBooks.isEmpty ? "好，一个账本最清爽。" : "好，\(pickedBooks.count + 1) 个账本。", pose: .write)
    }

    /// 把选好的账本、账户写进账本（已经有的不重复建）。
    private func commitSetup() {
        let haveBooks = Set(model.ledger.books.map(\.name))
        for c in bookChoices where pickedBooks.contains(c.name) && !haveBooks.contains(c.name) {
            _ = try? model.edit(quiet: true) { try $0.addBook(name: c.name, kind: c.bookKind, author: model.author) }
        }
        let haveAccounts = Set(model.ledger.accounts.map(\.name))
        for c in accountChoices where pickedAccounts.contains(c.name) && !haveAccounts.contains(c.name) {
            _ = try? model.edit(quiet: true) { ledger in
                let id = ledger.newAccountID(for: c.name)
                return try ledger.createAccount(Account(id: id, name: c.name, kind: c.accountKind), author: model.author)
            }
        }
    }

    private func toAI() async {
        commitSetup()
        let count = model.ledger.accounts.count
        if aiStepAvailable {
            withAnimation(.smooth(duration: 0.35)) { aiMode = .choose }
            go(.ai)
            await say(count == 0 ? "账户以后再加也行。最后一步啦！" : "记下了，\(count) 个放钱的地方。最后一步啦！", pose: .think)
        } else {
            go(.done)
            await say("都准备好了！", pose: .celebrate)
        }
    }

    private func choose(_ f: AIFamily) async {
        guard let c = model.aiConnector else { await skipAI(); return }
        family = f
        await say(f == .newbie ? "没关系，我来带你。" : "那我们看看吧。", pose: .think)
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.1 : 0.7))
        linked = f.apps.filter { c.isConnected($0) }
        toConnect = f.apps.filter { c.isInstalled($0) && !c.isConnected($0) }
        handshakeSeen = false
        tryStartedAt = Date()
        knownTransactions = Set(model.ledger.transactions.map(\.id))
        knownGoals = Set(model.ledger.goals.map(\.id))
        withAnimation(.smooth(duration: 0.35)) {
            aiMode = .trying
            if !linked.isEmpty || !toConnect.isEmpty { partner = f.partner }
        }
        if !linked.isEmpty {
            await say("连接上了！", pose: .cheer)
        } else if !toConnect.isEmpty {
            await say("还没有连接上，不过我找到它了。", pose: .idle)
        } else if f == .newbie {
            await say("先装一个，我在这儿等你。", pose: .idle)
        } else {
            await say("还没有连接上。", pose: .worried)
        }
    }

    private func connectFound() async {
        guard let c = model.aiConnector else { return }
        var done: [AIApp] = []
        var failed: [String] = []
        for app in toConnect {
            do { try AISetup(connector: c).connect(app); done.append(app) }
            catch { failed.append(app.name) }
        }
        withAnimation(.smooth) {
            toConnect.removeAll { done.contains($0) }
            linked += done
        }
        if let first = done.first {
            await say("连接上了！先\(first.afterConnect)，再把指令粘给它。", pose: .cheer)
        } else if !failed.isEmpty {
            await say("\(failed.joined(separator: "、")) 没连上。把指令粘给它，让它自己连。", pose: .worried)
        }
    }

    private func skipAI() async {
        go(.done)
        await say("好，以后再连也行。", pose: .calm)
    }

    /// 每 2 秒看一眼：新装的工具出现了没有；AI 有没有自己连好；有没有真的来读账本；有没有帮着记下第一笔、建了目标。
    private func watchAI() async {
        guard aiMode == .trying else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !thinking, step == .ai, aiMode == .trying, let c = model.aiConnector, let f = family else { continue }
            if linked.isEmpty, toConnect.isEmpty {
                let found = f.apps.filter { c.isInstalled($0) && !c.isConnected($0) }
                if !found.isEmpty {
                    withAnimation(.bouncy) { toConnect = found; partner = f.partner }
                    await say("认出来了！你装好了 \(found[0].name)。", pose: .cheer)
                    continue
                }
            }
            let nowLinked = f.apps.filter { c.isConnected($0) }
            if nowLinked.count > linked.count {
                // AI 照着指令自己连好了。
                withAnimation(.bouncy) {
                    linked = nowLinked
                    toConnect.removeAll { nowLinked.contains($0) }
                    partner = f.partner
                }
                await say("连接上了！", pose: .cheer)
                continue
            }
            guard !model.usesSampleData else { continue }
            let fresh = AIConnections.load().filter { $0.value > tryStartedAt }
            let who = fresh.max(by: { $0.value < $1.value }).map { AIApp.displayName(clientName: $0.key) }
            if !handshakeSeen, let who {
                withAnimation(.snappy) { handshakeSeen = true }
                await say("我看到 \(who) 来读账本了！跟它说说今天花了什么吧。", pose: .cheer)
                continue
            }
            model.refreshIfChanged()
            let newTx = model.ledger.transactions.filter { !knownTransactions.contains($0.id) }
            let newGoal = model.ledger.goals.first { !knownGoals.contains($0.id) }
            if !newTx.isEmpty || newGoal != nil {
                let note = newTx.max(by: { $0.date < $1.date }).map { "\(Merchant.display($0.description)) \($0.amount.formatted)" }
                await celebrate(who: who, note: note, goal: newGoal?.name)
                return
            }
        }
    }

    /// 连上了：撒花，说恭喜。
    private func celebrate(who: String?, note: String?, goal: String?) async {
        guard !celebrated else { return }
        model.activity = nil   // 顶上那条「AI 刚记了 1 笔」不用再弹，这一页自己说
        celebrationNote = note
        celebrationGoal = goal
        withAnimation(.smooth(duration: 0.35)) {
            celebrated = true
            step = .done
            confetti = true
        }
        await say(who.map { "\($0) 连上啦！" } ?? "连上啦！", pose: .celebrate)
        try? await Task.sleep(for: .seconds(4.5))
        withAnimation(.smooth) { confetti = false }
    }

    private func finish(openAdd: Bool) {
        withAnimation(.smooth) { model.finishWelcome() }
        if openAdd { model.sheet = .add }
    }

    // MARK: 连 AI（只在 Mac）

    private var aiStepAvailable: Bool {
        #if os(macOS)
        model.aiConnector != nil
        #else
        false
        #endif
    }
}

/// 左边背景里慢慢往上飘的泡泡。
struct WelcomeBubbles: View {
    struct Bubble {
        var x = Double.random(in: 0.05...0.95)
        var size = Double.random(in: 5...16)
        var speed = Double.random(in: 0.025...0.06)
        var phase = Double.random(in: 0...1)
    }

    var paused: Bool
    @State private var bubbles = (0..<10).map { _ in Bubble() }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { ctx in
            Canvas { context, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for b in bubbles {
                    let progress = (t * b.speed + b.phase).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1.06 - progress * 1.12)
                    let x = b.x * size.width + sin(t * 0.6 + b.phase * 6) * 10
                    let rect = CGRect(x: x - b.size, y: y - b.size, width: b.size * 2, height: b.size * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.16)))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.75)), lineWidth: 1.2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 撒花：从上面飘下来的彩色纸片，几秒后落完。
struct ConfettiView: View {
    struct Piece {
        var x = Double.random(in: 0...1)
        var delay = Double.random(in: 0...1.2)
        var speed = Double.random(in: 0.28...0.55)
        var size = Double.random(in: 6...11)
        var spin = Double.random(in: -5...5)
        var sway = Double.random(in: 0.8...2.2)
        var color = Int.random(in: 0..<6)
    }

    @State private var pieces = (0..<90).map { _ in Piece() }
    @State private var start = Date()
    private let colors: [Color] = [.brand, .ai, .income, .warn, .pink, .yellow]

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { context, size in
                let t = ctx.date.timeIntervalSince(start)
                for p in pieces {
                    let life = t - p.delay
                    guard life > 0 else { continue }
                    let y = -20 + life * p.speed * size.height
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + sin(life * p.sway * 2) * 18
                    var c = context
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(life * p.spin))
                    c.opacity = max(0, min(1, 4.5 - t))
                    c.fill(Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2), cornerRadius: 1.5),
                           with: .color(colors[p.color]))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
