import Foundation

/// 把夏夏账本接到这台 Mac 上的 AI 工具：找出装了哪些，帮它们写好 MCP 配置。
/// app 的「连 AI」引导和 fin 都只用这一份。只改配置里 xiaxia-ledger 这一项，别的不碰；第一次改之前在旁边留一份 .bak-xiaxia。
public enum AIApp: String, CaseIterable, Identifiable, Codable, Sendable {
    case claudeDesktop, claudeCode, codex, hermes, cursor, gemini

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .claudeDesktop: "Claude 桌面版"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .hermes: "Hermes Agent"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        }
    }

    /// 命令行里的名字：fin connect claude-desktop
    public var cliName: String {
        switch self {
        case .claudeDesktop: "claude-desktop"
        case .claudeCode: "claude-code"
        case .codex: "codex"
        case .hermes: "hermes"
        case .cursor: "cursor"
        case .gemini: "gemini"
        }
    }

    public static func from(cliName: String) -> AIApp? { allCases.first { $0.cliName == cliName.lowercased() } }

    /// 命令行程序名（没有就是 nil）。
    public var cliBinary: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .hermes: "hermes"
        case .gemini: "gemini"
        case .claudeDesktop, .cursor: nil
        }
    }

    /// 后台问一句、拿回答的参数（不开窗口）。app 内对话栏用：[可执行文件] + headlessArguments(问题)。
    /// claude -p、codex exec、gemini -p 是各家文档里的写法。hermes -z 默认不加载新加的 MCP 工具集，要用 -t 点名
    ///（2026-11-22 在 ming 的 Mac 上实测：不带 -t 回答「没有 xiaxia-ledger 工具」，带上就能读账本）。
    public func headlessArguments(_ prompt: String) -> [String]? {
        switch self {
        case .claudeCode: ["-p", prompt]
        case .codex: ["exec", prompt]
        case .hermes: ["-z", prompt, "-t", "xiaxia-ledger"]
        case .gemini: ["-p", prompt]
        case .claudeDesktop, .cursor: nil
        }
    }

    /// 写好配置之后要做什么才能用上。
    public var afterConnect: String {
        switch self {
        case .claudeDesktop: "完全退出 Claude（⌘Q）再打开"
        case .claudeCode: "新开一个 Claude Code 对话"
        case .codex: "重开 Codex"
        case .hermes: "在 Hermes 里输入 /reload-mcp（或重开 Hermes）"
        case .cursor: "重开 Cursor"
        case .gemini: "新开一个 Gemini CLI"
        }
    }

    /// 这个工具的 app 名（在「应用程序」里找）。
    var appBundles: [String] {
        switch self {
        case .claudeDesktop: ["Claude.app"]
        case .claudeCode: []
        case .codex: ["Codex.app"]
        case .hermes: ["Hermes.app"]
        case .cursor: ["Cursor.app"]
        case .gemini: []
        }
    }

    /// 在主目录下有这些文件夹 / 文件，就当它装过。
    var homeMarkers: [String] {
        switch self {
        case .claudeDesktop: ["Library/Application Support/Claude"]
        case .claudeCode: [".claude.json", ".claude"]
        case .codex: [".codex"]
        case .hermes: [".hermes"]
        case .cursor: [".cursor"]
        case .gemini: [".gemini"]
        }
    }

    /// MCP 配置文件（相对主目录）。
    var configPath: String {
        switch self {
        case .claudeDesktop: "Library/Application Support/Claude/claude_desktop_config.json"
        case .claudeCode: ".claude.json"
        case .codex: ".codex/config.toml"
        case .hermes: ".hermes/config.yaml"
        case .cursor: ".cursor/mcp.json"
        case .gemini: ".gemini/settings.json"
        }
    }

    /// MCP 握手时报上来的名字（clientInfo.name）对应哪个工具。
    public static func from(clientName: String) -> AIApp? {
        let n = clientName.lowercased()
        if n.contains("claude-code") || n == "claude code" { return .claudeCode }
        if n.contains("claude") { return .claudeDesktop }
        if n.contains("codex") { return .codex }
        if n.contains("hermes") { return .hermes }
        if n.contains("cursor") { return .cursor }
        if n.contains("gemini") { return .gemini }
        return nil
    }

    /// 给人看的名字：认得的换成中文名，不认得的原样。
    public static func displayName(clientName: String) -> String {
        from(clientName: clientName)?.name ?? clientName
    }
}

public struct AIConnector: Sendable {
    public enum ConnectError: LocalizedError, Equatable {
        case unreadableConfig(String)
        public var errorDescription: String? {
            switch self {
            case .unreadableConfig(let path): "配置文件 \(path) 格式读不懂，为了不弄坏它，没有改。可以手动把 MCP 配置粘进去。"
            }
        }
    }

    public static let serverName = "xiaxia-ledger"

    public var home: URL
    /// fin 的完整路径（app 自带的那份）。
    public var fin: String
    /// 去哪找 Claude.app 这些（测试时换成临时目录）。
    public var appFolders: [URL]

    public init(home: URL = URL(fileURLWithPath: NSHomeDirectory()), fin: String, appFolders: [URL]? = nil) {
        self.home = home
        self.fin = fin
        self.appFolders = appFolders ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    /// 粘进别的 AI 工具（Cherry Studio、Trae、ChatWise……）MCP 设置里的那段。
    public static func configSnippet(fin: String) -> String {
        let obj: [String: Any] = ["mcpServers": [serverName: ["command": fin, "args": ["mcp"]]]]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// 开始引导里让用户去跟 AI 说的那一句（用户看得懂、自己也会这么说）。怎么带着记第一笔写在 welcomeGuide 里，由 MCP 的 welcome 工具交给 AI。
    /// 三句人话，自己就说得清要做什么：不靠 AI 那边有没有新版的 welcome 工具；连不到账本的 AI（网页版、手机版）也会照最后一句直说。
    public static let welcomeSentence = "我刚装了夏夏账本，想让你以后帮我记账。先问我今天花了什么，帮我记下第一笔；再问我有没有想存钱达成的心愿。如果你连不到夏夏账本，直接告诉我。"

    /// 给 AI 看的：用户刚装好、第一次让它记账时怎么带。MCP 工具 welcome 返回这段。
    public static let welcomeGuide = """
    用户刚装好夏夏账本，这是第一次让你记账。照下面带着走：语气轻松，用用户说话的语言，每次只问一句，不要把账本里的内容念给用户听。
    1. 先调 context 看有哪些账本和账户。
    2. 只问一句：「今天花了什么？」等用户回答，再用 add_transaction 记下来（支出是负数）。金额、账户、账本没说清楚、你拿不准的，先问再记。记完用一句话说记了什么。
    3. 再问一句：「有没有想存钱达成的心愿？」（比如旅行、换手机、应急的钱）有就问清名字和金额，用 add_goal 建一个存钱目标；没有就跳过。context 里的 aim 是用户在引导里定的记账目标，问的时候可以顺着它问（比如目标是「每个月存下 300 €」，就问这笔钱想存来做什么）。
    4. 最后说「回到夏夏账本看看吧」，有 aim 就围着它鼓励一句，再举三个以后可以怎么跟你说的例子（比如「今天打车 12」「这个月吃饭花了多少」「拍张小票发给我」）。
    规矩：只记用户在这次对话里亲口说的；金额不要自己编。
    """

    /// 「一键复制配置提示词」：粘给任何 AI（Claude Code、Codex、Hermes、Gemini CLI、Cursor、Claude 桌面版……），
    /// 它自己判断能不能跑命令：能就跑 fin setup 装好 MCP + skill + 提示词；不能就告诉用户粘哪段配置。最后调一次只读的 summary 确认。
    public static func setupPrompt(fin: String) -> String {
        let names = AIApp.allCases.map(\.name).joined(separator: "、")
        return """
        请帮我把记账软件「夏夏账本」接到你身上。接好后我就能直接跟你说「今天超市花了 23,40」「这个月花了多少」，你来记账、查账。

        夏夏账本已经装在这台 Mac 上，它自带一个命令行工具，完整路径是：
        "\(fin)"

        请按顺序做：

        1. 你能在这台 Mac 上运行终端命令吗？
           能（比如你是 Claude Code、Codex、Hermes、Gemini CLI，或 Cursor 的 Agent）：
           a. 先运行 "\(fin)" setup --dry-run ，用一两句话告诉我它会改哪些文件。
           b. 再运行 "\(fin)" setup 。它会找出这台 Mac 上装了的 AI 工具（\(names)），给每个接上 MCP 服务「xiaxia-ledger」、装好使用说明（skill）和提示词；每个文件改之前先留一份 .bak-xiaxia 备份，最后自己读一次账本确认能用。
           c. 把它最后几行（✓ / ✗ 那几行）原样告诉我。有 ✗ 就照它说的处理，处理不了就告诉我卡在哪。
           如果你的沙盒或权限设置挡住了这些命令，就请我放行，或者让我自己在「终端」里粘贴运行上面这条 setup。
           不能运行命令（比如你是 Claude 桌面版或网页版）：直接跳到第 2 步。

        2. 如果上一步没把「你自己」配上（比如你不在上面那些工具里），请把下面这段加进你的 MCP 服务器设置（stdio 类型）；你自己改不了设置的话，一步一步告诉我该点哪里、粘到哪儿：
        \(configSnippet(fin: fin))
           Claude 桌面版也可以在夏夏账本 app 的「设置 → 连上你的 AI」里直接点「连上」。

        3. 确认能用：配好后，如果要重开你（或新开一个对话）才能看到新工具，就告诉我怎么做，我做完会再找你。
           能看到 xiaxia-ledger 的工具时，调用它的 summary 工具（只读），参数 month 填这个月（如 2026-11），把结果用一句话告诉我，再说「夏夏账本连好了」，并举两个以后可以怎么跟你说的例子。
           （你在无人值守模式下跑、调工具要先批准的话，请先放行 xiaxia-ledger 的 context 和 summary 这两个只读工具。）
           暂时看不到工具时，运行 "\(fin)" setup --check 确认账本能读到。

        4. 连好以后问我一个问题（你有提问工具或选项卡，比如 Claude Code 的 AskUserQuestion，就用它让我点；没有就用文字问）：
           「要不要我定时问你一下有没有漏记的开销？」选项：每天晚上 / 每周一次 / 不用。
           选了每天或每周：用你自己的定时功能（定时任务、cron、提醒都行）设好，到点先说一句这段时间记了多少，再问我有没有没记的，直接说或者拍小票都行。
           你没有定时功能就直接告诉我，不要假装设好了。

        5. 最后用一两句话告诉我以后可以怎么用：
           - 不管在聊什么，我说到自己花了钱、收了钱，你都记进夏夏账本（它是我记账的唯一入口）；
           - 我拍小票、单子、账单截图发给你，你读出来先给我看一眼，我说好再记；
           - 要我选的时候（哪个账户、什么分类），用选项让我点。
           这几条 fin setup 已经写进你的全局提示词了；如果你是在第 2 步手动配的，请把它们也记进你的长期记忆或自定义指令里。

        规矩：只改上面说的这些设置；不要直接改账本文件；没有我同意不要往账本里写东西。
        """
    }

    public func configURL(_ app: AIApp) -> URL { home.appendingPathComponent(app.configPath) }

    /// 这个工具的命令行在哪（app 内对话栏要在后台调用它）。Claude 桌面版、Cursor 没有可以后台调的命令行，返回 nil。
    /// GUI app 拿不到终端里的 PATH，所以按常见安装位置找。
    public func cliExecutable(_ app: AIApp) -> String? {
        guard let name = app.cliBinary else { return nil }
        let dirs = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin",
                    home.appendingPathComponent(".claude/local").path, home.appendingPathComponent(".npm-global/bin").path,
                    home.appendingPathComponent(".bun/bin").path, "/usr/bin"]
        return dirs.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 这台 Mac 上有没有这个工具。
    public func isInstalled(_ app: AIApp) -> Bool {
        let fm = FileManager.default
        if app.homeMarkers.contains(where: { fm.fileExists(atPath: home.appendingPathComponent($0).path) }) { return true }
        return app.appBundles.contains { b in appFolders.contains { fm.fileExists(atPath: $0.appendingPathComponent(b).path) } }
    }

    /// 配置里 xiaxia-ledger 指向的命令（没配就是 nil）。
    public func configuredCommand(_ app: AIApp) -> String? {
        let url = configURL(app)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if app == .codex {
            return TOMLSection.command(in: String(decoding: data, as: UTF8.self), server: Self.serverName)
        }
        if app == .hermes {
            return YAMLSection.command(in: String(decoding: data, as: UTF8.self), server: Self.serverName)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = obj["mcpServers"] as? [String: Any],
              let entry = servers[Self.serverName] as? [String: Any] else { return nil }
        return entry["command"] as? String
    }

    /// 连好了：配置里有 xiaxia-ledger，而且指向的 fin 还在（app 挪过位置、删过就不算）。
    public func isConnected(_ app: AIApp) -> Bool {
        guard let cmd = configuredCommand(app) else { return false }
        return FileManager.default.isExecutableFile(atPath: (cmd as NSString).expandingTildeInPath)
    }

    /// 配过，但指向的 fin 已经不在了（比如 app 换了位置）：该重新写一次。
    public func needsRepair(_ app: AIApp) -> Bool {
        guard let cmd = configuredCommand(app) else { return false }
        return !FileManager.default.isExecutableFile(atPath: (cmd as NSString).expandingTildeInPath)
    }

    /// 把 xiaxia-ledger 写进这个工具的配置。可以反复调，结果一样。返回改了哪个文件。
    @discardableResult
    public func connect(_ app: AIApp) throws -> URL {
        let url = configURL(app)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = (try? Data(contentsOf: url)) ?? Data()
        let new: Data
        if app == .codex {
            new = Data(TOMLSection.upsert(String(decoding: old, as: UTF8.self), server: Self.serverName, command: fin).utf8)
        } else if app == .hermes {
            new = Data(YAMLSection.upsert(String(decoding: old, as: UTF8.self), server: Self.serverName, command: fin).utf8)
        } else {
            var obj: [String: Any] = [:]
            if !old.isEmpty, !String(decoding: old, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let parsed = try? JSONSerialization.jsonObject(with: old) as? [String: Any] else {
                    throw ConnectError.unreadableConfig(url.path)
                }
                obj = parsed
            }
            var servers = obj["mcpServers"] as? [String: Any] ?? [:]
            // 已经是这样了就不重写（字典重新输出时键的顺序可能变，免得每次都改文件）
            if let entry = servers[Self.serverName] as? [String: Any], entry["command"] as? String == fin,
               entry["args"] as? [String] == ["mcp"] { return url }
            servers[Self.serverName] = ["command": fin, "args": ["mcp"]] as [String: Any]
            obj["mcpServers"] = servers
            var data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
            data.append(0x0A)
            new = data
        }
        guard new != old else { return url }
        backupOnce(url)
        try new.write(to: url, options: .atomic)
        return url
    }

    /// 从这个工具的配置里拿掉 xiaxia-ledger。
    public func disconnect(_ app: AIApp) throws {
        let url = configURL(app)
        guard let old = try? Data(contentsOf: url), !old.isEmpty else { return }
        let new: Data
        if app == .codex {
            new = Data(TOMLSection.remove(String(decoding: old, as: UTF8.self), server: Self.serverName).utf8)
        } else if app == .hermes {
            new = Data(YAMLSection.remove(String(decoding: old, as: UTF8.self), server: Self.serverName).utf8)
        } else {
            guard var obj = try? JSONSerialization.jsonObject(with: old) as? [String: Any] else { throw ConnectError.unreadableConfig(url.path) }
            guard var servers = obj["mcpServers"] as? [String: Any], servers[Self.serverName] != nil else { return }
            servers[Self.serverName] = nil
            obj["mcpServers"] = servers
            var data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
            data.append(0x0A)
            new = data
        }
        guard new != old else { return }
        backupOnce(url)
        try new.write(to: url, options: .atomic)
    }

    /// 只在第一次改的时候留备份：.bak-xiaxia 是装之前的原样，以后不覆盖。
    private func backupOnce(_ url: URL) {
        let fm = FileManager.default
        let bak = url.appendingPathExtension("bak-xiaxia")
        guard fm.fileExists(atPath: url.path), !fm.fileExists(atPath: bak.path) else { return }
        try? fm.copyItem(at: url, to: bak)
    }
}

/// Codex 的 config.toml：只处理 [mcp_servers.xiaxia-ledger] 这一节，其他原样留着。
enum TOMLSection {
    static func header(_ server: String) -> String { "[mcp_servers.\(server)]" }

    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 去掉这一节（包括 [mcp_servers.xiaxia-ledger.env] 这样的子节）。
    static func remove(_ text: String, server: String) -> String {
        let h = header(server)
        let sub = "[mcp_servers.\(server)."
        var out: [Substring] = []
        var skipping = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { skipping = (t == h || t.hasPrefix(sub)) }
            if !skipping { out.append(line) }
        }
        var s = out.joined(separator: "\n")
        while s.hasSuffix("\n\n") { s.removeLast() }
        return s
    }

    static func upsert(_ text: String, server: String, command: String) -> String {
        let section = "\(header(server))\ncommand = \(quoted(command))\nargs = [\"mcp\"]\n"
        let rest = remove(text, server: server).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? section : rest + "\n\n" + section
    }

    static func command(in text: String, server: String) -> String? {
        let h = header(server)
        var inside = false
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { inside = (t == h); continue }
            guard inside, t.hasPrefix("command"), t.dropFirst(7).trimmingCharacters(in: .whitespaces).hasPrefix("=") else { continue }
            guard let eq = t.firstIndex(of: "=") else { continue }
            var v = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard v.count >= 2, let q = v.first, q == "\"" || q == "'" else { continue }
            v.removeFirst()
            if let end = v.lastIndex(of: q) { v = String(v[..<end]) }
            return v.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        return nil
    }
}

/// Hermes Agent 的 ~/.hermes/config.yaml：只处理顶层 mcp_servers: 下面 xiaxia-ledger 这一项，其他原样留着。
/// 不引入 YAML 库，按缩进逐行处理（Hermes 文档里的写法：两格缩进、command / args 各一行）。
enum YAMLSection {
    static func indent(_ line: Substring) -> Int { line.prefix { $0 == " " }.count }
    static func isBlankOrComment(_ line: Substring) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces); return t.isEmpty || t.hasPrefix("#")
    }
    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// mcp_servers: 这一块的行号范围（不含标题行），以及子项的缩进。
    static func block(_ lines: [Substring]) -> (header: Int, end: Int, childIndent: Int)? {
        guard let h = lines.firstIndex(where: { indent($0) == 0 && $0.hasPrefix("mcp_servers:") }) else { return nil }
        var end = h + 1
        var child = 0
        while end < lines.count {
            let l = lines[end]
            if !isBlankOrComment(l) {
                if indent(l) == 0 { break }
                if child == 0 { child = indent(l) }
            }
            end += 1
        }
        // 块末尾的空行留给下一节
        while end > h + 1, isBlankOrComment(lines[end - 1]), lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        return (h, end, child == 0 ? 2 : child)
    }

    /// 在块里找 xiaxia-ledger: 这一项的行号范围。
    static func entry(_ lines: [Substring], _ b: (header: Int, end: Int, childIndent: Int), server: String) -> Range<Int>? {
        guard let start = (b.header + 1 ..< b.end).first(where: {
            indent(lines[$0]) == b.childIndent && lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("\(server):")
        }) else { return nil }
        var end = start + 1
        // 属于这一项的：更深缩进的行和中间的空行（同级缩进的注释算下一项的，不带走）
        while end < b.end, lines[end].trimmingCharacters(in: .whitespaces).isEmpty || indent(lines[end]) > b.childIndent { end += 1 }
        while end > start + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        return start ..< end
    }

    static func remove(_ text: String, server: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let b = block(lines), let r = entry(lines, b, server: server) else { return text }
        lines.removeSubrange(r)
        return lines.joined(separator: "\n")
    }

    static func upsert(_ text: String, server: String, command: String) -> String {
        let cleaned = remove(text, server: server)
        var lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false)
        func entryLines(_ ind: Int) -> [Substring] {
            let p = String(repeating: " ", count: ind)
            return ["\(p)\(server):", "\(p)  command: \(quoted(command))", "\(p)  args: [\"mcp\"]"].map { Substring($0) }
        }
        if let b = block(lines) {
            let header = lines[b.header].trimmingCharacters(in: .whitespaces)
            if header != "mcp_servers:" {
                // mcp_servers: {} 或 mcp_servers: null 这种写在一行的：换成块
                guard header.replacingOccurrences(of: " ", with: "") == "mcp_servers:{}" || header.hasSuffix("null") || header.hasSuffix("~") else { return text }
                lines[b.header] = "mcp_servers:"
            }
            lines.insert(contentsOf: entryLines(b.childIndent), at: b.header + 1)
            return lines.joined(separator: "\n")
        }
        var out = cleaned
        while out.hasSuffix("\n\n") { out.removeLast() }
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        if !out.isEmpty { out += "\n" }
        return out + (["mcp_servers:"] + entryLines(2).map(String.init)).joined(separator: "\n") + "\n"
    }

    static func command(in text: String, server: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let b = block(lines), let r = entry(lines, b, server: server) else { return nil }
        for l in lines[r].dropFirst() {
            let t = l.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("command:") else { continue }
            var v = t.dropFirst(8).trimmingCharacters(in: .whitespaces)
            if let q = v.first, q == "\"" || q == "'" {
                v.removeFirst()
                if let e = v.lastIndex(of: q) { v = String(v[..<e]) }
                if q == "\"" { v = v.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
            }
            return v
        }
        return nil
    }
}

/// AI 工具什么时候连上过账本：fin mcp 每次握手记一笔（工具名 → 时间），app 的引导页据此显示「连上了」。
/// 只记工具名和时间，不记对话内容。放在账本旁边的 ai-connections.json。
public enum AIConnections {
    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["XIAXIA_LEDGER_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath).deletingLastPathComponent()
                .appendingPathComponent("ai-connections.json")
        }
        return LedgerStores.appSupportFolder.appendingPathComponent("ai-connections.json")
    }

    public static func load(_ url: URL = defaultURL) -> [String: Date] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        let f = ISO8601DateFormatter()
        return raw.compactMapValues { f.date(from: $0) }
    }

    public static func record(client: String, at date: Date = Date(), _ url: URL = defaultURL) {
        var all = load(url)
        all[client] = date
        let f = ISO8601DateFormatter()
        let raw = all.mapValues { f.string(from: $0) }
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
