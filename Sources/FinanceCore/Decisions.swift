import Foundation

/// 决策模型：app 先把数算好，拼成一张「状态卡」，问模型一个是 / 否的问题，拿「是」的概率和临界点比。
/// 模型只做判断，不算账。没配密钥、调用失败时，用每个决策自己的「退回规则」。
/// 这里没有任何联网的代码：怎么拼请求、怎么读回来的概率、怎么比，都是纯的；发请求在 app 那一层。
public struct Decision: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// 什么时候跑。
    public var when: String
    public var question: String
    /// 「是」指什么、「否」指什么。
    public var yesWhen: String
    public var noWhen: String
    public var defaultThreshold: Double
    /// 没配密钥或调用失败时怎么判断（写给人看的）。
    public var fallback: String
    /// 已经接上了没有。没接的在设置里灰着写「以后」。
    public var wired: Bool
}

public enum Decisions {
    public static let remind = "D1"

    public static let all: [Decision] = [
        Decision(id: "D1", name: "要不要提醒", when: "每记一笔、每次导入、每天 9 点", question: "现在值得主动提醒用户一句吗？",
                 yesWhen: "不说会吃亏：余额不够下次扣款、某类花销超平常一倍、钱月底前会不够、目标明显推迟、订阅涨价或重复扣款；且 3 天内没说过同一件事",
                 noWhen: "正常花销或小波动、用户已知道、3 天内说过、用户关过这类", defaultThreshold: 0.70, fallback: "只提醒余额不够扣款和重复扣款", wired: true),
        Decision(id: "D2", name: "是不是在记账", when: "问夏夏 / 记一笔「说一句」里每句话", question: "这句话是要记一笔已经发生的收支吗？",
                 yesWhen: "说了花了 / 收了多少钱，且是已经发生的", noWhen: "在问问题、在计划还没花、在抱怨但没说金额、重复已记的",
                 defaultThreshold: 0.80, fallback: "有数字 + 有东西名就当记账", wired: false),
        Decision(id: "D3", name: "直接记还是先问", when: "认出是在记账之后", question: "可以不问用户，直接按猜的账户和分类记吗？",
                 yesWhen: "同类东西用同一账户记过 3 次以上，且金额在平常范围内", noWhen: "第一次出现、金额比平常大很多、上次被用户改过",
                 defaultThreshold: 0.85, fallback: "只有同类记过 3 次以上才直接记", wired: false),
        Decision(id: "D4", name: "是不是重复", when: "每次导入流水、每记一笔", question: "这一笔和已有的某一笔是同一笔钱吗？",
                 yesWhen: "金额一样、日期差 2 天内、名称相近或一个是手记一个是银行流水", noWhen: "金额一样但名称和地点明显不同，或同一天确实买了两次",
                 defaultThreshold: 0.85, fallback: "金额 + 日期 + 名称完全一样才算重复", wired: false),
        Decision(id: "D5", name: "是不是自己账户间转账", when: "导入流水时", question: "这笔是在用户自己的两个账户之间挪钱吗？",
                 yesWhen: "能在另一个自己的账户找到同金额反向一笔，时间 3 天内", noWhen: "对方是别人或商家",
                 defaultThreshold: 0.85, fallback: "找到完全对上的反向一笔才算", wired: false),
        Decision(id: "D6", name: "问题交给谁答", when: "问夏夏每句话", question: "这个问题能用账本里现成的数直接回答吗？",
                 yesWhen: "问余额、花了多少、还能花多少、某类多少、某天花了什么", noWhen: "问建议、问原因、问要不要、跟钱无关",
                 defaultThreshold: 0.75, fallback: "关键词命中就直接算，否则交大模型", wired: false),
        Decision(id: "D7", name: "是不是和钱有关", when: "账本答不了的问题", question: "这个问题和用户的钱有关吗？",
                 yesWhen: "花钱、存钱、收入、债、订阅、店的账、要不要买", noWhen: "闲聊、编程、天气等",
                 defaultThreshold: 0.60, fallback: "都交大模型", wired: false),
        Decision(id: "D8", name: "要不要买给建议", when: "用户贴图 / 链接 / 说想买", question: "这笔现在买，会让用户这个月或目标明显吃紧吗？",
                 yesWhen: "买了以后本月可花变负、或超过剩余的一半、或目标晚 2 周以上", noWhen: "买了以后还很宽松",
                 defaultThreshold: 0.60, fallback: "按「超过本月剩余一半」算", wired: false),
        Decision(id: "D9", name: "算不算意外开销", when: "每月小结、每记一笔", question: "这笔算意外开销吗？",
                 yesWhen: "比同类平时贵很多、或一笔占本月花销一成以上、且不是固定开销", noWhen: "固定开销、常买的东西、用户标过「不算」",
                 defaultThreshold: 0.70, fallback: "超同类平均 3 倍或占一成以上", wired: false),
    ]

    public static func find(_ id: String) -> Decision? { all.first { $0.id == id } }

    /// 临界点只能在 5% 到 95% 之间，按 5% 一格。
    public static func cleanThreshold(_ x: Double) -> Double { min(max((x * 20).rounded() / 20, 0.05), 0.95) }
}

/// 一次判断的结果。
public struct DecisionOutcome: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// 模型给的概率。
        case model
        /// 没用上模型，按固定规则判断的；附一句为什么。
        case fallback(String)
    }
    /// 「是」的概率（按固定规则判断时没有）。
    public var probability: Double?
    public var threshold: Double
    public var yes: Bool
    public var source: Source

    /// 「是的概率 83%，超过 70% → 会提醒」这样一句。
    public func line(yesDoes: String, noDoes: String) -> String {
        guard let p = probability else {
            if case .fallback(let why) = source { return "\(why)，按固定规则判断 → \(yes ? yesDoes : noDoes)" }
            return yes ? yesDoes : noDoes
        }
        let pp = Int((p * 100).rounded()), tt = Int((threshold * 100).rounded())
        return "是的概率 \(pp)%，\(yes ? "超过" : "没到") \(tt)% → \(yes ? yesDoes : noDoes)"
    }
}

public enum DecisionMath {
    /// 拿概率和临界点比。概率是 nil（没配、失败）就用固定规则的结果。
    public static func decide(probability: Double?, threshold: Double, fallbackYes: Bool, fallbackReason: String) -> DecisionOutcome {
        let t = Decisions.cleanThreshold(threshold)
        guard let p = probability, p.isFinite else {
            return DecisionOutcome(probability: nil, threshold: t, yes: fallbackYes, source: .fallback(fallbackReason))
        }
        let clamped = min(max(p, 0), 1)
        return DecisionOutcome(probability: clamped, threshold: t, yes: clamped >= t, source: .model)
    }

    /// 从「第一个字的几个候选和各自的对数概率」里算出「是」的概率：是 /（是 + 否）。两个都没出现就算不出来。
    public static func yesProbability(candidates: [(token: String, logprob: Double)]) -> Double? {
        var yes = 0.0, no = 0.0
        for c in candidates {
            let t = c.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let p = exp(c.logprob)
            guard p.isFinite else { continue }
            if t == "是" || t == "yes" || t == "y" || t.hasPrefix("是") { yes += p }
            else if t == "否" || t == "no" || t == "n" || t == "不" || t.hasPrefix("否") { no += p }
        }
        guard yes + no > 0 else { return nil }
        return yes / (yes + no)
    }

    /// 退路：模型回的是 {"yes": 0.83} 这样一小段。数字要在 0 到 1 之间。
    public static func yesProbability(json text: String) -> Double? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let obj = try? JSONSerialization.jsonObject(with: Data(text[a...b].utf8)) as? [String: Any] else { return nil }
        let raw = obj["yes"] ?? obj["是"]
        let p = (raw as? Double) ?? (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
        guard let p, p.isFinite, (0...1).contains(p) else { return nil }
        return p
    }
}

/// 和 OpenRouter 说话的格式（只管拼和读，不发请求）。
public enum OpenRouterWire {
    public static let endpoint = "https://openrouter.ai/api/v1/chat/completions"
    public static let modelsEndpoint = "https://openrouter.ai/api/v1/models"
    public static let defaultDecisionModel = "openai/gpt-4o-mini"
    public static let defaultChatModel = "openai/gpt-4o-mini"
    public static let timeout: TimeInterval = 10

    public enum Mode: Sendable { case logprobs, json }

    /// 模型名：去掉空白；要像「厂商/名字」。
    public static func cleanModel(_ raw: String) throws -> String {
        let m = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { throw TrialError("先填模型名") }
        guard m.contains("/"), !m.contains(where: { $0.isWhitespace }), m.count <= 120 else { throw TrialError("模型名写成「厂商/名字」这样，比如 openai/gpt-4o-mini") }
        return m
    }

    static func system(_ d: Decision, mode: Mode) -> String {
        let how = mode == .logprobs
            ? "只回一个字：「是」或「否」。不要解释，不要标点。"
            : "只回一小段 JSON：{\"yes\": 0 到 1 之间的小数}，表示「是」的可能性。不要别的字。"
        return "你在帮一个记账软件做一个是 / 否的判断。下面的数字都是软件算好的，不用你再算。\n问题：\(d.question)\n「是」的意思：\(d.yesWhen)。\n「否」的意思：\(d.noWhen)。\n\(how)"
    }

    /// 决策请求的正文。先试 `.logprobs`（让它只回一个字，同时要这个字的概率）；模型不支持时用 `.json`。
    public static func decisionBody(_ d: Decision, card: String, model: String, mode: Mode) -> Data {
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system(d, mode: mode)], ["role": "user", "content": card]],
            "temperature": 0,
        ]
        switch mode {
        case .logprobs: body["max_tokens"] = 1; body["logprobs"] = true; body["top_logprobs"] = 8
        case .json: body["max_tokens"] = 20; body["response_format"] = ["type": "json_object"]
        }
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    /// 聊天请求的正文：夏夏的口气 + app 算好的那几个数 + 用户的话。账本原文不整份发。
    public static func chatBody(model: String, numbers: String, question: String, maxTokens: Int = 300) -> Data {
        let system = "你是「夏夏」，一个记账软件里的助手。说大白话中文，短，不说教。只根据下面这些软件算好的数回答，不知道的就说不知道，不要自己编数字。\n\(numbers)"
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "temperature": 0.4,
                                   "messages": [["role": "system", "content": system], ["role": "user", "content": question]]]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    public enum Failure: Error, Equatable, Sendable {
        case badKey, badModel, noNetwork, timeout, noCredit, noLogprobs, unreadable
        /// 说人话的错误。
        public var message: String {
            switch self {
            case .badKey: "密钥不对，或者已经失效了"
            case .badModel: "模型名不对，OpenRouter 上没有这个模型"
            case .noNetwork: "没连上网"
            case .timeout: "等了 10 秒没回音"
            case .noCredit: "OpenRouter 账户里没额度了"
            case .noLogprobs: "这个模型给不出概率"
            case .unreadable: "回来的东西没看懂"
            }
        }
    }

    /// 按状态码和正文认出是哪种失败（200 返回 nil）。
    public static func failure(status: Int, body: Data) -> Failure? {
        if (200..<300).contains(status) {
            // OpenRouter 有时 200 里也带 error
            if let o = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let e = o["error"] as? [String: Any] {
                return failure(status: (e["code"] as? Int) ?? 400, body: Data())
            }
            return nil
        }
        let text = String(data: body, encoding: .utf8)?.lowercased() ?? ""
        switch status {
        case 401, 403: return .badKey
        case 402: return .noCredit
        case 404: return .badModel
        case 408, 504: return .timeout
        case 400:
            if text.contains("logprob") { return .noLogprobs }
            if text.contains("response_format") || text.contains("json") { return .unreadable }
            return .badModel
        default: return .unreadable
        }
    }

    /// 读决策的回答：算出「是」的概率。`.logprobs` 模式下回来的东西里没有概率，就抛 `.noLogprobs`，好让外面换 `.json` 再问一次。
    public static func yesProbability(from data: Data, mode: Mode) throws -> Double {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (o["choices"] as? [[String: Any]])?.first else { throw Failure.unreadable }
        let content = ((choice["message"] as? [String: Any])?["content"] as? String) ?? ""
        switch mode {
        case .json:
            guard let p = DecisionMath.yesProbability(json: content) else { throw Failure.unreadable }
            return p
        case .logprobs:
            guard let lp = choice["logprobs"] as? [String: Any], let first = (lp["content"] as? [[String: Any]])?.first else { throw Failure.noLogprobs }
            var candidates: [(String, Double)] = []
            for t in (first["top_logprobs"] as? [[String: Any]]) ?? [] {
                if let tok = t["token"] as? String, let l = (t["logprob"] as? NSNumber)?.doubleValue { candidates.append((tok, l)) }
            }
            if candidates.isEmpty, let tok = first["token"] as? String, let l = (first["logprob"] as? NSNumber)?.doubleValue { candidates.append((tok, l)) }
            guard let p = DecisionMath.yesProbability(candidates: candidates.map { (token: $0.0, logprob: $0.1) }) else { throw Failure.noLogprobs }
            return p
        }
    }

    /// 读聊天的回答。
    public static func chatText(from data: Data) throws -> String {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (o["choices"] as? [[String: Any]])?.first,
              let text = ((choice["message"] as? [String: Any])?["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { throw Failure.unreadable }
        return text
    }

    /// 读模型清单：只要名字（id）。
    public static func modelIDs(from data: Data) -> [String] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = o["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["id"] as? String }.sorted()
    }
}
