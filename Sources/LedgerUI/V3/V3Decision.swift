#if os(macOS)
import AppKit
import FinanceCore
import SwiftUI

// 决策模型（OpenRouter）在 app 这一层的部分：真的去发请求、设置存哪、D1「要不要提醒」什么时候跑、结果怎么出卡。
// 怎么拼请求、怎么读概率、怎么和临界点比、退回规则，都在 FinanceCore（Decisions.swift、ReminderDecision.swift）。
// 密钥只在钥匙串里；只在发请求的那一下读出来放进请求头，不显示、不进日志、不进偏好设置。

// 发请求的那一层和客户端在 FinanceCore/OpenRouterClient.swift（Mac 和 iPhone 共用），这里只是接到界面上。
typealias V3Transport = OpenRouterTransport
typealias V3OfflineTransport = OfflineOpenRouterTransport

extension V3State {
    static let openRouterAccount = AIKeyProvider.openrouter.rawValue
    private static var underTest: Bool { NSClassFromString("XCTestCase") != nil }
    static func defaultTransport() -> V3Transport { underTest ? OfflineOpenRouterTransport() : URLSessionOpenRouterTransport() }

    /// 填了 OpenRouter 的密钥没有。
    var hasOpenRouterKey: Bool { _ = keyRevision; return keyStore.has(Self.openRouterAccount) }
    /// 给人看的样子：只露最后 4 位。
    var openRouterKeyMasked: String { keyStore.read(Self.openRouterAccount).map(AIKeyRules.masked) ?? "" }

    /// 问夏夏现在走哪条路。
    enum ChatRoute: String, CaseIterable { case auto, openRouter, local
        var title: String { self == .auto ? "自动" : self == .openRouter ? "OpenRouter" : "连着的 AI" }
    }
    /// 现在实际走的是哪条：填了密钥、选了聊天模型、又没手动切走，就是 OpenRouter。
    var chatUsesOpenRouter: Bool { hasOpenRouterKey && !decisionPrefs.chatModel.isEmpty && decisionPrefs.route != .local }
    var chatRouteLine: String { chatUsesOpenRouter ? "OpenRouter · \(decisionPrefs.chatModel)" : (ai ?? "\(prefs.xiaName)自带的") }

    func saveDecisionPrefs() {
        guard !Self.underTest else { return }
        let d = UserDefaults.standard
        d.set(decisionPrefs.decisionModel, forKey: "xiaxia.v3.decide.model")
        d.set(decisionPrefs.chatModel, forKey: "xiaxia.v3.decide.chatModel")
        d.set(decisionPrefs.route.rawValue, forKey: "xiaxia.v3.decide.route")
        d.set(decisionPrefs.thresholds, forKey: "xiaxia.v3.decide.thresholds")
    }

    func threshold(_ id: String) -> Double { decisionPrefs.thresholds[id] ?? Decisions.find(id)?.defaultThreshold ?? 0.7 }
    func setThreshold(_ id: String, _ x: Double) { decisionPrefs.thresholds[id] = Decisions.cleanThreshold(x); saveDecisionPrefs() }

    func setModel(decision: String? = nil, chat: String? = nil) {
        do {
            if let decision { decisionPrefs.decisionModel = try OpenRouterWire.cleanModel(decision) }
            if let chat { decisionPrefs.chatModel = try OpenRouterWire.cleanModel(chat) }
            saveDecisionPrefs()
        } catch let e as TrialError { fail(e.message) } catch {}
    }

    /// 问一次决策模型：先要「是 / 否」那个字的概率；模型给不出概率，就换成让它回一小段 JSON 再问一次。
    func askDecision(_ d: Decision, card: String) async -> Result<Double, OpenRouterWire.Failure> {
        guard let key = keyStore.read(Self.openRouterAccount) else { return .failure(.badKey) }
        return await OpenRouterClient(transport: transport).askDecision(d, card: card, model: decisionPrefs.decisionModel, key: key)
    }

    /// 设置里的「试一下」：用「明显该提醒」那组示例问一次，把结果写成一句话。
    func tryDecision() async {
        guard let d = Decisions.find(Decisions.remind) else { return }
        guard hasOpenRouterKey else { decisionTry = "先填密钥。没连时按固定规则判断。"; return }
        decisionTrying = true; decisionTry = ""
        let r = await askDecision(d, card: ReminderDecision.sample(.yes).card)
        decisionTrying = false
        switch r {
        case .success(let p):
            decisionTry = DecisionMath.decide(probability: p, threshold: threshold(d.id), fallbackYes: false, fallbackReason: "").line(yesDoes: "会提醒", noDoes: "不提醒")
        case .failure(let f):
            decisionTry = f.message
        }
    }

    /// 从 OpenRouter 拿模型清单（公开的，不用密钥）。
    func loadModels() async {
        guard models.isEmpty, !modelsLoading else { return }
        modelsLoading = true
        defer { modelsLoading = false }
        models = await OpenRouterClient(transport: transport).models()
    }

    /// 用聊天模型回一句（问夏夏、写提醒那一句）。带上 app 算好的那几个数，账本原文不整份发。失败返回 nil，外面照旧走原来的路。
    func askChatModel(_ question: String) async -> String? {
        guard chatUsesOpenRouter, let key = keyStore.read(Self.openRouterAccount) else { return nil }
        return await OpenRouterClient(transport: transport).chat(question, numbers: book.numbersCard, model: decisionPrefs.chatModel, key: key)
    }

    // MARK: D1 要不要提醒

    /// 今天已经主动提醒过几句。
    var remindedToday: Int { book.reminderLog.filter { $0.daysAgo == 0 && $0.shown }.count }

    /// 跑一次「要不要提醒」。什么时候跑：每记一笔、每次导入、每天 9 点（没开着就下次打开时补一次）。
    func runReminderCheck(newEntries: [String] = []) async {
        guard let d = Decisions.find(Decisions.remind) else { return }
        let s = book.reminderSituation(newEntries: newEntries, prefs: book.memos.filter { $0.kind == .rule }.flatMap(\.lines).prefix(3).map { $0 })
        var p: Double?
        var why = "没连决策模型"
        if hasOpenRouterKey {
            switch await askDecision(d, card: s.card) {
            case .success(let x): p = x
            case .failure(let f): why = f.message   // 失败不弹错，退回固定规则
            }
        }
        switch ReminderDecision.resolve(s, probability: p, threshold: threshold(d.id), saidToday: remindedToday, fallbackReason: why) {
        case .quiet: break
        case .later(let t, _):
            patch { $0.reminderLog.append(.init(key: t.key, daysAgo: 0, shown: false, text: t.sentence)) }
        case .show(let t, _):
            // 这一句：连着聊天模型就让它写，写不出来就用固定说法
            let text = await askChatModel("把下面这件事用一句大白话提醒我，20 个字左右，不要客套：\(t.sentence)") ?? t.sentence
            patch { $0.reminderLog.append(.init(key: t.key, daysAgo: 0, shown: true, text: text)) }
            reminder = V3Reminder(key: t.key, kind: t.kind.rawValue, text: text)
            lastSaid = (text, Date())
            if !chatOpen, sheet == nil { withAnimation(.easeOut(duration: 0.22)) { sayCardID = "remind:" + t.key; sayUnreadID = nil } }
        }
    }

    /// 卡上的「别再提醒这个」：这一类以后都不提。能在设置里重新打开。
    func muteReminder(_ kind: String) {
        let title = ReminderSituation.Topic.Kind(rawValue: kind)?.title ?? "这一类"
        change("好，「\(title)」以后不提醒了") { $0.mutedReminders.insert(kind) }
        withAnimation(.easeIn(duration: 0.18)) { reminder = nil; sayCardID = nil }
    }

    /// 每天 9 点跑一次；今天还没跑过、现在又过了 9 点，就马上补一次。
    func startDailyReminder() {
        guard !Self.underTest else { return }
        dailyTask?.cancel()
        dailyTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let cal = Calendar.current, now = Date()
                let today9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
                let key = "xiaxia.v3.decide.lastDaily"
                let last = UserDefaults.standard.object(forKey: key) as? Date
                if now >= today9, last.map({ !cal.isDate($0, inSameDayAs: now) }) ?? true {
                    UserDefaults.standard.set(now, forKey: key)
                    await self?.runReminderCheck()
                }
                let next = now >= today9 ? cal.date(byAdding: .day, value: 1, to: today9) ?? now.addingTimeInterval(86_400) : today9
                try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 60)))
            }
        }
    }
}

/// 决策模型的几样设置（不含密钥）。
struct V3DecisionPrefs {
    var decisionModel = OpenRouterWire.defaultDecisionModel
    var chatModel = OpenRouterWire.defaultChatModel
    var route = V3State.ChatRoute.auto
    var thresholds: [String: Double] = [:]

    static func load() -> V3DecisionPrefs {
        var p = V3DecisionPrefs()
        guard NSClassFromString("XCTestCase") == nil else { return p }
        let d = UserDefaults.standard
        if let m = d.string(forKey: "xiaxia.v3.decide.model"), !m.isEmpty { p.decisionModel = m }
        if let m = d.string(forKey: "xiaxia.v3.decide.chatModel"), !m.isEmpty { p.chatModel = m }
        if let r = d.string(forKey: "xiaxia.v3.decide.route").flatMap(V3State.ChatRoute.init(rawValue:)) { p.route = r }
        if let t = d.dictionary(forKey: "xiaxia.v3.decide.thresholds") as? [String: Double] { p.thresholds = t }
        return p
    }
}

/// 夏夏主动提醒的那一句。
struct V3Reminder: Equatable {
    var key: String
    var kind: String
    var text: String
}

// MARK: - 设置里的「决策模型」

struct V3SetDecisionPage: View {
    @Environment(V3State.self) private var state
    @State private var decisionModel = ""
    @State private var chatModel = ""
    @State private var search = ""
    @State private var picking = false

    var body: some View {
        let has = state.hasOpenRouterKey
        V3SetColumn {
            V3SetGroup(title: "OpenRouter", note: "密钥只存在这台 Mac 的钥匙串里。") {
                V3SetRow(title: "密钥", detail: has ? state.openRouterKeyMasked : "没连时按固定规则判断", line: false) {
                    HStack(spacing: 8) {
                        V3Tag(text: has ? "已填" : "没填", tone: has ? .green : .blue)
                        Button(has ? "换" : "填…") { state.open(.apiKey) }.buttonStyle(.v3(has ? .ghost : .primary, .small))
                        if has { Button("删") { state.deleteAPIKey() }.buttonStyle(.v3(.danger, .small)) }
                    }
                }
                V3SetRow(title: "决策用的模型") {
                    V3Field(prompt: OpenRouterWire.defaultDecisionModel, text: $decisionModel, size: 13.5) { state.setModel(decision: decisionModel) }.frame(width: 300)
                }
                V3SetRow(title: "聊天用的模型") {
                    HStack(spacing: 8) {
                        V3Field(prompt: OpenRouterWire.defaultChatModel, text: $chatModel, size: 13.5) { state.setModel(chat: chatModel) }.frame(width: 228)
                        Button("挑…") { picking = true; Task { await state.loadModels() } }.buttonStyle(.v3(.ghost, .small))
                            .popover(isPresented: $picking, arrowEdge: .bottom) { modelPicker }
                    }
                }
                V3SetRow(title: "问夏夏用哪个", detail: state.chatRouteLine) {
                    V3SetMenu(options: V3State.ChatRoute.allCases.map(\.title),
                              pick: Binding(get: { V3State.ChatRoute.allCases.firstIndex(of: state.decisionPrefs.route) ?? 0 },
                                            set: { state.decisionPrefs.route = V3State.ChatRoute.allCases[$0]; state.saveDecisionPrefs() }))
                }
                V3SetRow(title: "试一下", detail: state.decisionTry) {
                    HStack(spacing: 8) {
                        if state.decisionTrying { ProgressView().controlSize(.small) }
                        Button("问一次") { state.setModel(decision: decisionModel, chat: chatModel); Task { await state.tryDecision() } }
                            .buttonStyle(.v3(.primary, .small)).disabled(state.decisionTrying)
                    }
                }
            }
            V3SetGroup(title: "每个决策的临界点", grow: true) {
                ForEach(Array(Decisions.all.enumerated()), id: \.element.id) { i, d in
                    HStack(spacing: 10) {
                        Text(d.id).font(V3.num(12.5, .heavy)).foregroundStyle(V3.ink2).frame(width: 24, alignment: .leading)
                        Text(d.name).font(V3.font(14, .bold)).foregroundStyle(V3.ink).lineLimit(1).frame(width: 150, alignment: .leading)
                        Slider(value: Binding(get: { state.threshold(d.id) }, set: { state.setThreshold(d.id, $0) }), in: 0.05...0.95, step: 0.05)
                            .controlSize(.small).disabled(!d.wired)
                        Text("\(Int((state.threshold(d.id) * 100).rounded()))%").font(V3.num(13.5, .heavy)).foregroundStyle(V3.navy).frame(width: 42, alignment: .trailing)
                        if d.wired { V3Tag(text: "在用", tone: .green) } else { V3Tag(text: "以后", tone: .blue) }
                    }
                    .padding(.vertical, 5).opacity(d.wired ? 1 : 0.5)
                    .help("问题：\(d.question)\n没连时：\(d.fallback)")
                    if i < Decisions.all.count - 1 { V3Divider() }
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { decisionModel = state.decisionPrefs.decisionModel; chatModel = state.decisionPrefs.chatModel }
    }

    /// 从 OpenRouter 的模型清单里挑一个聊天用的，能搜。
    private var modelPicker: some View {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = state.models.filter { q.isEmpty || $0.lowercased().contains(q) }
        return VStack(alignment: .leading, spacing: 8) {
            V3Field(prompt: "搜模型名", text: $search, size: 13.5)
            if state.modelsLoading { ProgressView().controlSize(.small) }
            else if state.models.isEmpty { V3Label("清单没拿到，直接把模型名填进去也行。") }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(hits.prefix(200), id: \.self) { m in
                        Button { chatModel = m; state.setModel(chat: m); picking = false } label: {
                            Text(m).font(V3.font(13, .semibold)).foregroundStyle(V3.ink).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 260)
        }
        .padding(14).frame(width: 360)
    }
}
#endif
