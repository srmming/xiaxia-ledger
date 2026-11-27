#if os(macOS)
import FinanceCore
import Security
import SwiftUI

// 用自己的 API 密钥连 AI。
// 密钥只进这台 Mac 的钥匙串：不进账本、不进偏好设置、不进日志和改动记录；存好以后界面上不再显示，app 也不把它读回来。
// 试用版只做填、存、换、删和「已填 / 没填」，不拿密钥去发请求。

/// 这台 Mac 的钥匙串（登录钥匙串里的一条通用密码，名字是这个试用版自己的）。
struct KeychainSecretStore: SecretStore {
    let service: String

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func save(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        var status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base(account)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "夏夏账本 v3 试用 · AI 密钥"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TrialError("没存进钥匙串（\(status)）。再试一次，或者先在「钥匙串访问」里看看") }
    }

    /// 只问有没有：不要求把密钥的内容还回来。
    func has(_ account: String) -> Bool {
        var q = base(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    func delete(_ account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TrialError("没从钥匙串里删掉（\(status)），再试一次") }
    }
}

extension V3State {
    /// 跑测试时不碰真的钥匙串，用内存里的假货。
    static func defaultKeyStore() -> SecretStore {
        NSClassFromString("XCTestCase") != nil ? MemorySecretStore() : KeychainSecretStore(service: "com.srmming.xiaxia-ledger.v3demo.ai-key")
    }

    static let aiOwnAPI = "自己的 API"
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
            V3SetMenu(options: AIKeyProvider.allCases.map(\.shortTitle),
                      pick: Binding(get: { AIKeyProvider.allCases.firstIndex(of: provider) ?? 0 }, set: { provider = AIKeyProvider.allCases[$0] }))
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
    @State private var provider = AIKeyProvider.anthropic
    @State private var key = ""
    @State private var address = ""

    var body: some View {
        let had = state.apiProvider
        V3SheetBox(width: 640, title: had == nil ? "自己的 API" : "换一把密钥", hint: "只存在这台 Mac 的钥匙串里。试用版不会拿它去连 AI。", primary: "存好",
                   canSave: !key.trimmingCharacters(in: .whitespaces).isEmpty,
                   save: {
                       if state.saveAPIKey(key, provider: provider, address: address) { key = ""; state.closeSheet() }
                   }) {
            V3APIKeyFields(provider: $provider, key: $key, address: $address)
        }
        .onAppear { if let had { provider = had }; address = state.apiAddress }
    }
}
#endif
