import Foundation

/// 夏夏怎么跟你说话。app 自己说的话、复制给 AI 的话、AI 经 MCP 读到的说明书都带上它。
public enum Persona: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 温和直说（默认）：说清楚数字和该留意的事，不绕弯，也不凶。
    case gentle
    /// 毒舌：一针见血，带点损，但不人身攻击。
    case sharp
    /// 文静：克制、书面、只讲事实。
    case calm
    /// 打气：先夸做得好的，再温柔提醒。
    case cheer

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .gentle: "温和直说"
        case .sharp: "毒舌"
        case .calm: "文静"
        case .cheer: "打气"
        }
    }

    /// 设置页里给人看的例句。
    public var sample: String {
        switch self {
        case .gentle: "这个月外卖 210 €，比上个月多一半，可以留意一下。"
        case .sharp: "外卖 210 €？厨房是摆设吗。"
        case .calm: "本月外卖支出 210 €，较上月增加 52%。"
        case .cheer: "这个月已经存下 300 € 啦！外卖再少点就更棒了。"
        }
    }

    /// 给 AI 的口吻说明。
    public var instruction: String {
        switch self {
        case .gentle: "用温和、直接的口吻：先说结论和数字，再说一句该留意什么，不说教。"
        case .sharp: "用毒舌的口吻：一针见血、带点幽默的损，但不人身攻击，结论和数字要准。"
        case .calm: "用文静、克制的口吻：书面、简短，只讲事实和数字，不用感叹号。"
        case .cheer: "用打气的口吻：先肯定做得好的地方，再温柔地提一个可以改进的点。"
        }
    }

    /// 读到不认识的（更新版本加的）当成默认，不让账本打不开。
    public init(from decoder: Decoder) throws {
        self = Persona(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .gentle
    }
}

/// 用户自己加的分类（还没有流水用过它时，也要出现在记一笔和管理分类里）。
public struct CustomCategory: Codable, Hashable, Sendable {
    public var name: String
    public var income: Bool
    /// 用户挑的图标（CategoryIcons 里的名字，如 "coffee"）；nil = 按名字自动配。
    public var icon: String?
    /// 新界面里用户挑的图标（一个 emoji）；nil = 按名字自动配。老账本没有这个字段。
    public var emoji: String?
    public init(name: String, income: Bool, icon: String? = nil) { self.name = name; self.income = income; self.icon = icon }
}

/// 跟着账本走（经 iCloud 同步）的个人设置：夏夏的性格、你想让夏夏帮你做到什么、自己加的分类。
public struct Profile: Codable, Hashable, Sendable {
    public var persona: Persona
    /// 「你想让夏夏帮你做到什么？」，比如「每个月存下 500 €」。
    public var aim: String?
    public var categories: [CustomCategory]
    /// 用户给助手起的名字；nil = 默认「夏夏」（ming 2026-11-23：「引导的时候可以改夏夏称呼」）。
    public var assistantName: String?
    /// 助手怎么称呼用户，比如「小明」「老板」；nil = 就叫「你」。
    public var userCallName: String?
    /// 上次整理夏夏的记忆是什么时候（一个月提醒一次）。
    public var memoryTidiedAt: Date?
    /// 一次性开销的标记（流水 id → 是不是一次性）：AI 记账、导入、悄悄复核时标的。没标的按规则猜。见 Outlook.swift。
    public var oneOff: [String: Bool]?
    /// 认出来、用户说「不算固定开销」的「账户|分类」，以后不再问。
    public var notFixed: [String]?
    /// 「这家店以后都算这一类」：店名的钥匙（见 Ledger.placeKey）→ 分类名。老账本没有这个字段。
    public var placeCategories: [String: String]?
    /// 问过「这家店算不算某一类」、用户说不是的店，以后不再问。
    public var placeSkipped: [String]?

    public init(persona: Persona = .gentle, aim: String? = nil, categories: [CustomCategory] = [],
                assistantName: String? = nil, userCallName: String? = nil) {
        self.persona = persona; self.aim = aim; self.categories = categories
        self.assistantName = assistantName; self.userCallName = userCallName
    }

    /// 助手现在叫什么（没改过就是「夏夏」）。
    public var xiaName: String { assistantName ?? Self.defaultAssistantName }
    public static let defaultAssistantName = "夏夏"

    /// 把一句界面文字里的「夏夏」换成用户起的名字；「夏夏账本」是 app 名，不换。
    public func renamed(_ text: String) -> String {
        guard let name = assistantName, name != Self.defaultAssistantName else { return text }
        let app = "\u{1}"
        return text.replacingOccurrences(of: "夏夏账本", with: app)
            .replacingOccurrences(of: Self.defaultAssistantName, with: name)
            .replacingOccurrences(of: app, with: "夏夏账本")
    }

    enum CodingKeys: String, CodingKey { case persona, aim, categories, assistantName, userCallName, memoryTidiedAt, oneOff, notFixed, placeCategories, placeSkipped }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        persona = try c.decodeIfPresent(Persona.self, forKey: .persona) ?? .gentle
        aim = try c.decodeIfPresent(String.self, forKey: .aim)
        categories = try c.decodeIfPresent([CustomCategory].self, forKey: .categories) ?? []
        assistantName = try c.decodeIfPresent(String.self, forKey: .assistantName)
        userCallName = try c.decodeIfPresent(String.self, forKey: .userCallName)
        memoryTidiedAt = try c.decodeIfPresent(Date.self, forKey: .memoryTidiedAt)
        oneOff = try c.decodeIfPresent([String: Bool].self, forKey: .oneOff)
        notFixed = try c.decodeIfPresent([String].self, forKey: .notFixed)
        placeCategories = try c.decodeIfPresent([String: String].self, forKey: .placeCategories)
        placeSkipped = try c.decodeIfPresent([String].self, forKey: .placeSkipped)
    }

    /// 「你的目标」示例，点一下就填。说法通用。
    public static let aimExamples = ["每个月存下 500 €", "搞清楚钱都花哪了", "少点外卖和网购", "先把信用卡还清", "年底前存够旅行的钱"]
}

extension Ledger {
    /// 换夏夏的说话方式。记进改动记录，能撤销。
    @discardableResult
    public mutating func setPersona(_ persona: Persona, author: String) throws -> ChangeRecord {
        guard profile.persona != persona else { throw ManageError.nothingToChange }
        let old = profile
        profile.persona = persona
        return appendProfileChange("夏夏的说话方式改成「\(persona.label)」", before: old, author: author)
    }

    /// 给助手改名字、设它怎么称呼你。传空 = 改回默认（「夏夏」/「你」）。名字最多 12 个字。
    @discardableResult
    public mutating func setNames(assistant: String?, callUser: String?, author: String) throws -> ChangeRecord {
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : String(t.prefix(12))
        }
        var a = clean(assistant)
        if a == Profile.defaultAssistantName { a = nil }
        let u = clean(callUser)
        guard profile.assistantName != a || profile.userCallName != u else { throw ManageError.nothingToChange }
        let old = profile
        profile.assistantName = a
        profile.userCallName = u
        var parts: [String] = []
        if old.assistantName != a { parts.append("助手改叫「\(a ?? Profile.defaultAssistantName)」") }
        if old.userCallName != u { parts.append(u.map { "称呼你「\($0)」" } ?? "称呼改回「你」") }
        return appendProfileChange(parts.joined(separator: "，"), before: old, author: author)
    }

    /// 写下（或清掉）你想让夏夏帮你做到什么。
    @discardableResult
    public mutating func setAim(_ aim: String?, author: String) throws -> ChangeRecord {
        let text = aim?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (text?.isEmpty ?? true) ? nil : text
        guard profile.aim != value else { throw ManageError.nothingToChange }
        let old = profile
        profile.aim = value
        return appendProfileChange(value.map { "目标写成「\($0)」" } ?? "清掉了目标", before: old, author: author)
    }

    /// 现在有的所有分类名（流水里用过的 + 自己加的），给查重用。
    public func allCategoryNames(income: Bool? = nil) -> Set<String> {
        var names = Set(transactions.filter { t in income.map { t.amount.isIncome == $0 } ?? true }.compactMap(\.category))
        for c in profile.categories where income == nil || c.income == income { names.insert(c.name) }
        return names
    }

    /// 加一个新分类（还没有流水用它）。重名会提示。icon 是 CategoryIcons 里的图标名，不填就按名字自动配。
    @discardableResult
    public mutating func addCategory(_ name: String, income: Bool, icon: String? = nil, author: String) throws -> ChangeRecord {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw ManageError.emptyName }
        guard !allCategoryNames(income: income).contains(n) else { throw ManageError.duplicateName(n) }
        if let icon { guard CategoryIcons.isValid(icon) else { throw ManageError.unknownIcon(icon) } }
        let old = profile
        profile.categories.append(CustomCategory(name: n, income: income, icon: icon))
        let iconNote = icon.flatMap(CategoryIcons.label).map { "，图标「\($0)」" } ?? ""
        return appendProfileChange("加分类「\(n)」（\(income ? "收入" : "支出")\(iconNote)）", before: old, author: author)
    }

    /// 给一个分类换图标（已有流水的分类也行）。icon 传 nil = 改回按名字自动配。
    @discardableResult
    public mutating func setCategoryIcon(_ name: String, icon: String?, author: String) throws -> ChangeRecord {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw ManageError.emptyName }
        if let icon { guard CategoryIcons.isValid(icon) else { throw ManageError.unknownIcon(icon) } }
        let old = profile
        if let i = profile.categories.firstIndex(where: { $0.name == n }) {
            profile.categories[i].icon = icon
        } else {
            let income = transactions.first { $0.category == n }.map { $0.amount.isIncome } ?? false
            profile.categories.append(CustomCategory(name: n, income: income, icon: icon))
        }
        let what = icon.flatMap(CategoryIcons.label).map { "换成「\($0)」" } ?? "改回自动配"
        return appendProfileChange("分类「\(n)」的图标\(what)", before: old, author: author)
    }

    /// 用户给分类挑过的图标：分类名 → 图标名。
    public var categoryIcons: [String: String] {
        var m: [String: String] = [:]
        for c in profile.categories { if let i = c.icon { m[c.name] = i } }
        return m
    }

    mutating func appendProfileChange(_ summary: String, before: Profile, author: String) -> ChangeRecord {
        var snapshot = PlanSnapshot()
        snapshot.profile = before
        let change = snapshotChange(.account, summary, before: snapshot, author: author)
        changes.append(change)
        return change
    }
}
