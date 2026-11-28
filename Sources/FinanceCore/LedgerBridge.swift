import Foundation

/// 把正式账本（`Ledger`）的数整理成 v3 界面要的样子。
/// 第 1 步：只读。界面照旧读 `TrialBook` 的形状，这里从正式账本现算一份出来；一个字都不往正式账本里写。
/// 口径尽量用正式账本已有的算法（`Summaries`、`Outlook`、`Plans`、`Subscriptions`、`WealthBreakdown`），这里只是换个摆法。
public enum LedgerBridge {
    /// 分类的图标：按名字找，找不到给一张小票。
    static func emoji(_ category: String?) -> String {
        guard let category else { return "❓" }
        let known: [String: String] = ["超市": "🛒", "餐饮": "🥗", "咖啡": "☕", "交通": "🚇", "房租": "🏠", "订阅": "🔁", "看病": "💊", "医疗": "💊", "娱乐": "🎬",
                                       "衣服": "👕", "购物": "👕", "话费": "📱", "送礼": "🎁", "水电": "💡", "工资": "💼", "进货": "📦", "未分类": "❓"]
        return known[category] ?? known.first { category.contains($0.key) }?.value ?? "🧾"
    }

    static func date(_ d: LocalDate) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 12)) ?? Date()
    }

    static func days(from a: LocalDate, to b: LocalDate) -> Int {
        Calendar(identifier: .gregorian).dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }

    static func daysInMonth(_ d: LocalDate) -> Int {
        Calendar(identifier: .gregorian).range(of: .day, in: .month, for: date(d))?.count ?? 30
    }

    /// 从正式账本现算一份界面用的账本。
    /// - showPrivate: 旧版标成私房钱的账户（isPrivate）要不要显示、算进合计。v3 去掉了私房钱，默认当普通账户显示、算进去（ming 2026-11-28 定）；
    ///   开关留着，传 false 就和旧界面一样藏起来。旧数据里的这个标记不删不改。
    public static func snapshot(of ledger: Ledger, today: LocalDate = .today, showPrivate: Bool = true) -> TrialBook {
        let hidden = showPrivate ? Set<String>() : Set(ledger.accounts.filter(\.isPrivate).map(\.id))
        let bizBooks = Set(ledger.books.filter(\.isBusiness).map(\.id))
        let bizAccounts = WealthBreakdown.businessAccounts(ledger)
        let goalAccounts = Set(ledger.goals.compactMap(\.savingsAccountID))
        // 每个账户的余额：每笔先换成主币种再加（外币账户也对）
        let balances: [String: Money] = ledger.transactions.reduce(into: [:]) { acc, t in acc[t.accountID, default: .zero] = acc[t.accountID, default: .zero] + ledger.baseAmount(t) }
        let names = Dictionary(ledger.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        // 账户：属于哪边用正式账本自己的判断（记在哪个账本的多，或者用户说过算哪边）
        var accounts: [TrialBook.Account] = ledger.accounts.filter { !hidden.contains($0.id) }.map { a in
            let bal = balances[a.id] ?? .zero
            let biz = bizAccounts.contains(a.id)
            let icon = a.kind == .cash ? "💶" : a.kind == .savings ? "🏦" : goalAccounts.contains(a.id) ? "⭐" : biz ? "🏪" : "💳"
            var out: TrialBook.Account
            if a.kind == .credit {
                // 信用卡：欠的是正数
                out = .init(emoji: "💳", name: a.name, note: a.institution ?? "", balance: bal < .zero ? bal.magnitude : .zero, kind: .debt, block: .none, side: biz ? .biz : .life)
            } else if biz {
                out = .init(emoji: icon, name: a.name, note: a.institution ?? "", balance: bal, kind: .shop, block: .shop)
            } else {
                let block: TrialBook.Account.Block = goalAccounts.contains(a.id) ? .goal : a.kind == .savings ? .emergency : .daily
                out = .init(emoji: icon, name: a.name, note: a.institution ?? "", balance: bal, kind: .own, block: block)
            }
            out.cardStyle = a.cardStyle
            return out
        }
        // 置顶成卡片的：按正式账本里记的先后
        let pinnedNames = ledger.accounts.filter { $0.cardPin != nil && !hidden.contains($0.id) }.sorted { ($0.cardPin ?? 0) < ($1.cardPin ?? 0) }.map(\.name)
        let pinIDs = pinnedNames.compactMap { n in accounts.first { $0.name == n } }
        // 借的钱和借出去的
        for d in Plans.debts(ledger, today: today) where d.outstanding > .zero {
            let lent = d.direction == .theyOweMe
            accounts.append(.init(emoji: lent ? "🧑" : "🤝", name: lent ? "借给\(d.counterparty)" : d.counterparty, note: lent ? "他欠我" : "欠的钱",
                                  balance: d.outstanding, kind: lent ? .lent : .debt, block: .none))
        }
        for i in Plans.installments(ledger) where i.remaining > .zero {
            accounts.append(.init(emoji: "🧾", name: i.name, note: "分期", balance: i.remaining, kind: .debt, block: .none))
        }

        // 流水：算进收支的那些；最近 90 天
        let plain = ledger.transactions.filter { $0.countsAsIncomeOrExpense && !hidden.contains($0.accountID) && $0.date <= today }
        func side(_ t: Transaction) -> TrialBook.Side { t.bookID.map { bizBooks.contains($0) } == true ? .biz : .life }
        let entries: [TrialBook.Entry] = plain.filter { days(from: $0.date, to: today) <= 90 }.sorted { $0.date > $1.date }.map { t in
            let acc = names[t.accountID] ?? t.accountID
            return .init(id: t.id, emoji: emoji(t.category), name: t.category ?? "还没分", meta: "\(t.description) · \(acc)", amount: ledger.baseAmount(t),
                         tag: t.source ?? "", daysAgo: days(from: t.date, to: today), side: side(t), place: t.description, account: acc, note: t.note ?? "")
        }

        // 这个月（生活）：进账、已经花的、还没到日子的固定开销、存进目标的
        let lifeTx = plain.filter { side($0) == .life }
        let spending = Summaries.expenseCategories(ledger.transactions)
        func month(_ ym: YearMonth, upTo: LocalDate?) -> (income: Money, expense: Money, by: [String: Money]) {
            var income = Money.zero, expense = Money.zero, by: [String: Money] = [:]
            for t in lifeTx where t.date.yearMonth == ym && !t.isTransfer && (upTo.map { t.date <= $0 } ?? true) {
                let amt = ledger.baseAmount(t)
                if Summaries.countsAsIncome(t, expenseCategories: spending) { income = income + amt } else {
                    expense = expense + amt
                    by[t.category ?? "未分类", default: .zero] = by[t.category ?? "未分类", default: .zero] + amt
                }
            }
            return (income, expense.magnitude, by.mapValues(\.magnitude))
        }
        let now = month(today.yearMonth, upTo: today)
        let last = month(today.yearMonth.adding(months: -1), upTo: nil)
        let guesses = Outlook.fixedGuesses(ledger, side: .life, today: today, hiddenAccounts: hidden)
        let fixedAll = guesses.map(\.amount.magnitude).reduce(.zero, +)
        let daily = accounts.filter { $0.side == .life && $0.kind == .own && $0.block == .daily }.map(\.balance).reduce(.zero, +)
        let outlook = Outlook.life(ledger, balance: daily, today: today, hiddenAccounts: hidden)
        let fixedLeft = outlook?.fixedLeft ?? .zero
        let fixedPaid = fixedAll > fixedLeft ? fixedAll - fixedLeft : .zero
        let saved = ledger.transactions.filter { $0.flow == .saving && $0.date.yearMonth == today.yearMonth && $0.amount < .zero && !hidden.contains($0.accountID) }
            .map { ledger.baseAmount($0).magnitude }.reduce(.zero, +)
        let daysLeft = max(daysInMonth(today) - today.day, 0)
        let free = FreeToSpend(income: now.income, fixed: fixedPaid + fixedLeft, forGoals: saved,
                               spent: now.expense > fixedPaid ? now.expense - fixedPaid : .zero, daysLeft: daysLeft)

        // 目标：钉住的（没有就第一个）当大目标，后面最多 3 个当小目标
        let statuses = Plans.goals(ledger)
        let ordered = ledger.goals.sorted { ($0.pinned ? 0 : 1, $0.rank ?? Int.max) < ($1.pinned ? 0 : 1, $1.rank ?? Int.max) }
        func status(_ g: Goal) -> GoalStatus? { statuses.first { $0.id == g.id } }
        var journey = Journey(name: "", stops: [])
        var bigAccount: UUID?
        if let g = ordered.first, let s = status(g), g.target > .zero {
            let stops = [10, 25, 50, 75, 100].map { Money(cents: max(g.target.cents * Int64($0) / 100 / 100 * 100, 100)) }
            journey = Journey(name: g.name, stops: Array(Set(stops)).sorted(), saved: s.saved)
            bigAccount = accounts.first { a in g.savingsAccountID.flatMap { names[$0] } == a.name }?.id
        }
        let small: [TrialBook.SmallGoal] = ordered.dropFirst().prefix(Plans.maxSmallGoals).compactMap { g in
            guard let s = status(g) else { return nil }
            var out = TrialBook.SmallGoal(id: g.id, name: g.name, target: g.target, saved: s.saved, due: g.deadline.map { "\($0.month) 月 \($0.day) 日前" } ?? "")
            out.account = accounts.first { a in g.savingsAccountID.flatMap { names[$0] } == a.name }?.id
            out.ownsAccount = false
            return out
        }

        var b = TrialBook(accounts: accounts, entries: entries, upcoming: [], month: free, journey: journey, monthlyMust: fixedAll)
        b.todayDay = today.day
        b.todayDate = date(today)
        b.lifePins = pinIDs.filter { $0.side == .life }.map(\.id)
        b.shopPins = pinIDs.filter { $0.side == .biz }.map(\.id)
        b.showLife = true
        b.showBiz = !bizBooks.isEmpty
        b.lifeName = ledger.books.first { !$0.isBusiness }?.name ?? "生活"
        b.shopName = ledger.books.first { $0.isBusiness }?.name ?? "店"
        b.smallGoals = small
        b.bigGoalAccount = bigAccount
        b.bigGoalOwnsAccount = false
        b.usualDailySpend = outlook?.dailyAverage ?? .zero
        b.spendByCategory = now.by.map { .init(emoji: emoji($0.key), name: $0.key, amount: $0.value, lastMonth: last.by[$0.key] ?? .zero) }.sorted { $0.amount > $1.amount }
        // 过去的月份：有流水的那些，最多往前 12 个月
        b.pastMonths = (1...12).compactMap { k in
            let ym = today.yearMonth.adding(months: -k)
            let m = month(ym, upTo: nil), before = month(ym.adding(months: -1), upTo: nil)
            guard m.income > .zero || m.expense > .zero else { return nil }
            let fixed = min(fixedAll, m.expense)
            return TrialBook.MonthData(key: .init(ym.year, ym.month), income: m.income, fixed: fixed, forGoals: .zero, spent: m.expense - fixed,
                                       slices: m.by.map { .init(emoji: emoji($0.key), name: $0.key, amount: $0.value, lastMonth: before.by[$0.key] ?? .zero) })
        }
        // 订阅，和 7 天内要扣的
        let subs = Subscriptions.status(ledger, today: today)
        b.subscriptions = subs.map { s in
            .init(id: s.id, emoji: "🔁", name: s.name, note: s.nextDate.map { "\($0.month) 月 \($0.day) 日扣" } ?? "停了", amount: s.amount,
                  off: s.nextDate == nil, cycle: [Subscription.Cycle.weekly, .monthly, .quarterly, .yearly].firstIndex(of: s.cycle) ?? 1)
        }
        b.upcoming = subs.compactMap { s in
            guard let d = s.nextDate, let left = s.daysLeft, left <= 31 else { return nil }
            return TrialBook.Entry(emoji: "🔁", name: s.name, meta: "\(d.month) 月 \(d.day) 日 · \(left) 天后", amount: s.monthlyBase,
                                   account: s.accountID.flatMap { names[$0] } ?? "")
        }
        // 店：这个月每天收了多少（按账户分渠道）
        if !bizBooks.isEmpty {
            let income = plain.filter { side($0) == .biz && $0.date.yearMonth == today.yearMonth && $0.amount > .zero && !$0.isTransfer }
            b.shopDays = (1...daysInMonth(today)).map { d in
                let rows = income.filter { $0.date.day == d }
                guard d <= today.day else { return .init(day: d, cash: .zero, card: .zero, state: .future) }
                guard !rows.isEmpty else { return .init(day: d, cash: .zero, card: .zero, state: .missing) }
                var parts: [String: Money] = [:]
                for t in rows { parts[names[t.accountID] ?? t.accountID, default: .zero] = parts[names[t.accountID] ?? t.accountID, default: .zero] + ledger.baseAmount(t) }
                let channels = parts.map { TrialBook.ShopChannel($0.key, $0.value) }.sorted { $0.amount > $1.amount }
                let cash = channels.filter { $0.account.contains("现金") }.map(\.amount).reduce(.zero, +)
                let all = channels.map(\.amount).reduce(.zero, +)
                return .init(day: d, cash: cash, card: all - cash, state: .open, parts: channels)
            }
            b.fixedCosts = Outlook.fixedGuesses(ledger, side: .business, today: today, hiddenAccounts: hidden).map { g in
                .init(emoji: emoji(g.category), name: g.name, note: "每月 \(g.day) 日 · \(names[g.accountID] ?? g.accountID)", amount: g.amount.magnitude,
                      account: names[g.accountID] ?? g.accountID, day: g.day)
            }
        }
        return b
    }
}

// MARK: - 写（第 2 步：记一笔、改分类、改金额、删）

extension LedgerBridge {
    /// 日子往前数几天。
    static func day(_ today: LocalDate, minus n: Int) -> LocalDate {
        let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: -n, to: date(today)) ?? date(today)
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: d)
        return LocalDate(year: c.year ?? today.year, month: c.month ?? today.month, day: c.day ?? today.day)
    }

    /// 界面上不属于流水的那些东西的样子（账户有哪些、目标、订阅、店的每天…）。写入前后拿它比：变了，说明这次改动不只是流水，这一步还没接。
    static func shape(_ b: TrialBook) -> [String] {
        ["goal|\(b.journey.name)|\(b.journey.total.cents)"]
            + b.smallGoals.map { "small|\($0.name)|\($0.target.cents)" }
            + b.subscriptions.map { "sub|\($0.name)|\($0.amount.cents)|\($0.off)" }
            + b.fixedCosts.map { "fixed|\($0.name)|\($0.amount.cents)|\($0.off)" }
            + ["names|\(b.lifeName)|\(b.shopName)|\(b.showLife)|\(b.showBiz)", "memos|\(b.memos.count)"]
    }

    /// 界面上做了一次改动（`before` → `after`），把它照样做到正式账本上。
    /// 这一步只接流水：多了一笔 = 记一笔；少了一笔 = 删；分类变了 = 改分类；金额变了 = 改金额。
    /// 每样都走正式账本自己的写法：带作者、记进改动记录、能撤销。别的改动（账户、目标、订阅、店的账…）还没接，直接拒绝，账本不动。
    @discardableResult
    public static func apply(before: TrialBook, after: TrialBook, to ledger: inout Ledger, today: LocalDate, author: String) throws -> [ChangeRecord] {
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { throw TrialError("先在设置里填一下记账人是谁") }
        guard shape(before) == shape(after) else { throw TrialError("这一步在接正式账本的这一版里还没接上，账本没动") }
        let old = Dictionary(before.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(after.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let added = after.entries.filter { old[$0.id] == nil }
        let removed = before.entries.filter { new[$0.id] == nil }
        let changed = after.entries.filter { e in old[e.id].map { $0.name != e.name || $0.amount != e.amount } ?? false }
        guard added.count <= 1 else { throw TrialError("一次进来好几笔（导入）在这一版里还没接上，账本没动") }

        var work = ledger
        var records: [ChangeRecord] = []
        let entriesTouched = !added.isEmpty || !removed.isEmpty || !changed.isEmpty
        // 第 3 步：账户（加、改名、改余额、删、置顶、换底色）。流水没动的时候才看账户，免得把「记一笔带来的余额变化」当成改余额
        if !entriesTouched {
            records += try applyAccounts(before: before, after: after, to: &work, today: today, author: who)
            guard !records.isEmpty else { throw TrialError("这一步在接正式账本的这一版里还没接上，账本没动") }
            ledger = work
            return records
        }
        let lifeBook = work.books.first { !$0.isBusiness }?.id
        let shopBook = work.books.first { $0.isBusiness }?.id
        func accountID(_ name: String) throws -> String {
            guard let a = work.accounts.first(where: { $0.name == name }) else { throw TrialError("「\(name)」不是正式账本里的账户，这笔记不上") }
            return a.id
        }
        for e in added {
            guard e.amount != .zero else { throw TrialError("金额要比 0 大") }
            let book = e.side == .biz ? shopBook : lifeBook
            let tx = Transaction(id: e.id, date: day(today, minus: e.daysAgo), amount: e.amount, description: e.place.isEmpty ? e.name : e.place,
                                 accountID: try accountID(e.account), bookID: book, category: e.name == "还没分" ? nil : e.name,
                                 source: "手记", note: e.note.isEmpty ? nil : e.note)
            records.append(try work.addTransaction(tx, author: who))
        }
        if !removed.isEmpty { records.append(try work.removeTransactions(removed.map(\.id), author: who)) }
        for e in changed {
            guard let was = old[e.id], var tx = work.transactions.first(where: { $0.id == e.id }) else { throw TrialError("这一笔在正式账本里找不到了") }
            if was.amount != e.amount {
                // 界面上的金额是换成主币种的；外币账户的那一笔先不让在这里改，免得改错
                guard work.baseAmount(tx) == tx.amount else { throw TrialError("这一笔是外币账户的，金额先回旧界面改") }
                tx.amount = e.amount
                if was.name != e.name { tx.category = e.name == "还没分" ? nil : e.name }
                records.append(try work.editTransaction(tx, author: who))
            } else {
                records.append(work.categorize([e.id], category: e.name, author: who))
            }
        }
        ledger = work
        return records
    }

    /// 账户上的改动照样做到正式账本上。能对上正式账本里一个账户的才动（银行卡、现金、储蓄、信用卡）；借的钱、分期那几行不是账户，这一步不管。
    static func applyAccounts(before: TrialBook, after: TrialBook, to work: inout Ledger, today: LocalDate, author who: String) throws -> [ChangeRecord] {
        var records: [ChangeRecord] = []
        func real(_ name: String) -> Account? { work.accounts.first { $0.name == name } }
        let was = Dictionary(before.accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Dictionary(after.accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // 删
        for a in before.accounts where now[a.id] == nil {
            guard let r = real(a.name) else { throw TrialError("「\(a.name)」不是一个账户，这一步还没接上，账本没动") }
            records.append(try work.removeAccount(r.id, author: who))
        }
        // 加
        for a in after.accounts where was[a.id] == nil {
            guard a.kind == .own || a.kind == .shop || a.isCreditCard else { throw TrialError("借的钱、借出去的在接正式账本的这一版里还没接上，账本没动") }
            guard real(a.name) == nil else { throw TrialError("已经有一个叫「\(a.name)」的账户了") }
            let kind: AccountKind = a.kind == .debt ? .credit : a.name.contains("现金") ? .cash : a.block == .emergency || a.block == .goal ? .savings : .bank
            let id = work.newAccountID(for: a.name)
            let opening = a.kind == .debt ? .zero - a.balance : a.balance
            records.append(try work.createAccount(Account(id: id, name: a.name, kind: kind), openingBalance: opening, date: today, author: who))
            if a.side == .biz { records.append(try work.setAccountSide(id, side: .business, author: who)) }
        }
        // 两个以上的账户余额一起变了：那是转账 / 还款，不是改余额，这一步还没接
        let moved = after.accounts.filter { a in was[a.id].map { $0.balance != a.balance } ?? false }
        guard moved.count <= 1 else { throw TrialError("转账、还款在接正式账本的这一版里还没接上，账本没动") }
        // 改名、改余额、换底色
        for a in after.accounts {
            guard let o = was[a.id], var r = real(o.name) else { continue }
            if o.name != a.name || o.cardStyle != a.cardStyle {
                guard o.name == a.name || real(a.name) == nil else { throw TrialError("已经有一个叫「\(a.name)」的账户了") }
                r.name = a.name; r.cardStyle = a.cardStyle
                records.append(try work.updateAccount(r, author: who))
            }
            if o.balance != a.balance {
                // 改余额 = 调期初余额：差多少，期初就挪多少（流水一笔不动）
                let delta = o.kind == .debt ? o.balance - a.balance : a.balance - o.balance
                let opening = work.transactions.first { $0.accountID == r.id && $0.flow == .opening }?.amount ?? .zero
                guard work.baseAmount(Transaction(date: today, amount: Money(cents: 100), description: "", accountID: r.id)) == Money(cents: 100) else {
                    throw TrialError("「\(a.name)」是外币账户，余额先回旧界面改")
                }
                records.append(try work.setOpeningBalance(accountID: r.id, amount: opening + delta, date: today, author: who))
            }
        }
        // 置顶：哪几张、什么先后
        for side in [TrialBook.Side.life, .biz] {
            let old = before.pinned(on: side).map(\.name), new = after.pinned(on: side).map(\.name)
            // 用户从没置顶过（正式账本里一张都没记）而界面上只是默认置顶的那张，不算改动
            let stored = work.accounts.contains { $0.cardPin != nil && (after.account($0.name)?.side == side) }
            guard old != new || (!stored && (side == .life ? after.lifePins != before.lifePins : after.shopPins != before.shopPins)) else { continue }
            for acc in after.accounts(on: side) {
                guard var r = real(acc.name) else { continue }
                let pin = new.firstIndex(of: acc.name)
                if r.cardPin != pin { r.cardPin = pin; records.append(try work.updateAccount(r, author: who)) }
            }
        }
        return records
    }
}
