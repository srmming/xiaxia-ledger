import Foundation

/// 去重：同一账户、同一天、同一金额、描述归一化后相同，就当同一笔。
/// 同一天确实有两笔一模一样的（比如两杯咖啡），用 occurrence 区分第几次出现。
public enum Dedup {
    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func baseKey(_ tx: Transaction) -> String {
        "\(tx.accountID)|\(tx.date)|\(tx.amount.cents)|\(normalize(tx.description))"
    }

    /// 返回 incoming 里账本中还没有的流水。
    public static func newTransactions(_ incoming: [Transaction], existing: [Transaction]) -> [Transaction] {
        var existingCounts: [String: Int] = [:]
        for tx in existing { existingCounts[baseKey(tx), default: 0] += 1 }
        var seen: [String: Int] = [:]
        return incoming.filter { tx in
            let key = baseKey(tx)
            seen[key, default: 0] += 1
            return seen[key]! > existingCounts[key, default: 0]
        }
    }
}
