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
        XCTAssertTrue(p.contains(#""/Applications/夏夏账本.app/Contents/MacOS/fin" setup"#))
        XCTAssertTrue(p.contains(#""/Applications/夏夏账本.app/Contents/MacOS/fin" setup --check"#))
        XCTAssertTrue(p.contains("xiaxia-ledger"))
        XCTAssertTrue(p.contains("summary"), "要让 AI 最后调一次只读的 summary 确认")
        XCTAssertTrue(p.contains(#""command" : "/Applications/夏夏账本.app/Contents/MacOS/fin""#), "不能跑命令的 AI 要有能粘的配置")
        for app in AIApp.allCases { XCTAssertEqual(AIApp.from(cliName: app.cliName), app); XCTAssertTrue(p.contains(app.name)) }
        // ming 2026-11-23：配置时问要不要定时问（每天 / 每周），用提问工具问；告诉用户能拍小票。
        XCTAssertTrue(p.contains("每天晚上") && p.contains("每周一次") && p.contains("AskUserQuestion") && p.contains("拍小票"))
    }

    /// ming 2026-11-23：新手的 AI 配不好。提示词要 AI 自己配、自己开权限、用提问框要授权、不截屏、配完自测直到连上、接不了的直说换哪个。
    func testSetupPromptLetsAIConfigureItself() {
        let p = AIConnector.setupPrompt(fin: "/x/fin")
        for word in ["自己能开的权限就自己开", "提问框", "不要让我自己去翻设置", "不要截屏", "直到连上", "ChatGPT", "Codex", "连接你的 AI", "总是允许", "setup --check"] {
            XCTAssertTrue(p.contains(word), word)
        }
        XCTAssertFalse(p.contains("--dry-run"), "新手不用先预演，少一次批准")
    }

    func testPromptMakesLedgerTheEntryPoint() {
        let block = AISetup.promptBlock
        for word in ["唯一入口", "小票", "AskUserQuestion", "定时"] { XCTAssertTrue(block.contains(word), word) }
        let skill = SkillBundle.files.first { $0.path == "SKILL.md" }?.text ?? ""
        for word in ["唯一入口", "拍小票", "AskUserQuestion", "定时问一问"] { XCTAssertTrue(skill.contains(word), word) }
        // 通用版：不写具体某个人的名字和店名。
        for word in ["ming", "Miora"] { XCTAssertFalse(block.contains(word) || skill.contains(word), word) }
    }

    func testWelcomeSentenceAndGuide() {
        XCTAssertTrue(AIConnector.welcomeSentence.contains("夏夏账本"), "一句人话，点名夏夏账本，AI 才知道用哪个工具")
        XCTAssertLessThan(AIConnector.welcomeSentence.count, 100, "给用户复制的要短，不能是一大段技术说明")
        for word in ["MCP", "/", "fin ", "context", "add_"] {
            XCTAssertFalse(AIConnector.welcomeSentence.contains(word), "给用户看的话里不出现技术词：\(word)")
        }
        XCTAssertTrue(AIConnector.welcomeSentence.contains("今天花了什么") && AIConnector.welcomeSentence.contains("连不到"))
        let g = AIConnector.welcomeGuide
        XCTAssertTrue(g.contains("今天花了什么"))
        XCTAssertTrue(g.contains("add_transaction") && g.contains("add_goal"))
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

    func testRefreshInstalledOnlyTouchesWhatWeInstalled() throws {
        // 没装过：什么都不碰
        try write(".codex/AGENTS.md", "# 别人的\n")
        XCTAssertTrue(setup.refreshInstalled().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.skillFolder.path))
        XCTAssertEqual(try read(".codex/AGENTS.md"), "# 别人的\n")
        // 装过，然后 app 更新：旧的 skill 和提示词段换成新的，别的内容不动
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try write(".claude/CLAUDE.md", "# 我的\n")
        _ = setup.install([.claudeCode])
        try write(".agents/skills/fin/SKILL.md", "旧说明\n")
        try write(".claude/CLAUDE.md", "# 我的\n\n\(AISetup.promptStart)\n旧提示词\n\(AISetup.promptEnd)\n")
        let steps = setup.refreshInstalled()
        XCTAssertEqual(steps.count, 2, "\(steps)")
        XCTAssertTrue(try read(".agents/skills/fin/SKILL.md").contains("name: fin"))
        let md = try read(".claude/CLAUDE.md")
        XCTAssertTrue(md.hasPrefix("# 我的\n") && md.contains("## 夏夏账本") && !md.contains("旧提示词"))
        XCTAssertEqual(try read(".codex/AGENTS.md"), "# 别人的\n", "没装过提示词的文件不加")
        XCTAssertTrue(setup.refreshInstalled().isEmpty, "已经是新的就不改")
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

    // MARK: 连接体检（设置里的圆点）

    func testHealthLevels() throws {
        let c = connector
        XCTAssertEqual(c.health(.claudeDesktop).level, .idle)
        XCTAssertEqual(c.health(.claudeDesktop).title, "这台 Mac 上没找到")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Applications/Claude.app"), withIntermediateDirectories: true)
        XCTAssertEqual(c.health(.claudeDesktop).title, "装了，还没连")
        try c.connect(.claudeDesktop)
        let waiting = c.health(.claudeDesktop, selfTest: AISelfTestResult(ok: true, message: "ok"))
        XCTAssertEqual(waiting.level, .waiting)
        XCTAssertTrue(waiting.fix?.contains("⌘Q") == true, "要告诉新手怎么重开")
        XCTAssertEqual(c.health(.claudeDesktop, selfTest: AISelfTestResult(ok: false, message: "坏了")).level, .problem)
        XCTAssertEqual(c.health(.claudeDesktop, lastSeen: Date()).level, .good)
        // fin 不见了（app 换了位置）
        try FileManager.default.removeItem(at: fin)
        XCTAssertEqual(c.health(.claudeDesktop).level, .problem)
    }

    func testParseSelfTest() {
        let ok = #"{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"2026-11 收入 0,00 €"}],"isError":false}}"#
        XCTAssertTrue(AIConnector.parseSelfTest(ok, month: "2026-11").ok)
        XCTAssertFalse(AIConnector.parseSelfTest(ok, month: "2026-11").message.contains("€"), "不把金额带出来")
        let bad = #"{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"找不到账本"}],"isError":true}}"#
        XCTAssertFalse(AIConnector.parseSelfTest(bad, month: "2026-11").ok)
        XCTAssertFalse(AIConnector.parseSelfTest("", month: "2026-11").ok)
    }

    #if os(macOS)
    func testSelfTestRunsConfiguredCommand() throws {
        let c = connector
        XCTAssertFalse(c.selfTest(.claudeDesktop).ok, "没配过")
        try c.connect(.claudeDesktop)
        XCTAssertFalse(c.selfTest(.claudeDesktop).ok, "假 fin 什么都不回答")
        // 假 fin：读一行，回答「收入」；看到 XIAXIA_SELFTEST 才回答，确认自测不会被记成 AI 连上过。
        let script = """
        #!/bin/sh
        read line
        [ "$XIAXIA_SELFTEST" = "1" ] || exit 1
        echo '{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"收入 0"}],"isError":false}}'
        """
        try Data(script.utf8).write(to: fin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fin.path)
        XCTAssertTrue(c.selfTest(.claudeDesktop).ok)
    }
    #endif

    func testUnsupportedChatGPT() throws {
        XCTAssertTrue(connector.unsupportedInstalled().isEmpty)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Applications/ChatGPT.app"), withIntermediateDirectories: true)
        XCTAssertEqual(connector.unsupportedInstalled(), [.chatGPT])
        XCTAssertTrue(UnsupportedAI.chatGPT.advice.contains("Codex"), "接不了的要直说换哪个")
    }
}
