import Foundation

/// 把夏夏账本接到这台 Mac 上的 AI 工具：找出装了哪些，帮它们写好 MCP 配置。
/// app 的「连 AI」引导和 fin 都只用这一份。只改配置里 xiaxia-ledger 这一项，别的不碰；第一次改之前在旁边留一份 .bak-xiaxia。
public enum AIApp: String, CaseIterable, Identifiable, Codable, Sendable {
    case claudeDesktop, claudeCode, codex, cursor, gemini

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .claudeDesktop: "Claude 桌面版"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
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
        case .cursor: "cursor"
        case .gemini: "gemini"
        }
    }

    public static func from(cliName: String) -> AIApp? { allCases.first { $0.cliName == cliName.lowercased() } }

    /// 写好配置之后要做什么才能用上。
    public var afterConnect: String {
        switch self {
        case .claudeDesktop: "完全退出 Claude（⌘Q）再打开"
        case .claudeCode: "新开一个 Claude Code 对话"
        case .codex: "重开 Codex"
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

    /// 「复制一段话给 AI，让它自己配好」：能在这台 Mac 上跑命令的 AI（Claude Code、Codex……）直接跑 fin connect；
    /// 不能跑命令的，照着里面的配置自己加，或者告诉用户去哪儿粘。
    public static func setupPrompt(fin: String) -> String {
        let names = AIApp.allCases.map(\.cliName).joined(separator: " / ")
        return """
        请帮我把记账软件「夏夏账本」接到你身上（MCP），接好后我就能让你帮我记账、看账。

        夏夏账本已经装在这台 Mac 上，它的 MCP 服务是：\(fin) mcp

        1. 如果你能在这台 Mac 上运行命令：先运行 "\(fin)" connect --list 看看状态，再运行 "\(fin)" connect 你自己的名字（\(names) 之一）。
        2. 如果你不在上面这些里，或者不能运行命令：把下面这段加进你的 MCP 服务器设置（stdio 类型）；你自己改不了设置的话，告诉我该点哪里、粘到哪儿。
        \(configSnippet(fin: fin))
        3. 配好后告诉我要不要重启你、怎么重启。重启后调用 xiaxia-ledger 的 context 工具，确认能读到账本，再跟我说一句「连好了」。
        不要改这段以外的设置，也不要动账本文件。
        """
    }

    public func configURL(_ app: AIApp) -> URL { home.appendingPathComponent(app.configPath) }

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
