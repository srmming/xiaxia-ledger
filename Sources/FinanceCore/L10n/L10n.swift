import Foundation

/// 多语言（ming 2026-11-23：中文、英文、西班牙语）。
///
/// 做法：代码里照旧写中文，外面包一层 `tr("…")`；英文、西班牙语在 `L10n+en.swift`、`L10n+es.swift` 两张表里，按中文原文查。
/// 表里没有的就显示中文原文，所以可以一页一页地翻，没翻完也不会坏。
/// 带数字、名字的句子直接写 `tr("够花 \(n) 个月")`，表里的键是「够花 %@ 个月」；译文里要换顺序就写 `%1$@`、`%2$@`。
/// 译文里 `%1$M` 把第 1 个值（月份数字）换成月份名，`%1$N` 是首字母大写的月份名。用了带编号的，这一句就全用带编号的。
///
/// 为什么不用苹果的 String Catalog：界面在 Swift 包里，`swift build` 不会编译 .xcstrings，测试和 fin 也读不到；
/// 自己的表在 app、fin、测试里是同一份，还能在设置里立刻切换，不用重开 app。
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    /// 跟着系统语言走。
    case system
    case zhHans = "zh-Hans"
    case en
    case es

    public var id: String { rawValue }

    /// 语言自己的名字（不翻译：不管现在是什么语言，都认得出自己的那一个）。
    public var nativeName: String {
        switch self {
        case .system: tr("跟随系统")
        case .zhHans: "简体中文"
        case .en: "English"
        case .es: "Español"
        }
    }

    /// 系统语言列表里第一个我们有的；都没有就用英文。
    public static func fromSystem(_ preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        for code in preferred {
            let c = code.lowercased()
            if c.hasPrefix("zh") { return .zhHans }
            if c.hasPrefix("en") { return .en }
            if c.hasPrefix("es") { return .es }
        }
        return .en
    }

    /// 日期、数字格式用的地区。
    public var locale: Locale {
        switch self {
        case .system: AppLanguage.fromSystem().locale
        case .zhHans: Locale(identifier: "zh_CN")
        case .en: Locale(identifier: "en_GB")
        case .es: Locale(identifier: "es_ES")
        }
    }
}

/// 一句要翻译的话：中文原文当键，`\(…)` 插进去的值单独存着。
public struct L10nText: ExpressibleByStringInterpolation, Sendable, Equatable {
    public var key: String
    public var args: [String]

    public init(key: String, args: [String] = []) { self.key = key; self.args = args }
    public init(stringLiteral value: String) { key = value; args = [] }
    public init(stringInterpolation i: StringInterpolation) { key = i.key; args = i.args }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var args: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) { key += "%@"; args.append("\(value)") }
    }
}

public enum L10n {
    /// 存在 UserDefaults 里的键（app 的设置页写，启动时读）。
    public static let defaultsKey = "xiaxia.language"
    /// 还没翻完之前，没选过语言的人先看中文；全部翻完后改成 .system（见 docs/L10N.md）。
    public static let fallbackChoice = AppLanguage.zhHans

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _choice: AppLanguage = fallbackChoice

    /// 用户选的（可能是「跟随系统」）。
    public static var choice: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return _choice }
        set { lock.lock(); _choice = newValue; lock.unlock() }
    }

    /// 现在真正用的语言（不会是 .system）。
    public static var language: AppLanguage {
        let c = choice
        return c == .system ? AppLanguage.fromSystem() : c
    }

    /// 从 UserDefaults 读出选的语言并用上；没选过就是 fallbackChoice。
    @discardableResult
    public static func load(from defaults: UserDefaults = .standard) -> AppLanguage {
        let c = defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? fallbackChoice
        choice = c
        return c
    }

    /// 一张语言的表：中文原文 → 译文。中文自己没有表。
    public static func table(_ language: AppLanguage) -> [String: String] {
        switch language {
        case .en: en
        case .es: es
        case .zhHans, .system: [:]
        }
    }

    /// 翻一句。表里没有就用中文原文。
    public static func string(_ text: L10nText, in language: AppLanguage? = nil) -> String {
        let lang = language ?? self.language
        let template = lang == .zhHans ? text.key : (table(lang)[text.key] ?? text.key)
        let out = fill(template, text.args)
        // 中文两句直接接上就行，英文、西语的句号后面要有空格，不然拼出来是「…€.Spending…」。
        if lang != .zhHans, let last = text.key.last, "。！？".contains(last), let end = out.last, ".!?".contains(end) { return out + " " }
        return out
    }

    /// 把 `%@`（按顺序）和 `%1$@`（指定第几个）换成值。
    static func fill(_ template: String, _ args: [String]) -> String {
        guard !args.isEmpty else { return template }
        var out = template
        for (i, a) in args.enumerated() {
            // %1$M：第 1 个值是月份数字，换成月份名（句子中间用，西语小写）；%1$N：单独显示用，首字母大写。
            if out.contains("%\(i + 1)$M") || out.contains("%\(i + 1)$N") {
                let name = monthName(a)
                out = out.replacingOccurrences(of: "%\(i + 1)$M", with: name)
                    .replacingOccurrences(of: "%\(i + 1)$N", with: name.prefix(1).uppercased() + name.dropFirst())
            }
            out = out.replacingOccurrences(of: "%\(i + 1)$@", with: a)
        }
        var next = 0
        var result = ""
        var rest = Substring(out)
        while let r = rest.range(of: "%@") {
            result += rest[..<r.lowerBound]
            result += next < args.count ? args[next] : ""
            next += 1
            rest = rest[r.upperBound...]
        }
        return result + rest
    }

    /// 键里有几个要填的位置（检查译文和原文对不对得上用）：`%@`，加上用到的 `%1$@`、`%1$M`、`%1$N`（同一个编号只算一次）。
    static func placeholders(_ s: String) -> Int {
        s.components(separatedBy: "%@").count - 1
            + (1...9).filter { n in ["@", "M", "N"].contains { s.contains("%\(n)$\($0)") } }.count
    }

    static let monthNames: [AppLanguage: [String]] = [
        .en: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
        .es: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
    ]

    /// 月份数字（「11」）在现在这种语言里的名字；不是 1–12 的数字就原样返回。
    static func monthName(_ number: String, in language: AppLanguage? = nil) -> String {
        guard let n = Int(number), (1...12).contains(n), let names = monthNames[language ?? self.language] else { return number }
        return names[n - 1]
    }
}

/// 界面文字都过这一下：`Text(tr("家底"))`、`tr("够花 \(n) 个月")`。
public func tr(_ text: L10nText) -> String { L10n.string(text) }

/// 运行时才知道的中文（枚举的原始值之类）：`trKey(section.rawValue)`。
public func trKey(_ key: String) -> String { L10n.string(L10nText(key: key)) }
