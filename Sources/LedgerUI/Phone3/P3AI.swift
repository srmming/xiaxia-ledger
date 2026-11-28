#if os(iOS)
import FinanceCore
import SwiftUI

// 夏夏的 AI：手机上只走 OpenRouter（ming 2026-11-28）。发请求、钥匙串都用 FinanceCore 里和 Mac 共用的那一套，
// 这里只是 iPhone 的设置页和接到聊天上。设置的名字和 Mac 用同几个（xiaxia.v3.decide.*），以后一起同步。
// 没填密钥时夏夏照旧按固定规则回话。

@MainActor @Observable
final class P3AI {
    static let account = AIKeyProvider.openrouter.rawValue
    private let store: SecretStore = NSClassFromString("XCTestCase") != nil
        ? MemorySecretStore() : KeychainSecretStore(service: "com.srmming.xiaxia-ledger.phone.ai-key", label: "夏夏账本 iPhone · OpenRouter 密钥")
    private let client = OpenRouterClient(transport: URLSessionOpenRouterTransport())
    private let defaults = UserDefaults.standard

    var hasKey = false
    var chatModel: String
    var decisionModel: String
    var threshold: Double

    init() {
        chatModel = defaults.string(forKey: "xiaxia.v3.decide.chatModel").flatMap { $0.isEmpty ? nil : $0 } ?? OpenRouterWire.defaultChatModel
        decisionModel = defaults.string(forKey: "xiaxia.v3.decide.model").flatMap { $0.isEmpty ? nil : $0 } ?? OpenRouterWire.defaultDecisionModel
        threshold = (defaults.dictionary(forKey: "xiaxia.v3.decide.thresholds") as? [String: Double])?[Decisions.remind]
            ?? Decisions.find(Decisions.remind)?.defaultThreshold ?? 0.7
        hasKey = store.has(Self.account)
    }

    func saveKey(_ raw: String) throws {
        let key = try AIKeyRules.cleanKey(raw)
        try store.save(key, for: Self.account)
        hasKey = true
    }

    func deleteKey() throws {
        try store.delete(Self.account)
        hasKey = false
    }

    func setModels(chat: String, decision: String) throws {
        chatModel = try OpenRouterWire.cleanModel(chat)
        decisionModel = try OpenRouterWire.cleanModel(decision)
        defaults.set(chatModel, forKey: "xiaxia.v3.decide.chatModel")
        defaults.set(decisionModel, forKey: "xiaxia.v3.decide.model")
    }

    func setThreshold(_ x: Double) {
        threshold = Decisions.cleanThreshold(x)
        var all = defaults.dictionary(forKey: "xiaxia.v3.decide.thresholds") as? [String: Double] ?? [:]
        all[Decisions.remind] = threshold
        defaults.set(all, forKey: "xiaxia.v3.decide.thresholds")
    }

    /// 问一句：带上 app 算好的几个数（不发整本账）。没密钥或没问到返回 nil。
    func chat(_ question: String, numbers: String) async -> String? {
        guard hasKey, let key = store.read(Self.account) else { return nil }
        return await client.chat(question, numbers: numbers, model: chatModel, key: key)
    }

    var routeLine: String { hasKey ? "OpenRouter · \(chatModel)" : "没填密钥，夏夏按固定规则回话" }
}

struct P3AIPage: View {
    @Environment(P3State.self) private var state
    @State private var key = ""
    @State private var chatModel = ""
    @State private var decisionModel = ""

    var body: some View {
        let ai = state.ai
        P3SubPage(title: "夏夏的 AI") {
            VStack(alignment: .leading, spacing: 6) {
                P3Label("现在")
                Text(ai.routeLine).font(P3.font(15, .bold)).foregroundStyle(ai.hasKey ? P3.green : P3.ink2)
            }
            .p3Card(h: 16, v: 12, radius: 18)

            VStack(alignment: .leading, spacing: 10) {
                P3Label("OpenRouter 密钥")
                if ai.hasKey {
                    HStack {
                        Text("已填好，只存在这台手机的钥匙串里").font(P3.font(14, .semibold)).foregroundStyle(P3.ink)
                        Spacer()
                        Button("删掉") { do { try ai.deleteKey(); state.say("密钥删掉了") } catch { state.fail("没删掉，再试一次") } }
                            .buttonStyle(.p3(.danger, .small))
                    }
                }
                SecureField(ai.hasKey ? "换一把：粘新的密钥" : "粘贴 sk-or-… 开头的密钥", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .p3Field(fill: P3.bg)
                Button(ai.hasKey ? "换成这把" : "存进钥匙串") {
                    do { try ai.saveKey(key); key = ""; state.say("存好了，夏夏现在用 OpenRouter") }
                    catch let e as TrialError { state.fail(e.message) } catch { state.fail("没存进钥匙串，再试一次") }
                }
                .buttonStyle(.p3(.primary, .wide))
                .disabled(key.isEmpty)
                Text("密钥不进账本、不进日志，存好以后界面上不再显示。").font(P3.font(12, .regular)).foregroundStyle(P3.ink2)
            }
            .p3Card(h: 16, v: 14, radius: 18)

            VStack(alignment: .leading, spacing: 10) {
                P3Label("聊天用的模型")
                TextField(OpenRouterWire.defaultChatModel, text: $chatModel).textInputAutocapitalization(.never).autocorrectionDisabled().p3Field(fill: P3.bg)
                P3Label("拿主意用的模型（要不要提醒你这类是/否的事）")
                TextField(OpenRouterWire.defaultDecisionModel, text: $decisionModel).textInputAutocapitalization(.never).autocorrectionDisabled().p3Field(fill: P3.bg)
                Button("用这两个") {
                    do { try ai.setModels(chat: chatModel, decision: decisionModel); state.say("换好了") }
                    catch let e as TrialError { state.fail(e.message) } catch { state.fail("模型名字写成 厂家/模型 这样") }
                }
                .buttonStyle(.p3(.ghost, .wide))
            }
            .p3Card(h: 16, v: 14, radius: 18)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    P3Label("多有把握才提醒你")
                    Spacer()
                    Text("\(Int((ai.threshold * 100).rounded())) %").font(P3.num(16, .heavy)).foregroundStyle(P3.navy)
                }
                Slider(value: Binding(get: { ai.threshold }, set: { ai.setThreshold($0) }), in: 0.05...0.95, step: 0.05).tint(P3.navy)
                Text("拿主意的模型觉得「该提醒」的把握超过这个数才说，默认 70 %。").font(P3.font(12, .regular)).foregroundStyle(P3.ink2)
            }
            .p3Card(h: 16, v: 14, radius: 18)
        }
        .onAppear { chatModel = ai.chatModel; decisionModel = ai.decisionModel }
    }
}
#endif
