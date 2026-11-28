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
    /// - showPrivate: 私房钱账户（isPrivate）要不要显示、算进合计。默认不显示、不算，和旧界面一样。
    public static func snapshot(of ledger: Ledger, today: LocalDate = .today, showPrivate: Bool = false) -> TrialBook {
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
            if a.kind == .credit {
                // 信用卡：欠的是正数
                return .init(emoji: "💳", name: a.name, note: a.institution ?? "", balance: bal < .zero ? bal.magnitude : .zero, kind: .debt, block: .none, side: biz ? .biz : .life)
            }
            if biz { return .init(emoji: icon, name: a.name, note: a.institution ?? "", balance: bal, kind: .shop, block: .shop) }
            let block: TrialBook.Account.Block = goalAccounts.contains(a.id) ? .goal : a.kind == .savings ? .emergency : .daily
            return .init(emoji: icon, name: a.name, note: a.institution ?? "", balance: bal, kind: .own, block: block)
        }
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
