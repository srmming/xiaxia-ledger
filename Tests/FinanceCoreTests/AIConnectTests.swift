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
        XCTAssertTrue(p.contains(#""/Applications/夏夏账本.app/Contents/MacOS/fin" connect --list"#))
        XCTAssertTrue(p.contains("xiaxia-ledger"))
        for app in AIApp.allCases { XCTAssertEqual(AIApp.from(cliName: app.cliName), app); XCTAssertTrue(p.contains(app.cliName)) }
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
