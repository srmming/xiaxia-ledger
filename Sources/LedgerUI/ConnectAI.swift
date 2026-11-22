import FinanceCore
import SwiftUI

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
        guard let fin = BundledFin.path ?? (usesSampleData ? "/Applications/夏夏账本.app/Contents/MacOS/fin" : nil) else { return nil }
        guard usesSampleData else { return AIConnector(fin: fin) }
        let noTools = ProcessInfo.processInfo.arguments.contains("-XiaxiaNoTools")
        let fake = FileManager.default.temporaryDirectory.appendingPathComponent(noTools ? "xiaxia-sample-home-empty" : "xiaxia-sample-home")
        if !noTools {
            // 演示时假装装了 Claude 桌面版和 Codex
            for dir in ["Library/Application Support/Claude", ".codex"] {
                try? FileManager.default.createDirectory(at: fake.appendingPathComponent(dir), withIntermediateDirectories: true)
            }
        }
        return AIConnector(home: fake, fin: fin, appFolders: [fake.appendingPathComponent("Applications")])
    }

    /// 「复制一段话给 AI，让它自己配好」。
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
        for app in AIApp.allCases where c.needsRepair(app) { try? c.connect(app) }
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
    @State private var picked: Set<AIApp> = []
    @State private var results: [AIApp: String] = [:]
    @State private var errors: [AIApp: String] = [:]
    @State private var handshakes: [String: Date] = [:]
    @State private var firstLoad = true

    private var connector: AIConnector? { model.aiConnector }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 30, weight: .semibold)).foregroundStyle(Color.ai)
                        .accessibilityHidden(true)
                    Text("连上你的 AI").font(.title2.weight(.bold))
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
                toolsSection
                selfSetupSection
                otherSection
                trySection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("连上你的 AI")
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

    // MARK: ① 选要连的 AI

    private var toolsSection: some View {
        Section {
            ForEach(AIApp.allCases) { app in toolRow(app) }
            if !results.isEmpty || !errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(AIApp.allCases.filter { results[$0] != nil }) { app in
                        Label("\(app.name) 写好了：\(results[app]!)才会用上", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.income)
                    }
                    ForEach(AIApp.allCases.filter { errors[$0] != nil }) { app in
                        Label("\(app.name)：\(errors[app]!)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.alert)
                    }
                }
                .font(.callout)
            }
            if !installed.isEmpty || !repair.isEmpty {
            HStack {
                Spacer()
                Button(action: connectPicked) {
                    Label(picked.isEmpty ? "连上" : "连上选中的 \(picked.count) 个", systemImage: "link")
                }
                .buttonStyle(AISolidButtonStyle())
                .disabled(picked.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            }
        } header: {
            Text("① 选要连的 AI")
        } footer: {
            footnote("点「连上」会在这些工具的设置里加上「夏夏账本」这一项，别的设置不动；改之前留一份备份（.bak-xiaxia）。")
        }
    }

    private func toolRow(_ app: AIApp) -> some View {
        let isOn = Binding(get: { picked.contains(app) }, set: { on in if on { picked.insert(app) } else { picked.remove(app) } })
        return HStack(spacing: 12) {
            Image(systemName: symbol(app)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(installed.contains(app) ? Color.ai : Color.fg3.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body.weight(.medium))
                Text(status(app)).font(.caption).foregroundStyle(connected.contains(app) ? Color.income : Color.fg2)
            }
            Spacer(minLength: 8)
            if connected.contains(app) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income).font(.title3)
                    .accessibilityLabel("已连上")
            } else if installed.contains(app) || repair.contains(app) {
                Toggle("连 \(app.name)", isOn: isOn).labelsHidden().toggleStyle(.switch)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func status(_ app: AIApp) -> String {
        if connected.contains(app) {
            if let seen = lastHandshake(app) { return "已连上 · \(seen.friendly) 用过账本" }
            return results[app] != nil ? "已连上 · \(app.afterConnect)" : "已连上"
        }
        if repair.contains(app) { return "以前连过，但夏夏账本换了位置，要重新连" }
        return installed.contains(app) ? "这台 Mac 上有" : "这台 Mac 上没找到"
    }

    private func symbol(_ app: AIApp) -> String {
        switch app {
        case .claudeDesktop: "bubble.left.and.text.bubble.right.fill"
        case .claudeCode, .codex, .gemini: "terminal.fill"
        case .cursor: "chevron.left.forwardslash.chevron.right"
        }
    }

    // MARK: 或者让 AI 自己配

    private var selfSetupSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("复制一段话发给你的 AI，它会自己把夏夏账本配好").font(.body)
                    Text("适合 Claude Code、Codex 这类能在电脑上执行命令的 AI，也适合上面没列出来的工具：AI 会告诉你粘到哪儿。")
                        .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    Clipboard.copy(model.aiSetupPrompt)
                    model.toast = .init(text: "已复制，粘贴给你的 AI 就行", changeID: nil)
                } label: { Label("复制这段话", systemImage: "doc.on.doc") }
                    .buttonStyle(.softAI)
            }
        } header: {
            Text("或者：让 AI 自己配")
        }
    }

    // MARK: ② 没装 / 用别的

    private var otherSection: some View {
        Section {
            if installed.isEmpty && connected.isEmpty {
                Text("这台 Mac 上还没有能连的 AI 工具。挑一个装上，回来点「连上」就行：")
                    .font(.callout)
            }
            linkRow("下载 Claude 桌面版", note: "最省事，装好登录就能用", url: "https://claude.ai/download", symbol: "arrow.down.circle.fill")
            linkRow("用 DeepSeek、通义千问、Kimi？装 Cherry Studio", note: "在它的「MCP 服务器」设置里粘贴下面复制的配置",
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
            Text("② 没有这些 AI，或者用别的")
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
                    Button { ask(sentence) } label: { Label("复制并打开 Claude", systemImage: "sparkles") }
                        .buttonStyle(.softAI)
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

    private func lastHandshake(_ app: AIApp) -> Date? {
        handshakes.filter { AIApp.from(clientName: $0.key) == app }.map(\.value).max()
    }

    private var anyGreen: Bool { !connected.isEmpty || newHandshake != nil || newAIChange != nil }

    private func refresh() {
        guard let c = connector else { return }
        installed = Set(AIApp.allCases.filter { c.isInstalled($0) })
        connected = Set(AIApp.allCases.filter { c.isConnected($0) })
        repair = Set(AIApp.allCases.filter { c.needsRepair($0) })
        if !model.usesSampleData { handshakes = AIConnections.load() }
        if firstLoad {
            // 默认勾上装了但还没连的
            picked = installed.union(repair).subtracting(connected)
            firstLoad = false
        } else {
            picked.subtract(connected)
        }
        model.refreshIfChanged()
    }

    private func connectPicked() {
        guard let c = connector else { return }
        for app in AIApp.allCases where picked.contains(app) {
            do {
                try c.connect(app)
                results[app] = app.afterConnect
                errors[app] = nil
            } catch {
                errors[app] = error.localizedDescription
                results[app] = nil
            }
        }
        picked.removeAll()
        refresh()
        if !results.isEmpty { model.toast = .init(text: "写好了，重开一次 AI 工具就能用", changeID: nil) }
    }
}

/// iPhone 设置里：AI 在 Mac 上连。
struct ConnectAIPhoneNote: View {
    var body: some View {
        Text("AI 工具在 Mac 上连：打开 Mac 上的夏夏账本，设置 →「连上你的 AI」。连好后 AI 记的账会同步到这里。")
            .font(.caption).foregroundStyle(Color.fg2)
    }
}

/// 设置页「AI 连接（MCP）」：每个 AI 工具连没连、最近一次用账本是什么时候；没连的一键连上。
struct AIStatusRows: View {
    @Environment(LedgerModel.self) var model
    @State private var rows: [(app: AIApp, installed: Bool, connected: Bool, repair: Bool)] = []
    @State private var handshakes: [String: Date] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let shown = rows.filter { $0.installed || $0.connected || $0.repair }
            if shown.isEmpty {
                line(symbol: "sparkles", color: .fg3, title: "这台 Mac 上没找到能自动连的 AI 工具", detail: "点下面「连上你的 AI」看看别的办法") { EmptyView() }
            }
            ForEach(shown, id: \.app) { r in
                line(symbol: r.connected ? "checkmark" : "link", color: r.connected ? .income : .fg3, title: r.app.name, detail: detail(r),
                     mascot: .of(r.app)) {
                    if !r.connected {
                        Button(r.repair ? "重新连" : "连上") { connect(r.app) }.buttonStyle(.softAI)
                    }
                }
            }
            // 握手过、但不是上面能自动连的工具（比如 Cherry Studio）
            ForEach(otherClients, id: \.self) { name in
                line(symbol: "checkmark", color: .income, title: name, detail: "已连上 · \(handshakes[name]!.friendly) 用过账本",
                     mascot: .of(author: name)) { EmptyView() }
            }
        }
        .task {
            while !Task.isCancelled { refresh(); try? await Task.sleep(for: .seconds(3)) }
        }
    }

    private var otherClients: [String] {
        handshakes.keys.filter { AIApp.from(clientName: $0) == nil && $0 != "AI" }.sorted()
    }

    private func detail(_ r: (app: AIApp, installed: Bool, connected: Bool, repair: Bool)) -> String {
        let seen = handshakes.filter { AIApp.from(clientName: $0.key) == r.app }.map(\.value).max()
        if r.connected { return seen.map { "已连上 · \($0.friendly) 用过账本" } ?? "已连上 · 还没用过（\(r.app.afterConnect)）" }
        if r.repair { return "以前连过，夏夏账本换了位置，要重新连" }
        return "装了，还没连"
    }

    private func line<Trailing: View>(symbol: String, color: Color, title: String, detail: String, mascot: MascotCharacter? = nil,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            if let mascot {
                // 每个 AI 工具一个小伙伴头像，右下角小圆点表示连没连
                MascotView(mascot, size: 32, face: true, animated: false)
                    .saturation(color == .income ? 1 : 0.35)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: symbol).font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 14, height: 14).background(color, in: Circle())
                            .overlay(Circle().strokeBorder(Color.pageBackground, lineWidth: 1.5))
                            .offset(x: 3, y: 3)
                    }
                    .accessibilityHidden(true)
            } else {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(detail).font(.caption).foregroundStyle(Color.fg2)
            }
            Spacer(minLength: 8)
            trailing().font(.callout)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func refresh() {
        guard let c = model.aiConnector else { return }
        rows = AIApp.allCases.map { ($0, c.isInstalled($0), c.isConnected($0), c.needsRepair($0)) }
        if !model.usesSampleData { handshakes = AIConnections.load() }
    }

    private func connect(_ app: AIApp) {
        guard let c = model.aiConnector else { return }
        do {
            try c.connect(app)
            model.toast = .init(text: "已连上 \(app.name)，\(app.afterConnect)就能用", changeID: nil)
        } catch {
            model.toast = .init(text: error.localizedDescription, changeID: nil, isError: true)
        }
        refresh()
    }
}
