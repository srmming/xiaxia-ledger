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
    public func arguments(prompt: String, resume: String?, fin: String? = nil) -> [String] {
        switch self {
        case .claude:
            // -p 无窗口；json 输出带 session_id，下一句接着聊；只放行夏夏账本这一组工具，别的工具要确认的就不做。
            var a = ["-p", prompt, "--output-format", "json", "--allowedTools", "mcp__xiaxia-ledger"]
            // 直接把 app 自带的 fin 交给它当 MCP，只用这一个：不靠用户自己有没有配过、配的是不是旧版 fin。
            // （实测只靠用户配置时，有一次 claude 没起 MCP，干等到超时。）
            if let fin { a += ["--mcp-config", Self.mcpConfig(fin: fin), "--strict-mcp-config"] }
            if let resume { a += ["--resume", resume] }
            return a
        case .codex:
            return ["exec", "--skip-git-repo-check", prompt]
        case .hermes:
            return ["-z", prompt]
        }
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

/// 一次回答。
public struct ChatReply: Sendable {
    public var text: String
    public var sessionID: String?
    public var isError: Bool
}

public enum ChatRunner {
    /// 在后台跑一次，最多等 `timeout` 秒。
    public static func ask(_ engine: ChatEngine, prompt: String, resume: String? = nil, executable: String? = nil,
                           fin: String? = nil, timeout: TimeInterval = 180) async -> ChatReply {
        guard let exe = executable ?? engine.executable() else {
            return ChatReply(text: "这台 Mac 上没找到 \(engine.name)。", sessionID: nil, isError: true)
        }
        let dir = LedgerStores.appSupportFolder.appendingPathComponent("chat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let args = engine.arguments(prompt: prompt, resume: resume, fin: fin)
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
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                // 先读完输出再等退出，免得输出太长把管道塞满卡住。
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                let text = String(decoding: data, as: UTF8.self)
                let errText = String(decoding: errData, as: UTF8.self)
                if p.terminationReason == .uncaughtSignal {
                    cont.resume(returning: ChatReply(text: "\(engine.name) 太久没回（超过 \(Int(timeout)) 秒），先停下了。", sessionID: nil, isError: true))
                    return
                }
                cont.resume(returning: parse(engine, stdout: text, stderr: errText, status: p.terminationStatus))
            }
        }
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
    public static func prompt(question: String, voice: String, aim: String?, where view: String, history: [(user: Bool, text: String)]) -> String {
        var p = """
        你是「夏夏」，夏夏账本 app 里的记账助手，用户正在 app 右边的对话栏里跟你说话。
        - 用 xiaxia-ledger 这组工具查账、记账；先调 context 看账本和账户。用户说「这笔」「这里」时调 current_view。
        - 拿不准的（哪个账户、哪个账本、什么分类）先问一句，别猜；信息齐全的单笔可以直接记。记完一句话说清记了什么；别把改动编号、id 这类内部编码说给用户。
        - 想让用户在 app 里看到某几笔或某一页时用 open_in_app。
        - 口吻：\(voice) 回答用中文，短一点，三五句以内，不用 Markdown 表格。
        """
        if let aim { p += "\n- 用户的目标：\(aim)。" }
        p += "\n\n用户现在在看：\(view)"
        if !history.isEmpty {
            p += "\n\n前面聊过的（最近几句）：\n" + history.suffix(6).map { ($0.user ? "用户：" : "夏夏：") + $0.text }.joined(separator: "\n")
        }
        p += "\n\n用户这一句：\(question)"
        return p
    }
}
#endif
