import Foundation

// 预测卡（ming 2026-11-25，替换原来的「趋势」图表）：一个大数字 + 一句大白话，不画图。
// 全在本机用简单的算术算，不靠 AI。
//
// 生活这边三张：月底大概花、下个月要付、钱还能撑几个月。
// 生意这边三张：这个月大概收（已收 + 估的）、下个月店里要付、月底账户大概剩。
// 数据不到一个月就不出卡（返回 nil）。
//
// 怎么算：
// - 月底大概花 = 这个月已经花的 + 这个月还没到日子的固定开销 + 每天平均 × 剩下的天数。
// - 每天平均 = 最近 3 个月的花销 − 固定开销 − 一次性开销，除以天数。
// - 生意估收入 = 过去 4 周每个星期几的平均，加到这个月剩下的每一天上。
// - 下个月要付 = 固定的（订阅、房租这类重复记账、分期、欠款计划、认出来的固定开销）+ 每月都有但金额会变的（按 3 个月平均），分两块列。
// - 钱还能撑 = 现在的钱 ÷ 平均每月花多少。
//
// 认固定开销：同一个账户、同一个分类，连续 3 个月每月正好一次、金额差不多。认出来的问用户一次「算不算」，
//   说「算」就加进固定开销（重复记账），说「不算」记在 profile.notFixed，以后不再问。固定开销列表说了算。
// 认一次性开销：AI 记的 / 导入时 AI 标过的（profile.oneOff）说了算；没标过的按规则：
//   这个分类以前有 3 笔以上的，比平常一笔多 3 倍算一次性；不够 3 笔的，超过平均每月花销的 10%、又不是固定的，算一次性。
//   手记的没人标过的进一个看不见的「待复核」，AI 下次运行时自己悄悄标，不问用户；记一笔页面上也没有「一次性」选项。

public enum Outlook {
    /// 要付的一样。
    public struct Line: Identifiable, Equatable, Sendable {
        public enum Kind: String, Sendable { case subscription, recurring, installment, debt, detected, variable }
        public var name: String
        public var amount: Money
        public var date: LocalDate?
        public var kind: Kind
        public var id: String { "\(kind.rawValue)|\(name)|\(date?.description ?? "")" }
        public init(name: String, amount: Money, date: LocalDate? = nil, kind: Kind) {
            self.name = name; self.amount = amount; self.date = date; self.kind = kind
        }
    }

    /// 下个月要付：固定的一块、每月都有但金额会变的一块。
    public struct Due: Equatable, Sendable {
        public var month: YearMonth
        public var fixed: [Line]
        public var variable: [Line]
        public var fixedTotal: Money { fixed.reduce(.zero) { $0 + $1.amount } }
        public var variableTotal: Money { variable.reduce(.zero) { $0 + $1.amount } }
        public var total: Money { fixedTotal + variableTotal }
        public var isEmpty: Bool { fixed.isEmpty && variable.isEmpty }
    }

    /// 认出来、还没问过用户的固定开销。
    public struct FixedGuess: Identifiable, Equatable, Sendable {
        /// 「账户|分类」。
        public var key: String
        public var accountID: String
        public var category: String
        /// 最近一笔的名称。
        public var name: String
        /// 最近一笔多少（正数）。
        public var amount: Money
        /// 每月几号。
        public var day: Int
        public var bookID: String?
        public var id: String { key }
    }

    public struct Life: Equatable, Sendable {
        public var today: LocalDate
        public var spentSoFar: Money
        /// 这个月还没到日子的固定开销。
        public var fixedLeft: Money
        public var dailyAverage: Money
        public var daysLeft: Int
        /// 月底大概花。
        public var monthEnd: Money
        public var next: Due
        /// 平均每月花多少（不算一次性的）。
        public var monthlySpend: Money
        /// 现在的钱 ÷ 每月花多少；每月花销是 0 时是 nil。
        public var runway: Double?
        public var balance: Money
    }

    public struct Business: Equatable, Sendable {
        public var today: LocalDate
        /// 这个月已经收了。
        public var received: Money
        /// 剩下的日子估还能收。
        public var estimateRest: Money
        public var monthIncome: Money { received + estimateRest }
        public var next: Due
        /// 店里账户现在一共。
        public var balance: Money
        /// 剩下的日子还要花（固定的 + 每天平均）。
        public var spendRest: Money
        public var endBalance: Money { balance + estimateRest - spendRest }
        /// 估收入用了几周（满 4 周才估）。
        public var weeks: Int
    }

    // MARK: - 共用

    /// 算的时候拿哪些流水：这一边、普通收支（不含转账、借还款、存目标、期初）。
    static func plain(_ ledger: Ledger, side: Side, hiddenAccounts: Set<String>) -> [Transaction] {
        ledger.transactions.filter {
            $0.flow == nil && $0.transferID == nil && !hiddenAccounts.contains($0.accountID) && ledger.side(of: $0) == side
        }
    }

    static func key(_ t: Transaction) -> String? {
        guard let c = t.category, !c.isEmpty else { return nil }
        return "\(t.accountID)|\(c)"
    }

    static func monthEnd(_ ym: YearMonth) -> LocalDate { LocalDate(year: ym.year, month: ym.month, day: LocalDate.daysIn(ym)) }
    static func monthStart(_ ym: YearMonth) -> LocalDate { LocalDate(year: ym.year, month: ym.month, day: 1) }

    /// 数据够不够一个月：这一边最早一笔在 30 天以前。
    static func enoughData(_ txs: [Transaction], today: LocalDate) -> Bool {
        guard let first = txs.map(\.date).min() else { return false }
        return first.days(until: today) >= 30
    }

    /// 算平均用的那段日子：最近 3 个过完的月（从有数据那天起）；不到 4 周就用最近 30 天。
    static func window(_ txs: [Transaction], today: LocalDate) -> (from: LocalDate, to: LocalDate) {
        let first = txs.map(\.date).min() ?? today
        let lastMonth = today.yearMonth.adding(months: -1)
        let to = monthEnd(lastMonth)
        let from = max(monthStart(lastMonth.adding(months: -2)), first)
        if from.days(until: to) + 1 >= 28 { return (from, to) }
        return (today.adding(days: -30), today.adding(days: -1))
    }

    /// 固定开销规则已经管着的「账户|分类」：重复记账、订阅。
    static func coveredKeys(_ ledger: Ledger) -> Set<String> {
        var out: Set<String> = []
        for r in ledger.recurring where !r.paused && r.template.amount.cents < 0 {
            if let k = key(r.template) { out.insert(k) }
        }
        for s in ledger.subscriptions where s.isActive {
            if let a = s.accountID, let c = s.category { out.insert("\(a)|\(c)") }
        }
        return out
    }

    // MARK: - 认固定开销

    /// 同一个账户、同一个分类，连续 3 个过完的月每月正好一次、金额差不多（最多差 15%）。
    /// 已经在固定开销 / 订阅里的、用户说过「不算」的不列。
    public static func fixedGuesses(_ ledger: Ledger, side: Side, today: LocalDate = .today,
                                    hiddenAccounts: Set<String> = []) -> [FixedGuess] {
        let txs = plain(ledger, side: side, hiddenAccounts: hiddenAccounts).filter { $0.amount.cents < 0 }
        let months = (1...3).map { today.yearMonth.adding(months: -$0) }
        let skip = coveredKeys(ledger).union(ledger.profile.notFixed ?? [])
        var byKey: [String: [Transaction]] = [:]
        for t in txs where t.date >= monthStart(months[2]) && t.date <= today {
            if let k = key(t), !skip.contains(k) { byKey[k, default: []].append(t) }
        }
        var out: [FixedGuess] = []
        for (k, list) in byKey {
            let perMonth = Dictionary(grouping: list, by: { $0.date.yearMonth })
            guard months.allSatisfy({ perMonth[$0]?.count == 1 }) else { continue }
            // 这个月已经有两笔以上就不像每月一次了。
            guard (perMonth[today.yearMonth]?.count ?? 0) <= 1 else { continue }
            let amounts = months.compactMap { perMonth[$0]?.first.map { ledger.baseAmount($0).magnitude.cents } }
            guard let lo = amounts.min(), let hi = amounts.max(), lo > 0, hi * 100 <= lo * 115 else { continue }
            let last = list.max { $0.date < $1.date }!
            out.append(FixedGuess(key: k, accountID: last.accountID, category: last.category ?? "",
                                  name: last.description, amount: ledger.baseAmount(last).magnitude,
                                  day: last.date.day, bookID: last.bookID))
        }
        return out.sorted { $0.amount == $1.amount ? $0.key < $1.key : $0.amount > $1.amount }
    }

    // MARK: - 一次性开销

    /// 这笔算不算一次性：AI 标过的说了算，没标过的按规则。
    /// history 是同一边、算平均那段日子里的支出；monthly 是平均每月花多少（正数）；fixed 是固定开销的「账户|分类」。
    static func isOneOff(_ t: Transaction, ledger: Ledger, history: [Transaction], monthly: Int64, fixed: Set<String>) -> Bool {
        if let mark = ledger.profile.oneOff?[t.id.uuidString] { return mark }
        return ruleOneOff(t, ledger: ledger, history: history, monthly: monthly, fixed: fixed)
    }

    static func ruleOneOff(_ t: Transaction, ledger: Ledger, history: [Transaction], monthly: Int64, fixed: Set<String>) -> Bool {
        guard t.amount.cents < 0 else { return false }
        if let k = key(t), fixed.contains(k) { return false }
        if t.source == "重复记账" { return false }
        let amount = ledger.baseAmount(t).magnitude.cents
        let same = history.filter { $0.id != t.id && $0.category != nil && $0.category == t.category && $0.date < t.date }
        if same.count >= 3 {
            let sorted = same.map { ledger.baseAmount($0).magnitude.cents }.sorted()
            let usual = sorted[sorted.count / 2]
            return usual > 0 && amount > usual * 3
        }
        return monthly > 0 && amount * 10 > monthly
    }

    /// 算平均用的：那段日子里每月平均花多少（全部），给 10% 规则用。
    static func rawMonthly(_ spend: [Transaction], ledger: Ledger, days: Int) -> Int64 {
        let total = spend.reduce(Int64(0)) { $0 + ledger.baseAmount($1).magnitude.cents }
        return days > 0 ? total * 3044 / Int64(days) / 100 : 0
    }

    /// 待复核：最近 60 天手记的支出（app 里自己记的、手机随手记的），AI 还没标过一次性不一次性的。
    /// AI 下次运行时自己悄悄看一遍、标上（mark_one_off），不问用户。guess 是规则的猜测，给 AI 参考。
    public static func reviewQueue(_ ledger: Ledger, today: LocalDate = .today, limit: Int = 50) -> [(tx: Transaction, guess: Bool)] {
        let marks = ledger.profile.oneOff ?? [:]
        let since = today.adding(days: -60)
        var out: [(tx: Transaction, guess: Bool)] = []
        for side in [Side.life, .business] {
            let all = plain(ledger, side: side, hiddenAccounts: [])
            let spend = all.filter { $0.amount.cents < 0 }
            let w = window(all, today: today)
            let hist = spend.filter { $0.date >= w.from && $0.date <= w.to }
            let monthly = rawMonthly(hist, ledger: ledger, days: w.from.days(until: w.to) + 1)
            let fixed = coveredKeys(ledger).union(fixedGuesses(ledger, side: side, today: today).map(\.key))
            // 手记的、导入时没标的、AI 记账时忘了标的，都在这里（重复记账是固定开销，不用标）。
            for t in spend where t.date >= since && marks[t.id.uuidString] == nil && t.source != "重复记账" {
                out.append((t, ruleOneOff(t, ledger: ledger, history: spend, monthly: monthly, fixed: fixed)))
            }
        }
        return Array(out.sorted { $0.tx.date > $1.tx.date }.prefix(limit))
    }

    // MARK: - 要付的

    /// from...to 之间这一边要付的固定开销：重复记账、订阅、分期、欠款计划。
    static func scheduled(_ ledger: Ledger, side: Side, from: LocalDate, to: LocalDate, today: LocalDate) -> [Line] {
        func onSide(_ book: String?) -> Bool {
            guard let shop = ledger.businessBook?.id else { return side == .life }
            return (book == shop) == (side == .business)
        }
        var out: [Line] = []
        for r in ledger.recurring where !r.paused && r.template.amount.cents < 0 && onSide(r.template.bookID) {
            var k = r.count
            while k < r.count + 400 {
                let d = r.date(after: k)
                if d > to { break }
                if let u = r.until, d > u { break }
                if d >= from { out.append(Line(name: r.template.description, amount: ledger.baseAmount(r.template).magnitude, date: d, kind: .recurring)) }
                k += 1
            }
        }
        for s in ledger.subscriptions where s.isActive && onSide(s.bookID) {
            let code = s.currency ?? s.accountID.map { ledger.currency(ofAccount: $0) } ?? ledger.baseCurrency
            var d = s.nextDate
            var n = 0
            while d <= today && n < 2000 { n += 1; d = s.cycle.advance(s.nextDate, by: n) }
            while d <= to && n < 2400 {
                if d >= from { out.append(Line(name: s.name, amount: ledger.toBase(s.amount, currency: code, on: today), date: d, kind: .subscription)) }
                n += 1; d = s.cycle.advance(s.nextDate, by: n)
            }
        }
        for i in ledger.installments where onSide(i.bookID) {
            for k in i.paidIDs.count..<max(i.count, i.paidIDs.count) {
                let d = i.firstDate.adding(months: k)
                if d > to { break }
                guard d >= from else { continue }
                let amount = k == i.count - 1 ? Money(cents: i.total.cents - i.perPayment.cents * Int64(i.count - 1)) : i.perPayment
                out.append(Line(name: i.name, amount: amount, date: d, kind: .installment))
            }
        }
        for debt in ledger.debts where !debt.closed && debt.direction == .iOweThem && onSide(debt.bookID) {
            guard let plan = debt.plan, let p = ledger.planProgress(debt.id, today: today), let cur = p.currentIndex else { continue }
            for idx in cur..<plan.count {
                if plan[idx].date > to { break }
                // 过期没还的算在这个月剩下的日子里要付（只算一次，不挪到下个月）。
                let overdue = plan[idx].date <= today
                let d = overdue ? from : plan[idx].date
                if overdue && from > today.adding(days: 1) { continue }
                guard d >= from, d <= to else { continue }
                out.append(Line(name: debt.counterparty, amount: idx == cur ? p.nextAmount : plan[idx].amount, date: d, kind: .debt))
            }
        }
        return out.sorted { ($0.date ?? to, $0.name) < ($1.date ?? to, $1.name) }
    }

    /// 认出来的固定开销里，from...to 要付的（按它每月几号）。这个月已经付过的不算。
    static func guessed(_ guesses: [FixedGuess], from: LocalDate, to: LocalDate, paidThisMonth: Set<String>) -> [Line] {
        var out: [Line] = []
        var ym = from.yearMonth
        while monthStart(ym) <= to {
            for g in guesses {
                let d = LocalDate(year: ym.year, month: ym.month, day: min(g.day, LocalDate.daysIn(ym)))
                guard d >= from, d <= to else { continue }
                if ym == from.yearMonth && paidThisMonth.contains(g.key) { continue }
                out.append(Line(name: g.name, amount: g.amount, date: d, kind: .detected))
            }
            ym = ym.adding(months: 1)
        }
        return out
    }

    /// 平时的花销（去掉固定的、一次性的）：每天平均多少；还有每月都有、金额会变的那几类（按月平均）。
    struct Usual {
        var daily: Int64
        var monthly: Int64
        var variable: [Line]
        var fixedMonthly: Int64
    }

    static func usual(_ ledger: Ledger, all: [Transaction], today: LocalDate, guesses: [FixedGuess]) -> Usual {
        let spend = all.filter { $0.amount.cents < 0 }
        let w = window(all, today: today)
        let days = max(1, w.from.days(until: w.to) + 1)
        let hist = spend.filter { $0.date >= w.from && $0.date <= w.to }
        let fixedKeys = coveredKeys(ledger).union(guesses.map(\.key))
        let raw = rawMonthly(hist, ledger: ledger, days: days)
        var normal: Int64 = 0
        var fixed: Int64 = 0
        var byCat: [String: Int64] = [:]
        var monthsByCat: [String: Set<YearMonth>] = [:]
        for t in hist {
            let c = ledger.baseAmount(t).magnitude.cents
            if (key(t).map(fixedKeys.contains) ?? false) || t.source == "重复记账" { fixed += c; continue }
            if isOneOff(t, ledger: ledger, history: spend, monthly: raw, fixed: fixedKeys) { continue }
            normal += c
            let cat = t.category ?? "其他"
            byCat[cat, default: 0] += c
            monthsByCat[cat, default: []].insert(t.date.yearMonth)
        }
        let monthsInWindow = Set(hist.map(\.date.yearMonth)).count
        var variable: [Line] = []
        for (cat, total) in byCat where monthsInWindow >= 2 && (monthsByCat[cat]?.count ?? 0) >= monthsInWindow {
            let m = total * 3044 / Int64(days) / 100
            if m >= 100 { variable.append(Line(name: cat, amount: Money(cents: m), kind: .variable)) }
        }
        variable.sort { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
        return Usual(daily: normal / Int64(days), monthly: normal * 3044 / Int64(days) / 100,
                     variable: variable, fixedMonthly: fixed * 3044 / Int64(days) / 100)
    }

    static func due(_ ledger: Ledger, side: Side, today: LocalDate, guesses: [FixedGuess], usual: Usual) -> Due {
        let next = today.yearMonth.adding(months: 1)
        let from = monthStart(next), to = monthEnd(next)
        let fixed = (scheduled(ledger, side: side, from: from, to: to, today: today)
                     + guessed(guesses, from: from, to: to, paidThisMonth: []))
            .sorted { ($0.date ?? to, $0.name) < ($1.date ?? to, $1.name) }
        return Due(month: next, fixed: fixed, variable: usual.variable)
    }

    // MARK: - 生活

    /// balance：现在能用的钱（家底页「现在能随便花」）。数据不到一个月返回 nil。
    public static func life(_ ledger: Ledger, balance: Money, today: LocalDate = .today,
                            hiddenAccounts: Set<String> = []) -> Life? {
        let all = plain(ledger, side: .life, hiddenAccounts: hiddenAccounts)
        guard enoughData(all, today: today) else { return nil }
        let guesses = fixedGuesses(ledger, side: .life, today: today, hiddenAccounts: hiddenAccounts)
        let u = usual(ledger, all: all, today: today, guesses: guesses)
        let thisMonth = all.filter { $0.date.yearMonth == today.yearMonth && $0.date <= today }
        let spent = thisMonth.filter { $0.amount.cents < 0 }.reduce(Int64(0)) { $0 + ledger.baseAmount($1).magnitude.cents }
        let paid = Set(thisMonth.compactMap(key))
        let end = monthEnd(today.yearMonth)
        let tomorrow = today.adding(days: 1)
        let fixedLeft = (scheduled(ledger, side: .life, from: tomorrow, to: end, today: today)
                         + guessed(guesses, from: tomorrow, to: end, paidThisMonth: paid)).reduce(Int64(0)) { $0 + $1.amount.cents }
        let daysLeft = max(0, end.day - today.day)
        let monthly = u.monthly + u.fixedMonthly
        return Life(today: today, spentSoFar: Money(cents: spent), fixedLeft: Money(cents: fixedLeft),
                    dailyAverage: Money(cents: u.daily), daysLeft: daysLeft,
                    monthEnd: Money(cents: spent + fixedLeft + u.daily * Int64(daysLeft)),
                    next: due(ledger, side: .life, today: today, guesses: guesses, usual: u),
                    monthlySpend: Money(cents: monthly),
                    runway: monthly > 0 ? Double(balance.cents) / Double(monthly) : nil, balance: balance)
    }

    // MARK: - 生意

    /// balance：店里账户现在一共多少。店里的账不到 4 周返回 nil。
    public static func business(_ ledger: Ledger, balance: Money, today: LocalDate = .today,
                                hiddenAccounts: Set<String> = []) -> Business? {
        guard ledger.businessBook != nil else { return nil }
        let all = plain(ledger, side: .business, hiddenAccounts: hiddenAccounts)
        guard enoughData(all, today: today) else { return nil }
        let guesses = fixedGuesses(ledger, side: .business, today: today, hiddenAccounts: hiddenAccounts)
        let u = usual(ledger, all: all, today: today, guesses: guesses)
        let income = all.filter { $0.amount.cents > 0 }
        let thisMonth = all.filter { $0.date.yearMonth == today.yearMonth && $0.date <= today }
        let received = thisMonth.filter { $0.amount.cents > 0 }.reduce(Int64(0)) { $0 + ledger.baseAmount($1).cents }

        // 过去 4 周（不含今天）每个星期几平均收多少。
        let from = today.adding(days: -28)
        var byWeekday = [Int64](repeating: 0, count: 7)
        for t in income where t.date >= from && t.date < today { byWeekday[t.date.weekdayIndex] += ledger.baseAmount(t).cents }
        let avg = byWeekday.map { $0 / 4 }
        let end = monthEnd(today.yearMonth)
        // 今天还没记收入的，今天也按平均估上。
        let start = income.contains { $0.date == today } ? today.adding(days: 1) : today
        var rest: Int64 = 0
        var d = start
        while d <= end { rest += avg[d.weekdayIndex]; d = d.adding(days: 1) }

        let tomorrow = today.adding(days: 1)
        let paid = Set(thisMonth.compactMap(key))
        let fixedLeft = (scheduled(ledger, side: .business, from: tomorrow, to: end, today: today)
                         + guessed(guesses, from: tomorrow, to: end, paidThisMonth: paid)).reduce(Int64(0)) { $0 + $1.amount.cents }
        let daysLeft = max(0, end.day - today.day)
        return Business(today: today, received: Money(cents: received), estimateRest: Money(cents: rest),
                        next: due(ledger, side: .business, today: today, guesses: guesses, usual: u),
                        balance: balance, spendRest: Money(cents: fixedLeft + u.daily * Int64(daysLeft)), weeks: 4)
    }
}

// MARK: - 写：认出来的固定开销「算 / 不算」，一次性标记

extension Ledger {
    /// 用户说认出来的这个「不算固定开销」：以后不再问。能撤销。
    @discardableResult
    public mutating func markNotFixed(_ key: String, name: String, author: String) -> ChangeRecord {
        let old = profile
        var list = profile.notFixed ?? []
        if !list.contains(key) { list.append(key) }
        profile.notFixed = list
        return appendProfileChange("「\(name)」不算固定开销", before: old, author: author)
    }

    /// AI 标一次性 / 不是一次性（导入、聊天记账时，或者悄悄处理待复核时）。能撤销。
    @discardableResult
    public mutating func markOneOff(_ ids: [UUID], oneOff: Bool, author: String) throws -> ChangeRecord {
        let known = Set(transactions.map(\.id))
        let list = ids.filter(known.contains)
        guard !list.isEmpty else { throw ManageError.nothingToChange }
        let old = profile
        var marks = profile.oneOff ?? [:]
        for id in list { marks[id.uuidString] = oneOff }
        profile.oneOff = marks
        return appendProfileChange("\(list.count) 笔标成\(oneOff ? "一次性开销" : "平时的开销")", before: old, author: author)
    }
}
