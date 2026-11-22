import FinanceCore
import SwiftUI

// 第一次打开（账本里还没有账户、没有流水）：夏夏用聊天的方式带着走三步——
// ① 要几个账本 ② 钱放在哪些地方 ③ 要不要连上 AI（只在 Mac）。每一步点选就行，也能自己加。
// 每一步选完马上写进账本（进改动记录，能撤销）。「以后再说」随时能跳过。

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

    enum Step { case hello, books, accounts, ai, done }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var fromXia: Bool
        var text: String
        /// 气泡里另起几行的小清单（比如连着的 AI），每个前面一个绿勾。
        var items: [String] = []
    }

    struct Choice: Identifiable, Hashable {
        var name: String
        var glyph: XiaGlyph?
        var symbol: String = "circle"
        var bookKind: BookKind = .personal
        var accountKind: AccountKind = .bank
        var id: String { name }
    }

    @State private var step: Step = .hello
    @State private var messages: [Message] = []
    @State private var typing = false
    @State private var pose: MascotPose = .hello

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
    @State private var aiMode: AIMode = .choose
    @State private var family: AIFamily?
    /// 找到了、还没连的工具。
    @State private var toConnect: [AIApp] = []
    @State private var partner: MascotCharacter?
    /// 这一家的工具已经连着的（设置里有夏夏账本）。
    @State private var linked: [AIApp] = []
    @State private var tryStartedAt = Date()
    /// AI 真的来读过账本了（fin 握手）。
    @State private var handshakeSeen = false
    @State private var knownTransactions: Set<UUID> = []
    @State private var knownGoals: Set<UUID> = []
    /// AI 连上并且带着记了第一笔 / 建了目标：结尾是庆祝，不是「记第一笔试试」。
    @State private var celebrated = false
    @State private var confetti = false
    @Environment(\.openURL) private var openURL

    /// 示例账本、假装新电脑时 AI 不会真的来：给一个「演示」按钮看连上之后的样子。
    private var isPretend: Bool {
        model.usesSampleData || ProcessInfo.processInfo.arguments.contains("-XiaxiaFreshAI")
    }
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if step != .done {
                    Button("以后再说") { model.finishWelcome() }
                        .buttonStyle(.borderless).foregroundStyle(Color.fg2)
                        .accessibilityIdentifier("welcome.skip")
                }
            }
            .padding(.horizontal, 20).padding(.top, 14)

            HStack(alignment: .bottom, spacing: 4) {
                MascotView(.xiaxia, pose: pose, size: 132, talking: typing)
                    .id(pose)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                if let partner {
                    // 选了哪家 AI，哪家的小伙伴就跳出来。
                    MascotView(partner, pose: .idle, size: 104)
                        .id(partner)
                        .transition(.move(edge: .trailing).combined(with: .scale(scale: 0.6, anchor: .bottom)).combined(with: .opacity))
                }
            }
            .frame(height: 140)
            .accessibilityHidden(true)

            progressDots.padding(.top, 6).padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(messages) { m in
                            bubble(m)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: m.fromXia ? .bottomLeading : .bottomTrailing)),
                                    removal: .opacity))
                        }
                        if typing { typingBubble.transition(.opacity) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 4).padding(.vertical, 6)
                }
                .onChange(of: messages) { _, _ in withAnimation(.snappy) { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: typing) { _, _ in withAnimation(.snappy) { proxy.scrollTo("end", anchor: .bottom) } }
            }

            ZStack {
                if !typing {
                    panel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(step)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10).padding(.bottom, 22)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground.ignoresSafeArea())
        .overlay {
            if confetti && !reduceMotion { ConfettiView().allowsHitTesting(false).transition(.opacity) }
        }
        .task { await start() }
        .task(id: aiMode) { await watchAI() }
    }

    // MARK: 进度

    private var stepIndex: Int {
        switch step { case .hello: 0; case .books: 1; case .accounts: 2; case .ai: 3; case .done: 4 }
    }

    private var stepCount: Int { aiStepAvailable ? 3 : 2 }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(1...stepCount, id: \.self) { i in
                Capsule()
                    .fill(i <= min(stepIndex, stepCount) ? Color.brand : Color.fg3.opacity(0.25))
                    .frame(width: i == stepIndex ? 22 : 8, height: 8)
            }
        }
        .animation(.snappy, value: stepIndex)
        .opacity(step == .hello ? 0 : 1)
        .accessibilityElement()
        .accessibilityLabel(step == .hello || step == .done ? "" : "第 \(min(stepIndex, stepCount)) 步，共 \(stepCount) 步")
    }

    // MARK: 聊天气泡

    private func bubble(_ m: Message) -> some View {
        HStack {
            if !m.fromXia { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                Text(m.text).font(.body)
                if !m.items.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(m.items, id: \.self) { item in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                                Text(item)
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.incomeSoft, in: Capsule())
                        }
                    }
                }
            }
                .foregroundStyle(m.fromXia ? Color.primary : Color.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(m.fromXia ? Color.cardBackground : Color.brand,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel((m.fromXia ? "夏夏：" : "你：") + m.text + (m.items.isEmpty ? "" : " " + m.items.joined(separator: "、")))
            if m.fromXia { Spacer(minLength: 40) }
        }
    }

    private var typingBubble: some View {
        HStack {
            TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(Color.fg3).frame(width: 7, height: 7)
                            .offset(y: reduceMotion ? 0 : -3 * max(0, sin(t * 6 - Double(i) * 0.9)))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("夏夏正在说话")
            Spacer()
        }
    }

    // MARK: 每一步底下的选项

    @ViewBuilder
    private var panel: some View {
        switch step {
        case .hello:
            primary("开始吧", id: "welcome.start") { Task { await askBooks() } }
        case .books:
            VStack(spacing: 12) {
                FlowLayout(spacing: 8) {
                    chip("个人", symbol: "person", on: true, locked: true) {}
                    ForEach(bookChoices) { c in
                        chip(c.name, symbol: c.symbol, on: pickedBooks.contains(c.name)) { toggle(&pickedBooks, c.name) }
                    }
                }
                customField("自己加一个账本，比如「副业」") { name in
                    bookChoices.append(Choice(name: name, symbol: "book.closed"))
                    pickedBooks.insert(name)
                }
                primary(pickedBooks.isEmpty ? "一个就够了" : "就这 \(pickedBooks.count + 1) 个", id: "welcome.books.next") { Task { await confirmBooks() } }
            }
        case .accounts:
            VStack(spacing: 12) {
                FlowLayout(spacing: 8) {
                    ForEach(accountChoices) { c in
                        chip(c.name, glyph: c.glyph, on: pickedAccounts.contains(c.name)) { toggle(&pickedAccounts, c.name) }
                    }
                }
                customField("自己加一个，比如某家银行的名字") { name in
                    accountChoices.append(Choice(name: name, glyph: AccountKind.bank.glyph, accountKind: .bank))
                    pickedAccounts.insert(name)
                }
                primary(pickedAccounts.isEmpty ? "先不加" : "选好了（\(pickedAccounts.count) 个）", id: "welcome.accounts.next") { Task { await confirmAccounts() } }
            }
        case .ai:
            VStack(spacing: 12) {
                switch aiMode {
                case .choose:
                    FlowLayout(spacing: 8) {
                        ForEach(AIFamily.allCases) { f in
                            chip(f.title, symbol: f == .newbie ? "questionmark.circle" : "sparkles", on: false) { Task { await choose(f) } }
                        }
                    }
                    secondary("以后再说") { Task { await skipAI() } }
                case .trying:
                    promptCard
                    HStack(spacing: 8) {
                        if handshakeSeen {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                            Text("连上了，等它帮你记第一笔…").font(.caption).foregroundStyle(Color.fg2)
                        } else {
                            ProgressView().controlSize(.small)
                            Text("等你的 AI 来读账本…").font(.caption).foregroundStyle(Color.fg2)
                        }
                        Spacer()
                    }
                    FlowLayout(spacing: 8) {
                        secondary("换一个") { backToFamilies() }
                        if !toConnect.isEmpty {
                            secondary("夏夏直接帮我连上") { Task { await connectFound() } }
                                .accessibilityIdentifier("welcome.ai.connect")
                        } else if linked.isEmpty, let f = family {
                            secondary("去下载 \(f.install.name)") {
                                if let u = URL(string: f.install.url) { openURL(u) }
                            }
                        }
                        if isPretend {
                            secondary("演示：假装 AI 记了一笔") { Task { await celebrate(who: family?.title ?? "AI", note: "咖啡 -3,50 €", goal: nil) } }
                        }
                        if handshakeSeen {
                            secondary("好了，进账本") { Task { await celebrate(who: nil, note: nil, goal: nil) } }
                        } else {
                            secondary("先跳过") { Task { await skipTry() } }
                        }
                    }
                }
            }
        case .done:
            if celebrated {
                primary("进入夏夏账本", id: "welcome.done.enter") { finish(openAdd: false) }
            } else {
                HStack(spacing: 10) {
                    secondary("先逛逛") { finish(openAdd: false) }
                    primary("记第一笔", id: "welcome.done.add") { finish(openAdd: true) }
                }
            }
        }
    }

    private func toggle(_ set: inout Set<String>, _ name: String) {
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
    }

    private func chip(_ title: String, glyph: XiaGlyph? = nil, symbol: String = "circle", on: Bool, locked: Bool = false,
                      tint: Color = .brand, action: @escaping () -> Void) -> some View {
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
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(on ? tint : Color.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : Color.fg3.opacity(0.25), lineWidth: 1))
            .scaleEffect(on ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(title)
        .accessibilityValue(locked ? "一定有" : on ? "已选" : "没选")
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
                .focused($customFocused)
                .onSubmit(submit)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.fg3.opacity(0.25), lineWidth: 1))
                .accessibilityIdentifier("welcome.custom")
            Button(action: submit) { Label("加上", systemImage: "plus") }
                .buttonStyle(.soft)
                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func primary(_ title: String, id: String, tint: Color = .brand, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .frame(minWidth: 150)
                .background(tint, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier(id)
    }

    /// 交给 AI 的提示词：一张卡片，点一下复制。里面写了怎么连、连不上怎么说、连上后问「今天花了什么」。
    private var promptCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("给 \(family == .newbie ? "AI" : (family?.title ?? "AI")) 的提示词").font(.subheadline.weight(.semibold))
                Text("它会自己连上账本，问你「今天花了什么？」，帮你记下第一笔；连不上也会告诉你为什么。")
                    .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                Clipboard.copy(model.aiWelcomePrompt)
                model.toast = .init(text: "已复制，去你的 AI 里粘贴发出去", changeID: nil)
            } label: { Label("复制提示词", systemImage: "doc.on.doc") }
                .buttonStyle(AISolidButtonStyle())
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcome.ai.copyPrompt")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.aiLine, lineWidth: 1))
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.medium)).foregroundStyle(Color.primary)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(Color.cardBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.fg3.opacity(0.25), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 对话怎么走

    /// 夏夏说一句：先冒三个点，再出字。
    private func say(_ text: String, items: [String] = [], pose newPose: MascotPose? = nil) async {
        if let newPose { withAnimation(.bouncy) { pose = newPose } }
        withAnimation(.snappy) { typing = true }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.15 : min(1.1, 0.45 + Double(text.count) * 0.012)))
        withAnimation(.bouncy(duration: 0.4)) {
            messages.append(Message(fromXia: true, text: text, items: items))
            typing = false
        }
    }

    private func answer(_ text: String) {
        withAnimation(.bouncy(duration: 0.35)) { messages.append(Message(fromXia: false, text: text)) }
    }

    private func start() async {
        guard messages.isEmpty else { return }
        await say("嗨，我是夏夏，以后我陪你记账。", pose: .hello)
        await say("让我们开始记账吧！先问你\(aiStepAvailable ? "三" : "两")个小问题，一分钟就好。")
    }

    private func askBooks() async {
        answer("开始吧")
        step = .books
        await say("第一个问题：你需要几个账本？", pose: .idle)
        await say("一个账本就是一摊分开算的钱。比如生活和开店的钱不想混在一起，就开两个。「个人」我已经帮你建好了。")
    }

    private func confirmBooks() async {
        let existing = Set(model.ledger.books.map(\.name))
        let picked = bookChoices.filter { pickedBooks.contains($0.name) }
        for c in picked where !existing.contains(c.name) {
            _ = try? model.edit(quiet: true) { try $0.addBook(name: c.name, kind: c.bookKind, author: model.author) }
        }
        answer((["个人"] + picked.map(\.name)).joined(separator: "、"))
        custom = ""
        step = .accounts
        await say(picked.isEmpty ? "好，一个账本最清爽。" : "好，\(picked.count + 1) 个账本建好了。", pose: .write)
        await say("第二个问题：你的钱平时放在哪些地方？现金、银行卡、支付宝……有的就点一下，没有的可以自己加。", pose: .idle)
    }

    private func confirmAccounts() async {
        let existing = Set(model.ledger.accounts.map(\.name))
        let picked = accountChoices.filter { pickedAccounts.contains($0.name) }
        for c in picked where !existing.contains(c.name) {
            _ = try? model.edit(quiet: true) { ledger in
                let id = ledger.newAccountID(for: c.name)
                return try ledger.createAccount(Account(id: id, name: c.name, kind: c.accountKind), author: model.author)
            }
        }
        answer(picked.isEmpty ? "先不加" : picked.map(\.name).joined(separator: "、"))
        custom = ""
        if picked.isEmpty {
            await say("没关系，记第一笔的时候再加也行。", pose: .calm)
        } else {
            await say("记下了，\(picked.count) 个放钱的地方。余额以后在「家底」里随时能填。", pose: .write)
        }
        if aiStepAvailable {
            aiMode = .choose
            step = .ai
            await say("最后一个问题：你平时用哪个 AI？", pose: .think)
            await say("把它连上账本以后，你跟它说一句「今天买菜花了 23」，它就帮你记，还能帮你看钱花在哪了。")
        } else {
            await wrapUp()
        }
    }

    private func choose(_ f: AIFamily) async {
        answer(f.title)
        family = f
        guard let c = model.aiConnector else { await wrapUp(); return }
        await say(f == .newbie ? "没关系，我来带你。" : "那我们看看吧。", pose: .think)
        linked = f.apps.filter { c.isConnected($0) }
        toConnect = f.apps.filter { c.isInstalled($0) && !c.isConnected($0) }
        handshakeSeen = false
        tryStartedAt = Date()
        knownTransactions = Set(model.ledger.transactions.map(\.id))
        knownGoals = Set(model.ledger.goals.map(\.id))
        if !linked.isEmpty {
            withAnimation(.bouncy) { partner = f.partner }
            await say("连接上了！", items: linked.map(\.name), pose: .cheer)
            withAnimation(.snappy) { aiMode = .trying }
            await say("现在试试第一笔：点「复制提示词」，粘给 \(linked[0].name)。它会问你今天花了什么，帮你记下来。我在这儿等着。", pose: .idle)
        } else if !toConnect.isEmpty {
            withAnimation(.bouncy) { partner = f.partner }
            await say("还没有连接上。不过这台 Mac 上有：", items: toConnect.map(\.name), pose: .worried)
            withAnimation(.snappy) { aiMode = .trying }
            await say("点「复制提示词」，粘给它，它会自己连上账本，再问你今天花了什么。想省事也可以让我直接帮你连。", pose: .idle)
        } else if f == .newbie {
            withAnimation(.snappy) { aiMode = .trying }
            await say("我推荐从 Claude 桌面版开始，最省事。装好、登录，再把下面的提示词粘给它就行。不急的话也可以先跳过。", pose: .idle)
        } else {
            withAnimation(.snappy) { aiMode = .trying }
            await say("还没有连接上，这台 Mac 上也没找到 \(f.install.name)。", pose: .worried)
            await say("可以先装一个。已经在用的话，把下面的提示词粘给它，它会告诉你怎么连；如果它是网页版、连不到这台电脑，也会直接告诉你。", pose: .idle)
        }
    }

    private func backToFamilies() {
        answer("换一个")
        withAnimation(.snappy) { partner = nil; family = nil; aiMode = .choose }
    }

    private func connectFound() async {
        guard let c = model.aiConnector else { return }
        answer("夏夏直接帮我连上")
        var done: [AIApp] = []
        var failed: [String] = []
        for app in toConnect {
            do { try AISetup(connector: c).connect(app); done.append(app) }
            catch { failed.append("\(app.name)：\(error.localizedDescription)") }
        }
        toConnect.removeAll { done.contains($0) }
        linked += done
        if !failed.isEmpty { await say("有的没连上：\(failed.joined(separator: "；"))。可以把提示词粘给它，让它自己连。", pose: .worried) }
        guard let first = done.first else { return }
        await say("连接上了！", items: done.map(\.name), pose: .cheer)
        await say("先\(first.afterConnect)，再把提示词粘给它。它会问你今天花了什么。", pose: .idle)
    }

    private func skipTry() async {
        answer("先跳过")
        await say("好。以后想看连没连上，去「设置」里的「连上你的 AI」。", pose: .calm)
        await wrapUp()
    }

    private func skipAI() async {
        answer("以后再说")
        await say("好，想连的时候去「设置」里点「连上你的 AI」。", pose: .calm)
        await wrapUp()
    }

    /// 每 2 秒看一眼：新装的工具出现了没有；AI 有没有真的来读账本；有没有帮着记下第一笔、建了目标。
    private func watchAI() async {
        guard aiMode == .trying else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !typing, step == .ai, aiMode == .trying, let c = model.aiConnector, let f = family else { continue }
            if linked.isEmpty, toConnect.isEmpty {
                let found = f.apps.filter { c.isInstalled($0) && !c.isConnected($0) }
                if !found.isEmpty {
                    toConnect = found
                    withAnimation(.bouncy) { partner = f.partner }
                    await say("认出来了！你装好了：", items: found.map(\.name), pose: .cheer)
                    await say("把提示词粘给它，或者让我直接帮你连。", pose: .idle)
                    continue
                }
            }
            let nowLinked = f.apps.filter { c.isConnected($0) }
            if nowLinked.count > linked.count {
                // AI 照着提示词自己连好了。
                let new = nowLinked.filter { !linked.contains($0) }
                linked = nowLinked
                toConnect.removeAll { nowLinked.contains($0) }
                withAnimation(.bouncy) { partner = f.partner }
                await say("连接上了！", items: new.map(\.name), pose: .cheer)
                continue
            }
            guard !model.usesSampleData else { continue }
            let fresh = AIConnections.load().filter { $0.value > tryStartedAt }
            let who = fresh.max(by: { $0.value < $1.value }).map { AIApp.displayName(clientName: $0.key) }
            if !handshakeSeen, let who {
                withAnimation(.snappy) { handshakeSeen = true }
                await say("我看到 \(who) 刚刚来读账本了！接着跟它说说今天花了什么吧。", pose: .cheer)
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
        celebrated = true
        model.activity = nil   // 顶上那条「AI 刚记了 1 笔」不用再弹，夏夏自己说
        step = .done
        withAnimation(.smooth) { confetti = true }
        await say("🎉 恭喜，连接成功！", pose: .celebrate)
        if let note { await say("\(who ?? "你的 AI") 帮你记下了第一笔：\(note)。") }
        if let goal {
            await say("祝你早日达成「\(goal)」！让我们一起努力吧！", pose: .cheer)
        } else {
            await say("祝你想存的钱都存到，心愿一个个达成。让我们一起努力吧！", pose: .cheer)
        }
        try? await Task.sleep(for: .seconds(4))
        withAnimation(.smooth) { confetti = false }
    }

    private func wrapUp() async {
        step = .done
        await say("都准备好了！现在记第一笔试试？", pose: .celebrate)
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
