import XCTest
@testable import FinanceCore

/// 决策模型：登记的九个决策、概率怎么算、和临界点怎么比、退回规则，还有 D1「要不要提醒」。全用编的数，不发任何请求。
final class DecisionsTests: XCTestCase {
    private func eur(_ s: String) -> Money { Money(parsing: s)! }
    private let d1 = Decisions.find("D1")!

    func testNineDecisionsAreRegisteredAndOnlyD1IsWired() {
        XCTAssertEqual(Decisions.all.map(\.id), (1...9).map { "D\($0)" })
        XCTAssertEqual(Decisions.all.filter(\.wired).map(\.id), ["D1"])
        XCTAssertEqual(d1.defaultThreshold, 0.70)
        XCTAssertEqual(Decisions.all.map(\.defaultThreshold), [0.70, 0.80, 0.85, 0.85, 0.85, 0.75, 0.60, 0.60, 0.70])
        XCTAssertTrue(Decisions.all.allSatisfy { !$0.question.isEmpty && !$0.yesWhen.isEmpty && !$0.noWhen.isEmpty && !$0.fallback.isEmpty })
        XCTAssertEqual(Decisions.cleanThreshold(0.72), 0.70)
        XCTAssertEqual(Decisions.cleanThreshold(2), 0.95)
        XCTAssertEqual(Decisions.cleanThreshold(-1), 0.05)
    }

    func testProbabilityFromCandidates() {
        // 是 0.83、否 0.17
        let p = DecisionMath.yesProbability(candidates: [("是", log(0.83)), ("否", log(0.17))])!
        XCTAssertEqual(p, 0.83, accuracy: 0.0001)
        // 别的字不算；是 / Yes 加在一起；只有一边出现也算
        let q = DecisionMath.yesProbability(candidates: [("是", log(0.4)), (" Yes", log(0.2)), ("嗯", log(0.3)), ("否", log(0.1))])!
        XCTAssertEqual(q, 0.6 / 0.7, accuracy: 0.0001)
        XCTAssertEqual(DecisionMath.yesProbability(candidates: [("否", log(0.9))]), 0)
        XCTAssertNil(DecisionMath.yesProbability(candidates: [("嗯", log(0.9))]), "是和否都没出现：算不出来")
        XCTAssertNil(DecisionMath.yesProbability(candidates: []))
    }

    func testProbabilityFromJSON() {
        XCTAssertEqual(DecisionMath.yesProbability(json: "{\"yes\": 0.83}"), 0.83)
        XCTAssertEqual(DecisionMath.yesProbability(json: "好的：```json\n{ \"yes\" : 0.2 }\n```"), 0.2)
        XCTAssertNil(DecisionMath.yesProbability(json: "{\"yes\": 83}"), "超出 0 到 1 的不认")
        XCTAssertNil(DecisionMath.yesProbability(json: "是"))
    }

    func testCompareWithThresholdAndFallback() {
        let a = DecisionMath.decide(probability: 0.83, threshold: 0.70, fallbackYes: false, fallbackReason: "没连")
        XCTAssertTrue(a.yes); XCTAssertEqual(a.source, .model)
        XCTAssertEqual(a.line(yesDoes: "会提醒", noDoes: "不提醒"), "是的概率 83%，超过 70% → 会提醒")
        let b = DecisionMath.decide(probability: 0.69, threshold: 0.70, fallbackYes: true, fallbackReason: "没连")
        XCTAssertFalse(b.yes, "有概率就按概率，不看固定规则")
        XCTAssertEqual(b.line(yesDoes: "会提醒", noDoes: "不提醒"), "是的概率 69%，没到 70% → 不提醒")
        XCTAssertTrue(DecisionMath.decide(probability: 0.70, threshold: 0.70, fallbackYes: false, fallbackReason: "").yes, "正好到临界点算是")
        let c = DecisionMath.decide(probability: nil, threshold: 0.70, fallbackYes: true, fallbackReason: "密钥不对")
        XCTAssertTrue(c.yes); XCTAssertNil(c.probability)
        XCTAssertEqual(c.line(yesDoes: "会提醒", noDoes: "不提醒"), "密钥不对，按固定规则判断 → 会提醒")
        XCTAssertFalse(DecisionMath.decide(probability: .nan, threshold: 0.7, fallbackYes: false, fallbackReason: "x").yes)
    }

    func testWireRequestAndReplies() throws {
        let card = ReminderDecision.sample(.yes).card
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: OpenRouterWire.decisionBody(d1, card: card, model: "openai/gpt-4o-mini", mode: .logprobs)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "openai/gpt-4o-mini")
        XCTAssertEqual(body["logprobs"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 1)
        let msgs = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertTrue(msgs[0]["content"]!.contains(d1.question)); XCTAssertTrue(msgs[0]["content"]!.contains("只回一个字"))
        XCTAssertEqual(msgs[1]["content"], card, "发出去的就是那张状态卡，没有别的")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: OpenRouterWire.decisionBody(d1, card: card, model: "x/y", mode: .json)) as? [String: Any])
        XCTAssertNil(json["logprobs"]); XCTAssertNotNil(json["response_format"])

        let reply = #"{"choices":[{"message":{"content":"是"},"logprobs":{"content":[{"token":"是","logprob":-0.1863,"top_logprobs":[{"token":"是","logprob":-0.1863},{"token":"否","logprob":-1.772}]}]}}]}"#
        XCTAssertEqual(try OpenRouterWire.yesProbability(from: Data(reply.utf8), mode: .logprobs), 0.83, accuracy: 0.005)
        let noLP = #"{"choices":[{"message":{"content":"是"}}]}"#
        XCTAssertThrowsError(try OpenRouterWire.yesProbability(from: Data(noLP.utf8), mode: .logprobs)) { XCTAssertEqual($0 as? OpenRouterWire.Failure, .noLogprobs) }
        let viaJSON = #"{"choices":[{"message":{"content":"{\"yes\": 0.41}"}}]}"#
        XCTAssertEqual(try OpenRouterWire.yesProbability(from: Data(viaJSON.utf8), mode: .json), 0.41)
        XCTAssertThrowsError(try OpenRouterWire.yesProbability(from: Data("oops".utf8), mode: .json))

        // 专门的决策接口
        let db = try XCTUnwrap(JSONSerialization.jsonObject(with: OpenRouterWire.decisionsBody(d1, card: card, model: "microsoft/microsoft-decision-1.1")) as? [String: Any])
        XCTAssertEqual(db["state"] as? String, card)
        XCTAssertEqual(((db["questions"] as? [String: Any])?["answer"] as? [String: Any])?["type"] as? String, "noul")
        let dr = try OpenRouterWire.decisionsReply(from: Data(#"{"answers":{"answer":{"type":"noul","noul":0.87}},"model":"m","usage":{"input_tokens":3,"output_tokens":0,"cost":0.0000088}}"#.utf8))
        XCTAssertEqual(dr.probability, 0.87); XCTAssertEqual(dr.cost, 0.0000088)
        XCTAssertThrowsError(try OpenRouterWire.decisionsReply(from: Data(#"{"answers":{"answer":{"type":"refusal"}}}"#.utf8)))
        XCTAssertThrowsError(try OpenRouterWire.decisionsReply(from: Data(#"{"answers":{"answer":{"type":"noul","noul":1.7}}}"#.utf8)))
        XCTAssertEqual(OpenRouterWire.failure(status: 401, body: Data()), .badKey)
        XCTAssertEqual(OpenRouterWire.failure(status: 404, body: Data()), .badModel)
        XCTAssertEqual(OpenRouterWire.failure(status: 402, body: Data()), .noCredit)
        XCTAssertEqual(OpenRouterWire.failure(status: 400, body: Data("logprobs is not supported".utf8)), .noLogprobs)
        XCTAssertEqual(OpenRouterWire.failure(status: 200, body: Data(#"{"error":{"code":401,"message":"x"}}"#.utf8)), .badKey)
        XCTAssertNil(OpenRouterWire.failure(status: 200, body: Data(reply.utf8)))
        XCTAssertEqual(OpenRouterWire.Failure.badKey.message, "密钥不对，或者已经失效了")
        XCTAssertThrowsError(try OpenRouterWire.cleanModel("gpt 4"))
        XCTAssertEqual(try OpenRouterWire.cleanModel("  openai/gpt-4o-mini\n"), "openai/gpt-4o-mini")
        XCTAssertEqual(OpenRouterWire.modelIDs(from: Data(#"{"data":[{"id":"b/two"},{"id":"a/one"}]}"#.utf8)), ["a/one", "b/two"])
        XCTAssertEqual(try OpenRouterWire.chatText(from: Data(#"{"choices":[{"message":{"content":" 还能花 976 €。 "}}]}"#.utf8)), "还能花 976 €。")
    }

    // MARK: D1 三组示例

    func testObviousYes() {
        let s = ReminderDecision.sample(.yes)
        XCTAssertTrue(s.card.contains("房租 650,00 €，3 天后从日常卡扣，日常卡现在有 412,60 €（不够）"))
        XCTAssertEqual(s.topics.map(\.kind), [.shortBalance, .doubled, .runsShort, .goalLate])
        // 模型说 0.91：出卡，说最要紧的那件
        guard case .show(let t, let o) = ReminderDecision.resolve(s, probability: 0.91, threshold: 0.70, saidToday: 0) else { return XCTFail() }
        XCTAssertEqual(t.kind, .shortBalance)
        XCTAssertEqual(t.sentence, "3 天后要扣房租 650,00 €，日常卡里只有 412,60 €，还差 237,40 €。")
        XCTAssertEqual(o.probability, 0.91)
        // 没连模型 / 调用失败：固定规则也会说（余额不够扣款）
        guard case .show(let f, let fo) = ReminderDecision.resolve(s, probability: nil, threshold: 0.70, saidToday: 0, fallbackReason: "没连上网") else { return XCTFail() }
        XCTAssertEqual(f.kind, .shortBalance); XCTAssertEqual(fo.source, .fallback("没连上网"))
        // 今天已经说过一句：存到晚上
        guard case .later(let l, _) = ReminderDecision.resolve(s, probability: 0.91, threshold: 0.70, saidToday: 1) else { return XCTFail() }
        XCTAssertEqual(l.key, "shortBalance:房租")
    }

    func testObviousNo() {
        let s = ReminderDecision.sample(.no)
        XCTAssertTrue(s.topics.isEmpty)
        guard case .quiet(let o) = ReminderDecision.resolve(s, probability: 0.06, threshold: 0.70, saidToday: 0) else { return XCTFail() }
        XCTAssertFalse(o.yes)
        guard case .quiet = ReminderDecision.resolve(s, probability: nil, threshold: 0.70, saidToday: 0) else { return XCTFail("固定规则也不说") }
        // 模型乱说 0.99 也不出卡：没有一件具体的事可说
        guard case .quiet = ReminderDecision.resolve(s, probability: 0.99, threshold: 0.70, saidToday: 0) else { return XCTFail() }
    }

    func testBorderline() {
        let s = ReminderDecision.sample(.edge)
        XCTAssertEqual(s.topics.map(\.kind), [], "衣服没到一倍、钱够、目标只晚 1 周：按固定说法没有可说的")
        XCTAssertNil(s.fallbackTopic)
        guard case .quiet(let low) = ReminderDecision.resolve(s, probability: 0.62, threshold: 0.70, saidToday: 0) else { return XCTFail() }
        XCTAssertEqual(low.line(yesDoes: "会提醒", noDoes: "不提醒"), "是的概率 62%，没到 70% → 不提醒")
        // 把临界点调到 60%：模型说是了，但没有具体的事，仍然不出卡
        guard case .quiet(let hi) = ReminderDecision.resolve(s, probability: 0.62, threshold: 0.60, saidToday: 0) else { return XCTFail() }
        XCTAssertTrue(hi.yes)
        // 擦边的那种：余额刚好不够
        var t = s
        t.charges = [.init(name: "手机分期", amount: eur("200"), account: "日常卡", balance: eur("190"), inDays: 6)]
        guard case .show(let topic, _) = ReminderDecision.resolve(t, probability: 0.62, threshold: 0.60, saidToday: 0) else { return XCTFail() }
        XCTAssertEqual(topic.kind, .shortBalance)
        guard case .quiet = ReminderDecision.resolve(t, probability: 0.62, threshold: 0.70, saidToday: 0) else { return XCTFail("没到临界点就不说") }
    }

    func testNoRepeatsAndMutedKinds() {
        var s = ReminderDecision.sample(.yes)
        s.recent = [(key: "shortBalance:房租", daysAgo: 1)]
        XCTAssertEqual(s.freshTopics.first?.kind, .doubled, "3 天内说过房租：换下一件")
        XCTAssertNil(s.fallbackTopic, "固定规则只管余额和重复扣款，这件说过了就不说")
        s.recent = [(key: "shortBalance:房租", daysAgo: 3)]
        XCTAssertEqual(s.freshTopics.first?.kind, .shortBalance, "满 3 天可以再说")
        s.muted = ["shortBalance", "doubled", "runsShort", "goalLate"]
        XCTAssertTrue(s.topics.isEmpty, "关掉的那几类不说")
        guard case .quiet = ReminderDecision.resolve(s, probability: 0.95, threshold: 0.70, saidToday: 0) else { return XCTFail() }
        XCTAssertTrue(s.card.contains("用户关掉了这几类提醒"))
        var d = ReminderDecision.sample(.no)
        d.duplicates = ["音乐会员 10,99 €"]
        XCTAssertEqual(d.fallbackTopic?.kind, .duplicate)
    }
}
