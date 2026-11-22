#if os(macOS)
import FinanceCore
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
    public var messages: [Message] = []
    public var busy = false
    public var draft = ""
    /// 用哪个 AI。记住上次选的；没选过就用装了的第一个（Claude Code 最快）。
    public var engine: ChatEngine? {
        didSet { UserDefaults.standard.set(engine?.rawValue, forKey: "xiaxia.chatEngine") }
    }
    public private(set) var available: [ChatEngine] = []
    @ObservationIgnored var session: String?

    public init() { refreshEngines() }

    public func refreshEngines() {
        available = ChatEngine.available()
        let saved = UserDefaults.standard.string(forKey: "xiaxia.chatEngine").flatMap(ChatEngine.init(rawValue:))
        if let saved, available.contains(saved) { engine = saved } else { engine = available.first }
    }

    /// 右键一笔「问夏夏这一笔」：打开对话栏，把这一笔写进输入框开头，光标停在后面等用户接着问。
    @ObservationIgnored var focusRequest: (() -> Void)?
    func ask(about tx: Transaction, model: LedgerModel) {
        open = true
        model.selectedTransactionID = tx.id
        draft = "这一笔：\(tx.date.month) 月 \(tx.date.day) 日「\(Merchant.display(tx.description))」\(tx.amount.formatted)，"
        focusRequest?()
    }

    /// 把一句话放进输入框（来自页面上的例句、「问 AI」按钮），打开对话栏等用户改完再发。
    func prefill(_ text: String) {
        open = true
        if !text.isEmpty { draft = text }
        focusRequest?()
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
        Task {
            let reply = await ChatRunner.ask(engine, prompt: prompt, resume: resume, fin: BundledFin.path)
            if engine == .claude, let s = reply.sessionID { session = s }
            messages.append(Message(fromUser: false, text: reply.text, isError: reply.isError, engine: engine.name))
            busy = false
            // AI 可能刚记了账：马上读一次，顶上会弹「刚记了 N 笔」，能看、能撤销。
            model.refreshIfChanged()
        }
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
                MascotView(.xiaxia, pose: .think, size: 72)
                if let engine {
                    MascotView(MascotCharacter.of(engine), pose: .think, size: 56)
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
    /// 夏夏刚回了一句：头像张嘴说两秒多。
    @State private var speaking = false

    var body: some View {
        let chat = model.chat
        VStack(spacing: 0) {
            header(chat)
            Divider()
            if model.store is InMemoryLedgerStore {
                notice(symbol: "eye", title: "示例数据不连 AI",
                       text: "现在看的是编出来的示例账本。AI 连的是你自己的账本，两边对不上，所以这里先不聊。")
            } else if chat.available.isEmpty {
                notice(symbol: "sparkles", title: "这台 Mac 上还没有能用的 AI",
                       text: "装好并登录 Claude Code、Codex 或 Hermes 其中一个，夏夏就能在这里直接回答，用的是你自己的订阅。也可以先复制这一页的情况去 Claude 里问。")
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
        .background(Color.pageBackground)
        .onAppear {
            chat.refreshEngines(); inputFocused = true
            chat.focusRequest = { inputFocused = true }
            speak()
        }
        .onChange(of: chat.messages.count) { _, _ in
            if let last = chat.messages.last, !last.fromUser, !last.isError { speak() }
        }
    }

    private func speak() {
        speaking = true
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            speaking = false
        }
    }

    private func header(_ chat: XiaxiaChatState) -> some View {
        HStack(spacing: 8) {
            MascotView(.xiaxia, size: 26, face: true, talking: speaking)
            Text("夏夏").font(.headline)
            Spacer()
            if chat.available.count > 1 {
                Menu {
                    Picker("用哪个 AI", selection: Binding(get: { chat.engine }, set: { chat.engine = $0; chat.newConversation() })) {
                        ForEach(chat.available) { Text($0.name).tag(Optional($0)) }
                    }
                    .pickerStyle(.inline)
                } label: { Text(chat.engine?.name ?? "选 AI").font(.caption) }
                    .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                    .accessibilityLabel("用哪个 AI：\(chat.engine?.name ?? "还没选")")
            } else if let e = chat.engine {
                Text(e.name).font(.caption).foregroundStyle(Color.fg2)
            }
            Button { chat.newConversation() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless).help("新对话").accessibilityLabel("新对话")
                .disabled(chat.messages.isEmpty || chat.busy)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
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
                MascotView(.xiaxia, pose: speaking ? .idle : .hello, size: 96, talking: speaking)  // 先张嘴说这句，说完挥手
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
            Text(LocalizedStringKey(m.text))
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
