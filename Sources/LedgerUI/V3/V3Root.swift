#if os(macOS)
import AppKit
import FinanceCore
import SwiftUI

/// 界面 v3 开发版的开关：启动参数带 `-XiaxiaV3 1`。只用编的示例数字，不打开任何账本文件。
/// `-XiaxiaV3Page overview / goals / wealth / ob1…ob5` 直接打开某一页（截图用）。
public enum V3Launch {
    public static var enabled: Bool {
        // 「夏夏账本 v3 试用.app」：包里写了 XiaxiaV3，双击就是 v3，不用带参数。
        if Bundle.main.object(forInfoDictionaryKey: "XiaxiaV3") as? Bool == true { return true }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-XiaxiaV3") else { return false }
        return i + 1 >= args.count || args[i + 1] != "0"
    }
    /// 内容铺到标题栏下面（V3Scene 用）。这时每页顶上要多留一点地方给三个圆点。
    nonisolated(unsafe) static var overTitleBar = false
    /// 截图用：数字不做滚动，直接显示。
    static let still = ProcessInfo.processInfo.arguments.contains("-XiaxiaV3Still")
    static func value(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    @MainActor static func apply(to state: V3State) {
        // `-XiaxiaV3Data empty`：从一本空账本开始，看每页没数据时的样子。
        if value("-XiaxiaV3Data") == "empty" { state.patch { $0.wipe() } }
        if ProcessInfo.processInfo.arguments.contains("-XiaxiaV3FakeUpdate") { state.updateVersion = "0.3.1" }
        if let f = value("-XiaxiaV3State") { state.forced = V3State.Forced(rawValue: f) }
        guard let p = value("-XiaxiaV3Page") else { return }
        if p.hasPrefix("ob"), let n = Int(p.dropFirst(2)), (1...5).contains(n) {
            state.onboardingStep = n - 1
        } else if ["smallerstep", "letter"].contains(p) {
            state.onboardingStep = nil
            state.wish = "三年后不用为钱发愁"
            state.ai = "Claude"
            if p == "smallerstep" { state.page = .goals; state.moment = .smallerStep }
            if p == "letter" {
                state.page = .goals
                state.patch {
                    $0.journey.resisted = 14
                    $0.journey.monthlyPlan = Money(cents: 100_00)
                    _ = $0.journey.deposit($0.journey.remainingToNext)
                }
                if let st = state.book.journey.stations.first(where: { $0.target == Money(cents: 700_00) }) {
                    let l = state.arrivalLetter(for: st)
                    state.patch { $0.letters.append(l) }
                    state.moment = .letter(l)
                }
            }
        } else if ["bigdecision", "log", "add", "ask", "askfrom"].contains(p) || p.hasPrefix("sheet-") || p.hasPrefix("set-") {
            state.onboardingStep = nil
            state.wish = "三年后不用为钱发愁"
            state.ai = "Claude"
            if p == "bigdecision" { state.page = .think; state.thinkBig = true }
            if p == "log" { state.page = .settings; state.showLog = true }
            if p == "add" { state.showAdd = true }
            V3Sheet.fromLaunch(p, state)
            if p.hasPrefix("set-"), let sub = V3State.SettingsSub(rawValue: String(p.dropFirst(4))) { state.page = .settings; state.settingsSub = sub }
            if p == "ask" { state.page = .overview; state.chatOpen = true }
            if p == "askfrom" { state.page = .overview; state.sayPopsToday = 0 }
        } else if let page = V3State.Page(rawValue: p) {
            state.wish = "三年后不用为钱发愁"
            state.ai = "Claude"
            state.onboardingStep = nil
            state.page = page
            state.side = V3State.Page.biz.contains(page) ? .biz : .life
        }
    }
}

/// 开发版自己的窗口：没有标题栏那一条，红黄绿三个点直接压在内容上（和设计稿一样）。
public struct V3Scene: Scene {
    public init() { V3Launch.overTitleBar = true }
    public var body: some Scene {
        Window("夏夏账本 v3 试用", id: "main") {
            // 系统会给三个圆点那一条另算 28 点高，所以这里写 584，整个窗口最小正好 1000×612。
            V3RootView().frame(minWidth: 1000, minHeight: 584)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
    }
}

public struct V3RootView: View {
    @State private var state: V3State

    public init() {
        let s = V3State()
        V3Launch.apply(to: s)
        _state = State(initialValue: s)
    }

    public var body: some View {
        GeometryReader { g in
            // 窗口比设计稿（1280×800）小就整体等比缩小，所以最小窗口（1000×612）也一屏看完；比它大就把多出来的地方分给内容。
            let s = min(g.size.width / V3.design.width, g.size.height / V3.design.height, 1)
            let canvas = CGSize(width: g.size.width / max(s, 0.01), height: g.size.height / max(s, 0.01))
            ZStack {
                if state.onboardingStep != nil {
                    V3Onboarding().environment(\.v3InlineXia, true).transition(.opacity)
                } else {
                    V3Shell().transition(.opacity)
                }
                V3MomentLayer().environment(\.v3InlineXia, true)
            }
            .frame(width: canvas.width, height: canvas.height)
            .overlay(alignment: .bottom) { V3ToastHost() }
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .background(V3.bg)
        .ignoresSafeArea(.container, edges: V3Launch.overTitleBar ? .all : [])
        .environment(state)
        .preferredColorScheme(.light)
        .background(V3WindowSetup())
        .foregroundStyle(V3.ink)
    }
}

/// 窗口：内容铺到标题栏下面，红黄绿三个点留在左上角（和设计稿一样）。
private struct V3WindowSetup: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // SwiftUI 自己也会设一遍窗口，所以晚一点再设，并多设两次。
            for delay in [0.0, 0.2, 0.8] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.setUp() }
            }
            if let window, token == nil {
                token = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setUp() }
                }
            }
        }
        private var token: NSObjectProtocol?
        private var sized = false
        private func setUp() {
            guard let w = window else { return }
            if !V3Launch.overTitleBar, w.styleMask.contains(.fullSizeContentView) { w.styleMask.remove(.fullSizeContentView) }
            if !w.titlebarAppearsTransparent { w.titlebarAppearsTransparent = true }
            if w.titleVisibility != .hidden { w.titleVisibility = .hidden }
            if w.titlebarSeparatorStyle != .none { w.titlebarSeparatorStyle = .none }
            if w.toolbar != nil { w.toolbar = nil }
            // 有的系统版本设了透明还留着一条灰底：直接把标题栏的底藏起来（三个圆点还在）。
            func hideBackground(_ v: NSView, _ depth: Int) {
                let name = String(describing: type(of: v))
                if name.contains("TitlebarBackground") || name.contains("TitlebarDecoration") || (name == "NSView" && depth == 2) {
                    if !v.isHidden { v.isHidden = true }
                    return
                }
                if depth < 3 { v.subviews.forEach { hideBackground($0, depth + 1) } }
            }
            if !V3Launch.overTitleBar {
                w.contentView?.superview?.subviews.filter { String(describing: type(of: $0)).contains("Titlebar") }.forEach { hideBackground($0, 0) }
            }
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(srgbRed: 0.863, green: 0.902, blue: 1, alpha: 1)
            w.minSize = NSSize(width: 1000, height: 612)
            // -XiaxiaWindowSize 1000x612：窗口内容改成这么大（检查最小窗口用）。
            if !sized, let v = V3Launch.value("-XiaxiaWindowSize") {
                sized = true
                let parts = v.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 {
                    // 整个窗口（连三个圆点那一条）就是这么大
                    var f = w.frame
                    f.origin.y += f.height - parts[1]
                    f.size = NSSize(width: parts[0], height: parts[1])
                    w.setFrame(f, display: true)
                }
            }
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}

// MARK: - 底部提示（带撤销）

private struct V3ToastHost: View {
    @Environment(V3State.self) private var state
    var body: some View {
        ZStack {
            if let t = state.toast {
                HStack(spacing: 14) {
                    Text(t.text).font(V3.font(14, .bold)).foregroundStyle(.white).lineLimit(1)
                    if t.canUndo {
                        Button("撤销") { state.undo() }
                            .buttonStyle(.plain).font(V3.font(14, .heavy)).foregroundStyle(V3.hex(0xFFD778))
                            .accessibilityLabel("撤销刚才这一步")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(V3.ink).shadow(color: V3.ink.opacity(0.25), radius: 10, y: 4))
                .id(t.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(.bottom, 26)
    }
}

// MARK: - 外壳：左边栏 + 顶栏 + 页面

struct V3Shell: View {
    @Environment(V3State.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            V3Sidebar()
            VStack(alignment: .leading, spacing: 16) {
                V3TopBar()
                pageBody.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(state.page)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
            }
            .padding(.init(top: V3Launch.overTitleBar ? 22 : 14, leading: 30, bottom: 26, trailing: 30))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(V3.bg)
            // 夏夏的消息和整页对话：盖在主区域上，左边栏一直留着
            .overlayPreferenceValue(V3SayKey.self) { saying in V3XiaLayer(saying: saying) }
            .clipped()
        }
        .overlay { if state.showAdd { V3AddSheet().environment(\.v3InlineXia, true).transition(.opacity) } }
        .overlay { if let sheet = state.sheet { V3SheetHost(sheet: sheet).environment(\.v3InlineXia, true).transition(.opacity) } }
        .sheet(isPresented: Bindable(state).showAddAccount) { V3AddAccountSheet().environment(state).environment(\.v3InlineXia, true) }
    }

    @ViewBuilder private var pageBody: some View {
        if state.forced == .loading { V3LoadingPage() }
        else if state.forced == .error { V3ErrorPage() }
        else if state.isEmpty(state.page) { V3EmptyPage(page: state.page) }
        else { pageData }
    }

    @ViewBuilder private var pageData: some View {
        switch state.page {
        case .overview: V3OverviewPage()
        case .goals: V3GoalsPage()
        case .wealth: V3WealthPage()
        case .spending: V3SpendingPage()
        case .trends: V3TrendsPage()
        case .transactions: V3TransactionsPage()
        case .think: V3ThinkPage()
        case .subscriptions: V3SubscriptionsPage()
        case .debts: V3DebtsPage()
        case .monthly: V3MonthlyPage()
        case .settings: V3SettingsPage()
        case .bizHome: V3BizHomePage()
        case .sales: V3SalesPage()
        case .fixed: V3FixedPage()
        case .payback: V3PaybackPage()
        case .stock: V3StockPage()
        case .checkup: V3CheckupPage()
        case .bizDebts: V3BizDebtsPage()
        }
    }
}

private struct V3Sidebar: View {
    @Environment(V3State.self) private var state

    var body: some View {
        let biz = state.side == .biz
        VStack(alignment: .leading, spacing: 4) {
            if state.mode == .both {
                sideSwitch.padding(.bottom, 14)
            }
            ForEach(Array((biz ? V3State.Page.biz : V3State.Page.life).enumerated()), id: \.element) { i, p in
                if i < 9 { navItem(p).keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command) } else { navItem(p) }
            }
            navItem(.settings).padding(.top, 6)
            Spacer(minLength: 8)
            goalCard
        }
        .padding(.init(top: V3Launch.overTitleBar ? 54 : 26, leading: 16, bottom: 16, trailing: 16))
        .frame(width: 232).frame(maxHeight: .infinity, alignment: .top)
        .background(biz ? V3.hex(0xDCEFF3) : V3.side)
    }

    private var sideSwitch: some View {
        HStack(spacing: 0) {
            seg("生活", .life)
            seg("生意", .biz)
        }
        .padding(3).background(Capsule().fill(V3.hex(0xD5DFFB)))
        .accessibilityElement(children: .contain).accessibilityLabel("看哪边")
    }

    private func seg(_ title: String, _ s: V3State.Side) -> some View {
        let on = state.side == s
        return Button { state.switchSide(s) } label: {
            Text(title).font(V3.font(13, .bold)).foregroundStyle(on ? .white : V3.ink2)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background {
                    if on { Capsule().fill(s == .biz ? V3.teal : V3.navy).background(Capsule().fill(V3.ink).offset(y: 2)) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(V3SinkStyle(depth: 2))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func navItem(_ p: V3State.Page) -> some View {
        let on = state.page == p && !state.chatOpen
        return Button { state.go(p) } label: {
            V3NavRow(on: on) {
            HStack(spacing: 10) {
                Image(systemName: p.symbol).font(.system(size: 14, weight: .semibold)).frame(width: 18)
                Text(p.title).font(V3.font(14.5, .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? (state.side == .biz ? V3.teal : V3.navy) : V3.ink2)
            .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .buttonStyle(V3PlainSink())
        .accessibilityAddTraits(on ? .isSelected : [])
        .help(p.title)
    }

    /// 左边栏最下面：AI 连着没有、今天改了几次。（目标那张卡总览里已经有了，这里不再放一遍，ming 2026-11-28。）
    private var goalCard: some View {
        let ai = state.ai ?? ""
        let linked = !ai.isEmpty && ai != "夏夏自带的"
        let changes = state.ledger.changes.filter { !$0.undone }.count
        return VStack(spacing: 8) {
            // 有新版本时才出现；平时没有这一行。
            if let v = state.updateVersion {
                Button { state.page = .settings; state.openSettings(.sync) } label: {
                    HStack(spacing: 6) {
                        Circle().fill(V3.red).frame(width: 8, height: 8)
                        Text("有新版本 \(v) · 更新").font(V3.font(12.5, .bold)).foregroundStyle(V3.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(V3.goodBG).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                    .contentShape(Capsule())
                }
                .buttonStyle(V3SinkStyle(depth: 2)).help("账本不动，只换 app 本身")
            }
            statusCard(linked: linked, ai: ai, changes: changes)
        }
    }

    private func statusCard(linked: Bool, ai: String, changes: Int) -> some View {
        VStack(spacing: 0) {
            statusRow(dot: linked ? V3.green : V3.dash, title: linked ? "\(ai) 连着" : "还没连 AI", help: "管理 AI 连接") {
                state.page = .settings; state.openSettings(.ai)
            }
            V3Divider()
            statusRow(symbol: "clock.arrow.circlepath", title: "今天改了 \(changes) 次", help: "改动记录：谁改的，都能撤销") {
                withAnimation(.snappy(duration: 0.2)) { state.page = .settings; state.settingsSub = nil; state.showLog = true }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
    }

    private func statusRow(dot: Color? = nil, symbol: String = "", title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let dot { Circle().fill(dot).frame(width: 9, height: 9).frame(width: 16) }
                else { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(V3.ink2).frame(width: 16) }
                Text(title).font(V3.font(13, .bold)).foregroundStyle(V3.ink).lineLimit(1).contentTransition(.numericText())
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(V3.ink2)
            }
            .padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    private func strip(_ m: Money) -> String { m.v3Short.replacingOccurrences(of: "\u{00A0}€", with: "") }
}

/// 左边栏的一行：选中是白底，鼠标移上去是半透明白底。
private struct V3NavRow<Content: View>: View {
    let on: Bool
    @ViewBuilder var content: Content
    @State private var hover = false
    var body: some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if on { shape.fill(.white).shadow(color: V3.navy.opacity(0.08), radius: 4, y: 2) }
                else if hover { shape.fill(.white.opacity(0.55)) }
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

private struct V3PlainSink: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 1 : 0).animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct V3TopBar: View {
    @Environment(V3State.self) private var state

    var body: some View {
        HStack(spacing: 14) {
            if state.page == .settings, state.settingsSub != nil || state.showLog {
                Button { withAnimation(.snappy(duration: 0.2)) { state.settingsSub = nil; state.showLog = false } } label: { Label("设置", systemImage: "chevron.left") }
                    .buttonStyle(.v3(.ghost, .small)).help("回到设置")
            }
            Text(title).font(V3.font(26, .heavy)).foregroundStyle(V3.ink).lineLimit(1).fixedSize()
            Text(subtitle).font(V3.font(14, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
            Spacer(minLength: 8)
            Button("问\(state.prefs.xiaName)") { state.openChat() }.buttonStyle(.v3(.ghost))
                .overlay(alignment: .topTrailing) {
                    // 夏夏有一句话没看：小红点
                    if state.sayUnreadID != nil {
                        Circle().fill(V3.red).overlay(Circle().strokeBorder(.white, lineWidth: 2)).frame(width: 13, height: 13).offset(x: 3, y: -3)
                            .transition(.scale.combined(with: .opacity)).accessibilityLabel("夏夏有一句话")
                    }
                }
                .keyboardShortcut("k", modifiers: .command).help("问夏夏（⌘K）")
            Button(state.side == .biz ? "+ 记今天的账" : "+ 记一笔") {
                if state.side == .biz { state.open(.shopDay(state.book.todayDay)) } else { withAnimation(.snappy(duration: 0.2)) { state.showAdd = true } }
            }
                .buttonStyle(.v3(state.side == .biz ? .teal : .primary))
                .keyboardShortcut("n", modifiers: .command).help("记一笔（⌘N）")
        }
        .frame(height: 48)
    }

    private var title: String {
        if state.page == .think, state.thinkBig { return "大决定" }
        if state.page == .settings, state.showLog { return "改动记录" }
        if state.page == .settings, let sub = state.settingsSub { return sub.title }
        if state.page == .monthly { return "10 月小结" }
        return state.page.title
    }

    /// 标题旁边只留「数据」：今天几号、哪家店。解释这页是干什么的那句话不放（ming 2026-11-27：小字太多）。
    private var subtitle: String {
        switch state.page {
        case .overview: state.today
        case .bizHome: "\(state.book.shopName) · 11 月"
        default: ""
        }
    }
}

// MARK: - 加账户

struct V3AddAccountSheet: View {
    @Environment(V3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var pick = 0
    @State private var name = ""
    @State private var amount = ""

    static let kinds: [(emoji: String, name: String, note: String, kind: V3State.Account.Kind)] = [
        ("💳", "银行卡", "平时花钱用的", .own),
        ("💶", "现金", "钱包里", .own),
        ("🤝", "跟别人借的", "欠的钱", .debt),
        ("🧑", "借给别人的", "别人欠我", .lent),
    ]

    var body: some View {
        let k = Self.kinds[pick]
        VStack(alignment: .leading, spacing: 14) {
            Text("加一个账户").font(V3.font(22, .heavy))
            HStack(spacing: 10) {
                ForEach(Array(Self.kinds.enumerated()), id: \.offset) { i, item in
                    V3Option(picked: pick == i) { pick = i } content: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.emoji) \(item.name)").font(V3.font(15, .bold)).foregroundStyle(V3.ink)
                            Text(item.note).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                        }
                    }
                    .frame(height: 70)
                }
            }
            HStack(spacing: 10) {
                field("叫什么（不填就叫「\(k.name)」）", text: $name)
                field(k.kind == .debt ? "欠多少（大概的数就行）" : "里面有多少（大概的数就行）", text: $amount).frame(width: 240)
            }
            if !amount.isEmpty && parsed == nil {
                V3Label("这个数我没看懂。写成 1500 或者 1.500,00 这样就行。", color: V3.red, weight: .semibold)
            }
            HStack {
                Spacer()
                Button("先不加") { dismiss() }.buttonStyle(.v3(.ghost)).keyboardShortcut(.cancelAction)
                Button("加上") {
                    state.addAccount(emoji: k.emoji, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? k.name : name,
                                     note: k.note, balance: parsed ?? .zero, kind: k.kind)
                    dismiss()
                }
                .buttonStyle(.v3).keyboardShortcut(.defaultAction).disabled(parsed == nil)
            }
        }
        .padding(26).frame(width: 640)
        .background(V3.bg)
        .foregroundStyle(V3.ink)
        .preferredColorScheme(.light)
    }

    private var parsed: Money? {
        guard let m = Money(parsing: amount), m >= .zero else { return nil }
        return m
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text).textFieldStyle(.plain).font(V3.font(15, .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2)))
    }
}
#endif
