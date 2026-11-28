import Foundation

/// 家底页怎么摆账户：上面一排置顶的卡片（最多 4 张），下面其余的按小标题分组成列表。
/// 生活和店里各管各的，谁也看不到对方的账户。
public enum AccountCards {
    public static let maxPinned = 4
    /// 卡片底色有几种可挑。
    public static let styleCount = 6
}

extension TrialBook {
    /// 一组列表：小标题 + 这一组的账户。
    public struct AccountGroup: Equatable, Sendable, Identifiable {
        public var title: String
        public var accounts: [Account]
        public var id: String { title }
    }

    /// 能置顶的账户：这一边的都行，私房钱不行（它一直藏着）。
    public func pinnable(on side: Side) -> [Account] { accounts(on: side).filter { $0.kind != .secret } }

    /// 这一边置顶的卡片，按排好的先后。一张都没置顶时，默认置顶第一个日常能用的（店里是第一个放钱的账户）。
    public func pinned(on side: Side) -> [Account] {
        let pool = pinnable(on: side)
        let picked = (side == .biz ? shopPins : lifePins).compactMap { id in pool.first { $0.id == id } }
        if !picked.isEmpty { return Array(picked.prefix(AccountCards.maxPinned)) }
        let first = side == .biz ? pool.first { $0.kind == .shop } : pool.first { $0.kind == .own && $0.block == .daily }
        // 生活这边默认还置顶大目标的那个账户
        let goal = side == .life ? pool.first { $0.id == bigGoalAccount } : nil
        return [first, goal].compactMap { $0 }
    }

    public func isPinned(_ name: String) -> Bool {
        guard let a = account(name) else { return false }
        return pinned(on: a.side).contains { $0.id == a.id }
    }

    /// 没置顶的账户，分组成列表。生活：日常能用 / 存起来的 / 欠的和借出去的；店里：能用的 / 欠着的。空的组不出现。
    public func listed(on side: Side) -> [AccountGroup] {
        let top = Set(pinned(on: side).map(\.id))
        let rest = pinnable(on: side).filter { !top.contains($0.id) }
        let groups: [AccountGroup]
        if side == .biz {
            groups = [AccountGroup(title: "能用的", accounts: rest.filter { $0.kind == .shop }),
                      AccountGroup(title: "欠着的", accounts: rest.filter { $0.kind == .debt })]
        } else {
            groups = [AccountGroup(title: "日常能用", accounts: rest.filter { $0.kind == .own && $0.block == .daily }),
                      AccountGroup(title: "存起来的", accounts: rest.filter { $0.kind == .own && $0.block != .daily }),
                      AccountGroup(title: "欠的和借出去的", accounts: rest.filter { $0.kind == .debt || $0.kind == .lent })]
        }
        return groups.filter { !$0.accounts.isEmpty }
    }

    private mutating func setPins(_ ids: [UUID], on side: Side) {
        if side == .biz { shopPins = ids } else { lifePins = ids }
    }

    /// 置顶成卡片 / 取消置顶。最多 4 张。
    public mutating func setPinned(_ name: String, _ on: Bool) throws {
        guard let a = account(name) else { throw TrialError("没找到「\(name)」这个账户") }
        guard a.kind != .secret else { throw TrialError("私房钱一直藏着，不能置顶") }
        var ids = pinned(on: a.side).map(\.id)
        if on {
            guard !ids.contains(a.id) else { return }
            guard ids.count < AccountCards.maxPinned else { throw TrialError("最多置顶 \(AccountCards.maxPinned) 张，先取消一张") }
            ids.append(a.id)
        } else {
            guard ids.contains(a.id) else { return }
            ids.removeAll { $0 == a.id }
        }
        setPins(ids, on: a.side)
    }

    /// 在卡片排里拖动：把这张挪到第几个位置（从 0 数）。
    public mutating func movePin(_ name: String, to index: Int) throws {
        guard let a = account(name) else { throw TrialError("没找到「\(name)」这个账户") }
        var ids = pinned(on: a.side).map(\.id)
        guard let from = ids.firstIndex(of: a.id) else { throw TrialError("「\(name)」还没置顶") }
        ids.remove(at: from)
        ids.insert(a.id, at: min(max(index, 0), ids.count))
        setPins(ids, on: a.side)
    }

    /// 换卡片的底色。
    public mutating func setCardStyle(_ name: String, _ style: Int) throws {
        guard let i = accounts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这个账户") }
        guard (0..<AccountCards.styleCount).contains(style) else { throw TrialError("没有这种底色") }
        accounts[i].cardStyle = style
    }
}
