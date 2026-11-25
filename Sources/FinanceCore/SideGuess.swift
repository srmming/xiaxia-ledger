import Foundation

public enum SideGuess {
    public struct Suggestion: Codable, Sendable { public let to: Side; public let reason: String }
    public static let businessExpenses = ["进货", "耗材", "店租", "员工工资", "水电", "设备", "税费", "社保", "营销", "手续费", "利息", "本钱", "其他"]
    public static let businessIncome = ["营业收入", "退款", "其他"]
    public static func guess(_ tx: Transaction, current: Side, ledger: Ledger) -> Suggestion? {
        guard let result = suggestion(tx, ledger: ledger), result.to != current else { return nil }
        return result
    }
    static func suggestion(_ tx: Transaction, ledger: Ledger) -> Suggestion? {
        guard ledger.business?.enabled == true else { return nil }
        var signals: [Suggestion] = []
        let key = Dedup.normalize(tx.description)
        let loose = Suggester.looseKey(key)
        let life = Set(ledger.lifeBookIDs)
        let hidden = ledger.privateAccountIDs
        let history = ledger.transactions.filter { !key.isEmpty && $0.id != tx.id && !hidden.contains($0.accountID)
            && ($0.bookID == ledger.businessBook?.id || life.contains($0.bookID ?? "")) && (Dedup.normalize($0.description) == key || (!loose.isEmpty && Suggester.looseKey(Dedup.normalize($0.description)) == loose)) }
        if history.count >= 3 {
            for side in [Side.life, .business] where history.filter({ ledger.side(of: $0) == side }).count * 10 >= history.count * 9 {
                signals.append(.init(to: side, reason: "这个商户以往主要记在这边"))
            }
        }
        for (side, categories, words) in [(Side.business, ["进货","店租","员工工资","营业收入","耗材","营销"], ["进货","批发","货款"]),
                                          (.life, ["宝宝","学习","娱乐"], ["书包","奶粉","玩具","尿不湿"])] {
            if categories.contains(tx.category ?? "") { signals.append(.init(to: side, reason: "分类「\(tx.category!)」")) }
            if let word = words.first(where: tx.description.contains) { signals.append(.init(to: side, reason: "说明里有「\(word)」")) }
        }
        guard let first = signals.first, signals.allSatisfy({ $0.to == first.to }) else { return nil }
        return first
    }
}
extension Ledger {
    public func routeEntry(_ tx: inout Transaction, side requested: String?) throws -> String {
        if let requested {
            guard let side = Side(rawValue: requested), let id = bookID(for: side), tx.bookID == nil || tx.bookID == id else { throw BusinessError(message: "请确认生活或生意和账本选择一致") }
            tx.bookID = id
            return "归到\(id)（指定了\(requested)）"
        }
        if let id = tx.bookID { return "归到\(id)（指定账本）" }
        guard business?.enabled == true else { throw BusinessError(message: "请指定账本") }
        if let guess = SideGuess.suggestion(tx, ledger: self), let id = bookID(for: guess.to) {
            tx.bookID = id; return "归到\(id)（\(guess.reason)）"
        }
        throw BusinessError(message: "请确认记在生活还是生意，指定 side 或 book")
    }
}

extension Ledger {
    public mutating func describeRoute(_ change: ChangeRecord, reason: String) -> ChangeRecord {
        var result = change
        result.summary += " · " + reason
        if let index = changes.lastIndex(where: { $0.id == change.id }) { changes[index] = result }
        return result
    }
}
