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
        var missingNote: String {
            switch self {
            case .claude: "这台 Mac 上还没找到 Claude。装一个 Claude 桌面版，登录好，再回到这里，我会自己认出来。"
            case .chatgpt: "ChatGPT 要通过它家的 Codex 才能读到这台电脑上的账本，用的还是你的 ChatGPT 账号。这台 Mac 上还没找到 Codex，装好再回到这里，我会自己认出来。"
            case .gemini: "这台 Mac 上还没找到 Gemini CLI。装好再回到这里，我会自己认出来。"
            case .other: "DeepSeek 这些要通过 Hermes Agent 这样的助手才能读到这台电脑上的账本。这台 Mac 上还没找到，装好再回到这里，我会自己认出来。"
            case .newbie: "那我推荐从 Claude 桌面版开始，最省事：装好、登录，再回到这里，我会自己认出来。不急的话也可以以后再说。"
            }
        }
    }
    enum AIMode: Hashable { case choose, found, missing, trying }
    @State private var aiMode: AIMode = .choose
    @State private var family: AIFamily?
    /// 找到了、还没连的工具。
    @State private var toConnect: [AIApp] = []
    @State private var partner: MascotCharacter?
    @State private var tryStartedAt = Date()
    @Environment(\.openURL) private var openURL
    private let trySentence = "用夏夏账本看看我这个月花了多少"
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
                case .found:
                    HStack(spacing: 10) {
                        secondary("换一个") { backToFamilies() }
                        primary("帮我连上", id: "welcome.ai.connect", tint: .aiSolid) { Task { await connectFound() } }
                    }
                case .missing:
                    HStack(spacing: 10) {
                        secondary("换一个") { backToFamilies() }
                        secondary("以后再说") { Task { await skipAI() } }
                        primary("去下载 \(family?.install.name ?? "")", id: "welcome.ai.download", tint: .aiSolid) {
                            if let u = (family?.install.url).flatMap(URL.init(string:)) { openURL(u) }
                        }
                    }
                case .trying:
                    HStack(spacing: 10) {
                        Text("「\(trySentence)」").font(.callout.weight(.medium)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            Clipboard.copy(trySentence)
                            model.toast = .init(text: "已复制，去你的 AI 里粘贴发出去", changeID: nil)
                        } label: { Label("复制这句话", systemImage: "doc.on.doc") }
                            .buttonStyle(.softAI)
                            .accessibilityIdentifier("welcome.ai.copyTry")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("等你的 AI 来读账本…").font(.caption).foregroundStyle(Color.fg2)
                        Spacer()
                        secondary("先跳过") { Task { await skipTry() } }
                    }
                }
            }
        case .done:
            HStack(spacing: 10) {
                secondary("先逛逛") { finish(openAdd: false) }
                primary("记第一笔", id: "welcome.done.add") { finish(openAdd: true) }
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
        let linked = f.apps.filter { c.isConnected($0) }
        toConnect = f.apps.filter { c.isInstalled($0) && !c.isConnected($0) }
        if !toConnect.isEmpty {
            withAnimation(.bouncy) { partner = f.partner; aiMode = .found }
            await say("找到了！这台 Mac 上有：", items: toConnect.map(\.name), pose: .cheer)
            await say("要我现在帮你连上吗？我只在它的设置里加上「夏夏账本」这一项，别的都不动。", pose: .idle)
        } else if !linked.isEmpty {
            withAnimation(.bouncy) { partner = f.partner }
            await say("这些已经连着了，不用再弄：", items: linked.map(\.name), pose: .cheer)
            await startTry(linked)
        } else {
            withAnimation(.snappy) { aiMode = .missing }
            await say(f.missingNote, pose: f == .newbie ? .idle : .worried)
        }
    }

    private func backToFamilies() {
        answer("换一个")
        withAnimation(.snappy) { partner = nil; family = nil; aiMode = .choose }
    }

    private func connectFound() async {
        guard let c = model.aiConnector else { return }
        answer("帮我连上")
        var done: [AIApp] = []
        var failed: [String] = []
        for app in toConnect {
            do { try AISetup(connector: c).connect(app); done.append(app) }
            catch { failed.append("\(app.name)：\(error.localizedDescription)") }
        }
        if !failed.isEmpty { await say("有的没连上：\(failed.joined(separator: "；"))。等下可以去「设置」里再试。", pose: .worried) }
        if done.isEmpty { await wrapUp(); return }
        await say("设置写好了：", items: done.map(\.name), pose: .write)
        await startTry(done)
    }

    /// 真的试一句：AI 来读账本（fin 握手）才算连上。
    private func startTry(_ apps: [AIApp]) async {
        tryStartedAt = Date()
        withAnimation(.snappy) { aiMode = .trying }
        let how = apps.first.map { "先\($0.afterConnect)，再" } ?? ""
        await say("最后真的试一下：\(how)跟它说下面这句话。它一来读账本，我马上告诉你。", pose: .think)
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

    /// 每 2 秒看一眼：等装好的工具出现；等 AI 真的来读账本。
    private func watchAI() async {
        guard aiMode == .missing || aiMode == .trying else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !typing, step == .ai, let c = model.aiConnector else { continue }
            if aiMode == .missing, let f = family {
                let found = f.apps.filter { c.isInstalled($0) && !c.isConnected($0) }
                if !found.isEmpty {
                    toConnect = found
                    typing = true
                    withAnimation(.bouncy) { partner = f.partner; aiMode = .found }
                    // 换了 aiMode 这个任务会被取消，接下来的话另起一个任务说完。
                    Task {
                        await say("认出来了！你装好了：", items: found.map(\.name), pose: .cheer)
                        await say("要我现在帮你连上吗？我只在它的设置里加上「夏夏账本」这一项，别的都不动。", pose: .idle)
                    }
                    return
                }
            } else if aiMode == .trying, !model.usesSampleData {
                let fresh = AIConnections.load().filter { $0.value > tryStartedAt }
                if let who = fresh.max(by: { $0.value < $1.value })?.key {
                    model.refreshIfChanged()
                    await say("连上了！我看到 \(AIApp.displayName(clientName: who)) 刚刚来读账本了。", pose: .celebrate)
                    await wrapUp()
                    return
                }
            }
        }
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
