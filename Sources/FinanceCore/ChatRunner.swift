#if os(macOS)
import Foundation

/// app 里「夏夏」对话栏的回答从哪来：在后台调用这台 Mac 上已经装好、已经登录的 AI 命令行，
/// 用的是用户自己的订阅，不用另外填 API key。它们都已经连着夏夏账本的 MCP，所以能直接查账、记账。
/// 2026-11-22 在 Mac 上实测：claude -p 约 4 秒；codex exec 约 13 秒（会加载所有 MCP，比较费）；hermes -z 约 12 秒。
public enum ChatEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude, codex, hermes
    public var id: String { rawValue }

    /// 给 claude --mcp-config 的一段 JSON：只有夏夏账本这一个 MCP，命令是 app 自带的 fin。
    public static func mcpConfig(fin: String) -> String {
        let obj: [String: Any] = ["mcpServers": [AIConnector.serverName: ["command": fin, "args": ["mcp"]]]]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .hermes: "Hermes"
        }
    }

    /// GUI app 拿不到终端的 PATH，按常见位置找。codex 先找 bun 装的那份（Homebrew 的旧版可能不认新模型）。
    public static func candidates(_ engine: ChatEngine, home: String = NSHomeDirectory()) -> [String] {
        let bins = ["\(home)/.local/bin", "\(home)/.bun/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        var list = bins.map { "\($0)/\(engine.rawValue)" }
        if engine == .claude { list.append("\(home)/.claude/local/claude") }
        return list
    }

    /// 这台 Mac 上找得到的可执行文件。
    public func executable(home: String = NSHomeDirectory()) -> String? {
        ChatEngine.candidates(self, home: home).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 装了哪些（按推荐顺序）。
    public static func available(home: String = NSHomeDirectory()) -> [ChatEngine] {
        allCases.filter { $0.executable(home: home) != nil }
    }

    /// 后台问一句的参数。claude 能接着上一轮聊（resume），另外两个每次把最近几句一起带上。
    /// model：nil = 跟随这个 AI 自己的默认（用户在 Claude Code / Codex 里设的那个），不加参数。
    public func arguments(prompt: String, resume: String?, fin: String? = nil, model: String? = nil) -> [String] {
        switch self {
        case .claude:
            // -p 无窗口；json 输出带 session_id，下一句接着聊；只放行夏夏账本这一组工具，别的工具要确认的就不做。
            var a = ["-p", prompt, "--output-format", "json", "--allowedTools", "mcp__xiaxia-ledger"]
            // 直接把 app 自带的 fin 交给它当 MCP，只用这一个：不靠用户自己有没有配过、配的是不是旧版 fin。
            // （实测只靠用户配置时，有一次 claude 没起 MCP，干等到超时。）
            if let fin { a += ["--mcp-config", Self.mcpConfig(fin: fin), "--strict-mcp-config"] }
            if let resume { a += ["--resume", resume] }
            if let model { a += ["--model", model] }
            return a
        case .codex:
            if let model { return ["exec", "--skip-git-repo-check", "--model", model, prompt] }
            return ["exec", "--skip-git-repo-check", prompt]
        case .hermes:
            // -z 默认不加载新加的 MCP 工具集，要用 -t 点名 xiaxia-ledger（2026-11-22 在 ming 的 Mac 上实测）。
            return ["-z", prompt, "-t", "xiaxia-ledger"]
        }
    }

    /// 能选的模型（不含「跟随默认」）。
    /// Claude Code：fable / opus / sonnet / haiku 是它命令行认的别名，永远指向这一代最新的那个（claude --help 里写着 fable、opus、sonnet）。
    /// Codex：只列用户自己在 ~/.codex/config.toml 里写过的模型（默认的和各个 profile 的），不猜 OpenAI 有哪些名字。
    /// Hermes：模型在它自己的设置里换，这里只跟随默认。
    public func models(home: String = NSHomeDirectory()) -> [ChatModel] {
        switch self {
        case .claude:
            return [ChatModel(id: "fable", name: "Fable", note: "最聪明"),
                    ChatModel(id: "opus", name: "Opus", note: "很聪明，慢一点"),
                    ChatModel(id: "sonnet", name: "Sonnet", note: "又快又好，日常够用"),
                    ChatModel(id: "haiku", name: "Haiku", note: "最快，简单记账")]
        case .codex:
            let text = (try? String(contentsOfFile: "\(home)/.codex/config.toml", encoding: .utf8)) ?? ""
            var seen: [String] = []
            for line in text.split(separator: "\n") {
                if let m = Self.tomlString(String(line), key: "model"), !seen.contains(m) { seen.append(m) }
            }
            // 和默认一样的不再列一遍（「跟随默认」已经是它了）。
            let fallback = defaultModel(home: home)
            return seen.filter { $0 != fallback }.map { ChatModel(id: $0, name: $0, note: "") }
        case .hermes:
            return []
        }
    }

    /// 这个 AI 自己设的默认模型（读它的设置文件，读不到是 nil：那就是它出厂的默认）。
    public func defaultModel(home: String = NSHomeDirectory()) -> String? {
        switch self {
        case .claude:
            guard let data = FileManager.default.contents(atPath: "\(home)/.claude/settings.json"),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let m = obj["model"] as? String, !m.isEmpty else { return nil }
            return Self.prettyClaude(m)
        case .codex:
            // 顶层（第一个 [section] 之前）的 model = "…"
            let text = (try? String(contentsOfFile: "\(home)/.codex/config.toml", encoding: .utf8)) ?? ""
            for line in text.split(separator: "\n") {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("[") { break }
                if let m = Self.tomlString(String(line), key: "model") { return m }
            }
            return nil
        case .hermes:
            // config.yaml 里 model: 下面的 default:（或者直接 model: xxx）
            let text = (try? String(contentsOfFile: "\(home)/.hermes/config.yaml", encoding: .utf8)) ?? ""
            var inModel = false
            for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(raw)
                if line.hasPrefix("model:") {
                    let v = line.dropFirst(6).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !v.isEmpty { return v }
                    inModel = true; continue
                }
                if inModel {
                    if !line.hasPrefix(" ") && !line.isEmpty { break }
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("default:") {
                        let v = t.dropFirst(8).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        return v.isEmpty ? nil : v
                    }
                }
            }
            return nil
        }
    }

    /// claude-opus-4-… / opus → Opus，看得懂就行。
    static func prettyClaude(_ m: String) -> String {
        let l = m.lowercased()
        for (k, v) in [("fable", "Fable"), ("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku")] where l.contains(k) { return v }
        return m
    }

    /// TOML 里一行 key = "value"（只认双引号或单引号的字符串）。
    static func tomlString(_ line: String, key: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(key) else { return nil }
        let rest = t.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("=") else { return nil }
        let v = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        guard let q = v.first, q == "\"" || q == "'" else { return nil }
        let body = v.dropFirst()
        guard let end = body.firstIndex(of: q) else { return nil }
        let value = String(body[..<end])
        return value.isEmpty ? nil : value
    }

    /// 环境：留着 HOME / USER / LOGNAME（claude 靠它读钥匙串里的登录），PATH 把常见位置放前面（codex 要找 node）。
    public static func environment(base: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) -> [String: String] {
        var env: [String: String] = [:]
        for k in ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "XIAXIA_LEDGER_PATH", "XIAXIA_BRIDGE_DIR"] { if let v = base[k] { env[k] = v } }
        env["HOME"] = env["HOME"] ?? home
        if env["USER"] == nil { env["USER"] = NSUserName() }
        if env["LOGNAME"] == nil { env["LOGNAME"] = env["USER"] }
        env["PATH"] = ["\(home)/.local/bin", "\(home)/.bun/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        return env
    }
}

/// 对话栏可以换的一个模型。
public struct ChatModel: Hashable, Sendable, Identifiable {
    /// 传给命令行的名字（Claude Code 用别名 opus / sonnet / haiku）。
    public var id: String
    public var name: String
    /// 一句大白话：快还是聪明。
    public var note: String
}

/// 一次回答。
public struct ChatReply: Sendable {
    public var text: String
    public var sessionID: String?
    public var isError: Bool
}

public enum ChatRunner {
    /// 在后台跑一次，最多等 `timeout` 秒。
    public static func ask(_ engine: ChatEngine, prompt: String, resume: String? = nil, executable: String? = nil,
                           fin: String? = nil, model: String? = nil, timeout: TimeInterval = 180) async -> ChatReply {
        guard let exe = executable ?? engine.executable() else {
            return ChatReply(text: "这台 Mac 上没找到 \(engine.name)。", sessionID: nil, isError: true)
        }
        let dir = LedgerStores.appSupportFolder.appendingPathComponent("chat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let args = engine.arguments(prompt: prompt, resume: resume, fin: fin, model: model)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.environment = ChatEngine.environment()
                p.currentDirectoryURL = dir
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    cont.resume(returning: ChatReply(text: "\(engine.name) 打不开：\(error.localizedDescription)", sessionID: nil, isError: true))
                    return
                }
                // 记下是不是我们停的：claude 收到 SIGTERM 会自己正常退出（退出码 143），光看退出原因看不出来。
                let stopped = StopFlag()
                let killer = DispatchWorkItem { if p.isRunning { stopped.set(); p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                // stdout 和 stderr 同时读：只读完一个再读另一个，另一个写满 64KB 管道时命令行就会卡住不动。
                let started = Date()
                let errBox = DataBox()
                let errDone = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                    errDone.signal()
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                errDone.wait()
                let errData = errBox.data
                p.waitUntilExit()
                killer.cancel()
                writeLog(dir: dir, engine: engine, args: args, prompt: prompt, seconds: Date().timeIntervalSince(started),
                         status: p.terminationStatus, stopped: stopped.value, stderr: errData)
                let text = String(decoding: data, as: UTF8.self)
                let errText = String(decoding: errData, as: UTF8.self)
                if stopped.value || p.terminationReason == .uncaughtSignal {
                    cont.resume(returning: ChatReply(text: "夏夏等了 \(Int(timeout / 60)) 分钟还没等到 \(engine.name) 的回答，先停下了。如果屏幕上有系统问「“夏夏账本”想访问…」的小窗，点「允许」后再发一次；也可以在右上角换一个 AI。", sessionID: nil, isError: true))
                    return
                }
                cont.resume(returning: parse(engine, stdout: text, stderr: errText, status: p.terminationStatus))
            }
        }
    }

    /// 每次调用记一份日志（chat/last-run.log，只留最近一次）：卡住、出错时能直接看到原因。不记提问内容。
    static func writeLog(dir: URL, engine: ChatEngine, args: [String], prompt: String, seconds: TimeInterval, status: Int32, stopped: Bool, stderr: Data) {
        let shown = redacted(args, prompt: prompt)
        var log = "\(ISO8601DateFormatter().string(from: Date())) \(engine.rawValue) \(String(format: "%.1f", seconds)) 秒 退出码 \(status)\(stopped ? "（超时被停）" : "")\n"
        log += "参数：\(shown.joined(separator: " "))\n--- stderr ---\n"
        log += String(decoding: stderr.suffix(20_000), as: UTF8.self)
        try? log.write(to: dir.appendingPathComponent("last-run.log"), atomically: true, encoding: .utf8)
    }

    /// 日志里的参数：提问那一项（不管排在第几个、跟在 -p 还是 -z 后面）一律换成「<提问>」。
    /// 按内容比，不按位置猜：Hermes 的参数是 -z 提问 -t xiaxia-ledger，提问不在最后（2026-11-22 曾因此把提问原样写进日志）。
    public static func redacted(_ args: [String], prompt: String) -> [String] {
        args.map { $0 == prompt ? "<提问>" : $0 }
    }

    /// 把命令行的输出变成一句回答。
    public static func parse(_ engine: ChatEngine, stdout: String, stderr: String, status: Int32) -> ChatReply {
        if engine == .claude, let obj = try? JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any] {
            let result = (obj["result"] as? String) ?? ""
            let isError = (obj["is_error"] as? Bool) ?? false
            let session = obj["session_id"] as? String
            if isError, result.localizedCaseInsensitiveContains("not logged in") {
                return ChatReply(text: "Claude Code 还没登录。在终端里运行一次 claude 登录好就行。", sessionID: nil, isError: true)
            }
            return ChatReply(text: result.isEmpty ? "（没有回答）" : result, sessionID: session, isError: isError)
        }
        let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if status != 0 || text.isEmpty {
            let why = stderr.split(separator: "\n").suffix(3).joined(separator: "\n")
            return ChatReply(text: "\(engine.name) 出错了（退出码 \(status)）。\(why)", sessionID: nil, isError: true)
        }
        return ChatReply(text: text, sessionID: nil, isError: false)
    }

    /// 给 AI 的话：先交代身份和规矩，再带上用户在看哪、最近几句，最后是这一句。
    /// `memory` 是 `MemoryBrief(ledger:).promptText`：用户定的规矩全文加其它记忆的标题，省得每次先调一轮工具才知道。
    public static func prompt(question: String, voice: String, aim: String?, where view: String, history: [(user: Bool, text: String)],
                              memory: String? = nil, name: String = Profile.defaultAssistantName, callUser: String? = nil) -> String {
        var p = """
        你是「\(name)」，夏夏账本 app 里的记账助手，用户正在 app 右边的对话栏里跟你说话。
        - 用 xiaxia-ledger 这组工具查账、记账；先调 context 看账本和账户。用户说「这笔」「这里」时调 current_view。
        - 拿不准的（哪个账户、哪个账本、什么分类）先问一句，别猜；信息齐全的单笔可以直接记。记完一句话说清记了什么；别把改动编号、id 这类内部编码说给用户。
        - 想让用户在 app 里看到某几笔或某一页时用 open_in_app。
        - 口吻：\(voice) 回答用中文，短一点，三五句以内，不用 Markdown 表格。
        """
        if let callUser { p += "\n- 称呼用户「\(callUser)」。" }
        if let aim { p += "\n- 用户的目标：\(aim)。" }
        p += "\n- 问什么用哪个工具：" + toolCrib
        p += "\n- 记忆：用户说「记住……」「以后都……」「别再……」就用 remember 记下来，记完说一句记了什么；说「忘掉」用 forget_memory。数字不记（工资、房租这些每次现算）。"
        if let memory, !memory.isEmpty { p += "\n\n" + memory }
        p += "\n\n用户现在在看：\(view)"
        if !history.isEmpty {
            p += "\n\n前面聊过的（最近几句）：\n" + history.suffix(6).map { ($0.user ? "用户：" : "\(name)：") + $0.text }.joined(separator: "\n")
        }
        p += "\n\n用户这一句：\(question)"
        return p
    }
}
extension ChatRunner {
    /// 一行小抄：免得问收入去翻支出、问余额去加流水。完整版在 context 的 toolGuide。
    static let toolCrib = "收入 / 支出 / 结余 / 某分类花了多少 → summary（只问收入就只答收入）；工资、每月固定进出 → regulars；找某几笔 → list_transactions；账户里有多少 → accounts；订阅 → subscriptions；欠款 → debts；存钱进度 → goals。"
}
/// 另一个线程读出来的 stderr，读完（信号量）之后才取。
private final class DataBox: @unchecked Sendable { var data = Data() }

/// 超时有没有被我们停掉：在两个线程之间传一个是/否。
private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    func set() { lock.lock(); on = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return on }
}
#endif
