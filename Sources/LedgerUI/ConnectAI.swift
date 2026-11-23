import FinanceCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

// 「连上你的 AI」：Mac 第一次打开时弹出，设置里也能再打开。
// 夏夏账本自带 fin（MCP 服务），这里找出这台 Mac 装了哪些 AI 工具，点一下帮它们写好 MCP 配置，
// 再给一句话去试，AI 一连上账本这里就变绿。iPhone 不用连（AI 工具只能在 Mac 上接本地账本）。

/// app 自带的 fin 在哪。
enum BundledFin {
    static var path: String? {
        let fm = FileManager.default
        // 正式 app：夏夏账本.app/Contents/MacOS/fin
        if let u = Bundle.main.url(forAuxiliaryExecutable: "fin"), fm.isExecutableFile(atPath: u.path) { return u.path }
        // swift run 开发版：和 app 在同一个 build 目录
        if let u = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("fin"), fm.isExecutableFile(atPath: u.path) {
            return u.path
        }
        // 以前用脚本装过的
        let local = NSHomeDirectory() + "/.local/bin/fin"
        return fm.isExecutableFile(atPath: local) ? local : nil
    }
}

extension LedgerModel {
    /// 示例 / 空账本（截图、演示）：连 AI 只写进一个临时的假主目录，不动这台 Mac 真的配置。
    var usesSampleData: Bool { store is InMemoryLedgerStore }

    var aiConnector: AIConnector? {
        let args = ProcessInfo.processInfo.arguments
        // -XiaxiaFreshAI：假装是一台还没连过 AI 的新电脑（看引导里「没配置好」的样子），同样只写假主目录。
        let fresh = args.contains("-XiaxiaFreshAI")
        guard let fin = BundledFin.path ?? (usesSampleData ? "/Applications/夏夏账本.app/Contents/MacOS/fin" : nil) else { return nil }
        guard usesSampleData || fresh else { return AIConnector(fin: fin) }
        let noTools = args.contains("-XiaxiaNoTools")
        let fake = FileManager.default.temporaryDirectory
            .appendingPathComponent(fresh ? (noTools ? "xiaxia-fresh-home-empty" : "xiaxia-fresh-home") : (noTools ? "xiaxia-sample-home-empty" : "xiaxia-sample-home"))
        if fresh, !Self.freshHomeReset {
            // 每次打开都从「没连过」开始。
            Self.freshHomeReset = true
            try? FileManager.default.removeItem(at: fake)
        }
        if !noTools {
            // 演示时假装装了 Claude 桌面版和 Codex
            for dir in ["Library/Application Support/Claude", ".codex"] {
                try? FileManager.default.createDirectory(at: fake.appendingPathComponent(dir), withIntermediateDirectories: true)
            }
        }
        let c = AIConnector(home: fake, fin: fin, appFolders: [fake.appendingPathComponent("Applications")])
        if args.contains("-XiaxiaAIStates") {
            // 截图看各种状态：Claude 桌面版写好了（等重开）、Hermes 以前连过但夏夏账本换了位置、Codex 装了没连、装了 ChatGPT。
            for dir in [".hermes", "Applications/ChatGPT.app"] {
                try? FileManager.default.createDirectory(at: fake.appendingPathComponent(dir), withIntermediateDirectories: true)
            }
            try? c.connect(.claudeDesktop)
            try? AIConnector(home: fake, fin: "/Volumes/旧位置/夏夏账本.app/Contents/MacOS/fin", appFolders: c.appFolders).connect(.hermes)
        }
        return c
    }

    nonisolated(unsafe) private static var freshHomeReset = false

    /// 「一键复制配置提示词」：粘给任何 AI，它自己配好。
    var aiSetupPrompt: String { AIConnector.setupPrompt(fin: aiConnector?.fin ?? "/Applications/夏夏账本.app/Contents/MacOS/fin") }

    /// 有没有任何 AI 连过账本：写过账、握过手、或者配置里已经有了。
    var anyAIConnected: Bool {
        if !aiTools.isEmpty { return true }
        if !usesSampleData, !AIConnections.load().isEmpty { return true }
        guard let c = aiConnector else { return false }
        return AIApp.allCases.contains { c.isConnected($0) }
    }

    /// Mac 第一次打开、还没连过任何 AI：弹「连上你的 AI」。只弹一次，以后从设置里进。
    func showAISetupIfNeeded() {
        #if os(macOS)
        let key = "xiaxia.aiSetupShown"
        guard !usesSampleData, !UserDefaults.standard.bool(forKey: key), sheet == nil, loadError == nil else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !anyAIConnected { sheet = .connectAI }
        #endif
    }

    /// app 换了位置（比如从「下载」拖进「应用程序」），已经连过的 AI 配置还指着旧位置：悄悄改成新位置。
    /// 只改夏夏账本自己那一项，而且只在旧位置的 fin 已经不在时才改。
    func repairAIConnections() {
        #if os(macOS)
        guard !usesSampleData, let c = aiConnector else { return }
        for app in AIApp.allCases where c.needsRepair(app) { try? AISetup(connector: c).connect(app) }
        // 更新到新版后，已经装过的 skill 和提示词跟着换新（ming 2026-11-23：更新后 AI 还按旧说明把旧小票记成今天）。
        AISetup(connector: c).refreshInstalled()
        #endif
    }
}

struct ConnectAIView: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    @State private var openedAt = Date()
    @State private var installed: Set<AIApp> = []
    @State private var connected: Set<AIApp> = []
    @State private var repair: Set<AIApp> = []
    @State private var unsupported: [UnsupportedAI] = []
    @State private var handshakes: [String: Date] = [:]
    @State private var firstLoad = true

    private var connector: AIConnector? { model.aiConnector }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 30, weight: .semibold)).foregroundStyle(Color.ai)
                        .accessibilityHidden(true)
                    Text("连接你的 AI").font(.title2.weight(.bold))
                    Text("夏夏账本靠 AI 记账：你跟 AI 说「今天买菜花了 23 €」，它就记进这本账，还能帮你导入对账单、写月报。连一次就好。")
                        .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                    Text("账本只在你自己的电脑和 iCloud 里，不经过我们的服务器。")
                        .font(.caption).foregroundStyle(Color.fg2)
                }
                .padding(.vertical, 4)
            }

            if connector == nil {
                Section {
                    Label("这个版本没带记账服务（fin），连不了 AI。请下载正式版夏夏账本。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.alert)
                }
            } else {
                if shownApps.isEmpty && unsupported.isEmpty && !firstLoad {
                    // 这台 Mac 上一个 AI 都没有：先告诉他装哪个，别先给一排「没找到」和用不上的「连上」说明。
                    otherSection
                    selfSetupSection
                } else {
                    toolsSection
                    selfSetupSection
                    otherSection
                }
                trySection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("连接你的 AI")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(anyGreen ? "关闭" : "以后再说") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }.disabled(!anyGreen)
            }
        }
        .task {
            // 每 2 秒看一眼：哪些工具装了 / 连上了，AI 有没有握手、有没有写进账本。
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: ① 每个 AI 一个「连接」

    private var toolsSection: some View {
        Section {
            AIHealthList(showMissing: true)
        } header: {
            Text("① 点「连接」，夏夏账本帮你配好")
        } footer: {
            footnote("点「连接」会在这个 AI 的设置里加上「夏夏账本」这一项，别的设置不动；改之前留一份备份（.bak-xiaxia）。写好后夏夏账本自己测一次能不能读到账本。")
        }
    }

    private var shownApps: [AIApp] { AIApp.allCases.filter { installed.contains($0) || connected.contains($0) || repair.contains($0) } }

    // MARK: 或者让 AI 自己配

    private var selfSetupSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("复制配置提示词，粘给任何一个 AI，它会自己把夏夏账本配好").font(.body)
                    Text("它会自己配、自己测，测到能读到账本为止；要你点「允许」的地方，它会弹选项问你，不用你自己翻设置。接不了的 AI（比如网页版）会直接告诉你换哪个。")
                        .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    Clipboard.copy(model.aiSetupPrompt)
                    model.toast = .init(text: "已复制配置提示词，粘贴给你的 AI 就行", changeID: nil)
                } label: { Label("一键复制配置提示词", systemImage: "doc.on.doc") }
                    .buttonStyle(.softAI)
            }
        } header: {
            Text("或者：让 AI 自己配")
        }
    }

    // MARK: ② 没装 / 用别的

    private var otherSection: some View {
        Section {
            if shownApps.isEmpty {
                Text("这台 Mac 上还没有能连的 AI 工具。挑一个装上，这一页会自动认出来，再点「连上」就行：")
                    .font(.callout)
            }
            linkRow("下载 Claude 桌面版", note: "最省事，装好登录就能用", url: "https://claude.ai/download", symbol: "arrow.down.circle.fill")
            linkRow("用 DeepSeek？装 Hermes Agent", note: "开源的 AI 助手，能接 DeepSeek，也能用 ChatGPT、Claude 的订阅登录；装好后回来点「连上」",
                    url: "https://hermes-agent.nousresearch.com", symbol: "arrow.down.circle.fill")
            linkRow("用通义千问、Kimi、豆包？装 Cherry Studio", note: "在它的「MCP 服务器」设置里粘贴下面复制的配置",
                    url: "https://www.cherry-ai.com", symbol: "arrow.down.circle.fill")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("别的 AI 工具（Trae、ChatWise、LM Studio…）").font(.body)
                    Text("复制下面这段，粘进它的 MCP 设置").font(.caption).foregroundStyle(Color.fg2)
                }
                Spacer(minLength: 8)
                Button {
                    Clipboard.copy(model.mcpConfig)
                    model.toast = .init(text: "MCP 配置已复制", changeID: nil)
                } label: { Label("复制配置", systemImage: "doc.on.doc") }
                    .buttonStyle(.softAI)
            }
        } header: {
            Text(shownApps.isEmpty ? "① 先装一个 AI" : "② 没有这些 AI，或者用别的")
        }
    }

    private func linkRow(_ title: String, note: String, url: String, symbol: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(note).font(.caption).foregroundStyle(Color.fg2)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Color.fg3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: ③ 试一句

    private var trySection: some View {
        let sentence = "用夏夏账本帮我记一笔：今天买咖啡花了 3,50 €"
        return Section {
            AskAIReader { ask in
                HStack(spacing: 10) {
                    Text("「\(sentence)」").font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(macOS)
                    if model.chatReady {
                        // 装了 Claude Code / Codex / Hermes：不用离开 app，放进夏夏对话栏，点发送就试。
                        Button { dismiss(); model.chat.prefill(sentence) } label: { Label("在夏夏对话栏里试", systemImage: "sparkles") }
                            .buttonStyle(.softAI)
                    } else {
                        Button { ask(sentence) } label: { Label("复制这句话", systemImage: "doc.on.doc") }
                            .buttonStyle(.softAI)
                    }
                    #else
                    Button { ask(sentence) } label: { Label("复制这句话", systemImage: "doc.on.doc") }
                        .buttonStyle(.softAI)
                    #endif
                }
            }
            tryStatus
        } header: {
            Text("③ 试一句")
        } footer: {
            footnote("用别的 AI 就把这句复制过去。AI 第一次用账本时可能会问你「允许使用夏夏账本吗」，选允许。记错了在「改动记录」里一键撤销。")
        }
    }

    @ViewBuilder private var tryStatus: some View {
        if let change = newAIChange {
            Label("连好了！\(change.author) 刚记下：\(change.summary)", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Color.income).font(.callout.weight(.semibold))
        } else if let hello = newHandshake {
            Label("\(AIApp.displayName(clientName: hello.0)) 已经连上账本，等它写进来…", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.income).font(.callout)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("等 AI 连上账本…（连上了这里会变绿）").font(.callout).foregroundStyle(Color.fg2)
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 状态

    private var newAIChange: ChangeRecord? {
        guard let last = model.lastAIChange, last.createdAt >= openedAt.addingTimeInterval(-5) else { return nil }
        return last
    }

    private var newHandshake: (String, Date)? {
        handshakes.filter { $0.value >= openedAt.addingTimeInterval(-5) }.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

        private var anyGreen: Bool { !connected.isEmpty || newHandshake != nil || newAIChange != nil }

    private func refresh() {
        guard let c = connector else { return }
        installed = Set(AIApp.allCases.filter { c.isInstalled($0) })
        connected = Set(AIApp.allCases.filter { c.isConnected($0) })
        repair = Set(AIApp.allCases.filter { c.needsRepair($0) })
        unsupported = c.unsupportedInstalled()
        if !model.usesSampleData { handshakes = AIConnections.load() }
        firstLoad = false
        model.refreshIfChanged()
    }
}

/// iPhone 设置里：AI 在 Mac 上连。
struct ConnectAIPhoneNote: View {
    var body: some View {
        Text("AI 工具在 Mac 上连：打开 Mac 上的夏夏账本，设置 →「连接你的 AI」。连好后 AI 记的账会同步到这里。")
            .font(.caption).foregroundStyle(Color.fg2)
    }
}

/// 设置页「AI 连接」：每个 AI 一个圆点和「连接」按钮（同一套 AIHealthList），再加上握过手的别的工具（比如 Cherry Studio）。
struct AIStatusRows: View {
    @Environment(LedgerModel.self) var model
    @State private var handshakes: [String: Date] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AIHealthList(showMissing: false)
            ForEach(otherClients, id: \.self) { name in
                AIHealthRowLayout(mascot: .of(author: name), level: .good, title: name,
                                  status: "连上了 · \(handshakes[name]!.friendly) 用过账本", fix: nil) { EmptyView() }
            }
        }
        .task {
            while !Task.isCancelled {
                if !model.usesSampleData { handshakes = AIConnections.load() }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var otherClients: [String] {
        handshakes.keys.filter { AIApp.from(clientName: $0) == nil && $0 != "AI" }.sorted()
    }
}

/// 每个 AI 一行：圆点（绿 = 用过账本 / 橙 = 写好了等重开 / 红 = 有问题 / 灰 = 还没连）、一句大白话、一个按钮。
/// 点「连接」由 app 自己写配置，写完马上自测一次（像 AI 那样启动记账服务读一次账本）。规则在 FinanceCore/AIHealth。
struct AIHealthList: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.openURL) var openURL
    /// 没找到的 AI 合成一行小字列出来。
    var showMissing: Bool

    @State private var installed: Set<AIApp> = []
    @State private var connected: Set<AIApp> = []
    @State private var repair: Set<AIApp> = []
    @State private var unsupported: [UnsupportedAI] = []
    @State private var handshakes: [String: Date] = [:]
    @State private var tests: [AIApp: AISelfTestResult] = [:]
    @State private var testing: Set<AIApp> = []
    @State private var errors: [AIApp: String] = [:]

    private var connector: AIConnector? { model.aiConnector }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty && unsupported.isEmpty {
                AIHealthRowLayout(mascot: nil, level: .idle, title: "这台 Mac 上没找到能连的 AI",
                                  status: "装一个 Claude 桌面版或 Codex，这里会自动认出来", fix: nil) { EmptyView() }
            }
            ForEach(shown) { app in row(app) }
            ForEach(unsupported) { u in
                AIHealthRowLayout(mascot: .star, level: .idle, title: u.name, status: "连不了电脑上的账本", fix: u.advice) {
                    Button(u.alternativeTitle) { if let url = URL(string: u.alternativeURL) { openURL(url) } }
                        .buttonStyle(.softAI)
                }
            }
            if showMissing, !missing.isEmpty, !(shown.isEmpty && unsupported.isEmpty) {
                Text("没找到：" + missing.map(\.name).joined(separator: "、"))
                    .font(.caption).foregroundStyle(Color.fg2).padding(.top, 6)
            }
        }
        .task {
            // 每 2 秒看一眼：装了哪些、写没写好、AI 有没有真的来读账本。
            var first = true
            while !Task.isCancelled {
                refresh()
                if first {
                    first = false
                    // 打开时把已经写好的都自测一遍，坏了的马上变红。
                    for app in connected where tests[app] == nil { runTest(app) }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var shown: [AIApp] { AIApp.allCases.filter { installed.contains($0) || connected.contains($0) || repair.contains($0) } }
    private var missing: [AIApp] { AIApp.allCases.filter { !shown.contains($0) } }

    private func lastSeen(_ app: AIApp) -> Date? {
        handshakes.filter { AIApp.from(clientName: $0.key) == app }.map(\.value).max()
    }

    @ViewBuilder private func row(_ app: AIApp) -> some View {
        let h = health(app)
        AIHealthRowLayout(mascot: .of(app), level: testing.contains(app) ? .waiting : h.level, title: app.name,
                          status: testing.contains(app) ? "正在测能不能读到账本…" : h.title, fix: errors[app] ?? h.fix) {
            if testing.contains(app) {
                ProgressView().controlSize(.small)
            } else if !connected.contains(app) {
                Button(repair.contains(app) ? "重新连接" : "连接") { connect(app) }
                    .buttonStyle(AISolidButtonStyle())
                    .accessibilityIdentifier("connect.\(app.cliName)")
            } else if h.level == .problem {
                Button("再连一次") { connect(app) }.buttonStyle(.softAI)
            } else if h.level == .waiting, AIRelauncher.canRelaunch(app) {
                Button("帮我重开 \(app == .claudeDesktop ? "Claude" : app.name)") { AIRelauncher.relaunch(app) }
                    .buttonStyle(.softAI)
                    .help("先退出再打开，新设置才会生效。没发完的话会留在 \(app.name) 里")
            } else if h.level == .good {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income).font(.title3)
                    .accessibilityLabel("已连上")
            }
        }
    }

    private func health(_ app: AIApp) -> AIHealth {
        guard let c = connector else { return AIHealth(level: .problem, title: "这个版本没带记账服务") }
        return c.health(app, selfTest: tests[app], lastSeen: lastSeen(app))
    }

    private func refresh() {
        guard let c = connector else { return }
        installed = Set(AIApp.allCases.filter { c.isInstalled($0) })
        let now = Set(AIApp.allCases.filter { c.isConnected($0) })
        // 别处（fin setup、AI 自己配）刚写好的，也测一次
        for app in now.subtracting(connected) where tests[app] == nil && !firstPass { runTest(app) }
        connected = now
        repair = Set(AIApp.allCases.filter { c.needsRepair($0) })
        unsupported = c.unsupportedInstalled()
        if !model.usesSampleData { handshakes = AIConnections.load() }
        firstPass = false
    }

    @State private var firstPass = true

    private func connect(_ app: AIApp) {
        guard let c = connector else { return }
        do {
            try AISetup(connector: c).connect(app)
            errors[app] = nil
        } catch {
            errors[app] = error.localizedDescription
            tests[app] = nil
            return
        }
        refresh()
        runTest(app)
    }

    /// 后台自测，不卡界面。示例数据时只看假主目录，不启动真的记账服务。
    private func runTest(_ app: AIApp) {
        guard let c = connector, !testing.contains(app) else { return }
        if model.usesSampleData {
            tests[app] = AISelfTestResult(ok: true, message: "示例数据，不测")
            return
        }
        testing.insert(app)
        Task { @MainActor in
            #if os(macOS)
            let r = await Task.detached(priority: .userInitiated) { c.selfTest(app) }.value
            #else
            let r = AISelfTestResult(ok: false, message: "AI 在 Mac 上连")
            #endif
            tests[app] = r
            testing.remove(app)
            model.toast = .init(text: r.ok ? "\(app.name) 写好了，自测能读到账本。\(app.afterConnect)就能用"
                                           : "\(app.name) 写好了，但自测没过：\(r.message)",
                                changeID: nil, isError: !r.ok)
        }
    }
}

/// 一行的样子：头像 + 右下角圆点、名字、一句状态、一句下一步，右边按钮。
struct AIHealthRowLayout<Trailing: View>: View {
    var mascot: MascotCharacter?
    var level: AIHealth.Level
    var title: String
    var status: String
    var fix: String?
    @ViewBuilder var trailing: () -> Trailing

    private var color: Color {
        switch level {
        case .good: .income
        case .waiting: .warn
        case .problem: .alert
        case .idle: .fg3
        }
    }

    private var symbol: String {
        switch level {
        case .good: "checkmark"
        case .waiting: "clock"
        case .problem: "exclamationmark"
        case .idle: "link"
        }
    }

    private var spoken: String {
        switch level {
        case .good: "已连上"
        case .waiting: "等重开"
        case .problem: "有问题"
        case .idle: "还没连"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let mascot {
                    MascotView(mascot, size: 32, face: true, animated: false)
                        .saturation(level == .good || level == .waiting ? 1 : 0.35)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Color.fg3.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol).font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 14, height: 14).background(color, in: Circle())
                    .overlay(Circle().strokeBorder(Color.pageBackground, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(status).font(.caption).foregroundStyle(level == .problem ? Color.alert : level == .good ? Color.income : Color.fg2)
                if let fix {
                    Text(fix).font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing().font(.callout)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityValue(spoken)
    }
}

#if os(macOS)
/// 写好设置后「帮我重开 Claude」：Claude 桌面版要完全退出再打开才会读新设置，新手不知道 ⌘Q。
enum AIRelauncher {
    static func running(_ app: AIApp) -> NSRunningApplication? {
        guard app == .claudeDesktop else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.anthropic.claudefordesktop" || ($0.localizedName == "Claude" && $0.bundleURL?.lastPathComponent == "Claude.app")
        }
    }

    static func canRelaunch(_ app: AIApp) -> Bool { running(app) != nil }

    static func relaunch(_ app: AIApp) {
        guard let r = running(app), let url = r.bundleURL else { return }
        r.terminate()
        Task { @MainActor in
            // 等它真的退出（最多 10 秒），再打开
            for _ in 0..<40 where !r.isTerminated { try? await Task.sleep(for: .milliseconds(250)) }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }
}
#else
enum AIRelauncher {
    static func canRelaunch(_ app: AIApp) -> Bool { false }
    static func relaunch(_ app: AIApp) {}
}
#endif
