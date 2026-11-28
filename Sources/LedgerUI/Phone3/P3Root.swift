#if os(iOS)
import FinanceCore
import SwiftUI

/// iPhone 界面 v3 的根：底部五格（总览、流水、记一笔、目标 / 店的家底、我的），不做引导，打开直接到总览。
public struct PhoneV3Root: View {
    @State private var state: P3State
    private var model: LedgerModel?
    /// 试用版：只用编的示例数。
    public init() { _state = State(initialValue: P3State()) }
    /// 正式的 app：接着 app 里那本正式账本（和旧界面同一个模型：存盘、同步都是它的）。
    public init(model: LedgerModel) {
        _state = State(initialValue: P3State(model: model))
        self.model = model
    }

    public var body: some View {
        @Bindable var state = state
        ZStack(alignment: .bottom) {
            P3.bg.ignoresSafeArea()
            Group {
                switch state.tab {
                case .home: P3HomePage()
                case .flow: P3FlowPage()
                case .goals: if state.side == .biz { NavigationStack { P3ShopWealthPage(isTab: true) } } else { P3GoalsPage() }
                case .xia: P3ChatView(inTab: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 62) }

            if let t = state.toast {
                P3ToastView(text: t.text, canUndo: t.canUndo, isError: t.isError) { state.undo() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, state.tab == .xia ? 150 : 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
            P3TabBar().zIndex(1)
        }
        .environment(state)
        // 正式账本在别处变了（AI、命令行、Mac）：界面上的数跟着重新算
        .onChange(of: model?.ledger) { _, _ in state.refreshFromModel() }
        .tint(state.side == .biz ? P3.teal : P3.navy)
        .preferredColorScheme(.light)
        .sensoryFeedback(trigger: state.toast) { _, new in
            guard let new else { return nil }
            return new.isError ? .error : .success
        }
        .p3Sheets($state.sheet, state)
        .sheet(isPresented: $state.meOpen) {
            P3MePage().environment(state)
                .overlay(alignment: .bottom) {
                    // 「我的」盖在上面时，提示条也要看得见（能点撤销）
                    if let t = state.toast {
                        P3ToastView(text: t.text, canUndo: t.canUndo, isError: t.isError) { state.undo() }
                            .padding(.horizontal, 16).padding(.bottom, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .p3Sheets($state.meSheet, state)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
        }
    }
}

extension View {
    /// 所有从底下弹出来的（根和「我的」各挂一份）。
    func p3Sheets(_ item: Binding<P3State.Sheet?>, _ state: P3State) -> some View { modifier(P3SheetHost(state: state, item: item)) }
}

struct P3SheetHost: ViewModifier {
    let state: P3State
    @Binding var item: P3State.Sheet?
    func body(content: Content) -> some View {
        content.sheet(item: $item) { sheet in
            Group {
                switch sheet {
                case .add: P3AddSheet()
                case .edit(let id): P3EditSheet(entryID: id)
                case .save(let id): P3SaveSheet(smallID: id)
                case .holdBack: P3HoldBackSheet()
                case .smallerStep: P3SmallerStepSheet()
                case .newBigGoal: P3GoalEditor(smallID: nil, big: true)
                case .editBigGoal: P3GoalEditor(smallID: nil, big: true, editBig: true)
                case .smallGoal(let id): P3GoalEditor(smallID: id, big: false)
                case .transfer: P3TransferSheet()
                case .account(let n): P3AccountEditor(editing: n)
                case .repay(let n): P3RepaySheet(debt: n)
                }
            }
            .environment(state)
            .overlay(alignment: .top) {
                // 弹出来的单子盖住了底下的提示条：没做成的原因要在单子上就看得见
                if let t = state.toast, t.isError {
                    P3ToastView(text: t.text, canUndo: false, isError: true) {}
                        .padding(.horizontal, 16).padding(.top, 28)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .presentationCornerRadius(26)
            .presentationDragIndicator(.visible)
            .presentationBackground(P3.bg)
        }
    }
}

// MARK: - 底部五格

struct P3TabBar: View {
    @Environment(P3State.self) private var state

    var body: some View {
        let biz = state.side == .biz
        HStack(alignment: .bottom, spacing: 0) {
            item(.home, biz ? "店里" : "总览", biz ? "storefront" : "house")
            item(.flow, "流水", "list.bullet")
            Button { state.sheet = .add } label: {
                Image(systemName: "plus").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(biz ? P3.teal : P3.navy).overlay(Circle().strokeBorder(P3.ink, lineWidth: 2.5)))
                    .background(Circle().fill(P3.ink).offset(y: 3))
            }
            .buttonStyle(P3Sink(depth: 3))
            .contextMenu {
                Button { ask(.camera) } label: { Label("拍照问夏夏", systemImage: "camera") }
                Button { ask(.voice) } label: { Label("说话问夏夏", systemImage: "mic") }
            }
            .frame(maxWidth: .infinity)
            .offset(y: -14)
            .accessibilityLabel(biz ? "记一笔店里的账" : "记一笔")
            item(.goals, biz ? "店的家底" : "目标", biz ? "building.columns" : "flag")
            item(.xia, "夏夏", "bubble.left.and.bubble.right", badge: state.chat.unread)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .frame(height: 62, alignment: .top)
        .background {
            Rectangle().fill(.white).ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(P3.line).frame(height: 1) }
        }
    }

    private func ask(_ intent: P3State.ChatIntent) {
        // 等长按的小菜单收起来再换页（菜单还在时换，底下的页面不跟着变）
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            state.chat.unread = 0
            state.chatIntent = intent
            state.tab = .xia
        }
    }

    private func item(_ tab: P3State.Tab, _ title: String, _ symbol: String, badge: Int = 0) -> some View {
        let on = state.tab == tab
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                if tab == .xia { state.chat.unread = 0 }
                state.tab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 20, weight: on ? .bold : .regular))
                    .symbolEffect(.bounce, value: on)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white)
                                .frame(minWidth: 17, minHeight: 17).background(Circle().fill(P3.red)).offset(x: 9, y: -6)
                        }
                    }
                Text(title).font(P3.font(10.5, on ? .bold : .medium))
            }
            .foregroundStyle(on ? (state.side == .biz ? P3.teal : P3.navy) : P3.ink2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityLabel(badge > 0 ? "\(title)，\(badge) 条新消息" : title)
    }
}

/// 右上角的「我的」：花销、家底、订阅、设置都在里面。
struct P3MeButton: View {
    @Environment(P3State.self) private var state
    var body: some View {
        Button { state.mePath = []; state.meOpen = true } label: {
            Image(systemName: "person.crop.circle").font(.system(size: 26, weight: .regular)).foregroundStyle(P3.navy)
                .frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .accessibilityLabel("我的：花销、家底、设置")
    }
}

// MARK: - 每页顶上：大标题 + 月份 + 生活 / 生意

struct P3Header<Trail: View>: View {
    @Environment(P3State.self) private var state
    let title: String
    var months = false
    var sideSwitch = false
    var meButton = false
    @ViewBuilder var trail: Trail

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).font(.system(size: 30, weight: .heavy)).foregroundStyle(P3.ink).lineLimit(1).fixedSize()
            if months { P3MonthSwitch() }
            Spacer(minLength: 4)
            trail
            if sideSwitch, state.book.showLife, state.book.showBiz { P3SideSwitch() }
            if meButton { P3MeButton() }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
    }
}

extension P3Header where Trail == EmptyView {
    init(title: String, months: Bool = false, sideSwitch: Bool = false, meButton: Bool = false) {
        self.title = title; self.months = months; self.sideSwitch = sideSwitch; self.meButton = meButton; self.trail = EmptyView()
    }
}

struct P3MonthSwitch: View {
    @Environment(P3State.self) private var state
    var body: some View {
        HStack(spacing: 0) {
            Button { state.flipMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 32).contentShape(Rectangle())
            }
            .disabled(!state.canGoBack)
            .opacity(state.canGoBack ? 1 : 0.3)
            .accessibilityLabel("上个月")
            Text(state.monthTitle).font(P3.font(14, .bold)).foregroundStyle(P3.ink2).contentTransition(.numericText()).fixedSize()
            Button { state.flipMonth(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 32).contentShape(Rectangle())
            }
            .disabled(state.isThisMonth)
            .opacity(state.isThisMonth ? 0.3 : 1)
            .accessibilityLabel("下个月")
        }
        .foregroundStyle(P3.ink2)
        .background(Capsule().fill(.white.opacity(0.7)))
    }
}

struct P3SideSwitch: View {
    @Environment(P3State.self) private var state
    var body: some View {
        HStack(spacing: 0) {
            seg("生活", .life)
            seg("生意", .biz)
        }
        .padding(3)
        .background(Capsule().fill(P3.hex(0xD5DFFB)))
    }
    private func seg(_ t: String, _ s: P3State.Side) -> some View {
        let on = state.side == s
        return Button { state.switchSide(s) } label: {
            Text(t).font(P3.font(13, .bold)).foregroundStyle(on ? .white : P3.ink2)
                .padding(.horizontal, 12).frame(height: 30)
                .background {
                    if on { Capsule().fill(s == .biz ? P3.teal : P3.navy).shadow(color: P3.ink, radius: 0, y: 2) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 「我的」里点进去的页：标题在导航栏上，返回用系统的。
struct P3SubPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(P3.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
