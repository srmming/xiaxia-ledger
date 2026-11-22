import Foundation

// 多币种（2026-11-21 ming：「增加一个多币种，可以设置币种」）。
//
// 口径：
// - 账本有一个「主币种」（默认欧元）。看板、月报、净资产里的总数都换成主币种。
// - 每个账户可以有自己的币种（美元卡、人民币账户……），没写就是主币种。
//   流水的 amount 永远是「这个账户的币种」里的金额，也就是银行账单上写的那个数。
//   所以以前的流水（全是欧元账户）一分钱都不用改。
// - 外币账户的每一笔，记下时顺便记当天的汇率（fx）。汇总时用这个汇率换算，以后汇率再变，过去的数不跟着变。
//   银行实际扣了多少主币种，可以手动改成银行的汇率（source = bank / manual）。
// - 用欧元卡在国外刷了 50 美元，银行扣了 46,12 €：amount 记 −46,12（以银行为准），original 记 50 USD，只是备注。
// - 汇率表：欧洲央行每天公布的参考汇率（免费、不用密钥，只下载一张公开表，不发出任何账目）。
//   表里存「1 欧元 = 多少某币」，别的币之间用欧元中转。

/// 一个币种的显示信息。
public struct CurrencyInfo: Hashable, Sendable {
    public var code: String
    public var name: String
    public var symbol: String
    /// 日元、韩元这种平时不写小数。
    public var noDecimals: Bool

    public init(code: String, name: String, symbol: String, noDecimals: Bool = false) {
        self.code = code; self.name = name; self.symbol = symbol; self.noDecimals = noDecimals
    }
}

public enum Currencies {
    /// 常用的放前面（选币种时按这个顺序），后面是欧洲央行有汇率的其它币种。
    public static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "EUR", name: "欧元", symbol: "€"),
        CurrencyInfo(code: "USD", name: "美元", symbol: "US$"),
        CurrencyInfo(code: "CNY", name: "人民币", symbol: "¥"),
        CurrencyInfo(code: "GBP", name: "英镑", symbol: "£"),
        CurrencyInfo(code: "HKD", name: "港币", symbol: "HK$"),
        CurrencyInfo(code: "JPY", name: "日元", symbol: "JP¥", noDecimals: true),
        CurrencyInfo(code: "CHF", name: "瑞士法郎", symbol: "CHF"),
        CurrencyInfo(code: "KRW", name: "韩元", symbol: "₩", noDecimals: true),
        CurrencyInfo(code: "SGD", name: "新加坡元", symbol: "S$"),
        CurrencyInfo(code: "AUD", name: "澳元", symbol: "A$"),
        CurrencyInfo(code: "CAD", name: "加元", symbol: "C$"),
        CurrencyInfo(code: "NZD", name: "新西兰元", symbol: "NZ$"),
        CurrencyInfo(code: "SEK", name: "瑞典克朗", symbol: "SEK"),
        CurrencyInfo(code: "NOK", name: "挪威克朗", symbol: "NOK"),
        CurrencyInfo(code: "DKK", name: "丹麦克朗", symbol: "DKK"),
        CurrencyInfo(code: "PLN", name: "波兰兹罗提", symbol: "zł"),
        CurrencyInfo(code: "CZK", name: "捷克克朗", symbol: "Kč"),
        CurrencyInfo(code: "HUF", name: "匈牙利福林", symbol: "Ft", noDecimals: true),
        CurrencyInfo(code: "RON", name: "罗马尼亚列伊", symbol: "lei"),
        CurrencyInfo(code: "BGN", name: "保加利亚列弗", symbol: "лв"),
        CurrencyInfo(code: "TRY", name: "土耳其里拉", symbol: "₺"),
        CurrencyInfo(code: "ISK", name: "冰岛克朗", symbol: "kr", noDecimals: true),
        CurrencyInfo(code: "ILS", name: "以色列新谢克尔", symbol: "₪"),
        CurrencyInfo(code: "INR", name: "印度卢比", symbol: "₹"),
        CurrencyInfo(code: "IDR", name: "印尼盾", symbol: "Rp", noDecimals: true),
        CurrencyInfo(code: "MYR", name: "马来西亚林吉特", symbol: "RM"),
        CurrencyInfo(code: "THB", name: "泰铢", symbol: "฿"),
        CurrencyInfo(code: "PHP", name: "菲律宾比索", symbol: "₱"),
        CurrencyInfo(code: "BRL", name: "巴西雷亚尔", symbol: "R$"),
        CurrencyInfo(code: "MXN", name: "墨西哥比索", symbol: "MX$"),
        CurrencyInfo(code: "ZAR", name: "南非兰特", symbol: "R"),
    ]

    public static func info(_ code: String) -> CurrencyInfo {
        let c = code.uppercased()
        return all.first { $0.code == c } ?? CurrencyInfo(code: c, name: c, symbol: c)
    }

    public static func isKnown(_ code: String) -> Bool { all.contains { $0.code == code.uppercased() } }

    /// 「美元 USD」这种给人看的写法。
    public static func label(_ code: String) -> String {
        let i = info(code)
        return i.name == i.code ? i.code : "\(i.name) \(i.code)"
    }
}

extension Money {
    /// 主币种。`formatted` 用它的符号；app 和 fin 打开账本时设成账本的主币种。
    nonisolated(unsafe) public static var defaultCurrency = "EUR"

    /// 按某个币种显示：1.234,56 US$；日元这种不写小数：1.235 JP¥。
    public func formatted(in currency: String) -> String {
        let info = Currencies.info(currency)
        let negative = cents < 0
        var absCents = cents.magnitude
        if info.noDecimals { absCents = (absCents + 50) / 100 * 100 }
        let units = String(absCents / 100)
        var grouped = ""
        for (i, ch) in units.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(".") }
            grouped.append(ch)
        }
        let intText = String(grouped.reversed())
        let frac = absCents % 100
        let number = info.noDecimals ? intText : "\(intText),\(frac < 10 ? "0" : "")\(frac)"
        return "\(negative ? "-" : "")\(number) \(info.symbol)"
    }

    /// 乘一个汇率，四舍五入到分。
    public func converted(by rate: Double) -> Money {
        Money(cents: Int64((Double(cents) * rate).rounded()))
    }
}

/// 一笔流水记下时用的汇率：1 个账户币种 = rate 个主币种。
public struct FXNote: Hashable, Codable, Sendable {
    /// 记的时候主币种是哪个。以后改了主币种，这个汇率就不用了，改用汇率表。
    public var base: String
    public var rate: Double
    /// 汇率是哪天的（欧洲央行周末不公布，取那之前最近的一天）。
    public var date: LocalDate
    /// ecb = 欧洲央行；bank = 按银行实际扣款算的；manual = 手动填的。
    public var source: String

    public init(base: String, rate: Double, date: LocalDate, source: String) {
        self.base = base; self.rate = rate; self.date = date; self.source = source
    }

    public var sourceLabel: String {
        switch source {
        case "ecb": "欧洲央行"
        case "bank": "按银行实际扣款"
        case "manual": "手动填的"
        default: source
        }
    }
}

/// 用别的币种付的原价（比如欧元卡在美国刷了 50 美元）。只做备注，金额以银行扣的为准。
public struct ForeignAmount: Hashable, Codable, Sendable {
    public var amount: Money
    public var currency: String
    public init(amount: Money, currency: String) { self.amount = amount; self.currency = currency.uppercased() }
    public var formatted: String { amount.formatted(in: currency) }
}

/// 某天 1 欧元换多少某币。
public struct RatePoint: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var perEUR: Double
    public init(date: LocalDate, perEUR: Double) { self.date = date; self.perEUR = perEUR }
}

/// 跟着账本走的币种设置：主币种、汇率表。存在 SQLite 的 meta 表 key = currency。
public struct CurrencySettings: Hashable, Codable, Sendable {
    public var base: String
    /// 币种 → 按日期排好的汇率（1 欧元 = 多少该币）。只存用得到的币种。
    public var rates: [String: [RatePoint]]
    /// 上次从欧洲央行取汇率的时间。
    public var updatedAt: Date?

    public init(base: String = "EUR", rates: [String: [RatePoint]] = [:], updatedAt: Date? = nil) {
        self.base = base; self.rates = rates; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case base, rates, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = (try c.decodeIfPresent(String.self, forKey: .base)) ?? "EUR"
        rates = (try? c.decodeIfPresent([String: [RatePoint]].self, forKey: .rates)) ?? [:]
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// 某天 1 欧元换多少 code：取那天或之前最近的一天；那之前没有就取之后最早的一天。欧元永远是 1。
    public func perEUR(_ code: String, on date: LocalDate) -> RatePoint? {
        let c = code.uppercased()
        if c == "EUR" { return RatePoint(date: date, perEUR: 1) }
        guard let list = rates[c], !list.isEmpty else { return nil }
        var best: RatePoint?
        for p in list where p.date <= date { best = p }   // 按日期排好了，最后一个就是最近的
        return best ?? list.first
    }

    /// 某天 1 个 from = 多少个 to（经欧元中转）。没有汇率时返回 nil。
    public func rate(from: String, to: String, on date: LocalDate) -> (rate: Double, date: LocalDate)? {
        let f = from.uppercased(), t = to.uppercased()
        if f == t { return (1, date) }
        guard let a = perEUR(f, on: date), let b = perEUR(t, on: date), a.perEUR > 0 else { return nil }
        // 用的是哪天的：两边里离得较远的那一天（欧元那边就是当天）。
        let used = f == "EUR" ? b.date : (t == "EUR" ? a.date : min(a.date, b.date))
        return (b.perEUR / a.perEUR, used)
    }

    /// 把新取到的汇率并进来（同一天同一币种以新的为准），只留 wanted 里的币种。
    public mutating func merge(_ table: [String: [RatePoint]], keeping wanted: Set<String>) {
        for (code, points) in table where wanted.contains(code) && code != "EUR" {
            var byDate = Dictionary((rates[code] ?? []).map { ($0.date, $0) }, uniquingKeysWith: { _, b in b })
            for p in points { byDate[p.date] = p }
            rates[code] = byDate.values.sorted { $0.date < $1.date }
        }
    }

    /// 最新一天的汇率是哪天（给设置页显示「欧洲央行 · 11 月 20 日」）。
    public var latestRateDate: LocalDate? { rates.values.compactMap { $0.last?.date }.max() }
}

/// 欧洲央行汇率表（XML）。
public enum ECBRates {
    /// 最近 90 天；最近一天；1999 年以来全部（第一次导入老账时用）。
    public static let url90d = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml")!
    public static let urlDaily = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    public static let urlAll = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml")!

    /// 读欧洲央行的 XML：<Cube time="2026-11-20"><Cube currency="USD" rate="1.0573"/>…
    /// 只认这两种标签，用字符串扫，不依赖 XML 解析库（Linux 上也能跑测试）。
    public static func parse(_ xml: String) -> [String: [RatePoint]] {
        var out: [String: [RatePoint]] = [:]
        var day: LocalDate?
        var rest = Substring(xml)
        while let open = rest.range(of: "<Cube") {
            rest = rest[open.upperBound...]
            guard let close = rest.firstIndex(of: ">") else { break }
            let tag = rest[..<close]
            rest = rest[close...]
            if let t = attr("time", in: tag), let d = LocalDate(t) { day = d; continue }
            if let code = attr("currency", in: tag), let r = attr("rate", in: tag), let v = Double(r), let day {
                out[code.uppercased(), default: []].append(RatePoint(date: day, perEUR: v))
            }
        }
        for k in out.keys { out[k]!.sort { $0.date < $1.date } }
        return out
    }

    private static func attr(_ name: String, in tag: Substring) -> String? {
        for quote in ["'", "\""] {
            if let r = tag.range(of: "\(name)=\(quote)") {
                let after = tag[r.upperBound...]
                if let end = after.firstIndex(of: Character(quote)) { return String(after[..<end]) }
            }
        }
        return nil
    }
}

extension Ledger {
    /// 主币种。
    public var baseCurrency: String { currency.base }

    /// 账户的币种（没写就是主币种）。
    public func currency(ofAccount id: String) -> String {
        accounts.first { $0.id == id }?.currency?.uppercased() ?? currency.base
    }

    /// 用到的外币（不是主币种的账户币种、流水原价的币种）。取汇率时只取这些。
    public var foreignCurrencies: Set<String> {
        var set = Set(accounts.compactMap { $0.currency?.uppercased() })
        for t in transactions { if let o = t.original { set.insert(o.currency) } }
        for s in subscriptions { if let c = s.currency { set.insert(c.uppercased()) } }
        set.remove(currency.base)
        return set
    }

    /// 有没有外币账户。没有的话一切照旧（不用换算）。
    public var hasForeignAccounts: Bool {
        accounts.contains { ($0.currency?.uppercased() ?? currency.base) != currency.base }
    }

    /// 换成主币种的汇率：1 个 code = 多少主币种。没有汇率时返回 nil。
    public func rateToBase(_ code: String, on date: LocalDate) -> (rate: Double, date: LocalDate)? {
        currency.rate(from: code, to: currency.base, on: date)
    }

    /// 这笔流水换成主币种是多少。
    /// 账户本来就是主币种：原样。记的时候存了汇率（而且主币种没改过）：按那个汇率。否则按汇率表那天的汇率。
    /// 汇率表里也没有（还没联网取过）：先按 1:1 算，missingRateCurrencies 里会列出来提醒。
    public func baseAmount(_ tx: Transaction) -> Money {
        let code = currency(ofAccount: tx.accountID)
        if code == currency.base { return tx.amount }
        if let fx = tx.fx, fx.base == currency.base { return tx.amount.converted(by: fx.rate) }
        if let r = rateToBase(code, on: tx.date) { return tx.amount.converted(by: r.rate) }
        return tx.amount
    }

    /// 一笔钱（某币种、某天）换成主币种。
    public func toBase(_ amount: Money, currency code: String, on date: LocalDate) -> Money {
        if code.uppercased() == currency.base { return amount }
        if let r = rateToBase(code, on: date) { return amount.converted(by: r.rate) }
        return amount
    }

    /// 全部流水，金额换成主币种。所有「加起来」的统计（月报、看板、净资产）都用它。
    /// 没有外币账户时直接返回原来的流水，不多花一点时间。
    public var baseTransactions: [Transaction] {
        guard hasForeignAccounts else { return transactions }
        return transactions.map { t in
            var c = t
            c.amount = baseAmount(t)
            return c
        }
    }

    /// 外币账户里缺汇率的币种（还没联网取过汇率）。
    public var missingRateCurrencies: [String] {
        let codes = Set(accounts.compactMap { $0.currency?.uppercased() }).subtracting([currency.base])
        return codes.filter { rateToBase($0, on: .today) == nil }.sorted()
    }

    /// 每个账户的余额：native 是账户自己的币种，base 是换成主币种（外币按今天的汇率）。
    public func accountBalances(asOf date: LocalDate = .today) -> [String: (native: Money, base: Money)] {
        let native = Summaries.balances(transactions)
        var out: [String: (Money, Money)] = [:]
        for (id, m) in native {
            out[id] = (m, toBase(m, currency: currency(ofAccount: id), on: date))
        }
        return out
    }

    /// 某笔流水按账户币种显示：外币账户写成「12,00 US$」，主币种账户照旧。
    public func formatted(_ tx: Transaction) -> String {
        tx.amount.formatted(in: currency(ofAccount: tx.accountID))
    }

    /// 记一笔外币流水时用的汇率说明：欧洲央行那天的汇率。账户是主币种就不用记。
    public func fxNote(accountID: String, date: LocalDate) -> FXNote? {
        let code = currency(ofAccount: accountID)
        guard code != currency.base, let r = rateToBase(code, on: date) else { return nil }
        return FXNote(base: currency.base, rate: r.rate, date: r.date, source: "ecb")
    }

    /// 外币账户的新流水还没记汇率的，按汇率表补上（只补没写的，不改已经有的）。返回补了几笔。
    @discardableResult
    public mutating func fillMissingFX() -> Int {
        guard hasForeignAccounts else { return 0 }
        var n = 0
        for i in transactions.indices where transactions[i].fx == nil {
            if let note = fxNote(accountID: transactions[i].accountID, date: transactions[i].date) {
                transactions[i].fx = note
                n += 1
            }
        }
        return n
    }

    // MARK: 写入（都记进改动记录，能撤销）

    /// 改主币种。已有的流水金额不变（它们是账户币种的），只是汇总换成新的主币种。
    @discardableResult
    public mutating func setBaseCurrency(_ code: String, author: String) throws -> ChangeRecord {
        let c = code.uppercased()
        guard Currencies.isKnown(c) else { throw CurrencyError.unknownCurrency(code) }
        guard c != currency.base else { throw ManageError.nothingToChange }
        var snapshot = PlanSnapshot()
        snapshot.currency = currency
        snapshot.accounts = accounts
        // 原来没写币种的账户其实是旧主币种的，先写明，免得改了主币种之后它们跟着「变成」新币种。
        let old = currency.base
        for i in accounts.indices where accounts[i].currency == nil { accounts[i].currency = old }
        for i in accounts.indices where accounts[i].currency == c { accounts[i].currency = nil }
        currency.base = c
        Money.defaultCurrency = c
        let change = snapshotChange(.currency, "主币种改成\(Currencies.label(c))（原来是\(Currencies.label(old))）", before: snapshot, author: author)
        changes.append(change)
        return change
    }

    /// 给账户定币种（新账户、或者原来记错了）。账户里已有的流水金额不变。
    @discardableResult
    public mutating func setAccountCurrency(_ accountID: String, _ code: String, author: String) throws -> ChangeRecord {
        let c = code.uppercased()
        guard Currencies.isKnown(c) else { throw CurrencyError.unknownCurrency(code) }
        guard let i = accounts.firstIndex(where: { $0.id == accountID }) else { throw EditError.unknownAccount(accountID) }
        let value: String? = c == currency.base ? nil : c
        guard accounts[i].currency?.uppercased() != value else { throw ManageError.nothingToChange }
        var snapshot = PlanSnapshot()
        snapshot.accounts = [accounts[i]]
        let ids = transactions.filter { $0.accountID == accountID }.map(\.id)
        let previous = transactions.filter { $0.accountID == accountID }
        accounts[i].currency = value
        // 账户里的流水按新币种重新记当天汇率（金额本身不动）。
        for k in transactions.indices where transactions[k].accountID == accountID {
            transactions[k].fx = fxNote(accountID: accountID, date: transactions[k].date)
        }
        let change = snapshotChange(.currency, "账户「\(accounts[i].name)」的币种改成\(Currencies.label(c))",
                                    ids: ids, before: snapshot, previous: previous, author: author)
        changes.append(change)
        return change
    }

    /// 手动改一笔外币流水的汇率（比如按银行实际扣的欧元算）。bankAmount 给了就按它反算汇率。
    @discardableResult
    public mutating func setRate(_ txID: UUID, rate: Double? = nil, bankAmount: Money? = nil, author: String) throws -> ChangeRecord {
        guard let i = transactions.firstIndex(where: { $0.id == txID }) else { throw EditError.unknownTransaction(txID.uuidString, 0) }
        let tx = transactions[i]
        let code = currency(ofAccount: tx.accountID)
        guard code != currency.base else { throw CurrencyError.notForeign }
        let r: Double, source: String
        if let bankAmount {
            guard tx.amount.cents != 0 else { throw EditError.amountMustBePositive }
            r = Double(bankAmount.magnitude.cents) / Double(tx.amount.magnitude.cents); source = "bank"
        } else if let rate, rate > 0 {
            r = rate; source = "manual"
        } else { throw CurrencyError.badRate }
        let base = currency.base
        let note = FXNote(base: base, rate: r, date: tx.date, source: source)
        return modify([txID], kind: .currency,
                      summary: "汇率改成 1 \(code) = \(Self.rateText(r)) \(base)（\(tx.description)）", author: author) {
            $0.fx = note
        }
    }

    /// 把从欧洲央行取到的汇率存进账本（不算改账，不记改动记录），并给外币流水补上汇率。
    public mutating func applyRates(_ table: [String: [RatePoint]], fetchedAt: Date = Date()) {
        var wanted = foreignCurrencies
        wanted.formUnion(Currencies.all.prefix(5).map(\.code))   // 常用的几个也留着，换主币种时用得上
        currency.merge(table, keeping: wanted)
        currency.updatedAt = fetchedAt
        fillMissingFX()
    }

    static func rateText(_ r: Double) -> String {
        let s = String(format: r >= 10 ? "%.2f" : "%.4f", r)
        return s.replacingOccurrences(of: ".", with: ",")
    }
}

public enum CurrencyError: Error, LocalizedError, Equatable {
    case unknownCurrency(String)
    case notForeign
    case badRate
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .unknownCurrency(let c): "不认识的币种「\(c)」。用三个字母的代码，比如 EUR、USD、CNY。"
        case .notForeign: "这笔是主币种的，不用换算汇率。"
        case .badRate: "汇率要大于 0，或者填银行实际扣了多少。"
        case .network(let m): "取汇率没成功：\(m)。可以稍后再试，或者手动填汇率。"
        }
    }
}

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension ECBRates {
    /// 下载并解析。账本里最早的外币流水在 90 天以前时，取全部历史（大约 7 MB，只第一次要）。
    public static func fetch(since earliest: LocalDate?) async throws -> [String: [RatePoint]] {
        var useAll = false
        if let earliest {
            let cutoff = Calendar.current.date(byAdding: .day, value: -85, to: Date()) ?? Date()
            let c = Calendar.current.dateComponents([.year, .month, .day], from: cutoff)
            useAll = earliest < LocalDate(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
        }
        var request = URLRequest(url: useAll ? urlAll : url90d)
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw CurrencyError.network("欧洲央行返回 \(http.statusCode)") }
            let table = parse(String(decoding: data, as: UTF8.self))
            guard !table.isEmpty else { throw CurrencyError.network("汇率表是空的") }
            return table
        } catch let e as CurrencyError {
            throw e
        } catch {
            throw CurrencyError.network(error.localizedDescription)
        }
    }
}

extension Ledger {
    /// 外币流水里最早的日期（决定要不要下载全部历史汇率）。
    public var earliestForeignDate: LocalDate? {
        let foreignAccounts = Set(accounts.filter { ($0.currency?.uppercased() ?? currency.base) != currency.base }.map(\.id))
        return transactions.filter { foreignAccounts.contains($0.accountID) || $0.original != nil }.map(\.date).min()
    }

    /// 汇率需要更新吗：有外币，而且今天还没取过（或者缺某个币种）。
    public var needsRateRefresh: Bool {
        guard !foreignCurrencies.isEmpty else { return false }
        if !missingRateCurrencies.isEmpty { return true }
        guard let at = currency.updatedAt else { return true }
        return Date().timeIntervalSince(at) > 12 * 3600
    }
}
