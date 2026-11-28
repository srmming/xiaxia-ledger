import Foundation
#if canImport(Security)
import Security
#endif

// Mac 和 iPhone 共用：发请求的那一层、问决策 / 聊天 / 拿模型清单的客户端、钥匙串里放密钥。
// 拼请求和读回答在 Decisions.swift（OpenRouterWire）。

/// 发请求的那一层。测试用假的，不联网。
public protocol OpenRouterTransport: Sendable {
    /// 返回 (正文, 状态码)。连不上、超时抛 `OpenRouterWire.Failure`。
    func send(url: String, key: String?, body: Data?) async throws -> (Data, Int)
}

/// 真的联网：10 秒超时。密钥只放进这一次请求的头里。
public struct URLSessionOpenRouterTransport: OpenRouterTransport {
    public init() {}
    public func send(url: String, key: String?, body: Data?) async throws -> (Data, Int) {
        guard let u = URL(string: url) else { throw OpenRouterWire.Failure.unreadable }
        var req = URLRequest(url: u, timeoutInterval: OpenRouterWire.timeout)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let e as URLError {
            throw e.code == .timedOut ? OpenRouterWire.Failure.timeout : OpenRouterWire.Failure.noNetwork
        } catch { throw OpenRouterWire.Failure.noNetwork }
    }
}

/// 永远连不上的那一层：跑测试时的默认值，保证测试不会真的发请求。
public struct OfflineOpenRouterTransport: OpenRouterTransport {
    public init() {}
    public func send(url: String, key: String?, body: Data?) async throws -> (Data, Int) { throw OpenRouterWire.Failure.noNetwork }
}

/// 和 OpenRouter 说话的客户端：问一个决策、聊一句、拿模型清单。不存密钥，每次由外面递进来。
public struct OpenRouterClient: Sendable {
    public var transport: OpenRouterTransport
    public init(transport: OpenRouterTransport) { self.transport = transport }

    /// 问一次决策：先要「是 / 否」那个字的概率；模型给不出概率，就换成让它回一小段 JSON 再问一次。
    public func askDecision(_ d: Decision, card: String, model: String, key: String) async -> Result<Double, OpenRouterWire.Failure> {
        func once(_ mode: OpenRouterWire.Mode) async throws -> Double {
            let (data, status) = try await transport.send(url: OpenRouterWire.endpoint, key: key, body: OpenRouterWire.decisionBody(d, card: card, model: model, mode: mode))
            if let f = OpenRouterWire.failure(status: status, body: data) { throw f }
            return try OpenRouterWire.yesProbability(from: data, mode: mode)
        }
        do { return .success(try await once(.logprobs)) }
        catch OpenRouterWire.Failure.noLogprobs {
            do { return .success(try await once(.json)) }
            catch let f as OpenRouterWire.Failure { return .failure(f) } catch { return .failure(.unreadable) }
        }
        catch let f as OpenRouterWire.Failure { return .failure(f) } catch { return .failure(.unreadable) }
    }

    /// 聊一句：带上 app 算好的那几个数，账本原文不整份发。失败返回 nil。
    public func chat(_ question: String, numbers: String, model: String, key: String) async -> String? {
        let body = OpenRouterWire.chatBody(model: model, numbers: numbers, question: question)
        guard let (data, status) = try? await transport.send(url: OpenRouterWire.endpoint, key: key, body: body),
              OpenRouterWire.failure(status: status, body: data) == nil else { return nil }
        return try? OpenRouterWire.chatText(from: data)
    }

    /// 模型清单（公开的，不用密钥）。拿不到是空的。
    public func models() async -> [String] {
        guard let (data, status) = try? await transport.send(url: OpenRouterWire.modelsEndpoint, key: nil, body: nil), (200..<300).contains(status) else { return [] }
        return OpenRouterWire.modelIDs(from: data)
    }
}

#if canImport(Security)
/// 这台设备的钥匙串（一条通用密码）。Mac 和 iPhone 都能用。
public struct KeychainSecretStore: SecretStore {
    public let service: String
    /// 在「钥匙串访问」里看到的名字。
    public var label: String
    public init(service: String, label: String = "夏夏账本 · AI 密钥") { self.service = service; self.label = label }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func save(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        var status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base(account)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = label
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TrialError("没存进钥匙串（\(status)）。再试一次，或者先在「钥匙串访问」里看看") }
    }

    /// 只问有没有：不要求把密钥的内容还回来。
    public func has(_ account: String) -> Bool {
        var q = base(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    public func read(_ account: String) -> String? {
        var q = base(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TrialError("没从钥匙串里删掉（\(status)），再试一次") }
    }
}
#endif
