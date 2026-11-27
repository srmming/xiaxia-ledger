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
    static func value(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    @MainActor static func apply(to state: V3State) {
        guard let p = value("-XiaxiaV3Page") else { return }
        if p.hasPrefix("ob"), let n = Int(p.dropFirst(2)), (1...5).contains(n) {
            state.onboardingStep = n - 1
        } else if ["firststep", "smallerstep", "letter"].contains(p) {
            state.onboardingStep = nil
            state.wish = "三年后不用为钱发愁"
            state.ai = "Claude"
            if p == "firststep" { state.moment = .firstStep }
            if p == "smallerstep" { state.page = .goals; state.moment = .smallerStep }
            if p == "letter" {
                state.page = .goals
                state.book.journey.resisted = 14
                state.book.journey.monthlyPlan = Money(cents: 100_00)
                _ = state.book.journey.deposit(state.book.journey.remainingToNext)
                if let st = state.book.journey.stations.first(where: { $0.target == Money(cents: 700_00) }) {
                    let l = state.arrivalLetter(for: st)
                    state.book.letters.append(l)
                    state.moment = .letter(l)
                }
            }
        } else if ["bigdecision", "log", "add", "ask"].contains(p) {
            state.onboardingStep = nil
            state.wish = "三年后不用为钱发愁"
            state.ai = "Claude"
            if p == "bigdecision" { state.page = .think; state.thinkBig = true }
            if p == "log" { state.page = .settings; state.showLog = true }
            if p == "add" { state.showAdd = true }
            if p == "ask" { state.page = .spending; state.showAsk = true }
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
                    V3Onboarding().transition(.opacity)
                } else {
                    V3Shell().transition(.opacity)
                }
                V3MomentLayer()
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
                    .transition(.opacity)
            }
            .padding(.init(top: V3Launch.overTitleBar ? 22 : 14, leading: 30, bottom: 24, trailing: 30))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(V3.bg)
        }
        .overlay(alignment: .trailing) {
            if state.showAsk {
                ZStack(alignment: .trailing) {
                    V3.ink.opacity(0.18).onTapGesture { withAnimation(.snappy(duration: 0.25)) { state.showAsk = false } }.accessibilityHidden(true)
                    V3AskPanel().transition(.move(edge: .trailing))
                }
                .transition(.opacity)
            }
        }
        .overlay { if state.showAdd { V3AddSheet().transition(.opacity) } }
        .sheet(isPresented: Bindable(state).showAddAccount) { V3AddAccountSheet().environment(state) }
    }

    @ViewBuilder private var pageBody: some View {
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
            if state.mode != .life || biz {
                sideSwitch.padding(.bottom, 14)
            }
            ForEach(biz ? V3State.Page.biz : V3State.Page.life) { p in navItem(p) }
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
        let on = state.page == p
        return Button { state.go(p) } label: {
            HStack(spacing: 10) {
                Image(systemName: p.symbol).font(.system(size: 14, weight: .semibold)).frame(width: 18)
                Text(p.title).font(V3.font(14.5, .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? (state.side == .biz ? V3.teal : V3.navy) : V3.ink2)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                if on { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white).shadow(color: V3.navy.opacity(0.08), radius: 4, y: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(V3SinkStyle(depth: 1))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 左边栏最下面一直看得到：目标走到哪了。
    @ViewBuilder private var goalCard: some View {
        if state.side == .biz {
            Button { state.go(.payback) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("店的这条路 · 回本").font(V3.font(12, .regular)).foregroundStyle(V3.ink2)
                    Text("还差 15.442\u{00A0}€").font(V3.num(14.5)).foregroundStyle(V3.ink)
                    V3Bar(fraction: 0.52, color: V3.teal)
                    Text("走了 52%").font(V3.font(12, .regular)).foregroundStyle(V3.ink2)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            }
            .buttonStyle(V3SinkStyle(depth: 2))
        } else {
            let j = state.book.journey
            let next = j.nextStation?.target ?? j.total
            Button { state.go(.goals) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("我的目标 · \(j.name)").font(V3.font(12, .regular)).foregroundStyle(V3.ink2)
                    Text(j.isFinished ? "走完了 \(j.total.v3Short)" : "这一站 \(strip(j.saved)) / \(next.v3Short)")
                        .font(V3.num(14.5)).foregroundStyle(V3.ink).contentTransition(.numericText())
                    V3Bar(fraction: next > .zero ? Double(j.saved.cents) / Double(next.cents) : 1)
                    Text(j.isFinished ? "电脑到手" : "还差 \(j.remainingToNext.v3Short) · 12 月 20 日前")
                        .font(V3.font(12, .regular)).foregroundStyle(V3.ink2).contentTransition(.numericText())
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            }
            .buttonStyle(V3SinkStyle(depth: 2))
            .accessibilityLabel("我的目标，\(j.name)，到这一站还差 \(j.remainingToNext.v3Short)")
        }
    }

    private func strip(_ m: Money) -> String { m.v3Short.replacingOccurrences(of: "\u{00A0}€", with: "") }
}

private struct V3TopBar: View {
    @Environment(V3State.self) private var state

    var body: some View {
        HStack(spacing: 14) {
            Text(title).font(V3.font(26, .heavy)).foregroundStyle(V3.ink).lineLimit(1).fixedSize()
            Text(subtitle).font(V3.font(14, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
            Spacer(minLength: 8)
            Button("问夏夏") { withAnimation(.snappy(duration: 0.25)) { state.showAsk.toggle() } }.buttonStyle(.v3(.ghost))
                .keyboardShortcut("k", modifiers: .command)
            Button("+ 记一笔") { withAnimation(.snappy(duration: 0.2)) { state.showAdd = true } }
                .buttonStyle(.v3(state.side == .biz ? .teal : .primary))
                .keyboardShortcut("n", modifiers: .command)
        }
        .frame(height: 48)
    }

    private var title: String {
        if state.page == .think, state.thinkBig { return "大决定" }
        if state.page == .settings, state.showLog { return "改动记录" }
        if state.page == .monthly { return "10 月小结" }
        return state.page.title
    }

    private var subtitle: String {
        switch state.page {
        case .overview: state.today
        case .goals: "一个大目标，拆成几站慢慢走"
        case .wealth: "你现在一共有多少、欠多少、净剩多少"
        case .spending: "11 月 · 钱花到哪了"
        case .trends: "往后看：月底、下个月、还能撑多久"
        case .transactions: "钱自己进来，你只管看一眼"
        case .think: state.thinkBig ? "离职、创业、买大件之前，先算一算" : "买之前算一算，我不替你决定"
        case .subscriptions: "每个月自己扣走的钱"
        case .debts: "先还哪个、哪天还完"
        case .monthly: "每个月一份，11 月 1 日写好"
        case .settings: state.showLog ? "账本每一次改动都记着是谁改的，都能撤销" : ""
        case .bizHome: "Miora 小店 · 11 月"
        case .sales: "每天只记一个总数"
        case .fixed: "不管开不开门，每个月都要付的"
        case .payback: "开店投进去的钱，赚回来多少了"
        case .stock: "不数库存，只估一个总数"
        case .checkup: "每个季度一次 · 第三季度（7–9 月）"
        case .bizDebts: "店欠别人的，别人欠店里的"
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
                V3Label(k.kind == .debt ? "欠的钱用红色，会从净剩里减掉。" : k.kind == .lent ? "别人欠你的用蓝色，收回来之前不算进「一共有」。" : "加上以后，家底的数马上跟着变。")
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
