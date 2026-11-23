import FinanceCore
import SwiftUI

/// 设置（ming 2026-11-23 的稿）：上面一张「AI 连接」卡，下面一组一行一项，点进去是二级页。
/// 「夏夏的记忆」那一行的内容归「让夏夏越用越懂我的财务」线程做（XiaxiaMemorySettings.swift）。
/// 启动参数 -XiaxiaSettingsPage books|sync|xiaxia|memory|privacy|author|ai 直接停在某个二级页（截图检查用）。
struct SettingsPage: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.openURL) var openURL
    @AppStorage("xiaxia.appearance") var appearance = "auto"
    @State private var pane: SettingsPane?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            aiCard
            VStack(spacing: 0) {
                row(.books, symbol: "building.columns", title: "账本与账户") { Text(booksSummary) }
                divider
                row(.sync, symbol: "icloud", title: "同步与币种") {
                    HStack(spacing: 6) {
                        Circle().fill(model.loadError == nil ? Color.income : Color.alert).frame(width: 7, height: 7)
                        Text("\(model.loadError == nil ? "账本已读到" : "账本读不出来") · \(Currencies.info(model.ledger.baseCurrency).name) \(Currencies.info(model.ledger.baseCurrency).symbol)")
                    }
                }
                divider
                row(.xiaxia, symbol: "slider.horizontal.3", title: "夏夏偏好") { Text(xiaxiaSummary) }
                divider
                row(.memory, symbol: "brain.head.profile", title: "夏夏的记忆") { Text(model.memorySummary) }
                divider
                row(.privacy, symbol: "eye", title: "隐私与外观") { Text(appearanceLabel) }
                divider
                row(.author, symbol: "person", title: "记账人") { Text(model.author.isEmpty ? "更改名称" : model.author) }
            }
            .padding(.horizontal, 16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))

            // 帮助与反馈、版本：稿里没画，放在最下面一行小字。
            HStack(spacing: 14) {
                Button { open("https://github.com/srmming/xiaxia-ledger/issues/new") } label: {
                    Label("反馈问题 / 提个想法", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.feedback")
                Spacer()
                Text("版本 \(version)").textSelection(.enabled)
            }
            .font(.caption).foregroundStyle(Color.fg2)
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .kitPage()
        .navigationDestination(item: $pane) { p in
            SettingsPaneView(pane: p)
                .navigationTitle(p.title)
        }
        .onAppear {
            if pane == nil, let name = UserDefaults.standard.string(forKey: "XiaxiaSettingsPage"), let p = SettingsPane(rawValue: name) {
                pane = p
            }
        }
    }

    // MARK: AI 连接

    @ViewBuilder private var aiCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 连接").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text("在你常用的 AI 里记账、查账。").font(.subheadline).foregroundStyle(Color.fg2)
                }
                Spacer(minLength: 12)
                #if os(macOS)
                Button { model.sheet = .connectAI } label: {
                    Text("连接你的 AI").font(.body.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Color.brand, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("settings.connectAI")
                #endif
            }
            #if os(macOS)
            VStack(spacing: 0) {
                Button { pane = .ai } label: { ConnectedAISummary() }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.manageAI")
                Divider()
                Button {
                    Clipboard.copy(model.aiSetupPrompt)
                    model.toast = .init(text: "已复制配置指令，粘贴给你的 AI，它会自己配好", changeID: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "link").frame(width: 22)
                        Text("复制配置指令")
                        Spacer()
                        Image(systemName: "doc.on.doc").foregroundStyle(Color.fg2)
                    }
                    .font(.callout)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("复制一段话，粘给任何 AI，它会自己把夏夏账本配好")
                .accessibilityIdentifier("settings.copySetup")
            }
            .padding(.horizontal, 16)
            .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            #else
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.aiTools) { t in
                    HStack(spacing: 10) {
                        Monogram.author(t.name, isMe: false, size: 26)
                        Text(t.name).font(.callout)
                        Spacer()
                        StatusDot(color: .income, text: "\(t.last.friendly) 写过").font(.caption).foregroundStyle(Color.fg2)
                    }
                }
                ConnectAIPhoneNote()
            }
            #endif
        }
        .kitCard()
    }

    // MARK: 一行

    private var divider: some View { Divider().padding(.leading, 40) }

    private func row<Value: View>(_ p: SettingsPane, symbol: String, title: String, @ViewBuilder value: () -> Value) -> some View {
        Button { pane = p } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17)).frame(width: 26)
                Text(title).font(.body)
                Spacer(minLength: 12)
                value().font(.callout).foregroundStyle(Color.fg2).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.\(p.rawValue)")
    }

    private var booksSummary: String {
        let books = model.ledger.books
        let accounts = "\(model.ledger.accounts.count) 个账户"
        return books.count == 1 ? "\(books[0].name) · \(accounts)" : "\(books.count) 个账本 · \(accounts)"
    }

    private var xiaxiaSummary: String {
        #if os(macOS)
        if model.chat.available.isEmpty { return model.ledger.profile.persona.label }
        return model.chat.enabled ? "内置夏夏已打开" : "内置夏夏已关闭"
        #else
        return model.ledger.profile.persona.label
        #endif
    }

    private var appearanceLabel: String {
        switch appearance { case "light": "浅色"; case "dark": "深色"; default: "跟随系统" }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v)（\($0)）" } ?? v
    }

    private func open(_ s: String) { if let u = URL(string: s) { openURL(u) } }
}

/// 设置的二级页。
enum SettingsPane: String, Identifiable, Hashable {
    case ai, books, sync, xiaxia, memory, privacy, author
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ai: "管理 AI 连接"
        case .books: "账本与账户"
        case .sync: "同步与币种"
        case .xiaxia: "夏夏偏好"
        case .memory: "夏夏的记忆"
        case .privacy: "隐私与外观"
        case .author: "记账人"
        }
    }
}

#if os(macOS)
/// AI 连接卡里那一行：连上的 AI 头像叠成一排，「N 个 AI 已连接」，下面一行小字写是哪几个。
struct ConnectedAISummary: View {
    @Environment(LedgerModel.self) var model
    @State private var connected: [(name: String, mascot: MascotCharacter)] = []

    var body: some View {
        HStack(spacing: 14) {
            if connected.isEmpty {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(Color.fg3).frame(width: 40)
            } else {
                HStack(spacing: -10) {
                    ForEach(Array(connected.prefix(5).enumerated()), id: \.offset) { _, c in
                        MascotView(c.mascot, size: 34, face: true, animated: false)
                            .overlay(Circle().strokeBorder(Color.cardBackground, lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
            }
            Rectangle().fill(Color.fg3.opacity(0.3)).frame(width: 1, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(connected.isEmpty ? "还没连上 AI" : "\(connected.count) 个 AI 已连接").font(.body.weight(.semibold))
                Text(connected.isEmpty ? "点右上角「连接你的 AI」，一步连好" : connected.map(\.name).joined(separator: "、"))
                    .font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("管理连接").font(.callout).foregroundStyle(Color.fg2)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .task {
            while !Task.isCancelled { refresh(); try? await Task.sleep(for: .seconds(3)) }
        }
    }

    private func refresh() {
        guard let c = model.aiConnector else { return }
        var list: [(String, MascotCharacter)] = AIApp.allCases.filter { c.isConnected($0) }.map { ($0.name, MascotCharacter.of($0)) }
        // 握手过、但不是能自动连的那几个（比如 Cherry Studio）也算上。
        if !model.usesSampleData {
            for name in AIConnections.load().keys.sorted() where AIApp.from(clientName: name) == nil && name != "AI" {
                list.append((name, MascotCharacter.of(author: name)))
            }
        }
        connected = list.map { (name: $0.0, mascot: $0.1) }
    }
}
#endif

/// 二级页的内容：大多是原来设置页里的那几组，挪进来。
struct SettingsPaneView: View {
    @Environment(LedgerModel.self) var model
    let pane: SettingsPane
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var manage: AppSheet?
    @AppStorage("xiaxia.appearance") var appearance = "auto"

    var body: some View {
        // 记忆页是另一个线程做的整页，自己管排版和滚动。
        if pane == .memory { XiaxiaMemorySettings() } else { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch pane {
            case .ai:
                #if os(macOS)
                group("AI 连接", note: "Claude、Codex 这些 AI 通过 MCP 读写同一本账。「用过账本」是 AI 最近一次打开账本的时间。") {
                    AIStatusRows()
                    Button { model.sheet = .connectAI } label: {
                        item(symbol: "link", color: .ai, title: "连上你的 AI（Claude、Codex、Hermes…）") { chevron }
                    }
                    .buttonStyle(.plain)
                }
                #else
                ConnectAIPhoneNote()
                #endif
            case .books:
                group("账本") {
                    ForEach(model.ledger.books) { b in
                        let n = model.ledger.bookUsage(b.id).transactions
                        item(monogram: Monogram(text: b.name, color: model.bookColor(b.id), size: 26), title: b.name) {
                            Text("\(n) 笔流水").foregroundStyle(Color.fg2)
                        }
                    }
                }
                group("管理") {
                    manageRow("books.vertical", "管理账本（新建、改名、删除）", .books)
                    manageRow("building.columns", "管理账户（\(model.ledger.accounts.count) 个）", .accounts)
                    manageRow("square.grid.2x2", "管理分类", .categories)
                }
            case .sync:
                group("同步") {
                    item(symbol: "icloud.fill", color: Color.kit(0x0A84FF, 0x409CFF), title: "状态") {
                        StatusDot(color: model.loadError == nil ? .income : .alert, text: model.loadError == nil ? "账本已读到" : "读不出来")
                            .foregroundStyle(Color.fg2)
                    }
                    item(symbol: "doc.fill", color: .fg3, title: "账本文件") {
                        // 路径很长：从中间省略，留住开头和「夏夏账本/ledger.sqlite」结尾；鼠标停上去看完整路径。
                        Text(ledgerLocation(model.store)).font(.caption).foregroundStyle(Color.fg2).lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.trailing).textSelection(.enabled)
                            .help(ledgerLocation(model.store))
                    }
                }
                #if os(macOS)
                if AppUpdateSupport.isAvailable {
                    group("更新", note: "更新只换 app 本身，账本不动；换之前还会把账本复制一份到账本旁边的「更新前备份」文件夹。") {
                        AppUpdateRows()
                    }
                }
                #endif
                group("币种", note: "每个账户可以有自己的币种。外币的每一笔记原来的金额和当天汇率，看板上的总数换成主币种；银行实际扣了多少，就以银行为准。取汇率只下载欧洲央行的公开汇率表，不会发出任何账目。") {
                    CurrencySettingsRows()
                }
            case .xiaxia:
                #if os(macOS)
                group("内置夏夏", note: "打开后窗口右边有个聊天栏，借你电脑上的 AI 回答；关掉后「问夏夏」会把提示词复制好，交给你自己的 AI。") {
                    item(symbol: "bubble.left.and.text.bubble.right.fill", color: .ai,
                         title: model.chat.available.isEmpty ? "内置夏夏（要先装 Claude Code、Codex 或 Hermes）" : "内置夏夏") {
                        Toggle("内置夏夏", isOn: Binding(get: { model.chat.enabled }, set: { on in
                            withAnimation(.snappy) { model.chat.enabled = on }
                            if on { model.chat.show() }
                        }))
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(model.chat.available.isEmpty)
                        .accessibilityIdentifier("settings.chatEnabled")
                    }
                    if model.chat.available.count > 1 {
                        item(symbol: "cpu", color: .ai, title: "用哪个 AI 回答") {
                            Picker("用哪个 AI 回答", selection: Binding(get: { model.chat.engine?.rawValue ?? "" },
                                                                    set: { model.chat.engine = ChatEngine(rawValue: $0) })) {
                                ForEach(model.chat.available) { e in Text(e.name).tag(e.rawValue) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                }
                #endif
                group("夏夏怎么跟你说话", note: "夏夏在每页说的话、复制给 AI 的话、AI 写回来的意见，都按这个口吻。跟着账本同步。") {
                    PersonaPicker()
                }
            case .memory:
                EmptyView()
            case .privacy:
                group("隐私") {
                    item(symbol: "eye.slash.fill", color: .fg3, title: "显示私房钱") {
                        Toggle("显示私房钱", isOn: Bindable(model).showPrivate).labelsHidden().toggleStyle(.switch)
                    }
                }
                group("外观") {
                    item(symbol: "circle.lefthalf.filled", color: .fg3, title: "外观") {
                        Picker("外观", selection: $appearance) {
                            Text("跟随系统").tag("auto"); Text("浅色").tag("light"); Text("深色").tag("dark")
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
            case .author:
                group("记账的人", note: "你在 app 里记的、改的，改动记录里都记在这个名字下，流水上标「你」。") {
                    item(symbol: "person.fill", color: .brand, title: "名字") {
                        TextField("你的名字", text: $name)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .frame(maxWidth: 200)
                            .focused($nameFocused)
                            .onSubmit { saveName(); nameFocused = false }
                            .accessibilityIdentifier("settings.authorName")
                    }
                }
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
        .kitPage()
        .sheet(item: $manage) { sheet in
            NavigationStack {
                switch sheet {
                case .books: BookManager()
                case .accounts: AccountManager()
                default: CategoryManager()
                }
            }
            .environment(model)
            .tint(Color.brand)
            #if os(macOS)
            .frame(width: 520, height: 580)
            #endif
        }
        .onAppear { name = model.author }
        .onDisappear { saveName() }
    }

    private var chevron: some View { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.fg3) }

    private func saveName() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty, n != model.author { model.author = n }
    }

    private func manageRow(_ symbol: String, _ title: String, _ sheet: AppSheet) -> some View {
        Button { manage = sheet } label: { item(symbol: symbol, color: .brand, title: title) { chevron } }
            .buttonStyle(.plain)
    }

    private func group<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.fg2).padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
            if let note { Text(note).font(.caption).foregroundStyle(Color.fg2).padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func item<Trailing: View>(symbol: String, color: Color, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        item(monogram: nil, symbol: symbol, color: color, title: title, trailing: trailing)
    }

    private func item<Trailing: View>(monogram: Monogram?, symbol: String = "", color: Color = .fg3, title: String,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            if let monogram { monogram } else {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Text(title).font(.callout)
            Spacer(minLength: 12)
            trailing().font(.callout)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
