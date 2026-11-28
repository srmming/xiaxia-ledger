import Foundation

/// 把正式账本（`Ledger`）的数整理成 v3 界面要的样子。
/// 第 1 步：只读。界面照旧读 `TrialBook` 的形状，这里从正式账本现算一份出来；一个字都不往正式账本里写。
/// 口径尽量用正式账本已有的算法（`Summaries`、`Outlook`、`Plans`、`Subscriptions`、`WealthBreakdown`），这里只是换个摆法。
public enum LedgerBridge {
    /// 分类的图标：按名字找，找不到给一张小票。
    /// 内置分类各用哪个小图标。正式账本里内置的每个分类（CategoryIcons 里那一整张表、生意那几样）都要在这里有一个，测试守着。
    static let categoryEmoji: [String: String] = [
        "餐饮": "🥗", "超市": "🛒", "交通": "🚇", "房租": "🏠", "水电": "💡", "购物": "🛍️", "娱乐": "🎬", "医疗": "💊", "看病": "💊", "通讯": "📱", "话费": "📱",
        "旅行": "🧳", "宝宝": "🍼", "其他": "🧾", "衣服": "👕", "礼物": "🎁", "送礼": "🎁", "咖啡": "☕", "加油": "⛽", "宠物": "🐾", "学习": "📚", "美容": "💄",
        "美甲": "💅", "订阅": "🔁", "保险": "🛡️", "税费": "🧮", "社保": "🪪", "手续费": "💸", "退款": "↩️", "工资": "💼", "收入": "💰", "营业收入": "💶",
        "营业额": "💶", "店租": "🏬", "耗材": "🧴", "设备": "🛠️", "员工工资": "🧑‍💼", "营销": "📣", "充值": "🔋", "转账": "🔀", "老板提款": "👛", "储蓄": "🏦",
        "投资": "📈", "借款": "🤝", "还款": "✅", "运动": "🏃", "家居": "🛋️", "零食": "🍪", "数码": "💻", "未分类": "❓", "外卖": "🥡", "早餐": "🥐",
        "水果": "🍎", "甜品": "🍰", "奶茶": "🧋", "喝酒": "🍺", "买菜": "🥬", "面包": "🍞", "火锅": "🍲", "打车": "🚕", "地铁": "🚇", "机票": "✈️",
        "火车": "🚆", "停车": "🅿️", "单车": "🚲", "修车": "🔧", "过路费": "🛣️", "房贷": "🏡", "网费": "🌐", "燃气": "🔥", "水费": "🚿", "电费": "⚡",
        "家电": "🔌", "维修": "🔧", "清洁": "🧹", "绿植": "🪴", "物业": "🏢", "化妆品": "💄", "鞋子": "👟", "包包": "👜", "首饰": "💍", "眼镜": "👓",
        "书": "📖", "文具": "✏️", "玩具": "🧸", "网购": "📦", "看牙": "🦷", "买药": "💊", "体检": "🩺", "护肤": "🧴", "理发": "💇", "按摩": "💆",
        "健身房": "🏋️", "电影": "🎬", "音乐": "🎵", "门票": "🎟️", "摄影": "📷", "酒吧": "🍸", "唱歌": "🎤", "爱好": "🎨", "酒店": "🏨", "证件": "🪪",
        "红包": "🧧", "家人": "👪", "捐款": "💝", "婚礼": "💒", "父母": "👵", "学费": "🎓", "母婴": "🍼", "课程": "📝", "办公": "🗂️", "软件": "💿",
        "网站": "🌐", "副业": "🧩", "奖金": "🏅", "报销": "🧾", "租金收入": "🏘️", "二手": "♻️", "利息": "🪙", "退税": "↩️", "还信用卡": "💳", "分期": "🗓️",
        "换汇": "💱", "股票": "📈", "罚款": "🚫", "银行费": "🏦", "汇款": "📮", "欠款": "📒", "数字货币": "🪙", "快递": "🚚", "平台佣金": "🏷️", "刷卡费": "💳",
        "装修": "🔨", "会计": "🧮", "工作服": "🦺", "执照": "📜", "客人": "🙋", "心愿": "⭐", "喜欢": "❤️", "应急": "🆘", "节日": "🎉",
        "进货": "📦", "花材": "💐", "本钱": "🏦", "包装耗材": "🧴", "个人护理": "🧼", "原料": "🧺", "推广": "📣", "期初余额": "🏁", "转入": "📥", "转出": "📤",
    ]

    /// 还没有图标的分类用这个（用户自己起的分类）。
    static let fallbackEmoji = "🧾"

    static func emoji(_ category: String?) -> String {
        guard let category, !category.isEmpty else { return "❓" }
        if let hit = categoryEmoji[category] { return hit }
        // 用户自己起的名字里带着内置分类的词（「宠物医疗」）：用最长的那个词的图标
        let part = categoryEmoji.keys.filter { $0 != "其他" && $0 != "书" && category.contains($0) }.max { $0.count < $1.count }
        return part.flatMap { categoryEmoji[$0] } ?? fallbackEmoji
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
        // 目标页只管生活这边的目标：钉住的（没有就第一个）当大目标，后面最多 3 个当小目标。店里账本的目标不在这一页（它的账户照常算店里的）
        let ordered = ledger.goals.filter { !bizBooks.contains($0.bookID) && !$0.isFinished }
            .sorted { ($0.pinned ? 0 : 1, $0.rank ?? Int.max) < ($1.pinned ? 0 : 1, $1.rank ?? Int.max) }
        let shownGoals = Array(ordered.prefix(1 + Plans.maxSmallGoals))
        let goalAccounts = Set(shownGoals.compactMap(\.savingsAccountID)).subtracting(bizAccounts)
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
        // 生意账本里的欠款、分期不放在生活这边：它们在店的「欠款」里（见下面 shopDebts）
        let bizDebtIDs = Set(ledger.debts.filter { bizBooks.contains($0.bookID) }.map(\.id))
        let bizInstallmentIDs = Set(ledger.installments.filter { bizBooks.contains($0.bookID) }.map(\.id))
        for d in Plans.debts(ledger, today: today) where d.outstanding > .zero && !bizDebtIDs.contains(d.id) {
            let lent = d.direction == .theyOweMe
            accounts.append(.init(emoji: lent ? "🧑" : "🤝", name: lent ? "借给\(d.counterparty)" : d.counterparty, note: lent ? "他欠我" : "欠的钱",
                                  balance: d.outstanding, kind: lent ? .lent : .debt, block: .none))
        }
        for i in Plans.installments(ledger) where i.remaining > .zero && !bizInstallmentIDs.contains(i.id) {
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
        // 这个月留给目标的：定了每月存多少、还没存够的，按定的留；已经存得比定的多，按真存的
        let bigPlan = ledger.goals.filter { !bizBooks.contains($0.bookID) && !$0.isFinished }
            .sorted { ($0.pinned ? 0 : 1, $0.rank ?? Int.max) < ($1.pinned ? 0 : 1, $1.rank ?? Int.max) }.first?.monthlyPlan ?? .zero
// 固定的里已经付的不会比这个月真花掉的还多；这样「一共花掉」正好等于各分类加起来
        let paidFixed = min(fixedPaid, now.expense)
        let free = FreeToSpend(income: now.income, fixed: paidFixed + fixedLeft, forGoals: max(saved, bigPlan),
                               spent: now.expense - paidFixed, daysLeft: daysLeft, fixedLeft: fixedLeft)

        // 目标：钉住的（没有就第一个）当大目标，后面最多 3 个当小目标
        let statuses = Plans.goals(ledger)
        func status(_ g: Goal) -> GoalStatus? { statuses.first { $0.id == g.id } }
        var journey = Journey(name: "", stops: [])
        var bigAccount: UUID?
        if let g = ordered.first, let s = status(g), g.target > .zero {
            let stops = [10, 25, 50, 75, 100].map { Money(cents: max(g.target.cents * Int64($0) / 100 / 100 * 100, 100)) }
            journey = Journey(name: g.name, stops: Array(Set(stops)).sorted(), saved: s.saved, monthlyPlan: g.monthlyPlan ?? .zero)
            bigAccount = accounts.first { a in g.savingsAccountID.flatMap { names[$0] } == a.name }?.id
            // 这个月往大目标里存了多少：它那个账户这个月进的减出的（没有自己账户的按挂在它名下的存钱流水）
            let mine: [Transaction]
            if let jar = g.savingsAccountID { mine = ledger.transactions.filter { $0.accountID == jar && $0.date.yearMonth == today.yearMonth && $0.date <= today && $0.flow != .opening } }
            else { let ids = ledger.goalContributionIDs(g); mine = ledger.transactions.filter { ids.contains($0.id) && $0.date.yearMonth == today.yearMonth } }
            journey.savedThisMonth = max(mine.reduce(Money.zero) { $0 + ledger.baseAmount($1) }, .zero)
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
        b.memos = memos(of: ledger)
        b.lifeLoanMonthly = lifeMonthlyRepayments(ledger, today: today)
        // 欠的每一笔照计划哪个月还完：排了还款计划的看最后一期，没排但约了日子的看约的日子，分期看最后一期。别的不写
        func monthLabel(_ d: LocalDate) -> String { "\(d.year) 年 \(d.month) 月" }
        var ends: [String: LocalDate] = [:], lifeOpen: [String] = []
        for d in ledger.debts where d.direction == .iOweThem && !d.closed {
            guard let st = Plans.debts(ledger, today: today).first(where: { $0.id == d.id }), st.outstanding > .zero else { continue }
            if !bizBooks.contains(d.bookID) { lifeOpen.append(d.counterparty) }
            if let last = (d.plan ?? []).map(\.date).max(), last >= today { ends[d.counterparty] = last }
            else if let due = d.dueDate, due >= today { ends[d.counterparty] = due }
        }
        for i in ledger.installments {
            guard let st = Plans.installments(ledger).first(where: { $0.id == i.id }), st.remaining > .zero else { continue }
            if !bizBooks.contains(i.bookID) { lifeOpen.append(i.name) }
            if let next = st.nextDate { ends[i.name] = next.adding(months: max(st.count - st.paidCount - 1, 0)) }
        }
        b.payoffMonths = ends.mapValues(monthLabel)
        if !lifeOpen.isEmpty, lifeOpen.allSatisfy({ ends[$0] != nil }) { b.debtFreeMonth = lifeOpen.compactMap { ends[$0] }.max().map(monthLabel) }
        // 大目标各站是哪天到的：它那个账户一天天的余额，第一次到那么多的那天。钱取出去又存回来的，按第一次算
        if let g = ordered.first, let jar = g.savingsAccountID {
            var running = Money.zero
            var reached: [Int: String] = [:]
            let history = ledger.transactions.filter { $0.accountID == jar && $0.date <= today }.sorted { $0.date < $1.date }
            for t in history {
                running = running + ledger.baseAmount(t)
                for (i, st) in journey.stations.enumerated() where i > 0 && reached[i] == nil && st.target > .zero && running >= st.target && st.target <= journey.saved {
                    reached[i] = (t.date.year == today.year ? "" : "\(t.date.year) 年 ") + "\(t.date.month) 月 \(t.date.day) 日"
                }
            }
            b.stationDates = reached
        }
        // 这个月从店里拿回家的（给自己发的）：两边转钱里从生意那边出去的那些
        if !bizBooks.isEmpty {
            b.ownerPaidThisMonth = ledger.sideTransfers(month: today.yearMonth).filter { $0.amount < .zero }
                .reduce(Money.zero) { $0 + ledger.baseAmount($1).magnitude }
        }
        b.finishedGoals = ledger.finishedGoals.filter { !bizBooks.contains($0.bookID) }.map { g in
            .init(id: g.id, name: g.name, total: g.target, date: g.finishedOn.map { "\($0.year) 年 \($0.month) 月" } ?? "", small: !g.pinned)
        }
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
            // 那个月存进目标的（和这个月一个算法：存钱那种流水里出去的那一头）
            let put = ledger.transactions.filter { $0.flow == .saving && $0.date.yearMonth == ym && $0.amount < .zero && !hidden.contains($0.accountID) }
                .map { ledger.baseAmount($0).magnitude }.reduce(.zero, +)
            var d = TrialBook.MonthData(key: .init(ym.year, ym.month), income: m.income, fixed: fixed, forGoals: put, spent: m.expense - fixed,
                                        slices: m.by.map { .init(emoji: emoji($0.key), name: $0.key, amount: $0.value, lastMonth: before.by[$0.key] ?? .zero) })
            // 第 7 步：那个月底的家底（生活这边每个账户到月底的余额：正的算有，信用卡欠的算欠；借的钱和分期按现在的算，过去的没法倒推）
            var have = Money.zero, owe = Money.zero
            for a in ledger.accounts where !hidden.contains(a.id) && !bizAccounts.contains(a.id) {
                let bal = ledger.transactions.filter { $0.accountID == a.id && $0.date.yearMonth <= ym }.reduce(Money.zero) { $0 + ledger.baseAmount($1) }
                if a.kind == .credit { owe = owe + (bal < .zero ? bal.magnitude : .zero) } else { have = have + max(bal, .zero) }
            }
            let realNames = Set(ledger.accounts.map(\.name))
            owe = owe + accounts.filter { $0.side == .life && $0.kind == .debt && !realNames.contains($0.name) }.map(\.balance).reduce(.zero, +)
            have = have + accounts.filter { $0.kind == .lent }.map(\.balance).reduce(.zero, +)
            d.have = have; d.owe = owe; d.net = have - owe
            // 那个月花到「和今天同一天」时花了多少（比上月同期用）
            if k == 1 { d.sameDaySpent = month(ym, upTo: LocalDate(year: ym.year, month: ym.month, day: min(today.day, 28))).expense }
            // 到那个月底大目标一共存了多少：它那个账户到月底的余额（小结里「过了哪一站」用）
            if let jar = ordered.first?.savingsAccountID {
                let end = LocalDate(year: ym.year, month: ym.month, day: 1).adding(months: 1).adding(days: -1)
                let sum = ledger.transactions.filter { $0.accountID == jar && $0.date <= end }.reduce(Money.zero) { $0 + ledger.baseAmount($1) }
                d.goalSavedEnd = max(sum, .zero)
            }
            // 那个月每天花了多少（趋势页画「上个月」那条线用）
            var perDay = [Money](repeating: .zero, count: daysInMonth(LocalDate(year: ym.year, month: ym.month, day: 1)))
            for t in lifeTx where t.date.yearMonth == ym && t.amount < .zero && !t.isTransfer && t.date.day <= perDay.count {
                perDay[t.date.day - 1] = perDay[t.date.day - 1] + ledger.baseAmount(t).magnitude
            }
            d.daily = perDay
            d.weekly = stride(from: 0, to: perDay.count, by: 7).map { perDay[$0..<min($0 + 7, perDay.count)].reduce(.zero, +) }
            // 那个月记的几笔（最大的几笔），和店里收的、花的
            d.entries = lifeTx.filter { $0.date.yearMonth == ym && $0.amount < .zero && !$0.isTransfer }.sorted { $0.amount < $1.amount }.prefix(8).map { t in
                .init(id: t.id, emoji: emoji(t.category), name: t.category ?? "还没分", meta: "\(t.description) · \(names[t.accountID] ?? t.accountID)", amount: ledger.baseAmount(t),
                      tag: t.source ?? "", daysAgo: days(from: t.date, to: today), place: t.description, account: names[t.accountID] ?? t.accountID)
            }
            let shop = plain.filter { side($0) == .biz && $0.date.yearMonth == ym && !$0.isTransfer }
            d.shopIn = shop.filter { $0.amount > .zero }.reduce(Money.zero) { $0 + ledger.baseAmount($1) }
            d.shopOut = shop.filter { $0.amount < .zero }.reduce(Money.zero) { $0 + ledger.baseAmount($1) }.magnitude
            // 那个月店里一笔笔的流水（正式账本里本来就有）。最近 90 天里的那些笔带着编号，点开能改；更早的只看
            d.shopRows = shop.map { t in
                .init(id: t.id.uuidString, emoji: t.amount > .zero ? ((names[t.accountID] ?? "").contains("现金") ? "💶" : "💳") : emoji(t.category),
                      title: t.amount > .zero && t.category == "营业收入" ? "营业额" : (t.category ?? "还没分"),
                      detail: [t.description, names[t.accountID] ?? t.accountID].filter { !$0.isEmpty }.joined(separator: " · "),
                      amount: ledger.baseAmount(t), day: t.date.day, entryID: days(from: t.date, to: today) <= 90 ? t.id : nil)
            }
            return d
        }
        // 订阅，和 7 天内要扣的
        let subs = Subscriptions.status(ledger, today: today)
        b.subscriptions = subs.map { s in
            .init(id: s.id, emoji: "🔁", name: s.name, note: s.nextDate.map { "\($0.month) 月 \($0.day) 日扣" } ?? "停了", amount: s.amount,
                  off: s.nextDate == nil, cycle: [Subscription.Cycle.weekly, .monthly, .quarterly, .yearly].firstIndex(of: s.cycle) ?? 1,
                  account: s.accountID.flatMap { names[$0] } ?? "")
        }
        b.upcoming = subs.compactMap { s in
            guard let d = s.nextDate, let left = s.daysLeft, left <= 31 else { return nil }
            return TrialBook.Entry(emoji: "🔁", name: s.name, meta: "\(d.month) 月 \(d.day) 日 · \(left) 天后", amount: s.monthlyBase,
                                   account: s.accountID.flatMap { names[$0] } ?? "")
        }
        // 店：这个月每天收了多少（按账户分渠道）
        if !bizBooks.isEmpty {
            let income = plain.filter { side($0) == .biz && $0.date.yearMonth == today.yearMonth && $0.amount > .zero && !$0.isTransfer }
            b.shopDaysHoldIncome = true
            b.shopDays = (1...daysInMonth(today)).map { d in
                let rows = income.filter { $0.date.day == d }
                guard d <= today.day else { return .init(day: d, cash: .zero, card: .zero, state: .future) }
                // 那天有收入就是开了门（哪怕标过休息）；没收入又标了休息的才算休息
                let rest = ledger.isShopRest(LocalDate(year: today.year, month: today.month, day: d))
                guard !rows.isEmpty else { return .init(day: d, cash: .zero, card: .zero, state: rest ? .rest : .missing) }
                var parts: [String: Money] = [:]
                for t in rows { parts[names[t.accountID] ?? t.accountID, default: .zero] = parts[names[t.accountID] ?? t.accountID, default: .zero] + ledger.baseAmount(t) }
                let channels = parts.map { TrialBook.ShopChannel($0.key, $0.value) }.sorted { $0.amount > $1.amount }
                let cash = channels.filter { $0.account.contains("现金") }.map(\.amount).reduce(.zero, +)
                let all = channels.map(\.amount).reduce(.zero, +)
                return .init(day: d, cash: cash, card: all - cash, state: .open, parts: channels)
            }
            // 固定开销两种：自己加的（每月自动记的规则，能改能停能拿掉）、从流水里认出来的（只能「不算」）
            let rules: [TrialBook.Item] = shopFixedRules(ledger).map { r in
                .init(id: r.id, emoji: emoji(r.template.category), name: r.template.description,
                      note: "每月 \(r.start.day) 日 · \(names[r.template.accountID] ?? r.template.accountID)", amount: r.template.amount.magnitude,
                      off: r.paused, account: names[r.template.accountID] ?? r.template.accountID, day: r.start.day)
            }
            let guessed: [TrialBook.Item] = Outlook.fixedGuesses(ledger, side: .business, today: today, hiddenAccounts: hidden)
                .filter { g in !rules.contains { $0.name == g.name } }.map { g in
                .init(emoji: emoji(g.category), name: g.name, note: "每月 \(g.day) 日 · \(names[g.accountID] ?? g.accountID)", amount: g.amount.magnitude,
                      tag: guessedTag, account: names[g.accountID] ?? g.accountID, day: g.day)
            }
            b.fixedCosts = (rules + guessed).sorted { $0.amount > $1.amount }
            // 回本、体检：开店本钱、以前赚回来多少、店里每月要还的，都从正式账本来
            if let cap = ledger.business?.capital, cap.total > .zero {
                let when = cap.openedOn.map { "\($0.year) 年 \($0.month) 月" } ?? ""
                var items = cap.items.map { TrialBook.Item(emoji: "🏪", name: $0.name, note: when, amount: $0.amount) }
                let listed = cap.items.map(\.amount).reduce(.zero, +)
                if listed < cap.total { items.append(.init(emoji: "🏪", name: items.isEmpty ? "开店本钱" : "别的本钱", note: when, amount: cap.total - listed)) }
                b.capital = items
                // 界面上「赚回来的」= 以前赚回来的 + 这个月真正赚的；正式账本给的是到今天一共赚回来多少，所以把这个月的那部分先减掉
                if let p = ledger.capitalProgress(today: today) {
                    b.shopBackBefore = max(p.recovered - max(b.shopMonth().earned, .zero), .zero)
                }
                // 过去每个月底一共赚回来多少（回本页那条线）：用正式账本自己的算法，按那个月最后一天算。开店之前的月份不带
                for i in b.pastMonths.indices {
                    let k = b.pastMonths[i].key
                    let end = LocalDate(year: k.year, month: k.month, day: 1).adding(months: 1).adding(days: -1)
                    if let open = cap.openedOn, end < open { continue }
                    b.pastMonths[i].shopBack = ledger.capitalProgress(today: end)?.recovered
                }
            }
            b.shopLoanMonthly = shopMonthlyRepayments(ledger, today: today)
            // 店的欠款：生意账本里欠别人的、别人欠店的、没还完的分期、旧界面记的「客人欠的」
            var owing: [TrialBook.Item] = []
            for d in Plans.debts(ledger, today: today) where d.outstanding > .zero && bizDebtIDs.contains(d.id) {
                let toShop = d.direction == .theyOweMe
                // 排了还款计划、或者约的日子不在这个月的：按月还，这个月该还的那部分在「每月要还的」里
                let plan = ledger.debts.first { $0.id == d.id }?.plan ?? []
                let monthly = !toShop && (!plan.isEmpty || (d.dueDate.map { $0.yearMonth > today.yearMonth } ?? false))
                owing.append(.init(id: d.id, emoji: toShop ? "🧑" : "📦", name: d.counterparty, note: d.dueDate.map { "\($0.month) 月 \($0.day) 日前" } ?? "",
                                   amount: d.outstanding, tag: monthly ? "按月还" : "", flag: toShop))
            }
            for i in Plans.installments(ledger) where i.remaining > .zero && bizInstallmentIDs.contains(i.id) {
                owing.append(.init(id: i.id, emoji: "🧾", name: i.name, note: "分期 · 还剩 \(i.count - i.paidCount) 期，每期 \(i.perPayment.formatted)", amount: i.remaining, tag: installmentTag))
            }
            for r in ledger.receivables where r.amount > .zero {
                owing.append(.init(id: r.id, emoji: "🧑", name: r.name, note: "", amount: r.amount, flag: true))
            }
            b.shopDebts = owing
            // 最近两次估货之间用掉和损耗了多少：上次估的 + 这段时间进的货 − 这次估的
            let ests = (ledger.business?.stockEstimates ?? []).sorted { $0.date < $1.date }
            if ests.count >= 2 {
                let a = ests[ests.count - 2], z = ests[ests.count - 1]
                let stockCats: Set<String> = ["进货", "花材", "原料"]
                let bought = ledger.transactions.filter { t in
                    t.bookID.map(bizBooks.contains) == true && t.amount < .zero && t.countsAsIncomeOrExpense && t.date > a.date && t.date <= z.date
                        && stockCats.contains(t.category ?? "")
                }.reduce(Money.zero) { $0 + ledger.baseAmount($1).magnitude }
                func label(_ d: LocalDate) -> String { "\(d.month) 月 \(d.day) 日估的" }
                b.stockUsage = .init(fromLabel: label(a.date), start: a.value, bought: bought, toLabel: label(z.date), end: z.value)
            }
            b.stockEstimates = (ledger.business?.stockEstimates ?? []).sorted { $0.date > $1.date }.map {
                .init(emoji: "📅", name: $0.date == today ? "今天" : "\($0.date.month) 月 \($0.date.day) 日", note: $0.note ?? "", amount: $0.value)
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
            + b.fixedCosts.map { "fixed|\($0.name)|\($0.amount.cents)|\($0.off)" }
            + ["names|\(b.lifeName)|\(b.shopName)|\(b.showLife)|\(b.showBiz)", 
               "shop|\(b.purchases.count)|\(b.shopDebts.map { "\($0.name)\($0.off)" }.joined())|\(b.capital.count)|\(b.capitalTotal.cents)|\(b.stockEstimates.count)|\(b.wanted.count)"]
            + b.shopDays.map { "day|\($0.day)|\($0.state)|\($0.total.cents)" }
    }

    /// 界面上做了一次改动（`before` → `after`），把它照样做到正式账本上。
    /// 这一步只接流水：多了一笔 = 记一笔；少了一笔 = 删；分类变了 = 改分类；金额变了 = 改金额。
    /// 每样都走正式账本自己的写法：带作者、记进改动记录、能撤销。别的改动（账户、目标、订阅、店的账…）还没接，直接拒绝，账本不动。
    @discardableResult
    public static func apply(before: TrialBook, after: TrialBook, to ledger: inout Ledger, today: LocalDate, author: String) throws -> [ChangeRecord] {
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { throw TrialError("先在设置里填一下记账人是谁") }
        // 第 6 步：店里某一天收了多少（按收款渠道）、加一样固定开销
        var shopWork = ledger
        if let records = try applyShop(before: before, after: after, to: &shopWork, today: today, author: who) {
            ledger = shopWork
            return records
        }
        // 第 4 步：目标（存一笔、定一个新目标、改名字和金额）
        var goalWork = ledger
        if let records = try applyGoals(before: before, after: after, to: &goalWork, today: today, author: who) {
            ledger = goalWork
            return records
        }
        // 店的本钱、估货值、欠款
        var bizWork = ledger
        if let records = try applyShopBooks(before: before, after: after, to: &bizWork, today: today, author: who) {
            ledger = bizWork
            return records
        }
        // 第 8 步：夏夏的记忆、账本改名
        var moreWork = ledger
        if let records = try applyMemos(before: before, after: after, to: &moreWork, today: today, author: who) ?? applyNames(before: before, after: after, to: &moreWork, author: who) {
            ledger = moreWork
            return records
        }
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
            guard a.kind == .own || a.kind == .shop || a.isCreditCard else { continue }   // 借的钱、借出去的：下面当成借款记
            guard real(a.name) == nil else { throw TrialError("已经有一个叫「\(a.name)」的账户了") }
            let kind: AccountKind = a.kind == .debt ? .credit : a.name.contains("现金") ? .cash : a.block == .emergency || a.block == .goal ? .savings : .bank
            let id = work.newAccountID(for: a.name)
            let opening = a.kind == .debt ? .zero - a.balance : a.balance
            records.append(try work.createAccount(Account(id: id, name: a.name, kind: kind), openingBalance: opening, date: today, author: who))
            if a.side == .biz { records.append(try work.setAccountSide(id, side: .business, author: who)) }
        }
        // 第 5 步：两个账户的余额一起变了，一个少多少、另一个对上这么多 = 转账 / 还信用卡 / 还欠款 / 别人还钱 / 分期还一期
        let moved = after.accounts.filter { a in was[a.id].map { $0.balance != a.balance } ?? false }
        if moved.count == 2 {
            return records + [try applyMove(moved, was: was, to: &work, today: today, author: who)]
        }
        guard moved.count <= 1 else { throw TrialError("一次动了好几个账户的钱，这一步在接正式账本的这一版里还没接上，账本没动") }
        var paidOut: Set<UUID> = []
        // 订阅：加一个、标成要退 / 留着、拿掉
        records += try applySubscriptions(before: before, after: after, to: &work, today: today, author: who)
        // 新记一笔欠款（我欠别人 / 别人欠我）：不是账户，记成正式账本里的一笔借款
        for a in after.accounts where was[a.id] == nil && (a.kind == .lent || (a.kind == .debt && !a.isCreditCard)) {
            let lent = a.kind == .lent
            let who2 = lent && a.name.hasPrefix("借给") ? String(a.name.dropFirst(2)) : a.name
            // 在店那边记的（店的贷款、欠供应商的）记在生意账本上；别的记在生活账本上
            let book = (a.side == .biz ? work.books.first { $0.isBusiness }?.id : nil) ?? work.books.first { !$0.isBusiness }?.id ?? work.books.first?.id ?? ""
            // 借出去的同时有一个账户正好少了这么多（「借给小李 50」）：钱是从那个账户出去的，一起记上
            // 向别人借的同时有一个账户正好多了这么多：钱是进了那个账户
            let change1 = moved.count == 1 ? moved[0].balance - (was[moved[0].id]?.balance ?? .zero) : .zero
            let payer = moved.count == 1 && change1 == (lent ? .zero - a.balance : a.balance) ? real(was[moved[0].id]?.name ?? "") : nil
            if payer != nil { paidOut.insert(moved[0].id) }
            records.append(try work.addDebt(counterparty: who2, direction: lent ? .theyOweMe : .iOweThem, amount: a.balance, bookID: book,
                                            date: today, accountID: payer?.id, note: a.note.isEmpty ? nil : a.note, author: who).1)
        }
        // 改名、改余额、换底色
        for a in after.accounts {
            guard !paidOut.contains(a.id) else { continue }
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

    /// 目标上的改动照样做到正式账本上。没有目标上的改动返回 nil（让别的步骤去看）。
    /// 接了的：存一笔（从一个账户转进这个目标自己的账户）、定一个新目标（新开存钱罐或用已有的存起来的账户）、改名字和金额。
    /// 还没接的：删目标、换大目标、走完收起来 —— 直接拒绝，账本不动。
    static func applyGoals(before: TrialBook, after: TrialBook, to work: inout Ledger, today: LocalDate, author who: String) throws -> [ChangeRecord]? {
        struct G: Equatable { var key: String; var name: String; var target: Money; var saved: Money; var account: UUID?; var big: Bool }
        func list(_ b: TrialBook) -> [G] {
            (b.journey.total > .zero ? [G(key: "big", name: b.journey.name, target: b.journey.total, saved: b.journey.saved, account: b.bigGoalAccount, big: true)] : [])
                + b.smallGoals.map { G(key: $0.id.uuidString, name: $0.name, target: $0.target, saved: $0.saved, account: $0.account, big: false) }
        }
        let was = list(before), now = list(after)
        // 每月打算存多少（大目标的步子）：只改了这一个数
        if was == now, before.finishedGoals.count == after.finishedGoals.count, before.journey.monthlyPlan != after.journey.monthlyPlan {
            guard let g = work.goals.first(where: { $0.name == after.journey.name && !$0.isFinished }) else { throw TrialError("先定一个大目标，再定每月存多少") }
            do { return [try work.setGoalMonthlyPlan(g.id, to: after.journey.monthlyPlan > .zero ? after.journey.monthlyPlan : nil, author: who)] }
            catch { throw TrialError((error as? LocalizedError)?.errorDescription ?? "没改成，账本没动") }
        }
        guard was != now || before.finishedGoals.count != after.finishedGoals.count else { return nil }
        let notYet = TrialError("这一步在接正式账本的这一版里还没接上，账本没动")
        let finishing = after.finishedGoals.count == before.finishedGoals.count + 1
        guard finishing || before.finishedGoals.count == after.finishedGoals.count else { throw notYet }
        var records: [ChangeRecord] = []
        // 换大目标：原来的一个小目标现在是大目标，原来的大目标变成小目标。正式账本里就是「把它设成大目标」
        if let ob = was.first(where: \.big), let nb = now.first(where: \.big), ob.name != nb.name,
           was.contains(where: { !$0.big && $0.name == nb.name }), now.contains(where: { !$0.big && $0.name == ob.name }), was.count == now.count {
            guard let g = work.goals.first(where: { $0.name == nb.name }) else { throw TrialError("「\(nb.name)」在正式账本里找不到了") }
            return [try work.setMainGoal(g.id, author: who)]
        }
        // 删目标：一次只删一个。里面的钱照界面上选的走（挪去的那个账户多了这么多），目标删掉；它的账户留着（只加不删），不再算这个目标的
        let gone = was.filter { o in !now.contains { $0.key == o.key } }
        if !gone.isEmpty {
            guard gone.count == 1, now.count == was.count - 1, let o = gone.first else { throw notYet }
            guard let g = (o.big ? work.goals.first { $0.name == o.name } : work.goals.first { $0.id.uuidString == o.key } ?? work.goals.first { $0.name == o.name }) else {
                throw TrialError("「\(o.name)」在正式账本里找不到了")
            }
            if finishing {
                // 走完收起来：目标留着、标成走完；里面的钱转到界面上放回去的那个账户。
                // 最后一笔存进去正好存够的：钱从哪个账户来的先照样存进去，再整罐转走。
                guard let jarID = g.savingsAccountID, let jarName = before.accounts.first(where: { $0.id == o.account })?.name else {
                    throw TrialError("「\(g.name)」还没有自己的账户，先做一次迁移")
                }
                func delta(_ a: TrialBook.Account) -> Money { a.balance - (before.accounts.first { $0.id == a.id }?.balance ?? .zero) }
                let others = after.accounts.filter { $0.name != jarName && $0.kind == .own }
                if let from = others.first(where: { delta($0) < .zero }) {
                    guard let src = work.accounts.first(where: { $0.name == from.name }) else { throw TrialError("「\(from.name)」不是正式账本里的账户") }
                    records.append(try work.deposit(goalID: g.id, amount: delta(from).magnitude, fromAccount: src.id, date: today, author: who))
                }
                let inJar = Plans.goals(work).first { $0.id == g.id }?.saved ?? .zero
                // 界面上钱放回了别的账户才转；留在原来那个账户里的（它以后就是一个普通的账户）不用动
                if inJar > .zero, let to = others.first(where: { delta($0) > .zero }) {
                    guard let dest = work.accounts.first(where: { $0.name == to.name }) else { throw TrialError("「\(to.name)」不是正式账本里的账户") }
                    records.append(try work.addAccountTransfer(amount: inJar, from: jarID, to: dest.id, date: today, bookID: g.bookID,
                                                                note: "「\(g.name)」走完了，钱放回\(dest.name)", author: who))
                }
                records.append(try work.finishGoal(g.id, today: today, author: who))
                return records
            }
            if o.saved > .zero, let jarID = g.savingsAccountID, let jarName = before.accounts.first(where: { $0.id == o.account })?.name {
                // 钱去了哪：删之后余额多了这么多的那个账户（不是它自己的账户）。没有就是留在原账户
                let to = after.accounts.first { a in
                    a.name != jarName && before.accounts.first(where: { $0.id == a.id }).map { a.balance - $0.balance == o.saved } == true
                }
                if let to {
                    guard let dest = work.accounts.first(where: { $0.name == to.name }) else { throw TrialError("「\(to.name)」不是正式账本里的账户") }
                    records.append(try work.addAccountTransfer(amount: o.saved, from: jarID, to: dest.id, date: today, bookID: g.bookID,
                                                                note: "删掉目标「\(g.name)」，里面的钱放回\(dest.name)", author: who))
                }
            }
            records.append(try work.removeGoal(g.id, author: who))
            return records
        }
        func realAccount(_ id: UUID?, in b: TrialBook) -> Account? { b.accounts.first { $0.id == id }.flatMap { a in work.accounts.first { $0.name == a.name } } }
        func realGoal(_ g: G) -> Goal? { g.big ? work.goals.first { $0.name == g.name } : work.goals.first { $0.id.uuidString == g.key } ?? work.goals.first { $0.name == g.name } }
        let lifeBook = work.books.first { !$0.isBusiness }?.id ?? work.books.first?.id ?? ""

        for n in now {
            guard let o = was.first(where: { $0.key == n.key }) else {
                // 新目标：钱单独放在哪
                guard let home = after.accounts.first(where: { $0.id == n.account }) else { throw TrialError("新目标要先选好钱放在哪个账户") }
                var accountID = work.accounts.first { $0.name == home.name }?.id
                if accountID == nil {
                    let jar = Account(id: work.newAccountID(for: home.name), name: home.name, kind: .savings)
                    records.append(try work.createAccount(jar, date: today, author: who))
                    accountID = jar.id
                }
                guard !work.goals.contains(where: { $0.savingsAccountID == accountID }) else { throw TrialError("「\(home.name)」已经是另一个目标的账户了") }
                records.append(try work.addGoal(name: n.name, bookID: lifeBook, target: n.target, savingsAccountID: accountID, main: n.big, today: today, author: who).1)
                continue
            }
            if o.big, o.name != n.name, o.saved != n.saved { throw notYet }   // 大目标换成了另一个
            guard let g = realGoal(o) else { throw TrialError("「\(o.name)」在正式账本里找不到了") }
            if o.name != n.name || o.target != n.target {
                var edited = g
                edited.name = n.name; edited.target = n.target
                records.append(try work.updateGoal(edited, author: who))
                // 为它开的存钱罐跟着改名
                if let old = realAccount(o.account, in: before), let newName = after.accounts.first(where: { $0.id == n.account })?.name, old.name != newName {
                    var acc = old; acc.name = newName
                    records.append(try work.updateAccount(acc, author: who))
                }
            }
            if n.saved > o.saved {
                // 存一笔：从余额少了这么多的那个账户，转进这个目标的账户
                let amount = n.saved - o.saved
                let fromName = after.accounts.first { a in
                    a.id != n.account && before.accounts.first(where: { $0.id == a.id }).map { $0.balance - a.balance == amount } == true
                }?.name
                guard let fromName, let from = work.accounts.first(where: { $0.name == fromName }) else { throw TrialError("没看出这笔钱是从哪个账户来的，账本没动") }
                guard g.savingsAccountID != nil else { throw TrialError("「\(g.name)」还没有自己的账户，先做一次迁移") }
                records.append(try work.deposit(goalID: g.id, amount: amount, fromAccount: from.id, date: today, author: who))
            } else if n.saved < o.saved {
                throw TrialError("从目标里拿钱出来，在接正式账本的这一版里还没接上，账本没动")
            }
        }
        guard !records.isEmpty else { throw TrialError("这一步在接正式账本的这一版里还没接上，账本没动") }
        return records
    }

    /// 两个账户之间挪了一笔钱：看两头各是什么，照正式账本里对应的写法记。
    static func applyMove(_ moved: [TrialBook.Account], was: [UUID: TrialBook.Account], to work: inout Ledger, today: LocalDate, author who: String) throws -> ChangeRecord {
        func delta(_ a: TrialBook.Account) -> Money { a.balance - (was[a.id]?.balance ?? .zero) }
        func real(_ a: TrialBook.Account) -> Account? { work.accounts.first { $0.name == (was[a.id]?.name ?? a.name) } }
        let a = moved[0], b = moved[1]
        let amount = delta(a).magnitude
        guard amount > .zero, delta(b).magnitude == amount else { throw TrialError("两个账户变的钱对不上，账本没动") }
        // 放钱的账户：少了的是转出的，多了的是转入的。欠的（信用卡、欠款）变少 = 还了这么多；借出去的变少 = 别人还了这么多
        func holds(_ x: TrialBook.Account) -> Bool { x.kind == .own || x.kind == .shop }
        let payer = moved.first { holds($0) && delta($0) < .zero }
        let receiver = moved.first { holds($0) && delta($0) > .zero }
        let paidDebt = moved.first { $0.kind == .debt && delta($0) < .zero }
        let gotBack = moved.first { $0.kind == .lent && delta($0) < .zero }
        if let payer, let receiver, let f = real(payer), let t = real(receiver) {
            // 一头是生活、一头是店里：走正式账本的「两边转钱」（从店里拿回家会算成给自己发的）
            if payer.side != receiver.side { return try work.transferBetweenSides(amount: amount, from: f.id, to: t.id, date: today, author: who) }
            return try work.addAccountTransfer(amount: amount, from: f.id, to: t.id, date: today, author: who)
        }
        if let payer, let paidDebt, let f = real(payer) {
            if let card = real(paidDebt) { return try work.addAccountTransfer(amount: amount, from: f.id, to: card.id, date: today, note: "还\(card.name)", author: who) }
            let name = was[paidDebt.id]?.name ?? paidDebt.name
            if let inst = work.installments.first(where: { $0.name == name }) { return try work.payInstallment(inst.id, amount: amount, date: today, author: who) }
            if let d = work.debts.first(where: { $0.counterparty == name && $0.direction == .iOweThem }) {
                return try work.repay(debtID: d.id, amount: amount, date: today, accountID: f.id, author: who)
            }
        }
        // 又向同一个人借了一笔：欠的变多，一个账户多了这么多
        if let receiver, let more = moved.first(where: { $0.kind == .debt && !$0.isCreditCard && delta($0) > .zero }), let t = real(receiver) {
            let name = was[more.id]?.name ?? more.name
            let book = work.books.first { !$0.isBusiness }?.id ?? work.books.first?.id ?? ""
            return try work.addDebt(counterparty: name, direction: .iOweThem, amount: amount, bookID: book, date: today, accountID: t.id, author: who).1
        }
        // 又借给同一个人一笔：借出去的变多，一个账户少了这么多
        if let payer, let more = moved.first(where: { $0.kind == .lent && delta($0) > .zero }), let f = real(payer) {
            let name = was[more.id]?.name ?? more.name
            let person = name.hasPrefix("借给") ? String(name.dropFirst(2)) : name
            let book = work.books.first { !$0.isBusiness }?.id ?? work.books.first?.id ?? ""
            return try work.addDebt(counterparty: person, direction: .theyOweMe, amount: amount, bookID: book, date: today, accountID: f.id, author: who).1
        }
        if let receiver, let gotBack, let t = real(receiver) {
            let name = was[gotBack.id]?.name ?? gotBack.name
            let person = name.hasPrefix("借给") ? String(name.dropFirst(2)) : name
            if let d = work.debts.first(where: { $0.counterparty == person && $0.direction == .theyOweMe }) {
                return try work.repay(debtID: d.id, amount: amount, date: today, accountID: t.id, author: who)
            }
        }
        throw TrialError("这样挪钱在接正式账本的这一版里还没接上，账本没动")
    }

    /// 订阅上的改动：按名字对。
    static func applySubscriptions(before: TrialBook, after: TrialBook, to work: inout Ledger, today: LocalDate, author who: String) throws -> [ChangeRecord] {
        var records: [ChangeRecord] = []
        let cycles: [Subscription.Cycle] = [.weekly, .monthly, .quarterly, .yearly]
        for n in after.subscriptions {
            guard let o = before.subscriptions.first(where: { $0.name == n.name }) else {
                // 下次扣款：新界面加订阅时不问哪天扣，先按「从今天起过一个周期」算（每周 7 天后、每月下个月今天…），以后对上流水会自己校准
                let cycle = cycles[min(max(n.cycle, 0), 3)]
                // 选了哪天扣就用那天；没选才按周期估
                let next = n.dueIn.map { today.adding(days: $0) }
                    ?? (cycle == .weekly ? today.adding(days: 7) : today.adding(months: cycle == .monthly ? 1 : cycle == .quarterly ? 3 : 12))
                // 标了「赚钱用的」又开着生意：记在生意账本上；别的记在生活账本上
                let book = (n.flag ? work.books.first { $0.isBusiness } : nil) ?? work.books.first { !$0.isBusiness }
                // 从哪个账户扣：界面上选的那个（信用卡也行）
                let charge = n.account.isEmpty ? nil : work.accounts.first { $0.name == n.account }?.id
                records.append(try work.addSubscription(Subscription(name: n.name, amount: n.amount, cycle: cycle, nextDate: next, accountID: charge,
                                                                      bookID: book?.id, note: n.note.isEmpty ? nil : n.note), author: who))
                continue
            }
            guard o.off != n.off || o.amount != n.amount, var s = work.subscriptions.first(where: { $0.name == n.name }) else { continue }
            if o.off != n.off, n.off { records.append(try work.cancelSubscription(s.id, on: today, author: who)); continue }
            s.amount = n.amount
            if !n.off { s.cancelledOn = nil }
            records.append(try work.editSubscription(s, author: who))
        }
        for o in before.subscriptions where !after.subscriptions.contains(where: { $0.name == o.name }) {
            guard let s = work.subscriptions.first(where: { $0.name == o.name }) else { continue }
            records.append(try work.removeSubscription(s.id, author: who))
        }
        return records
    }

    /// 店里每个月要还的：生意账本里欠别人的钱（有还款计划的按这个月那一期，没排计划但约了日子的按平摊）+ 还没还完的分期每期多少。
    public static func shopMonthlyRepayments(_ ledger: Ledger, today: LocalDate) -> Money {
        let biz = Set(ledger.books.filter(\.isBusiness).map(\.id))
        guard !biz.isEmpty else { return .zero }
        return monthlyRepayments(ledger, today: today, books: biz)
    }

    /// 生活这边每个月要还的：欠别人的钱这个月该还的那一期 + 没还完的分期每期多少。信用卡不在这里（它按账单还）。
    public static func lifeMonthlyRepayments(_ ledger: Ledger, today: LocalDate) -> Money {
        monthlyRepayments(ledger, today: today, books: Set(ledger.books.filter { !$0.isBusiness }.map(\.id)))
    }

    static func monthlyRepayments(_ ledger: Ledger, today: LocalDate, books biz: Set<String>) -> Money {
        var total = Money.zero
        let status = Dictionary(Plans.debts(ledger, today: today).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for d in ledger.debts where biz.contains(d.bookID) && d.direction == .iOweThem && !d.closed {
            guard let st = status[d.id], st.outstanding > .zero else { continue }
            let thisMonth = (d.plan ?? []).filter { $0.date.yearMonth == today.yearMonth }.map(\.amount.magnitude).reduce(.zero, +)
            if thisMonth > .zero { total = total + thisMonth }
            else if let next = (d.plan ?? []).filter({ $0.date >= today }).min(by: { $0.date < $1.date }) { total = total + next.amount.magnitude }
            else if let even = Plans.repaymentPlan(st, today: today) { total = total + even.perMonth }
        }
        let inst = Dictionary(Plans.installments(ledger).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in ledger.installments where biz.contains(i.bookID) {
            if let st = inst[i.id], st.remaining > .zero { total = total + min(st.perPayment, st.remaining) }
        }
        return total
    }

    /// 界面上给「店里没还完的分期」打的记号（它一期一期还，不能一次还清）。
    public static let installmentTag = "分期"
    /// 界面上给「从流水里认出来的固定开销」打的记号。
    public static let guessedTag = "认出来的"

    /// 店里自己加的固定开销：生意账本里每月自动记的支出规则。
    static func shopFixedRules(_ ledger: Ledger) -> [Recurring] {
        guard let shop = ledger.businessBook?.id else { return [] }
        return ledger.recurring.filter { $0.template.bookID == shop && $0.template.amount < .zero && $0.frequency == .monthly }
    }

    /// 店里的改动。没有店里的改动返回 nil。
    /// 接了的：记某一天按渠道收了多少（那天原来没记过的）、加一样固定开销。
    /// 固定开销：自己加的能改、能停、能拿掉；从流水里认出来的只能拿掉（记进「不算固定开销」）。
    static func applyShop(before: TrialBook, after: TrialBook, to work: inout Ledger, today: LocalDate, author who: String) throws -> [ChangeRecord]? {
        var records: [ChangeRecord] = []
        let changedDays = after.shopDays.filter { d in before.shopDays.first { $0.day == d.day }.map { $0 != d } ?? true }
        let fixedBefore = before.fixedCosts.map { "\($0.name)|\($0.amount.cents)|\($0.off)|\($0.day)|\($0.account)" }
        let fixedAfter = after.fixedCosts.map { "\($0.name)|\($0.amount.cents)|\($0.off)|\($0.day)|\($0.account)" }
        guard !changedDays.isEmpty || Set(fixedBefore) != Set(fixedAfter) else { return nil }
        for d in changedDays {
            let old = before.shopDays.first { $0.day == d.day }
            let date = day(today, minus: today.day - d.day)
            guard d.state == .open || d.state == .rest || d.state == .missing else { throw TrialError("还没到的日子记不了") }
            // 口径和整理数的时候（snapshot）一样：一天收了多少 = 这一天、生意账本里所有算收入的流水加起来，
            // 不管是「每天记账」记的还是从银行流水导进来的，按账户（渠道）合成一个数，既不漏也不重复。
            // 所以界面上改一天的数，就是把每个渠道「现在的数」改成「新的数」：
            //   导进来的那几笔从来不动；「每天记账」记的那部分改成「新的数 − 导进来的」（原来记过就删掉重记）；
            //   要是新的数比导进来的还少，得去动导进来的那笔，分不清该改哪笔，就不动并说清楚。
            let bizBooks = Set(work.books.filter(\.isBusiness).map(\.id))
            let income = work.transactions.filter { t in
                t.date == date && t.amount > .zero && t.countsAsIncomeOrExpense && !t.isTransfer && t.bookID.map(bizBooks.contains) == true
            }
            let wanted: [String: Money] = d.state == .open
                ? Dictionary(after.channels(of: d).map { ($0.account, $0.amount) }, uniquingKeysWith: +) : [:]
            var remove: [UUID] = []
            var lines: [(method: PaymentMethod, amount: Money)] = []
            let names = Set(wanted.keys).union(income.compactMap { t in work.accounts.first { $0.id == t.accountID }?.name })
            for name in names.sorted() {
                guard let acc = work.accounts.first(where: { $0.name == name }) else { throw TrialError("「\(name)」不是正式账本里的账户") }
                let rows = income.filter { $0.accountID == acc.id }
                let mine = rows.filter { $0.source == Ledger.dailySource }
                let has = rows.reduce(Money.zero) { $0 + work.baseAmount($1) }
                let daily = mine.reduce(Money.zero) { $0 + work.baseAmount($1) }
                let want = wanted[name] ?? .zero
                guard want != has else { continue }
                // 渠道就是店里的账户：有同一个账户的收款方式就用它，没有就临时用账户名当名字
                let method = work.paymentMethods.first { $0.accountID == acc.id } ?? PaymentMethod(name: acc.name, accountID: acc.id)
                // 「每天记账」记的那部分 = 新的数 − 导进来的。原来记过就删掉重记成这个数（不留两笔零碎的），没记过就新记一笔
                let imported = has - daily
                guard want >= imported else {
                    throw TrialError("\(d.day) 号「\(name)」里有 \(imported.formatted) 是从流水导进来的，这里改不到比它少。要改去流水里改那一笔。账本没动")
                }
                guard mine.allSatisfy({ work.baseAmount($0) == $0.amount }) else { throw TrialError("这一天有外币的收入，先回旧界面改") }
                remove += mine.map(\.id)
                if want > imported { lines.append((method, want - imported)) }
            }
            if !remove.isEmpty { records.append(try work.removeTransactions(remove, author: who)) }
            // 休息的日子：标上 / 取消（有收入的那天不算休息）
            if work.isShopRest(date) != (d.state == .rest) {
                records.append(try work.setShopRest(date, rest: d.state == .rest, author: who))
            }
            if !lines.isEmpty { records.append(try work.recordDailyTakings(lines, date: date, author: who)) }
        }
        for f in after.fixedCosts where !before.fixedCosts.contains(where: { $0.name == f.name }) {
            guard let acc = work.accounts.first(where: { $0.name == f.account }) else { throw TrialError("选一个店里能付钱的账户") }
            records.append(try work.addFixedCost(name: f.name, amount: f.amount, day: max(f.day, 1), accountID: acc.id, category: f.name, today: today, author: who))
        }
        // 拿掉：自己加的就把那条规则停掉；认出来的记进「不算固定开销」的名单（以后不再认）。都能撤销
        for f in before.fixedCosts where !after.fixedCosts.contains(where: { $0.name == f.name }) {
            if let r = shopFixedRules(work).first(where: { $0.template.description == f.name }) {
                records.append(try work.removeRecurring(r.id, author: who))
            } else if let g = Outlook.fixedGuesses(work, side: .business, today: today).first(where: { $0.name == f.name }) {
                records.append(work.markNotFixed(g.key, name: g.name, author: who))
            } else { throw TrialError("「\(f.name)」在正式账本里找不到了") }
        }
        // 改多少、几号、从哪扣，停一停 / 接着付：只有自己加的能改
        for f in after.fixedCosts {
            guard let o = before.fixedCosts.first(where: { $0.name == f.name }),
                  o.amount != f.amount || o.off != f.off || o.day != f.day || o.account != f.account else { continue }
            guard var r = shopFixedRules(work).first(where: { $0.template.description == f.name }) else {
                throw TrialError("「\(f.name)」是从流水里认出来的，改不了。不想算它就拿掉；想改，先拿掉再自己加一样")
            }
            guard let acc = work.accounts.first(where: { $0.name == f.account }) else { throw TrialError("选一个店里能付钱的账户") }
            r.template.amount = -f.amount
            r.template.accountID = acc.id
            r.paused = f.off
            if o.day != f.day, (1...31).contains(f.day) {
                // 换了几号付：从下一个那一天起
                func on(_ ym: YearMonth) -> LocalDate {
                    let last = LocalDate(year: ym.year, month: ym.month, day: 1).adding(months: 1).adding(days: -1).day
                    return LocalDate(year: ym.year, month: ym.month, day: min(f.day, last))
                }
                var start = on(today.yearMonth)
                if start <= today { start = on(today.yearMonth.adding(months: 1)) }
                r.start = start; r.nextDate = start; r.count = 0; r.template.date = start
            }
            records.append(try work.updateRecurring(r, author: who))
        }
        guard !records.isEmpty else { throw TrialError("这一步在接正式账本的这一版里还没接上，账本没动") }
        return records
    }
}
