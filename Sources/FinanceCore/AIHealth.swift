import Foundation

/// 「连接 AI」的体检：一个 AI 工具现在连到哪一步了，差哪步用大白话说。
/// app 设置里每个 AI 一个圆点（绿 / 橙 / 红 / 灰）就看这个；规则只写在这里，app 和 fin 都用它。
public struct AIHealth: Equatable, Sendable {
    public enum Level: String, Sendable {
        /// 绿：AI 真的用过账本了。
        case good
        /// 橙：配置写好、自测也过了，等用户重开一次 AI。
        case waiting
        /// 红：写过了但用不了（记账服务打不开、夏夏账本换了位置）。
        case problem
        /// 灰：还没连（装了没连，或者这台 Mac 上没有）。
        case idle
    }

    public var level: Level
    /// 一行状态，比如「写好了，等你重开 Claude」。
    public var title: String
    /// 下一步怎么做（大白话）；没什么要做的就是 nil。
    public var fix: String?

    public init(level: Level, title: String, fix: String? = nil) {
        self.level = level
        self.title = title
        self.fix = fix
    }
}

/// 自测结果：像 AI 工具那样启动配置里写的那个命令，问一次只读的 summary，看能不能读到账本。
public struct AISelfTestResult: Equatable, Sendable {
    public var ok: Bool
    /// 给人看的一句话（不带金额）。
    public var message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}

extension AIConnector {
    /// 这个 AI 工具现在怎么样了。
    /// - selfTest: 刚才自测的结果（没测过就是 nil）。
    /// - lastSeen: 这个 AI 最近一次真的用账本的时间（fin mcp 握手记的）。
    public func health(_ app: AIApp, selfTest: AISelfTestResult? = nil, lastSeen: Date? = nil) -> AIHealth {
        if needsRepair(app) {
            return AIHealth(level: .problem, title: "以前连过，但夏夏账本换了位置",
                            fix: "点「重新连接」就好")
        }
        if isConnected(app) {
            if let test = selfTest, !test.ok {
                return AIHealth(level: .problem, title: "写好了，但记账服务打不开",
                                fix: test.message)
            }
            if let lastSeen {
                return AIHealth(level: .good, title: "连上了 · \(Self.friendly(lastSeen)) 用过账本")
            }
            return AIHealth(level: .waiting, title: selfTest?.ok == true ? "写好了，自测能读到账本" : "写好了",
                            fix: "\(app.afterConnect)，然后跟它说一句「这个月花了多少」，这里就会变绿")
        }
        if isInstalled(app) {
            return AIHealth(level: .idle, title: "装了，还没连", fix: "点「连接」，夏夏账本帮你写好")
        }
        return AIHealth(level: .idle, title: "这台 Mac 上没找到")
    }

    static func friendly(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 120 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if Calendar.current.isDate(date, inSameDayAs: now) { return "今天" }
        if s < 86400 * 2 { return "昨天" }
        return "\(Int(s / 86400)) 天前"
    }

    #if os(macOS)
    /// 自测：用这个 AI 配置里写的那个命令启动 fin mcp（AI 工具也是这么启动的），调一次只读的 summary。
    /// 不发 initialize，并带上 XIAXIA_SELFTEST，fin 就不会把自测记成「有 AI 连上过」。
    public func selfTest(_ app: AIApp, timeout: TimeInterval = 15) -> AISelfTestResult {
        guard let cmd = configuredCommand(app) else {
            return AISelfTestResult(ok: false, message: "\(app.name) 的设置里还没有夏夏账本，点「连接」")
        }
        return Self.selfTest(command: (cmd as NSString).expandingTildeInPath, timeout: timeout)
    }

    /// 直接测一个 fin（fin setup 装完也用它）。
    public static func selfTest(command: String, timeout: TimeInterval = 15) -> AISelfTestResult {
        guard FileManager.default.isExecutableFile(atPath: command) else {
            return AISelfTestResult(ok: false, message: "找不到夏夏账本自带的记账服务（\(command)）。夏夏账本是不是挪了位置或删了？打开 app 再点一次「连接」")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command)
        p.arguments = ["mcp"]
        var env = ProcessInfo.processInfo.environment
        env["XIAXIA_SELFTEST"] = "1"
        p.environment = env
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch {
            return AISelfTestResult(ok: false, message: "记账服务启动不了：\(error.localizedDescription)。可能是 macOS 拦住了，打开一次夏夏账本 app 再试")
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let month = LocalDate.today.yearMonth.description
        let call = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"summary","arguments":{"month":"\#(month)"}}}"#
        input.fileHandleForWriting.write(Data((call + "\n").utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return parseSelfTest(String(decoding: data, as: UTF8.self), month: month)
    }
    #endif

    /// 读 fin mcp 的回答。只说读没读到，不把金额带出来。
    static func parseSelfTest(_ output: String, month: String) -> AISelfTestResult {
        guard let line = output.split(separator: "\n").first,
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String else {
            return AISelfTestResult(ok: false, message: "记账服务没有正常回答。重开一次夏夏账本 app 再点「连接」试试")
        }
        if result["isError"] as? Bool == true {
            return AISelfTestResult(ok: false, message: "记账服务读账本出错：\(text.prefix(120))")
        }
        let read = text.contains("收入") || text.contains("没有")
        return read ? AISelfTestResult(ok: true, message: "能读到账本（自测调了一次只读的 summary，\(month)）")
                    : AISelfTestResult(ok: false, message: "记账服务的回答看不懂：\(text.prefix(80))")
    }
}

/// 这台 Mac 上装了、但接不了本机账本的 AI：如实说，并告诉换哪个。
public enum UnsupportedAI: String, CaseIterable, Identifiable, Sendable {
    case chatGPT

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .chatGPT: "ChatGPT"
        }
    }

    var appBundles: [String] {
        switch self {
        case .chatGPT: ["ChatGPT.app"]
        }
    }

    /// 为什么连不了、换哪个。
    public var advice: String {
        switch self {
        case .chatGPT: "ChatGPT app 现在接不了电脑上的账本。用同一个 ChatGPT 账号登录 Codex 就能连，装好回来点「连接」"
        }
    }

    public var alternativeURL: String {
        switch self {
        case .chatGPT: "https://openai.com/codex/"
        }
    }

    public var alternativeTitle: String {
        switch self {
        case .chatGPT: "下载 Codex"
        }
    }
}

extension AIConnector {
    /// 装了、但接不了的 AI。
    public func unsupportedInstalled() -> [UnsupportedAI] {
        let fm = FileManager.default
        return UnsupportedAI.allCases.filter { u in
            u.appBundles.contains { b in appFolders.contains { fm.fileExists(atPath: $0.appendingPathComponent(b).path) } }
        }
    }
}
