import ArgumentParser
import FinanceCore
import Foundation

/// `fin connect`：把夏夏账本的 MCP 写进这台 Mac 上 AI 工具的配置。app 的「连上你的 AI」用的是同一套规则（FinanceCore/AIConnect）。
/// 给 AI 自己跑用：用户把 app 里「复制一段话给 AI」那段发给 Claude Code / Codex，它们跑这个命令把自己连上。
struct ConnectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "把夏夏账本连到 AI 工具（写 MCP 配置）。",
        discussion: """
        fin connect --list              看哪些 AI 工具装了、连没连
        fin connect claude-desktop      连 Claude 桌面版（可写多个：codex cursor …）
        fin connect --all               连所有装了的
        fin connect --remove codex      从 Codex 拿掉
        能连的：\(AIApp.allCases.map(\.cliName).joined(separator: "、"))。只改配置里 xiaxia-ledger 这一项，第一次改前留 .bak-xiaxia。
        """)

    @Argument(help: "要连的工具") var tools: [String] = []
    @Flag(name: .long, help: "只列出状态") var list = false
    @Flag(name: .long, help: "连所有装了的") var all = false
    @Flag(name: .long, help: "拿掉，不是连上") var remove = false
    @Flag(name: .long, help: "只说会改什么，不改") var dryRun = false
    @Flag(name: .long, help: "输出 JSON") var json = false

    func run() throws {
        let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())
        let c = AIConnector(home: home, fin: Self.selfPath)
        if list || (tools.isEmpty && !all) {
            let rows = AIApp.allCases.map { app -> [String: Any] in
                ["tool": app.cliName, "name": app.name, "installed": c.isInstalled(app), "connected": c.isConnected(app),
                 "needsRepair": c.needsRepair(app), "config": c.configURL(app).path]
            }
            if json {
                let data = try JSONSerialization.data(withJSONObject: ["fin": Self.selfPath, "tools": rows], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                print(String(decoding: data, as: UTF8.self))
            } else {
                print("fin：\(Self.selfPath)")
                for app in AIApp.allCases {
                    let state = c.isConnected(app) ? "已连上" : c.needsRepair(app) ? "连过但路径失效，要重连" : c.isInstalled(app) ? "装了，没连" : "没装"
                    print("\(app.cliName)\t\(app.name)\t\(state)")
                }
                if tools.isEmpty && !all && !list { print("\n要连哪个就运行：fin connect <名字>，或 fin connect --all") }
            }
            return
        }
        var targets: [AIApp] = []
        for t in tools {
            guard let app = AIApp.from(cliName: t) else {
                throw ValidationError("不认识 \(t)。能连的：\(AIApp.allCases.map(\.cliName).joined(separator: "、"))。别的工具请把 MCP 配置粘进它的设置：\n\(AIConnector.configSnippet(fin: Self.selfPath))")
            }
            targets.append(app)
        }
        if all { targets += AIApp.allCases.filter { c.isInstalled($0) && !targets.contains($0) } }
        if targets.isEmpty { print("这台 Mac 上没找到能自动连的 AI 工具。"); return }
        for app in targets {
            if dryRun { print("（预演）会\(remove ? "从" : "把夏夏账本写进 ")\(c.configURL(app).path)\(remove ? " 拿掉夏夏账本" : "")"); continue }
            if remove {
                try c.disconnect(app); print("已从 \(app.name) 拿掉")
            } else {
                let url = try c.connect(app)
                print("已连上 \(app.name)（\(url.path)）。\(app.afterConnect)后就能用。")
            }
        }
    }

    /// 自己的完整路径（写进配置的就是它）。
    static var selfPath: String {
        let arg = CommandLine.arguments.first ?? "fin"
        var url = URL(fileURLWithPath: arg)
        if !arg.contains("/") {
            // 从 PATH 里找到的
            for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
                let u = URL(fileURLWithPath: String(dir)).appendingPathComponent(arg)
                if FileManager.default.isExecutableFile(atPath: u.path) { url = u; break }
            }
        }
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
