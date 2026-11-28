#if os(macOS)
import AppKit
import FinanceCore
import SwiftUI

// 设置：首页 12 项分 4 组（最上面是「AI 连接」），点进去是各自的一页；弹窗在文件最后。
// 账本里的东西（账户、分类、记忆、删除数据）走核心，留改动记录、能撤销；
// 开关和名字这些偏好只是这台 Mac 上的设置，放在 V3Prefs 里。

/// 这台 Mac 上的偏好（不进账本）。
struct V3Prefs: Equatable {
    var builtIn = true
    var xiaName = "夏夏"
    var callMe = ""
    var showXia = true
    /// 页面顶上滑下来的那句话。关着时她的话都在「问夏夏」里。
    var bubbles = true
    var persona = 0
    /// 夏夏会主动说的几样，都能关。
    var speak: [String: Bool] = [:]
    var remindDays = 3
    var maxPerDay = 3
    var language = 0
    var dedupe = true
    var phoneReceipts = true
    var receiptAuto = false
    var aiRecords = true
    var samePlace = true
    /// 上次更新汇率是几号。
    var ratesDay = 17
}

struct V3AILink: Identifiable, Equatable {
    enum State { case using, linked, idle, manual, testing }
    let id: String
    var note: String
    var state: State
    static let demo: [V3AILink] = [
        .init(id: "Claude 桌面版", note: "连上了 · 今天 09:12 用过账本", state: .using),
        .init(id: "Codex", note: "连上了 · 昨天用过账本", state: .linked),
        .init(id: "Hermes", note: "装了，还没连", state: .idle),
        .init(id: "Cherry Studio", note: "要在它自己的设置里粘配置", state: .manual),
    ]
}

/// 删除前、恢复前自动留的一份。
struct V3Backup: Identifiable {
    let id = UUID()
    var title: String
    var ledger: TrialLedger
    @MainActor static var demo: [V3Backup] {
        let l = TrialLedger(book: V3State.demoBook, changes: V3State.demoChanges)
        return [V3Backup(title: "恢复前 · 11 月 12 日 09:30", ledger: l), V3Backup(title: "删除前 · 10 月 3 日 21:15", ledger: l)]
    }
}

extension V3State {
    enum SettingsSub: String {
        case ai, xia, memory, speak, privacy, author, books, business, money, sync, data, decision
        var title: String {
            switch self {
            case .ai: "管理 AI 连接"
            case .xia: "夏夏偏好"
            case .memory: "夏夏的记忆"
            case .speak: "夏夏什么时候开口"
            case .privacy: "隐私与语言"
            case .author: "记账人"
            case .books: "账本与账户"
            case .business: "管哪边"
            case .money: "钱怎么进来"
            case .sync: "同步与币种"
            case .data: "数据"
            case .decision: "决策模型"
            }
        }
    }

    func openSettings(_ sub: SettingsSub) { withAnimation(.snappy(duration: 0.2)) { settingsSub = sub } }

    func copy(_ text: String, say message: String = "复制好了") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        say(message)
    }

    /// 试用版里连 AI 是演出来的：不碰这台 Mac 上任何 AI 的设置。
    func connect(_ id: String) {
        guard let i = aiLinks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) { aiLinks[i].state = .testing; aiLinks[i].note = "正在测能不能读到账本…" }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, let k = self.aiLinks.firstIndex(where: { $0.id == id }) else { return }
            withAnimation(.snappy) { self.aiLinks[k].state = .linked; self.aiLinks[k].note = "连上了 · 刚刚读到账本" }
            self.say("\(id) 连上了（试用版是演示，没有动它的设置）")
        }
    }

    /// 删掉全部数据：先留一份备份，再删。
    func deleteEverything() {
        let stamp = Date().formatted(date: .omitted, time: .shortened)
        backups.insert(V3Backup(title: "删除前 · 今天 \(stamp)", ledger: ledger), at: 0)
        if backups.count > 10 { backups.removeLast() }
        change("已删除全部数据。删之前的备份留好了", kind: .remove) { $0.wipe() }
    }

    func restore(_ id: UUID) {
        guard let b = backups.first(where: { $0.id == id }) else { fail("这份备份已经不在了"); return }
        let stamp = Date().formatted(date: .omitted, time: .shortened)
        let now = V3Backup(title: "恢复前 · 今天 \(stamp)", ledger: ledger)
        withAnimation(.spring(duration: 0.45)) { replaceLedger(b.ledger) }
        backups.insert(now, at: 0)
        if backups.count > 10 { backups.removeLast() }
        say("已恢复成「\(b.title)」那份")
    }

    static let configPrompt = """
    请帮我把「夏夏账本」接到你这里：
    1. 在你的 MCP 设置里加一项，名字 xiaxia-ledger，命令是 ~/.local/bin/fin，参数是 mcp。
    2. 加好以后调用 context 工具，告诉我读到了几个账本、几个账户。
    3. 如果你是网页版、接不了本地工具，直接告诉我，我换一个能接的。
    """
    static let trySentence = "用夏夏账本帮我记一笔：今天买咖啡花了 3,50 €"
}

// MARK: - 搭设置页用的几块

struct V3SetGroup<Content: View>: View {
    let title: String
    var note = ""
    var grow = false
    @ViewBuilder var content: Content
    @Environment(\.v3SetNarrow) private var narrow
    var body: some View {
        // 说明不占地方：鼠标移到这一组上才出来（ming：小字太多）。
        let tall = grow && !narrow
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(V3.font(15, .heavy)).padding(.bottom, 4)
            content
            if tall { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: tall ? .infinity : nil, alignment: .topLeading)
        .v3Soft()
        .help(note)
    }
}

private struct V3SetNarrowKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var v3SetNarrow: Bool { get { self[V3SetNarrowKey.self] } set { self[V3SetNarrowKey.self] = newValue } }
}

/// 内容不多的设置子页：一栏，居中，收窄，卡片有多少内容就多高。
struct V3SetColumn<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 14) { content }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.v3SetNarrow, true)
    }
}

/// 设置里的一行：左边标题，右边放开关、按钮或者一个值。
/// `sub` 是解释，鼠标移上去才出来；`detail` 是这一行自己的数据（几笔、哪天），直接写在标题下面。
struct V3SetRow<Trail: View>: View {
    let title: String
    var sub = ""
    var detail = ""
    var line = true
    @ViewBuilder var trail: Trail
    var body: some View {
        VStack(spacing: 0) {
            if line { V3Divider() }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(V3.font(14, .bold)).lineLimit(1)
                    if !detail.isEmpty { Text(detail).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1) }
                }
                Spacer(minLength: 8)
                trail
            }
            .padding(.vertical, detail.isEmpty ? 11 : 8)
        }
        .help(sub)
    }
}

/// 点了进下一页的一行：右边一个值和小箭头。
struct V3SetLink: View {
    let title: String
    var sub = ""
    var value = ""
    var line = true
    /// 说明不写在行里，鼠标移上去才出来（ming：小字太多）。
    private var showSub: Bool { false }
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            V3SetRow(title: title, sub: sub, detail: showSub ? sub : "", line: line) {
                HStack(spacing: 6) {
                    if !value.isEmpty { Text(value).font(V3.font(13, .semibold)).foregroundStyle(V3.ink2).lineLimit(1) }
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(V3.ink2)
                }
            }
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10).fill(hover ? V3.bg : .clear).padding(.horizontal, -8))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 几个里选一个的小菜单（提前 3 天、3 件……）。
struct V3SetMenu: View {
    let options: [String]
    @Binding var pick: Int
    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in Button(o) { pick = i } }
        } label: {
            HStack(spacing: 5) {
                Text(options.indices.contains(pick) ? options[pick] : "").font(V3.font(13, .bold)).foregroundStyle(V3.ink)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(V3.ink2)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
    }
}

/// 直接在行里改的一小格字：回车或点别处就存好。
struct V3SetText: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat = 200
    var commit: () -> Void = {}
    @FocusState private var focused: Bool
    var body: some View {
        TextField(prompt, text: $text).textFieldStyle(.plain).font(V3.font(14, .bold)).foregroundStyle(V3.ink)
            .multilineTextAlignment(.trailing).focused($focused)
            .padding(.horizontal, 12).padding(.vertical, 6).frame(width: width)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? V3.ink : V3.line, lineWidth: focused ? 2 : 1.5)))
            .onSubmit(commit)
            .onChange(of: focused) { _, f in if !f { commit() } }
    }
}

// MARK: - 设置首页

struct V3SettingsPage: View {
    @Environment(V3State.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        if state.showLog { V3LogPage() } else {
            switch state.settingsSub {
            case nil: home
            case .ai: V3SetAIPage()
            case .decision: V3SetDecisionPage()
            case .xia: V3SetXiaPage()
            case .memory: V3SetMemoryPage()
            case .speak: V3SetSpeakPage()
            case .privacy: V3SetPrivacyPage()
            case .author: V3SetAuthorPage()
            case .books: V3SetBooksPage()
            case .business: V3SetBusinessPage()
            case .money: V3SetMoneyPage()
            case .sync: V3SetSyncPage()
            case .data: V3SetDataPage()
            }
        }
    }

    private var home: some View {
        let b = state.book
        let linked = state.aiLinks.filter { $0.state == .using || $0.state == .linked }
        let speakOn = V3SetSpeakPage.items.filter { state.prefs.speak[$0.0] ?? true }.count
        let today = state.ledger.changes.filter { !$0.undone }.count
        return V3Cols {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 连接").font(V3.font(19, .heavy))
                        }
                        Spacer()
                        Button("连接你的 AI") { state.openSettings(.ai) }.buttonStyle(.v3)
                    }
                    .padding(.bottom, 8)
                    V3SetLink(title: linked.isEmpty ? "还没连 AI" : "✨ \(linked.count) 个 AI 已连接", sub: "管理连接",
                              value: linked.map { $0.id.replacingOccurrences(of: " 桌面版", with: "") }.joined(separator: "、")) { state.openSettings(.ai) }
                    V3SetRow(title: "🔗 复制配置指令", sub: "复制一段话，粘给任何 AI，它会自己把夏夏账本配好") {
                        Button("复制") { state.copy(V3State.configPrompt, say: "已复制，粘贴给你的 AI 就行") }.buttonStyle(.v3(.ghost, .small))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
                V3SetGroup(title: state.prefs.xiaName) {
                    V3SetLink(title: "\(state.prefs.xiaName)偏好", sub: "名字、口吻、要不要出现在页面上", value: state.prefs.builtIn ? "内置\(state.prefs.xiaName)已打开" : "关着", line: false) { state.openSettings(.xia) }
                    V3SetLink(title: "\(state.prefs.xiaName)的记忆", sub: "她记住的关于你的钱的事",
                              value: "\(b.memos.filter { $0.kind == .rule }.count) 条规矩 · \(b.memos.filter { $0.kind != .rule }.count) 件事") { state.openSettings(.memory) }
                    V3SetLink(title: "\(state.prefs.xiaName)什么时候开口", sub: "提醒、小结、到站的信", value: speakOn == V3SetSpeakPage.items.count ? "\(speakOn) 样都开着" : "开着 \(speakOn) 样") { state.openSettings(.speak) }
                }
                V3SetGroup(title: "这台 Mac", grow: true) {
                    V3SetLink(title: "隐私与语言", sub: "上锁、界面语言", value: "\(state.lockPolicy.enabled ? "上着锁" : "没上锁") · \(V3SetPrivacyPage.languages[state.prefs.language])", line: false) { state.openSettings(.privacy) }
                    V3SetLink(title: "记账人", sub: "改动记录里用这个名字", value: state.author) { state.openSettings(.author) }
                }
            }
        } trailing: {
            VStack(spacing: 14) {
                V3SetGroup(title: "账本") {
                    V3SetLink(title: "账本与账户", sub: "账本、账户、分类", value: "\(state.mode == .both ? 2 : 1) 个账本 · \(b.accounts.count) 个账户", line: false) { state.openSettings(.books) }
                    V3SetLink(title: "管哪边", sub: "生活、生意各一个开关", value: state.mode == .both ? "生活 + 生意" : state.showsBiz ? "只管生意" : "只管生活") { state.openSettings(.business) }
                    V3SetLink(title: "钱怎么进来", sub: "流水、小票、跟 AI 说一句", value: "上次：今天") { state.openSettings(.money) }
                    V3SetLink(title: "同步与币种", sub: "账本放在哪、更新、汇率", value: "● 试用账本 · 欧元 €") { state.openSettings(.sync) }
                    V3SetLink(title: "改动记录", sub: "每一次改动都能撤销", value: "今天 \(today) 次") { withAnimation(.snappy(duration: 0.2)) { state.showLog = true } }
                }
                V3SetGroup(title: "数据和帮助", grow: true) {
                    V3SetLink(title: "数据", sub: "演示数据、删除数据、从备份恢复", line: false) { state.openSettings(.data) }
                    V3SetLink(title: "反馈问题 / 提个想法", sub: "写好用邮件发给我们") { state.open(.feedback) }
                    V3SetLink(title: "更新日志", sub: "每一版改了什么（官网）") { openURL(Changelog.webURL) }
                    V3SetLink(title: "再走一遍开头的引导", sub: "试用版里用来再看一次") { withAnimation(.snappy) { state.onboardingStep = 0 } }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - 管理 AI 连接

private struct V3SetAIPage: View {
    @Environment(V3State.self) private var state
    var body: some View {
        V3SetColumn {
            V3SetGroup(title: "这台 Mac 上的 AI", note: "「用过账本」是这个 AI 最近一次打开账本的时间。", grow: true) {
                ForEach(Array(state.aiLinks.enumerated()), id: \.element.id) { i, a in
                    V3SetRow(title: a.id, detail: a.note, line: i > 0) {
                        HStack(spacing: 8) {
                            switch a.state {
                            case .using: V3Tag(text: "在用", tone: .green)
                            case .linked: V3Tag(text: "连着", tone: .green)
                            case .idle: V3Tag(text: "没连", tone: .blue)
                            case .manual: V3Tag(text: "手动", tone: .blue)
                            case .testing: ProgressView().controlSize(.small)
                            }
                            switch a.state {
                            case .using, .linked: Button("重新连接") { state.connect(a.id) }.buttonStyle(.v3(.ghost, .small))
                            case .idle: Button("连接") { state.connect(a.id) }.buttonStyle(.v3(.primary, .small))
                            case .manual: Button("复制配置") { state.copy(V3State.configPrompt, say: "配置已复制") }.buttonStyle(.v3(.ghost, .small))
                            case .testing: EmptyView()
                            }
                        }
                    }
                }
                V3SetRow(title: "\(state.prefs.xiaName)自带的 AI", sub: "没连别的 AI，或者它连不上时用") { V3Tag(text: "备用", tone: .blue) }
            }
            V3SetGroup(title: "OpenRouter") {
                let _ = state.keyRevision
                V3SetLink(title: "决策模型", value: state.hasOpenRouterKey ? "密钥已填 · \(state.decisionPrefs.decisionModel)" : "没连 · 按固定规则判断", line: false) { state.openSettings(.decision) }
                V3SetRow(title: "问夏夏用哪个", detail: state.chatRouteLine) { EmptyView() }
            }
            VStack(spacing: 14) {
                V3SetGroup(title: "再连一个", note: "Claude、Codex、Hermes 点一下就连好；别的 AI 复制一段话粘过去。") {
                    V3SetRow(title: "走一遍连接的步骤", line: false) { Button("开始") { withAnimation(.snappy) { state.onboardingStep = 4 } }.buttonStyle(.v3(.primary, .small)) }
                }
                V3SetGroup(title: "试一句", note: "AI 第一次用账本时可能会问「允许使用夏夏账本吗」，选允许。记错了在改动记录里撤销。", grow: true) {
                    Text(V3State.trySentence).font(V3.font(14, .bold))
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(V3.bg))
                    HStack(spacing: 8) {
                        Button("复制这句话") { state.copy(V3State.trySentence) }.buttonStyle(.v3(.ghost, .small))
                        Button("在问\(state.prefs.xiaName)里试") {
                            state.chat.append(.init(mine: true, text: V3State.trySentence))
                            let ok = state.record(QuickPhrase(name: "咖啡", emoji: "☕", amount: Money(cents: 3_50)), account: "现金")
                            state.chat.append(.init(mine: false, text: ok ? "记好了：咖啡 3,50 €，现金。记错了点底下的「撤销」。" : "没记成，再试一次。"))
                            state.openChat()
                        }
                        .buttonStyle(.v3(.ghost, .small))
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

// MARK: - 夏夏偏好

private struct V3SetXiaPage: View {
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var call = ""
    static let personas: [(String, String)] = [("温和直说", "可以留意一下。"), ("毒舌", "钱包在哭，你听见了吗。"), ("文静", "比上月多 40 €。"), ("打气", "没关系，下个月一起少花一点！")]

    var body: some View {
        @Bindable var s = state
        V3SetColumn {
            VStack(spacing: 14) {
                V3SetGroup(title: "内置\(state.prefs.xiaName)", note: "打开后借你电脑上的 AI 回答；关掉后「问\(state.prefs.xiaName)」会把问题复制好，交给你自己的 AI。") {
                    V3SetRow(title: "内置\(state.prefs.xiaName)", sub: "点「问\(state.prefs.xiaName)」时打开一整页对话", line: false) { V3Switch(on: $s.prefs.builtIn, label: "内置夏夏") }
                }
                V3SetGroup(title: "名字和称呼", note: "回车或点别处就存好。", grow: true) {
                    V3SetRow(title: "她的名字", line: false) {
                        V3SetText(prompt: "夏夏", text: $name) {
                            let n = name.trimmingCharacters(in: .whitespaces)
                            let use = n.isEmpty ? "夏夏" : String(n.prefix(8))
                            if use != state.prefs.xiaName { state.prefs.xiaName = use; state.say("好，以后叫她「\(use)」") }
                            name = use
                        }
                    }
                    V3SetRow(title: "怎么叫你") {
                        V3SetText(prompt: "不填就叫「你」", text: $call) {
                            let n = String(call.trimmingCharacters(in: .whitespaces).prefix(8))
                            if n != state.prefs.callMe { state.prefs.callMe = n; state.say(n.isEmpty ? "好，就叫「你」" : "好，以后叫你「\(n)」") }
                        }
                    }
                }
            }
            VStack(spacing: 14) {
                V3SetGroup(title: "\(state.prefs.xiaName)出不出现") {
                    V3SetRow(title: "大事的时候显示\(state.prefs.xiaName)", sub: "到站、月底小结。关掉后只是不出现人物", line: false) { V3Switch(on: $s.prefs.showXia, label: "显示夏夏") }
                    V3SetRow(title: "页面顶上滑下来的那句话", sub: "关着时她的话都在「问\(state.prefs.xiaName)」里") { V3Switch(on: $s.prefs.bubbles, label: "夏夏的消息") }
                }
                V3SetGroup(title: "\(state.prefs.xiaName)怎么跟你说话", note: "不管选哪个，都不批评人。", grow: true) {
                    HStack(spacing: 10) {
                        ForEach(Array(Self.personas.enumerated()), id: \.offset) { i, p in
                            V3Option(picked: state.prefs.persona == i) {
                                withAnimation(.snappy(duration: 0.15)) { state.prefs.persona = i }
                                state.say("好，以后用「\(p.0)」的口吻")
                            } content: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(p.0).font(V3.font(14.5, .bold)).foregroundStyle(V3.ink)
                                    Text("「\(p.1)」").font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(height: 104).padding(.top, 6)
                }
            }
        }
        .onAppear { name = state.prefs.xiaName; call = state.prefs.callMe }
    }
}

// MARK: - 夏夏的记忆

private struct V3SetMemoryPage: View {
    @Environment(V3State.self) private var state
    @State private var tab = 1
    @State private var search = ""
    static let tabs = ["我的规矩", "记得的事", "做事经验"]

    var body: some View {
        let all = state.book.memos
        let kind = TrialBook.Memo.Kind(rawValue: tab) ?? .topic
        let q = search.trimmingCharacters(in: .whitespaces)
        let list = all.filter { $0.kind == kind && (q.isEmpty || $0.topic.localizedCaseInsensitiveContains(q) || $0.lines.contains { $0.localizedCaseInsensitiveContains(q) }) }
        V3Cols(left: 1.5, right: 1) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    V3FormPick(label: "", options: Self.tabs.enumerated().map { i, t in "\(t) \(all.filter { $0.kind.rawValue == i }.count)" }, pick: $tab).fixedSize()
                    HStack(spacing: 6) {
                        Text("🔍")
                        TextField("搜记忆", text: $search).textFieldStyle(.plain).font(V3.font(14, .semibold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                    Button("记一条") { state.open(.memoAdd) }.buttonStyle(.v3(.primary, .small))
                }
                if all.isEmpty {
                    VStack(spacing: 10) {
                        V3Face(face: "think", width: 84)
                        Text("\(state.prefs.xiaName)还没记住什么").font(V3.font(20, .heavy))
                        Button("记一条") { state.open(.memoAdd) }.buttonStyle(.v3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).v3Soft()
                } else if list.isEmpty {
                    V3Label(q.isEmpty ? "「\(Self.tabs[tab])」里还没有东西。" : "没找到「\(q)」。").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 10) { ForEach(list) { m in memo(m) } }
                    }
                    .scrollIndicators(.never)
                }
            }
        } trailing: {
            VStack(spacing: 14) {
                let stale = state.book.memos.filter { !$0.important && $0.kind == .lesson }
                if !stale.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("该整理了").font(V3.font(15, .heavy))
                        HStack {
                            V3Label("\(stale.count) 条可能用不上了")
                            Spacer()
                            Button("看一看") { state.open(.memoTidy) }.buttonStyle(.v3(.primary, .small))
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 22).fill(V3.goodBG))
                }
                V3SetGroup(title: "让\(state.prefs.xiaName)先认识我", note: "她翻一遍流水，把看出来的规律一条条问你，你说对的才记。你说的直接记；金额、卡号、密码不记。") {
                    V3SetRow(title: "翻一遍流水，一条条问你", line: false) { Button("开始") { state.open(.memoMeet) }.buttonStyle(.v3(.ghost, .small)) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func memo(_ m: TrialBook.Memo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(m.topic).font(V3.font(15, .heavy))
                if m.important { V3Tag(text: "重要", tone: .gold) }
                Spacer(minLength: 6)
                Text(m.source).font(V3.font(12, .regular)).foregroundStyle(V3.ink2)
                Menu {
                    Button(m.important ? "不标重要了" : "标成重要（整理时不问）") {
                        state.change(m.important ? "好，不标重要了" : "标成重要了：\(m.topic)") { try $0.setMemo(m.id, important: !m.important) }
                    }
                    ForEach(TrialBook.Memo.Kind.allCases.filter { $0 != m.kind }, id: \.rawValue) { k in
                        Button("挪到「\(Self.tabs[k.rawValue])」") { state.change("挪好了：\(m.topic) → \(Self.tabs[k.rawValue])") { try $0.setMemo(m.id, kind: k) } }
                    }
                    Divider()
                    Button("删掉（能撤销）") { state.change("删掉了：\(m.topic)", kind: .remove) { try $0.removeMemo(m.id) } }
                    Button("彻底忘掉（找不回来）…") { state.open(.memoForget(m.id)) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 28, height: 24)
                }
                .menuStyle(.button).buttonStyle(.plain).fixedSize().accessibilityLabel("「\(m.topic)」的更多操作")
            }
            ForEach(m.lines, id: \.self) { l in
                Text("· \(l)").font(V3.font(13.5, .regular)).foregroundStyle(V3.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).v3Soft(radius: 16)
    }
}

// MARK: - 夏夏什么时候开口

private struct V3SetSpeakPage: View {
    @Environment(V3State.self) private var state
    static let items: [(String, String)] = [
        ("目标快到不了时", "说清情况，建议把步子改小"), ("到站时写一封信", "收进「沿途风光」"), ("该付钱、该还钱之前", "提前几天说一声"),
        ("每月小结", "每月 1 日写好"), ("每周一句（生意）", "周一早上说上周店里的情况"), ("拿不准的流水", "「这笔算超市吗？」一次只问一笔"),
    ]

    var body: some View {
        @Bindable var s = state
        V3SetColumn {
            V3SetGroup(title: "她会主动说的", grow: true) {
                ForEach(Array(Self.items.enumerated()), id: \.offset) { i, item in
                    V3SetRow(title: item.0, sub: item.1, line: i > 0) {
                        HStack(spacing: 8) {
                            if i == 2 { V3SetMenu(options: ["提前 1 天", "提前 3 天", "提前 7 天"], pick: Binding(get: { [1, 3, 7].firstIndex(of: state.prefs.remindDays) ?? 1 }, set: { state.prefs.remindDays = [1, 3, 7][$0] })) }
                            V3Switch(on: Binding(get: { state.prefs.speak[item.0] ?? true }, set: { v in
                                state.prefs.speak[item.0] = v
                                state.say(v ? "好，这件事我会说" : "好，这件事我不主动说了")
                            }), label: item.0)
                        }
                    }
                }
            }
            VStack(spacing: 14) {
                V3SetGroup(title: "她怎么出现", note: "一次只说一件事。同一件事你点了叉，当天不再提。") {
                    V3SetRow(title: "页面顶上滑下来的那句话", sub: "关掉以后页面上只留数字", line: false) { V3Switch(on: $s.prefs.bubbles, label: "夏夏的消息") }
                    V3SetRow(title: "一天最多说几件事") {
                        V3SetMenu(options: ["1 件", "2 件", "3 件", "5 件"], pick: Binding(get: { [1, 2, 3, 5].firstIndex(of: state.prefs.maxPerDay) ?? 2 }, set: { state.prefs.maxPerDay = [1, 2, 3, 5][$0] }))
                    }
                }
                V3SetGroup(title: "试用", note: "把今天说过的次数清零，回到总览再看她说一句。") {
                    V3SetRow(title: "让她再说一次", line: false) { Button("去看") { state.sayAgain(); state.go(.overview) }.buttonStyle(.v3(.ghost, .small)) }
                }
            }
        }
    }
}

// MARK: - 隐私与语言

private struct V3SetPrivacyPage: View {
    @Environment(V3State.self) private var state
    static let languages = ["中文", "English", "Español"]

    var body: some View {
        @Bindable var s = state
        V3SetColumn {
            V3SetGroup(title: "上锁", note: "解锁用这台 Mac 的指纹或登录密码，夏夏账本自己不存密码。") {
                V3SetRow(title: "打开 app 时要解锁", line: false) {
                    V3Switch(on: Binding(get: { state.lockPolicy.enabled }, set: { v in Task { await state.setLock(enabled: v) } }), label: "打开 app 时要解锁")
                }
                V3SetRow(title: "离开多久后再锁") {
                    V3SetMenu(options: AppLockPolicy.graceChoices.map(\.title),
                              pick: Binding(get: { AppLockPolicy.graceChoices.firstIndex { $0.seconds == state.lockPolicy.grace } ?? 2 },
                                            set: { state.setLock(grace: AppLockPolicy.graceChoices[$0].seconds) }))
                }
            }
            V3SetGroup(title: "语言", note: "试用版只有中文。英文和西班牙语还在翻译，选了以后没翻到的地方先显示中文。", grow: true) {
                V3SetRow(title: "界面语言", line: false) {
                    V3SetMenu(options: Self.languages, pick: Binding(get: { state.prefs.language }, set: { v in
                        state.prefs.language = v
                        state.say(v == 0 ? "好，用中文" : "记下了：\(Self.languages[v])。试用版还没翻译，先显示中文")
                    }))
                }
            }
        }
    }
}

// MARK: - 记账人

private struct V3SetAuthorPage: View {
    @Environment(V3State.self) private var state
    @State private var name = ""

    var body: some View {
        V3SetColumn {
            V3SetGroup(title: "记账的人", note: "回车或离开这一页就存好。以后你在 app 里记的、改的，都写这个名字。", grow: true) {
                V3SetRow(title: "名字", line: false) { V3SetText(prompt: "你", text: $name) { commit() } }
            }
            V3SetGroup(title: "改动记录里长这样", note: "AI 记的写 AI 的名字，你记的写你的名字。", grow: true) {
                V3SetRow(title: "存一笔 20 € 进「换新电脑」", detail: "今天 08:30", line: false) { V3Tag(text: name.trimmingCharacters(in: .whitespaces).isEmpty ? "你" : name, tone: .blue) }
                V3SetRow(title: "记一笔：咖啡 3,20 € · 现金", detail: "今天 09:12") { V3Tag(text: "Claude", tone: .gold) }
            }
        }
        .onAppear { name = state.author }
        .onDisappear { commit() }
    }

    private func commit() {
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(12))
        let use = n.isEmpty ? "你" : n
        guard use != state.author else { return }
        state.author = use
        state.say("好，以后改动记录里写「\(use)」")
    }
}

// MARK: - 账本与账户

private struct V3SetBooksPage: View {
    @Environment(V3State.self) private var state
    var body: some View {
        let b = state.book
        let life = b.entries.filter { $0.side == .life }.count
        let shop = b.entries.filter { $0.side == .biz }.count + b.shopOpenDays
        V3SetColumn {
            V3SetGroup(title: "账本", note: "每个账本有自己的收支和小结。", grow: true) {
                if state.showsLife { V3SetRow(title: "🏠 \(b.lifeName)", detail: "\(life) 笔流水 · \(b.accounts(on: .life).count) 个账户", line: false) { V3Tag(text: "生活", tone: .blue) } }
                if state.showsBiz {
                    V3SetRow(title: "🏪 \(b.shopName)", detail: "\(shop) 笔流水 · \(b.accounts(on: .biz).count) 个账户") { V3Tag(text: "生意", tone: .teal) }
                }
            }
            V3SetGroup(title: "管理", grow: true) {
                V3SetLink(title: "管理账本", sub: "改名", value: "\(state.mode == .both ? 2 : 1) 个", line: false) { state.open(.books) }
                V3SetLink(title: "管理账户", sub: "加、改、删，置顶成卡片", value: "\(b.accounts(on: state.side == .biz ? .biz : .life).count) 个") { state.open(.accounts) }
                V3SetLink(title: "管理分类", sub: "换图标、改名、把两个并成一个", value: "\(b.categories.count) 个") { state.open(.categories) }
            }
        }
    }
}

// MARK: - 生意模式

private struct V3SetBusinessPage: View {
    @Environment(V3State.self) private var state
    var body: some View {
        let b = state.book
        let on = state.showsBiz
        V3SetColumn {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    HStack {
                        Text("生活").font(V3.font(17, .heavy))
                        Spacer()
                        V3Switch(on: Binding(get: { state.showsLife }, set: { v in state.setSides(life: v, biz: state.showsBiz) }), label: "生活")
                    }
                    .padding(.vertical, 8)
                    V3Divider()
                    HStack {
                        Text("生意").font(V3.font(17, .heavy))
                        Spacer()
                        V3Switch(on: Binding(get: { state.showsBiz }, set: { v in state.setSides(life: state.showsLife, biz: v) }), label: "生意", tint: V3.teal)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 20).padding(.vertical, 16).v3Sticker()
                if on {
                    V3SetGroup(title: "开店本钱", grow: true) {
                        if b.capitalTotal > .zero {
                            V3SetRow(title: b.capitalTotal.v3, detail: "\(b.capital.count) 样 · 已经赚回 \(Int((Double(16_728_00) / Double(max(b.capitalTotal.cents, 1)) * 100).rounded()))%", line: false) {
                                Button("改本钱…") { state.open(.capitalTotal) }.buttonStyle(.v3(.ghost, .small))
                            }
                        } else {
                            V3SetRow(title: "还没填", sub: "填上以后，夏夏就能算什么时候回本", line: false) { Button("填本钱…") { state.open(.capitalTotal) }.buttonStyle(.v3(.teal, .small)) }
                        }
                    }
                } else {
                    EmptyView()
                }
            }
            V3SetGroup(title: "两边怎么算", note: "关掉的那边只是不显示，账还在，再打开一样。", grow: true) {
                V3SetRow(title: "给自己发工资", sub: "从店里拿回家的钱，扣掉它才算真赚", line: false) {
                    Text(b.fixedCosts.first { $0.name.contains("工资") }.map { "\($0.note) · \($0.amount.v3Short)" } ?? "还没定").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                }
                V3SetRow(title: "每天收的钱", sub: "现金和刷卡各记一个总数") { Button("记今天的账") { state.open(.shopDay(b.todayDay)) }.buttonStyle(.v3(.ghost, .small)).disabled(!on) }
                V3SetRow(title: "两边转钱", sub: "店里和家里之间挪钱") { Button("转一笔") { state.open(.transfer) }.buttonStyle(.v3(.ghost, .small)).disabled(!on) }
            }
        }
    }
}

// MARK: - 钱怎么进来

private struct V3SetMoneyPage: View {
    @Environment(V3State.self) private var state
    var body: some View {
        @Bindable var s = state
        V3SetColumn {
            V3SetGroup(title: "流水导入", note: "导错了能在改动记录里整批撤销。", grow: true) {
                V3SetRow(title: "上次导入", detail: "今天 10:40 · 晴空银行 11 月流水 · 新的 31 笔，跳过重复 6 笔", line: false) { Button("再导一份") { state.go(.transactions) }.buttonStyle(.v3(.ghost, .small)) }
                V3SetRow(title: "认得哪些银行", detail: "常见银行导出的 CSV") { EmptyView() }
                V3SetRow(title: "重复的流水", sub: "同一天、同一金额、同一家店的只留一笔") { V3Switch(on: $s.prefs.dedupe, label: "跳过重复的流水") }
            }
            VStack(spacing: 14) {
                V3SetGroup(title: "手机拍的小票") {
                    V3SetRow(title: "自动传到这台 Mac", sub: "手机上拍，几秒钟后出现在「记一笔」里", line: false) { V3Switch(on: $s.prefs.phoneReceipts, label: "小票自动传过来") }
                    V3SetRow(title: "认出来以后") {
                        V3SetMenu(options: ["等我点一下再记", "直接记"], pick: Binding(get: { state.prefs.receiptAuto ? 1 : 0 }, set: { state.prefs.receiptAuto = $0 == 1 }))
                    }
                }
                V3SetGroup(title: "跟 AI 说一句", note: "AI 记的每一笔都在改动记录里，写着是哪个 AI 记的。", grow: true) {
                    V3SetRow(title: "让连着的 AI 直接记", sub: "「刚才咖啡 3 块 2」", line: false) { V3Switch(on: $s.prefs.aiRecords, label: "让 AI 直接记") }
                    V3SetRow(title: "同一家店的付款方式", sub: "只问第一次，以后按你的习惯") { V3Switch(on: $s.prefs.samePlace, label: "记住付款方式") }
                }
            }
        }
    }
}

// MARK: - 同步与币种

private struct V3SetSyncPage: View {
    @Environment(V3State.self) private var state
    @Environment(\.openURL) private var openURL
    var body: some View {
        V3SetColumn {
            VStack(spacing: 14) {
                V3SetGroup(title: "同步", note: "试用版的账本只在内存里，关掉 app 就没了，不碰你真的账本。") {
                    V3SetRow(title: "状态", line: false) { Text("● 试用账本 · 示例数据").font(V3.font(13, .bold)).foregroundStyle(V3.green) }
                    V3SetRow(title: "账本文件", sub: "正式版里在 iCloud 云盘 / 夏夏账本 / ledger.sqlite") { EmptyView() }
                    V3SetRow(title: "重新读取账本", sub: "另一台设备刚改过、这边没变时点一下") { Button("重新读取") { state.reload() }.buttonStyle(.v3(.ghost, .small)) }
                }
                V3SetGroup(title: "更新", grow: true) {
                    V3SetRow(title: "现在的版本", sub: "界面 v3 试用版，不会自己更新", detail: state.updateVersion.map { "有新版本 \($0)" } ?? "", line: false) {
                        if state.updateVersion != nil { Button("更新") { state.say("试用版不会自己更新，这里只是演示有新版本时的样子") }.buttonStyle(.v3(.primary, .small)) }
                    }
                    V3SetLink(title: "更新日志", sub: "每一版改了什么（官网）") { openURL(Changelog.webURL) }
                }
            }
            V3SetGroup(title: "币种", note: "取汇率只下载欧洲央行的公开数据，不上传你的任何东西。", grow: true) {
                V3SetRow(title: "主币种", sub: "总览、小结里的总数都换成它", line: false) { Button("欧元 €  ›") { state.open(.baseCurrency) }.buttonStyle(.v3(.ghost, .small)) }
                V3SetRow(title: "金额写法") { Text("1.234,56 €").font(V3.num(14)).foregroundStyle(V3.ink2) }
                V3SetRow(title: "汇率", detail: "欧洲央行 · 11 月 \(state.prefs.ratesDay) 日的") {
                    Button("更新汇率") { state.prefs.ratesDay = 18; state.say("试用版没有真的去取：正式版会下载欧洲央行当天的汇率") }.buttonStyle(.v3(.ghost, .small))
                }
                V3SetRow(title: "外币账户") { Text("没有，用不到").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2) }
            }
        }
    }
}

// MARK: - 数据

private struct V3SetDataPage: View {
    @Environment(V3State.self) private var state
    var body: some View {
        let c = state.book.counts
        V3SetColumn {
            VStack(spacing: 14) {
                V3SetGroup(title: "演示数据", note: "试用版里一直是演示数据：都是编的，随便点、随便改，都不会进你自己的账本。") {
                    V3SetRow(title: "正在看演示数据", sub: "你自己的账本没动，好好地放着", line: false) {
                        Button("换回一开始的样子") {
                            let fresh = TrialLedger(book: V3State.demoBook, changes: V3State.demoChanges)
                            let stamp = Date().formatted(date: .omitted, time: .shortened)
                            state.backups.insert(V3Backup(title: "恢复前 · 今天 \(stamp)", ledger: state.ledger), at: 0)
                            withAnimation(.spring(duration: 0.45)) { state.replaceLedger(fresh) }
                            state.say("换回一开始的示例了")
                        }
                        .buttonStyle(.v3(.ghost, .small))
                    }
                }
                V3SetGroup(title: "删除数据", note: "删之前会自动留一份备份。夏夏的名字、口吻、记忆这些不会删。", grow: true) {
                    V3SetRow(title: "删掉全部数据", detail: state.book.isEmpty ? "现在已经是空的了" : "\(c.entries) 笔流水、\(c.plans) 个目标和欠款、\(c.subscriptions) 个订阅", line: false) {
                        Button("删除…") { state.open(.deleteAsk) }.buttonStyle(.v3(.danger, .small)).disabled(state.book.isEmpty)
                    }
                }
            }
            V3SetGroup(title: "从备份恢复", note: "每次删除前、恢复前自动留的备份，只留最近 10 份。", grow: true) {
                if state.backups.isEmpty { V3Label("还没有备份。") }
                ForEach(Array(state.backups.prefix(7).enumerated()), id: \.element.id) { i, b in
                    V3SetRow(title: b.title, detail: "里面有 \(b.ledger.book.counts.entries) 笔", line: i > 0) {
                        Button("恢复") { state.open(.restore(b.id)) }.buttonStyle(.v3(.ghost, .small))
                    }
                }
            }
        }
    }
}

// MARK: - 设置里的弹窗

/// 没有输入框、只问一句的确认窗。
private struct V3ConfirmBody: View {
    let text: String
    var warn = false
    var body: some View {
        Text(text).font(V3.font(14.5, .semibold)).foregroundStyle(V3.ink).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(warn ? V3.warnBG : V3.bg))
    }
}

struct V3MemoAddSheet: View {
    @Environment(V3State.self) private var state
    @State private var kind = 1
    @State private var topic = ""
    @State private var line = ""

    var body: some View {
        let t = topic.trimmingCharacters(in: .whitespaces)
        let exists = state.book.memos.contains { $0.topic == t }
        V3SheetBox(width: 560, title: "记一条", sub: "告诉\(state.prefs.xiaName)一件她该记住的事", foot: "\(line.count)/200", primary: "记下",
                   canSave: !t.isEmpty && !line.trimmingCharacters(in: .whitespaces).isEmpty && line.count <= 200,
                   save: {
                       let k = TrialBook.Memo.Kind(rawValue: kind) ?? .topic
                       if state.change(exists ? "记下了，加在「\(t)」下面" : "记下了：\(t)", { try $0.remember(k, topic: topic, line: line) }) { state.closeSheet() }
                   }) {
            if !exists { V3FormPick(label: "放在哪", options: V3SetMemoryPage.tabs, pick: $kind) }
            V3FormField(label: "话题", prompt: "转给妈妈的钱", text: $topic, focus: true)
            if exists { V3Label("已经有「\(t)」这一条了，会加在它下面，不另开一条。", size: 12.5, color: V3.teal, weight: .semibold) }
            V3FormField(label: "要\(state.prefs.xiaName)记住什么", prompt: "一句话说清。写话题，不写结论：「工资」，不是「工资涨了」", text: $line)
            if line.count > 200 { V3Label("写短一点，200 个字以内。", color: V3.red, weight: .semibold) }
        }
    }
}

struct V3MemoForgetSheet: View {
    let id: UUID
    @Environment(V3State.self) private var state
    var body: some View {
        let m = state.book.memos.first { $0.id == id }
        V3SheetBox(width: 480, title: "彻底忘掉「\(m?.topic ?? "")」？", primary: "彻底忘掉", danger: true, save: {
            state.forget(memo: id)
            state.closeSheet()
        }) {
            V3ConfirmBody(text: "连改动记录里留着的那段话一起抹掉，找不回来，也不能撤销。\n只是不想让它出现在这里的话，用「删掉」就行，那个能撤销。", warn: true)
        }
    }
}

/// 该整理了：一条条看，留着还是删掉。
struct V3MemoTidySheet: View {
    @Environment(V3State.self) private var state
    var body: some View {
        let stale = state.book.memos.filter { !$0.important && $0.kind == .lesson }
        V3SheetBox(width: 560, title: "该整理了", sub: "可能用不上的", foot: "删掉的能撤销。留着的标成重要，以后不再问。", primary: "好了", save: { state.closeSheet() }) {
            if stale.isEmpty { V3ConfirmBody(text: "都整理完了。") }
            ForEach(stale.prefix(4)) { m in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.topic).font(V3.font(14.5, .heavy))
                        Text(m.lines.joined(separator: "；")).font(V3.font(13, .regular)).foregroundStyle(V3.ink2).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button("留着") { state.change("留着：\(m.topic)") { try $0.setMemo(m.id, important: true) } }.buttonStyle(.v3(.ghost, .small))
                    Button("删掉") { state.change("删掉了：\(m.topic)", kind: .remove) { try $0.removeMemo(m.id) } }.buttonStyle(.v3(.danger, .small))
                }
                .padding(.horizontal, 14).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 14).fill(V3.bg))
            }
        }
    }
}

/// 让夏夏先认识我：把从流水里看出来的规律一条条问，说对的才记。
struct V3MemoMeetSheet: View {
    @Environment(V3State.self) private var state
    @State private var step = 0
    @State private var kept = 0
    @State private var skipped: Set<String> = []

    /// 从账本里现看出来的几条（话题，一句话）。
    private var guesses: [(String, String)] {
        let b = state.book
        var out: [(String, String)] = []
        if let rent = b.upcoming.first(where: { $0.name == "房租" }) { out.append(("房租", "每月 1 日付，\(rent.amount.v3Short) 左右")) }
        if let top = Dictionary(grouping: b.entries.filter { !$0.place.isEmpty && $0.amount.cents < 0 }, by: \.place).max(by: { $0.value.count < $1.value.count }) {
            out.append((top.key, "常去，用\(top.value.first?.account ?? "现金")付"))
        }
        if let s = b.subscriptions.first(where: { $0.flag }) { out.append((s.name, "赚钱要用的，别建议我退")) }
        if b.accounts.contains(where: { $0.kind == .shop }) { out.append(("店里的钱", "和家里的分开算")) }
        return out.filter { g in !skipped.contains(g.0) && !b.memos.contains { $0.topic == g.0 } }
    }

    var body: some View {
        let list = guesses
        let g = list.first
        V3SheetBox(width: 540, title: "让\(state.prefs.xiaName)先认识我", sub: g == nil ? "" : "第 \(step + 1) 条", foot: "你说对的才记。记了也能删。", primary: g == nil ? "好了" : "先到这",
                   save: { state.closeSheet() }) {
            if let g {
                V3Ask(face: "think", text: "「\(g.0)」：\(g.1)。对吗？") {
                    HStack(spacing: 8) {
                        Button("对，记下") {
                            if state.change("记下了：\(g.0)", { try $0.remember(.topic, topic: g.0, line: g.1, source: "夏夏看出来的，你确认过") }) { kept += 1; step += 1 }
                        }
                        .buttonStyle(.v3(.primary, .small))
                        Button("不对") { skipped.insert(g.0); step += 1; state.say("好，这条不记") }
                            .buttonStyle(.v3(.ghost, .small))
                    }
                }
            } else {
                V3ConfirmBody(text: kept > 0 ? "这一轮记了 \(kept) 条。别的我没看出来，以后看出来再问你。" : "流水里暂时没看出别的规律，以后看出来再问你。")
            }
        }
    }
}

struct V3DeleteAskSheet: View {
    @Environment(V3State.self) private var state
    var body: some View {
        let c = state.book.counts
        V3SheetBox(width: 480, title: "要删掉全部数据吗？", primary: "继续", danger: true, save: { state.open(.deleteConfirm) }) {
            V3ConfirmBody(text: "会删掉：\(c.entries) 笔流水、\(c.plans) 个目标和欠款、\(c.subscriptions) 个订阅。账本和账户留着，里面的钱归零。\n删之前自动备份，删错了能在这一页恢复。", warn: true)
        }
    }
}

struct V3DeleteConfirmSheet: View {
    @Environment(V3State.self) private var state
    @State private var word = ""
    var body: some View {
        V3SheetBox(width: 480, title: "最后确认一次", primary: "删除", danger: true, canSave: word.trimmingCharacters(in: .whitespaces) == "删除", save: {
            state.closeSheet()
            state.deleteEverything()
        }) {
            V3FormField(label: "在下面输入「删除」两个字，再点删除", prompt: "删除", text: $word, focus: true)
        }
    }
}

struct V3RestoreSheet: View {
    let id: UUID
    @Environment(V3State.self) private var state
    var body: some View {
        let b = state.backups.first { $0.id == id }
        V3SheetBox(width: 480, title: "恢复这份备份吗？", sub: b.map { "\($0.title)，里面有 \($0.ledger.book.counts.entries) 笔" } ?? "", primary: "恢复", canSave: b != nil, save: {
            state.closeSheet()
            state.restore(id)
        }) {
            V3ConfirmBody(text: "现在的账本会先另存一份「恢复前」的备份，再换成这一份。")
        }
    }
}

struct V3BaseCurrencySheet: View {
    @Environment(V3State.self) private var state
    var body: some View {
        V3SheetBox(width: 480, title: "主币种", sub: "试用版只有欧元", primary: "知道了", save: { state.closeSheet() }) {
            V3ConfirmBody(text: "试用版的示例数据全是欧元，先不能换。")
        }
    }
}

struct V3FeedbackSheet: View {
    @Environment(V3State.self) private var state
    @Environment(\.openURL) private var openURL
    @State private var kind = 0
    @State private var text = ""
    @State private var withInfo = true
    @FocusState private var focused: Bool
    static let kinds = ["遇到问题", "提个想法", "别的"]

    private var bodyText: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return withInfo ? "\(t)\n\n——\n夏夏账本 界面 v3 试用版 · Mac · \(os)" : t
    }

    var body: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        V3SheetBox(width: 580, title: "反馈问题 / 提个想法", foot: "会打开你的邮件 app，内容已经填好，按发送就行。", primary: "用邮件发送", canSave: !empty,
                   save: {
                       var c = URLComponents()
                       c.scheme = "mailto"; c.path = FeedbackSheet.address
                       c.queryItems = [URLQueryItem(name: "subject", value: "夏夏账本 · \(Self.kinds[kind])"), URLQueryItem(name: "body", value: bodyText)]
                       if let url = c.url { openURL(url) }
                       state.closeSheet()
                       state.say("打开邮件了，按发送就行")
                   },
                   extra: { Button("复制下来") { state.copy("发到 \(FeedbackSheet.address)\n\(bodyText)") }.buttonStyle(.v3(.ghost)).disabled(empty) }) {
            V3FormPick(label: "", options: Self.kinds, pick: $kind)
            VStack(alignment: .leading, spacing: 5) {
                V3Label("是什么", size: 12.5, weight: .bold)
                TextEditor(text: $text).font(V3.font(14.5, .semibold)).foregroundStyle(V3.ink).scrollContentBackground(.hidden).focused($focused)
                    .padding(10).frame(height: 120)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(V3.ink, lineWidth: 2)))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty { Text("在哪一页、点了什么、看到了什么？").font(V3.font(14.5, .semibold)).foregroundStyle(V3.ink2.opacity(0.6)).padding(.horizontal, 15).padding(.vertical, 10).allowsHitTesting(false) }
                    }
                    .accessibilityLabel("要说的话")
            }
            V3FormSwitch(title: "带上版本和系统信息", sub: "只有 app 版本、macOS 版本，不会带上账本里的任何东西", on: $withInfo)
        }
        .onAppear { focused = true }
    }
}

struct V3BooksSheet: View {
    @Environment(V3State.self) private var state
    @State private var life = ""
    @State private var shop = ""
    var body: some View {
        V3SheetBox(width: 520, title: "管理账本", hint: "试用版只有这两本，不能新建和删除。", primary: "存好", save: {
            var ok = true
            if life != state.book.lifeName { ok = state.change("改好了：\(state.book.lifeName) → \(life)") { try $0.renameBook(.life, to: life) } }
            if ok, state.showsBiz, shop != state.book.shopName { ok = state.change("改好了：\(state.book.shopName) → \(shop)") { try $0.renameBook(.biz, to: shop) } }
            if ok { state.closeSheet() }
        }) {
            V3FormField(label: "🏠 生活这本叫什么", prompt: "生活", text: $life, focus: true)
            if state.showsBiz { V3FormField(label: "🏪 生意这本叫什么", prompt: "晴空小花店", text: $shop) }
        }
        .onAppear { life = state.book.lifeName; shop = state.book.shopName }
    }
}

struct V3AccountsSheet: View {
    @Environment(V3State.self) private var state
    @State private var pick = ""
    @State private var name = ""
    @State private var amount = ""
    /// 这次管的是哪一边的账户：生活和店里的分开管，不混在一张单子里。
    @State private var side: TrialBook.Side = .life

    /// 把正在改的这个账户存好（没改就不动）。存不成返回 false，停在原地。
    private func commit() -> Bool {
        guard let a = state.book.account(pick) else { return true }
        guard let m = V3Form.amountOrZero(amount) else { state.fail("这个数我没看懂。写成 1500 或者 1.500,00 这样就行。"); return false }
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard clean != a.name || m != a.balance else { return true }
        guard state.change("存好了：\(clean)", kind: .account, { try $0.editAccount(pick, newName: name, balance: m, secret: a.kind == .secret) }) else { return false }
        pick = clean
        return true
    }

    var body: some View {
        let accounts = state.book.accounts(on: side)
        let a = accounts.first { $0.name == pick }
        let m = V3Form.amountOrZero(amount)
        let n = state.book.entries.filter { $0.account == pick }.count
        V3SheetBox(width: 820, title: side == .biz ? "管理店里的账户" : "管理账户", primary: "完成", single: true,
                   save: { if commit() { state.closeSheet() } }) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(accounts.prefix(10)) { acc in
                        Button { if commit() { load(acc) } } label: {
                            HStack(spacing: 8) {
                                Text(acc.emoji)
                                Text(acc.name).font(V3.font(14, .bold)).foregroundStyle(V3.ink).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Self.kindName(acc)).font(V3.font(12, .regular)).foregroundStyle(V3.ink2)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(acc.name == pick ? V3.soft : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button("＋ 加一个账户") {
                        guard commit() else { return }
                        if side == .biz { state.open(.shopAccount) } else { state.closeSheet(); state.showAddAccount = true }
                    }
                    .buttonStyle(.v3(.ghost, .small)).padding(.top, 6)
                }
                .frame(width: 290)
                VStack(alignment: .leading, spacing: 12) {
                    V3FormField(label: "叫什么", text: $name)
                    V3FormField(label: a?.kind == .debt ? "现在欠多少" : "现在里面有多少", prompt: "0", text: $amount)
                    if m == nil { V3Label("这个数我没看懂。写成 1500 或者 1.500,00 这样就行。", color: V3.red, weight: .semibold) }
                    if let a, a.kind != .secret {
                        let pinned = state.book.isPinned(a.name)
                        VStack(alignment: .leading, spacing: 10) {
                            V3FormSwitch(title: "置顶成卡片", on: Binding(get: { pinned }, set: { v in
                                state.change(v ? "置顶了：\(a.name)" : "取消置顶了：\(a.name)", kind: .account) { try $0.setPinned(a.name, v) }
                            }))
                            if pinned {
                                HStack(spacing: 6) {
                                    Text("卡片底色").font(V3.font(14.5, .bold))
                                    Spacer()
                                    ForEach(Array(V3CardLook.all.enumerated()), id: \.offset) { k, look in
                                        Button {
                                            state.change("换好了：\(a.name)的卡片改成\(look.name)", kind: .account) { try $0.setCardStyle(a.name, k) }
                                        } label: {
                                            Circle().fill(LinearGradient(colors: [look.a, look.b], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .frame(width: 24, height: 24)
                                                .overlay(Circle().strokeBorder(V3.ink, lineWidth: a.cardLook == k ? 2.5 : 1))
                                        }
                                        .buttonStyle(.plain).help("卡片底色：\(look.name)").accessibilityLabel("卡片底色：\(look.name)")
                                    }
                                }
                            }
                        }
                    }
                    V3Divider()
                    HStack {
                        V3Label(n > 0 ? "里面还有 \(n) 笔流水" : "", size: 12.5)
                        Spacer()
                        Button("删除这个账户") {
                            if state.change("删掉了账户：\(pick)", kind: .remove, { try $0.removeAccount(pick) }), let first = state.book.accounts(on: side).first { load(first) }
                        }
                        .buttonStyle(.v3(.danger, .small)).disabled(n > 0).help(n > 0 ? "先把流水删掉或改到别的账户才能删" : "删错了能撤销")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            if let n = state.accountFocus, let a = state.book.account(n) { side = a.side; load(a); state.accountFocus = nil }
            else {
                side = state.side == .biz ? .biz : .life
                if let first = state.book.accounts(on: side).first { load(first) }
            }
        }
    }

    private func load(_ a: V3State.Account) {
        pick = a.name; name = a.name; amount = V3Form.plain(a.balance)
    }

    static func kindName(_ a: V3State.Account) -> String {
        switch a.kind {
        case .own: a.block == .goal ? "目标" : a.block == .emergency ? "储蓄" : "自己的"
        case .shop: "放钱的"
        case .debt: "欠的"
        case .lent: "借出去的"
        case .secret: "私房钱 · 藏着"
        }
    }
}

struct V3CategoriesSheet: View {
    @Environment(V3State.self) private var state
    @State private var pick = ""
    @State private var name = ""
    @State private var fresh = ""
    static let icons = "☕ 🍵 🧋 🥐 🍰 🍺 🍷 🥤 🍜 🍕 🍔 🥗 🛒 🧺 🚇 🚕 ⛽ 🏠 💡 📱 🎬 🎵 🎮 💊 🐶 🎁 👕 ✂️ 📚 ✈️".split(separator: " ").map(String.init)

    var body: some View {
        let cats = state.book.categories
        let c = cats.first { $0.name == pick }
        let target = name.trimmingCharacters(in: .whitespaces)
        let merge = target != pick && cats.contains { $0.name == target }
        V3SheetBox(width: 820, title: "管理分类", hint: "改成一个已有的名字，就是把两个分类并成一个，流水一起改。", primary: "完成", save: { state.closeSheet() }) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(cats.prefix(14).enumerated()), id: \.offset) { _, cat in
                        Button { pick = cat.name; name = cat.name } label: {
                            HStack(spacing: 8) {
                                V3Ico(emoji: cat.emoji, size: 24)
                                Text(cat.name).font(V3.font(14, .bold)).foregroundStyle(V3.ink).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(state.book.entryCount(category: cat.name)) 笔").font(V3.font(12, .regular)).foregroundStyle(V3.ink2)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(cat.name == pick ? V3.soft : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 6) {
                        V3Field(prompt: "新分类叫什么", text: $fresh, size: 13) { add() }
                        Button("新建") { add() }.buttonStyle(.v3(.ghost, .small)).disabled(fresh.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 6)
                }
                .frame(width: 290)
                VStack(alignment: .leading, spacing: 12) {
                    if let c {
                        HStack(alignment: .bottom, spacing: 10) {
                            V3FormField(label: "名字", text: $name)
                            Button(merge ? "并进「\(target)」" : "改名") {
                                if state.change(merge ? "并好了：\(pick) → \(target)" : "改好了：\(pick) → \(target)", kind: .categorize, { try $0.editCategory(pick, newName: name, emoji: c.emoji) }) { pick = target }
                            }
                            .buttonStyle(.v3(.primary, .small)).disabled(target.isEmpty || target == pick).padding(.bottom, 4)
                        }
                        V3Label("给「\(pick)」换图标", size: 12.5, weight: .bold)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                            ForEach(Self.icons, id: \.self) { e in
                                Button {
                                    state.change("换好了：\(pick) 用 \(e)", kind: .categorize) { try $0.editCategory(pick, newName: pick, emoji: e) }
                                } label: {
                                    Text(e).font(.system(size: 20)).frame(maxWidth: .infinity).frame(height: 36)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(c.emoji == e ? V3.goodBG : V3.bg)
                                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.emoji == e ? V3.ink : .clear, lineWidth: 2)))
                                }
                                .buttonStyle(V3SinkStyle(depth: 2)).accessibilityLabel("换成 \(e)")
                            }
                        }
                    } else {
                        V3Label("点左边一个分类。")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { if let first = state.book.categories.first { pick = first.name; name = first.name } }
    }

    private func add() {
        let n = fresh.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if state.change("新建了分类：\(n)", kind: .categorize, { try $0.addCategory(emoji: "🏷", name: n) }) { pick = n; name = n; fresh = "" }
    }
}
#endif
