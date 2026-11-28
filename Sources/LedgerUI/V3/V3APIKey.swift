#if os(macOS)
import FinanceCore
import Security
import SwiftUI

// 用 OpenRouter 的密钥连 AI（一把密钥，决策和聊天两个模型共用）。
// 密钥只进这台 Mac 的钥匙串：不进账本、不进偏好设置、不进日志和改动记录；存好以后界面上不再显示，app 也不把它读回来。
// 填、存、换、删在这里；拿它发请求在 V3Decision.swift。

// 钥匙串那一层（KeychainSecretStore）在 FinanceCore/OpenRouterClient.swift，Mac 和 iPhone 共用。

extension V3State {
    /// 跑测试时不碰真的钥匙串，用内存里的假货。
    static func defaultKeyStore() -> SecretStore {
        NSClassFromString("XCTestCase") != nil ? MemorySecretStore() : KeychainSecretStore(service: "com.srmming.xiaxia-ledger.v3demo.ai-key", label: "夏夏账本 v3 试用 · AI 密钥")
    }

    static let aiOwnAPI = "OpenRouter"
    private static let addressKey = "xiaxia.v3demo.ai-address"

    /// 现在填了哪一家的密钥（没填是 nil）。
    var apiProvider: AIKeyProvider? { AIKeyProvider.allCases.first { keyStore.has($0.rawValue) } }
    /// 自定义地址（不是秘密，放偏好设置里）。
    var apiAddress: String { UserDefaults.standard.string(forKey: Self.addressKey) ?? "" }

    /// 存一把密钥：一次只留一家的，换一家就把原来那家的删掉。存完不留明文。返回存上了没有。
    @discardableResult
    func saveAPIKey(_ raw: String, provider: AIKeyProvider, address: String = "") -> Bool {
        do {
            let key = try AIKeyRules.cleanKey(raw)
            let addr = provider.needsAddress ? try AIKeyRules.cleanAddress(address) : ""
            for other in AIKeyProvider.allCases where other != provider { try keyStore.delete(other.rawValue) }
            try keyStore.save(key, for: provider.rawValue)
            if NSClassFromString("XCTestCase") == nil { UserDefaults.standard.set(addr, forKey: Self.addressKey) }
            keyRevision += 1
            ai = Self.aiOwnAPI
            say("存进这台 Mac 的钥匙串了 · \(provider.shortTitle)")
            return true
        } catch let e as TrialError { fail(e.message) } catch { fail("没存上，再试一次") }
        return false
    }

    func deleteAPIKey() {
        do {
            for p in AIKeyProvider.allCases { try keyStore.delete(p.rawValue) }
            if NSClassFromString("XCTestCase") == nil { UserDefaults.standard.removeObject(forKey: Self.addressKey) }
            keyRevision += 1
            if ai == Self.aiOwnAPI { ai = nil }
            say("密钥从钥匙串里删掉了")
        } catch let e as TrialError { fail(e.message) } catch { fail("没删掉，再试一次") }
    }
}

/// 填密钥的那一行：选哪家、粘密钥（遮住）、自定义地址时多一格地址。引导和设置里的弹窗共用。
struct V3APIKeyFields: View {
    @Binding var provider: AIKeyProvider
    @Binding var key: String
    @Binding var address: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            // 现在只连 OpenRouter 这一家（一把密钥，决策和聊天两个模型共用）
            Text("OpenRouter").font(V3.font(14, .heavy)).foregroundStyle(V3.ink).fixedSize()
            if provider.needsAddress {
                TextField("https://…", text: $address).textFieldStyle(.plain).font(V3.font(14, .bold)).foregroundStyle(V3.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8).frame(width: 220)
                    .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2)))
                    .accessibilityLabel("地址")
            }
            SecureField("粘贴密钥", text: $key).textFieldStyle(.plain).font(V3.font(14, .bold)).foregroundStyle(V3.ink)
                .padding(.horizontal, 14).padding(.vertical, 8).frame(width: provider.needsAddress ? 220 : 300)
                .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2)))
                .onSubmit(onSubmit)
                .accessibilityLabel("密钥")
        }
    }
}

/// 设置里填 / 换密钥的弹窗。
struct V3APIKeySheet: View {
    @Environment(V3State.self) private var state
    @State private var provider = AIKeyProvider.openrouter
    @State private var key = ""
    @State private var address = ""

    var body: some View {
        let had = state.apiProvider
        V3SheetBox(width: 640, title: had == nil ? "OpenRouter 的密钥" : "换一把密钥", hint: "只存在这台 Mac 的钥匙串里。", primary: "存好",
                   canSave: !key.trimmingCharacters(in: .whitespaces).isEmpty,
                   save: {
                       if state.saveAPIKey(key, provider: provider, address: address) { key = ""; state.closeSheet() }
                   }) {
            V3APIKeyFields(provider: $provider, key: $key, address: $address)
        }
        .onAppear { provider = .openrouter; address = "" }
    }
}
#endif
