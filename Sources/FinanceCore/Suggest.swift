import Foundation

/// 按以前的习惯猜分类和账本：同一个商户上次分到哪，这次就先猜哪。
/// 只是建议。app 里记一笔、整理、导入时用它预填，ming 看一眼就能改。
public struct Suggester: Sendable {
    public struct Guess: Equatable, Sendable {
        public var category: String?
        public var bookID: String?
        public var isEmpty: Bool { category == nil && bookID == nil }
    }

    private var exact: [String: [String: Int]] = [:]
    private var loose: [String: [String: Int]] = [:]
    private var exactBook: [String: [String: Int]] = [:]
    private var looseBook: [String: [String: Int]] = [:]

    public init(_ transactions: [Transaction]) {
        for t in transactions where t.flow == nil && !t.isTransfer {
            let k = Dedup.normalize(t.description)
            guard !k.isEmpty else { continue }
            let l = Self.looseKey(k)
            if let c = t.category {
                exact[k, default: [:]][c, default: 0] += 1
                if !l.isEmpty { loose[l, default: [:]][c, default: 0] += 1 }
            }
            if let b = t.bookID {
                exactBook[k, default: [:]][b, default: 0] += 1
                if !l.isEmpty { looseBook[l, default: [:]][b, default: 0] += 1 }
            }
        }
    }

    /// 宽松的商户名：去掉带数字的词（门店号、卡号、日期），只留前两个词。
    /// 「MERCADONA 1234 VALENCIA」和「MERCADONA 0098 VALENCIA」算同一家。
    public static func looseKey(_ normalized: String) -> String {
        normalized.split(separator: " ").filter { w in !w.contains(where: \.isNumber) && w.count > 1 }
            .prefix(2).joined(separator: " ")
    }

    private func best(_ counts: [String: Int]?) -> String? {
        counts?.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }

    public func guess(_ description: String) -> Guess {
        let k = Dedup.normalize(description)
        guard !k.isEmpty else { return Guess() }
        let l = Self.looseKey(k)
        return Guess(category: best(exact[k]) ?? best(loose[l]), bookID: best(exactBook[k]) ?? best(looseBook[l]))
    }
}

extension Ledger {
    /// 给一批还没分类 / 没分账本的流水按以前的习惯填上。返回填了几笔。
    public func applyingGuesses(to incoming: [Transaction]) -> (transactions: [Transaction], guessed: Int) {
        let s = Suggester(transactions)
        var n = 0
        let out = incoming.map { t -> Transaction in
            guard t.flow == nil, t.category == nil || t.bookID == nil else { return t }
            let g = s.guess(t.description)
            guard !g.isEmpty else { return t }
            var c = t
            if c.category == nil { c.category = g.category }
            if c.bookID == nil { c.bookID = g.bookID }
            if c != t { n += 1 }
            return c
        }
        return (out, n)
    }
}
