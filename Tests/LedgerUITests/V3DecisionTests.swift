import FinanceCore
import XCTest
@testable import LedgerUI

/// 决策模型在 app 这一层：假的网络层、假的密钥，不发任何真请求。
@MainActor
final class V3DecisionTests: XCTestCase {
    /// 假的网络层：按顺序回准备好的东西，并把收到的请求记下来。
    final class FakeTransport: V3Transport, @unchecked Sendable {
        var replies: [Result<(String, Int), OpenRouterWire.Failure>]
        /// 专门的决策接口怎么回。默认是「这个模型不是决策模型」（400），这样就会换去聊天接口。
        var decisions: [Result<(String, Int), OpenRouterWire.Failure>] = []
        private(set) var sent: [(url: String, key: String?, body: [String: Any])] = []
        private(set) var decisionsSent: [[String: Any]] = []
        init(_ replies: [Result<(String, Int), OpenRouterWire.Failure>]) { self.replies = replies }
        func send(url: String, key: String?, body: Data?) async throws -> (Data, Int) {
            let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            if url == OpenRouterWire.decisionsEndpoint {
                decisionsSent.append(json)
                guard !decisions.isEmpty else { return (Data(#"{"error":{"code":400,"message":"model does not support decisions"}}"#.utf8), 400) }
                let (text, status) = try decisions.removeFirst().get()
                return (Data(text.utf8), status)
            }
            sent.append((url, key, json))
            guard !replies.isEmpty else { throw OpenRouterWire.Failure.noNetwork }
            let (text, status) = try replies.removeFirst().get()
            return (Data(text.utf8), status)
        }
    }

    private static func logprobs(yes: Double) -> String {
        #"{"choices":[{"message":{"content":"是"},"logprobs":{"content":[{"token":"是","logprob":\#(log(yes)),"top_logprobs":[{"token":"是","logprob":\#(log(yes))},{"token":"否","logprob":\#(log(1 - yes))}]}]}}]}"#
    }
    private static func chat(_ text: String) -> String { #"{"choices":[{"message":{"content":"\#(text)"}}]}"# }

    private func state(_ replies: [Result<(String, Int), OpenRouterWire.Failure>], key: Bool = true) -> (V3State, FakeTransport) {
        let s = V3State()
        s.onboardingStep = nil
        s.keyStore = MemorySecretStore()
        let t = FakeTransport(replies)
        s.transport = t
        if key { XCTAssertTrue(s.saveAPIKey("sk-demo-000-fake", provider: .openrouter)) }
        s.toast = nil
        return (s, t)
    }

    func testOfflineByDefaultUnderTests() async {
        let s = V3State()
        XCTAssertTrue(s.transport is V3OfflineTransport, "跑测试时默认连不上网，绝不会真的发请求")
        XCTAssertFalse(s.hasOpenRouterKey)
        XCTAssertEqual(s.decisionPrefs.decisionModel, "microsoft/microsoft-decision-1.1")
        XCTAssertEqual(s.decisionPrefs.chatModel, "deepseek/deepseek-v4.1-flash-1017")
        XCTAssertEqual(s.threshold("D1"), 0.70)
    }

    func testTryItShowsProbabilityOrAPlainError() async {
        let (s, t) = state([.success((Self.logprobs(yes: 0.83), 200))])
        XCTAssertEqual(s.openRouterKeyMasked, "••••••••fake", "只露最后 4 位")
        await s.tryDecision()
        XCTAssertEqual(s.decisionTry, "是的概率 83%，超过 70% → 会提醒")
        XCTAssertEqual(t.sent.count, 1)
        XCTAssertEqual(t.sent[0].url, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(t.sent[0].key, "sk-demo-000-fake")
        XCTAssertEqual(t.sent[0].body["logprobs"] as? Bool, true)
        XCTAssertFalse(s.decisionTry.contains("sk-demo"), "结果那句话里没有密钥")
        // 调高临界点：同一个概率就不提醒了
        s.setThreshold("D1", 0.9); t.replies = [.success((Self.logprobs(yes: 0.83), 200))]
        await s.tryDecision()
        XCTAssertEqual(s.decisionTry, "是的概率 83%，没到 90% → 不提醒")
        // 说人话的错误
        for (reply, text) in [(Result<(String, Int), OpenRouterWire.Failure>.success(("{}", 401)), "密钥不对，或者已经失效了"),
                              (.success(("{}", 404)), "模型名不对，OpenRouter 上没有这个模型"), (.failure(.noNetwork), "没连上网"), (.failure(.timeout), "等了 10 秒没回音")] {
            t.replies = [reply]
            await s.tryDecision()
            XCTAssertEqual(s.decisionTry, text)
        }
        // 没填密钥：不发请求
        let (n, nt) = state([], key: false)
        await n.tryDecision()
        XCTAssertEqual(n.decisionTry, "先填密钥。没连时按固定规则判断。")
        XCTAssertTrue(nt.sent.isEmpty)
    }

    func testDecisionModelGoesThroughTheDecisionsAPI() async {
        // 决策模型：走专门的接口，直接回「是」的概率和花了多少额度
        let (s, t) = state([])
        t.decisions = [.success((#"{"model":"microsoft/microsoft-decision-1.1","answers":{"answer":{"type":"noul","noul":0.87,"confidence":0.9}},"usage":{"input_tokens":210,"output_tokens":0,"cost":0.0000088}}"#, 200))]
        let r = await s.askDecision(Decisions.find("D1")!, card: ReminderDecision.sample(.yes).card)
        XCTAssertEqual((try? r.get())?.probability, 0.87)
        XCTAssertEqual((try? r.get())?.route, .decisions)
        XCTAssertEqual((try? r.get())?.cost, 0.0000088)
        XCTAssertTrue(t.sent.isEmpty, "决策接口答了，就不再去问聊天接口")
        let body = t.decisionsSent[0]
        XCTAssertEqual(body["model"] as? String, "microsoft/microsoft-decision-1.1")
        XCTAssertEqual(body["state"] as? String, ReminderDecision.sample(.yes).card)
        let q = ((body["questions"] as? [String: Any])?["answer"] as? [String: Any]) ?? [:]
        XCTAssertEqual(q["type"] as? String, "noul")
        XCTAssertEqual(q["instructions"] as? String, "现在值得主动提醒用户一句吗？")
        XCTAssertNotNil((q["criteria"] as? [String: String])?["true"]); XCTAssertNotNil((q["criteria"] as? [String: String])?["false"])
        // 模型不肯答：不算数，换聊天接口
        t.decisions = [.success((#"{"model":"x","answers":{"answer":{"type":"refusal"}},"usage":{"input_tokens":1,"output_tokens":0}}"#, 200))]
        t.replies = [.success((Self.logprobs(yes: 0.6), 200))]
        let r2 = await s.askDecision(Decisions.find("D1")!, card: "x")
        XCTAssertEqual((try? r2.get())?.route, .logprobs)
        // 密钥不对：马上停，不往下试
        t.decisions = [.success(("{}", 401))]
        let r3 = await s.askDecision(Decisions.find("D1")!, card: "x")
        if case .failure(let f) = r3 { XCTAssertEqual(f, .badKey) } else { XCTFail() }
        XCTAssertEqual(t.sent.count, 1)
        // 「三组都跑一遍」：两个模型、三组、各 2 次
        t.decisions = Array(repeating: .success((#"{"model":"m","answers":{"answer":{"type":"noul","noul":0.9}},"usage":{"input_tokens":1,"output_tokens":0,"cost":0.00001}}"#, 200)), count: 12)
        await s.runDecisionSamples()
        XCTAssertEqual(s.decisionReport.count, 2 + 6 + 1)
        XCTAssertEqual(s.decisionReport[0], "模型 deepseek/deepseek-v4.1-flash-1017")
        XCTAssertEqual(s.decisionReport[1], "  明显该说：90%（决策接口）、90%（决策接口） · 临界点 70%")
        XCTAssertEqual(s.decisionReport.last, "一共花了 0.000120 额度")
        XCTAssertFalse(s.decisionReport.joined().contains("sk-"), "结果里没有密钥")
    }

    func testFallsBackToJSONWhenModelHasNoLogprobs() async {
        // 第一次：模型说不支持 logprobs；第二次：换成 JSON 的问法
        let (s, t) = state([.success((#"{"error":{"message":"logprobs is not supported"}}"#, 400)), .success((Self.chat(#"{\"yes\": 0.41}"#), 200))])
        let r = await s.askDecision(Decisions.find("D1")!, card: "x")
        XCTAssertEqual((try? r.get())?.probability, 0.41)
        XCTAssertEqual((try? r.get())?.route, .json)
        XCTAssertEqual(t.sent.count, 2)
        XCTAssertNil(t.sent[1].body["logprobs"]); XCTAssertNotNil(t.sent[1].body["response_format"])
        // 回来的里面没带概率：也换 JSON 再问
        let (s2, t2) = state([.success((Self.chat("是"), 200)), .success((Self.chat(#"{\"yes\": 0.9}"#), 200))])
        let r2 = await s2.askDecision(Decisions.find("D1")!, card: "x")
        XCTAssertEqual((try? r2.get())?.probability, 0.9); XCTAssertEqual(t2.sent.count, 2)
    }

    /// 把示例账本摆成「房租 3 天后扣、日常卡不够」的样子。
    private func makeShort(_ s: V3State) {
        s.patch { b in
            if let i = b.accounts.firstIndex(where: { $0.name == "日常卡" }) { b.accounts[i].balance = Money(cents: 412_60) }
            b.upcoming = [.init(emoji: "🏠", name: "房租", meta: "11 月 21 日 · 3 天后", amount: Money(cents: 650_00))]
        }
    }

    func testReminderShowsOnlyWhenModelSaysYes() async {
        // 概率高：出卡；那一句交聊天模型写
        let (s, t) = state([.success((Self.logprobs(yes: 0.91), 200)), .success((Self.chat("房租 3 天后扣，日常卡还差 237 €，先挪点钱过去。"), 200))])
        makeShort(s)
        await s.runReminderCheck(newEntries: ["餐饮 48,00 €"])
        XCTAssertEqual(s.reminder?.kind, "shortBalance")
        XCTAssertEqual(s.reminder?.text, "房租 3 天后扣，日常卡还差 237 €，先挪点钱过去。")
        XCTAssertEqual(s.sayCardID, "remind:shortBalance:房租")
        XCTAssertEqual(s.remindedToday, 1)
        let card = ((t.sent[0].body["messages"] as? [[String: String]])?[1]["content"]) ?? ""
        XCTAssertTrue(card.contains("新记的：餐饮 48,00 €")); XCTAssertTrue(card.contains("（不够）"))
        XCTAssertEqual(t.sent[1].body["model"] as? String, s.decisionPrefs.chatModel)
        // 同一天再跑：不再出第二张卡（一天最多 1 条；同一件事 3 天内也不重复），只存着
        t.replies = [.success((Self.logprobs(yes: 0.95), 200))]
        s.reminder = nil; s.sayCardID = nil
        await s.runReminderCheck()
        XCTAssertNil(s.reminder)
        XCTAssertEqual(s.remindedToday, 1)
    }

    func testReminderStaysQuietBelowThresholdAndFallsBackOnFailure() async {
        // 概率不到临界点：不说，哪怕固定规则会说
        let (s, _) = state([.success((Self.logprobs(yes: 0.40), 200))])
        makeShort(s)
        await s.runReminderCheck()
        XCTAssertNil(s.reminder)
        // 调用失败：不弹错，退回固定规则 → 余额不够扣款要说；没连聊天模型就用固定说法
        let (f, _) = state([.failure(.timeout)])
        makeShort(f)
        await f.runReminderCheck()
        XCTAssertEqual(f.reminder?.text, "3 天后要扣房租 650,00 €，日常卡里只有 412,60 €，还差 237,40 €。")
        XCTAssertNil(f.toast, "失败不弹错")
        // 没填密钥：不发请求，按固定规则
        let (n, nt) = state([], key: false)
        makeShort(n)
        await n.runReminderCheck()
        XCTAssertEqual(n.reminder?.kind, "shortBalance"); XCTAssertTrue(nt.sent.isEmpty)
        // 示例账本原样（钱够）：固定规则不说
        let (q, _) = state([], key: false)
        await q.runReminderCheck()
        XCTAssertNil(q.reminder)
        // 「别再提醒这个」：这一类以后不提
        n.muteReminder("shortBalance")
        XCTAssertNil(n.reminder)
        XCTAssertTrue(n.book.mutedReminders.contains("shortBalance"))
        n.patch { $0.reminderLog = [] }
        await n.runReminderCheck()
        XCTAssertNil(n.reminder, "关掉的那一类不再出卡")
    }

    func testChatGoesToOpenRouterFirstAndSendsOnlyComputedNumbers() async {
        let (s, t) = state([.success((Self.chat("还能花 976 €，省着点够用。"), 200))])
        XCTAssertTrue(s.chatUsesOpenRouter)
        XCTAssertEqual(s.chatRouteLine, "OpenRouter · deepseek/deepseek-v4.1-flash-1017")
        let a = await s.askChatModel("这个月还能花多少")
        XCTAssertEqual(a, "还能花 976 €，省着点够用。")
        let sys = ((t.sent[0].body["messages"] as? [[String: String]])?[0]["content"]) ?? ""
        XCTAssertTrue(sys.contains("这个月还能随便花 976,61 €"))
        XCTAssertFalse(sys.contains("Super Sol"), "账本原文（每一笔流水）不发出去")
        // 调用失败：返回 nil，外面照旧走原来的路
        t.replies = [.failure(.noNetwork)]
        let b = await s.askChatModel("x")
        XCTAssertNil(b)
        // 手动切走：不发请求
        s.decisionPrefs.route = .local
        let c = await s.askChatModel("x")
        XCTAssertNil(c); XCTAssertEqual(t.sent.count, 2)
        XCTAssertFalse(s.chatUsesOpenRouter)
    }

    func testModelNamesAndList() async {
        let (s, _) = state([.success((#"{"data":[{"id":"openai/gpt-4o-mini"},{"id":"anthropic/claude-x"}]}"#, 200))])
        await s.loadModels()
        XCTAssertEqual(s.models, ["anthropic/claude-x", "openai/gpt-4o-mini"])
        s.setModel(decision: "bad name")
        XCTAssertEqual(s.decisionPrefs.decisionModel, "microsoft/microsoft-decision-1.1", "写得不像模型名的不收")
        s.setModel(chat: "anthropic/claude-x")
        XCTAssertEqual(s.decisionPrefs.chatModel, "anthropic/claude-x")
    }
}
