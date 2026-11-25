import FinanceCore
import SwiftUI

// 第一次打开（账本里还没有账户、没有流水）的开始引导。样子照 ming 给的稿（design/mockups/welcome-ming-2026-11-22.png）：
// 左边一大块是夏夏（会动、会说话的气泡、飘着的泡泡），右边是四步：① 目标 ② 账本 ③ 账户 ④ 连接 AI（只在 Mac）。
// 最后一步（Mac、装了 Claude Code / Codex / Hermes 时）问要不要打开内置夏夏：右边的对话栏，以后一打开 app 就在。
// 「目标」是用户记账最想做到的事（存进 profile.aim）：夏夏给意见、AI 帮忙记账都围着它说，最后撒花也祝的是它。
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

    enum Step: Int { case hello, aim, books, accounts, ai, chat, done }

    /// 第一步「你记账最想做到什么」的几个现成答案。
    struct AimOption: Identifiable, Hashable {
        var id: String
        var title: String
        var symbol: String
        /// 存进 profile.aim 的那句话。
        var aim: String
        /// 夏夏听到后回的话。
        var reply: String
    }

    static var aimOptions: [AimOption] { [
        AimOption(id: "save", title: tr("每个月存下一笔钱"), symbol: "banknote", aim: "", reply: tr("好目标！我每个月帮你盯着。")),
        AimOption(id: "clarity", title: tr("搞清楚钱都花哪了"), symbol: "chart.pie", aim: tr("搞清楚钱都花哪了"), reply: tr("交给我，每一笔都给你分好类。")),
        AimOption(id: "less", title: tr("少花冤枉钱"), symbol: "cart.badge.minus", aim: tr("少花冤枉钱，比如外卖和冲动网购"), reply: tr("好，花多了我会提醒你。")),
        AimOption(id: "debt", title: tr("先把欠的钱还清"), symbol: "creditcard", aim: tr("先把信用卡和欠的钱还清"), reply: tr("一笔一笔来，我陪你还完。")),
        AimOption(id: "wish", title: tr("攒钱实现一个心愿"), symbol: "gift", aim: tr("攒够钱，实现一个心愿"), reply: tr("真好！心愿是什么，待会儿可以告诉 AI。")),
        AimOption(id: "shop", title: tr("把生意的账管清楚"), symbol: "storefront", aim: tr("把生意的收入和支出管清楚"), reply: tr("好，生意的账和生活的分开算。")),
    ] }
    /// 第一页「你平时用哪种钱？」直接摆出来的币种；别的从「别的币种」菜单里挑。
    static let commonCurrencies = ["EUR", "CNY", "USD", "GBP", "HKD", "JPY"]

    /// 目标里的金额：「300 €」「1.000 ¥」（整数不写 ,00）。
    static func goalAmount(_ m: Money, _ currency: String) -> String {
        m.formatted(in: currency).replacingOccurrences(of: ",00 ", with: " ")
    }

    /// 用户敲的金额：只认数字和 , .，大于 0 才算。
    static func parseAmount(_ text: String) -> Money? {
        let kept = String(text.filter { $0.isNumber || $0 == "," || $0 == "." })
        guard let m = Money(parsing: kept), m.cents > 0 else { return nil }
        return m
    }

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
            case .other: tr("DeepSeek 或别的")
            case .newbie: tr("还没用过 AI")
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
        /// 没装的话装哪个、去哪下。
        var install: (name: String, url: String) {
            switch self {
            case .claude, .newbie: (tr("Claude 桌面版"), "https://claude.ai/download")
            case .chatgpt: ("Codex", "https://openai.com/codex/")
            case .gemini: ("Gemini CLI", "https://github.com/google-gemini/gemini-cli")
            case .other: ("Hermes Agent", "https://hermes-agent.nousresearch.com")
            }
        }
    }

    enum AIMode: Hashable { case choose, trying }

    @State private var step: Step = .hello
    @State private var pose: MascotPose = .hello
    /// 夏夏和伙伴用女生版还是男生版（第一页选，设置里也能改）。
    @AppStorage(MascotLook.storageKey) private var lookRaw = MascotLook.girl.rawValue
    /// 第一页填的：助手叫什么、怎么称呼你（点「开始」时存进账本，设置里能改）。
    @State private var assistantNameText = ""
    @State private var callUserText = ""
    /// 夏夏头上的气泡。
    @State private var speech = ""
    @State private var thinking = false

    @State private var bookChoices: [Choice] = [
        Choice(name: tr("家庭"), symbol: "house"),
        Choice(name: tr("我的小店"), symbol: "storefront", bookKind: .business),
        Choice(name: tr("旅行"), symbol: "airplane"),
    ]
    @State private var pickedBooks: Set<String> = []
    /// 第一次打开二选一：nil = 还没选，false = 只记生活，true = 生活和生意都记。
    @State private var withShop: Bool?
    /// 选了生意：店是不是新开的（新开的才算回本）、开店投了多少。
    @State private var newShop: Bool?
    @State private var capitalText = ""
    /// 第一步选的目标（现成的 id，或 "custom"）。
    @State private var pickedAim: String?
    /// 每个月想存多少：用户自己填。
    @State private var saveAmountText = ""
    @FocusState private var amountFocused: Bool
    /// 第一页选的币种（nil = 还没动，用建议的那个）。
    @State private var pickedCurrency: String?
    @State private var customAim: String?
    @State private var accountChoices: [Choice] = [
        Choice(name: tr("现金"), glyph: AccountKind.cash.glyph, accountKind: .cash),
        Choice(name: tr("银行卡"), glyph: AccountKind.bank.glyph, accountKind: .bank),
        Choice(name: tr("信用卡"), glyph: AccountKind.credit.glyph, accountKind: .credit),
        Choice(name: tr("支付宝"), glyph: AccountKind.wallet.glyph, accountKind: .wallet),
        Choice(name: tr("微信支付"), glyph: AccountKind.wallet.glyph, accountKind: .wallet),
        Choice(name: "PayPal", glyph: AccountKind.wallet.glyph, accountKind: .wallet),
        Choice(name: tr("存钱罐"), glyph: AccountKind.savings.glyph, accountKind: .savings),
    ]
    @State private var pickedAccounts: Set<String> = ["现金", "银行卡"]
    @State private var custom = ""

    @State private var aiMode: AIMode = .choose
    @State private var family: AIFamily?
    /// 刚点了哪一家、正在看它连没连上（这一小会儿要让人看得出在忙）。
    @State private var checking: AIFamily?
    /// 这一家的工具里已经连着的（设置里有夏夏账本）。
    @State private var linked: [AIApp] = []
    /// 这台 Mac 上有、还没连的。
    @State private var toConnect: [AIApp] = []
    @State private var tryStartedAt = Date()
    /// AI 真的来读过账本了（fin 握手）。
    @State private var handshakeSeen = false
    /// 刚刚由夏夏写好设置的那个工具（要先重开它才看得到账本）。
    @State private var justConnected: AIApp?
    /// 连着了但一直没等到 AI 来：等了几轮（提醒一次「网页版连不到」）。
    @State private var waitTicks = 0
    /// 点过「复制指令」了：从这时起才算「在等 AI 来」。
    @State private var copiedSentence = false
    @State private var knownTransactions: Set<UUID> = []
    @State private var knownGoals: Set<UUID> = []
    /// AI 连上了：结尾是庆祝，不是「记第一笔试试」。
    @State private var celebrated = false
    @State private var celebrationNote: String?
    @State private var celebrationGoal: String?
    @State private var confetti = false
    /// 内置夏夏用哪个 AI 回答（ChatEngine 的 rawValue；只在 Mac 有）。
    @State private var chatPick: String?
    /// 内容区不够高：每页收紧一些，保证不用往下滚。
    @State private var tight = false

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
                        // 左边夏夏让出位置：右边内容至少留 640 宽，窄窗口里选项、步骤条才不会被裁掉。
                        let heroWidth = max(180, min(geo.size.width * 0.4, 560, geo.size.width - 112 - 640))
                        hero(mascot: min(geo.size.height * 0.58, heroWidth * 0.72))
                            .frame(width: heroWidth)
                            .clipped()
                        content(padding: 56, wide: true)
                    }
                } else {
                    VStack(spacing: 0) {
                        hero(mascot: 120).frame(height: min(250, geo.size.height * 0.32)).clipped()
                        content(padding: 20, wide: false)
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
                    HStack(alignment: .bottom, spacing: 0) {
                        MascotView(pose: pose, size: size, talking: thinking)
                            .id(pose)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    .padding(.bottom, size * 0.05)
                    .background(alignment: .bottom) {
                        // 脚下的水波：画在背景里，不撑大这一栏
                        ZStack(alignment: .bottom) {
                            ForEach(0..<3, id: \.self) { i in
                                Ellipse().stroke(Color.white.opacity(0.6 - Double(i) * 0.15), lineWidth: 1.5)
                                    .frame(width: size * (0.7 + CGFloat(i) * 0.22), height: size * (0.14 + CGFloat(i) * 0.05))
                                    .offset(y: size * 0.025 * CGFloat(i))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speech.isEmpty ? model.xiaName : tr("\(model.xiaName)说：\(speech)"))
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

    private func content(padding: CGFloat, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 28) {
                // 放得下就每一步都写字；放不下只写当前这一步，别的只留圆点。
                ViewThatFits(in: .horizontal) {
                    stepper(big: wide, allLabels: true)
                    stepper(big: false, allLabels: true)
                    stepper(big: false, allLabels: false)
                }
                if step != .done {
                    Button(tr("以后再说")) { model.finishWelcome() }
                        .buttonStyle(.borderless).foregroundStyle(Color.fg2)
                        .fixedSize()
                        .accessibilityIdentifier("welcome.skip")
                }
            }
            // 内容在剩下的高度里上下居中；窗口矮了就能滚。
            GeometryReader { area in
                ScrollView {
                    page
                        .environment(\.welcomeBig, wide && !tight)
                        .frame(maxWidth: 780, alignment: .leading)
                        .frame(maxWidth: .infinity, minHeight: area.size.height, alignment: .leading)
                        .id(pageKey)
                        // 旧的一页很快淡掉，新的一页再滑进来：两页不会叠在一起看着花。
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity).animation(.smooth(duration: 0.35).delay(0.08)),
                                                removal: .opacity.animation(.easeOut(duration: 0.08))))
                }
                .scrollBounceBehavior(.basedOnSize)
                // 窗口矮（比如最小的 1000×612）：标题、演示、选项都收小一号，按钮留在一屏里。
                .onGeometryChange(for: Bool.self) { $0.size.height < 520 } action: { tight = $0 }
            }
            if canGoBack {
                Button { goBack() } label: { Label(tr("返回"), systemImage: "chevron.left") }
                    .buttonStyle(.borderless).foregroundStyle(Color.fg2)
                    .padding(.top, 10)
                    .accessibilityIdentifier("welcome.back")
            }
        }
        // 上下留白比左右少：每一页都要在一屏里放下，不用往下滚。
        .padding(.horizontal, padding).padding(.vertical, wide ? 32 : padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pageKey: String { "\(step.rawValue)-\(aiMode == .choose ? "a" : "b")-\(celebrated)" }

    private var stepNames: [String] {
        var names = [tr("目标"), tr("账本"), tr("账户")]
        if aiStepAvailable { names.append(tr("连接 AI")) }
        if chatStepAvailable { names.append(tr("内置夏夏")) }
        return names
    }

    private func stepper(big: Bool, allLabels: Bool) -> some View {
        let dot: CGFloat = big ? 34 : 26
        return HStack(spacing: big ? 14 : 8) {
            ForEach(Array(stepNames.enumerated()), id: \.offset) { i, name in
                let number = i + 1
                let done = step.rawValue > number
                let current = step.rawValue == number
                if i > 0 {
                    Capsule().fill(step.rawValue >= number ? Color.ai.opacity(0.45) : Color.fg3.opacity(0.22))
                        .frame(height: 2).frame(minWidth: 16, maxWidth: .infinity)
                }
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(current ? Color.aiSolid : done ? Color.ai.opacity(0.18) : Color.fg3.opacity(0.15))
                        if done {
                            Image(systemName: "checkmark").font((big ? Font.subheadline : .caption).weight(.bold)).foregroundStyle(Color.ai)
                        } else {
                            Text("\(number)").font((big ? Font.subheadline : .caption).weight(.bold)).foregroundStyle(current ? Color.white : Color.fg2)
                        }
                    }
                    .frame(width: dot, height: dot)
                    if allLabels || current {
                        Text(name).font((big ? Font.title3 : .subheadline).weight(current ? .semibold : .regular))
                            .foregroundStyle(current ? Color.ai : Color.fg2)
                            .lineLimit(1).fixedSize()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("第 \(number) 步，\(name)") + (done ? tr("，完成") : current ? tr("，正在这一步") : ""))
            }
        }
        .animation(.snappy, value: step)
        .opacity(step == .hello ? 0 : 1)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .hello:
            pageBody(tr("让我们开始记账吧"), tr("我是\(typedName)，以后陪你记账。先问你\(["", tr("一"), tr("两"), tr("三"), tr("四"), tr("五"), tr("六")][min(stepNames.count, 6)])个小问题，一分钟就好。")) {
                currencyPicker
                namesRow
                if MascotLook.boyAvailable { lookPicker }
            } buttons: {
                primary(tr("开始"), id: "welcome.start") { Task { await toAim() } }
            }
        case .aim:
            pageBody(tr("你记账最想做到什么？"), tr("选一个最重要的。以后\(model.xiaName)给你意见、AI 帮你记账，都会围着它说。")) {
                FlowLayout(spacing: 8) {
                    ForEach(Self.aimOptions) { o in
                        chip(o.title, symbol: o.symbol, on: pickedAim == o.id) { pickAim(o.id) }
                    }
                    if let customAim {
                        chip(customAim, symbol: "pencil", on: pickedAim == "custom") { pickAim("custom") }
                    }
                }
                if pickedAim == "save" {
                    // 存钱要有个数才好盯：点一个，夏夏按这个数每月看你存没存到。
                    HStack(spacing: 10) {
                        Text(tr("每个月想存")).font(.title3).foregroundStyle(Color.fg2)
                        TextField(tr("比如 300"), text: $saveAmountText)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                            .frame(width: 130)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.pageBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(amountFocused ? Color.aiLine : Color.fg3.opacity(0.22), lineWidth: amountFocused ? 2 : 1))
                            .accessibilityLabel(tr("每个月想存多少"))
                            .accessibilityIdentifier("welcome.aim.amount")
                        Text(Currencies.info(model.ledger.baseCurrency).symbol).font(.title3.weight(.semibold))
                        if !saveAmountText.isEmpty && Self.parseAmount(saveAmountText) == nil {
                            Text(tr("填个数字就行")).font(.callout).foregroundStyle(Color.alert)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                customField(tr("自己写一个，比如「明年攒够房子首付」")) { text in
                    customAim = text
                    if pickedAim == "custom" { Task { await say(tr("好，我记住了！"), pose: .cheer) } } else { pickAim("custom") }
                }
                if let aimText, !tight {
                    HStack(spacing: 10) {
                        Image(systemName: "flag.checkered").foregroundStyle(Color.ai)
                        Text(tr("我的目标：")).foregroundStyle(Color.fg2)
                        Text(aimText).fontWeight(.semibold)
                    }
                    .font(.title3)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.aiLine, lineWidth: 1))
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("welcome.aim.summary")
                }
            } buttons: {
                primary(aimText == nil ? tr("先不定，下一步") : tr("就定这个"), id: "welcome.aim.next") { Task { await toBooks() } }
            }
        case .books:
            // ming 2026-11-25：第一次打开二选一——只记生活 / 生活和生意都记；选生意再问店是不是新开的。
            pageBody(tr("你想记哪些钱？"), tr("生活和店里的钱分开算，账户也分两边。以后在 设置 → 生意模式 随时能改。")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        sideCard(tr("只记生活"), detail: tr("家里的吃穿住行、存钱、还款"), symbol: "house.fill", on: withShop == false) {
                            withShop = false
                        }
                        .accessibilityIdentifier("welcome.side.life")
                        sideCard(tr("生活和生意都记"), detail: tr("再加一边，算店里真正赚了多少"), symbol: "storefront.fill", on: withShop == true) {
                            withShop = true
                        }
                        .accessibilityIdentifier("welcome.side.both")
                    }
                    if withShop == true {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("店是新开的吗？")).font(.headline)
                            HStack(spacing: 8) {
                                chip(tr("新开的，想知道什么时候回本"), symbol: "sparkles", on: newShop == true) { newShop = true }
                                chip(tr("开了一阵了"), symbol: "clock", on: newShop == false) { newShop = false }
                            }
                            if newShop == true {
                                HStack(spacing: 8) {
                                    Text(tr("开店一共投了多少")).foregroundStyle(Color.fg2)
                                    TextField(tr("可以先不填"), text: $capitalText)
                                        .textFieldStyle(.roundedBorder).frame(width: 140)
                                        .accessibilityIdentifier("welcome.capital")
                                    Text(model.ledger.baseCurrency).foregroundStyle(Color.fg3)
                                }
                                .font(.callout)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } buttons: {
                primary(tr("下一步"), id: "welcome.books.next") { Task { await toAccounts() } }
                    .disabled(withShop == nil)
            }
        case .accounts:
            pageBody(tr("钱平时放在哪？"), tr("有的就点一下，没有的可以自己加。余额以后随时能填。")) {
                FlowLayout(spacing: 8) {
                    ForEach(accountChoices) { c in
                        let made = model.ledger.accounts.contains { $0.name == c.name }
                        chip(c.name, glyph: c.glyph, on: made || pickedAccounts.contains(c.name), locked: made) { toggle(&pickedAccounts, c.name) }
                    }
                }
                customField(tr("自己加一个，比如某家银行的名字")) { name in
                    if !accountChoices.contains(where: { $0.name == name }) {
                        accountChoices.append(Choice(name: name, glyph: AccountKind.bank.glyph, accountKind: .bank))
                    }
                    pickedAccounts.insert(name)
                }
            } buttons: {
                primary(tr("下一步"), id: "welcome.accounts.next") { Task { await toAI() } }
            }
        case .ai:
            if aiMode == .choose {
                pageBody(tr("连接你的 AI"), tr("连接后，用一句话就能记账、查账。你平时用哪个？")) {
                    FlowLayout(spacing: 8) {
                        ForEach(AIFamily.allCases) { f in
                            chip(f.title, symbol: f == .newbie ? "questionmark.circle" : "sparkles", on: checking == f) { Task { await choose(f) } }
                                .opacity(checking == nil || checking == f ? 1 : 0.45)
                        }
                    }
                    .allowsHitTesting(checking == nil)
                    if let checking {
                        // 点下去马上有回应：选中的那个变色，下面转圈说在干什么。
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(checking == .newbie ? tr("正在看这台 Mac 上有没有装 AI…") : tr("正在看这台 Mac 上的 \(checking.title) 连上没有…"))
                                .font(.subheadline).foregroundStyle(Color.fg2)
                        }
                        .transition(.opacity)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("welcome.ai.checking")
                    }
                } buttons: {
                    secondary(tr("先跳过")) { Task { await skipAI() } }
                }
            } else {
                pageBody(tryTitle, trySubtitle) {
                    if !linked.isEmpty {
                        // 连着了：去 AI 里说这一句人话就行，怎么带着记第一笔由账本自己告诉 AI。
                        Text("「\(AIConnector.welcomeSentence)」")
                            .font(.title3.weight(.medium))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 22).padding(.vertical, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.aiLine, lineWidth: 1))
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            if handshakeSeen {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                                Text(tr("已经读到账本，等它帮你记第一笔")).font(.subheadline).foregroundStyle(Color.fg2)
                            } else {
                                ProgressView().controlSize(.small)
                                Text(tr("等待你的 AI 读取账本")).font(.subheadline).foregroundStyle(Color.fg2)
                            }
                        }
                    } else if toConnect.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(tr("装好以后我会自己认出来")).font(.subheadline).foregroundStyle(Color.fg2)
                        }
                    }
                } buttons: {
                    if !linked.isEmpty {
                        primary(tr("复制指令"), symbol: "doc.on.doc", id: "welcome.ai.copyPrompt") {
                            Clipboard.copy(AIConnector.welcomeSentence)
                            copiedSentence = true
                            waitTicks = 0
                            model.toast = .init(text: tr("已复制，去你的 AI 里粘贴发出去"), changeID: nil)
                        }
                    } else if !toConnect.isEmpty {
                        primary(tr("帮我连上"), symbol: "link", id: "welcome.ai.connect") { Task { await connectFound() } }
                    } else if let f = family {
                        primary(tr("去下载 \(f.install.name)"), symbol: "arrow.down.circle", id: "welcome.ai.download") {
                            if let u = URL(string: f.install.url) { openURL(u) }
                        }
                    }
                    if handshakeSeen {
                        secondary(tr("好了，进账本")) { Task { await celebrate(who: nil, note: nil, goal: nil) } }
                    } else {
                        secondary(tr("先跳过")) { Task { await skipAI() } }
                    }
                } extras: {
                    if linked.isEmpty {
                        // 用的是别的 AI 工具：让它照着配置指令自己连。
                        link(tr("用的是别的 AI？复制配置指令粘给它"), symbol: "doc.on.doc") {
                            Clipboard.copy(model.aiSetupPrompt)
                            model.toast = .init(text: tr("已复制配置指令，粘给你的 AI，它会自己连上"), changeID: nil)
                        }
                    } else if isPretend {
                        link(tr("演示：假装 AI 记了一笔"), symbol: "wand.and.stars") {
                            Task { await celebrate(who: family?.title ?? "AI", note: tr("咖啡 -3,50 €"), goal: nil) }
                        }
                    }
                }
            }
        case .chat:
            #if os(macOS)
            chatPage
            #else
            EmptyView()
            #endif
        case .done:
            if celebrated {
                pageBody(tr("🎉 恭喜，连接成功！"), celebrationText) {
                    EmptyView()
                } buttons: {
                    primary(tr("进入夏夏账本"), id: "welcome.done.enter") { finish(openAdd: false) }
                }
            } else {
                pageBody(tr("都准备好了！"), tr("现在记第一笔试试？\(aiStepAvailable ? tr("想连 AI 的时候，去「设置」里点「连接你的 AI」。") : "")")) {
                    EmptyView()
                } buttons: {
                    primary(tr("记第一笔"), id: "welcome.done.add") { finish(openAdd: true) }
                    secondary(tr("先逛逛")) { finish(openAdd: false) }
                }
            }
        }
    }

    #if os(macOS)
    /// 最后一步：用不用内置夏夏。先说清它是什么，再放一段会动的演示（照真对话栏的样子）。
    private var chatPage: some View {
        let engines = model.chat.available
        let pick = chatPick.flatMap(ChatEngine.init(rawValue:)) ?? model.chat.engine ?? engines.first
        let name = pick?.name ?? "AI"
        return pageBody(tr("要不要用内置夏夏？"), tr("内置夏夏就是窗口右边的一个聊天栏。不用切到别的 app，打字就能记账、查账。")) {
            if celebrated {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                    Text(celebrationNote.map { tr("AI 连上了，第一笔记下了：\($0)") } ?? tr("AI 连上了！")).font(.subheadline).foregroundStyle(Color.fg2)
                }
            }
            // 演示和说明并排放，一屏看完不用往下滚（ming：「不要让我下拉」）。窗口窄就把演示收窄，再窄只留演示。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    ChatDemo(engineName: name, height: tight ? 120 : 196).frame(width: 300)
                    chatSide(name, pick: pick, engines: engines).frame(minWidth: 220, idealWidth: 240, maxWidth: 400, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 18) {
                    ChatDemo(engineName: name, height: tight ? 120 : 196).frame(width: 250)
                    chatSide(name, pick: pick, engines: engines).frame(minWidth: 190, idealWidth: 200, maxWidth: 400, alignment: .leading)
                }
                ChatDemo(engineName: name, height: tight ? 120 : 196).frame(width: 300)
            }
        } buttons: {
            primary(tr("用内置夏夏"), symbol: "bubble.left.and.text.bubble.right", id: "welcome.chat.on") { Task { await chooseChat(true) } }
            secondary(tr("先不用")) { Task { await chooseChat(false) } }
        } extras: {
            if !tight {
            Text(tr("选「先不用」右边就不出现，「问夏夏」会把问题复制好打开 Claude。以后在「设置」里随时能开。"))
                .font(.callout).foregroundStyle(Color.fg3)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 演示右边：三句话说清它能做什么，有几个 AI 就顺便选用哪个。
    private func chatSide(_ name: String, pick: ChatEngine?, engines: [ChatEngine]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            chatFacts(name)
            if engines.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("用哪个 AI 来回答")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.fg2)
                    Picker(tr("用哪个 AI 来回答"), selection: Binding(get: { pick?.rawValue ?? "" }, set: { chatPick = $0 })) {
                        ForEach(engines) { e in Text(e.name).tag(e.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
    }

    /// 内置夏夏能做什么、和别的 AI 什么关系、不用会怎样：三句话。
    private func chatFacts(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            fact("text.bubble", tr("说一句就记账、查账"), tr("记好的账马上出现在页面上，能撤销。"))
            fact("eye", tr("知道你在看哪一页"), tr("停在花销页问「为什么这么多」，她知道你说的是哪些。"))
            fact("cpu", tr("借你电脑上的 \(name) 回答"), tr("用你自己的订阅，不另外收费。"))
        }
    }

    private func fact(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.headline).foregroundStyle(Color.ai)
                .frame(width: 32, height: 32)
                .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if !tight {
                    Text(detail).font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 32)
        }
        .accessibilityElement(children: .combine)
    }
    #endif

    private var tryTitle: String {
        guard let f = family else { return tr("连接你的 AI") }
        if !linked.isEmpty { return tr("\(f == .newbie ? "Claude" : f.title) 连接上了") }
        return f == .newbie ? tr("先装一个 AI") : tr("还没有连接上")
    }

    private var trySubtitle: String {
        guard let f = family else { return "" }
        if let first = linked.first {
            if let justConnected { return tr("记账工具我已经装进 \(justConnected.name) 了，不用你再配置。先\(justConnected.afterConnect)，再把下面这段话发给它。") }
            return tr("记账工具已经装在 \(first.name) 里了，不用你再配置。把下面这段话发给它，它会带你记下第一笔。")
        }
        if !toConnect.isEmpty {
            // 说清楚这几个是什么、点了会发生什么：新用户不一定认识 Codex、Hermes 这些名字。
            let names = toConnect.map { "\($0.name)（\($0.plainWords)）" }.joined(separator: "、")
            return tr("这台 Mac 上有 \(names)。点一下，我就把「夏夏账本」这个记账工具装进去，它才读得到账本。它别的设置我都不动，以后想拿掉，去「设置」里点一下就行。")
        }
        switch f {
        case .newbie: return tr("推荐从 Claude 桌面版开始，最省事。装好、登录，我会自己认出来，再帮你连上。")
        case .chatgpt: return tr("ChatGPT 要通过它家的 Codex 才能读到这台电脑上的账本，用的还是你的 ChatGPT 账号。装好以后我再帮你连上。")
        case .other: return tr("DeepSeek 这些要通过 Hermes Agent 这样的助手才能读到这台电脑上的账本。装好以后我再帮你连上。")
        case .claude, .gemini: return tr("这台 Mac 上没找到 \(f.install.name)。装好以后我再帮你连上。")
        }
    }

    /// 第一步选好的目标，存进账本的那句话（没选就是 nil）。
    /// 建议的币种：账本里已经有账就用账本的主币种；新账本按这台电脑的地区猜（西班牙 → 欧元，中国 → 人民币）。
    private var suggestedCurrency: String {
        let base = model.ledger.baseCurrency
        guard model.ledger.transactions.isEmpty,
              let local = Locale.current.currency?.identifier.uppercased(), Currencies.isKnown(local) else { return base }
        return base == "EUR" ? local : base
    }

    private var currencyChoice: String { pickedCurrency ?? suggestedCurrency }

    /// 第一页：你平时用哪种钱？常用的直接摆出来，别的在菜单里。
    /// 第一页现在填的助手名字（没填就是「夏夏」）。
    private var typedName: String {
        let t = assistantNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? model.xiaName : String(t.prefix(12))
    }

    /// 第一页：给助手起名字、它怎么称呼你（ming 2026-11-23：「引导的时候可以改夏夏称呼，比如我想叫我什么，怎么称呼用户」）。
    private var namesRow: some View {
        HStack(alignment: .top, spacing: 16) {
            nameField(tr("叫我"), placeholder: model.xiaName, text: $assistantNameText, id: "welcome.name.assistant")
            nameField(tr("我怎么叫你"), placeholder: tr("比如 小明，不填就叫「你」"), text: $callUserText, id: "welcome.name.user")
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func nameField(_ title: String, placeholder: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Color.fg2)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.pageBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.fg3.opacity(0.22), lineWidth: 1))
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 第一页：夏夏想要女生还是男生的样子（ming 2026-11-23：「界面男女角色也要加上」）。左边的夏夏马上跟着换。
    private var lookPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("夏夏想要什么样子？")).font(.headline).foregroundStyle(Color.fg2)
            HStack(spacing: 8) {
                ForEach(MascotLook.kidChoices) { l in
                    chip(l.label, symbol: l == .girl ? "face.smiling" : "face.smiling.inverse", on: lookRaw == l.rawValue) {
                        // 每次点都记「自己挑过」（点已经亮着的那个也算）；样子真的变了才播动画、说话。
                        guard MascotLook.pick(l) else { return }
                        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { lookRaw = l.rawValue }
                        Task { await say(l == .girl ? tr("好呀，就这样陪你记账～") : tr("好，换个样子陪你记账！"), pose: .cheer) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.look")
    }

    private var currencyPicker: some View {
        let choice = currencyChoice
        var codes = Self.commonCurrencies
        if !codes.contains(choice) { codes.insert(choice, at: 0) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("你平时用哪种钱？")).font(.headline).foregroundStyle(Color.fg2)
            FlowLayout(spacing: 8) {
                ForEach(codes, id: \.self) { code in
                    let i = Currencies.info(code)
                    chip("\(i.name) \(i.symbol)", symbol: "banknote", on: choice == code) { pickedCurrency = code }
                }
                Menu {
                    ForEach(Currencies.all.filter { !codes.contains($0.code) }, id: \.code) { c in
                        Button("\(c.name) \(c.symbol)") { withAnimation(.snappy) { pickedCurrency = c.code } }
                    }
                } label: {
                    Text(tr("别的币种")).font(.title3.weight(.medium))
                }
                .menuStyle(.button).buttonStyle(.borderless)
                .fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 11)
                .accessibilityIdentifier("welcome.currency.more")
            }
            Text(tr("账上的总数都按它算。有外币卡也没关系，加账户时能单独设，以后在「设置」里也能改。"))
                .font(.callout).foregroundStyle(Color.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("welcome.currency")
    }

    private var aimText: String? {
        guard let pickedAim else { return nil }
        if pickedAim == "custom" { return customAim }
        if pickedAim == "save" {
            guard let m = Self.parseAmount(saveAmountText) else { return tr("每个月存下一笔钱") }
            return tr("每个月存下 \(Self.goalAmount(m, model.ledger.baseCurrency))")
        }
        return Self.aimOptions.first { $0.id == pickedAim }?.aim
    }

    private var celebrationText: String {
        var parts: [String] = []
        if let celebrationNote { parts.append(tr("第一笔记下了：\(celebrationNote)。")) }
        if let celebrationGoal {
            parts.append(tr("祝你早日达成「\(celebrationGoal)」！"))
        } else if let aim = model.ledger.profile.aim {
            parts.append(tr("祝你早日做到「\(aim)」！"))
        } else {
            parts.append(tr("祝你想存的钱都存到，心愿一个个达成。"))
        }
        parts.append(tr("让我们一起努力吧！"))
        return parts.joined(separator: "\n")
    }

    // MARK: 小零件

    /// 一页：大标题、一句说明、中间的选项、底下一排按钮、再底下几个小链接。
    private func pageBody<Main: View, Buttons: View, Extras: View>(
        _ title: String, _ subtitle: String,
        @ViewBuilder main: () -> Main, @ViewBuilder buttons: () -> Buttons, @ViewBuilder extras: () -> Extras
    ) -> some View {
        let mainView = main(), buttonsView = buttons(), extrasView = extras()
        return WelcomeSized { big in
        VStack(alignment: .leading, spacing: big ? 26 : 18) {
            VStack(alignment: .leading, spacing: big ? 14 : 10) {
                Text(title)
                    .font(.system(size: big ? 54 : 34, weight: .heavy))
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.title3).foregroundStyle(Color.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            mainView
            FlowLayout(spacing: 12) { buttonsView }.padding(.top, 4)
            FlowLayout(spacing: 16) { extrasView }
        }
        .padding(.vertical, tight ? 4 : 16)
        }
    }

    private func pageBody<Main: View, Buttons: View>(
        _ title: String, _ subtitle: String,
        @ViewBuilder main: () -> Main, @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        pageBody(title, subtitle, main: main, buttons: buttons, extras: { EmptyView() })
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
                Text(title).font((tight ? Font.body : .title3).weight(.medium))
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, tight ? 14 : 18).padding(.vertical, tight ? 8 : 11)
            .background(on ? Color.aiSolid : Color.pageBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : Color.fg3.opacity(0.22), lineWidth: 1))
            .scaleEffect(on ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!locked)   // 已经有的：不能取消，但不变灰
        .accessibilityLabel(title)
        .accessibilityValue(locked ? tr("已经有了") : on ? tr("已选") : tr("没选"))
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
                .font(.body)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.pageBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.fg3.opacity(0.22), lineWidth: 1))
                .accessibilityIdentifier("welcome.custom")
            Button(action: submit) { Label(tr("加上"), systemImage: "plus") }
                .buttonStyle(.softAI)
                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: 480)
    }

    private func primary(_ title: String, symbol: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.title3.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 30).padding(.vertical, 15)
            .frame(minWidth: 170)
            .background(Color.aiSolid, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier(id)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.title3.weight(.medium)).foregroundStyle(Color.primary)
                .padding(.horizontal, 30).padding(.vertical, 15)
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

    private var canGoBack: Bool { step == .aim || step == .books || step == .accounts || step == .ai || (step == .chat && !celebrated) }

    private func goBack() {
        switch step {
        case .aim: go(.hello)
        case .books:
            go(.aim)
            Task { await say(tr("你记账最想做到什么？"), pose: .think) }
        case .accounts:
            go(.books)
            Task { await say(tr("要几个账本？"), pose: .idle) }
        case .ai:
            if aiMode == .trying {
                withAnimation(.smooth(duration: 0.35)) { aiMode = .choose; family = nil; checking = nil }
                Task { await say(tr("换一个也行，你平时用哪个？"), pose: .think) }
            } else {
                checking = nil
                go(.accounts)
                Task { await say(tr("钱平时放在哪？"), pose: .write) }
            }
        case .chat:
            go(.ai)
            Task { await say(aiMode == .trying ? tr("连接 AI 这一步还在这儿。") : tr("你平时用哪个 AI？"), pose: .think) }
        case .hello, .done: break
        }
    }

    private func start() async {
        guard speech.isEmpty else { return }
        if model.welcomeAtAI, aiStepAvailable {
            // 从「问夏夏」点「去连接 AI」进来的：直接到第三步。
            model.welcomeAtAI = false
            aiMode = .choose
            step = .ai
            await say(tr("你平时用哪个 AI？"), pose: .think)
            return
        }
        model.welcomeAtAI = false
        // 截图、检查用：启动参数 -XiaxiaWelcomeStep aim|books|accounts|ai|chat 直接停在那一页（不用点）。
        let jump: [String: Step] = ["aim": .aim, "books": .books, "accounts": .accounts, "ai": .ai, "chat": .chat]
        if let name = UserDefaults.standard.string(forKey: "XiaxiaWelcomeStep"), let target = jump[name] {
            if target == .aim { pickedAim = "save" }
            step = target
            await say(tr("（检查用：直接到这一页）"), pose: .idle)
            return
        }
        await say(tr("嗨，我是\(model.xiaName)！"), pose: .hello)
    }

    private func toAim() async {
        // 第一页选的币种：定成账本的主币种（进改动记录，能撤销）。目标里的金额、看板上的总数都用它。
        let code = currencyChoice
        if code != model.ledger.baseCurrency {
            _ = try? model.edit(quiet: true) { try $0.setBaseCurrency(code, author: model.author) }
        }
        // 第一页填的名字和称呼（没填的保持原样）。
        let newName = assistantNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCall = callUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty || !newCall.isEmpty {
            let p = model.ledger.profile
            _ = try? model.edit(quiet: true) {
                try $0.setNames(assistant: newName.isEmpty ? p.assistantName : newName,
                                callUser: newCall.isEmpty ? p.userCallName : newCall, author: model.author)
            }
        }
        // 以前定过（比如在「夏夏建议」页）：直接选上，用户点「就定这个」就行。
        if pickedAim == nil, let old = model.ledger.profile.aim {
            if let o = Self.aimOptions.first(where: { $0.aim == old && !$0.aim.isEmpty }) {
                pickedAim = o.id
            } else if old.hasPrefix("每个月存下") {
                pickedAim = "save"
                let digits = old.dropFirst(tr("每个月存下").count).filter { $0.isNumber || $0 == "," || $0 == "." }
                saveAmountText = String(digits)
            } else {
                customAim = old; pickedAim = "custom"
            }
        }
        go(.aim)
        let call = model.ledger.profile.userCallName.map { "\($0)，" } ?? ""
        await say(tr("\(call)先说说，你记账最想做到什么？"), pose: .think)
    }

    private func pickAim(_ id: String) {
        withAnimation(.snappy) { pickedAim = pickedAim == id ? nil : id }
        guard pickedAim == id else { return }
        if id == "save" { DispatchQueue.main.async { amountFocused = true } }
        let reply = id == "save" ? tr("好目标！每个月想存多少？填个数，我每个月帮你盯着。")
            : id == "custom" ? tr("好，我记住了！") : Self.aimOptions.first { $0.id == id }?.reply ?? tr("好！")
        Task { await say(reply, pose: .cheer) }
    }

    private func toBooks() async {
        // 目标马上存进账本（进改动记录，能撤销）：中途点「以后再说」也不会丢。
        if let aimText, aimText != model.ledger.profile.aim {
            _ = try? model.edit(quiet: true) { try $0.setAim(aimText, author: model.author) }
        }
        go(.books)
        await say(aimText == nil ? tr("目标以后想好再定也行。「个人」账本我已经帮你建好了。") : tr("记住了！「个人」账本我已经帮你建好了。"), pose: .idle)
    }

    private func toAccounts() async {
        go(.accounts)
        if withShop == true {
            for c in [Choice(name: tr("店里的卡"), bookKind: .business, accountKind: .bank), Choice(name: tr("店里现金"), bookKind: .business, accountKind: .cash)]
            where !accountChoices.contains(where: { $0.name == c.name }) {
                accountChoices.insert(Choice(name: c.name, glyph: c.accountKind.glyph, bookKind: .business, accountKind: c.accountKind), at: 0)
            }
        }
        await say(withShop == true ? tr("好，生活和生意分两边算。店里的账户我放在前面了。") : tr("好，只记生活，最清爽。"), pose: .write)
    }

    /// 把选好的账本、账户写进账本（已经有的不重复建）。
    private func commitSetup() {
        // 选了「生活和生意都记」：打开生意模式（没有生意账本就建一个「我的小店」）；新店填了本钱就记上，用来算回本。
        if withShop == true, model.ledger.business?.enabled != true {
            if !model.ledger.books.contains(where: \.isBusiness) {
                _ = try? model.edit(quiet: true) { try $0.addBook(name: tr("我的小店"), kind: .business, author: model.author) }
            }
            _ = try? model.edit(quiet: true) { ledger in
                guard case .enabled(let change) = try ledger.enableBusinessMode(author: model.author) else { throw CancellationError() }
                return change
            }
            if newShop == true, let total = Self.parseAmount(capitalText) {
                _ = try? model.edit(quiet: true) { try $0.setCapital(Capital(total: total, openedOn: .today), author: model.author) }
            }
        }
        let haveAccounts = Set(model.ledger.accounts.map(\.name))
        for c in accountChoices where pickedAccounts.contains(c.name) && !haveAccounts.contains(c.name) {
            var made: String?
            _ = try? model.edit(quiet: true) { ledger in
                let id = ledger.newAccountID(for: c.name)
                made = id
                return try ledger.createAccount(Account(id: id, name: c.name, kind: c.accountKind), author: model.author)
            }
            if c.bookKind == .business, let id = made, model.businessOn {
                _ = try? model.edit(quiet: true) { try $0.setAccountSide(id, side: .business, author: model.author) }
            }
        }
    }

    /// 第一次打开二选一的大卡片。
    private func sideCard(_ title: String, detail: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Color.brand)
                    .frame(width: 44, height: 44)
                    .background(on ? Color.brand : Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Color.brand : Color.fg3.opacity(0.3), lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toAI() async {
        commitSetup()
        let count = model.ledger.accounts.count
        if aiStepAvailable {
            withAnimation(.smooth(duration: 0.35)) { aiMode = .choose }
            go(.ai)
            let tail = chatStepAvailable ? tr("快好啦！") : tr("最后一步啦！")
            await say(count == 0 ? tr("账户以后再加也行。\(tail)") : tr("记下了，\(count) 个放钱的地方。\(tail)"), pose: .think)
        } else {
            go(.done)
            await say(tr("都准备好了！"), pose: .celebrate)
        }
    }

    private func choose(_ f: AIFamily) async {
        guard checking == nil else { return }
        guard let c = model.aiConnector else { await skipAI(); return }
        family = f
        withAnimation(.snappy(duration: 0.2)) { checking = f }
        await say(f == .newbie ? tr("没关系，我来带你。") : tr("那我们看看吧。"), pose: .think)
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.1 : 0.3))
        // 这一小会儿里点了「返回」或「先跳过」：不再往下走。
        guard step == .ai, aiMode == .choose, checking == f else { return }
        linked = f.apps.filter { c.isConnected($0) }
        toConnect = f.apps.filter { c.isInstalled($0) && !c.isConnected($0) }
        handshakeSeen = false
        justConnected = nil
        waitTicks = 0
        copiedSentence = false
        tryStartedAt = Date()
        knownTransactions = Set(model.ledger.transactions.map(\.id))
        knownGoals = Set(model.ledger.goals.map(\.id))
        withAnimation(.smooth(duration: 0.35)) {
            aiMode = .trying
            checking = nil
        }
        if !linked.isEmpty {
            await say(tr("连接上了！"), pose: .cheer)
        } else if !toConnect.isEmpty {
            await say(tr("还没有连接上，不过我找到它了。"), pose: .idle)
        } else if f == .newbie {
            await say(tr("先装一个，我在这儿等你。"), pose: .idle)
        } else {
            await say(tr("还没有连接上。"), pose: .worried)
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
            justConnected = done.first
        }
        waitTicks = 0
        if done.first != nil {
            await say(tr("连接上了！"), pose: .cheer)
        } else if !failed.isEmpty {
            await say(tr("\(failed.joined(separator: "、")) 没连上，等下去「设置」里再试试。"), pose: .worried)
        }
    }

    private func skipAI() async {
        checking = nil
        if chatStepAvailable {
            go(.chat)
            await say(tr("好，以后再连也行。最后一个问题！"), pose: .calm)
        } else {
            go(.done)
            await say(tr("好，以后再连也行。"), pose: .calm)
        }
    }

    /// 用不用内置夏夏：记下来（和设置里的开关是同一个）。用：以后一打开 app 右边就有对话栏；不用：右边不出，「问夏夏」去 Claude。
    private func chooseChat(_ on: Bool) async {
        #if os(macOS)
        model.chat.enabled = on
        if on, let e = chatPick.flatMap(ChatEngine.init(rawValue:)) { model.chat.engine = e }
        #endif
        go(.done)
        if celebrated { withAnimation(.smooth) { confetti = true } }
        await say(on ? tr("好！以后我就在右边陪着你。") : tr("好，想聊的时候点右上角「问夏夏」。"), pose: on ? .cheer : .calm)
        if celebrated {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.smooth) { confetti = false }
        }
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
                    withAnimation(.bouncy) { toConnect = found }
                    await say(tr("认出来了！你装好了 \(found[0].name)，点一下我帮你连上。"), pose: .cheer)
                    continue
                }
            }
            let nowLinked = f.apps.filter { c.isConnected($0) }
            if nowLinked.count > linked.count {
                // AI 照着指令自己连好了。
                withAnimation(.bouncy) {
                    linked = nowLinked
                    toConnect.removeAll { nowLinked.contains($0) }
                }
                await say(tr("连接上了！"), pose: .cheer)
                continue
            }
            guard !model.usesSampleData else { continue }
            let fresh = AIConnections.load().filter { $0.value > tryStartedAt }
            let who = fresh.max(by: { $0.value < $1.value }).map { AIApp.displayName(clientName: $0.key) }
            if !handshakeSeen, let who {
                withAnimation(.snappy) { handshakeSeen = true }
                await say(tr("我看到 \(who) 来读账本了！跟它说说今天花了什么吧。"), pose: .cheer)
                continue
            }
            if !handshakeSeen, !linked.isEmpty, copiedSentence {
                waitTicks += 1
                if waitTicks == 45 {
                    // 复制后等了一分半还没动静：可能还没发、粘到了网页版 / 手机版，或者还没重开 AI。只提醒一次，不吓人。
                    let reopen = justConnected.map { tr("先\($0.afterConnect)，再发一次。") } ?? tr("要发给装在这台电脑上的那个，网页版和手机版连不过来。")
                    await say(tr("还没看到 AI 来读账本。\(reopen)"), pose: .think)
                    continue
                }
            }
            model.refreshIfChanged()
            let newTx = model.ledger.transactions.filter { !knownTransactions.contains($0.id) }
            let newGoal = model.ledger.goals.first { !knownGoals.contains($0.id) }
            if !newTx.isEmpty || newGoal != nil {
                let note = newTx.max(by: { $0.date < $1.date }).map { "\(Merchant.display($0.description)) \($0.amount.formatted)" }
                // 没等到握手记录（旧版的记账服务只在连接时记一次）：从改动记录的作者认出是谁记的。
                let writer = model.ledger.changes.last.map(\.author).flatMap { $0 == model.author ? nil : AIApp.displayName(clientName: $0) }
                await celebrate(who: who ?? writer, note: note, goal: newGoal?.name)
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
            step = chatStepAvailable ? .chat : .done
            confetti = true
        }
        await say(who.map { tr("\($0) 连上啦！") } ?? tr("连上啦！"), pose: .celebrate)
        try? await Task.sleep(for: .seconds(4.5))
        withAnimation(.smooth) { confetti = false }
    }

    private func finish(openAdd: Bool) {
        withAnimation(.smooth) { model.finishWelcome() }
        if openAdd { model.sheet = .add }
        #if os(macOS)
        // 选了打开内置夏夏：进账本时右边就展开。
        if !openAdd, model.chat.enabled, XiaxiaChatState.chosenOn { model.chat.show() }
        #endif
    }

    /// 最后一步「内置夏夏」：只在 Mac、而且这台 Mac 上有能在后台回答的 AI（Claude Code / Codex / Hermes）时问。
    private var chatStepAvailable: Bool {
        #if os(macOS)
        aiStepAvailable && !model.chat.available.isEmpty && !isPretendChat
        #else
        false
        #endif
    }

    /// 示例账本时对话栏答不了（它不碰示例数据），就不问了。
    private var isPretendChat: Bool { model.usesSampleData }

    // MARK: 连 AI（只在 Mac）

    private var aiStepAvailable: Bool {
        #if os(macOS)
        model.aiConnector != nil
        #else
        false
        #endif
    }
}

private extension AIApp {
    /// 一句大白话：这个工具是什么。
    var plainWords: String {
        switch self {
        case .claudeDesktop: tr("电脑上的 Claude")
        case .claudeCode: tr("Claude 的命令行版")
        case .codex: tr("ChatGPT 装在电脑上的助手")
        case .hermes: tr("能接 DeepSeek 等模型的助手")
        case .cursor: tr("带 AI 的写代码软件")
        case .gemini: tr("Gemini 的命令行版")
        }
    }
}

/// 宽窗口（Mac）字大一号，窄的（iPhone）小一号。
private struct WelcomeBigKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var welcomeBig: Bool {
        get { self[WelcomeBigKey.self] }
        set { self[WelcomeBigKey.self] = newValue }
    }
}

struct WelcomeSized<Content: View>: View {
    @Environment(\.welcomeBig) private var big
    @ViewBuilder var content: (Bool) -> Content
    var body: some View { content(big) }
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

#if os(macOS)
/// 引导里的内置夏夏演示：照右边聊天栏的样子，一句一句冒出来，放完停一会儿再从头放。
struct ChatDemo: View {
    var engineName: String
    /// 对话那一块的高度（窗口矮时收小，旧的几句会从上面滚出去，跟真聊天一样）。
    var height: CGFloat = 196
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var typing = false

    private let lines: [(mine: Bool, text: String)] = [
        (true, tr("今天午饭 12 欧")),
        (false, tr("记好了：午饭 -12,00 €，个人账本 · 餐饮。")),
        (true, tr("这个月吃饭花了多少？")),
        (false, tr("86,40 €，比上个月少 12 €。照这样，月底还能剩 420 € 左右。")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                MascotView(size: 24, face: true, animated: false)
                Text(tr("夏夏")).font(.headline)
                Spacer()
                Text(engineName).font(.caption).foregroundStyle(Color.brand)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                ForEach(Array(lines.prefix(shown).enumerated()), id: \.offset) { _, line in
                    bubble(line.text, mine: line.mine)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if typing {
                    HStack(spacing: 6) {
                        MascotView(size: 22, face: true, animated: false)
                        Text(tr("夏夏在想…")).font(.caption).foregroundStyle(Color.fg3)
                    }
                    .transition(.opacity)
                }
            }
            .padding(14)
            .frame(height: height, alignment: .bottom)
            .clipped()
            Divider()
            HStack {
                Text(tr("跟夏夏说，比如「午饭 12 欧」")).font(.callout).foregroundStyle(Color.fg3)
                Spacer()
                Image(systemName: "arrow.up.circle.fill").font(.title3).foregroundStyle(Color.aiSolid)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.fg3.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.ai.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("演示：你说「今天午饭 12 欧」，夏夏回答记好了；你问这个月吃饭花了多少，夏夏回答 86,40 €"))
        .task { await play() }
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if mine { Spacer(minLength: 40) } else { MascotView(size: 22, face: true, animated: false) }
            Text(text).font(.callout)
                .foregroundStyle(mine ? Color.white : Color.primary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Color.aiSolid : Color.sunken, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            if !mine { Spacer(minLength: 24) }
        }
    }

    private func play() async {
        if reduceMotion { shown = lines.count; return }
        while !Task.isCancelled {
            withAnimation(.smooth) { shown = 0; typing = false }
            try? await Task.sleep(for: .seconds(0.8))
            for (i, line) in lines.enumerated() {
                if !line.mine {
                    withAnimation(.smooth) { typing = true }
                    try? await Task.sleep(for: .seconds(1.1))
                    withAnimation(.smooth) { typing = false }
                }
                guard !Task.isCancelled else { return }
                withAnimation(.bouncy(duration: 0.45)) { shown = i + 1 }
                try? await Task.sleep(for: .seconds(line.mine ? 0.9 : 1.6))
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
#endif
