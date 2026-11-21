import Foundation

/// 金额，用「分」存整数，避免浮点误差。正数是收入，负数是支出。
public struct Money: Hashable, Comparable, Codable, Sendable {
    public var cents: Int64

    public init(cents: Int64) { self.cents = cents }

    /// 从字符串解析，接受 "1.234,56"、"-12,30"、"1234.56"、"12" 等写法。
    public init?(parsing text: String) {
        var s = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("-") || s.hasPrefix("−") { negative = true; s.removeFirst() }
        else if s.hasPrefix("+") { s.removeFirst() }

        // 最后出现的 , 或 . 如果后面正好 1–2 位数字，就当小数点；其余当千分位。
        let lastSep = s.lastIndex(where: { $0 == "," || $0 == "." })
        var intPart = s
        var fracPart = ""
        if let i = lastSep {
            let after = s[s.index(after: i)...]
            if (1...2).contains(after.count) {
                intPart = String(s[..<i])
                fracPart = String(after)
            }
        }
        intPart = intPart.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        guard !intPart.isEmpty || !fracPart.isEmpty,
              intPart.allSatisfy(\.isNumber), fracPart.allSatisfy(\.isNumber),
              let units = Int64(intPart.isEmpty ? "0" : intPart)
        else { return nil }
        let frac = Int64(fracPart.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        let value = units * 100 + frac
        self.cents = negative ? -value : value
    }

    public static let zero = Money(cents: 0)
    public static func + (a: Money, b: Money) -> Money { Money(cents: a.cents + b.cents) }
    public static func - (a: Money, b: Money) -> Money { Money(cents: a.cents - b.cents) }
    public static prefix func - (a: Money) -> Money { Money(cents: -a.cents) }
    public static func < (a: Money, b: Money) -> Bool { a.cents < b.cents }

    public var isIncome: Bool { cents > 0 }
    public var isExpense: Bool { cents < 0 }
    public var magnitude: Money { Money(cents: Swift.abs(cents)) }

    /// 西班牙格式：1.234,56 €（四位数也加千分位，系统 es_ES 格式不加，所以自己写）。
    public var formatted: String {
        let negative = cents < 0
        let absCents = cents.magnitude
        let units = String(absCents / 100)
        let frac = absCents % 100
        var grouped = ""
        for (i, ch) in units.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(".") }
            grouped.append(ch)
        }
        let intText = String(grouped.reversed())
        let fracText = frac < 10 ? "0\(frac)" : "\(frac)"
        return "\(negative ? "-" : "")\(intText),\(fracText) €"
    }

    /// 给 --json 用的十进制字符串，如 "-1234.56"。
    public var decimalString: String {
        let negative = cents < 0
        let absCents = cents.magnitude
        let frac = absCents % 100
        return "\(negative ? "-" : "")\(absCents / 100).\(frac < 10 ? "0" : "")\(frac)"
    }
}
