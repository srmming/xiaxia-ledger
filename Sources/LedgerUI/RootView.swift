import FinanceCore
import SwiftUI

public enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview = "总览", transactions = "流水", reports = "报表", plans = "计划"
    case importer = "导入", history = "改动记录", settings = "设置"
    public var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .transactions: "list.bullet.rectangle"
        case .reports: "chart.bar.xaxis"
        case .plans: "target"
        case .importer: "tray.and.arrow.down"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
    @ViewBuilder var screen: some View {
        switch self {
        case .overview: OverviewView()
        case .transactions: TransactionsView()
        case .reports: ReportsView()
        case .plans: PlansView()
        case .importer: ImportView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
    /// Mac 侧栏分两组：天天看的，和偶尔用的。
    static let main: [AppSection] = [.overview, .transactions, .reports, .plans]
    static let tools: [AppSection] = [.importer, .history, .settings]
    /// iPhone 底部的标签。导入和改动记录在「设置」里。
    static let tabs: [AppSection] = [.overview, .transactions, .reports, .plans, .settings]
}

/// app 的根视图：iPhone 用标签栏，Mac 用侧栏。
public struct RootView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        @Bindable var model = model
        Group {
            if let error = model.loadError {
                ContentUnavailableView {
                    Label("账本读不出来", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error + "\n\n账本文件在 iCloud 云盘的「夏夏账本」文件夹里。先确认 iCloud 云盘开着、文件已经下载到这台设备。")
                } actions: {
                    Button("再试一次") { model.reload() }.buttonStyle(.borderedProminent)
                }
            } else if model.ledger.accounts.isEmpty && !model.isLoading {
                OnboardingView()
            } else {
                layout
            }
        }
        .tint(Color.coral)
        .overlay(alignment: .bottom) {
            ZStack { toastLayer }.animation(.snappy, value: model.toast)
        }
        .sheet(item: $model.sheet) { sheet in
            NavigationStack { content(for: sheet) }
                .environment(model)
                .tint(Color.coral)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.sheet == nil { model.refreshIfChanged() }
        }
    }

    @ViewBuilder
    private func content(for sheet: AppSheet) -> some View {
        switch sheet {
        case .add: TransactionEditor().sheetSize(height: 620)
        case .edit(let id):
            if let t = model.transaction(id) { TransactionEditor(editing: t).sheetSize(height: 620) }
            else { ContentUnavailableView("这一笔已经不在了", systemImage: "tray").sheetSize() }
        case .addDebt(let direction): AddDebtView(direction: direction).sheetSize()
        case .addInstallment: AddInstallmentView().sheetSize(height: 600)
        case .addGoal: AddGoalView().sheetSize()
        case .importer: ImportView(inSheet: true).sheetSize(width: 620, height: 640)
        case .triage: TriageView().sheetSize(width: 560, height: 620)
        case .addAccount: AddAccountView().sheetSize(height: 420)
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = model.toast {
            ToastView(toast: toast) { model.undo(toast.changeID ?? UUID()) }
                .padding(.bottom, toastInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(toast.changeID == nil ? 3 : 6))
                    if model.toast?.id == toast.id { withAnimation { model.toast = nil } }
                }
                .id(toast.id)
        }
    }

    private var toastInset: CGFloat {
        #if os(iOS)
        64
        #else
        18
        #endif
    }

    #if os(iOS)
    private var layout: some View {
        @Bindable var model = model
        return TabView(selection: Binding(get: { model.section ?? .overview }, set: { model.section = $0 })) {
            ForEach(AppSection.tabs) { s in
                NavigationStack {
                    s.screen.toolbar { AddMenu(model: model) }
                }
                .tabItem { Label(s.rawValue, systemImage: s.symbol) }
                .tag(s)
            }
        }
    }
    #else
    private var layout: some View {
        @Bindable var model = model
        return NavigationSplitView {
            List(selection: $model.section) {
                Section {
                    ForEach(AppSection.main) { s in Label(s.rawValue, systemImage: s.symbol).tag(s) }
                }
                Section("工具") {
                    ForEach(AppSection.tools) { s in
                        Label(s.rawValue, systemImage: s.symbol)
                            .tag(s)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            NavigationStack { (model.section ?? .overview).screen }
                .id(model.section)
                .toolbar { AddMenu(model: model) }
        }
    }

    /// 侧栏底部：还没整理的笔数，点一下去整理。
    @ViewBuilder
    private var sidebarFooter: some View {
        let n = model.untidy.count
        if n > 0 {
            Button { model.sheet = .triage } label: {
                HStack {
                    Image(systemName: "tray.full")
                    Text("\(n) 笔等整理")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .font(.subheadline)
                .padding(10)
                .background(Color.coral.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }
    #endif
}

/// 右上角的 ＋：点一下记一笔，按住（Mac 上点旁边的小箭头）还能记欠款、分期、目标、导入。
struct AddMenu: ToolbarContent {
    let model: LedgerModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { model.sheet = .add } label: { Label("记一笔", systemImage: "plus") }
                Divider()
                Button { model.sheet = .addDebt(.theyOweMe) } label: { Label("记一笔欠款", systemImage: "person.2") }
                Button { model.sheet = .addInstallment } label: { Label("记一个分期", systemImage: "calendar") }
                Button { model.sheet = .addGoal } label: { Label("建一个存钱目标", systemImage: "target") }
                Divider()
                Button { model.sheet = .importer } label: { Label("导入对账单", systemImage: "tray.and.arrow.down") }
            } label: {
                Label("记一笔", systemImage: "plus")
            } primaryAction: {
                model.sheet = .add
            }
            .help("记一笔（⌘N）。点旁边的箭头还能记欠款、分期、目标、导入对账单")
        }
    }
}

/// 两个 app 共用的场景。
public struct XiaxiaScene: Scene {
    @State private var model: LedgerModel

    public init() {
        // 截图和演示：启动参数带 -XiaxiaDemo 就用编造的示例账本，-XiaxiaEmpty 是空账本（看第一次打开的样子），都不碰真实数据。
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-XiaxiaDemo") {
            _model = State(initialValue: LedgerModel.demo())
        } else if args.contains("-XiaxiaEmpty") {
            _model = State(initialValue: LedgerModel.empty())
        } else {
            _model = State(initialValue: LedgerModel(store: LedgerStores.defaultStore()))
        }
    }

    public var body: some Scene {
        WindowGroup("夏夏账本") {
            RootView()
                .environment(model)
                #if os(macOS)
                .frame(minWidth: 920, minHeight: 620)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("记一笔") { model.sheet = .add }.keyboardShortcut("n", modifiers: .command)
                Button("记一笔欠款") { model.sheet = .addDebt(.theyOweMe) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("导入对账单…") { model.sheet = .importer }.keyboardShortcut("i", modifiers: .command)
                Button("整理还没分类的") { model.sheet = .triage }.keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu("账本") {
                Button("撤销上一步改动") { model.undoLast() }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                    .disabled(model.undoStack.isEmpty)
                Button("重新读取账本") { model.reload() }.keyboardShortcut("r", modifiers: .command)
                Divider()
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.rawValue) { model.section = s }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }
        #endif
    }
}
