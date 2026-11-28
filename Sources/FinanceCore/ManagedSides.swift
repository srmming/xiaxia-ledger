import Foundation

/// 「管哪边」：只管生活、只管生意，还是两边都管。
/// 存在账本本身（生意设置里的 `manages`），跟着账本一起同步，Mac 和手机读的是同一个。
public enum ManagedSides: String, Codable, Hashable, Sendable, CaseIterable {
    case life, biz, both
    public var showsLife: Bool { self != .biz }
    public var showsBiz: Bool { self != .life }
    public init(life: Bool, biz: Bool) { self = life && biz ? .both : biz ? .biz : .life }
    public var title: String { switch self { case .life: "只管生活"; case .biz: "只管生意"; case .both: "两边都管" } }
}

extension Ledger {
    /// 现在管哪边。生意模式没开（或者没有生意账本）就只有生活；开着但没选过，就是两边都管。
    public var managedSides: ManagedSides {
        guard business?.enabled == true, businessBook != nil else { return .life }
        return business?.manages ?? .both
    }

    /// 改「管哪边」：记一条能撤销的改动，带作者。
    /// 选「只管生活」不关生意模式，生意的账和设置都还在，只是先不显示。
    /// 选「只管生意」「两边都管」而生意模式还没开：顺手打开（账本里有好几个生意账本时先让用户选，这里不替他选）。
    @discardableResult
    public mutating func setManagedSides(_ sides: ManagedSides, author: String) throws -> ChangeRecord {
        // 已经是这样了（选过同一个，或者从没开过生意又选只管生活）：不记改动
        guard !(sides == managedSides && (business?.manages == sides || business == nil || (sides == .both && business?.manages == nil))) else { throw ManageError.nothingToChange }
        var record: ChangeRecord?
        if sides.showsBiz, !(business?.enabled == true && businessBook != nil) {
            var work = self
            switch try work.enableBusinessMode(author: author) {
            case .enabled(let change): record = change
            case .needsChoice: throw BusinessError(message: "账本里有好几个生意账本，先选一个")
            }
            self = work
            if sides == .both, business?.manages == nil || business?.manages == .both { return record! }
        }
        var settings = business ?? BusinessSettings()
        settings.manages = sides
        return changeBusinessSettings(settings, summary: "管哪边改成「\(sides.title)」", author: author)
    }
}

extension TrialBook {
    /// 管哪边（和正式账本同一种说法）。
    public var managedSides: ManagedSides { ManagedSides(life: showLife, biz: showBiz) }
    public mutating func setManagedSides(_ sides: ManagedSides) { showLife = sides.showsLife; showBiz = sides.showsBiz }
}

extension LedgerBridge {
    /// 界面上改了「管哪边」：照样写进正式账本。没改就返回 nil。
    static func applySides(before: TrialBook, after: TrialBook, to ledger: inout Ledger, author: String) throws -> [ChangeRecord]? {
        guard before.managedSides != after.managedSides else { return nil }
        var a = after; a.showLife = before.showLife; a.showBiz = before.showBiz
        guard a == before else { throw TrialError("改管哪边的时候别的也动了，这一步还没接上，账本没动") }
        do { return [try ledger.setManagedSides(after.managedSides, author: author)] }
        catch let e as BusinessError { throw TrialError(e.message) }
    }
}
