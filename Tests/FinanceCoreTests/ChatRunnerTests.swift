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
        XCTAssertEqual(ChatEngine.hermes.arguments(prompt: "x", resume: nil), ["-z", "x", "-t", "xiaxia-ledger"])
    }

    /// 选了模型才加参数；没选（跟随默认）不加，用的就是用户在那个 AI 里自己设的模型。
    func testModelChoice() throws {
        let c = ChatEngine.claude.arguments(prompt: "x", resume: nil, model: "sonnet")
        let i = try XCTUnwrap(c.firstIndex(of: "--model"))
        XCTAssertEqual(c[i + 1], "sonnet")
        XCTAssertFalse(ChatEngine.claude.arguments(prompt: "x", resume: nil).contains("--model"))
        XCTAssertEqual(ChatEngine.codex.arguments(prompt: "x", resume: nil, model: "some-model"),
                       ["exec", "--skip-git-repo-check", "--model", "some-model", "x"])
        XCTAssertEqual(ChatEngine.hermes.arguments(prompt: "x", resume: nil, model: "y"), ["-z", "x", "-t", "xiaxia-ledger"])
        XCTAssertEqual(ChatEngine.claude.models().map(\.id), ["fable", "opus", "sonnet", "haiku"])

        // 读各家自己的设置：默认模型、Codex 用过的模型（假的主目录，名字都是编的）。
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("chat-model-\(UUID().uuidString)")
        let fm = FileManager.default
        for d in [".claude", ".codex", ".hermes"] { try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: home) }
        XCTAssertNil(ChatEngine.claude.defaultModel(home: home.path))
        try Data(#"{"model": "claude-sonnet-9"}"#.utf8).write(to: home.appendingPathComponent(".claude/settings.json"))
        XCTAssertEqual(ChatEngine.claude.defaultModel(home: home.path), "Sonnet")
        try Data("model = \"model-a\"\nmodel_reasoning_effort = \"high\"\n\n[profiles.fast]\nmodel = 'model-b'\n[profiles.again]\nmodel = \"model-a\"\n".utf8)
            .write(to: home.appendingPathComponent(".codex/config.toml"))
        XCTAssertEqual(ChatEngine.codex.defaultModel(home: home.path), "model-a")
        XCTAssertEqual(ChatEngine.codex.models(home: home.path).map(\.id), ["model-b"])   // model-a 就是默认，不再列
        try Data("model:\n  default: model-h\n  provider: x\ntoolsets: []\n".utf8).write(to: home.appendingPathComponent(".hermes/config.yaml"))
        XCTAssertEqual(ChatEngine.hermes.defaultModel(home: home.path), "model-h")
        XCTAssertTrue(ChatEngine.hermes.models(home: home.path).isEmpty)
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

    /// 日志不能记下提问：三家参数里提问的位置都不一样。
    func testLogRedactsPromptWherever() {
        let q = "系统提示……用户：我这个月花了多少"
        for engine in [ChatEngine.claude, .codex, .hermes] {
            let shown = ChatRunner.redacted(engine.arguments(prompt: q, resume: nil), prompt: q)
            XCTAssertFalse(shown.contains(q), "\(engine) 的日志里有提问原文")
            XCTAssertTrue(shown.contains("<提问>"))
        }
        XCTAssertTrue(ChatRunner.redacted(ChatEngine.hermes.arguments(prompt: q, resume: nil), prompt: q).contains("xiaxia-ledger"))
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
