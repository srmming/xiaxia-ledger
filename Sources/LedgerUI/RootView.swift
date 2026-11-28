import FinanceCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 9 个页面，每页回答一个问题。前 5 页是「看」，夏夏建议和改动记录是「AI 做了什么」，最后是流水和设置。
public enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview = "总览", spending = "花销", trends = "趋势", wealth = "家底", plans = "目标", subscriptions = "订阅", debts = "欠款与分期", reimburse = "报销"
    case insights = "夏夏建议", changes = "改动记录", transactions = "流水", settings = "设置"
    /// 生意那边才有：房租、工资这些每月固定要付的（2026-11-25）。
    case fixed = "固定开销"
    public var id: String { rawValue }
    /// 显示给人看的名字（跟着界面语言）。rawValue 是中文，留给 AI 和存储用，不变。
    public var title: String { trKey(rawValue) }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .spending: "chart.pie.fill"
        case .trends: "chart.bar.fill"
        case .wealth: "wallet.bifold.fill"
        case .plans: "target"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .debts: "arrow.left.arrow.right"
        case .reimburse: "doc.text.fill"
        case .insights: "sparkles"
        case .changes: "clock.arrow.circlepath"
        case .transactions: "list.bullet.rectangle.portrait.fill"
        case .settings: "gearshape.fill"
        case .fixed: "calendar.badge.clock"
        }
    }

    /// 工具栏要不要月份和账本切换（AI、改动记录、设置不按月看）。
    var usesMonth: Bool { ![.insights, .changes, .settings, .subscriptions, .debts, .reimburse, .fixed].contains(self) }
    var usesBook: Bool { ![.insights, .changes, .settings, .wealth].contains(self) }

    @ViewBuilder var screen: some View {
        switch self {
        case .overview: OverviewPage()
        case .spending: SpendingPage()
        case .trends: TrendsPage()
        case .wealth: WealthPage()
        case .plans: PlansPage()
        case .subscriptions: SubscriptionsPage()
        case .debts: DebtsPage()
        case .reimburse: ReimbursementPage()
        case .insights: InsightsPage()
        case .changes: ChangesPage()
        case .transactions: TransactionsPage()
        case .settings: SettingsPage()
        case .fixed: FixedCostsPage()
        }
    }

    /// Mac 侧栏「看」：订阅、欠款与分期各自单独一页，「计划」只放存钱目标、改叫「目标」（ming 2026-11-23）。
    /// iPhone 底栏放不下，订阅、欠款还在「计划」那个标签里分格看。
    /// 流水也放进「看」，就在总览下面（ming 2026-11-25）。
    static let look: [AppSection] = [.overview, .transactions, .spending, .trends, .wealth, .plans, .subscriptions, .debts, .reimburse]
    /// 生意那边的侧栏：没有目标、订阅、报销，多一个固定开销（ming 2026-11-25：生活和生意完全分开）。
    static let businessLook: [AppSection] = [.overview, .transactions, .spending, .trends, .wealth, .fixed, .debts]
    static let ai: [AppSection] = [.insights, .changes]

    /// AI 写意见时带的 page（英文 id 或中文页名）→ 页面。
    static func from(page: String?) -> AppSection? {
        guard let page else { return nil }
        let ids: [String: AppSection] = [
            "overview": .overview, "spending": .spending, "reports": .spending, "trends": .trends, "wealth": .wealth,
            "plans": .plans, "goals": .plans, "subscriptions": .subscriptions, "debts": .debts, "reimburse": .reimburse, "reimbursements": .reimburse,
            "insights": .insights, "ai": .insights, "changes": .changes, "history": .changes, "transactions": .transactions, "settings": .settings, "fixed": .fixed,
        ]
        return ids[page] ?? AppSection(rawValue: page)
    }

    /// 一条提醒该去哪一页：AI 写了 page 就去那页，没写就按标题里的字猜（订阅、欠款、目标、花销）。
    static func forInsight(_ i: Insight) -> AppSection? {
        if let s = from(page: i.page), s != .overview { return s }
        let text = i.title + i.body
        if text.contains("订阅") || text.contains("会员") { return .subscriptions }
        if text.contains("分期") || text.contains("欠") || text.contains("借") || text.contains("还款") { return .debts }
        if text.contains("目标") || text.contains("存钱") || text.contains("小猪") { return .plans }
        if text.contains("报销") { return .reimburse }
        if text.contains("信用卡") || text.contains("余额") || text.contains("家底") { return .wealth }
        if text.contains("花") || text.contains("超支") || text.contains("分类") { return .spending }
        return from(page: i.page)
    }
    static let records: [AppSection] = [.transactions]
}

/// app 的根视图：iPhone 用 5 个标签，Mac 用侧栏 + 工具栏。
public struct RootView: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.scenePhase) var scenePhase

    public init() { L10n.load() }

    @AppStorage("xiaxia.appearance") var appearance = "auto"
    /// 界面语言（设置 → 隐私与外观里选）。换了就整个界面重画一遍。
    @AppStorage(L10n.defaultsKey) var language = L10n.fallbackChoice.rawValue
    /// 主窗口有多高（Mac 上弹出的面板不能比它高）。
    @State private var windowHeight: CGFloat = 900

    #if os(macOS)
    /// 弹窗多高：短表单就矮一点，主按钮紧跟在内容下面，不留一大块空（审查 2026-11-26）。
    static func sheetHeight(_ sheet: AppSheet) -> CGFloat {
        switch sheet {
        case .connectAI: 720
        case .plan: 540
        case .newDebt, .newInstallment: 440
        case .fixedCost: 420
        case .sideTransfer: 480
        case .daily: 540
        case .feedback: 440
        default: 580
        }
    }
    #endif

    public var body: some View {
        @Bindable var model = model
        // 先把语言用上，下面的界面才按新语言画（放在 onChange 里会晚一拍）。
        let _ = (L10n.choice = AppLanguage(rawValue: language) ?? L10n.fallbackChoice)
        Group {
            if let error = model.loadError {
                LoadErrorView(error: error)
            } else if model.isLoading && model.ledger.transactions.isEmpty {
                ProgressView(tr("正在读取账本…")).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.pageBackground)
            } else if model.showWelcome {
                WelcomeView().transition(.opacity)
            } else {
                layout.transition(.opacity)
            }
        }
        .id(language)
        .environment(\.locale, (AppLanguage(rawValue: language) ?? L10n.fallbackChoice).locale)
        .animation(.smooth, value: model.showWelcome)
        // 当前这边的点缀色：生活橙、生意青（审查 2026-11-26：生意那边还有很多橙色）。
        .tint(model.accent)
        // 开了「减少动态效果」：全 app 的弹簧、移动都换成短短的淡入淡出（审查 2026-11-26：以前 25 个有动画的文件只有 10 个判断了）。
        .calmWhenReduceMotion()
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
        #if os(macOS)
        .overlay(alignment: .bottomTrailing) {
            // 更新后第一次打开：右下角「这次更新了什么」，不挡操作。
            ZStack {
                if !model.showWelcome, model.loadError == nil, !WhatsNewState.shared.entries.isEmpty {
                    WhatsNewCard(state: WhatsNewState.shared)
                        .padding(20)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: WhatsNewState.shared.entries)
        }
        #endif
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
                case .memory: XiaxiaMemoryPanel()
                case .newCategory: CategoryCreator()
                case .connectAI: ConnectAIView()
                case .plan: GoalWizard()
                case .newInstallment: NewPlanSheet(kind: .installment)
                case .newDebt: NewPlanSheet(kind: .debt)
                case .daily: DailyTakingsSheet()
                case .fixedCost: FixedCostEditor()
                case .sideTransfer: SideTransferSheet()
                case .feedback: FeedbackSheet()
                }
            }
                .environment(model)
                .tint(model.accent)
                .calmWhenReduceMotion()
                #if os(macOS)
                // 面板不比窗口高：窗口缩小了也能看到底部的「取消 / 建好了」，里面自己滚动。
                // 记一笔多减一些：面板挂在工具栏下面（约 52），按钮那排要整个露在窗口里。
                .frame(width: sheet == .add ? 520 : sheet == .connectAI ? 600 : sheet == .memory ? 760 : sheet == .plan ? 700 : sheet == .daily ? 480 : (sheet == .fixedCost || sheet == .sideTransfer) ? 480 : 520,
                       height: sheet == .add ? min(760, max(420, windowHeight - 110))
                                              : min(Self.sheetHeight(sheet), max(360, windowHeight - 60)))
                #else
                .presentationDetents([.large])
                // 记一笔、记今天的账有计算器键盘，特大字号会把整页挤出屏幕（iPhone 审计 2026-11-26）：这两个到 xxxLarge 为止。
                .dynamicTypeSize(sheet == .add || sheet == .daily ? ...DynamicTypeSize.xxxLarge : ...DynamicTypeSize.accessibility2)
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
            #if os(macOS)
            WhatsNewState.shared.checkOnLaunch(hasData: !model.ledger.transactions.isEmpty) // 刚更新完：右下角说说这次改了什么
            #endif
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
                    // 读屏也念一遍，能撤销的顺带说快捷键（审查第二轮：底部小条里的撤销读屏找不到）。
                    AccessibilityNotification.Announcement(toast.changeID == nil ? toast.text : tr("\(toast.text)。按 ⌥⌘Z 撤销")).post()
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
            Label(tr("账本读不出来"), systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(Color.alert)
            Text(error).font(.subheadline).textSelection(.enabled)
            Text(tr("账本在 iCloud 云盘的「夏夏账本」文件夹里。先确认 iCloud 云盘开着、文件已经下载到这台设备；如果是新版本写的账本，更新一下 app。"))
                .font(.caption).foregroundStyle(Color.fg2)
            HStack(spacing: 8) {
                Button(tr("再试一次")) { model.reload() }.buttonStyle(.borderedProminent).tint(.brandSolid)
                AskAIReader { ask in
                    Button { ask(tr("夏夏账本打不开，提示：\(error)。帮我检查一下账本文件哪里有问题（只看不改）。")) } label: {
                        Label(tr("让 AI 检查"), systemImage: "sparkles")
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
                Section { ForEach(model.side == .business ? AppSection.businessLook : AppSection.look) { row($0) } } header: { sectionHeader(tr("看")) }
                Section { ForEach(AppSection.ai) { row($0) } } header: { sectionHeader(model.xiaName) }
                Section { row(.settings) }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            // 生活和生意是两个大空间，侧栏的页面跟着变：切换放侧栏最上面、整宽（ming 2026-11-25：放顶栏中间按着不对）。
            .safeAreaInset(edge: .top, spacing: 4) {
                if model.businessOn {
                    SideSwitch(fill: true).padding(.horizontal, 12).padding(.top, 2)
                }
            }
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            let section = model.section ?? .overview
            // 对话栏不用系统的 .inspector：它是 AppKit 分栏里的一栏，展开收起时分栏要重算，
            // 2026-11-22 在 Mac 上连着几次陷进约束死循环闪退（_postWindowNeedsUpdateConstraints）。
            // 这里就是中间这栏里一个普通的左右排版，右边固定 340 宽，分栏本身完全不动。
            HStack(spacing: 0) {
                NavigationStack {
                    section.screen
                        .safeAreaInset(edge: .top, spacing: 0) { DemoBanner() }
                        .navigationTitle(section.title)
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

    /// 侧栏分组标题：系统 Section 标题的样子（11pt 半粗、次要文字颜色），看得清（审查实测原来 2.2:1）。
    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.fg2)
    }

    private func row(_ s: AppSection) -> some View {
        Label { Text(model.xia(s.title)) } icon: { s.glyph.image(size: 18) }
            .badge(s == .insights ? model.insightsHere(month: LocalDate.today.yearMonth).count : 0)
            .tag(s)
    }
}

/// 侧栏底部：同步状态和 AI 最近一次写入。
struct SidebarFooter: View {
    @Environment(LedgerModel.self) var model
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.bottom, 6)
            StatusDot(color: model.loadError == nil ? .income : .alert,
                      text: model.isTryingDemo ? tr("正在看演示数据") : model.loadError == nil ? tr("账本已读到") : tr("账本读不出来"))
                .foregroundStyle(Color.fg2)
            if model.isTryingDemo {
                // 演示时不显示真账本「谁刚写过」，免得以为演示数据被写了。
                Text(tr("演示数据，不会保存")).foregroundStyle(Color.ai)
            } else if let last = model.lastAIChange {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text(tr("\(last.author) \(last.createdAt.friendly) 写入")).lineLimit(1)
                }
                .foregroundStyle(Color.ai)
            } else {
                Text(tr("AI 还没写过账本")).foregroundStyle(Color.fg3)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        #if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 6) { SidebarUpdateButton() }
        #endif
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
}

/// 工具栏：月份、账本切换（全部 / 每个账本）、记一笔、问 AI。
struct MacToolbar: ToolbarContent {
    let model: LedgerModel
    let section: AppSection

    var body: some ToolbarContent {
        // 月份和账本放左边，「记一笔」「问 AI」单独一组放最右：窗口窄的时候先收起的是左边，记一笔一直看得见。
        ToolbarItemGroup(placement: .navigation) {
            Button { withAnimation(.snappy) { model.goBack() } } label: { Image(systemName: "chevron.backward") }
                .disabled(model.backStack.isEmpty)
                .keyboardShortcut("[", modifiers: .command)
                .help(tr("返回上一页（⌘[）"))
                .accessibilityLabel(tr("返回"))
            if section.usesMonth {
                // 月份是一个整体「‹ 2026 年 11 月 ›」，和返回按钮之间隔开，不会把两个 ‹ 看混（审查 2026-11-26）。
                MonthStepper(month: Binding(get: { model.shownMonth }, set: { m in withAnimation(.snappy) { model.selectedMonth = m } }),
                             latest: LocalDate.today.yearMonth, recorded: model.recordedMonths, accent: model.accent)
                    .padding(.leading, 10)
            }
            if section.usesBook {
                BookSwitch().environment(model)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            // 照 ming 的稿：「记一笔」是橙色实心（系统的醒目按钮样式 + 品牌橙，工具栏不会切掉它的底色）。
            Button { model.sheet = .add } label: { Label { Text(tr("记一笔")) } icon: { XiaGlyph.actAdd.image(size: 17) }.labelStyle(.titleAndIcon) }
                .buttonStyle(.borderedProminent).solidTint()
                // 实心底用暗一档的颜色，白字在深色模式下也有 4.5:1（原来 2.5:1）；生意那边是青色。
                .tint(model.accentSolid)
                .help(tr("记一笔（⌘N）"))
            Button { model.toggleChat() } label: {
                Label(model.xia(tr("问夏夏")), systemImage: "sparkles").labelStyle(.titleAndIcon)
            }
            .tint(Color.ai)
            .help(tr("打开右边的夏夏对话栏，说一句就记账、查账（⌘K）"))
        }
    }
}
#endif

/// 账本切换：全部 / 每个账本，最下面是「管理账本…」（新建、改名、删除）。
struct BookSwitch: View {
    @Environment(LedgerModel.self) var model
    var body: some View {
        // 开着生意模式：顶栏不放账本菜单，「生活 | 生意」在侧栏最上面（Mac）/ 标题栏正中（iPhone）。
        // 账本管理还在 设置 → 账本与账户。
        if !model.businessOn { bookMenu }
    }

    private var bookMenu: some View {
        let selection = Binding(get: { model.selectedBookID }, set: { id in withAnimation(.snappy) { model.selectedBookID = id } })
        return Menu {
            Picker(tr("看哪个账本"), selection: selection) {
                if model.ledger.books.count > 1 { Text(tr("全部")).tag(String?.none) }
                ForEach(model.ledger.books) { b in Text(b.name).tag(Optional(b.id)) }
            }
            .pickerStyle(.inline)
            Divider()
            Button { model.sheet = .books } label: { Label(tr("管理账本…"), systemImage: "books.vertical") }
        } label: {
            // iPhone 工具栏里的 Label 只显示图标，看不出现在是哪个账本，所以自己拼图标 + 名字。
            HStack(spacing: 4) {
                Image(systemName: "books.vertical")
                Text(model.ledger.books.count > 1 ? model.bookName(model.selectedBookID) : (model.ledger.books.first?.name ?? tr("账本")))
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .help(tr("切换账本，或新建、改名、删除账本"))
        .accessibilityLabel(tr("账本：\(model.bookName(model.selectedBookID))"))
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
            case .subscriptions, .debts, .reimburse, .fixed: return .plans
            case .transactions: return .overview
            default: return model.section ?? .overview
            }
        }, set: { model.section = $0 })
    }

    var body: some View {
        TabView(selection: tab) {
            page(.overview, title: tr("总览")) { OverviewPage() }
            page(.spending, title: tr("收支")) {
                VStack(spacing: 0) {
                    Picker(tr("看什么"), selection: $flowsTab) {
                        Text(tr("花在哪")).tag(0)
                        Text(tr("趋势")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Kit.side).padding(.bottom, 6)
                    if flowsTab == 0 { SpendingPage() } else { TrendsPage() }
                }
                .background(Color.pageBackground)
            }
            page(.wealth, title: tr("家底")) { WealthPage() }
            // 生意那边「计划」这格放固定开销和欠款（以前 iPhone 上根本进不去固定开销，iPhone 审计 2026-11-26）。
            page(.plans, title: model.side == .business ? tr("开销") : tr("计划")) { PlansPage() }
            page(.insights, title: tr("夏夏")) { InsightsPage() }
        }
        // 特大字号时版面撑不下：最大到「辅助功能 2」，再大字号也不会把卡片挤出屏幕（iPhone 审计 2026-11-26）。
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsPage()
                    .navigationTitle(tr("设置"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("完成")) { showSettings = false } } }
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
                .safeAreaInset(edge: .top, spacing: 0) { DemoBanner() }
                .navigationTitle(title)
                .toolbar {
                    // iPhone 也能选月份（ming 2026-11-23）：左上角点月份弹出同一个小面板。
                    if section.usesMonth {
                        ToolbarItem(placement: .topBarLeading) {
                            MonthStepper(month: Binding(get: { model.shownMonth }, set: { m in withAnimation(.snappy) { model.selectedMonth = m } }),
                                         latest: LocalDate.today.yearMonth, recorded: model.recordedMonths, compact: true, accent: model.accent)
                                // 顶栏挤时「11 月」被压成「…」，看不出是几月（iPhone 审计 2026-11-26）：按字的宽度来，不压缩。
                                .fixedSize()
                        }
                    }
                    // 开着生意模式：「生活 | 生意」放标题栏正中间，每页都在同一个位置（设计稿 ③）。
                    if model.businessOn && section != .insights {
                        ToolbarItem(placement: .principal) { SideSwitch() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        // 顶栏只留两件事：记一笔、设置（iPhone 审计 2026-11-26：以前右上三个圆挤在一起）。
                        // 每页的「问 AI」星星拿掉了：非引导页不放 AI 提示（ming 2026-11-25），问夏夏走底栏「夏夏」。
                        if section != .insights, !model.businessOn { BookSwitch() }
                        Button { model.sheet = .add } label: {
                            Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 30, height: 30).background(model.accentSolid, in: Circle())
                        }
                        .accessibilityLabel(tr("记一笔"))
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape").font(.system(size: 15, weight: .semibold))
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityLabel(tr("设置"))
                    }
                }
                .navigationDestination(for: AppSection.self) { s in s.screen.navigationTitle(s.title) }
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
        // V3Launch 只有 Mac 有；iPhone 上是 PhoneV3Launch
        #if os(macOS)
        let v3 = V3Launch.enabled
        #else
        let v3 = PhoneV3Launch.enabled
        #endif
        if useDemo || v3 {
            // -XiaxiaPersona sharp / calm / cheer：示例账本换个夏夏性格（截图用，不写任何文件）。
            let persona = args.firstIndex(of: "-XiaxiaPersona").flatMap { $0 + 1 < args.count ? Persona(rawValue: args[$0 + 1]) : nil }
            model = LedgerModel.demo(persona: persona)
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
    /// 偶尔启动后没有主窗口（上次关窗口退出、或被强制退出几次后，系统按「恢复窗口」什么也没恢复）。
    /// 不恢复旧窗口；启动后还没有可见窗口：先把藏起来/缩到程序坞的主窗口拿出来，没有就点「窗口 → 显示主窗口」
    /// （那一项是我们自己加的，里面直接 openWindow(id: "main")，不靠系统菜单名字找）。审查 2026-11-26。
    private static func ensureMainWindow() {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        for delay in [0.8, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard NSApp != nil, !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
                if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.identifier?.rawValue.contains("main") == true }) {
                    if w.isMiniaturized { w.deminiaturize(nil) }
                    w.makeKeyAndOrderFront(nil)
                } else if let found = findMenuItem(tr("显示主窗口"), in: NSApp.mainMenu) {
                    found.0.performActionForItem(at: found.1)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private static func findMenuItem(_ title: String, in menu: NSMenu?) -> (NSMenu, Int)? {
        guard let menu else { return nil }
        for (i, item) in menu.items.enumerated() {
            if item.title == title { return (menu, i) }
            if let found = findMenuItem(title, in: item.submenu) { return found }
        }
        return nil
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
            "plans": .plans, "goals": .plans, "subscriptions": .subscriptions, "debts": .debts, "reimburse": .reimburse, "reimbursements": .reimburse, "insights": .insights, "ai": .insights, "changes": .changes, "history": .changes,
            "transactions": .transactions, "settings": .settings, "fixed": .fixed,
        ]
        if let s = value("-XiaxiaSection"), let section = sections[s] { model.section = section }
        if let v = value("-XiaxiaSheet"), let sheet = AppSheet(rawValue: v) { model.sheet = sheet }
        if args.contains("-XiaxiaPrivate") { model.showPrivate = true }
        #if os(macOS)
        if let out = value("-XiaxiaSnapshot") { WindowSnapshot.schedule(to: out) }
        // -XiaxiaChat：一打开就展开右边的夏夏对话栏（检查对话栏、截图用）。
        if args.contains("-XiaxiaChat") { model.chat.open = true }
        // 引导里选了「打开内置夏夏」：每次打开都展开对话栏。
        // 示例数据不连 AI：别一打开就摆个用不了的对话栏，挤窄页面。
        if XiaxiaChatState.chosenOn, model.chatReady { model.chat.open = true }
        #endif
        // -XiaxiaBusiness off：示例账本里关掉生意模式（只在内存里，测以前那套账本菜单用）。
        if value("-XiaxiaBusiness") == "off", model.usesSampleData, model.businessOn {
            _ = try? model.edit(quiet: true) { $0.disableBusinessMode(author: model.author) }
        }
        if let b = value("-XiaxiaBook") {
            if b == "all" { model.selectedBookID = nil } else if model.ledger.books.contains(where: { $0.id == b }) { model.selectedBookID = b }
        }
    }

    public var body: some Scene {
        #if os(macOS)
        // Mac 上只有一个主窗口，用 Window 而不是 WindowGroup：每次启动都一定会出主窗口，关掉窗口就退出。
        Window(tr("夏夏账本"), id: "main") {
            if V3Launch.enabled {
                // 界面 v3 开发版（-XiaxiaV3 1）：只用编的示例数字，不打开任何账本。
                V3RootView().frame(minWidth: 1000, minHeight: 612)
            } else if V3Launch.newLook {
                // 新界面接着正式账本（和旧界面是同一本、同一个模型）。默认不开，见 V3Launch.newLook。
                V3RootView(model: model).frame(minWidth: 1000, minHeight: 612)
            } else {
                RootView()
                    .environment(model)
                    // 窗口最窄也要放得下：侧栏 190 + 页面 460 + 对话栏 340。宽度固定不变，开关对话栏时不改窗口最小宽度。
                    .frame(minWidth: 1000, minHeight: 560)
            }
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("记一笔")) { model.sheet = .add }.keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button(model.chat.open ? tr("收起夏夏对话栏") : tr("和夏夏聊")) { model.toggleChat() }
                    .keyboardShortcut("k", modifiers: .command)
                Button(tr("复制这一页的情况，去 Claude 里问")) {
                    let page = (model.section ?? .overview).rawValue
                    Clipboard.copy(model.contextLine(page: page))
                    model.toast = .init(text: tr("已复制，在 Claude 里粘贴就行"), changeID: nil)
                }
                Button(tr("搜流水")) { model.section = .transactions; model.focusSearch = true }.keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu(tr("账本")) {
                Button(tr("撤销上一步改动")) { model.undoLast() }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                    .disabled(model.undoStack.isEmpty)
                Button(tr("上个月")) { model.selectedMonth = model.shownMonth.adding(months: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button(tr("下个月")) {
                    let next = model.shownMonth.adding(months: 1)
                    if next <= LocalDate.today.yearMonth { model.selectedMonth = next }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Button(tr("重新读取账本")) { model.reload() }.keyboardShortcut("r", modifiers: .command)
                Divider()
                // ⌘1…⌘9：只有九个数字键，多出来的页（设置有 ⌘,）不给数字快捷键。
                ForEach(Array(AppSection.allCases.prefix(9).enumerated()), id: \.element) { i, s in
                    Button(s.title) { model.section = s }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
            CommandGroup(before: .windowList) { ShowMainWindowButton() }
            CommandGroup(replacing: .help) {
                Button(tr("反馈问题 / 提个想法…")) { model.sheet = .feedback }
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
        }
        #else
        WindowGroup(tr("夏夏账本")) {
            if PhoneV3Launch.enabled {
                // iPhone 界面 v3（-XiaxiaV3 1，或包里写了 XiaxiaV3）：只用编的示例数字，不打开任何账本。
                PhoneV3Root()
            } else {
                RootView()
                    .environment(model)
            }
        }
        #endif
    }
}

#if os(macOS)
/// 「窗口 → 显示主窗口」（⌘0）：主窗口被关掉或没出来时把它叫回来；启动兜底也点这一项。
private struct ShowMainWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(tr("显示主窗口")) { openWindow(id: "main") }.keyboardShortcut("0", modifiers: .command)
    }
}
#endif
