import Foundation

/// 一条命令把夏夏账本装进 AI 工具：MCP 服务、使用说明（skill）、全局提示词。`fin setup` 和 app 的「连上」都用它。
/// 规矩和 AIConnector 一样：只动夏夏账本自己的那一项 / 那一段，第一次改一个文件前在旁边留 .bak-xiaxia。
public struct AISetup: Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public var what: String
        public var path: String
        /// 这一步改了文件（预演时是「会改」）。
        public var changed: Bool
        public var note: String?
    }

    public static let promptStart = "<!-- xiaxia-ledger:start（夏夏账本写入；拿掉用 fin setup --remove）-->"
    static let promptStartPrefix = "<!-- xiaxia-ledger:start"
    public static let promptEnd = "<!-- xiaxia-ledger:end -->"
    /// skill 目录里放这个文件，说明是夏夏账本装的（以后更新、拿掉只动有它的目录）。
    static let marker = ".xiaxia-ledger"

    public var connector: AIConnector
    public var home: URL { connector.home }
    public var fin: String { connector.fin }

    public init(connector: AIConnector) { self.connector = connector }

    /// skill 的正本：~/.agents/skills/fin（Codex 等直接读这里，其他工具链到这里）。
    public var skillFolder: URL { home.appendingPathComponent(".agents/skills/fin") }

    /// 这个工具从哪读 skill（要它的主目录在才链）。
    func skillLink(_ app: AIApp) -> URL? {
        switch app {
        case .claudeCode: home.appendingPathComponent(".claude/skills/fin")
        case .codex: home.appendingPathComponent(".codex/skills/fin")
        case .hermes: home.appendingPathComponent(".hermes/skills/fin")
        case .claudeDesktop, .cursor, .gemini: nil
        }
    }

    /// 这个工具的全局指令文件（每次对话都会读）。
    func promptFile(_ app: AIApp) -> URL? {
        switch app {
        case .claudeCode: home.appendingPathComponent(".claude/CLAUDE.md")
        case .codex: home.appendingPathComponent(".codex/AGENTS.md")
        case .gemini: home.appendingPathComponent(".gemini/GEMINI.md")
        case .claudeDesktop, .cursor, .hermes: nil
        }
    }

    /// 工具的主目录（在才往里写 skill 链接和提示词）。
    func toolHome(_ app: AIApp) -> URL? {
        switch app {
        case .claudeCode: home.appendingPathComponent(".claude")
        case .codex: home.appendingPathComponent(".codex")
        case .hermes: home.appendingPathComponent(".hermes")
        case .gemini: home.appendingPathComponent(".gemini")
        case .claudeDesktop, .cursor: nil
        }
    }

    /// PROMPT.md 里两条 --- 之间的那段。
    public static var promptBlock: String {
        let text = SkillBundle.files.first { $0.path == "PROMPT.md" }?.text ?? ""
        let parts = (text + "\n").components(separatedBy: "\n---\n")
        return (parts.count >= 3 ? parts[1] : text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 装

    /// 给这些工具装好。dryRun 时只说会改什么。
    public func install(_ apps: [AIApp], dryRun: Bool = false) -> [Step] {
        var steps: [Step] = []
        steps.append(contentsOf: linkFin(dryRun: dryRun))
        steps.append(installSkillFolder(dryRun: dryRun))
        for app in apps {
            // MCP
            let url = connector.configURL(app)
            if dryRun {
                steps.append(Step(what: "\(app.name)：MCP", path: url.path, changed: !connector.isConnected(app) || connector.configuredCommand(app) != fin))
            } else {
                do {
                    let before = try? Data(contentsOf: url)
                    try connector.connect(app)
                    steps.append(Step(what: "\(app.name)：MCP", path: url.path, changed: before != (try? Data(contentsOf: url))))
                } catch {
                    steps.append(Step(what: "\(app.name)：MCP", path: url.path, changed: false,
                                      note: Self.explain(error)))
                }
            }
            guard let toolHome = toolHome(app), FileManager.default.fileExists(atPath: toolHome.path) else { continue }
            if let link = skillLink(app) { steps.append(linkSkill(at: link, app: app, dryRun: dryRun)) }
            if let file = promptFile(app) { steps.append(writePrompt(file, app: app, dryRun: dryRun)) }
        }
        return steps
    }

    /// app 更新后：之前装过的使用说明（skill）和提示词换成新版的。只动夏夏账本自己装的：
    /// skill 目录里有标记文件才换；提示词文件里已经有夏夏账本那段才换那一段。没装过的一概不碰。
    @discardableResult
    public func refreshInstalled() -> [Step] {
        let fm = FileManager.default
        var steps: [Step] = []
        if fm.fileExists(atPath: skillFolder.appendingPathComponent(Self.marker).path) {
            let step = installSkillFolder(dryRun: false)
            if step.changed { steps.append(step) }
        }
        for app in AIApp.allCases {
            guard let file = promptFile(app), let text = try? String(contentsOf: file, encoding: .utf8),
                  Self.blockRange(text) != nil else { continue }
            let step = writePrompt(file, app: app, dryRun: false)
            if step.changed { steps.append(step) }
        }
        return steps
    }

    /// app 里点「连上」：写 MCP（写不成就报错），再顺手装好 skill 和提示词（这些写不成不算失败）。
    public func connect(_ app: AIApp) throws {
        try connector.connect(app)
        _ = install([app])
    }

    /// ~/.local/bin/fin 指向自己，提示词里写的 fin 就能用。那里已经有一个真文件（不是链接）就不碰。
    func linkFin(dryRun: Bool) -> [Step] {
        let fm = FileManager.default
        let link = home.appendingPathComponent(".local/bin/fin")
        let target = URL(fileURLWithPath: fin).resolvingSymlinksInPath().path
        if link.resolvingSymlinksInPath().path == target { return [] }
        let isLink = (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil
        if fm.fileExists(atPath: link.path) && !isLink {
            return [Step(what: "命令行 fin", path: link.path, changed: false, note: "那里已经有一个 fin，没动它")]
        }
        if !dryRun {
            try? fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if isLink { try? fm.removeItem(at: link) }
            do { try fm.createSymbolicLink(atPath: link.path, withDestinationPath: fin) }
            catch { return [Step(what: "命令行 fin", path: link.path, changed: false, note: Self.explain(error))] }
        }
        return [Step(what: "命令行 fin", path: link.path, changed: true)]
    }

    func installSkillFolder(dryRun: Bool) -> Step {
        let fm = FileManager.default
        let dir = skillFolder
        let what = "使用说明（skill）"
        let isLink = (try? fm.destinationOfSymbolicLink(atPath: dir.path)) != nil
        let ours = fm.fileExists(atPath: dir.appendingPathComponent(Self.marker).path)
        let same = !isLink && SkillBundle.files.allSatisfy {
            (try? String(contentsOf: dir.appendingPathComponent($0.path), encoding: .utf8)) == $0.text + "\n"
        }
        if same && ours { return Step(what: what, path: dir.path, changed: false) }
        var note: String?
        if dryRun { return Step(what: what, path: dir.path, changed: true) }
        do {
            if isLink {
                try fm.removeItem(at: dir)   // 以前用源码装的是链接，换成实文件
            } else if fm.fileExists(atPath: dir.path) && !ours {
                // 不是夏夏账本装的同名目录：整个挪到旁边留着
                let bak = dir.deletingLastPathComponent().appendingPathComponent("fin.bak-xiaxia")
                if !fm.fileExists(atPath: bak.path) { try fm.moveItem(at: dir, to: bak); note = "原来的同名目录挪到了 \(bak.path)" }
                else { try fm.removeItem(at: dir) }
            }
            for f in SkillBundle.files {
                let url = dir.appendingPathComponent(f.path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data((f.text + "\n").utf8).write(to: url, options: .atomic)
            }
            try Data("夏夏账本 fin setup 装的。fin setup --remove 会拿掉这个目录。\n".utf8).write(to: dir.appendingPathComponent(Self.marker))
            return Step(what: what, path: dir.path, changed: true, note: note)
        } catch {
            return Step(what: what, path: dir.path, changed: false, note: Self.explain(error))
        }
    }

    func linkSkill(at link: URL, app: AIApp, dryRun: Bool) -> Step {
        let fm = FileManager.default
        let what = "\(app.name)：skill"
        if let dest = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            if dest == skillFolder.path { return Step(what: what, path: link.path, changed: false) }
            if !dryRun { try? fm.removeItem(at: link) }
        } else if fm.fileExists(atPath: link.path) {
            // 真目录：是我们以前复制进去的就换掉，别人的不碰
            guard fm.fileExists(atPath: link.appendingPathComponent(Self.marker).path) else {
                return Step(what: what, path: link.path, changed: false, note: "那里已经有一个别的 fin 目录，没动它")
            }
            if !dryRun { try? fm.removeItem(at: link) }
        }
        if !dryRun {
            do {
                try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.createSymbolicLink(atPath: link.path, withDestinationPath: skillFolder.path)
            } catch { return Step(what: what, path: link.path, changed: false, note: Self.explain(error)) }
        }
        return Step(what: what, path: link.path, changed: true)
    }

    func writePrompt(_ file: URL, app: AIApp, dryRun: Bool) -> Step {
        let what = "\(app.name)：提示词"
        let old = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let new = Self.upsertBlock(old, block: Self.promptBlock)
        guard new != old else { return Step(what: what, path: file.path, changed: false) }
        if !dryRun {
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                backupOnce(file)
                try Data(new.utf8).write(to: file, options: .atomic)
            } catch { return Step(what: what, path: file.path, changed: false, note: Self.explain(error)) }
        }
        return Step(what: what, path: file.path, changed: true)
    }

    /// 把标记包起来的那段换成新的；没有就加在最后。别的内容原样。
    static func upsertBlock(_ text: String, block: String) -> String {
        let section = "\(promptStart)\n\(block)\n\(promptEnd)"
        if let r = blockRange(text) {
            var s = text
            s.replaceSubrange(r, with: section)
            return s
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "" : text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) + "\n\n") + section + "\n"
    }

    static func removeBlock(_ text: String) -> String {
        guard let r = blockRange(text) else { return text }
        var s = text
        s.removeSubrange(r)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : s.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) + "\n"
    }

    static func blockRange(_ text: String) -> Range<String.Index>? {
        guard let a = text.range(of: promptStartPrefix),
              let b = text.range(of: promptEnd, range: a.upperBound ..< text.endIndex) else { return nil }
        return a.lowerBound ..< b.upperBound
    }

    /// 写不进文件时说人话：多半是 AI 工具自己的沙盒挡住了（比如 Codex 只让写工作目录）。
    static func explain(_ error: Error) -> String {
        let ns = error as NSError
        let denied = [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code)
            || (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { $0.domain == NSPOSIXErrorDomain && [1, 13].contains($0.code) } == true
        if denied { return "没有权限写这个文件（多半是 AI 工具的沙盒挡住了）。请自己在「终端」里运行 fin setup，或在夏夏账本 app 里点「连上」" }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: 拿掉

    /// 从这些工具里拿掉；装的 skill 目录在最后一个工具也拿掉后删除（all 为 true 时）。
    public func remove(_ apps: [AIApp], all: Bool, dryRun: Bool = false) -> [Step] {
        let fm = FileManager.default
        var steps: [Step] = []
        for app in apps {
            let url = connector.configURL(app)
            if connector.configuredCommand(app) != nil {
                if !dryRun {
                    do { try connector.disconnect(app) }
                    catch { steps.append(Step(what: "\(app.name)：MCP", path: url.path, changed: false, note: Self.explain(error))); continue }
                }
                steps.append(Step(what: "\(app.name)：MCP", path: url.path, changed: true))
            }
            if let link = skillLink(app), let dest = try? fm.destinationOfSymbolicLink(atPath: link.path), dest == skillFolder.path {
                if !dryRun { try? fm.removeItem(at: link) }
                steps.append(Step(what: "\(app.name)：skill", path: link.path, changed: true))
            }
            if let file = promptFile(app), let old = try? String(contentsOf: file, encoding: .utf8), Self.blockRange(old) != nil {
                if !dryRun { try? Data(Self.removeBlock(old).utf8).write(to: file, options: .atomic) }
                steps.append(Step(what: "\(app.name)：提示词", path: file.path, changed: true))
            }
        }
        if all {
            if fm.fileExists(atPath: skillFolder.appendingPathComponent(Self.marker).path) {
                if !dryRun { try? fm.removeItem(at: skillFolder) }
                steps.append(Step(what: "使用说明（skill）", path: skillFolder.path, changed: true))
            }
            let link = home.appendingPathComponent(".local/bin/fin")
            if let dest = try? fm.destinationOfSymbolicLink(atPath: link.path),
               URL(fileURLWithPath: dest).resolvingSymlinksInPath().path == URL(fileURLWithPath: fin).resolvingSymlinksInPath().path {
                if !dryRun { try? fm.removeItem(at: link) }
                steps.append(Step(what: "命令行 fin", path: link.path, changed: true))
            }
        }
        return steps
    }

    /// 这几个工具都装好了没有（MCP 指向能用的 fin；能装 skill 的已链上）。
    public func isComplete(_ app: AIApp) -> Bool {
        guard connector.isConnected(app) else { return false }
        guard let toolHome = toolHome(app), FileManager.default.fileExists(atPath: toolHome.path) else { return true }
        if let link = skillLink(app), (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != skillFolder.path { return false }
        if let file = promptFile(app), let text = try? String(contentsOf: file, encoding: .utf8) { return Self.blockRange(text) != nil }
        return promptFile(app) == nil
    }

    private func backupOnce(_ url: URL) {
        let fm = FileManager.default
        let bak = url.appendingPathExtension("bak-xiaxia")
        guard fm.fileExists(atPath: url.path), !fm.fileExists(atPath: bak.path) else { return }
        try? fm.copyItem(at: url, to: bak)
    }
}
