import Foundation

/// 「说一句」记账：从一句大白话里认出是什么、多少钱。不用 AI，没网也行。
/// 「刚才咖啡 3 块 2」→ 咖啡，3,20。认不出金额就返回 nil，让界面说人话问一句。
public struct QuickPhrase: Equatable, Sendable {
    public var name: String
    public var emoji: String
    public var amount: Money

    /// 这句话是哪一种：花了、收了、还钱、自己账户之间转、借给别人、别人还我。
    public enum Kind: Equatable, Sendable {
        case spend
        case income
        /// 还欠的钱（信用卡、分期、欠某个人的）。`to` 是话里说的那个名字。
        case repay(to: String)
        /// 自己的账户之间挪（「转 200 到储蓄」）。
        case transfer(to: String)
        /// 借给别人。
        case lend(to: String)
        /// 别人把借的钱还我。
        case repaidToMe(from: String)
    }
    public var kind: Kind = .spend
    /// 话里说了「店里」「店」：记到生意那边。
    public var shop = false

    public init(name: String, emoji: String, amount: Money, kind: Kind = .spend, shop: Bool = false) {
        self.name = name; self.emoji = emoji; self.amount = amount; self.kind = kind; self.shop = shop
    }

    /// 这句话是不是在说一笔账（要动账本）：听得出金额，而且说了记、花、买、付，或者是收了、还钱、转账、借钱这几种。
    /// 「这个值得买吗 200」这种问话不算。Mac 和手机的聊天都用这一个来判断要不要自己记，不交给聊天模型。
    public static func isBookkeeping(_ text: String) -> Bool {
        guard let q = parse(text) else { return false }
        if ["吗", "？", "?", "值得", "要不要", "能不能", "该不该"].contains(where: text.contains) { return false }
        return q.kind != .spend || ["记", "花了", "买了", "付了", "块"].contains(where: text.contains)
    }

    static let incomeWords = ["收了", "收到", "进账", "到账", "卖了", "工资", "收入", "赚了", "奖金", "退税"]

    /// 从一句话里认出是哪一种。认不出来就是花了。
    static func kind(of text: String) -> Kind {
        func capture(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text) else { return nil }
            var who = String(text[r])
            for f in ["了", "的", "钱", "给", " ", "，", ","] { who = who.replacingOccurrences(of: f, with: "") }
            return who
        }
        // 「小李还我 50」「小李还了我 50」
        if let who = capture(#"([^\d\s，,。]{1,8}?)还了?给?我"#), !who.isEmpty { return .repaidToMe(from: who) }
        // 「借给小李 50」
        if let who = capture(#"借给?了?\s*([^\d\s，,。]{1,8}?)\s*\d"#), !who.isEmpty, !text.contains("借我") { return .lend(to: who) }
        // 「转 200 到储蓄」「存 100 进旅行」
        if let to = capture(#"(?:转|存|挪)[^到进去]*(?:到|进|去)\s*([^\d\s，,。]{1,10})"#), !to.isEmpty { return .transfer(to: to) }
        // 「还信用卡 640」「还款 200」「还阿青 100」
        if text.contains("信用卡"), text.contains("还") { return .repay(to: "信用卡") }
        if text.contains("还款") || text.contains("还贷") { return .repay(to: text.contains("分期") ? "分期" : "") }
        if let to = capture(#"还了?给?\s*([^\d\s，,。我]{1,8}?)\s*\d"#), !to.isEmpty { return .repay(to: to) }
        if incomeWords.contains(where: text.contains) { return .income }
        return .spend
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

        let kind = Self.kind(of: text)
        let shop = text.contains("店里") || text.contains("店的") || text.hasPrefix("店")
        var rest = text
        if let all = Range(m.range, in: text) { rest.removeSubrange(all) }
        for f in filler + ["店里", "店的"] { rest = rest.replacingOccurrences(of: f, with: "") }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .income:
            var what = rest
            for f in ["收了", "收到", "进账", "到账", "卖了", "赚了"] { what = what.replacingOccurrences(of: f, with: "") }
            what = what.trimmingCharacters(in: .whitespacesAndNewlines)
            return QuickPhrase(name: what.isEmpty ? (shop ? "营业额" : "收入") : what, emoji: "💰", amount: amount, kind: kind, shop: shop)
        case .repay(let to): return QuickPhrase(name: to.isEmpty ? "还款" : "还\(to)", emoji: "💳", amount: amount, kind: kind, shop: shop)
        case .transfer(let to): return QuickPhrase(name: "转到\(to)", emoji: "🔀", amount: amount, kind: kind, shop: shop)
        case .lend(let to): return QuickPhrase(name: "借给\(to)", emoji: "🧑", amount: amount, kind: kind, shop: shop)
        case .repaidToMe(let from): return QuickPhrase(name: "\(from)还我", emoji: "🧑", amount: amount, kind: kind, shop: shop)
        case .spend: break
        }
        if let hit = known.first(where: { text.contains($0.0) }) {
            return QuickPhrase(name: hit.0, emoji: hit.1, amount: amount, shop: shop)
        }
        return QuickPhrase(name: rest.isEmpty ? "一笔开销" : rest, emoji: "🧾", amount: amount, shop: shop)
    }
}


// MARK: - 照一句话记账（Mac 和手机都只调这一处）

extension TrialBook {
    /// 照认出来的那句话记：花了记支出、收了记收入、还钱是还款、转是自己账户之间挪、借给别人和别人还我是借款往来。
    /// 后四种都不算花销也不算收入。话里说了「店里」而且开着生意那一边，就记到店里；只管生活时照样记在生活。
    /// - account: 钱从哪个账户出（收入、别人还我时是进哪个账户）。
    /// - Returns: 记了什么的一句话（给提示条和夏夏的回话用）。
    @discardableResult
    public mutating func record(_ q: QuickPhrase, account: String, place: String = "", daysAgo: Int = 0) throws -> String {
        let inShop = q.shop && showBiz
        func at(_ name: String) throws -> Int {
            guard let i = accounts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这个账户") }
            return i
        }
        func find(_ word: String, in list: [Account]) -> Account? {
            guard !word.isEmpty else { return list.count == 1 ? list.first : nil }
            return list.first { $0.name == word } ?? list.first { $0.name.contains(word) || word.contains($0.name) }
        }
        switch q.kind {
        case .spend:
            if inShop {
                let pay = shopHeld.first { $0.name == account }?.name ?? shopHeld.first?.name ?? account
                let cat = Self.shopCategories.first { q.name.contains($0.name) }?.name ?? q.name
                _ = try recordShopExpense(name: q.name, amount: q.amount, category: cat, account: pay, daysAgo: daysAgo)
                return "记好了 · 店里 \(q.name) \(q.amount.formatted) · \(pay)"
            }
            try record(name: q.name, emoji: q.emoji, amount: q.amount, account: account, place: place, daysAgo: daysAgo)
            return "记好了 · \(q.name) \(q.amount.formatted) · \(account)"
        case .income:
            if inShop {
                // 店里收的钱：加在那一天那个渠道已经收的上面
                guard let into = shopHeld.first(where: { $0.name == account })?.name ?? shopHeld.first?.name else { throw TrialError("还没有店里收钱的账户") }
                let day = todayDay - daysAgo
                var channels = shopDays.first { $0.day == day }.map { channels(of: $0) } ?? []
                if let i = channels.firstIndex(where: { $0.account == into }) { channels[i].amount = channels[i].amount + q.amount }
                else { channels.append(ShopChannel(into, q.amount)) }
                try recordShopIncome(daysAgo: daysAgo, channels: day >= 1 ? channels : [ShopChannel(into, q.amount)])
                return "记好了 · 店里收了 \(q.amount.formatted) · \(into)"
            }
            try record(name: q.name, emoji: q.emoji, amount: q.amount, income: true, account: account, place: place, daysAgo: daysAgo)
            return "记好了 · 收了 \(q.amount.formatted)（\(q.name)）· \(account)"
        case .repay(let to):
            let side: Side = inShop ? .biz : .life
            let owed = accounts.filter { $0.side == side && $0.kind == .debt && $0.balance > .zero }
            guard let debt = (to == "信用卡" ? owed.first { $0.isCreditCard } : nil) ?? find(to, in: owed) else {
                throw TrialError(to.isEmpty ? "欠的不止一笔，说一下还哪一笔，比如「还信用卡 640」" : "没找到欠着的「\(to)」")
            }
            let from = inShop ? (shopHeld.first { $0.name == account }?.name ?? shopHeld.first?.name ?? account) : account
            try repay(debt: debt.name, amount: q.amount, from: from)
            return "还好了 · \(debt.name) \(q.amount.formatted) · 从\(from)，不算花销"
        case .transfer(let to):
            let side: Side = inShop ? .biz : .life
            guard let target = find(to, in: transferTargets(side).filter { $0.name != account }) else { throw TrialError("没找到叫「\(to)」的账户") }
            let from = inShop ? (shopHeld.first { $0.name == account }?.name ?? shopHeld.first?.name ?? account) : account
            try transferAny(q.amount, from: from, to: target.name)
            return "转好了 · \(from) → \(target.name) \(q.amount.formatted)，不算花销"
        case .lend(let to):
            let f = try at(account)
            guard accounts[f].balance >= q.amount else { throw TrialError("\(account)里只有 \(accounts[f].balance.formatted)") }
            if let i = accounts.firstIndex(where: { $0.kind == .lent && ($0.name == "借给\(to)" || $0.name == to) }) {
                accounts[i].balance = accounts[i].balance + q.amount
            } else {
                try addDebt(name: "借给\(to)", amount: q.amount, owedToMe: true, note: "")
            }
            // 钱是从账户里拿出去的；重新找一遍位置（上面可能加了一行）
            let from = try at(account)
            accounts[from].balance = accounts[from].balance - q.amount
            return "记好了 · 借给\(to) \(q.amount.formatted) · 从\(account)，不算花销"
        case .repaidToMe(let from):
            guard let i = accounts.firstIndex(where: { $0.kind == .lent && $0.balance > .zero && ($0.name.contains(from) || from.contains($0.name)) }) else {
                throw TrialError("没找到「\(from)」欠你的那一笔")
            }
            guard q.amount <= accounts[i].balance else { throw TrialError("\(accounts[i].name)只欠 \(accounts[i].balance.formatted)") }
            let into = try at(account)
            accounts[i].balance = accounts[i].balance - q.amount
            accounts[into].balance = accounts[into].balance + q.amount
            if accounts[i].balance == .zero { accounts[i].note = "还清了" }
            return "记好了 · \(from)还了 \(q.amount.formatted) · 进\(account)，不算收入"
        }
    }
}
