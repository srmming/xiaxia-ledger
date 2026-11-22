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
    public init(name: String, income: Bool) { self.name = name; self.income = income }
}

/// 跟着账本走（经 iCloud 同步）的个人设置：夏夏的性格、你想让夏夏帮你做到什么、自己加的分类。
public struct Profile: Codable, Hashable, Sendable {
    public var persona: Persona
    /// 「你想让夏夏帮你做到什么？」，比如「每个月存下 500 €」。
    public var aim: String?
    public var categories: [CustomCategory]

    public init(persona: Persona = .gentle, aim: String? = nil, categories: [CustomCategory] = []) {
        self.persona = persona; self.aim = aim; self.categories = categories
    }

    enum CodingKeys: String, CodingKey { case persona, aim, categories }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        persona = try c.decodeIfPresent(Persona.self, forKey: .persona) ?? .gentle
        aim = try c.decodeIfPresent(String.self, forKey: .aim)
        categories = try c.decodeIfPresent([CustomCategory].self, forKey: .categories) ?? []
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

    /// 加一个新分类（还没有流水用它）。重名会提示。
    @discardableResult
    public mutating func addCategory(_ name: String, income: Bool, author: String) throws -> ChangeRecord {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw ManageError.emptyName }
        guard !allCategoryNames(income: income).contains(n) else { throw ManageError.duplicateName(n) }
        let old = profile
        profile.categories.append(CustomCategory(name: n, income: income))
        return appendProfileChange("加分类「\(n)」（\(income ? "收入" : "支出")）", before: old, author: author)
    }

    mutating func appendProfileChange(_ summary: String, before: Profile, author: String) -> ChangeRecord {
        var snapshot = PlanSnapshot()
        snapshot.profile = before
        let change = snapshotChange(.account, summary, before: snapshot, author: author)
        changes.append(change)
        return change
    }
}
