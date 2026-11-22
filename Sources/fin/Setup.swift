import ArgumentParser
import FinanceCore
import Foundation

/// fin setup：一条命令把夏夏账本装进这台 Mac 上的 AI 工具（MCP + skill + 提示词），装完自己读一次账本确认能用。
/// 「复制一段话给 AI」里让 AI 跑的就是它。
struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "把夏夏账本装进这台 Mac 上的 AI 工具：MCP、使用说明（skill）、提示词，装完自检。",
        discussion: """
        fin setup --dry-run        先看会改哪些文件（不改）
        fin setup                  给所有装了的 AI 工具装好，然后自检
        fin setup codex hermes     只装这几个（名字见 fin connect --list）
        fin setup --check          不改，只检查装好没有、账本读不读得到
        fin setup --remove         全部拿掉（MCP、skill、提示词）
        每个文件第一次改之前在旁边留一份 .bak-xiaxia；只动夏夏账本自己的那一项 / 那一段。
        """)

    @Argument(help: "只装这些工具（不写就是所有装了的）") var tools: [String] = []
    @Flag(name: .long, help: "只说会改什么，不改") var dryRun = false
    @Flag(name: .long, help: "不改，只检查") var check = false
    @Flag(name: .long, help: "拿掉，不是装上") var remove = false
    @Flag(name: .long, help: "输出 JSON") var json = false

    func run() throws {
        let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())
        let fin = ConnectCommand.selfPath
        let setup = AISetup(connector: AIConnector(home: home, fin: fin))
        let c = setup.connector

        var apps: [AIApp] = []
        for t in tools {
            guard let app = AIApp.from(cliName: t) else {
                throw ValidationError("不认识 \(t)。能装的：\(AIApp.allCases.map(\.cliName).joined(separator: "、"))。别的工具请把这段粘进它的 MCP 设置：\n\(AIConnector.configSnippet(fin: fin))")
            }
            apps.append(app)
        }
        let explicit = !apps.isEmpty
        if !explicit {
            apps = remove ? AIApp.allCases.filter { c.configuredCommand($0) != nil || c.isInstalled($0) } : AIApp.allCases.filter { c.isInstalled($0) }
        }

        let steps: [AISetup.Step]
        if check { steps = [] }
        else if remove { steps = setup.remove(apps, all: !explicit, dryRun: dryRun) }
        else { steps = setup.install(apps, dryRun: dryRun) }

        let verify = (dryRun || remove) ? nil : Self.verify(fin: fin)
        let status = apps.map { app in
            Status(tool: app.cliName, name: app.name, ready: setup.isComplete(app), next: app.afterConnect)
        }

        if json {
            struct Out: Encodable { var fin: String; var dryRun: Bool; var steps: [AISetup.Step]; var tools: [Status]; var check: Check? }
            return try Output.json(Out(fin: fin, dryRun: dryRun, steps: steps, tools: status, check: verify))
        }

        print("fin：\(fin)")
        if apps.isEmpty {
            print(remove ? "没找到装过夏夏账本的 AI 工具。" : """
            这台 Mac 上没找到能自动配的 AI 工具（\(AIApp.allCases.map(\.name).joined(separator: "、"))）。
            别的 AI 工具：把下面这段粘进它的 MCP 服务器设置（stdio 类型）：
            \(AIConnector.configSnippet(fin: fin))
            """)
        }
        if !check {
            let changed = steps.filter(\.changed)
            if steps.isEmpty || (changed.isEmpty && steps.allSatisfy { $0.note == nil }) {
                if !apps.isEmpty { print(remove ? "没有要拿掉的。" : "都已经装好了，没有要改的。") }
            }
            for s in steps where s.changed || s.note != nil {
                let verb = remove ? (dryRun ? "会拿掉" : "已拿掉") : (dryRun ? "会改" : "已装好")
                print("\(s.changed ? verb : "跳过")\t\(s.what)\t\(s.path)\(s.note.map { "（\($0)）" } ?? "")")
            }
            if dryRun { print("（预演，什么都没改。去掉 --dry-run 正式装。）") }
        }
        if !remove && !dryRun {
            print("")
            for s in status { print("\(s.ready ? "✓" : "✗")\t\(s.name)\t\(s.ready ? "装好了，\(s.next)后就能用" : "没装完整，看上面的说明")") }
            if let v = verify {
                print(v.ok ? "✓\t账本自检\t\(v.message)" : "✗\t账本自检\t\(v.message)")
            }
            if verify?.ok == true && status.contains(where: \.ready) {
                print("\n装好了。按上面说的重开一次 AI 工具，然后对它说「这个月花了多少」试试。")
            }
        }
        if verify?.ok == false { throw ExitCode.failure }
    }

    struct Status: Encodable { var tool: String; var name: String; var ready: Bool; var next: String }
    struct Check: Encodable { var ok: Bool; var message: String }

    /// 像 AI 工具那样启动 fin mcp，调一次只读的 summary（本月），看能不能读到账本。
    static func verify(fin: String) -> Check {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: fin)
        p.arguments = ["mcp"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return Check(ok: false, message: "fin mcp 启动不了：\(error.localizedDescription)") }
        let month = LocalDate.today.yearMonth.description
        // 不发 initialize：那会把「fin setup」记成一个连上过的 AI 工具
        let call = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"summary","arguments":{"month":"\#(month)"}}}"#
        input.fileHandleForWriting.write(Data((call + "\n").utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first,
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String else {
            return Check(ok: false, message: "fin mcp 没有正常回答")
        }
        if result["isError"] as? Bool == true { return Check(ok: false, message: text) }
        let first = text.split(separator: "\n").first.map(String.init) ?? text
        return Check(ok: true, message: "MCP 能读到账本（\(month)：\(first)）")
    }
}
