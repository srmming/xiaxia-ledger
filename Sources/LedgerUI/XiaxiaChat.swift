#if os(macOS)
import FinanceCore
import AppKit
import SwiftUI

/// app 右边的「夏夏」对话栏：不用切窗口，说一句就查账、记账。回答来自这台 Mac 上已登录的 Claude Code / Codex / Hermes。
@MainActor @Observable
public final class XiaxiaChatState {
    public struct Message: Identifiable, Equatable {
        public let id = UUID()
        public var fromUser: Bool
        public var text: String
        public var isError = false
        public var engine: String?
    }

    public var open = false
    /// 用不用内置夏夏（引导最后一步、设置里的开关）。关掉：右边不出对话栏，「问夏夏」改成复制好问题、打开 Claude。
    /// 没选过算开着（旧用户照旧能用）。
    public var enabled: Bool = UserDefaults.standard.object(forKey: XiaxiaChatState.enabledKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled { open = false }
        }
    }
    public static let enabledKey = "xiaxia.chatEnabled"
    /// 明确选过「用」：一打开 app 就展开。
    static var chosenOn: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool == true }
    public var messages: [Message] = []
    public var busy = false
    public var draft = ""
    /// 用哪个 AI。记住上次选的；没选过就用装了的第一个（Claude Code 最快）。
    public var engine: ChatEngine? {
        didSet {
            UserDefaults.standard.set(engine?.rawValue, forKey: "xiaxia.chatEngine")
            if engine != oldValue { model = engine.flatMap { Self.savedModel(for: $0) } }
        }
    }
    /// 用哪个模型：nil = 跟随这个 AI 自己的默认（用户在 Claude Code / Codex 里设的）。每个 AI 各记各的。
    public var model: String? {
        didSet { if let engine { UserDefaults.standard.set(model ?? "", forKey: "xiaxia.chatModel.\(engine.rawValue)") } }
    }

    static func savedModel(for engine: ChatEngine) -> String? {
        guard let m = UserDefaults.standard.string(forKey: "xiaxia.chatModel.\(engine.rawValue)"), !m.isEmpty else { return nil }
        // 以前选过、现在已经不在列表里的（比如 Codex 设置里删掉了），回到跟随默认。
        return engine.models().contains { $0.id == m } ? m : nil
    }

    /// 菜单里的一项：「claude|」= Claude Code 跟随默认，「claude|sonnet」= Claude Code 用 Sonnet。
    var choiceKey: String { "\(engine?.rawValue ?? "")|\(model ?? "")" }

    func choose(_ key: String) {
        let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let e = ChatEngine(rawValue: parts[0]) else { return }
        let m = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        guard e != engine || m != model else { return }
        let engineChanged = e != engine
        engine = e
        model = m
        // 换了 AI 要重开对话（各家的对话接不上）；只换模型就接着聊。
        if engineChanged { newConversation() } else { session = nil }
    }

    /// 顶上显示的名字：「Claude Code」或「Claude Code · Sonnet」。
    var label: String {
        guard let engine else { return "选 AI" }
        guard let model else { return engine.name }
        return "\(engine.name) · \(engine.models().first { $0.id == model }?.name ?? model)"
    }
    public private(set) var available: [ChatEngine] = []
    @ObservationIgnored var session: String?

    public init() { refreshEngines() }

    public func refreshEngines() {
        let found = ChatEngine.available()
        if found != available { available = found }
        let saved = UserDefaults.standard.string(forKey: "xiaxia.chatEngine").flatMap(ChatEngine.init(rawValue:))
        let pick = saved.flatMap { found.contains($0) ? $0 : nil } ?? found.first
        if pick != engine { engine = pick }  // 没变就不赋值，免得界面白白重画
        if let e = engine, model == nil, let m = Self.savedModel(for: e) { model = m }
    }

    /// 右键一笔「问夏夏这一笔」：打开对话栏，把这一笔写进输入框开头，光标停在后面等用户接着问。
    @ObservationIgnored var focusRequest: (() -> Void)?
    func ask(about tx: Transaction, model: LedgerModel) {
        model.selectedTransactionID = tx.id
        draft = "这一笔：\(tx.date.month) 月 \(tx.date.day) 日「\(Merchant.display(tx.description))」\(tx.amount.formatted)，"
        show()
    }

    /// 把一句话放进输入框（来自页面上的例句、「问 AI」按钮），打开对话栏等用户改完再发。
    func prefill(_ text: String) {
        if !text.isEmpty { draft = text }
        show()
    }

    /// 所有打开对话栏的地方都走这里：先把主窗口叫到前面，下一轮再展开对话栏，最后把光标放进输入框。
    func show() {
        guard !open else { focusRequest?(); return }
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.async {
            withAnimation(.snappy) { self.open = true }
            DispatchQueue.main.async { self.focusRequest?() }
        }
    }

    public func newConversation() {
        messages = []
        session = nil
    }

    func send(_ text: String, model: LedgerModel) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy, let engine else { return }
        let history = messages.filter { !$0.isError }.map { (user: $0.fromUser, text: $0.text) }
        messages.append(Message(fromUser: true, text: question))
        draft = ""
        busy = true
        let prompt = ChatRunner.prompt(question: question, voice: model.ledger.profile.persona.instruction, aim: model.ledger.profile.aim,
                                       where: model.currentView.describe(), history: engine == .claude && session != nil ? [] : history)
        let resume = engine == .claude ? session : nil
        let aiModel = self.model   // 这里的参数 model 是账本（LedgerModel），选的 AI 模型是 self.model
        Task {
            let reply = await ChatRunner.ask(engine, prompt: prompt, resume: resume, fin: BundledFin.path, model: aiModel)
            if engine == .claude, let s = reply.sessionID { session = s }
            messages.append(Message(fromUser: false, text: reply.text, isError: reply.isError, engine: engine.name))
            busy = false
            // AI 可能刚记了账：马上读一次，顶上会弹「刚记了 N 笔」，能看、能撤销。
            model.refreshIfChanged()
        }
    }
}

extension LedgerModel {
    /// ⌘K、菜单「和夏夏聊」、工具栏「问夏夏」共用：开着就收起，没开就 chat.show()。
    func toggleChat() {
        guard chat.enabled else {
            // 选了不用内置夏夏：和以前一样，把这一页的情况复制好，打开 Claude。
            Clipboard.copy(contextLine(page: (section ?? .overview).rawValue))
            toast = .init(text: "已复制，在 Claude 里粘贴就行", changeID: nil)
            if let app = URL(string: "claude://"), !NSWorkspace.shared.open(app), let web = URL(string: "https://claude.ai/new") {
                NSWorkspace.shared.open(web)
            }
            return
        }
        if chat.open { withAnimation(.snappy) { chat.open = false } } else { chat.show() }
    }
}

/// 「夏夏在想…」。等了 15 秒还没回，提醒看一眼有没有系统弹窗：
/// 第一次在 app 里叫 AI 时，macOS 可能问「“夏夏账本”想访问“文稿”文件夹」，不点它 AI 就一直等着（实测卡满 3 分钟）。
/// 夏夏托着下巴想，旁边是这次帮她查账的 AI 伙伴；等久了提示去点系统的「允许」。
private struct ThinkingRow: View {
    var engine: ChatEngine?
    @State private var long = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                MascotView(.xiaxia, pose: .think, size: 72, animated: false)
                if let engine {
                    MascotView(MascotCharacter.of(engine), pose: .think, size: 56, animated: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("夏夏在想…").font(.caption.weight(.medium)).foregroundStyle(Color.fg2)
                    if let engine {
                        Text("\(MascotCharacter.of(engine).name)（\(engine.name)）在帮她查账").font(.caption2).foregroundStyle(Color.fg3)
                    }
                }
                .padding(.bottom, 8)
            }
            if long {
                Text("等得有点久。看看屏幕上有没有系统问「“夏夏账本”想访问…」的小窗，点「允许」夏夏就能接着回答。")
                    .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .task {
            try? await Task.sleep(for: .seconds(15))
            withAnimation { long = true }
        }
    }
}

struct XiaxiaChatPanel: View {
    @Environment(LedgerModel.self) var model
    @FocusState var inputFocused: Bool

    var body: some View {
        let chat = model.chat
        VStack(spacing: 0) {
            header(chat)
            Divider()
            if model.store is InMemoryLedgerStore {
                notice(symbol: "eye", title: "示例数据不连 AI",
                       text: "现在看的是编出来的示例账本。AI 连的是你自己的账本，两边对不上，所以这里先不聊。")
                Spacer()
            } else if chat.available.isEmpty {
                notice(symbol: "sparkles", title: "这台 Mac 上还没有能用的 AI",
                       text: "装好并登录 Claude Code、Codex 或 Hermes 其中一个，夏夏就能在这里直接回答，用的是你自己的订阅。也可以先复制这一页的情况去 Claude 里问。")
                Button {
                    // 夏夏带着连：直接到引导的「连接你的 AI」那一步。
                    model.welcomeAtAI = true
                    model.showWelcome = true
                } label: { Label("去连接 AI", systemImage: "link") }
                    .buttonStyle(AISolidButtonStyle()).padding(.top, 4)
                    .accessibilityIdentifier("chat.connectAI")
                AskAIReader { ask in
                    Button { ask("", page: (model.section ?? .overview).rawValue) } label: { Label("复制并打开 Claude", systemImage: "doc.on.doc") }
                        .buttonStyle(.soft).padding(.top, 4)
                }
                Spacer()
            } else {
                messages(chat)
                Divider()
                input(chat)
            }
        }
        // 占满对话栏、内容靠上：不让对话栏的大小跟着里面的内容变（分栏跟着重算会陷进约束死循环）。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.pageBackground)
        .onAppear {
            chat.focusRequest = { inputFocused = true }
            inputFocused = true
            // 对话栏展开的动画做完再看装了哪些 AI，别在分栏正在动的时候改顶上那一行。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { chat.refreshEngines() }
        }
    }

    private func header(_ chat: XiaxiaChatState) -> some View {
        HStack(spacing: 8) {
            MascotView(.xiaxia, size: 26, face: true, animated: false)
            Text("夏夏").font(.headline)
            Spacer()
            if !chat.available.isEmpty {
                // 每个 AI 一组：第一项「跟随默认」= 用户在那个 AI 里自己设的模型（不加参数），下面是可以手动换的。
                Menu {
                    Picker("用哪个 AI 和模型", selection: Binding(get: { chat.choiceKey }, set: { chat.choose($0) })) {
                        ForEach(chat.available) { e in
                            Section(e.name) {
                                Text(defaultTitle(e)).tag("\(e.rawValue)|")
                                ForEach(e.models()) { m in
                                    Text(m.note.isEmpty ? m.name : "\(m.name) · \(m.note)").tag("\(e.rawValue)|\(m.id)")
                                }
                            }
                        }
                    }
                    .pickerStyle(.inline)
                } label: { Text(chat.label).font(.caption).lineLimit(1) }
                    .menuStyle(.button).buttonStyle(.borderless)
                    .frame(width: 160, alignment: .trailing)  // 宽度固定，不随选中的名字变（AppKit 菜单按钮的尺寸一变就会重排整个分栏）
                    .accessibilityLabel("用哪个 AI 和模型：\(chat.label)")
                    .accessibilityIdentifier("chat.modelMenu")
            }
            Button { chat.newConversation() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless).help("新对话").accessibilityLabel("新对话")
                .disabled(chat.messages.isEmpty || chat.busy)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// 「跟随默认（Opus）」：读得到那个 AI 自己设的模型就写出来。
    private func defaultTitle(_ e: ChatEngine) -> String {
        if let m = e.defaultModel() { return "跟随 \(e.name) 的默认（\(m)）" }
        return "跟随 \(e.name) 的默认"
    }

    private func notice(symbol: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ai)
            Text(text).font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messages(_ chat: XiaxiaChatState) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if chat.messages.isEmpty { starter(chat) }
                    ForEach(chat.messages) { m in bubble(m).id(m.id) }
                    if chat.busy {
                        ThinkingRow(engine: chat.engine)
                            .id("busy")
                            .transition(.opacity)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.messages.count) { _, _ in
                if let id = chat.messages.last?.id { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) } }
            }
            .onChange(of: chat.busy) { _, busy in
                if busy { withAnimation(.snappy) { proxy.scrollTo("busy", anchor: .bottom) } }
            }
        }
    }

    private func starter(_ chat: XiaxiaChatState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                MascotView(.xiaxia, pose: .hello, size: 96, animated: false)
                Text("想记账、想问钱花哪了，直接跟我说。我看得到你现在停在哪一页。")
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }
            ForEach(model.prompts(for: model.section ?? .overview).prefix(3)) { p in
                Button { chat.prefill(p.text) } label: { PromptRow(prompt: p) }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("问夏夏：\(p.text)")
            }
        }
    }

    private func bubble(_ m: XiaxiaChatState.Message) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if m.fromUser { Spacer(minLength: 40) } else {
                MascotView(.xiaxia, pose: m.isError ? .worried : model.persona.mascotPose, size: 24, face: true, animated: false)
            }
            Text(LocalizedStringKey(m.text.keepingAmountsTogether))
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(m.fromUser ? Color.white : (m.isError ? Color.alert : Color.primary))
                .background(m.fromUser ? AnyShapeStyle(Color.aiSolid) : AnyShapeStyle(Color.aiSoft),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !m.fromUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((m.fromUser ? "你：" : "夏夏：") + m.text)
    }

    private func input(_ chat: XiaxiaChatState) -> some View {
        @Bindable var chat = chat
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("跟夏夏说，比如「午饭 12 欧」", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { chat.send(chat.draft, model: model) }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("跟夏夏说")
            Button { chat.send(chat.draft, model: model) } label: {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.aiSolid.opacity(chat.draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.busy ? 0.35 : 1), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(chat.draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.busy)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("发送")
        }
        .padding(12)
    }
}
#endif
