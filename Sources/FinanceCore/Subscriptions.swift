import Foundation

// 订阅（2026-11-21 ming：「增加订阅信息」）：Netflix、Spotify、健身房、iCloud、云服务器……每月 / 每年固定在扣的钱。
// - 登记：名字、金额、币种、周期、下次扣款日、从哪个账户扣、归哪个账本。
// - 看：每月合计、一年合计（换成主币种），按下次扣款排，快到的标出来；最近一次扣款和登记的价钱不一样就标「涨价」。
// - 认：从已有流水里找出「同一个商户、差不多的金额、隔一个月 / 一年扣一次」的，列成「可能是订阅」，
//   用户（或 AI 在对话里问过用户）确认后再登记。只算出来给人看，不自动写进账本。

public struct Subscription: Identifiable, Hashable, Codable, Sendable {
    public enum Cycle: String, Codable, Sendable, CaseIterable {
        case weekly, monthly, quarterly, yearly

        public var label: String {
            switch self {
            case .weekly: "每周"
            case .monthly: "每月"
            case .quarterly: "每季度"
            case .yearly: "每年"
            }
        }

        /// 换成每月要多少：每周 × 52 / 12，每季度 / 3，每年 / 12。
        func monthly(_ m: Money) -> Money {
            switch self {
            case .weekly: Money(cents: (m.cents * 52 + 6) / 12)
            case .monthly: m
            case .quarterly: Money(cents: (m.cents + 1) / 3)
            case .yearly: Money(cents: (m.cents + 6) / 12)
            }
        }

        func yearly(_ m: Money) -> Money {
            switch self {
            case .weekly: Money(cents: m.cents * 52)
            case .monthly: Money(cents: m.cents * 12)
            case .quarterly: Money(cents: m.cents * 4)
            case .yearly: m
            }
        }

        /// 读不认识的（更新版本加的）当成每月。
        public init(from decoder: Decoder) throws {
            self = Cycle(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .monthly
        }

        /// 「每月」「monthly」「month」「月」都认。
        public init?(text: String) {
            let t = text.lowercased().trimmingCharacters(in: .whitespaces)
            switch t {
            case "weekly", "week", "每周", "周", "w": self = .weekly
            case "monthly", "month", "每月", "月", "m": self = .monthly
            case "quarterly", "quarter", "每季度", "季度", "季", "q": self = .quarterly
            case "yearly", "year", "annual", "annually", "每年", "年", "y": self = .yearly
            default: return nil
            }
        }
    }

    public var id: UUID
    public var name: String
    /// 每次扣多少（正数），币种见 currency。
    public var amount: Money
    /// 币种。nil = 扣款账户的币种（没写账户就是主币种）。
    public var currency: String?
    public var cycle: Cycle
    /// 下次扣款日。过了的话显示时自动往后推一个周期。
    public var nextDate: LocalDate
    public var accountID: String?
    public var bookID: String?
    public var category: String?
    /// 在流水里认它的关键词（商户名），比如「netflix」。没写就用名字。
    public var match: String?
    public var note: String?
    /// 不续了：哪天停的。停了的不算进合计，但留着记录。
    public var cancelledOn: LocalDate?
    /// 用户（或 AI 问过用户）说「最近很少用」：订阅页标「可以考虑退」（ming 2026-11-23）。nil = 没说过。
    public var rarelyUsed: Bool?

    public init(id: UUID = UUID(), name: String, amount: Money, currency: String? = nil, cycle: Cycle,
                nextDate: LocalDate, accountID: String? = nil, bookID: String? = nil, category: String? = nil,
                match: String? = nil, note: String? = nil, cancelledOn: LocalDate? = nil, rarelyUsed: Bool? = nil) {
        self.id = id; self.name = name; self.amount = amount.magnitude; self.currency = currency?.uppercased()
        self.cycle = cycle; self.nextDate = nextDate; self.accountID = accountID; self.bookID = bookID
        self.category = category; self.match = match; self.note = note; self.cancelledOn = cancelledOn
        self.rarelyUsed = rarelyUsed
    }

    public var isActive: Bool { cancelledOn == nil }

    /// 认流水用的关键词（小写）。
    public var matchKey: String { Subscriptions.key(match?.isEmpty == false ? match! : name) }
}

/// 给人看的订阅状态。
public struct SubscriptionStatus: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var amount: Money
    public var currency: String
    public var cycle: Subscription.Cycle
    /// 下一次扣款（已经推过今天了）。停了的是 nil。
    public var nextDate: LocalDate?
    public var daysLeft: Int?
    /// 换成主币种、摊到每月 / 每年。
    public var monthlyBase: Money
    public var yearlyBase: Money
    public var accountID: String?
    public var bookID: String?
    public var category: String?
    public var cancelledOn: LocalDate?
    /// 流水里最近一次扣款。
    public var lastChargeDate: LocalDate?
    public var lastChargeAmount: Money?
    /// 最近一次扣的和登记的不一样（多半是涨价了）。
    public var priceChanged: Bool
    /// 流水里认出了几次扣款。
    public var chargeCount: Int
    /// 最近一次扣的比登记的多（涨价了）。
    public var priceUp: Bool = false
    /// 用户说最近很少用。
    public var rarelyUsed: Bool = false
    /// 摊到每月多少（订阅自己的币种）。每月扣的就是 amount。
    public var monthlyAmount: Money = .zero

    /// 7 天内要扣。
    public var isDueSoon: Bool { (daysLeft ?? 99) <= 7 }
    /// 3 天内要扣（订阅页标出来）。
    public var isDueVerySoon: Bool { cancelledOn == nil && (daysLeft ?? 99) <= 3 }
    /// 「可以考虑退」：刚涨价，或者说过很少用。永远排在订阅页最上面。
    public var worthReviewing: Bool { cancelledOn == nil && (priceUp || rarelyUsed) }
    /// 为什么可以考虑退，一句话。
    public var reviewReason: String? {
        guard worthReviewing else { return nil }
        if priceUp, rarelyUsed { return "刚涨价，你也说很少用" }
        return priceUp ? "刚涨价" : "你说最近很少用"
    }
}

/// 从流水里认出来的「可能是订阅」。
public struct SubscriptionCandidate: Identifiable, Codable, Sendable, Equatable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var amount: Money
    public var currency: String
    public var cycle: Subscription.Cycle
    public var nextDate: LocalDate
    public var lastDate: LocalDate
    public var count: Int
    public var accountID: String
    public var bookID: String?
    public var category: String?
    /// 最近几笔（给人核对用）。
    public var transactionIDs: [UUID]

    public func subscription() -> Subscription {
        Subscription(name: name, amount: amount, cycle: cycle, nextDate: nextDate, accountID: accountID,
                     bookID: bookID, category: category, match: key)
    }
}

public struct SubscriptionTotals: Codable, Sendable, Equatable {
    public var monthly: Money
    public var yearly: Money
    public var activeCount: Int
    public var dueSoon: Int
    /// 7 天内要扣几笔、一共多少（换成主币种）。
    public var weekCount: Int = 0
    public var weekAmount: Money = .zero
    /// 可以考虑退的几个、每月一共多少（主币种）。
    public var reviewCount: Int = 0
    public var reviewMonthly: Money = .zero
}

/// 订阅多了以后分组折叠（ming 2026-11-23）：可以考虑退 / 这周要扣 / 这个月 / 年付的。
public struct SubscriptionGroup: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case review, thisWeek, thisMonth, later, yearly }
    public var kind: Kind
    public var items: [SubscriptionStatus]
    public var id: String { kind.rawValue }
    public var title: String {
        switch kind {
        case .review: "可以考虑退"
        case .thisWeek: "这周要扣"
        case .thisMonth: "这个月"
        case .later: "下个月以后"
        case .yearly: "年付和季付"
        }
    }
}

extension LocalDate {
    /// 从某个固定日子数起的第几天（只用来算差几天、加几天）。
    public var dayNumber: Int {
        let a = (14 - month) / 12, y = year + 4800 - a, m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    init(dayNumber n: Int) {
        let a = n + 32044, b = (4 * a + 3) / 146097, c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461, e = c - 1461 * d / 4, m = (5 * e + 2) / 153
        self.init(year: 100 * b + d - 4800 + m / 10, month: m + 3 - 12 * (m / 10), day: e - (153 * m + 2) / 5 + 1)
    }

    public func adding(days: Int) -> LocalDate { LocalDate(dayNumber: dayNumber + days) }

    /// 加几个月，日子超出那个月就取月底（1 月 31 日 + 1 个月 = 2 月 28 日）。
    public func adding(months: Int) -> LocalDate {
        let ym = yearMonth.adding(months: months)
        return LocalDate(year: ym.year, month: ym.month, day: min(day, LocalDate.daysIn(ym)))
    }

    public static func daysIn(_ ym: YearMonth) -> Int {
        let next = ym.adding(months: 1)
        return LocalDate(year: next.year, month: next.month, day: 1).dayNumber - LocalDate(year: ym.year, month: ym.month, day: 1).dayNumber
    }

    public func days(until other: LocalDate) -> Int { other.dayNumber - dayNumber }
}

extension Subscription.Cycle {
    func advance(_ d: LocalDate, by n: Int = 1) -> LocalDate {
        switch self {
        case .weekly: d.adding(days: 7 * n)
        case .monthly: d.adding(months: n)
        case .quarterly: d.adding(months: 3 * n)
        case .yearly: d.adding(months: 12 * n)
        }
    }
}

public enum Subscriptions {
    /// 商户关键词：整理过的商户名，小写、去掉空格和符号。「NETFLIX.COM 866-579」→「netflix」。
    public static func key(_ text: String) -> String {
        Merchant.display(text).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 下一次扣款：stored 过了就按周期往后推，直到不早于 today。
    public static func upcoming(_ s: Subscription, today: LocalDate) -> LocalDate {
        var d = s.nextDate
        var guardCount = 0
        while d < today && guardCount < 2000 { d = s.cycle.advance(s.nextDate, by: guardCount + 1); guardCount += 1 }
        return d
    }

    /// 某条流水是不是这个订阅的扣款：支出、商户关键词对上。
    static func isCharge(_ tx: Transaction, of s: Subscription) -> Bool {
        guard tx.amount.cents < 0, tx.flow == nil else { return false }
        if let a = s.accountID, a != tx.accountID { return false }
        let k = s.matchKey
        guard !k.isEmpty else { return false }
        let tk = key(tx.description)
        return tk == k || tk.contains(k) || (tk.count >= 4 && k.contains(tk))
    }

    public static func status(_ ledger: Ledger, today: LocalDate = .today) -> [SubscriptionStatus] {
        ledger.subscriptions.map { s in
            let code = s.currency ?? s.accountID.map { ledger.currency(ofAccount: $0) } ?? ledger.baseCurrency
            let charges = ledger.transactions.filter { isCharge($0, of: s) }.sorted { $0.date < $1.date }
            let last = charges.last
            let next = s.isActive ? upcoming(s, today: today) : nil
            let monthly = s.isActive ? ledger.toBase(s.cycle.monthly(s.amount), currency: code, on: today) : .zero
            let yearly = s.isActive ? ledger.toBase(s.cycle.yearly(s.amount), currency: code, on: today) : .zero
            var changed = false
            if let last, s.isActive {
                // 差 1% 以上、而且至少差 10 分才算（汇率小抖动不算）。
                let diff = abs(last.amount.magnitude.cents - s.amount.cents)
                changed = diff >= 10 && diff * 100 > s.amount.cents
                // 账户币种和订阅币种不一样时（欧元卡扣美元订阅）没法直接比，不标。
                if ledger.currency(ofAccount: last.accountID) != code { changed = false }
            }
            var st = SubscriptionStatus(id: s.id, name: s.name, amount: s.amount, currency: code, cycle: s.cycle,
                                        nextDate: next, daysLeft: next.map { today.days(until: $0) },
                                        monthlyBase: monthly, yearlyBase: yearly, accountID: s.accountID, bookID: s.bookID,
                                        category: s.category, cancelledOn: s.cancelledOn,
                                        lastChargeDate: last?.date, lastChargeAmount: last?.amount.magnitude,
                                        priceChanged: changed, chargeCount: charges.count)
            st.priceUp = changed && (last?.amount.magnitude ?? .zero) > s.amount
            st.rarelyUsed = s.rarelyUsed == true
            st.monthlyAmount = s.cycle.monthly(s.amount)
            return st
        }
        .sorted { a, b in
            switch (a.nextDate, b.nextDate) {
            case let (x?, y?): return x == y ? a.name < b.name : x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.name < b.name
            }
        }
    }

    public static func totals(_ list: [SubscriptionStatus], bookID: String? = nil) -> SubscriptionTotals {
        let active = list.filter { $0.cancelledOn == nil && (bookID == nil || $0.bookID == nil || $0.bookID == bookID) }
        return SubscriptionTotals(monthly: active.reduce(.zero) { $0 + $1.monthlyBase },
                                  yearly: active.reduce(.zero) { $0 + $1.yearlyBase },
                                  activeCount: active.count, dueSoon: active.filter(\.isDueSoon).count,
                                  weekCount: active.filter(\.isDueSoon).count,
                                  weekAmount: active.filter(\.isDueSoon).reduce(.zero) { $0 + base($1) },
                                  reviewCount: active.filter(\.worthReviewing).count,
                                  reviewMonthly: active.filter(\.worthReviewing).reduce(.zero) { $0 + $1.monthlyBase })
    }

    /// 这一次扣多少，换成主币种（按每月折算的比例换回一次的钱）。
    static func base(_ s: SubscriptionStatus) -> Money {
        let m = s.cycle.monthly(s.amount)
        guard m.cents > 0 else { return .zero }
        return Money(cents: s.monthlyBase.cents * s.amount.cents / m.cents)
    }

    /// 分组：可以考虑退的永远最上面；其余按下次扣款分「这周要扣 / 这个月 / 下个月以后」，年付季付单放一组。
    /// 没有东西的组不返回。停了的不在里面。
    public static func groups(_ list: [SubscriptionStatus], today: LocalDate = .today) -> [SubscriptionGroup] {
        let active = list.filter { $0.cancelledOn == nil }
        let review = active.filter(\.worthReviewing)
        let rest = active.filter { !$0.worthReviewing }
        let monthEnd = LocalDate(year: today.year, month: today.month, day: LocalDate.daysIn(today.yearMonth))
        var week: [SubscriptionStatus] = [], month: [SubscriptionStatus] = [], later: [SubscriptionStatus] = [], yearly: [SubscriptionStatus] = []
        for s in rest {
            if s.isDueSoon { week.append(s) }
            else if s.cycle == .yearly || s.cycle == .quarterly { yearly.append(s) }
            else if let n = s.nextDate, n <= monthEnd { month.append(s) }
            else { later.append(s) }
        }
        return [SubscriptionGroup(kind: .review, items: review), SubscriptionGroup(kind: .thisWeek, items: week),
                SubscriptionGroup(kind: .thisMonth, items: month), SubscriptionGroup(kind: .later, items: later),
                SubscriptionGroup(kind: .yearly, items: yearly)].filter { !$0.items.isEmpty }
    }

    /// 从流水里认出「可能是订阅」：同一个账户、同一个商户，金额差不多（最多差 15%），
    /// 两次之间隔得很规律（每周 6–8 天、每月 26–35 天、每季度 85–96 天、每年 350–380 天），
    /// 而且最近一次还没「断」（离今天不超过一个周期再多 10 天）。已经登记过的不再列。
    /// 每月要至少 3 次、每周 4 次，每季度和每年 2 次就行。
    public static func detect(_ ledger: Ledger, today: LocalDate = .today) -> [SubscriptionCandidate] {
        let registered = ledger.subscriptions.map(\.matchKey).filter { !$0.isEmpty }
        var groups: [String: [Transaction]] = [:]
        for tx in ledger.transactions where tx.amount.cents < 0 && tx.flow == nil && !tx.isTransfer && !isFixedCost(tx) {
            let k = key(tx.description)
            guard k.count >= 2 else { continue }
            groups["\(tx.accountID)|\(k)", default: []].append(tx)
        }
        var out: [SubscriptionCandidate] = []
        for (gk, txs) in groups where txs.count >= 2 {
            let k = String(gk.split(separator: "|", maxSplits: 1).last ?? "")
            if registered.contains(where: { $0 == k || $0.contains(k) || k.contains($0) }) { continue }
            let sorted = txs.sorted { $0.date < $1.date }
            // 同一天扣了两次的只留一笔（重复扣款不影响周期判断）。
            var charges: [Transaction] = []
            for t in sorted where charges.last?.date != t.date { charges.append(t) }
            guard let found = bestCycle(charges) else { continue }
            let (cycle, run) = found
            guard let last = run.last else { continue }
            let next = upcomingFrom(last.date, cycle: cycle, today: today)
            let slack = cycle == .weekly ? 4 : 10
            guard last.date.days(until: today) <= days(of: cycle) + slack else { continue }   // 停了的不算
            let info = ledger.transactions.first { $0.id == last.id }
            out.append(SubscriptionCandidate(key: k, name: Merchant.display(last.description), amount: last.amount.magnitude,
                                             currency: ledger.currency(ofAccount: last.accountID), cycle: cycle,
                                             nextDate: next, lastDate: last.date, count: run.count,
                                             accountID: last.accountID, bookID: info?.bookID, category: info?.category,
                                             transactionIDs: run.suffix(6).map(\.id)))
        }
        return out.sorted { $0.nextDate == $1.nextDate ? $0.name < $1.name : $0.nextDate < $1.nextDate }
    }

    /// 房租、工资、水电、税、交通卡这些固定开销每月也扣，但不是「订阅」，不往候选里放。
    /// 看分类（中文名或图标名都认），没分类再看描述里的字。
    static let fixedCostCategories: Set<String> = [
        "房租", "housing", "店租", "shoprent", "水电", "utilities", "工资", "salary", "员工工资", "staff",
        "税费", "tax", "社保", "social", "交通", "transport", "还款", "repay", "借款", "loan",
        "储蓄", "savings", "投资", "invest", "转账", "transfer", "老板提款", "withdraw", "充值", "topup",
    ]
    static let fixedCostWords = ["房租", "租金", "店租", "工资", "薪水", "水电", "电费", "水费", "燃气", "增值税", "税",
                                 "社保", "交通卡", "月票", "alquiler", "nomina", "nómina", "iva", "hacienda",
                                 "seguridad social", "abono transporte", "rent", "salary", "payroll"]

    /// 进货、买菜、吃饭这些是「买东西」，再规律也不是订阅（比如每周去花市进一次货）。
    static let purchaseCategories: Set<String> = [
        "花材", "原料", "包装耗材", "进货", "supplies", "超市", "grocery", "餐饮", "dining", "买菜", "veggies",
        "水果", "fruit", "外卖", "delivery", "咖啡", "coffee", "加油", "fuel", "购物", "shopping",
    ]

    static func isFixedCost(_ tx: Transaction) -> Bool {
        if let c = tx.category?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
            return fixedCostCategories.contains(c) || fixedCostCategories.contains(c.lowercased())
                || purchaseCategories.contains(c) || purchaseCategories.contains(c.lowercased())
        }
        let text = tx.description.lowercased()
        return fixedCostWords.contains { w in
            // 短的西语/英语词按整词比，免得 "iva" 撞上 "privada"。
            w.allSatisfy(\.isASCII) && w.count <= 4
                ? text.split(whereSeparator: { !$0.isLetter }).contains { $0 == Substring(w) }
                : text.contains(w)
        }
    }

    static func days(of cycle: Subscription.Cycle) -> Int {
        switch cycle { case .weekly: 7; case .monthly: 31; case .quarterly: 92; case .yearly: 366 }
    }

    static func upcomingFrom(_ last: LocalDate, cycle: Subscription.Cycle, today: LocalDate) -> LocalDate {
        var n = 1
        var d = cycle.advance(last, by: n)
        while d < today && n < 2000 { n += 1; d = cycle.advance(last, by: n) }
        return d
    }

    /// 从最近一笔往回数，找最长的一串「间隔规律、金额差不多」的扣款，看它像哪种周期。
    static func bestCycle(_ charges: [Transaction]) -> (Subscription.Cycle, [Transaction])? {
        let ranges: [(Subscription.Cycle, ClosedRange<Int>, Int)] = [
            (.weekly, 6...8, 4), (.monthly, 26...35, 3), (.quarterly, 85...96, 2), (.yearly, 350...380, 2),
        ]
        for (cycle, range, need) in ranges {
            var run: [Transaction] = []
            for t in charges.reversed() {
                guard let first = run.first else { run = [t]; continue }
                let gap = t.date.days(until: first.date)
                if gap < range.lowerBound { continue }          // 一个周期里多出来的一笔（比如另买了一次）：跳过
                guard range.contains(gap), similar(t.amount, first.amount) else { break }
                run.insert(t, at: 0)
            }
            guard run.count >= need, let a = run.first?.date, let b = run.last?.date else { continue }
            // 这段时间里同一个商户还有很多别的扣款（超市、加油站）：是常去的店，不是订阅。最多容一笔另买的。
            let others = charges.filter { $0.date >= a && $0.date <= b }.count - run.count
            if others <= max(1, run.count / 4) { return (cycle, run) }
        }
        return nil
    }

    static func similar(_ a: Money, _ b: Money) -> Bool {
        let x = a.magnitude.cents, y = b.magnitude.cents
        guard max(x, y) > 0 else { return false }
        return abs(x - y) * 100 <= max(x, y) * 15
    }
}

public enum SubscriptionError: Error, LocalizedError, Equatable {
    case unknownSubscription(String)
    case ambiguous(String, Int)
    case alreadyCancelled(String)

    public var errorDescription: String? {
        switch self {
        case .unknownSubscription(let k): "找不到订阅「\(k)」"
        case .ambiguous(let k, let n): "「\(k)」对上了 \(n) 个订阅，写全一点名字，或者用编号"
        case .alreadyCancelled(let n): "「\(n)」已经停了"
        }
    }
}

extension Ledger {
    /// 按名字或编号（前几位）找订阅。
    public func findSubscription(_ key: String) throws -> Subscription {
        let k = key.trimmingCharacters(in: .whitespaces)
        if let s = subscriptions.first(where: { $0.id.uuidString.lowercased().hasPrefix(k.lowercased()) && k.count >= 4 }) { return s }
        let exact = subscriptions.filter { $0.name.lowercased() == k.lowercased() }
        if exact.count == 1 { return exact[0] }
        let hits = subscriptions.filter { $0.name.lowercased().contains(k.lowercased()) }
        if hits.count == 1 { return hits[0] }
        if hits.isEmpty { throw SubscriptionError.unknownSubscription(key) }
        // 名字一样的好几个，只有一个还在续，就是它。
        let active = hits.filter(\.isActive)
        if active.count == 1 { return active[0] }
        throw SubscriptionError.ambiguous(key, hits.count)
    }

    /// 登记一个订阅。
    @discardableResult
    public mutating func addSubscription(_ s: Subscription, author: String) throws -> ChangeRecord {
        guard !s.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ManageError.emptyName }
        guard s.amount.cents > 0 else { throw EditError.amountMustBePositive }
        if let a = s.accountID { try requireAccount(a) }
        if let b = s.bookID { try requireBook(b) }
        if let c = s.currency, !Currencies.isKnown(c) { throw CurrencyError.unknownCurrency(c) }
        subscriptions.append(s)
        var snapshot = PlanSnapshot()
        snapshot.addedSubscriptionIDs = [s.id]
        let code = s.currency ?? s.accountID.map { currency(ofAccount: $0) } ?? baseCurrency
        let change = snapshotChange(.subscription, "登记订阅「\(s.name)」\(s.cycle.label) \(s.amount.formatted(in: code))，下次 \(s.nextDate)",
                                    before: snapshot, author: author)
        changes.append(change)
        return change
    }

    /// 改订阅（涨价了、换了扣款日、换了账户……）。传进来改好的整条。
    @discardableResult
    public mutating func editSubscription(_ updated: Subscription, author: String) throws -> ChangeRecord {
        guard let i = subscriptions.firstIndex(where: { $0.id == updated.id }) else { throw SubscriptionError.unknownSubscription(updated.name) }
        guard subscriptions[i] != updated else { throw ManageError.nothingToChange }
        guard !updated.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ManageError.emptyName }
        guard updated.amount.cents > 0 else { throw EditError.amountMustBePositive }
        if let a = updated.accountID { try requireAccount(a) }
        if let b = updated.bookID { try requireBook(b) }
        if let c = updated.currency, !Currencies.isKnown(c) { throw CurrencyError.unknownCurrency(c) }
        let old = subscriptions[i]
        var parts: [String] = []
        if old.name != updated.name { parts.append("改名「\(updated.name)」") }
        if old.amount != updated.amount || old.currency != updated.currency {
            let code = updated.currency ?? updated.accountID.map { currency(ofAccount: $0) } ?? baseCurrency
            parts.append("金额 \(updated.amount.formatted(in: code))")
        }
        if old.cycle != updated.cycle { parts.append(updated.cycle.label) }
        if old.nextDate != updated.nextDate { parts.append("下次 \(updated.nextDate)") }
        if old.cancelledOn != updated.cancelledOn { parts.append(updated.cancelledOn == nil ? "恢复续费" : "停了") }
        if parts.isEmpty { parts.append("改了细节") }
        subscriptions[i] = updated
        var snapshot = PlanSnapshot()
        snapshot.subscriptions = [old]
        let change = snapshotChange(.subscription, "订阅「\(old.name)」：" + parts.joined(separator: "、"), before: snapshot, author: author)
        changes.append(change)
        return change
    }

    /// 不续了。留着记录，不再算进合计。
    @discardableResult
    public mutating func cancelSubscription(_ id: UUID, on date: LocalDate = .today, author: String) throws -> ChangeRecord {
        guard let s = subscriptions.first(where: { $0.id == id }) else { throw SubscriptionError.unknownSubscription(id.uuidString) }
        guard s.isActive else { throw SubscriptionError.alreadyCancelled(s.name) }
        var u = s
        u.cancelledOn = date
        return try editSubscription(u, author: author)
    }

    /// 删掉订阅（登记错了）。能撤销。
    @discardableResult
    public mutating func removeSubscription(_ id: UUID, author: String) throws -> ChangeRecord {
        guard let i = subscriptions.firstIndex(where: { $0.id == id }) else { throw SubscriptionError.unknownSubscription(id.uuidString) }
        let old = subscriptions.remove(at: i)
        var snapshot = PlanSnapshot()
        snapshot.subscriptions = [old]
        let change = snapshotChange(.subscription, "删掉订阅「\(old.name)」", before: snapshot, author: author)
        changes.append(change)
        return change
    }
}
