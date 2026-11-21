import Foundation

/// 把银行对账单上的原话整理成好读的商户名，只用来显示，不改存的内容。
/// 比如「UBR* PENDING.UBER」→「Uber」，「COMPRA TARJ. MERCADONA MADRID 4821」→「Mercadona Madrid」。
/// 规则保守：拿不准就原样返回。
public enum Merchant {
    /// 认得出的常见商户：说明里（去掉符号、转小写后）包含左边，就显示右边。
    static let known: [(String, String)] = [
        ("ubr", "Uber"), ("uber", "Uber"), ("amzn", "Amazon"), ("amazon", "Amazon"), ("mercadona", "Mercadona"),
        ("glovo", "Glovo"), ("netflix", "Netflix"), ("spotify", "Spotify"), ("aliexpress", "AliExpress"),
        ("ikea", "IKEA"), ("lidl", "Lidl"), ("carrefour", "Carrefour"), ("zara", "Zara"), ("openai", "OpenAI"),
        ("anthropic", "Anthropic"), ("apple.com", "Apple"), ("google", "Google"), ("paypal", "PayPal"),
        ("basic-fit", "Basic-Fit"), ("basicfit", "Basic-Fit"), ("bizum", "Bizum"), ("ovh", "OVHcloud"),
    ]

    /// 开头这些词是银行加的，不是商户名。
    static let prefixes = ["compra tarj.", "compra tarjeta", "compra en", "compra", "pago en", "pago con tarjeta", "pago",
                           "tpv", "tarj.", "tarjeta", "recibo", "adeudo", "sq *", "sumup *", "sumup*", "paypal *", "paypal*",
                           "pending.", "card payment to", "payment to", "to "]

    public static func display(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        let lower = trimmed.lowercased()

        // 充值（Revolut 的 Top-up）
        if lower.hasPrefix("top-up") || lower.hasPrefix("top up") {
            if lower.contains("apple pay") { return "Apple Pay 充值" }
            return "充值"
        }
        // 含中文的多半是自己手写的，不动
        if trimmed.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) { return trimmed }

        // PayPal 后面跟着真正的商户时，用后面的；其余认得出的商户直接用标准写法
        let isPayPalWrapper = lower.hasPrefix("paypal *") || lower.hasPrefix("paypal*")
        // 按「词」来认，免得 Huber、Zarautz 这种被认错：短的要整词相同，长的词开头相同就行。
        let tokens = lower.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        func matches(_ key: String) -> Bool {
            if key.contains(where: { !($0.isLetter || $0.isNumber) }) { return lower.contains(key) }
            return key.count <= 4 ? tokens.contains(key) : tokens.contains { $0.hasPrefix(key) }
        }
        if !isPayPalWrapper, let hit = known.first(where: { matches($0.0) }) {
            // 「Bizum 张三」这种保留后面的人名
            if hit.1 == "Bizum" { return tidy(trimmed) }
            return hit.1
        }

        var text = trimmed
        var changed = true
        while changed {
            changed = false
            let l = text.lowercased()
            for p in prefixes where l.hasPrefix(p) && text.count > p.count + 1 {
                text = String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
        }
        let cleaned = tidy(text)
        return cleaned.count >= 2 ? cleaned : trimmed
    }

    /// 去掉卡号尾巴、长数字、多余符号；全大写的改成首字母大写。
    static func tidy(_ text: String) -> String {
        var words: [String] = []
        for w in text.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            var word = String(w)
            if word.hasPrefix("*") { continue }                                     // *9362 这种卡号尾巴
            // Revolut**5670 这种：名字后面粘着卡号尾巴，只留名字
            if let star = word.firstIndex(of: "*"), word[star...].dropFirst().allSatisfy({ $0 == "*" || $0.isNumber }), star != word.startIndex {
                word = String(word[..<star])
            }
            let digits = word.filter(\.isNumber).count
            if digits >= 4 && digits * 2 >= word.count { continue }                 // 长数字、日期、流水号
            word = word.trimmingCharacters(in: CharacterSet(charactersIn: "*#,;:-_/"))
            if word.isEmpty { continue }
            words.append(word)
        }
        guard !words.isEmpty else { return text }
        let joined = words.joined(separator: " ")
        let letters = joined.filter(\.isLetter)
        // 全大写的拉丁字母才改；有小写说明本来就写得好好的
        if !letters.isEmpty, letters.allSatisfy(\.isUppercase), letters.count > 3 {
            return words.map { w in
                w.count <= 3 && w.allSatisfy(\.isLetter) && words.count > 1 && w != words.first ? w   // SL、SA 这种留着
                    : w.prefix(1).uppercased() + w.dropFirst().lowercased()
            }.joined(separator: " ")
        }
        return joined
    }
}
