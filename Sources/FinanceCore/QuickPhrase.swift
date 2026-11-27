import Foundation

/// 「说一句」记账：从一句大白话里认出是什么、多少钱。不用 AI，没网也行。
/// 「刚才咖啡 3 块 2」→ 咖啡，3,20。认不出金额就返回 nil，让界面说人话问一句。
public struct QuickPhrase: Equatable, Sendable {
    public var name: String
    public var emoji: String
    public var amount: Money

    public init(name: String, emoji: String, amount: Money) {
        self.name = name; self.emoji = emoji; self.amount = amount
    }

    private static let known: [(String, String)] = [
        ("咖啡", "☕"), ("奶茶", "🧋"), ("午饭", "🥗"), ("晚饭", "🍜"), ("早饭", "🥐"), ("早餐", "🥐"), ("外卖", "🥡"),
        ("超市", "🛒"), ("买菜", "🥬"), ("打车", "🚕"), ("地铁", "🚇"), ("公交", "🚌"), ("加油", "⛽"),
        ("电影", "🎬"), ("房租", "🏠"), ("话费", "📱"), ("水电", "💡"), ("药", "💊"),
    ]
    private static let filler = ["刚才", "刚刚", "今天", "昨天", "早上", "中午", "晚上", "花了", "买了", "付了", "用了", "一共", "了", "的", "，", ",", "。", "欧元"]

    public static func parse(_ text: String) -> QuickPhrase? {
        let pattern = #"(\d+(?:[.,]\d{1,2})?)\s*(块|元|欧|€)?\s*(?:(\d)\s*(?:毛|角)?)?"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(m.range(at: 1), in: text)
        else { return nil }
        var number = String(text[whole])
        let hasUnit = m.range(at: 2).location != NSNotFound
        if hasUnit, !number.contains(","), !number.contains("."), let tail = Range(m.range(at: 3), in: text) {
            number += "," + text[tail] + "0"
        }
        guard let amount = Money(parsing: number), amount > .zero else { return nil }

        if let hit = known.first(where: { text.contains($0.0) }) {
            return QuickPhrase(name: hit.0, emoji: hit.1, amount: amount)
        }
        var rest = text
        if let all = Range(m.range, in: text) { rest.removeSubrange(all) }
        for f in filler { rest = rest.replacingOccurrences(of: f, with: "") }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuickPhrase(name: rest.isEmpty ? "一笔开销" : rest, emoji: "🧾", amount: amount)
    }
}
