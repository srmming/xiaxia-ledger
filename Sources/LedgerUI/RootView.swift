import FinanceCore
import SwiftUI

public enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview = "总览", transactions = "流水", plans = "计划", history = "改动记录", settings = "设置"
    public var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .transactions: "list.bullet.rectangle"
        case .plans: "target"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
    @ViewBuilder var screen: some View {
        switch self {
        case .overview: OverviewView()
        case .transactions: TransactionsView()
        case .plans: PlansView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

/// app 的根视图：iPhone 用标签栏，Mac 用侧栏。
public struct RootView: View {
    @Environment(LedgerModel.self) private var model
    @State private var section: AppSection? = .overview
    @State private var adding = false

    public init() {}

    public var body: some View {
        Group {
            if let error = model.loadError {
                ContentUnavailableView {
                    Label("账本读不出来", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("再试一次") { model.reload() }
                }
            } else {
                layout
            }
        }
        .tint(Color.coral)
        .sheet(isPresented: $adding) { NavigationStack { AddTransactionView() }.sheetSize() }
    }

    #if os(iOS)
    private var layout: some View {
        TabView(selection: Binding(get: { section ?? .overview }, set: { section = $0 })) {
            ForEach([AppSection.overview, .transactions, .plans, .settings]) { s in
                NavigationStack {
                    s.screen.toolbar { addButton }
                }
                .tabItem { Label(s.rawValue, systemImage: s.symbol) }
                .tag(s)
            }
        }
    }
    #else
    private var layout: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            NavigationStack { (section ?? .overview).screen }
                .toolbar { addButton }
        }
    }
    #endif

    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { adding = true } label: { Label("记一笔", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: .command)
        }
    }
}

/// 两个 app 共用的场景。
public struct XiaxiaScene: Scene {
    @State private var model: LedgerModel

    public init() {
        // 截图和演示：启动参数带 -XiaxiaDemo 就用编造的示例账本，不碰真实数据。
        if ProcessInfo.processInfo.arguments.contains("-XiaxiaDemo") {
            _model = State(initialValue: LedgerModel.demo())
        } else {
            _model = State(initialValue: LedgerModel(store: LedgerStores.defaultStore()))
        }
    }

    public var body: some Scene {
        WindowGroup("夏夏账本") {
            RootView()
                .environment(model)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新读取账本") { model.reload() }.keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }
}
