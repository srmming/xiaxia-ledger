#if os(macOS)
import FinanceCore
import Foundation
import XCTest

/// 对话栏在后台调用本机 AI 命令行：参数、环境、输出解析、给 AI 的话。
final class ChatRunnerTests: XCTestCase {
    func testArguments() {
        let c = ChatEngine.claude.arguments(prompt: "午饭 12 欧", resume: "abc")
        XCTAssertEqual(Array(c.prefix(2)), ["-p", "午饭 12 欧"])
        XCTAssertTrue(c.contains("--allowedTools") && c.contains("mcp__xiaxia-ledger"))
        XCTAssertEqual(Array(c.suffix(2)), ["--resume", "abc"])
        XCTAssertFalse(ChatEngine.claude.arguments(prompt: "x", resume: nil).contains("--resume"))
        XCTAssertEqual(ChatEngine.codex.arguments(prompt: "x", resume: nil), ["exec", "--skip-git-repo-check", "x"])
        XCTAssertEqual(ChatEngine.hermes.arguments(prompt: "x", resume: nil), ["-z", "x"])
    }

    func testClaudeGetsAppFinAsOnlyMCP() {
        let a = ChatEngine.claude.arguments(prompt: "x", resume: nil, fin: "/Applications/夏夏账本.app/Contents/MacOS/fin")
        let i = try! XCTUnwrap(a.firstIndex(of: "--mcp-config"))
        let obj = try! JSONSerialization.jsonObject(with: Data(a[i + 1].utf8)) as! [String: [String: [String: Any]]]
        XCTAssertEqual(obj["mcpServers"]?["xiaxia-ledger"]?["command"] as? String, "/Applications/夏夏账本.app/Contents/MacOS/fin")
        XCTAssertEqual(obj["mcpServers"]?["xiaxia-ledger"]?["args"] as? [String], ["mcp"])
        XCTAssertTrue(a.contains("--strict-mcp-config"))
        XCTAssertFalse(ChatEngine.claude.arguments(prompt: "x", resume: nil).contains("--mcp-config"))
    }

    func testCandidatesPreferLocalAndBun() {
        let codex = ChatEngine.candidates(.codex, home: "/Users/someone")
        XCTAssertEqual(codex.first, "/Users/someone/.local/bin/codex")
        XCTAssertLessThan(codex.firstIndex(of: "/Users/someone/.bun/bin/codex")!, codex.firstIndex(of: "/opt/homebrew/bin/codex")!)
        XCTAssertTrue(ChatEngine.candidates(.claude, home: "/h").contains("/h/.claude/local/claude"))
        XCTAssertTrue(ChatEngine.available(home: "/nonexistent-home").allSatisfy { $0.executable(home: "/nonexistent-home") != nil })
    }

    func testEnvironmentKeepsLoginAndPath() {
        let env = ChatEngine.environment(base: ["HOME": "/Users/a", "USER": "a", "SECRET_TOKEN": "x"], home: "/Users/a")
        XCTAssertEqual(env["USER"], "a")
        XCTAssertEqual(env["LOGNAME"], "a")
        XCTAssertNil(env["SECRET_TOKEN"], "别的环境变量不带过去")
        XCTAssertTrue(env["PATH"]!.hasPrefix("/Users/a/.local/bin:"))
    }

    func testParseClaudeJSON() {
        let ok = ChatRunner.parse(.claude, stdout: #"{"type":"result","is_error":false,"result":"记好了：午饭 12,00 €","session_id":"s1"}"#, stderr: "", status: 0)
        XCTAssertEqual(ok.text, "记好了：午饭 12,00 €")
        XCTAssertEqual(ok.sessionID, "s1")
        XCTAssertFalse(ok.isError)
        let login = ChatRunner.parse(.claude, stdout: #"{"is_error":true,"result":"Not logged in · Please run /login"}"#, stderr: "", status: 1)
        XCTAssertTrue(login.isError)
        XCTAssertTrue(login.text.contains("还没登录"))
    }

    func testParsePlainAndFailure() {
        XCTAssertEqual(ChatRunner.parse(.hermes, stdout: "OK\n", stderr: "", status: 0).text, "OK")
        let bad = ChatRunner.parse(.codex, stdout: "", stderr: "a\nb\nenv: node: No such file or directory", status: 127)
        XCTAssertTrue(bad.isError)
        XCTAssertTrue(bad.text.contains("127") && bad.text.contains("node"))
    }

    func testPrompt() {
        let p = ChatRunner.prompt(question: "这笔是什么", voice: "用毒舌的口吻。", aim: "每个月存下 500 €",
                                  where: "用户正在看「流水」页。", history: [(true, "你好"), (false, "你好呀")])
        XCTAssertTrue(p.contains("current_view"))
        XCTAssertTrue(p.contains("毒舌"))
        XCTAssertTrue(p.contains("每个月存下 500 €"))
        XCTAssertTrue(p.contains("用户：你好") && p.contains("夏夏：你好呀"))
        XCTAssertTrue(p.hasSuffix("用户这一句：这笔是什么"))
    }

    /// 用一个假的命令行（shell 脚本）跑一遍完整流程：能启动、能读输出。
    func testAskRunsFakeHermes() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("hermes")
        try "#!/bin/sh\necho \"收到：$2\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        XCTAssertEqual(ChatEngine.hermes.executable(home: home.path), script.path)
        let reply = await ChatRunner.ask(.hermes, prompt: "你好", executable: script.path, timeout: 10)
        XCTAssertFalse(reply.isError, reply.text)
        XCTAssertEqual(reply.text, "收到：你好")
    }
}
#endif
