import XCTest
@testable import FinanceCore

/// 「连 AI」引导：在临时的假主目录里试，不碰这台机器真的配置。
final class AIConnectTests: XCTestCase {
    var home: URL!
    var fin: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("xiaxia-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // 假的 fin（要可执行，才算「连好了」）
        fin = home.appendingPathComponent("App Folder/夏夏账本.app/Contents/MacOS/fin")
        try FileManager.default.createDirectory(at: fin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: fin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fin.path)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    var connector: AIConnector { AIConnector(home: home, fin: fin.path, appFolders: [home.appendingPathComponent("Applications")]) }

    func write(_ path: String, _ text: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ path: String) throws -> String { try String(contentsOf: home.appendingPathComponent(path), encoding: .utf8) }

    func testDetectsInstalledTools() throws {
        XCTAssertTrue(AIApp.allCases.allSatisfy { !connector.isInstalled($0) }, "空主目录什么都没装")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Applications/Claude.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try write(".claude.json", "{}")
        XCTAssertTrue(connector.isInstalled(.claudeDesktop))
        XCTAssertTrue(connector.isInstalled(.codex))
        XCTAssertTrue(connector.isInstalled(.claudeCode))
        XCTAssertFalse(connector.isInstalled(.cursor))
        XCTAssertFalse(connector.isInstalled(.gemini))
    }

    func testConnectJSONKeepsOtherSettings() throws {
        try write("Library/Application Support/Claude/claude_desktop_config.json",
                  #"{"theme":"dark","mcpServers":{"other":{"command":"/bin/echo","args":["hi"]}}}"#)
        XCTAssertFalse(connector.isConnected(.claudeDesktop))
        try connector.connect(.claudeDesktop)
        XCTAssertTrue(connector.isConnected(.claudeDesktop))
        let obj = try JSONSerialization.jsonObject(with: Data(try read(AIApp.claudeDesktop.configPath).utf8)) as! [String: Any]
        XCTAssertEqual(obj["theme"] as? String, "dark")
        let servers = obj["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["other"], "别的 MCP 不动")
        let mine = servers["xiaxia-ledger"] as! [String: Any]
        XCTAssertEqual(mine["command"] as? String, fin.path)
        XCTAssertEqual(mine["args"] as? [String], ["mcp"])
        // 第一次改之前留了原样的备份
        XCTAssertTrue(try read(AIApp.claudeDesktop.configPath + ".bak-xiaxia").contains("theme"))
        XCTAssertFalse(try read(AIApp.claudeDesktop.configPath + ".bak-xiaxia").contains("xiaxia-ledger"))
        // 再连一次结果一样
        let before = try read(AIApp.claudeDesktop.configPath)
        try connector.connect(.claudeDesktop)
        XCTAssertEqual(try read(AIApp.claudeDesktop.configPath), before)
        // 拿掉
        try connector.disconnect(.claudeDesktop)
        XCTAssertFalse(connector.isConnected(.claudeDesktop))
        XCTAssertTrue(try read(AIApp.claudeDesktop.configPath).contains("other"))
    }

    func testConnectCreatesMissingFile() throws {
        try connector.connect(.cursor)
        XCTAssertTrue(connector.isConnected(.cursor))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor/mcp.json.bak-xiaxia").path))
    }

    func testBrokenJSONIsLeftAlone() throws {
        try write(".gemini/settings.json", "{ not json")
        XCTAssertThrowsError(try connector.connect(.gemini)) { error in
            XCTAssertEqual(error as? AIConnector.ConnectError, .unreadableConfig(home.appendingPathComponent(".gemini/settings.json").path))
        }
        XCTAssertEqual(try read(".gemini/settings.json"), "{ not json")
    }

    func testCodexTOML() throws {
        try write(".codex/config.toml", """
        model = "gpt-5"

        [mcp_servers.xiaxia-ledger]
        command = "/old/place/fin"
        args = ["mcp"]

        [mcp_servers.xiaxia-ledger.env]
        A = "1"

        [mcp_servers.other]
        command = "other"
        """)
        XCTAssertEqual(connector.configuredCommand(.codex), "/old/place/fin")
        XCTAssertFalse(connector.isConnected(.codex))
        XCTAssertTrue(connector.needsRepair(.codex), "旧路径不在了，要重写")
        try connector.connect(.codex)
        let text = try read(".codex/config.toml")
        XCTAssertTrue(connector.isConnected(.codex))
        XCTAssertEqual(text.components(separatedBy: "[mcp_servers.xiaxia-ledger]").count, 2, "只有一节")
        XCTAssertFalse(text.contains("/old/place/fin"))
        XCTAssertFalse(text.contains("xiaxia-ledger.env"))
        XCTAssertTrue(text.contains("model = \"gpt-5\""))
        XCTAssertTrue(text.contains("[mcp_servers.other]\ncommand = \"other\""))
        try connector.connect(.codex)
        XCTAssertEqual(try read(".codex/config.toml"), text, "再连一次不变")
        try connector.disconnect(.codex)
        XCTAssertNil(connector.configuredCommand(.codex))
        XCTAssertTrue(try read(".codex/config.toml").contains("[mcp_servers.other]"))
    }

    func testHermesYAML() throws {
        // 没有配置文件：新建
        try connector.connect(.hermes)
        XCTAssertTrue(connector.isConnected(.hermes))
        XCTAssertEqual(try read(".hermes/config.yaml"), "mcp_servers:\n  xiaxia-ledger:\n    command: \"\(fin.path)\"\n    args: [\"mcp\"]\n")

        // 已有别的设置和别的 MCP：只动自己那项，换位置后再连只剩一份
        try write(".hermes/config.yaml", """
        model:
          provider: "deepseek"
          default: "deepseek-chat"

        mcp_servers:
          # 我的文件夹
          filesystem:
            command: "npx"
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
          xiaxia-ledger:
            command: "/old/fin"
            args: ["mcp"]
            env:
              A: "1"

        terminal:
          backend: local
        """)
        XCTAssertEqual(connector.configuredCommand(.hermes), "/old/fin")
        XCTAssertTrue(connector.needsRepair(.hermes))
        try connector.connect(.hermes)
        let text = try read(".hermes/config.yaml")
        XCTAssertTrue(connector.isConnected(.hermes))
        XCTAssertFalse(text.contains("/old/fin"))
        XCTAssertFalse(text.contains("A: \"1\""))
        XCTAssertEqual(text.components(separatedBy: "xiaxia-ledger:").count, 2)
        XCTAssertTrue(text.contains("provider: \"deepseek\""))
        XCTAssertTrue(text.contains("  filesystem:\n    command: \"npx\""))
        XCTAssertTrue(text.contains("# 我的文件夹"))
        XCTAssertTrue(text.contains("terminal:\n  backend: local"))
        try connector.connect(.hermes)
        XCTAssertEqual(try read(".hermes/config.yaml"), text, "再连一次不变")
        try connector.disconnect(.hermes)
        XCTAssertNil(connector.configuredCommand(.hermes))
        XCTAssertTrue(try read(".hermes/config.yaml").contains("filesystem:"))

        // mcp_servers: {} 写在一行
        try write(".hermes/config.yaml", "mcp_servers: {}\n")
        try connector.connect(.hermes)
        XCTAssertTrue(connector.isConnected(.hermes))
    }

    func testCLILookup() throws {
        let bin = home.appendingPathComponent(".local/bin/hermes")
        try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: bin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        XCTAssertEqual(connector.cliExecutable(.hermes), bin.path)
        XCTAssertNil(connector.cliExecutable(.claudeDesktop))
        XCTAssertEqual(AIApp.hermes.headlessArguments("你好"), ["-z", "你好", "-t", "xiaxia-ledger"])
        XCTAssertEqual(AIApp.from(clientName: "hermes-agent"), .hermes)
    }

    func testPathWithQuotesInTOML() throws {
        let odd = AIConnector(home: home, fin: #"/a "b"/fin"#)
        try odd.connect(.codex)
        XCTAssertEqual(odd.configuredCommand(.codex), #"/a "b"/fin"#)
    }

    func testSnippetAndClientNames() {
        XCTAssertTrue(AIConnector.configSnippet(fin: "/x/fin").contains(#""command" : "/x/fin""#))
        XCTAssertEqual(AIApp.from(clientName: "claude-ai"), .claudeDesktop)
        XCTAssertEqual(AIApp.from(clientName: "claude-code"), .claudeCode)
        XCTAssertEqual(AIApp.from(clientName: "codex-mcp-client"), .codex)
        XCTAssertEqual(AIApp.displayName(clientName: "cherry-studio"), "cherry-studio")
    }

    func testSetupPromptAndCLINames() {
        let p = AIConnector.setupPrompt(fin: "/Applications/夏夏账本.app/Contents/MacOS/fin")
        XCTAssertTrue(p.contains(#""/Applications/夏夏账本.app/Contents/MacOS/fin" setup --dry-run"#))
        XCTAssertTrue(p.contains(#""/Applications/夏夏账本.app/Contents/MacOS/fin" setup --check"#))
        XCTAssertTrue(p.contains("xiaxia-ledger"))
        XCTAssertTrue(p.contains("summary"), "要让 AI 最后调一次只读的 summary 确认")
        XCTAssertTrue(p.contains(#""command" : "/Applications/夏夏账本.app/Contents/MacOS/fin""#), "不能跑命令的 AI 要有能粘的配置")
        for app in AIApp.allCases { XCTAssertEqual(AIApp.from(cliName: app.cliName), app); XCTAssertTrue(p.contains(app.name)) }
    }

    func testWelcomePromptGuidesFirstEntry() {
        let p = AIConnector.welcomePrompt(fin: "/Applications/夏夏账本.app/Contents/MacOS/fin")
        XCTAssertTrue(p.contains(#""/Applications/夏夏账本.app/Contents/MacOS/fin" setup"#), "没连上时要能自己连")
        XCTAssertTrue(p.contains("今天花了什么"), "连上后由 AI 问第一笔")
        XCTAssertTrue(p.contains("add_transaction") && p.contains("add_goal"))
        XCTAssertTrue(p.contains("网页版"), "碰不到本机的 AI 要直说，不能假装记了")
    }

    // MARK: fin setup（MCP + skill + 提示词）

    var setup: AISetup { AISetup(connector: connector) }

    func testSkillBundleMatchesRepo() throws {
        // 打包进 fin 的 skill 要和仓库里 skills/fin 一样；不一样就跑 python3 scripts/gen-skill-bundle.py
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for f in SkillBundle.files {
            let text = try String(contentsOf: repo.appendingPathComponent("skills/fin").appendingPathComponent(f.path), encoding: .utf8)
            XCTAssertEqual(f.text + "\n", text, "\(f.path) 和打包的不一样，跑 python3 scripts/gen-skill-bundle.py")
        }
        XCTAssertTrue(AISetup.promptBlock.hasPrefix("## 夏夏账本"))
        XCTAssertFalse(AISetup.promptBlock.contains("---"))
    }

    func testSetupInstallsEverythingAndIsRepeatable() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try write(".claude.json", #"{"numStartups": 3}"#)
        try write(".claude/CLAUDE.md", "# 我自己的规矩\n别删我\n")
        let steps = setup.install([.claudeCode, .codex])
        XCTAssertTrue(steps.allSatisfy { $0.note == nil }, "\(steps)")
        // skill 正本 + 两个链接
        XCTAssertTrue(try read(".agents/skills/fin/SKILL.md").contains("name: fin"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".agents/skills/fin/references/commands.md").path))
        let fm = FileManager.default
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".claude/skills/fin").path), setup.skillFolder.path)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".codex/skills/fin").path), setup.skillFolder.path)
        XCTAssertTrue(try read(".claude/skills/fin/SKILL.md").contains("name: fin"), "链接能读到")
        // 提示词：原来的内容留着，加了一段
        let md = try read(".claude/CLAUDE.md")
        XCTAssertTrue(md.hasPrefix("# 我自己的规矩\n别删我\n\n"))
        XCTAssertTrue(md.contains(AISetup.promptStart) && md.contains(AISetup.promptEnd))
        XCTAssertEqual(try read(".claude/CLAUDE.md.bak-xiaxia"), "# 我自己的规矩\n别删我\n")
        XCTAssertTrue(try read(".codex/AGENTS.md").contains("## 夏夏账本"))
        // MCP
        XCTAssertTrue(connector.isConnected(.claudeCode))
        XCTAssertTrue(connector.isConnected(.codex))
        XCTAssertTrue(try read(".claude.json").contains("numStartups"))
        // 命令行 fin
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".local/bin/fin").path), fin.path)
        XCTAssertTrue(setup.isComplete(.claudeCode) && setup.isComplete(.codex))
        // 再跑一次什么都不改
        let again = setup.install([.claudeCode, .codex])
        XCTAssertTrue(again.allSatisfy { !$0.changed }, "\(again.filter(\.changed))")
        XCTAssertEqual(try read(".claude/CLAUDE.md"), md)
        // 预演不改文件
        let dry = AISetup(connector: connector).install([.gemini], dryRun: true)
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(".gemini/settings.json").path))
        XCTAssertTrue(dry.contains { $0.what.contains("Gemini") && $0.changed })
    }

    func testSetupReplacesOldBlockAndOldLink() throws {
        // 以前 install-global.sh 装的：skill 是指向仓库的链接，提示词标记带旧说明
        let repoSkill = home.appendingPathComponent("repo/skills/fin")
        try FileManager.default.createDirectory(at: repoSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".agents/skills"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: setup.skillFolder, withDestinationURL: repoSkill)
        try write(".codex/AGENTS.md", "前面\n\n<!-- xiaxia-ledger:start（由 xiaxia-ledger/scripts/install-global.sh 维护）-->\n旧的\n<!-- xiaxia-ledger:end -->\n\n后面\n")
        _ = setup.install([.codex])
        let agents = try read(".codex/AGENTS.md")
        XCTAssertFalse(agents.contains("旧的"))
        XCTAssertTrue(agents.hasPrefix("前面\n\n" + AISetup.promptStart))
        XCTAssertTrue(agents.hasSuffix(AISetup.promptEnd + "\n\n后面\n"))
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: setup.skillFolder.path), "换成了实目录")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoSkill.path), "仓库里的不动")
    }

    func testSetupLeavesForeignSkillFolderAside() throws {
        try write(".agents/skills/fin/SKILL.md", "别人的 fin skill")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let steps = setup.install([.codex])
        XCTAssertEqual(try read(".agents/skills/fin.bak-xiaxia/SKILL.md"), "别人的 fin skill")
        XCTAssertTrue(steps.contains { $0.note?.contains("fin.bak-xiaxia") == true })
        XCTAssertTrue(try read(".agents/skills/fin/SKILL.md").contains("name: fin"))
    }

    func testSetupExplainsSandboxDenial() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                             userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 1)])
        XCTAssertTrue(AISetup.explain(denied).contains("终端"))
        XCTAssertFalse(AISetup.explain(AIConnector.ConnectError.unreadableConfig("/x")).contains("终端"))
    }

    func testSetupRemoveTakesEverythingBack() throws {
        try write(".claude.json", "{}")
        try write(".claude/CLAUDE.md", "我的\n")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        _ = setup.install([.claudeCode, .codex])
        let steps = setup.remove([.claudeCode, .codex], all: true)
        XCTAssertFalse(steps.isEmpty)
        let fm = FileManager.default
        XCTAssertFalse(connector.isConnected(.claudeCode) || connector.isConnected(.codex))
        XCTAssertEqual(try read(".claude/CLAUDE.md"), "我的\n")
        XCTAssertEqual(try read(".codex/AGENTS.md"), "")
        XCTAssertFalse(fm.fileExists(atPath: setup.skillFolder.path))
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".claude/skills/fin").path))
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".local/bin/fin").path))
    }

    func testConnectionsLog() {
        let url = home.appendingPathComponent("ai-connections.json")
        XCTAssertTrue(AIConnections.load(url).isEmpty)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        AIConnections.record(client: "claude-ai", at: t, url)
        AIConnections.record(client: "codex", at: t.addingTimeInterval(60), url)
        let all = AIConnections.load(url)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all["claude-ai"], t)
    }
}
