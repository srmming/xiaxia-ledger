import FinanceCore
import SwiftUI

/// 设置（ming 2026-11-23 的稿）：上面一张「AI 连接」卡，下面一组一行一项，点进去是二级页。
/// 「夏夏的记忆」那一行的内容归「让夏夏越用越懂我的财务」线程做（XiaxiaMemorySettings.swift）。
/// 启动参数 -XiaxiaSettingsPage books|sync|xiaxia|memory|privacy|author|data|ai 直接停在某个二级页（截图检查用）。
struct SettingsPage: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.openURL) var openURL
    @AppStorage("xiaxia.appearance") var appearance = "auto"
    @AppStorage(L10n.defaultsKey) var language = L10n.fallbackChoice.rawValue
    @State private var pane: SettingsPane?
    /// 换语言时整页会按新语言重建（RootView 的 .id(language)），@State 跟着清空。
    /// 记下当时开着哪一页和当时的语言：重建后语言变了，就回到那一页，不把人踢回设置首页。
    @MainActor private static var openBeforeLanguageSwitch: (pane: SettingsPane, language: AppLanguage)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            aiCard
            VStack(spacing: 0) {
                row(.books, symbol: "building.columns", title: tr("账本与账户")) { Text(booksSummary) }
                divider
                row(.business, symbol: "storefront", title: tr("生意模式")) {
                    Text(model.businessOn ? tr("开着 · \(model.ledger.businessBook?.name ?? "")") : tr("关着"))
                }
                divider
                row(.sync, symbol: "icloud", title: tr("同步与币种")) {
                    HStack(spacing: 6) {
                        Circle().fill(model.loadError == nil ? Color.income : Color.alert).frame(width: 7, height: 7)
                        Text("\(model.loadError == nil ? tr("账本已读到") : tr("账本读不出来")) · \(Currencies.info(model.ledger.baseCurrency).name) \(Currencies.info(model.ledger.baseCurrency).symbol)")
                    }
                }
                divider
                row(.xiaxia, symbol: "slider.horizontal.3", title: tr("夏夏偏好")) { Text(xiaxiaSummary) }
                divider
                row(.memory, symbol: "brain.head.profile", title: tr("夏夏的记忆")) { Text(model.memorySummary) }
                divider
                row(.privacy, symbol: "eye", title: tr("隐私与外观")) { Text(appearanceLabel) }
                divider
                row(.author, symbol: "person", title: tr("记账人")) { Text(model.author.isEmpty ? tr("更改名称") : model.author) }
                divider
                row(.data, symbol: "externaldrive", title: tr("数据")) { Text(model.isTryingDemo ? tr("正在看演示数据") : tr("演示数据、删除数据")) }
            }
            .padding(.horizontal, 16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))

            // 帮助与反馈、版本：稿里没画，放在最下面一行小字。
            HStack(spacing: 14) {
                Button { model.sheet = .feedback } label: {  // 写好用邮件发（Feedback.swift）
                    Label(tr("反馈问题 / 提个想法"), systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.feedback")
                Spacer()
                Text(tr("版本 \(version)")).textSelection(.enabled)
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
            if pane == nil, let kept = Self.openBeforeLanguageSwitch, kept.language != L10n.choice {
                // 等新的导航栈先建好再推进去，同一拍里推会被丢掉。
                Task { @MainActor in pane = kept.pane }
            } else if pane == nil, let name = UserDefaults.standard.string(forKey: "XiaxiaSettingsPage"), let p = SettingsPane(rawValue: name) {
                pane = p
            }
        }
        .onChange(of: pane) { _, now in
            Self.openBeforeLanguageSwitch = now.map { ($0, L10n.choice) }
        }
    }

    // MARK: AI 连接

    @ViewBuilder private var aiCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("AI 连接")).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text(tr("在你常用的 AI 里记账、查账。")).font(.subheadline).foregroundStyle(Color.fg2)
                }
                Spacer(minLength: 12)
                #if os(macOS)
                Button { model.sheet = .connectAI } label: {
                    Text(tr("连接你的 AI")).font(.body.weight(.semibold)).foregroundStyle(.white)
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
                    model.toast = .init(text: tr("已复制配置指令，粘贴给你的 AI，它会自己配好"), changeID: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "link").frame(width: 22)
                        Text(tr("复制配置指令"))
                        Spacer()
                        Image(systemName: "doc.on.doc").foregroundStyle(Color.fg2)
                    }
                    .font(.callout)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("复制一段话，粘给任何 AI，它会自己把夏夏账本配好"))
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
                        StatusDot(color: .income, text: tr("\(t.last.friendly) 写过")).font(.caption).foregroundStyle(Color.fg2)
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
                Text(model.xia(title)).font(.body)
                Spacer(minLength: 12)
                value().font(.callout).foregroundStyle(Color.fg2).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.\(p.rawValue)")
    }

    private var booksSummary: String {
        let books = model.ledger.books
        let accounts = tr("\(model.ledger.accounts.count) 个账户")
        return books.count == 1 ? "\(books[0].name) · \(accounts)" : tr("\(books.count) 个账本 · \(accounts)")
    }

    private var xiaxiaSummary: String {
        #if os(macOS)
        if model.chat.available.isEmpty { return model.ledger.profile.persona.label }
        return model.chat.enabled ? tr("内置夏夏已打开") : tr("内置夏夏已关闭")
        #else
        return model.ledger.profile.persona.label
        #endif
    }

    private var appearanceLabel: String {
        switch appearance { case "light": tr("浅色"); case "dark": tr("深色"); default: tr("跟随系统") }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? tr("开发版")
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v)（\($0)）" } ?? v
    }

    private func open(_ s: String) { if let u = URL(string: s) { openURL(u) } }
}

/// 设置的二级页。
enum SettingsPane: String, Identifiable, Hashable {
    case ai, books, business, sync, xiaxia, memory, privacy, author, data
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ai: tr("管理 AI 连接")
        case .books: tr("账本与账户")
        case .business: tr("生意模式")
        case .sync: tr("同步与币种")
        case .xiaxia: tr("夏夏偏好")
        case .memory: tr("夏夏的记忆")
        case .privacy: tr("隐私与外观")
        case .author: tr("记账人")
        case .data: tr("数据")
        }
    }
}

#if os(macOS)
/// AI 连接卡里那一行：「N 个 AI 已连接」，下面一行小字写是哪几个。
struct ConnectedAISummary: View {
    @Environment(LedgerModel.self) var model
    @State private var connected: [String] = []

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.title3).foregroundStyle(connected.isEmpty ? Color.fg3 : Color.ai).frame(width: 40)
                .accessibilityHidden(true)
            Rectangle().fill(Color.fg3.opacity(0.3)).frame(width: 1, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(connected.isEmpty ? tr("还没连上 AI") : tr("\(connected.count) 个 AI 已连接")).font(.body.weight(.semibold))
                Text(connected.isEmpty ? tr("点右上角「连接你的 AI」，一步连好") : connected.joined(separator: "、"))
                    .font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(tr("管理连接")).font(.callout).foregroundStyle(Color.fg2)
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
        var list = AIApp.allCases.filter { c.isConnected($0) }.map(\.name)
        // 握手过、但不是能自动连的那几个（比如 Cherry Studio）也算上。
        if !model.usesSampleData {
            for name in AIConnections.load().keys.sorted() where AIApp.from(clientName: name) == nil && name != "AI" {
                list.append(name)
            }
        }
        connected = list
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
    @AppStorage(L10n.defaultsKey) var language = L10n.fallbackChoice.rawValue

    var body: some View {
        // 记忆页是另一个线程做的整页，自己管排版和滚动。
        if pane == .memory { XiaxiaMemorySettings() } else if pane == .data { DataSettingsPane() }
        else if pane == .business { BusinessSettingsPane() } else { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch pane {
            case .ai:
                #if os(macOS)
                group(tr("AI 连接"), note: tr("Claude、Codex 这些 AI 通过 MCP 读写同一本账。「用过账本」是 AI 最近一次打开账本的时间。")) {
                    AIStatusRows()
                    Button { model.sheet = .connectAI } label: {
                        item(symbol: "link", color: .ai, title: tr("连接你的 AI（Claude、Codex、Hermes…）")) { chevron }
                    }
                    .buttonStyle(.plain)
                }
                #else
                ConnectAIPhoneNote()
                #endif
            case .books:
                group(tr("账本")) {
                    ForEach(model.ledger.books) { b in
                        let n = model.ledger.bookUsage(b.id).transactions
                        item(monogram: Monogram(text: b.name, color: model.bookColor(b.id), size: 26), title: b.name) {
                            Text(tr("\(n) 笔流水")).foregroundStyle(Color.fg2)
                        }
                    }
                }
                group(tr("管理")) {
                    manageRow("books.vertical", tr("管理账本（新建、改名、删除）"), .books)
                    manageRow("building.columns", tr("管理账户（\(model.ledger.accounts.count) 个）"), .accounts)
                    manageRow("square.grid.2x2", tr("管理分类"), .categories)
                }
            case .sync:
                group(tr("同步")) {
                    item(symbol: "icloud.fill", color: Color.kit(0x0A84FF, 0x409CFF), title: tr("状态")) {
                        StatusDot(color: model.loadError == nil ? .income : .alert, text: model.loadError == nil ? tr("账本已读到") : tr("读不出来"))
                            .foregroundStyle(Color.fg2)
                    }
                    item(symbol: "doc.fill", color: .fg3, title: tr("账本文件")) {
                        // 路径很长：从中间省略，留住开头和「夏夏账本/ledger.sqlite」结尾；鼠标停上去看完整路径。
                        Text(ledgerLocation(model.store)).font(.caption).foregroundStyle(Color.fg2).lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.trailing).textSelection(.enabled)
                            .help(ledgerLocation(model.store))
                    }
                    #if os(iOS)
                    // 手机和电脑看同一本账：选 iCloud 云盘里的「夏夏账本」文件夹（ming 2026-11-23「记得支持 iCloud」）。
                    NavigationLink { PhoneSyncSettings() } label: {
                        item(symbol: "laptopcomputer.and.iphone", color: Color.kit(0x0A84FF, 0x409CFF), title: tr("和电脑同步")) {
                            Text(model.isPhoneLinked ? tr("已接上") : tr("没接上")).foregroundStyle(Color.fg2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.phoneSync")
                    #endif
                }
                #if os(macOS)
                if AppUpdateSupport.isAvailable || AppUpdateSupport.preview {
                    group(tr("更新"), note: tr("更新只换 app 本身，账本不动；换之前还会把账本复制一份到账本旁边的「更新前备份」文件夹。")) {
                        AppUpdateRows()
                    }
                }
                #endif
                group(tr("币种"), note: tr("每个账户可以有自己的币种。外币的每一笔记原来的金额和当天汇率，看板上的总数换成主币种；银行实际扣了多少，就以银行为准。取汇率只下载欧洲央行的公开汇率表，不会发出任何账目。")) {
                    CurrencySettingsRows()
                }
            case .xiaxia:
                #if os(macOS)
                group(tr("内置夏夏"), note: tr("打开后窗口右边有个聊天栏，借你电脑上的 AI 回答；关掉后「问夏夏」会把提示词复制好，交给你自己的 AI。")) {
                    item(symbol: "bubble.left.and.text.bubble.right.fill", color: .ai,
                         title: model.chat.available.isEmpty ? tr("内置夏夏（要先装 Claude Code、Codex 或 Hermes）") : tr("内置夏夏")) {
                        Toggle(tr("内置夏夏"), isOn: Binding(get: { model.chat.enabled }, set: { on in
                            withAnimation(.snappy) { model.chat.enabled = on }
                            if on { model.chat.show() }
                        }))
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(model.chat.available.isEmpty)
                        .accessibilityIdentifier("settings.chatEnabled")
                    }
                    if model.chat.available.count > 1 {
                        item(symbol: "cpu", color: .ai, title: tr("用哪个 AI 回答")) {
                            Picker(tr("用哪个 AI 回答"), selection: Binding(get: { model.chat.engine?.rawValue ?? "" },
                                                                    set: { model.chat.engine = ChatEngine(rawValue: $0) })) {
                                ForEach(model.chat.available) { e in Text(e.name).tag(e.rawValue) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                }
                #endif
                group(tr("名字和称呼"), note: tr("助手在 app 里和 AI 回答里都用这个名字自称、这样叫你。跟着账本同步。")) {
                    NameSettingsRows()
                }
                group(tr("夏夏怎么跟你说话"), note: tr("夏夏在每页说的话、复制给 AI 的话、AI 写回来的意见，都按这个口吻。跟着账本同步。")) {
                    CharacterToggle().padding(.bottom, 6)
                    AILayerToggle().padding(.bottom, 6)
                    PersonaPicker()
                }
            case .memory, .data, .business:
                EmptyView()
            case .privacy:
                group(tr("隐私")) {
                    item(symbol: "eye.slash.fill", color: .fg3, title: tr("显示私房钱")) {
                        Toggle(tr("显示私房钱"), isOn: Bindable(model).showPrivate).labelsHidden().toggleStyle(.switch)
                    }
                }
                group(tr("外观")) {
                    item(symbol: "circle.lefthalf.filled", color: .fg3, title: tr("外观")) {
                        Picker(tr("外观"), selection: $appearance) {
                            Text(tr("跟随系统")).tag("auto"); Text(tr("浅色")).tag("light"); Text(tr("深色")).tag("dark")
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
                // 多语言（ming 2026-11-23）：中文、英文、西班牙语。换了马上生效，不用重开。
                group(tr("语言"), note: tr("英文和西班牙语还在翻译，没翻到的地方先显示中文。")) {
                    item(symbol: "globe", color: .fg3, title: tr("界面语言")) {
                        Picker(tr("界面语言"), selection: $language) {
                            ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0.rawValue) }
                        }
                        .labelsHidden().fixedSize()
                        .accessibilityIdentifier("settings.language")
                    }
                }
            case .author:
                group(tr("记账的人"), note: tr("你在 app 里记的、改的，改动记录里都记在这个名字下，流水上标「你」。")) {
                    item(symbol: "person.fill", color: .brand, title: tr("名字")) {
                        TextField(tr("你的名字"), text: $name)
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

/// 设置 → 夏夏偏好 →「名字和称呼」：改助手的名字、它怎么叫你。回车或离开输入框就存（进改动记录，能撤销）。
struct NameSettingsRows: View {
    @Environment(LedgerModel.self) var model
    @State private var name = ""
    @State private var call = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            row(tr("名字"), placeholder: Profile.defaultAssistantName, text: $name, id: "settings.assistantName")
            Divider()
            row(tr("怎么叫你"), placeholder: tr("不填就叫「你」"), text: $call, id: "settings.callUser")
        }
        .onAppear { load() }
        .onChange(of: focused) { _, f in if !f { save() } }
        .onDisappear { save() }
    }

    private func row(_ title: String, placeholder: String, text: Binding<String>, id: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.callout)
            Spacer(minLength: 12)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 220)
                .focused($focused)
                .onSubmit { save() }
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
        }
        .padding(.vertical, 9)
    }

    private func load() {
        name = model.ledger.profile.assistantName ?? ""
        call = model.ledger.profile.userCallName ?? ""
    }

    private func save() {
        let p = model.ledger.profile
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n == Profile.defaultAssistantName { n = "" }
        let c = call.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (n.isEmpty ? nil : n) != p.assistantName || (c.isEmpty ? nil : c) != p.userCallName else { return }
        model.perform { try $0.setNames(assistant: n, callUser: c, author: model.author) }
        load()
    }
}
