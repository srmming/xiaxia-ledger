import FinanceCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 9 个页面，每页回答一个问题。前 5 页是「看」，夏夏建议和改动记录是「AI 做了什么」，最后是流水和设置。
public enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview = "总览", spending = "花销", trends = "趋势", wealth = "家底", plans = "计划"
    case insights = "夏夏建议", changes = "改动记录", transactions = "流水", settings = "设置"
    public var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .spending: "chart.pie.fill"
        case .trends: "chart.bar.fill"
        case .wealth: "wallet.bifold.fill"
        case .plans: "target"
        case .insights: "sparkles"
        case .changes: "clock.arrow.circlepath"
        case .transactions: "list.bullet.rectangle.portrait.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// 工具栏要不要月份和账本切换（AI、改动记录、设置不按月看）。
    var usesMonth: Bool { ![.insights, .changes, .settings].contains(self) }
    var usesBook: Bool { ![.insights, .changes, .settings, .wealth].contains(self) }

    @ViewBuilder var screen: some View {
        switch self {
        case .overview: OverviewPage()
        case .spending: SpendingPage()
        case .trends: TrendsPage()
        case .wealth: WealthPage()
        case .plans: PlansPage()
        case .insights: InsightsPage()
        case .changes: ChangesPage()
        case .transactions: TransactionsPage()
        case .settings: SettingsPage()
        }
    }

    static let look: [AppSection] = [.overview, .spending, .trends, .wealth, .plans]
    static let ai: [AppSection] = [.insights, .changes]
    static let records: [AppSection] = [.transactions]
}

/// app 的根视图：iPhone 用 5 个标签，Mac 用侧栏 + 工具栏。
public struct RootView: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.scenePhase) var scenePhase

    public init() {}

    @AppStorage("xiaxia.appearance") var appearance = "auto"
    /// 主窗口有多高（Mac 上弹出的面板不能比它高）。
    @State private var windowHeight: CGFloat = 900

    public var body: some View {
        @Bindable var model = model
        Group {
            if let error = model.loadError {
                LoadErrorView(error: error)
            } else if model.isLoading && model.ledger.transactions.isEmpty {
                ProgressView("正在读取账本…").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.pageBackground)
            } else if model.showWelcome {
                WelcomeView().transition(.opacity)
            } else {
                layout.transition(.opacity)
            }
        }
        .animation(.smooth, value: model.showWelcome)
        .tint(Color.brand)
        #if os(macOS)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { windowHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, h in windowHeight = h }
        })
        #endif
        .overlay(alignment: .bottom) {
            ZStack { toastLayer }.animation(.snappy, value: model.toast)
        }
        .overlay(alignment: .top) {
            ZStack {
                if let a = model.activity {
                    ActivityBanner(activity: a).environment(model)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.activity)
        }
        .task { await model.watch() }
        .sensoryFeedback(trigger: model.toast) { _, new in
            guard let new else { return nil }
            return new.isError ? .error : .success
        }
        .sheet(item: $model.sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .add: QuickAdd()
                case .books: BookManager()
                case .accounts: AccountManager()
                case .categories: CategoryManager()
                case .newCategory: CategoryCreator()
                case .connectAI: ConnectAIView()
                case .plan: NewPlanSheet()
                }
            }
                .environment(model)
                .tint(Color.brand)
                #if os(macOS)
                // 面板不比窗口高：窗口缩小了也能看到底部的「取消 / 建好了」，里面自己滚动。
                // 记一笔多减一些：面板挂在工具栏下面（约 52），按钮那排要整个露在窗口里。
                .frame(width: sheet == .add ? 460 : sheet == .connectAI ? 600 : 520,
                       height: sheet == .add ? min(760, max(420, windowHeight - 110))
                                              : min(sheet == .connectAI ? 720 : 580, max(360, windowHeight - 60)))
                #else
                .presentationDetents([.large])
                #endif
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .task {
            // Mac：app 换过位置就把 AI 配置里的路径改过来；第一次打开、还没连过 AI 就弹「连上你的 AI」。
            model.repairAIConnections()
            await model.refreshRatesIfNeeded()   // 有外币账户时，一天取一次欧洲央行汇率
            model.showWelcomeIfNeeded()          // 空账本第一次打开：夏夏带着走一遍
            try? await Task.sleep(for: .seconds(0.6))
            if !model.showWelcome { model.showAISetupIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.sheet == nil { model.refreshIfChanged() }
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = model.toast {
            ToastView(toast: toast) { model.undo(toast.changeID ?? UUID()) }
                .padding(.bottom, toastInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(toast.seconds ?? (toast.changeID == nil ? 3 : 10)))
                    if model.toast?.id == toast.id { withAnimation { model.toast = nil } }
                }
                .id(toast.id)
        }
    }

    private var toastInset: CGFloat {
        #if os(iOS)
        110
        #else
        18
        #endif
    }

    #if os(iOS)
    private var layout: some View { PhoneRoot() }
    #else
    private var layout: some View { MacRoot() }
    #endif
}

/// 账本读不出来：说清楚原因，给「再试一次」和「让 AI 检查」。
struct LoadErrorView: View {
    @Environment(LedgerModel.self) var model
    let error: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("账本读不出来", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(Color.alert)
            Text(error).font(.subheadline).textSelection(.enabled)
            Text("账本在 iCloud 云盘的「夏夏账本」文件夹里。先确认 iCloud 云盘开着、文件已经下载到这台设备；如果是新版本写的账本，更新一下 app。")
                .font(.caption).foregroundStyle(Color.fg2)
            HStack(spacing: 8) {
                Button("再试一次") { model.reload() }.buttonStyle(.borderedProminent).tint(.brand)
                AskAIReader { ask in
                    Button { ask("夏夏账本打不开，提示：\(error)。帮我检查一下账本文件哪里有问题（只看不改）。") } label: {
                        Label("让 AI 检查", systemImage: "sparkles")
                    }
                    .buttonStyle(.softAI)
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(Color.alertSoft, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
        .padding(Kit.side)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pageBackground)
    }
}

// MARK: - Mac

#if os(macOS)
struct MacRoot: View {
    @Environment(LedgerModel.self) var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.section) {
                Section("看") { ForEach(AppSection.look) { row($0) } }
                Section("夏夏") { ForEach(AppSection.ai) { row($0) } }
                Section("记录") { ForEach(AppSection.records) { row($0) } }
                Section { row(.settings) }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            let section = model.section ?? .overview
            // 对话栏不用系统的 .inspector：它是 AppKit 分栏里的一栏，展开收起时分栏要重算，
            // 2026-11-22 在 Mac 上连着几次陷进约束死循环闪退（_postWindowNeedsUpdateConstraints）。
            // 这里就是中间这栏里一个普通的左右排版，右边固定 340 宽，分栏本身完全不动。
            HStack(spacing: 0) {
                NavigationStack {
                    section.screen
                        .navigationTitle(section.rawValue)
                        .toolbar { MacToolbar(model: model, section: section) }
                }
                .id(section)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                if model.chat.open && model.chat.enabled {
                    Divider()
                    XiaxiaChatPanel()
                        .frame(width: 340)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            // 中间这栏的最小宽度固定死，不随页面内容、对话栏开关变：分栏就不用重算最小宽度（「看看」闪退就是这么修的）。
            .frame(minWidth: 460, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
    }

    private func row(_ s: AppSection) -> some View {
        Label { Text(s.rawValue) } icon: { s.glyph.image(size: 18) }
            .badge(s == .insights ? model.ledger.insights(month: LocalDate.today.yearMonth).count : 0)
            .tag(s)
    }
}

/// 侧栏底部：同步状态和 AI 最近一次写入。
struct SidebarFooter: View {
    @Environment(LedgerModel.self) var model
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.bottom, 6)
            StatusDot(color: model.loadError == nil ? .income : .alert, text: model.loadError == nil ? "账本已读到" : "账本读不出来")
                .foregroundStyle(Color.fg2)
            if let last = model.lastAIChange {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("\(last.author) \(last.createdAt.friendly) 写入").lineLimit(1)
                }
                .foregroundStyle(Color.ai)
            } else {
                Text("AI 还没写过账本").foregroundStyle(Color.fg3)
            }
        }
        .font(.caption)
        .padding(.horizontal, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 工具栏：月份、账本切换（全部 / 每个账本）、记一笔、问 AI。
struct MacToolbar: ToolbarContent {
    let model: LedgerModel
    let section: AppSection

    var body: some ToolbarContent {
        // 月份和账本放左边，「记一笔」「问 AI」单独一组放最右：窗口窄的时候先收起的是左边，记一笔一直看得见。
        ToolbarItemGroup(placement: .navigation) {
            if section.usesMonth {
                MonthStepper(month: Binding(get: { model.shownMonth }, set: { m in withAnimation(.snappy) { model.selectedMonth = m } }),
                             latest: LocalDate.today.yearMonth)
            }
            if section.usesBook {
                BookSwitch().environment(model)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            // 照 ming 的稿：「记一笔」是橙色实心（系统的醒目按钮样式 + 品牌橙，工具栏不会切掉它的底色）。
            Button { model.sheet = .add } label: { Label { Text("记一笔") } icon: { XiaGlyph.actAdd.image(size: 17) }.labelStyle(.titleAndIcon) }
                .buttonStyle(.borderedProminent)
                .tint(Color.brand)
                .help("记一笔（⌘N）")
            Button { model.toggleChat() } label: {
                Label("问夏夏", systemImage: "sparkles").labelStyle(.titleAndIcon)
            }
            .tint(Color.ai)
            .help("打开右边的夏夏对话栏，说一句就记账、查账（⌘K）")
        }
    }
}
#endif

/// 账本切换：全部 / 每个账本，最下面是「管理账本…」（新建、改名、删除）。
struct BookSwitch: View {
    @Environment(LedgerModel.self) var model
    var body: some View {
        let selection = Binding(get: { model.selectedBookID }, set: { id in withAnimation(.snappy) { model.selectedBookID = id } })
        Menu {
            Picker("看哪个账本", selection: selection) {
                if model.ledger.books.count > 1 { Text("全部").tag(String?.none) }
                ForEach(model.ledger.books) { b in Text(b.name).tag(Optional(b.id)) }
            }
            .pickerStyle(.inline)
            Divider()
            Button { model.sheet = .books } label: { Label("管理账本…", systemImage: "books.vertical") }
        } label: {
            // iPhone 工具栏里的 Label 只显示图标，看不出现在是哪个账本，所以自己拼图标 + 名字。
            HStack(spacing: 4) {
                Image(systemName: "books.vertical")
                Text(model.ledger.books.count > 1 ? model.bookName(model.selectedBookID) : (model.ledger.books.first?.name ?? "账本"))
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .help("切换账本，或新建、改名、删除账本")
        .accessibilityLabel("账本：\(model.bookName(model.selectedBookID))")
    }
}

// MARK: - iPhone

#if os(iOS)
/// iPhone 的 5 个标签：总览、收支（花销 + 趋势）、家底、计划、夏夏。
struct PhoneRoot: View {
    @Environment(LedgerModel.self) var model
    @State var flowsTab = 0
    @State var showSettings = false

    private var tab: Binding<AppSection> {
        Binding(get: {
            switch model.section ?? .overview {
            case .trends: return .spending
            case .changes, .settings: return .insights
            case .transactions: return .overview
            default: return model.section ?? .overview
            }
        }, set: { model.section = $0 })
    }

    var body: some View {
        TabView(selection: tab) {
            page(.overview, title: "总览") { OverviewPage() }
            page(.spending, title: "收支") {
                VStack(spacing: 0) {
                    Picker("看什么", selection: $flowsTab) {
                        Text("花在哪").tag(0)
                        Text("趋势").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Kit.side).padding(.bottom, 6)
                    if flowsTab == 0 { SpendingPage() } else { TrendsPage() }
                }
                .background(Color.pageBackground)
            }
            page(.wealth, title: "家底") { WealthPage() }
            page(.plans, title: "计划") { PlansPage() }
            page(.insights, title: "夏夏") { InsightsPage() }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsPage()
                    .navigationTitle("设置")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showSettings = false } } }
            }
            .environment(model)
        }
        .onAppear {
            if model.section == .trends { flowsTab = 1 }
            if model.section == .settings { showSettings = true }
        }
    }

    private func page<Content: View>(_ section: AppSection, title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if section != .insights {
                            BookSwitch()
                            // 「问 AI」放进顶栏，不再浮在右下角挡住卡片上的按钮；「夏夏」页自己有问的入口，这里不重复。
                            AskAIReader { ask in
                                Button { ask("", page: (model.section ?? section).rawValue) } label: {
                                    Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ai)
                                }
                                .accessibilityLabel("问 AI")
                                .accessibilityHint("复制当前页面、月份和账本，打开 Claude")
                            }
                        }
                        Button { model.sheet = .add } label: {
                            Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 30, height: 30).background(Color.brand, in: Circle())
                        }
                        .accessibilityLabel("记一笔")
                        Button { showSettings = true } label: {
                            Text(String(model.author.prefix(1))).font(.system(size: 13, weight: .bold))
                                .frame(width: 30, height: 30).background(Color.sunken, in: Circle())
                        }
                        .accessibilityLabel("设置")
                    }
                }
                .navigationDestination(for: AppSection.self) { s in s.screen.navigationTitle(s.rawValue) }
        }
        .tabItem { Label { Text(title) } icon: { section.glyph.image(size: 25) } }
        .tag(section)
    }
}
#endif

/// 两个 app 共用的场景。
public struct XiaxiaScene: Scene {
    @State var model: LedgerModel

    public init() {
        // 截图和演示：启动参数带 -XiaxiaDemo 就用编造的示例账本，-XiaxiaEmpty 是空账本，都不碰真实数据。
        let args = ProcessInfo.processInfo.arguments
        let model: LedgerModel
        #if DEBUG
        // 开发版（Debug）默认用示例账本，不去读 iCloud 里的真账本；真要读加 -XiaxiaReal。
        let useDemo = args.contains("-XiaxiaDemo") || (!args.contains("-XiaxiaEmpty") && !args.contains("-XiaxiaReal"))
        #else
        let useDemo = args.contains("-XiaxiaDemo")
        #endif
        if useDemo {
            model = LedgerModel.demo()
        } else if args.contains("-XiaxiaEmpty") {
            model = LedgerModel.empty()
        } else {
            model = LedgerModel(store: LedgerStores.appStore())
        }
        Self.applyLaunchOptions(args, to: model)
        _model = State(initialValue: model)
        #if os(macOS)
        Self.ensureMainWindow()
        #endif
    }

    #if os(macOS)
    /// 偶尔启动后没有主窗口（上次关窗口退出，系统按「恢复窗口」什么也没恢复）。
    /// 不恢复旧窗口；启动一秒后还没有可见窗口，就点一下「窗口」菜单里的「夏夏账本」把它叫出来。
    private static func ensureMainWindow() {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        for delay in [1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard NSApp != nil, !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
                guard let menu = NSApp.windowsMenu ?? NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "Window" || $0.submenu?.title == "窗口" })?.submenu,
                      let item = menu.items.first(where: { $0.title == "夏夏账本" }),
                      let i = menu.items.firstIndex(of: item) else { return }
                menu.performActionForItem(at: i)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    #endif

    /// 截图和自动检查用：-XiaxiaSection spending 直接打开某一页，-XiaxiaSheet add / books / accounts / categories 直接弹出记一笔或管理页，
    /// -XiaxiaPrivate 显示私房钱，-XiaxiaBook personal 直接看某个账本（all = 全部）。
    private static func applyLaunchOptions(_ args: [String], to model: LedgerModel) {
        func value(_ key: String) -> String? {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let sections: [String: AppSection] = [
            "overview": .overview, "spending": .spending, "reports": .spending, "trends": .trends, "wealth": .wealth,
            "plans": .plans, "insights": .insights, "ai": .insights, "changes": .changes, "history": .changes,
            "transactions": .transactions, "settings": .settings,
        ]
        if let s = value("-XiaxiaSection"), let section = sections[s] { model.section = section }
        if let v = value("-XiaxiaSheet"), let sheet = AppSheet(rawValue: v) { model.sheet = sheet }
        if args.contains("-XiaxiaPrivate") { model.showPrivate = true }
        #if os(macOS)
        if let out = value("-XiaxiaSnapshot") { WindowSnapshot.schedule(to: out) }
        // -XiaxiaChat：一打开就展开右边的夏夏对话栏（检查对话栏、截图用）。
        if args.contains("-XiaxiaChat") { model.chat.open = true }
        // 引导里选了「打开内置夏夏」：每次打开都展开对话栏。
        if XiaxiaChatState.chosenOn, !model.chat.available.isEmpty { model.chat.open = true }
        #endif
        if let b = value("-XiaxiaBook") {
            if b == "all" { model.selectedBookID = nil } else if model.ledger.books.contains(where: { $0.id == b }) { model.selectedBookID = b }
        }
    }

    public var body: some Scene {
        #if os(macOS)
        // Mac 上只有一个主窗口，用 Window 而不是 WindowGroup：每次启动都一定会出主窗口，关掉窗口就退出。
        Window("夏夏账本", id: "main") {
            RootView()
                .environment(model)
                // 窗口最窄也要放得下：侧栏 190 + 页面 460 + 对话栏 340。宽度固定不变，开关对话栏时不改窗口最小宽度。
                .frame(minWidth: 1000, minHeight: 560)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("记一笔") { model.sheet = .add }.keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button(model.chat.open ? "收起夏夏对话栏" : "和夏夏聊") { model.toggleChat() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("复制这一页的情况，去 Claude 里问") {
                    let page = (model.section ?? .overview).rawValue
                    Clipboard.copy(model.contextLine(page: page))
                    model.toast = .init(text: "已复制，在 Claude 里粘贴就行", changeID: nil)
                }
                Button("搜流水") { model.section = .transactions; model.focusSearch = true }.keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("账本") {
                Button("撤销上一步改动") { model.undoLast() }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                    .disabled(model.undoStack.isEmpty)
                Button("上个月") { model.selectedMonth = model.shownMonth.adding(months: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("下个月") {
                    let next = model.shownMonth.adding(months: 1)
                    if next <= LocalDate.today.yearMonth { model.selectedMonth = next }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("重新读取账本") { model.reload() }.keyboardShortcut("r", modifiers: .command)
                Divider()
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.rawValue) { model.section = s }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
            CommandGroup(replacing: .help) {
                Button("反馈问题") {
                    if let url = URL(string: "https://github.com/srmming/xiaxia-ledger/issues/new") { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
        }
        #else
        WindowGroup("夏夏账本") {
            RootView()
                .environment(model)
        }
        #endif
    }
}
