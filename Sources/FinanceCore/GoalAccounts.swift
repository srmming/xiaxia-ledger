import Foundation

/// 一个目标对一个账户：目标的钱一定单独放起来，不和日常的钱混，也不和别的目标共用。目标已存 = 这个账户的余额。
extension TrialBook {
    /// 新目标的钱放哪。
    public enum GoalPlace: Equatable, Sendable {
        /// 新开一个存钱罐（名字跟目标走，比如「换新电脑 存钱罐」）。
        case newJar
        /// 放进一个已有的账户（只能是「存起来的」那类、还没给别的目标用的）。里面原有的钱算这个目标已经存的。
        case existing(String)
    }

    /// 新目标能用的已有账户：生活这边「存起来的」、还没给哪个目标用的。日常卡、现金、信用卡都不在里面。
    public var goalPlaceCandidates: [Account] { owned.filter { $0.block == .emergency } }

    public static func jarName(_ goal: String) -> String { "\(goal) 存钱罐" }

    /// 给一个新目标安排账户。返回账户、里面已经有多少、是不是新开的。
    mutating func placeGoal(_ goal: String, _ place: GoalPlace) throws -> (id: UUID, saved: Money, owned: Bool) {
        switch place {
        case .newJar:
            var name = Self.jarName(goal), n = 2
            while accounts.contains(where: { $0.name == name }) { name = "\(Self.jarName(goal)) \(n)"; n += 1 }
            let a = Account(emoji: "⭐", name: name, note: "存给「\(goal)」", balance: .zero, kind: .own, block: .goal)
            accounts.append(a)
            return (a.id, .zero, true)
        case .existing(let name):
            guard let i = accounts.firstIndex(where: { $0.name == name }), goalPlaceCandidates.contains(where: { $0.name == name }) else {
                throw TrialError("「\(name)」不能拿来放目标的钱：要选一个存起来的、还没给别的目标用的账户")
            }
            accounts[i].block = .goal
            accounts[i].note = "存给「\(goal)」"
            return (accounts[i].id, accounts[i].balance, false)
        }
    }

    /// 目标改名：为它新开的存钱罐跟着改名；用的已有账户不改名，只改那行小字。
    mutating func renameJar(_ id: UUID?, owned: Bool, to goal: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].note = "存给「\(goal)」"
        guard owned else { return }
        let old = accounts[i].name
        var name = Self.jarName(goal), n = 2
        while accounts.contains(where: { $0.name == name && $0.id != id }) { name = "\(Self.jarName(goal)) \(n)"; n += 1 }
        accounts[i].name = name
        for k in entries.indices where entries[k].account == old { entries[k].account = name }
    }

    /// 一个账户是哪个目标的（不是目标的账户返回 nil）：目标名、存了多少、一共要多少。
    public func goal(of accountID: UUID) -> (name: String, saved: Money, target: Money, big: Bool)? {
        if accountID == bigGoalAccount, journey.total > .zero { return (journey.name, journey.saved, journey.total, true) }
        if let g = smallGoals.first(where: { $0.account == accountID }) { return (g.name, g.saved, g.target, false) }
        return nil
    }

    /// 大目标的账户。
    public var bigGoalHome: Account? { accounts.first { $0.id == bigGoalAccount } }

    /// 每个目标的已存都等于它那个账户的余额，而且没有两个目标共用一个账户。测试和自查用。
    public var goalAccountsAreConsistent: Bool {
        var ids: [UUID] = []
        if journey.total > .zero {
            guard let a = bigGoalHome, a.balance == journey.saved, a.block == .goal else { return false }
            ids.append(a.id)
        }
        for g in smallGoals {
            guard let a = accounts.first(where: { $0.id == g.account }), a.balance == g.saved, a.block == .goal else { return false }
            ids.append(a.id)
        }
        return Set(ids).count == ids.count && accounts.filter { $0.block == .goal }.count == ids.count
    }
}
