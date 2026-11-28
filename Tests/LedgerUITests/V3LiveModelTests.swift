#if os(macOS)
import XCTest
import FinanceCore
@testable import LedgerUI

/// 真的连 OpenRouter 跑一遍「三组示例」。平时跳过：只有环境变量 XIAXIA_LIVE_OPENROUTER_KEY 里给了密钥才跑。
/// 密钥只在这次运行的内存里（不进钥匙串、不落盘、不打印）；发出去的只有编的三组示例。
@MainActor
final class V3LiveModelTests: XCTestCase {
    func testRunDecisionSamplesAgainstOpenRouter() async throws {
        guard let key = ProcessInfo.processInfo.environment["XIAXIA_LIVE_OPENROUTER_KEY"], !key.isEmpty else { throw XCTSkip("没给密钥，不连网") }
        let s = V3State()
        s.onboardingStep = nil
        s.keyStore = MemorySecretStore()
        s.transport = URLSessionOpenRouterTransport()
        XCTAssertTrue(s.saveAPIKey(key, provider: .openrouter))
        s.setModel(decision: "microsoft/microsoft-decision-1.1", chat: "deepseek/deepseek-v4.1-flash-1017")
        await s.runDecisionSamples()
        XCTAssertFalse(s.decisionReport.joined().contains(key), "结果里没有密钥")
        for line in s.decisionReport { print("LIVE", line) }
        if let reply = await s.askChatModel("这个月还能随便花多少？一句话。") { print("LIVE 聊天模型回了一句：", reply.contains(key) ? "（含密钥，不显示）" : reply) }
        else { print("LIVE 聊天模型没回（或没开用聊天模型）") }
    }
}
#endif
