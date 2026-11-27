import Foundation

/// 用自己的 API 密钥连 AI：哪几家、填的东西对不对。密钥本身不在这里存，交给 `SecretStore`（app 里是这台 Mac 的钥匙串）。
public enum AIKeyProvider: String, CaseIterable, Sendable {
    case anthropic, openai, google, custom

    public var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .google: "Google"
        case .custom: "兼容 OpenAI 的自定义地址"
        }
    }

    public var shortTitle: String { self == .custom ? "自定义地址" : title }
    /// 这一家要不要另外填地址。
    public var needsAddress: Bool { self == .custom }
}

public enum AIKeyRules {
    /// 整理并检查要存的密钥：去掉头尾空白；不能空、不能有空白、不能太短。
    public static func cleanKey(_ raw: String) throws -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TrialError("先把密钥粘进来") }
        guard !key.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw TrialError("密钥中间不该有空格或换行，再粘一次") }
        guard key.count >= 8 else { throw TrialError("这个密钥太短了，像是没粘全") }
        guard key.count <= 512 else { throw TrialError("这个密钥太长了，像是粘错了东西") }
        return key
    }

    /// 自定义地址：要是 https 的网址（本机的 http 也行）。
    public static func cleanAddress(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TrialError("自定义地址还没填") }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            throw TrialError("地址写成 https://… 这样")
        }
        let local = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && local) else { throw TrialError("地址要用 https 开头") }
        return text
    }

    /// 给人看的样子：只露最后 4 位，前面全是点。绝不把整串还回去。
    public static func masked(_ key: String) -> String {
        "••••••••" + String(key.suffix(min(4, max(0, key.count - 8))))
    }
}

/// 放密钥的地方。app 里是钥匙串；测试里用内存里的假货，不碰真的钥匙串。
public protocol SecretStore: Sendable {
    func save(_ secret: String, for account: String) throws
    /// 只问有没有，不把密钥读出来。
    func has(_ account: String) -> Bool
    func delete(_ account: String) throws
}

/// 只活在内存里的假钥匙串（测试、离屏出图用）。
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var items: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func save(_ secret: String, for account: String) throws { lock.lock(); items[account] = secret; lock.unlock() }
    public func has(_ account: String) -> Bool { lock.lock(); defer { lock.unlock() }; return items[account] != nil }
    public func delete(_ account: String) throws { lock.lock(); items[account] = nil; lock.unlock() }
    /// 只给测试核对用。
    public func peek(_ account: String) -> String? { lock.lock(); defer { lock.unlock() }; return items[account] }
}
