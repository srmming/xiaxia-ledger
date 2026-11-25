import Foundation

// 生意模式：每天记账、首页夏夏卡。规则只写在这里，app 和 fin 都调用它。

/// 一天的收入：现金一个框、刷卡/转账一个框。
public struct DailyTakings: Equatable, Sendable {
    public var cash: Money
    public var card: Money
    public init(cash: Money, card: Money) { self.cash = cash; self.card = card }
    public var total: Money { cash + card }
}

extension Ledger {
    /// 店里的账户：只在生意账本里用的那些（见 WealthBreakdown.businessAccounts），私房钱不算。
    public var businessAccountIDs: [String] {
        let set = WealthBreakdown.businessAccounts(self)
        return accounts.filter { set.contains($0.id) && !$0.isPrivate }.map(\.id)
    }

    /// 每天记账默认记到哪：现金进店里的现金账户，刷卡进店里的银行卡。找不到就留空，让人自己选。
    public func dailyAccounts() -> (cash: String?, card: String?) {
        let shop = businessAccountIDs.compactMap { id in accounts.first { $0.id == id } }
        let cash = shop.first { $0.kind == .cash }?.id
        let card = shop.first { $0.kind == .bank || $0.kind == .wallet }?.id ?? shop.first { $0.kind != .cash && $0.kind != .credit }?.id
        return (cash, card)
    }

    /// 那天已经记过的营业收入（每天记账那屏用来显示「已经记了」）。
    public func dailyTakings(on date: LocalDate) -> DailyTakings {
        guard let book = businessBook?.id else { return DailyTakings(cash: .zero, card: .zero) }
        var cash = Money.zero, card = Money.zero
        for t in transactions where t.bookID == book && t.date == date && t.source == Self.dailySource && t.amount > .zero {
            if accounts.first(where: { $0.id == t.accountID })?.kind == .cash { cash = cash + t.amount } else { card = card + t.amount }
        }
        return DailyTakings(cash: cash, card: card)
    }

    static let dailySource = "每天记账"

    /// 记一天的收入：现金、刷卡各一笔营业收入，记在生意账本上；0 的那格不记。一条改动记录，一起撤销。
    /// 同一天再记一次是「又收了」：接着加，不覆盖前面记的（记错了在流水里改，或撤销这一次）。
    @discardableResult
    public mutating func recordDailyTakings(_ takings: DailyTakings, date: LocalDate, cashAccount: String?, cardAccount: String?,
                                            author: String) throws -> ChangeRecord {
        guard let book = businessBook?.id else { throw BusinessError(message: "请先打开生意模式") }
        guard takings.cash >= .zero, takings.card >= .zero, takings.total > .zero else { throw EditError.amountMustBePositive }
        var fresh: [Transaction] = []
        if takings.cash > .zero {
            guard let cashAccount else { throw BusinessError(message: "选一下现金记到哪个账户") }
            try requireAccount(cashAccount)
            fresh.append(Transaction(date: date, amount: takings.cash, description: "现金收入", accountID: cashAccount, bookID: book,
                                     category: "营业收入", source: Self.dailySource))
        }
        if takings.card > .zero {
            guard let cardAccount else { throw BusinessError(message: "选一下刷卡记到哪个账户") }
            try requireAccount(cardAccount)
            fresh.append(Transaction(date: date, amount: takings.card, description: "刷卡收入", accountID: cardAccount, bookID: book,
                                     category: "营业收入", source: Self.dailySource))
        }
        transactions += fresh
        return record(.add, "记 \(date) 的收入 \(takings.total.formatted)", ids: fresh.map(\.id), author: author)
    }
}

extension Nudges {
    /// 生意首页最上面的夏夏卡：这个月赚得怎么样、回本到哪了、给自己发了多少。不说交税、不催房租（ming 2026-11-25 不要）。
    public static func business(_ r: BusinessReport, progress: CapitalProgress?, month: YearMonth, today: LocalDate,
                                currency: String) -> [Nudge] {
        func m(_ x: Money) -> String { short(x, currency) }
        let current = today.yearMonth == month
        let than = current ? "上月同期" : "上个月"
        var out: [Nudge] = []
        if r.profit < .zero {
            let top = r.topCosts.first
            out.append(Nudge(kind: .unusual, key: "biz-loss-\(month)",
                             title: "\(month.month) 月到现在亏了 \(m(r.profit.magnitude))。",
                             advice: top.map { "花得最多的是「\($0.category)」\(m($0.amount))，先看看这一项能不能省。" } ?? "先把这个月的进账记全，再看哪里花多了。",
                             question: "我店里这个月为什么亏钱？哪里能省？"))
        } else if r.changeFromPrevious > .zero {
            out.append(Nudge(kind: .praise, key: "biz-up-\(month)",
                             title: "比\(than)多赚了 \(m(r.changeFromPrevious))。",
                             advice: "\(month.month) 月到现在真正赚了 \(m(r.profit))，房租、工资这些都已经扣掉了。",
                             question: "我店里这个月为什么赚得比上个月多？能保持吗？"))
        } else if r.changeFromPrevious < .zero {
            let top = r.topCosts.first
            out.append(Nudge(kind: .info, key: "biz-down-\(month)",
                             title: "比\(than)少赚了 \(m(r.changeFromPrevious.magnitude))。",
                             advice: top.map { "这个月花得最多的是「\($0.category)」\(m($0.amount))。" } ?? "进账比上个月少一些。",
                             question: "我店里这个月为什么赚得比上个月少？"))
        }
        if let p = progress {
            switch p.estimate {
            case .done:
                out.append(Nudge(kind: .praise, key: "biz-payback-done", title: "开店的本钱已经全赚回来了。",
                                 advice: "以后赚的都是净赚。", question: "回本以后，店里的钱该怎么安排？"))
            case .months(let n):
                out.append(Nudge(kind: .goal, key: "biz-payback",
                                 title: "回本到 \(Int((p.fraction * 100).rounded()))% 了。",
                                 advice: "还差 \(m(p.remaining))，照最近 3 个月的速度，大约还要 \(n) 个月。",
                                 question: "我的店还要多久回本？怎么能快一点？"))
            default: break
            }
        }
        if r.takenHome > .zero {
            out.append(Nudge(kind: .info, key: "biz-home-\(month)",
                             title: "这个月给自己发了 \(m(r.takenHome))。",
                             advice: "从店里拿回家的钱，不算店里的开销。",
                             question: "我每个月从店里拿多少回家比较合适？"))
        }
        if out.isEmpty {
            out.append(Nudge(kind: .info, key: "biz-start-\(month)",
                             title: r.income == .zero ? "这个月还没记进账。" : "\(month.month) 月到现在赚了 \(m(r.profit))。",
                             advice: r.income == .zero ? "每天关店后点「记今天的账」，现金和刷卡各填一个数就行。" : "每天记一下，月底就知道真正赚了多少。",
                             question: "我的店这个月怎么样？"))
        }
        return out
    }
}

// MARK: - 账户分两边、两边转钱

extension Ledger {
    /// 这个账户算哪一边。没开生意模式时都算生活。
    public func side(ofAccount id: String) -> Side {
        guard businessBook != nil else { return .life }
        return WealthBreakdown.businessAccounts(self).contains(id) ? .business : .life
    }

    /// 把账户挪到另一边（或者新加账户时说好算哪边）。只改账户归哪边，流水不动。能撤销。
    @discardableResult
    public mutating func setAccountSide(_ accountID: String, side: Side, author: String) throws -> ChangeRecord {
        guard var settings = business, businessBook != nil else { throw BusinessError(message: "请先打开生意模式") }
        try requireAccount(accountID)
        var sides = settings.accountSides ?? [:]
        sides[accountID] = side
        settings.accountSides = sides
        let name = accounts.first { $0.id == accountID }?.name ?? accountID
        return changeBusinessSettings(settings, summary: "账户「\(name)」算到\(side == .business ? "生意" : "生活")那边", author: author)
    }

    /// 两边之间转钱：从一边的账户转到另一边的账户。记两笔（同一个 transferID），不算收入也不算开销；
    /// 从生意转到生活就是「给自己发了」，首页那一行会加上。
    @discardableResult
    public mutating func transferBetweenSides(amount: Money, from: String, to: String, date: LocalDate, note: String? = nil,
                                              author: String) throws -> ChangeRecord {
        guard amount > .zero else { throw EditError.amountMustBePositive }
        guard let shop = businessBook?.id else { throw BusinessError(message: "请先打开生意模式") }
        try requireAccount(from); try requireAccount(to)
        let fromSide = side(ofAccount: from), toSide = side(ofAccount: to)
        guard fromSide != toSide else { throw BusinessError(message: "两个账户在同一边，这是普通的账户间转账") }
        guard let life = bookID(for: .life) else { throw BusinessError(message: "还没有生活账本") }
        let fromName = accounts.first { $0.id == from }?.name ?? from
        let toName = accounts.first { $0.id == to }?.name ?? to
        let home = fromSide == .business
        let text = (note?.isEmpty == false ? note! : (home ? "从店里拿钱回家" : "自己的钱垫给店里"))
        let tid = UUID()
        let outTx = Transaction(date: date, amount: -amount, description: text, accountID: from, bookID: home ? shop : life,
                                category: home ? "老板提款" : "转出", transferID: tid, source: "手记")
        let inTx = Transaction(date: date, amount: amount, description: text, accountID: to, bookID: home ? life : shop,
                               category: "转入", transferID: tid, source: "手记")
        transactions += [outTx, inTx]
        return record(.transfer, "两边转钱：\(fromName) → \(toName) \(amount.formatted)", ids: [outTx.id, inTx.id], author: author)
    }

    /// 这个月两边之间来回的钱（家底页生意那边列出来）。每次转账只取生意那边的那一笔：负数 = 拿回家，正数 = 垫给店里。
    public func sideTransfers(month: YearMonth) -> [Transaction] {
        guard let shop = businessBook?.id else { return [] }
        let life = Set(lifeBookIDs)
        let lifeIDs = Set(transactions.filter { life.contains($0.bookID ?? "") }.compactMap(\.transferID))
        return transactions.filter { $0.bookID == shop && $0.date.yearMonth == month && $0.transferID.map(lifeIDs.contains) == true }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - 固定开销

extension Ledger {
    /// 店里的固定开销：生意账本上、每月自动记的开销（房租、工资……）。
    public var businessFixedCosts: [Recurring] {
        guard let shop = businessBook?.id else { return [] }
        return recurring.filter { $0.template.bookID == shop && $0.template.amount < .zero }
            .sorted { ($0.start.day, $0.template.description) < ($1.start.day, $1.template.description) }
    }

    /// 加一项固定开销：每月 day 号从 accountID 付 amount。不马上记一笔：从下一个 day 号起，到日子自动记上。能撤销。
    @discardableResult
    public mutating func addFixedCost(name: String, amount: Money, day: Int, accountID: String, category: String,
                                      today: LocalDate = .today, author: String) throws -> ChangeRecord {
        guard let shop = businessBook?.id else { throw BusinessError(message: "请先打开生意模式") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ManageError.emptyName }
        guard amount > .zero else { throw EditError.amountMustBePositive }
        guard (1...31).contains(day) else { throw BusinessError(message: "几号要在 1 到 31 之间") }
        try requireAccount(accountID)
        func on(_ ym: YearMonth) -> LocalDate {
            let last = LocalDate(year: ym.year, month: ym.month, day: 1).adding(months: 1).adding(days: -1).day
            return LocalDate(year: ym.year, month: ym.month, day: min(day, last))
        }
        var start = on(today.yearMonth)
        if start <= today { start = on(today.yearMonth.adding(months: 1)) }
        let template = Transaction(date: start, amount: -amount, description: trimmed, accountID: accountID, bookID: shop,
                                   category: category, source: "重复记账")
        var rule = Recurring(template: template, frequency: .monthly, start: start)
        rule.count = 0
        rule.nextDate = start
        recurring.append(rule)
        var snap = PlanSnapshot()
        snap.addedRecurringIDs = [rule.id]
        let change = snapshotChange(.add, "加固定开销：每月 \(day) 号 \(trimmed) \(amount.formatted)", ids: [], before: snap, author: author)
        changes.append(change)
        return change
    }
}
