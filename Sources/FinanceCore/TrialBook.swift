import Foundation

// 界面 v3 试用版用的账本：只在内存里，装的是设计稿那套编的示例。
// 所有「记、改、删、存」的规则都写在这里，界面只调用；每次写入记一条 ChangeRecord（写明作者），能撤销。
// 它不是正式账本（Ledger）的格式：v3 定稿、接上正式账本以后，这个文件就可以拿掉。

/// 做不成时说的人话。
public struct TrialError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public struct TrialBook: Equatable, Sendable {
    public enum Side: String, Sendable { case life, biz }

    public struct Account: Identifiable, Equatable, Sendable {
        public enum Kind: Sendable { case own, shop, debt, lent, secret }
        public enum Block: Sendable { case daily, emergency, goal, shop, none }
        public var id = UUID()
        public var emoji: String
        public var name: String
        /// 家底页卡片下面那行小字。
        public var note: String
        public var balance: Money
        public var kind: Kind = .own
        public var block: Block = .daily
        /// 总览小卡片上的短名字。
        public var short: String = ""
        public var label: String { short.isEmpty ? name : short }
        public var isDebt: Bool { kind == .debt }
        /// 能拿来刷的信用卡（欠款里只有它能直接付钱；分期、欠别人的不行）。
        public var isCreditCard: Bool { kind == .debt && (name.contains("信用卡") || emoji == "💳") }
        /// 属于哪一边：生活，还是店里。店里的账户也分「有的」（kind 是 shop）和「欠的」（kind 是 debt）。
        public var side: Side = .life
        /// 置顶成银行卡样子时用哪一种底色（`AccountCards.styleCount` 种里的第几种）。
        public var cardStyle: Int?
        /// 实际用的底色：自己挑过就用挑的，没挑过按种类给一个（欠的浅粉、店里的青、应急钱天蓝、目标金、其余深蓝）。
        public var cardLook: Int { cardStyle ?? (kind == .debt ? 4 : side == .biz ? 2 : block == .emergency ? 1 : block == .goal ? 3 : 0) }
        public init(id: UUID = UUID(), emoji: String, name: String, note: String, balance: Money,
                    kind: Kind = .own, block: Block = .daily, short: String = "", side: Side? = nil) {
            self.id = id; self.emoji = emoji; self.name = name; self.note = note; self.balance = balance
            self.kind = kind; self.block = block; self.short = short
            self.side = side ?? (kind == .shop ? .biz : .life)
        }
    }

    /// 一笔流水（也用来放「接下来要付的」那几行）。支出是负数。
    public struct Entry: Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var emoji: String
        public var name: String
        public var meta: String
        public var amount: Money
        public var tag: String = ""
        public var red = false
        /// 0 = 今天，1 = 昨天。
        public var daysAgo = 0
        public var side: Side = .life
        /// 店名（「以后这家店都按这一类」用）。
        public var place = ""
        public var account = ""
        public var note = ""
        /// 这一笔里有多少是在付「固定要付的」（房租、订阅这些月初就算进去了的）。这部分不再从「还能随便花」里扣第二遍。
        public var fixedPart: Money = .zero
        public init(id: UUID = UUID(), emoji: String, name: String, meta: String, amount: Money, tag: String = "",
                    red: Bool = false, daysAgo: Int = 0, side: Side = .life, place: String = "", account: String = "", note: String = "") {
            self.id = id; self.emoji = emoji; self.name = name; self.meta = meta; self.amount = amount; self.tag = tag
            self.red = red; self.daysAgo = daysAgo; self.side = side; self.place = place; self.account = account; self.note = note
        }
    }

    public struct Letter: Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var title: String
        public var quote: String
        public var date: String
        public var tag = ""
        public var headline = "你做到了。"
        public var paragraphs: [String] = []
        public var facts: [[String]] = []
        public init(id: UUID = UUID(), title: String, quote: String, date: String, tag: String = "",
                    headline: String = "你做到了。", paragraphs: [String] = [], facts: [[String]] = []) {
            self.id = id; self.title = title; self.quote = quote; self.date = date; self.tag = tag
            self.headline = headline; self.paragraphs = paragraphs; self.facts = facts
        }
    }

    /// 订阅、固定开销、进货、估值、本钱这类「名字 + 说明 + 金额」的一行。
    public struct Item: Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var emoji: String
        public var name: String
        public var note: String
        public var amount: Money
        public var tag = ""
        /// 订阅：要退；固定开销：先停着。
        public var off = false
        /// 固定开销：能不能省；订阅：赚钱要用的。
        public var flag = false
        /// 订阅多久扣一次：0 每周、1 每月、2 每三个月、3 每年。
        public var cycle = 1
        /// 固定开销：从哪个账户扣、每月几号付（0 是没填）、上个月是多少（没有就是这个月新加的或没变过）。
        public var account = ""
        public var day = 0
        public var lastMonth: Money?
        public init(id: UUID = UUID(), emoji: String, name: String, note: String, amount: Money, tag: String = "", off: Bool = false, flag: Bool = false, cycle: Int = 1,
                    account: String = "", day: Int = 0, lastMonth: Money? = nil) {
            self.id = id; self.emoji = emoji; self.name = name; self.note = note; self.amount = amount; self.tag = tag; self.off = off; self.flag = flag; self.cycle = cycle
            self.account = account; self.day = day; self.lastMonth = lastMonth
        }
        public static let cycleNames = ["每周", "每月", "每三个月", "每年"]
        /// 折成每个月多少（订阅用）。
        public var monthly: Money {
            switch cycle {
            case 0: Money(cents: amount.cents * 52 / 12)
            case 2: Money(cents: amount.cents / 3)
            case 3: Money(cents: amount.cents / 12)
            default: amount
            }
        }
        /// 一年多少（订阅用）。
        public var yearly: Money { Money(cents: amount.cents * [52, 12, 4, 1][min(max(cycle, 0), 3)]) }
    }

    /// 一个收款渠道这天收了多少。渠道 = 店里的一个账户。
    public struct ShopChannel: Equatable, Sendable, Identifiable {
        public var account: String
        public var amount: Money
        public var id: String { account }
        public init(_ account: String, _ amount: Money) { self.account = account; self.amount = amount }
    }

    /// 店里某一天收了多少。
    public struct ShopDay: Equatable, Sendable {
        public enum State: Sendable { case open, rest, missing, future }
        public var day: Int
        public var cash: Money
        public var card: Money
        public var state: State
        /// 按收款渠道分的数：渠道就是店里的账户。空着说明是老的记法（只有现金、刷卡两个总数）。
        public var parts: [ShopChannel] = []
        public var total: Money { cash + card }
        public init(day: Int, cash: Money, card: Money, state: State, parts: [ShopChannel] = []) {
            self.day = day; self.cash = cash; self.card = card; self.state = state; self.parts = parts
        }
    }

    /// 夏夏记住的一件事：一个话题，下面几行。
    public struct Memo: Identifiable, Equatable, Sendable {
        public enum Kind: Int, Sendable, CaseIterable { case rule, topic, lesson }
        public var id = UUID()
        public var kind: Kind
        public var topic: String
        public var lines: [String]
        /// 谁说的：「你说的」「你纠正的」「夏夏看出来的，你确认过」。
        public var source: String
        /// 重要：整理时不问。
        public var important = false
        public init(id: UUID = UUID(), kind: Kind, topic: String, lines: [String], source: String, important: Bool = false) {
            self.id = id; self.kind = kind; self.topic = topic; self.lines = lines; self.source = source; self.important = important
        }
    }

    public struct Category: Equatable, Sendable {
        public var emoji: String
        public var name: String
        public init(_ emoji: String, _ name: String) { self.emoji = emoji; self.name = name }
    }

    /// 管哪边：生活、生意各一个开关，至少开一个。关掉的那边只是不显示，数据不动。
    public var showLife = true
    public var showBiz = true

    /// 哪些页面属于哪一边（页面的名字和界面里的一样）。界面的导航只读这里。
    /// 导航的顺序：天天看的 → 管钱的地方 → 回头看的。组之间画一条细线。
    public static let lifeGroups = [["overview", "transactions", "spending"], ["wealth", "debts", "subscriptions", "goals"], ["trends", "monthly"]]
    public static let bizGroups = [["bizHome", "sales", "shopFlow"], ["shopWealth", "fixed", "stock", "bizDebts"], ["payback", "checkup"]]
    public static let lifePages = lifeGroups.flatMap { $0 }
    public static let bizPages = bizGroups.flatMap { $0 }

    /// 现在导航里该出现的页面（不含设置）。
    public var visiblePages: [String] { (showLife ? Self.lifePages : []) + (showBiz ? Self.bizPages : []) }

    public func shows(page: String) -> Bool {
        if Self.lifePages.contains(page) { return showLife }
        if Self.bizPages.contains(page) { return showBiz }
        return true
    }

    /// 改「管哪边」。两个都关不行。
    public mutating func setSides(life: Bool, biz: Bool) throws {
        guard life || biz else { throw TrialError("生活和生意至少管一边") }
        showLife = life; showBiz = biz
    }

    /// 两本账的名字。
    public var lifeName = "生活"
    public var shopName = "晴空小花店"
    public var categories: [Category] = [
        .init("🛒", "超市"), .init("🥗", "餐饮"), .init("☕", "咖啡"), .init("🚇", "交通"), .init("🏠", "房租"), .init("🔁", "订阅"),
        .init("💊", "看病"), .init("🎬", "娱乐"), .init("👕", "衣服"), .init("📱", "话费"), .init("🎁", "送礼"), .init("❓", "还没分"),
    ]
    /// 收入的分类。
    public static let incomeCategories: [Category] = [
        .init("💰", "工资"), .init("🎉", "奖金"), .init("💼", "兼职"), .init("↩️", "退款"), .init("🤝", "别人还我"),
        .init("🧧", "红包礼金"), .init("📦", "卖二手"), .init("🏦", "利息"), .init("❓", "其他"),
    ]
    public var smallGoals: [SmallGoal] = []
    public var memos: [Memo] = []
    // 生活
    public var accounts: [Account]
    public var entries: [Entry]
    public var upcoming: [Entry]
    public var month: FreeToSpend
    public var journey: Journey
    public var letters: [Letter]
    /// 应急钱和目标对半分：nil = 还没回答。
    public var splitWithEmergency: Bool?
    public var monthlyMust: Money
    /// 这个月到今天，一个分类花了多少（花销页的圆环和右边的列表都用它，口径只有这一份：固定要付的也算在里面）。
    public struct SpendSlice: Identifiable, Equatable, Sendable {
        public var id: String { name }
        public var emoji: String
        public var name: String
        public var amount: Money
        /// 上个月同期这个分类花了多少。
        public var lastMonth: Money
        public init(emoji: String, name: String, amount: Money, lastMonth: Money) { self.emoji = emoji; self.name = name; self.amount = amount; self.lastMonth = lastMonth }
    }
    public var spendByCategory: [SpendSlice] = []

    /// 圆环上的几段：按花得多少排，最多 `limit` 段，多出来的合成「其他」。
    public func spendSlices(limit: Int = 8) -> [SpendSlice] {
        let sorted = spendByCategory.filter { $0.amount > .zero }.sorted { $0.amount > $1.amount }
        guard sorted.count > limit, limit > 1 else { return sorted }
        let rest = sorted[(limit - 1)...]
        return Array(sorted[..<(limit - 1)]) + [SpendSlice(emoji: "❓", name: "其他", amount: rest.map(\.amount).reduce(.zero, +), lastMonth: rest.map(\.lastMonth).reduce(.zero, +))]
    }
    public var spendSliceTotal: Money { spendByCategory.map(\.amount).reduce(.zero, +) }

    /// 平时一天大概花多少（算「等于几天的花销」用）。
    public var usualDailySpend: Money = .zero
    /// 应急钱想存够几个月（1、3、6）。
    public var emergencyGoalMonths = 3
    public var subscriptions: [Item] = []
    public var wanted: [Item] = []
    /// 记住的「这家店算哪一类」：店名 → (图标, 分类名)。
    public var placeRules: [String: [String]] = [:]
    // 生意
    public var shopDays: [ShopDay] = []
    public var fixedCosts: [Item] = []
    public var purchases: [Item] = []
    public var stockEstimates: [Item] = []
    public var capital: [Item] = []
    public var shopDebts: [Item] = []
    /// 今天是这个月几号（示例：18）。
    public var todayDay = 18
    /// 示例账本里的「今天」：2026 年 11 月 18 日，周三。认「上周五」「12 号」这些时用它当今天。
    public var todayDate: Date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)) ?? Date()
    /// 店的贷款每月还多少（「一天收多少不亏」「手里实际多了」都要算它）。
    public var shopLoanMonthly: Money = .zero
    /// 这个月以前，开店本钱已经赚回来多少。
    public var shopBackBefore: Money = .zero
    public var fixedTotal: Money { fixedCosts.filter { !$0.off }.map(\.amount).reduce(.zero, +) }
    public var capitalTotal: Money { capital.map(\.amount).reduce(.zero, +) }

    public init(accounts: [Account], entries: [Entry], upcoming: [Entry], month: FreeToSpend, journey: Journey,
                letters: [Letter] = [], splitWithEmergency: Bool? = nil, monthlyMust: Money) {
        self.accounts = accounts; self.entries = entries; self.upcoming = upcoming; self.month = month
        self.journey = journey; self.letters = letters; self.splitWithEmergency = splitWithEmergency; self.monthlyMust = monthlyMust
    }

    // MARK: 现算的数

    public var today: [Entry] { entries.filter { $0.daysAgo == 0 && $0.side == .life } }
    /// 硬规则：生活和生意的账户完全分开。账户属于哪边看 `side`，生活这边的任何清单、合计都不含店里的；
    /// 只有 `transferBetweenSides`（两边转钱）能让钱跨过去。
    public func accounts(on side: Side) -> [Account] { accounts.filter { $0.side == side } }
    /// 生活这边自己手里的钱（不含店里的、私房钱）。
    public var owned: [Account] { accounts.filter { $0.side == .life && $0.kind == .own } }
    /// 生活这边欠的（店里欠的看 `shopOwed`）。
    public var debts: [Account] { accounts.filter { $0.kind == .debt && $0.side == .life } }
    public var lent: [Account] { accounts.filter { $0.kind == .lent && $0.side == .life } }
    /// 一共有：自己手里的钱 + 借出去还没收回来的（那也是你的钱；店里「别人欠店的」同样算进店的家底）。
    public var totals: HouseholdTotals { HouseholdTotals(holdings: owned.map(\.balance) + lent.map(\.balance), debts: debts.map(\.balance)) }
    /// 自己手里的钱（不含借出去的）。
    public var inHand: Money { owned.map(\.balance).reduce(.zero, +) }
    /// 家底分成几块：存在目标里、存着不动（储蓄）、日常能用（日常的卡和现金）、借出去的。加起来 = 一共有。是 0 的那块不列。
    public var wealthBlocks: [(name: String, amount: Money)] {
        [("存在目标里", sum(.goal)), ("存着不动", sum(.emergency)), ("日常能用", sum(.daily)), ("借出去的", lent.map(\.balance).reduce(.zero, +))].filter { $0.1 > .zero }
    }
    public func sum(_ block: Account.Block) -> Money { owned.filter { $0.block == block }.map(\.balance).reduce(.zero, +) }
    public var runway: EmergencyRunway { EmergencyRunway(fund: sum(.emergency), monthlyMust: monthlyMust) }
    /// 平时一个月大概花多少：固定要付的 + 平时每天花的 × 30。不用谁来设。
    public var usualMonthlySpend: Money { month.fixed + Money(cents: usualDailySpend.cents * 30) }
    /// 手里的钱（不含存在目标里的）按平时每月花，够撑几个月。自动算，没有设置。
    public var handRunway: EmergencyRunway { EmergencyRunway(fund: inHand - sum(.goal), monthlyMust: usualMonthlySpend) }
    public func account(_ name: String) -> Account? { accounts.first { $0.name == name } }
    /// 能拿来付钱的账户（自己的、店里的；不含欠款、借出、私房钱）。
    public func payable(_ side: Side) -> [Account] {
        accounts.filter { $0.side == side && (side == .biz ? $0.kind == .shop : ($0.kind == .own && $0.block == .daily)) }
    }
    public var shopSalesTotal: Money { shopDays.filter { $0.state == .open }.map(\.total).reduce(.zero, +) }
    public var shopOpenDays: Int { shopDays.filter { $0.state == .open }.count }

    /// 选账户时的用途。各处的账户清单都从这里取，页面里不写死。
    public enum AccountUse: Sendable { case pay, receive, moveOut, moveIn }

    /// 这一边、这个用途能选的账户。
    /// - 付钱：生活是日常的账户（卡、现金、自己加的）加信用卡；生意是店里的账户。储蓄 / 应急钱、目标罐、分期、欠别人的不能直接付钱。
    /// - 收钱：生活是日常的账户；生意是店里的账户。
    /// - 转出、转入：见 `transferSources` / `transferTargets`。
    public func accounts(for use: AccountUse, side: Side = .life) -> [Account] {
        switch use {
        case .pay:
            if side == .biz { return accounts.filter { $0.side == .biz && ($0.kind == .shop || $0.isCreditCard) } }
            return accounts.filter { $0.side == .life && (($0.kind == .own && $0.block == .daily) || $0.isCreditCard) }
        case .receive:
            return payable(side)
        case .moveOut: return transferSources(side)
        case .moveIn: return transferTargets(side)
        }
    }

    private func index(_ name: String) throws -> Int {
        guard let i = accounts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这个账户") }
        return i
    }

    private static func positive(_ amount: Money, _ what: String = "金额") throws {
        guard amount > .zero else { throw TrialError("\(what)要比 0 大") }
    }

    // MARK: 记一笔、改、删

    /// 记一笔支出或收入。店名记过分类的，按记住的来。
    @discardableResult
    public mutating func record(name: String, emoji: String, amount: Money, income: Bool = false, account: String,
                                place: String = "", tag: String = "刚记的", daysAgo: Int = 0, side: Side = .life, note: String = "") throws -> Entry {
        try Self.positive(amount)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下是什么") }
        let i = try index(account)
        guard accounts[i].side == side else {
            throw TrialError(side == .life ? "「\(account)」是店里的账户，生活的账记不到它上面" : "「\(account)」是生活这边的账户，店里的账记不到它上面")
        }
        var useName = clean, useEmoji = emoji
        if let rule = placeRules[place], rule.count == 2 { useEmoji = rule[0]; useName = rule[1] }
        if accounts[i].kind == .debt {
            // 刷信用卡：欠的变多
            guard !income else { throw TrialError("钱不能进到「\(account)」里，换一个账户") }
            accounts[i].balance = accounts[i].balance + amount
        } else {
            accounts[i].balance = income ? accounts[i].balance + amount : accounts[i].balance - amount
        }
        var e = Entry(emoji: useEmoji, name: useName, meta: (place.isEmpty ? "" : place + " · ") + account,
                      amount: income ? amount : -amount, tag: tag, daysAgo: daysAgo, side: side, place: place, account: account, note: note)
        count(&e)
        entries.insert(e, at: 0)
        return e
    }

    // MARK: 一笔流水怎么算进这个月（只有这一处；记、删、改分类、改金额、导入都走它）

    /// 这一笔算不算这个月生活的收支：生活这边的、日子落在这个月里的。
    private func inThisMonth(_ e: Entry) -> Bool { e.side == .life && e.daysAgo >= 0 && e.daysAgo < todayDay }

    private mutating func addSlice(_ name: String, _ emoji: String, _ delta: Money) {
        guard delta != .zero else { return }
        if let i = spendByCategory.firstIndex(where: { $0.name == name }) {
            spendByCategory[i].amount = max(spendByCategory[i].amount + delta, .zero)
        } else if delta > .zero {
            spendByCategory.append(SpendSlice(emoji: emoji, name: name, amount: delta, lastMonth: .zero))
        }
    }

    /// 把一笔算进这个月：进账加到进账；支出先对「固定要付的」（房租、订阅这类月初已经算过的，不扣第二遍），
    /// 对不上的部分才算平时花的，同时加到那一类的花销里。所以「这个月花掉」= 固定要付的 + 平时花的 = 各分类加起来，永远对得上。
    private mutating func count(_ e: inout Entry) {
        e.fixedPart = .zero
        guard inThisMonth(e) else { return }
        if e.amount > .zero { month.income = month.income + e.amount; return }
        let a = e.amount.magnitude
        let room = max((fixedPlan[e.name] ?? .zero) - (fixedPaid[e.name] ?? .zero), .zero)
        let matched = min(a, room)
        if matched > .zero { fixedPaid[e.name] = (fixedPaid[e.name] ?? .zero) + matched; e.fixedPart = matched }
        let rest = a - matched
        month.spent = month.spent + rest
        addSlice(e.name, e.emoji, rest)
    }

    /// 把一笔从这个月里拿掉（`count` 的反过来）。
    private mutating func uncount(_ e: Entry) {
        guard inThisMonth(e) else { return }
        if e.amount > .zero { month.income = month.income - e.amount; return }
        if e.fixedPart > .zero { fixedPaid[e.name] = max((fixedPaid[e.name] ?? .zero) - e.fixedPart, .zero) }
        let rest = e.amount.magnitude - e.fixedPart
        month.spent = max(month.spent - rest, .zero)
        addSlice(e.name, e.emoji, .zero - rest)
    }

    /// 删一笔：钱回到账户，「还能随便花」跟着回去。
    @discardableResult
    public mutating func delete(entry id: UUID) throws -> Entry {
        guard let k = entries.firstIndex(where: { $0.id == id }) else { throw TrialError("这一笔已经不在了") }
        let e = entries.remove(at: k)
        if let i = accounts.firstIndex(where: { $0.name == e.account }) {
            accounts[i].balance = accounts[i].kind == .debt ? accounts[i].balance + e.amount : accounts[i].balance - e.amount
        }
        uncount(e)
        return e
    }

    /// 改分类。`always`：以后这家店都按这一类。
    public mutating func recategorize(entry id: UUID, emoji: String, name: String, always: Bool) throws {
        guard let k = entries.firstIndex(where: { $0.id == id }) else { throw TrialError("这一笔已经不在了") }
        let place = entries[k].place.isEmpty ? entries[k].name : entries[k].place
        entries[k].place = place
        entries[k].meta = entries[k].account.isEmpty ? place : "\(place) · \(entries[k].account)"
        if entries[k].tag == "等你看一眼" { entries[k].tag = "你认的" }
        if always { placeRules[place] = [emoji, name] }
        // 这一笔（和「以后都这样」时同一家店的那几笔）：先从原来那一类里拿出来，再算进新的一类
        for j in entries.indices where j == k || (always && entries[j].place == place) {
            let was = entries[j]
            uncount(was)
            var e = was
            e.emoji = emoji; e.name = name
            count(&e)
            entries[j] = e
        }
    }

    /// 改金额（传正数；支出还是支出，收入还是收入）。
    public mutating func setAmount(entry id: UUID, to amount: Money) throws {
        try Self.positive(amount)
        guard let k = entries.firstIndex(where: { $0.id == id }) else { throw TrialError("这一笔已经不在了") }
        let old = entries[k].amount
        let new = old.cents < 0 ? -amount : amount
        let diff = new - old
        let was = entries[k]
        uncount(was)
        var e = was
        e.amount = new
        count(&e)
        entries[k] = e
        if let i = accounts.firstIndex(where: { $0.name == entries[k].account }) {
            accounts[i].balance = accounts[i].kind == .debt ? accounts[i].balance - diff : accounts[i].balance + diff
        }
    }

    /// 自己两个账户之间挪钱：不算花也不算赚。
    public mutating func move(_ amount: Money, from: String, to: String) throws {
        try Self.positive(amount)
        guard from != to else { throw TrialError("两边选了同一个账户") }
        let f = try index(from), t = try index(to)
        guard accounts[f].side == accounts[t].side else { throw TrialError("生活和店里的钱是分开的，要挪请用「两边转钱」") }
        guard accounts[f].balance >= amount else { throw TrialError("\(from)里只有 \(accounts[f].balance.formatted)") }
        accounts[f].balance = accounts[f].balance - amount
        accounts[t].balance = accounts[t].balance + amount
    }

    /// 导入一份流水（试用版：示例的几笔）。同一天、同一家店、同一金额的算重复，跳过。返回新进来几笔、跳过几笔。
    @discardableResult
    public mutating func importEntries(_ rows: [Entry]) throws -> (added: Int, skipped: Int) {
        guard !rows.isEmpty else { throw TrialError("这份流水里一笔都没有") }
        var added = 0, skipped = 0
        for r in rows {
            if entries.contains(where: { $0.daysAgo == r.daysAgo && $0.place == r.place && $0.amount == r.amount }) { skipped += 1; continue }
            var e = r
            e.id = UUID(); e.tag = "流水导入"
            count(&e)
            entries.append(e)
            added += 1
        }
        guard added > 0 else { throw TrialError("这 \(skipped) 笔都导过了，没有新的") }
        entries.sort { $0.daysAgo < $1.daysAgo }
        return (added, skipped)
    }

    // MARK: 账本、账户、分类的管理

    public mutating func renameBook(_ side: Side, to name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("账本要有个名字") }
        guard clean.count <= 20 else { throw TrialError("名字短一点，20 个字以内") }
        if side == .life { lifeName = clean } else { shopName = clean }
    }

    /// 改账户：名字、现在有多少、是不是私房钱。流水里记的账户名跟着改。
    public mutating func editAccount(_ name: String, newName: String, balance: Money, secret: Bool) throws {
        let i = try index(name)
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先给它起个名字") }
        guard clean == name || !accounts.contains(where: { $0.name == clean }) else { throw TrialError("已经有一个叫「\(clean)」的账户了") }
        guard balance >= .zero else { throw TrialError("这里填正数就行") }
        if secret != (accounts[i].kind == .secret) {
            guard accounts[i].kind == .own || accounts[i].kind == .secret else { throw TrialError("只有自己的账户能标成私房钱") }
            guard accounts[i].block != .goal, accounts[i].block != .emergency else { throw TrialError("目标罐和应急钱不能标成私房钱") }
            accounts[i].kind = secret ? .secret : .own
            accounts[i].block = secret ? .none : .daily
        }
        accounts[i].name = clean
        accounts[i].balance = balance
        // 目标已存 = 这个账户的余额：改了余额，目标跟着变
        if accounts[i].id == bigGoalAccount { journey.saved = balance }
        if let k = smallGoals.firstIndex(where: { $0.account == accounts[i].id }) { smallGoals[k].saved = balance }
        if clean != name {
            for k in entries.indices where entries[k].account == name {
                entries[k].account = clean
                entries[k].meta = entries[k].place.isEmpty ? clean : "\(entries[k].place) · \(clean)"
            }
        }
    }

    /// 删账户：里面还有流水时不能删。
    public mutating func removeAccount(_ name: String) throws {
        let i = try index(name)
        let n = entries.filter { $0.account == name }.count
        guard n == 0 else { throw TrialError("「\(name)」里还有 \(n) 笔流水，先把流水删掉或改到别的账户") }
        guard accounts[i].block != .goal, accounts[i].block != .emergency else { throw TrialError("「\(name)」别的地方还在用，不能删") }
        guard accounts[i].kind != .shop || shopHeld.count > 1 else { throw TrialError("店里至少留一个放钱的账户") }
        accounts.remove(at: i)
        upcoming.removeAll { $0.name == name }
    }

    public func entryCount(category name: String) -> Int { entries.filter { $0.name == name }.count }

    /// 改分类的名字或图标。改成一个已有的名字，就是把两个并成一个，流水一起改。
    public mutating func editCategory(_ name: String, newName: String, emoji: String) throws {
        guard let i = categories.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这个分类") }
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("分类要有个名字") }
        var useEmoji = emoji
        if clean != name, let other = categories.firstIndex(where: { $0.name == clean }) {
            useEmoji = categories[other].emoji
            categories.remove(at: i)
        } else {
            categories[i] = Category(emoji, clean)
        }
        for k in entries.indices where entries[k].name == name { entries[k].name = clean; entries[k].emoji = useEmoji }
        for (place, rule) in placeRules where rule.count == 2 && rule[1] == name { placeRules[place] = [useEmoji, clean] }
    }

    public mutating func addCategory(emoji: String, name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("分类要有个名字") }
        guard !categories.contains(where: { $0.name == clean }) else { throw TrialError("已经有「\(clean)」这个分类了") }
        categories.insert(Category(emoji, clean), at: max(categories.count - 1, 0))
    }

    // MARK: 夏夏的记忆

    /// 记一条。已经有这个话题，就加在它下面，不另开一条。返回是不是加在了已有的话题下面。
    @discardableResult
    public mutating func remember(_ kind: Memo.Kind, topic: String, line: String, source: String = "你说的") throws -> Bool {
        let t = topic.trimmingCharacters(in: .whitespacesAndNewlines), l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw TrialError("先写一下话题，比如「工资」") }
        guard !l.isEmpty else { throw TrialError("要记住什么？写一句就行") }
        guard l.count <= 200 else { throw TrialError("写短一点，200 个字以内") }
        if let i = memos.firstIndex(where: { $0.topic == t }) {
            guard !memos[i].lines.contains(l) else { throw TrialError("这句已经记过了") }
            memos[i].lines.append(l)
            return true
        }
        memos.insert(Memo(kind: kind, topic: t, lines: [l], source: source), at: 0)
        return false
    }

    public mutating func removeMemo(_ id: UUID) throws {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { throw TrialError("这一条已经不在了") }
        memos.remove(at: i)
    }

    public mutating func setMemo(_ id: UUID, important: Bool? = nil, kind: Memo.Kind? = nil) throws {
        guard let i = memos.firstIndex(where: { $0.id == id }) else { throw TrialError("这一条已经不在了") }
        if let important { memos[i].important = important }
        if let kind { memos[i].kind = kind }
    }

    // MARK: 删除数据

    /// 一共有多少笔流水、多少个计划、多少个订阅（删除前给人看的）。
    public var counts: (entries: Int, plans: Int, subscriptions: Int) {
        (entries.count + shopDays.filter { $0.state == .open }.count + purchases.count,
         (journey.total > .zero ? 1 : 0) + debts.count + lent.count + shopDebts.count, subscriptions.count)
    }

    public var isEmpty: Bool { entries.isEmpty && subscriptions.isEmpty && journey.total == .zero && shopSalesTotal == .zero }

    /// 删掉全部数据：流水、目标、欠款、订阅都没了；账本和账户留着，里面的钱归零。记忆和设置不动。
    public mutating func wipe() {
        entries = []; upcoming = []; subscriptions = []; wanted = []; letters = []; placeRules = [:]
        accounts.removeAll { $0.kind == .debt || $0.kind == .lent }
        for i in accounts.indices { accounts[i].balance = .zero; accounts[i].note = "" }
        month = FreeToSpend(income: .zero, fixed: .zero, forGoals: .zero, spent: .zero, daysLeft: month.daysLeft)
        journey = Journey(name: "", why: "", stations: [], saved: .zero, monthlyPlan: .zero)
        monthlyMust = .zero; splitWithEmergency = nil; usualDailySpend = .zero; spendByCategory = []
        for i in shopDays.indices where shopDays[i].state == .open || shopDays[i].state == .rest {
            shopDays[i] = ShopDay(day: shopDays[i].day, cash: .zero, card: .zero, state: shopDays[i].day <= todayDay ? .missing : .future)
        }
        fixedCosts = []; purchases = []; stockEstimates = []; capital = []; shopDebts = []; nextGoals = []; smallGoals = []
    }

    /// 这一边能把钱转出去的账户：生活是自己的钱（不含目标罐、私房钱）；生意是店里放钱的账户。两边不混。
    public func transferSources(_ side: Side = .life) -> [Account] {
        accounts.filter { $0.side == side && (side == .biz ? $0.kind == .shop : ($0.kind == .own && $0.block != .goal)) }
    }
    /// 这一边能把钱转进去的账户：上面那些，加上目标罐和这一边欠着的（转给欠款就是还款）。
    public func transferTargets(_ side: Side = .life) -> [Account] {
        accounts.filter { $0.side == side && ((side == .biz ? $0.kind == .shop : $0.kind == .own) || ($0.kind == .debt && $0.balance > .zero)) }
    }

    /// 这一边能不能转账：能转出、能转进的账户合起来至少要有 2 个。只有一个账户时界面上不出现「转账」。
    public func canTransfer(on side: Side) -> Bool {
        let outs = transferSources(side)
        return !outs.isEmpty && Set((outs + transferTargets(side)).map(\.name)).count >= 2
    }

    /// 两边都开着时，转账的「到」末尾多出来的那一组：对面那一边放钱的账户（生活看到「店里的」，店里看到「生活的」）。
    public func crossTargets(from side: Side) -> [Account] {
        guard showLife, showBiz else { return [] }
        return side == .life ? shopHeld : accounts.filter { $0.side == .life && $0.kind == .own && $0.block == .daily }
    }

    /// 转账弹窗用的一个入口：同一边就是普通转账；跨到对面那一边的，走「两边转钱」那条唯一的路。
    @discardableResult
    public mutating func transferAny(_ amount: Money, from: String, to: String) throws -> [Journey.Station] {
        guard let f = account(from), let t = account(to) else { throw TrialError("没找到要转的账户") }
        if f.side == t.side { return try transfer(amount, from: from, to: to) }
        guard crossTargets(from: f.side).contains(where: { $0.name == to }), transferSources(f.side).contains(where: { $0.name == from }) else {
            throw TrialError("生活和店里之间，只能在两边放钱的账户之间转")
        }
        let toHome = f.side == .biz
        try transferBetweenSides(amount, toHome: toHome, shopAccount: toHome ? from : to, homeAccount: toHome ? to : from)
        return []
    }

    /// 转账：从一个账户到另一个。到目标罐算存一笔，到欠款算还款，别的就是两个账户之间挪。都不算花也不算赚。
    /// 返回刚到的站（只有存进目标罐时才可能有）。
    @discardableResult
    public mutating func transfer(_ amount: Money, from: String, to: String) throws -> [Journey.Station] {
        try Self.positive(amount)
        guard from != to else { throw TrialError("从和到选了同一个账户") }
        guard let source = accounts.first(where: { $0.name == from }), transferSources(source.side).contains(where: { $0.name == from }) else { throw TrialError("不能从「\(from)」转出去") }
        guard let target = accounts.first(where: { $0.name == to }) else { throw TrialError("不能转进「\(to)」") }
        guard target.side == source.side else { throw TrialError("生活和店里的钱是分开的，要挪请用「两边转钱」") }
        guard transferTargets(source.side).contains(where: { $0.name == to }) else { throw TrialError("不能转进「\(to)」") }
        if target.kind == .debt { try repay(debt: to, amount: amount, from: from); return [] }
        if target.block == .goal {
            if target.id == bigGoalAccount { return try deposit(amount, from: from) }
            guard let g = smallGoals.first(where: { $0.account == target.id }) else { throw TrialError("「\(to)」不是哪个目标的账户") }
            try depositSmall(g.id, amount: amount, from: from)
            return []
        }
        try move(amount, from: from, to: to)
        return []
    }

    /// 常用的几种转法：存进储蓄、还信用卡、取现金、放进目标罐。账本里有对应的账户才给。
    public var transferShortcuts: [(title: String, from: String, to: String)] {
        guard let main = owned.first(where: { $0.block == .daily && !$0.name.contains("现金") })?.name else { return [] }
        var out: [(String, String, String)] = []
        if let s = owned.first(where: { ($0.block == .emergency || $0.name.contains("储蓄")) && $0.name != main }) { out.append(("存进\(s.name)", main, s.name)) }
        if let d = accounts.first(where: { $0.kind == .debt && $0.side == .life && $0.balance > .zero && $0.name.contains("信用卡") }) { out.append(("还\(d.name)", main, d.name)) }
        if let c = owned.first(where: { $0.name.contains("现金") }) { out.append(("取现金", main, c.name)) }
        if let g = accounts.first(where: { $0.id == bigGoalAccount }), journey.total > .zero { out.append(("放进\(g.name)", main, g.name)) }
        return out
    }

    // MARK: 目标

    /// 存一笔进目标：从 `from` 挪到目标罐（答应过对半分就一半进应急钱）。返回刚到的站。
    @discardableResult
    public mutating func deposit(_ amount: Money, from: String? = nil, resisted: Bool = false) throws -> [Journey.Station] {
        try Self.positive(amount, "存的钱")
        let source = from ?? accounts.first { $0.block == .daily && $0.kind == .own }?.name ?? ""
        let i = try index(source)
        guard accounts[i].balance >= amount else { throw TrialError("\(source)里只有 \(accounts[i].balance.formatted)") }
        // 存一笔就是从日常能用的账户转到这个目标自己的账户：不算花销
        guard journey.total > .zero, let g = accounts.firstIndex(where: { $0.id == bigGoalAccount }) else { throw TrialError("还没有大目标，先去定一个") }
        guard g != i else { throw TrialError("不能从目标自己的账户存进去") }
        guard accounts[i].block != .goal else { throw TrialError("「\(source)」是另一个目标的钱，不能直接挪") }
        accounts[i].balance = accounts[i].balance - amount
        accounts[g].balance = accounts[g].balance + amount
        let reached = journey.deposit(amount)
        if resisted { journey.resisted += 1 }
        return reached
    }

    /// 从头定一个目标：拆成四站（一成、四分之一、一半、四分之三）再到终点。钱放哪：新开一个存钱罐，或者放进一个已有的「存起来的」账户。
    public mutating func startGoal(name: String, total: Money, place: GoalPlace = .newJar) throws {
        try Self.positive(total, "目标的钱")
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下想要什么") }
        guard journey.total == .zero else { throw TrialError("已经有一个目标在走了") }
        guard !smallGoals.contains(where: { $0.name == clean }) else { throw TrialError("已经有「\(clean)」这个目标了") }
        guard total.cents >= 20_00 else { throw TrialError("目标至少 20 €") }
        let stops = [10, 25, 50, 75, 100].map { Money(cents: total.cents * Int64($0) / 100 / 100 * 100) }
        let home = try placeGoal(clean, place)
        // 已有账户里原来的钱，算这个目标已经存的
        journey = Journey(name: clean, stops: stops, saved: home.saved)
        bigGoalAccount = home.id; bigGoalOwnsAccount = home.owned
    }

    public mutating func setMonthlyPlan(_ plan: Money) throws {
        try Self.positive(plan, "每月存的钱")
        journey.monthlyPlan = plan
        month.forGoals = plan
    }

    // MARK: 账户、欠款

    public mutating func addAccount(emoji: String, name: String, note: String, balance: Money, kind: Account.Kind) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先给它起个名字") }
        guard !accounts.contains(where: { $0.name == clean }) else { throw TrialError("已经有一个叫「\(clean)」的账户了") }
        guard balance >= .zero else { throw TrialError("这里填正数就行") }
        guard kind != .shop else { throw TrialError("店里的账户到生意那边的「店的家底」里加") }
        accounts.append(Account(emoji: emoji, name: clean, note: note, balance: balance, kind: kind, block: kind == .own ? .daily : .none))
    }

    /// 还一笔欠款：从 `from` 出钱，欠的减少。还清了就从「接下来要付的」里拿掉。
    public mutating func repay(debt name: String, amount: Money, from: String) throws {
        try Self.positive(amount, "还的钱")
        let d = try index(name)
        guard accounts[d].kind == .debt else { throw TrialError("「\(name)」不是欠款") }
        guard amount <= accounts[d].balance else { throw TrialError("\(name)只欠 \(accounts[d].balance.formatted)，不用还这么多") }
        let f = try index(from)
        guard accounts[f].side == accounts[d].side else { throw TrialError("生活和店里的钱是分开的，「\(name)」不能用「\(from)」来还") }
        guard accounts[f].balance >= amount else { throw TrialError("\(from)里只有 \(accounts[f].balance.formatted)") }
        accounts[f].balance = accounts[f].balance - amount
        accounts[d].balance = accounts[d].balance - amount
        if accounts[d].balance == .zero {
            accounts[d].note = "还清了"
            upcoming.removeAll { $0.name == name }
        }
    }

    /// 记一笔欠款：我欠别人（debt）或别人欠我（lent）。
    public mutating func addDebt(name: String, amount: Money, owedToMe: Bool, note: String) throws {
        try Self.positive(amount)
        try addAccount(emoji: owedToMe ? "🧑" : "🤝", name: name, note: note.isEmpty ? (owedToMe ? "他欠我" : "欠的钱") : note,
                       balance: amount, kind: owedToMe ? .lent : .debt)
    }

    /// 记一笔分期：一共多少、分几期、已经还了几期。欠的是还没还的那部分，每期的钱排进「接下来要付的」。
    public mutating func addInstallment(name: String, total: Money, periods: Int, paid: Int, day: Int, from: String = "") throws {
        try Self.positive(total)
        guard (2...60).contains(periods) else { throw TrialError("分期填 2 到 60 期") }
        guard (0..<periods).contains(paid) else { throw TrialError("已经还的期数要比总期数少") }
        guard (1...28).contains(day) else { throw TrialError("每月几号扣，填 1 到 28") }
        guard from.isEmpty || accounts(for: .pay, side: .life).contains(where: { $0.name == from && $0.kind == .own }) else { throw TrialError("选一个自己能付钱的账户来扣") }
        let each = Money(cents: total.cents / Int64(periods))
        let left = total - Money(cents: each.cents * Int64(paid))
        try addAccount(emoji: "🧾", name: name, note: "欠 · 还剩 \(periods - paid) 期，每月 \(each.formatted)", balance: left, kind: .debt)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        upcoming.append(Entry(emoji: "🧾", name: clean, meta: "12 月 \(day) 日 · 第 \(paid + 1) / \(periods) 期" + (from.isEmpty ? "" : " · \(from)"), amount: each, red: true, account: from))
    }

    /// 排在现在这个目标后面的下一个目标（大决定页「存成一个目标」）。
    public var nextGoals: [Item] = []
    /// 置顶成卡片的账户，按卡片排里的先后。生活、店里各一排；空着时默认置顶第一个日常能用的。
    public var finishedGoals: [FinishedGoal] = []
    /// 固定要付的，每一类这个月计划多少（房租 650、订阅 42…），加起来就是 `month.fixed`。月初就整个算进「花掉」里了。
    public var fixedPlan: [String: Money] = [:]
    /// 这个月每一类已经手记 / 导入付掉了多少（对上了计划的那部分）。
    public var fixedPaid: [String: Money] = [:]
    /// 手动标过的：这笔算不算意外开销（标过的说了算，没标的按规则）。
    public var surpriseMarks: [UUID: Bool] = [:]
    /// 大目标的钱放在哪个账户（一个目标对一个账户）。没有大目标时是 nil。
    public var bigGoalAccount: UUID?
    /// 大目标的账户是不是为它新开的存钱罐（是的话，目标没了账户跟着删；用的已有账户就留着）。
    public var bigGoalOwnsAccount = true
    /// 夏夏主动提醒过什么（哪件事、几天前、是出了卡还是存到晚上）。
    public var reminderLog: [ReminderEntry] = []
    /// 用户关掉的那几类提醒。
    public var mutedReminders: Set<String> = []
    /// 过去那些月份存下来的数（这个月的不在这里，是现算的）。
    public var pastMonths: [MonthData] = []
    public var lifePins: [UUID] = []
    public var shopPins: [UUID] = []

    public mutating func queueGoal(name: String, total: Money) throws {
        try Self.positive(total, "目标的钱")
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下目标叫什么") }
        guard clean != journey.name, !nextGoals.contains(where: { $0.name == clean }) else { throw TrialError("已经有「\(clean)」这个目标了") }
        if journey.total == .zero { try startGoal(name: clean, total: total); return }
        nextGoals.append(Item(emoji: "🧭", name: clean, note: "排在「\(journey.name)」后面", amount: total))
    }

    /// 改开店本钱的总数。细项加起来对不上时，合成一行。
    public mutating func setCapitalTotal(_ total: Money) throws {
        try Self.positive(total, "本钱")
        guard total != capitalTotal else { throw TrialError("和现在的一样，没有要改的") }
        capital = [Item(emoji: "💰", name: "开店本钱", note: "一共投的", amount: total)]
    }

    // MARK: 订阅、想要清单

    public mutating func addSubscription(name: String, amount: Money, note: String, forWork: Bool, cycle: Int = 1) throws {
        try Self.positive(amount)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下订阅叫什么") }
        guard !subscriptions.contains(where: { $0.name == clean }) else { throw TrialError("已经有「\(clean)」这个订阅了") }
        guard (0...3).contains(cycle) else { throw TrialError("多久扣一次没选对") }
        subscriptions.append(Item(emoji: "🔁", name: clean, note: note, amount: amount, tag: forWork ? "赚钱用的" : "", flag: forWork, cycle: cycle))
    }

    public mutating func setSubscription(_ name: String, dropped: Bool) throws {
        guard let i = subscriptions.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这个订阅") }
        subscriptions[i].off = dropped
    }

    public var subscriptionsMonthly: Money { subscriptions.filter { !$0.off }.map(\.monthly).reduce(.zero, +) }

    public mutating func removeWanted(_ id: UUID) throws {
        guard let i = wanted.firstIndex(where: { $0.id == id }) else { throw TrialError("清单里没有这一样了") }
        wanted.remove(at: i)
    }

    // MARK: 店的家底

    /// 店里的账户：有的（现金、银行卡、收款机里没结的、储蓄）和欠的（信用卡、贷款、欠供应商的）。
    public var shopAccounts: [Account] { accounts.filter { $0.side == .biz } }
    public var shopHeld: [Account] { accounts.filter { $0.side == .biz && $0.kind == .shop } }
    public var shopOwedAccounts: [Account] { accounts.filter { $0.side == .biz && $0.kind == .debt } }

    /// 店里一共值多少 = 手里的现金和账户 + 压在货上的 + 别人欠店的 − 店欠别人的。
    public struct ShopWorth: Equatable, Sendable {
        public var cash: Money       // 手里的现金和账户
        public var stock: Money      // 压在货上的（最近一次估的）
        public var owedToShop: Money // 别人欠店的
        public var owes: Money       // 店欠别人的（信用卡、贷款、欠供应商的）
        public var monthlyFixed: Money
        public var net: Money { cash + stock + owedToShop - owes }
        /// 手里的钱够付几个月的固定开销。
        public var months: Double { monthlyFixed > .zero ? Double(cash.cents) / Double(monthlyFixed.cents) : 0 }
        public var monthsText: String { let t = Int((months * 10).rounded()); return "\(t / 10),\(t % 10)" }
    }

    public var shopWorth: ShopWorth {
        ShopWorth(cash: shopHeld.map(\.balance).reduce(.zero, +),
                  stock: stockEstimates.first?.amount ?? .zero,
                  owedToShop: shopDebts.filter { $0.flag && !$0.off }.map(\.amount).reduce(.zero, +),
                  owes: shopOwedAccounts.map(\.balance).reduce(.zero, +) + shopDebts.filter { !$0.flag && !$0.off }.map(\.amount).reduce(.zero, +),
                  monthlyFixed: fixedTotal)
    }

    /// 给店里加一个账户。`owes`：信用卡、贷款、欠供应商的这类。
    public mutating func addShopAccount(emoji: String, name: String, balance: Money, owes: Bool) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先给它起个名字") }
        guard !accounts.contains(where: { $0.name == clean }) else { throw TrialError("已经有一个叫「\(clean)」的账户了") }
        guard balance >= .zero else { throw TrialError("这里填正数就行") }
        accounts.append(Account(emoji: emoji, name: clean, note: owes ? "店里欠的" : "店里的", balance: balance, kind: owes ? .debt : .shop, block: owes ? .none : .shop, side: .biz))
    }

    // MARK: 小目标（1 个大目标 + 最多 3 个小目标，规则和正式版 PiggyBank.swift 里的一样）

    public struct SmallGoal: Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var name: String
        public var target: Money
        public var saved: Money
        /// 想哪天前存够（一句话，比如「明年 3 月」；可以空着）。
        public var due: String
        /// 这个目标的钱放在哪个账户，是不是为它新开的存钱罐。
        public var account: UUID?
        public var ownsAccount = true
        public var isDone: Bool { saved >= target }
        public var fraction: Double { target > .zero ? min(1, Double(saved.cents) / Double(target.cents)) : 0 }
        public init(id: UUID = UUID(), name: String, target: Money, saved: Money = .zero, due: String = "") {
            self.id = id; self.name = name; self.target = target; self.saved = saved; self.due = due
        }
    }

    /// 还在存的小目标有几个（存够了的不算）。
    public var activeSmallGoals: [SmallGoal] { smallGoals.filter { !$0.isDone } }
    public var canAddSmallGoal: Bool { activeSmallGoals.count < Plans.maxSmallGoals }

    public mutating func addSmallGoal(name: String, target: Money, due: String = "", place: GoalPlace = .newJar) throws {
        try Self.positive(target, "目标的钱")
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下想要什么") }
        guard clean != journey.name, !smallGoals.contains(where: { $0.name == clean }) else { throw TrialError("已经有「\(clean)」这个目标了") }
        guard canAddSmallGoal else { throw TrialError(Plans.goalLimitSentence + "先完成或删掉一个。") }
        let home = try placeGoal(clean, place)
        var g = SmallGoal(name: clean, target: target, saved: home.saved, due: due.trimmingCharacters(in: .whitespaces))
        g.account = home.id; g.ownsAccount = home.owned
        smallGoals.append(g)
    }

    public mutating func editSmallGoal(_ id: UUID, name: String, target: Money, due: String) throws {
        try Self.positive(target, "目标的钱")
        guard let i = smallGoals.firstIndex(where: { $0.id == id }) else { throw TrialError("这个小目标已经不在了") }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("目标要有个名字") }
        guard clean == smallGoals[i].name || (clean != journey.name && !smallGoals.contains(where: { $0.name == clean })) else { throw TrialError("已经有「\(clean)」这个目标了") }
        smallGoals[i].name = clean; smallGoals[i].target = target; smallGoals[i].due = due.trimmingCharacters(in: .whitespaces)
        renameJar(smallGoals[i].account, owned: smallGoals[i].ownsAccount, to: clean)
    }

    /// 删目标时，里面已经存的钱去哪。
    public enum GoalMoney: Equatable, Sendable {
        /// 放回一个自己的账户（从目标罐里拿出来）。
        case account(String)
        /// 挪给一个小目标（钱还在目标罐里）。
        case smallGoal(UUID)
        /// 挪给大目标。
        case bigGoal
        /// 留在原来的账户里（目标用的是已有账户时才行；账户留着，只是不再算这个目标的）。
        case stay
    }

    /// 删目标时钱能放回哪些账户：生活这边自己的、不是目标罐的。默认是第一个日常能用的。
    public var goalMoneyAccounts: [Account] { owned.filter { $0.block != .goal } }

    /// 一个目标没了（删掉、走完）：把它账户里的钱放到别处，再处理这个账户。
    /// 为它新开的存钱罐跟着删；用的已有账户留着，只解除和目标的关联。
    private mutating func moveGoalMoney(_ amount: Money, from accountID: UUID?, owned: Bool, to: GoalMoney?, skip: UUID? = nil) throws {
        let dest = to ?? (owned || amount == .zero ? goalMoneyAccounts.first.map { GoalMoney.account($0.name) } : .stay)
        func take(_ m: Money) { if let a = accounts.firstIndex(where: { $0.id == accountID }) { accounts[a].balance = accounts[a].balance - min(m, accounts[a].balance) } }
        if amount > .zero {
            switch dest {
            case .stay?:
                guard !owned else { throw TrialError("这个存钱罐会跟着目标一起删，钱要先放到别处") }
            case .account(let name)?:
                guard let a = accounts.firstIndex(where: { $0.name == name }), goalMoneyAccounts.contains(where: { $0.name == name }) else { throw TrialError("选一个自己的账户来放这笔钱") }
                take(amount)
                accounts[a].balance = accounts[a].balance + amount
            case .smallGoal(let id)?:
                guard id != skip, let k = smallGoals.firstIndex(where: { $0.id == id }), let a = accounts.firstIndex(where: { $0.id == smallGoals[k].account }) else { throw TrialError("这个小目标已经不在了") }
                take(amount)
                accounts[a].balance = accounts[a].balance + amount
                smallGoals[k].saved = smallGoals[k].saved + amount
            case .bigGoal?:
                guard journey.total > .zero, let a = accounts.firstIndex(where: { $0.id == bigGoalAccount }) else { throw TrialError("现在没有大目标") }
                take(amount)
                accounts[a].balance = accounts[a].balance + amount
                journey.saved = journey.saved + amount
            case nil:
                throw TrialError("先选一下这笔钱放到哪")
            }
        }
        guard let a = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        if owned { lifePins.removeAll { $0 == accountID }; accounts.remove(at: a) }
        else { accounts[a].block = .emergency; accounts[a].note = "存着" }
    }

    /// 删掉大目标。里面已经存的钱放回一个账户，或者挪给一个小目标。删完就没有大目标了。
    public mutating func removeBigGoal(moneyTo: GoalMoney? = nil) throws {
        guard journey.total > .zero else { throw TrialError("现在没有大目标") }
        guard moneyTo != .bigGoal else { throw TrialError("钱不能放回正在删的这个目标") }
        let saved = journey.saved
        try moveGoalMoney(saved, from: bigGoalAccount, owned: bigGoalOwnsAccount, to: moneyTo)
        journey = Journey(name: "", stops: [])
        bigGoalAccount = nil; bigGoalOwnsAccount = true
    }

    /// 改大目标的名字和一共要存多少。站按新的金额重排，已经存的不变。
    public mutating func editBigGoal(name: String, total: Money) throws {
        guard journey.total > .zero else { throw TrialError("现在没有大目标") }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("目标要有个名字") }
        guard clean == journey.name || !smallGoals.contains(where: { $0.name == clean }) else { throw TrialError("已经有「\(clean)」这个目标了") }
        guard total.cents >= 20_00 else { throw TrialError("目标至少 20 €") }
        if total != journey.total {
            let stops = [10, 25, 50, 75, 100].map { Money(cents: max(total.cents * Int64($0) / 100 / 100 * 100, 100)) }
            var next = Journey(name: clean, why: journey.why, stops: stops, saved: journey.saved, monthlyPlan: journey.monthlyPlan)
            next.savedThisMonth = journey.savedThisMonth; next.resisted = journey.resisted
            journey = next
        } else {
            journey.name = clean
        }
        renameJar(bigGoalAccount, owned: bigGoalOwnsAccount, to: clean)
    }

    /// 删一个小目标：里面存的钱放回一个账户（不说就是第一个日常能用的），或者挪给大目标、别的小目标。
    public mutating func removeSmallGoal(_ id: UUID, moneyTo: GoalMoney? = nil) throws {
        guard let i = smallGoals.firstIndex(where: { $0.id == id }) else { throw TrialError("这个小目标已经不在了") }
        let g = smallGoals[i]
        try moveGoalMoney(g.saved, from: g.account, owned: g.ownsAccount, to: moneyTo, skip: id)
        smallGoals.removeAll { $0.id == id }
    }

    /// 往一个小目标里存一笔：钱从账户挪进目标罐。
    public mutating func depositSmall(_ id: UUID, amount: Money, from: String) throws {
        try Self.positive(amount, "存的钱")
        guard let g = smallGoals.firstIndex(where: { $0.id == id }) else { throw TrialError("这个小目标已经不在了") }
        let f = try index(from)
        guard accounts[f].balance >= amount else { throw TrialError("\(from)里只有 \(accounts[f].balance.formatted)") }
        guard let jar = accounts.firstIndex(where: { $0.id == smallGoals[g].account }) else { throw TrialError("这个目标的账户不见了") }
        guard jar != f, accounts[f].block != .goal else { throw TrialError("「\(from)」是目标的钱，不能直接挪") }
        accounts[f].balance = accounts[f].balance - amount
        accounts[jar].balance = accounts[jar].balance + amount
        smallGoals[g].saved = smallGoals[g].saved + amount
        // 存够了：收进「走完的路」，钱放回日常的账户，可以去买了
        if smallGoals[g].isDone {
            let done = smallGoals.remove(at: g)
            try moveGoalMoney(done.saved, from: done.account, owned: done.ownsAccount, to: nil)
            finishedGoals.insert(FinishedGoal(name: done.name, total: done.saved, date: Self.monthLabel(todayDate), small: true), at: 0)
        }
    }

    /// 走完的目标。
    public struct FinishedGoal: Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var name: String
        public var total: Money
        /// 哪个月走完的（「2026 年 11 月」）。
        public var date: String
        public var small: Bool
        public init(id: UUID = UUID(), name: String, total: Money, date: String, small: Bool) {
            self.id = id; self.name = name; self.total = total; self.date = date; self.small = small
        }
    }

    static func monthLabel(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0) 年 \(c.month ?? 0) 月"
    }

    /// 目标罐里该有多少：大目标已存的 + 每个小目标已存的。
    public var goalMoney: Money { journey.saved + smallGoals.map(\.saved).reduce(.zero, +) }

    /// 大目标存够以后收起来：记进「走完的路」，钱放回日常的账户（可以去买了），大目标的位置空出来。
    public mutating func archiveBigGoal() throws {
        guard journey.total > .zero else { throw TrialError("现在没有大目标") }
        guard journey.isFinished else { throw TrialError("「\(journey.name)」还没存够") }
        let done = journey
        try moveGoalMoney(done.saved, from: bigGoalAccount, owned: bigGoalOwnsAccount, to: nil)
        finishedGoals.insert(FinishedGoal(name: done.name, total: done.total, date: Self.monthLabel(todayDate), small: false), at: 0)
        journey = Journey(name: "", stops: [])
        bigGoalAccount = nil; bigGoalOwnsAccount = true
    }

    /// 把一个小目标设成大目标：原来的大目标变成小目标。小目标已经满了、原来的大目标又没存够，就换不了。
    public mutating func promoteSmallGoal(_ id: UUID) throws {
        guard let i = smallGoals.firstIndex(where: { $0.id == id }) else { throw TrialError("这个小目标已经不在了") }
        let g = smallGoals[i]
        let old = journey
        smallGoals.remove(at: i)
        if old.total > .zero {
            guard old.isFinished || canAddSmallGoal else {
                smallGoals.insert(g, at: i)
                throw TrialError(Plans.goalLimitSentence + "先完成或删掉一个小目标。")
            }
            var demoted = SmallGoal(name: old.name, target: old.total, saved: old.saved)
            demoted.account = bigGoalAccount; demoted.ownsAccount = bigGoalOwnsAccount
            smallGoals.insert(demoted, at: 0)
        }
        // 账户跟着目标走：一个目标对一个账户
        bigGoalAccount = g.account; bigGoalOwnsAccount = g.ownsAccount
        let stops = [10, 25, 50, 75, 100].map { Money(cents: max(g.target.cents * Int64($0) / 100 / 100 * 100, 100)) }
        journey = Journey(name: g.name, stops: Array(Set(stops)).sorted(), saved: g.saved, monthlyPlan: old.monthlyPlan)
        nextGoals.removeAll { $0.name == g.name }
    }

    // MARK: 忍住了一笔（规则和正式版一样：最近 60 天最常买的 0,50–15 € 小东西）

    /// 最近 60 天里买得最多的小东西（一次 0,50–15 €，至少 3 次）。流水里没找到就是 nil，不瞎猜。
    public var smallHabit: SmallHabit? {
        let small = entries.filter { $0.side == .life && $0.daysAgo <= 60 && $0.amount.cents <= -50 && $0.amount.cents >= -1500 }
        let groups = Dictionary(grouping: small) { $0.place.isEmpty ? $0.name : $0.place }
        guard let best = groups.filter({ $0.value.count >= 3 }).max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }) else { return nil }
        let sorted = best.value.map { -$0.amount.cents }.sorted()
        let typical = Money(cents: sorted[sorted.count / 2])
        return SmallHabit(name: best.key, typical: typical, count60: best.value.count,
                          lastWeek: best.value.filter { (7..<14).contains($0.daysAgo) }.count, thisWeek: best.value.filter { $0.daysAgo < 7 }.count, isGuess: false)
    }

    /// 把省下的一笔钱说成人话：常买什么就说什么（「等于少买 4 次 Café Nube」）；流水里看不出来就说「等于少花 N 天的零花」；都不知道就不说。
    public func savedPhrase(_ amount: Money) -> String {
        guard amount > .zero else { return "" }
        if let h = smallHabit, h.typical > .zero {
            let n = Int((Double(amount.cents) / Double(h.typical.cents)).rounded())
            if n >= 1 { return "等于少买 \(n) 次\(h.name)" }
        }
        if usualDailySpend > .zero {
            let n = Int((Double(amount.cents) / Double(usualDailySpend.cents)).rounded())
            if n >= 1 { return "等于少花 \(n) 天的零花" }
        }
        return ""
    }

    /// 忍住了一笔：这笔钱从日常的账户存进大目标，流水里留一条带「忍住了」标签的记号（金额不算花）。
    @discardableResult
    public mutating func holdBack(name: String, amount: Money) throws -> [Journey.Station] {
        try Self.positive(amount)
        guard journey.total > .zero else { throw TrialError("还没有大目标，先去定一个") }
        let reached = try deposit(amount, resisted: true)
        let what = name.trimmingCharacters(in: .whitespacesAndNewlines)
        wanted.insert(Item(emoji: "✋", name: what.isEmpty ? "忍住了一笔" : what, note: "忍住了 · 存进\(journey.name)", amount: amount, tag: "忍住了", off: true), at: 0)
        return reached
    }

    // MARK: 应急钱

    /// 能设成应急钱的账户：自己的钱，不含目标罐、店里的、欠的、借出去的、私房钱。
    public var emergencyCandidates: [Account] { owned.filter { $0.block != .goal } }
    public var emergencyAccounts: [Account] { owned.filter { $0.block == .emergency } }
    /// 想存够的那个数：几个月 × 每月必须花的。
    public var emergencyGoal: Money { Money(cents: monthlyMust.cents * Int64(emergencyGoalMonths)) }

    /// 设应急钱：放在哪几个账户、想存够几个月。没选的账户回到日常。
    public mutating func setEmergency(accounts names: Set<String>, months: Int) throws {
        guard [1, 3, 6].contains(months) else { throw TrialError("想存够几个月：选 1、3 或 6") }
        let ok = Set(emergencyCandidates.map(\.name))
        if let bad = names.first(where: { !ok.contains($0) }) { throw TrialError("「\(bad)」不能当应急钱（目标罐、店里的钱、欠的都不行）") }
        for i in accounts.indices where accounts[i].side == .life && accounts[i].kind == .own && accounts[i].block != .goal {
            accounts[i].block = names.contains(accounts[i].name) ? .emergency : .daily
        }
        emergencyGoalMonths = months
    }

    public mutating func addWanted(name: String, price: Money) throws {
        try Self.positive(price, "价钱")
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        wanted.insert(Item(emoji: "🛍", name: clean.isEmpty ? "想买的东西" : clean, note: "还要冷静 48 小时", amount: price), at: 0)
    }

    /// 忍住不买：把这笔钱存进目标。
    @discardableResult
    public mutating func resist(wanted id: UUID) throws -> [Journey.Station] {
        guard let i = wanted.firstIndex(where: { $0.id == id }) else { throw TrialError("清单里没有这一样了") }
        let reached = try deposit(wanted[i].amount, resisted: true)
        wanted[i].off = true; wanted[i].note = "刚忍住了 · 存进目标"; wanted[i].tag = ""
        return reached
    }

    // MARK: 生意

    /// 老记法里现金、刷卡各进哪个店账户：现金进名字带「现金」的，刷卡进第一个不是现金的；只有一个店账户就都进它。
    private var legacyShopAccounts: (cash: String?, card: String?) {
        let held = shopHeld
        let cash = held.first { $0.name.contains("现金") } ?? held.first
        let card = held.first { !$0.name.contains("现金") } ?? cash
        return (cash?.name, card?.name)
    }

    /// 只填一个总数时进哪个渠道：店里第一个不是现金的账户。
    public var usualShopChannel: String { legacyShopAccounts.card ?? "" }

    /// 某一天按渠道分的数（老记法的那些天，现金 / 刷卡折成对应的两个账户）。没开门的天是空的。
    public func channels(of day: ShopDay) -> [ShopChannel] {
        guard day.state == .open else { return [] }
        if !day.parts.isEmpty { return day.parts }
        let l = legacyShopAccounts
        var out: [ShopChannel] = []
        if let c = l.card, day.card > .zero { out.append(ShopChannel(c, day.card)) }
        if let c = l.cash, day.cash > .zero {
            if let k = out.firstIndex(where: { $0.account == c }) { out[k].amount = out[k].amount + day.cash } else { out.append(ShopChannel(c, day.cash)) }
        }
        return out
    }

    /// 记某一天按渠道收了多少。渠道必须是店里放钱的账户。改已经记过的那天就是改数：账户里只算差的。
    public mutating func recordShopDay(_ day: Int, channels: [ShopChannel]) throws {
        guard channels.allSatisfy({ $0.amount >= .zero }) else { throw TrialError("这里填正数就行") }
        let filled = channels.filter { $0.amount > .zero }
        guard !filled.isEmpty else { throw TrialError("至少填一个渠道收了多少") }
        guard let i = shopDays.firstIndex(where: { $0.day == day }) else { throw TrialError("没有 \(day) 号这一天") }
        guard day <= todayDay else { throw TrialError("\(day) 号还没到") }
        guard Set(filled.map(\.account)).count == filled.count else { throw TrialError("同一个渠道填了两次") }
        for c in filled {
            guard shopHeld.contains(where: { $0.name == c.account }) else { throw TrialError("「\(c.account)」不是店里收钱的账户") }
        }
        for old in self.channels(of: shopDays[i]) {
            if let a = accounts.firstIndex(where: { $0.name == old.account }) { accounts[a].balance = accounts[a].balance - old.amount }
        }
        for c in filled {
            if let a = accounts.firstIndex(where: { $0.name == c.account }) { accounts[a].balance = accounts[a].balance + c.amount }
        }
        let cash = filled.filter { $0.account.contains("现金") }.map(\.amount).reduce(.zero, +)
        let all = filled.map(\.amount).reduce(.zero, +)
        shopDays[i] = ShopDay(day: day, cash: cash, card: all - cash, state: .open, parts: filled)
    }

    /// 记某一天收了多少（现金、刷卡各一个总数）。改已经记过的那天就是改数。
    public mutating func recordShopDay(_ day: Int, cash: Money, card: Money) throws {
        guard cash >= .zero, card >= .zero else { throw TrialError("这里填正数就行") }
        guard cash + card > .zero else { throw TrialError("现金和刷卡至少填一个") }
        let l = legacyShopAccounts
        guard let cashAt = l.cash, let cardAt = l.card else { throw TrialError("还没有店里的账户") }
        try recordShopDay(day, channels: cashAt == cardAt ? [ShopChannel(cashAt, cash + card)] : [ShopChannel(cardAt, card), ShopChannel(cashAt, cash)])
    }

    public mutating func markShopRest(_ day: Int) throws {
        guard let i = shopDays.firstIndex(where: { $0.day == day }) else { throw TrialError("没有 \(day) 号这一天") }
        for old in channels(of: shopDays[i]) {
            if let a = accounts.firstIndex(where: { $0.name == old.account }) { accounts[a].balance = accounts[a].balance - old.amount }
        }
        shopDays[i] = ShopDay(day: day, cash: .zero, card: .zero, state: .rest)
    }

    /// 按日子记店里收的钱：`daysAgo` 是几天前（0 是今天）。落在这个月里就记到那一天；更早的月份，按渠道各记一笔店里的收入。
    public mutating func recordShopIncome(daysAgo: Int, channels: [ShopChannel]) throws {
        guard daysAgo >= 0 else { throw TrialError("还没到的日子记不了") }
        let day = todayDay - daysAgo
        if day >= 1 { try recordShopDay(day, channels: channels); return }
        let filled = channels.filter { $0.amount > .zero }
        guard !filled.isEmpty, channels.allSatisfy({ $0.amount >= .zero }) else { throw TrialError("至少填一个渠道收了多少") }
        for c in filled {
            guard shopHeld.contains(where: { $0.name == c.account }) else { throw TrialError("「\(c.account)」不是店里收钱的账户") }
        }
        for c in filled {
            try record(name: "营业额", emoji: c.account.contains("现金") ? "💶" : "💳", amount: c.amount, income: true, account: c.account,
                       tag: "补记的", daysAgo: daysAgo, side: .biz)
        }
    }

    // MARK: 生意的开销和流水

    /// 生意开销的分类（图标 + 名字）。
    public static let shopCategories: [Category] = [
        Category("📦", "进货"), Category("🏠", "房租"), Category("💡", "水电网"), Category("🧑", "员工工资"), Category("🔧", "设备"), Category("🎀", "包装耗材"),
        Category("📱", "平台抽成"), Category("📣", "广告"), Category("🛠", "维修"), Category("🚚", "交通运输"), Category("🧾", "其他"),
    ]

    /// 记一笔店里的开销：多少、叫什么、哪一类、从店里哪个账户出、哪天。
    @discardableResult
    public mutating func recordShopExpense(name: String, amount: Money, category: String, account: String, daysAgo: Int = 0, note: String = "") throws -> Entry {
        guard let cat = Self.shopCategories.first(where: { $0.name == category }) else { throw TrialError("选一个生意的分类") }
        guard accounts(for: .pay, side: .biz).contains(where: { $0.name == account }) else { throw TrialError("选一个店里能付钱的账户") }
        guard daysAgo >= 0 else { throw TrialError("还没到的日子记不了") }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try record(name: cat.name, emoji: cat.emoji, amount: amount, account: account, place: clean, tag: "自己记的", daysAgo: daysAgo, side: .biz, note: note)
    }

    /// 生意流水里的一行：哪天、收的还是花的。
    public struct ShopFlowRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var emoji: String
        public var title: String
        public var detail: String
        /// 收的是正数，花的是负数。
        public var amount: Money
        /// 这个月几号。
        public var day: Int
        public var entryID: UUID?
    }

    /// 这个月的生意流水：每天按渠道收的钱 + 记的每笔开销，新的在前。
    public var shopFlow: [ShopFlowRow] {
        var rows: [ShopFlowRow] = []
        for d in shopDays where d.state == .open {
            for c in channels(of: d) {
                rows.append(ShopFlowRow(id: "in-\(d.day)-\(c.account)", emoji: c.account.contains("现金") ? "💶" : "💳", title: "营业额", detail: c.account, amount: c.amount, day: d.day))
            }
        }
        for e in entries where e.side == .biz {
            let day = todayDay - e.daysAgo
            guard day >= 1 else { continue }
            rows.append(ShopFlowRow(id: e.id.uuidString, emoji: e.emoji, title: e.name, detail: [e.place, e.account].filter { !$0.isEmpty }.joined(separator: " · "),
                                    amount: e.amount, day: day, entryID: e.id))
        }
        return rows.sorted { ($0.day, $0.amount.cents) > ($1.day, $1.amount.cents) }
    }
    public var shopFlowIn: Money { shopFlow.filter { $0.amount > .zero }.map(\.amount).reduce(.zero, +) }
    public var shopFlowOut: Money { shopFlow.filter { $0.amount < .zero }.map(\.amount).reduce(.zero, +).magnitude }

    /// 固定开销默认从哪个账户扣：别的固定开销用得最多的那个；都没填过，就是店里第一个不是现金的账户。
    public var usualFixedAccount: String {
        let pay = accounts(for: .pay, side: .biz).map(\.name)
        let used = Dictionary(grouping: fixedCosts.map(\.account).filter { pay.contains($0) }, by: { $0 }).mapValues(\.count)
        if let top = pay.max(by: { (used[$0] ?? 0) < (used[$1] ?? 0) }), (used[top] ?? 0) > 0 { return top }
        return pay.first { !$0.contains("现金") } ?? pay.first ?? ""
    }

    private func fixedNote(day: Int, account: String) -> String {
        [day > 0 ? "每月 \(day) 日" : "", account].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func checkFixed(day: Int, account: String) throws {
        guard (1...31).contains(day) else { throw TrialError("每月几号付，选 1 到 31") }
        guard accounts(for: .pay, side: .biz).contains(where: { $0.name == account }) else { throw TrialError("选一个店里能付钱的账户") }
    }

    /// 加一样固定开销：叫什么、每月多少、每月几号付、从店里哪个账户扣。
    public mutating func addFixedCost(name: String, amount: Money, day: Int, account: String, canSkip: Bool = false) throws {
        try Self.positive(amount)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下这样开销叫什么") }
        guard !fixedCosts.contains(where: { $0.name == clean }) else { throw TrialError("已经有「\(clean)」这一样了") }
        try checkFixed(day: day, account: account)
        fixedCosts.append(Item(emoji: "🧾", name: clean, note: fixedNote(day: day, account: account), amount: amount, tag: canSkip ? "可省" : "必要", flag: canSkip,
                               account: account, day: day))
        fixedCosts.sort { $0.amount > $1.amount }
    }

    /// 改一样固定开销：多少、几号付、从哪扣。金额变了就记住原来是多少（「比上个月多了的」用）。
    public mutating func editFixedCost(_ name: String, amount: Money, day: Int? = nil, account: String? = nil) throws {
        try Self.positive(amount)
        guard let i = fixedCosts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这样开销") }
        let d = day ?? fixedCosts[i].day, a = account ?? fixedCosts[i].account
        if day != nil || account != nil { try checkFixed(day: d, account: a) }
        if amount != fixedCosts[i].amount, fixedCosts[i].lastMonth == nil { fixedCosts[i].lastMonth = fixedCosts[i].amount }
        fixedCosts[i].amount = amount
        if day != nil || account != nil {
            fixedCosts[i].day = d; fixedCosts[i].account = a
            fixedCosts[i].note = fixedNote(day: d, account: a)
        }
        fixedCosts.sort { $0.amount > $1.amount }
    }

    /// 比上个月多了的固定开销：哪一样涨了、涨了多少。涨得多的排前面；停着的不算。
    public var fixedRises: [(item: Item, rise: Money)] {
        fixedCosts.compactMap { c in
            guard !c.off, let last = c.lastMonth, c.amount > last else { return nil }
            return (c, c.amount - last)
        }
        .sorted { $0.rise > $1.rise }
    }

    /// 不再付这笔了。
    public mutating func removeFixedCost(_ name: String) throws {
        guard let i = fixedCosts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这样开销") }
        fixedCosts.remove(at: i)
    }

    public mutating func setFixedCost(_ name: String, paused: Bool) throws {
        guard let i = fixedCosts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这样开销") }
        fixedCosts[i].off = paused
    }

    /// 记一次进货：钱从店里账户出去。
    /// 记一次进货：就是一笔分类是「进货」的店里开销（和流水页、货值页是同一份，不另记一本）。
    public mutating func addPurchase(name: String, amount: Money, note: String, account: String? = nil) throws {
        try Self.positive(amount)
        let a = try shopPayIndex(account)
        if accounts[a].kind != .debt {
            guard accounts[a].balance >= amount else { throw TrialError("\(accounts[a].name)里只有 \(accounts[a].balance.formatted)") }
        }
        try recordShopExpense(name: name, amount: amount, category: Self.purchaseCategory, account: accounts[a].name, note: note == "今天" ? "" : note)
    }

    public mutating func estimateStock(_ value: Money, note: String) throws {
        try Self.positive(value, "估的数")
        stockEstimates.insert(Item(emoji: "📅", name: "今天", note: note, amount: value), at: 0)
    }

    /// 后来又投了钱：本钱变多，回本的路变长。
    public mutating func addCapital(name: String, amount: Money, note: String) throws {
        try Self.positive(amount)
        capital.append(Item(emoji: "💰", name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "后来投的" : name, note: note, amount: amount))
    }

    /// 店里和家里之间挪钱：两边各记一笔，不算赚也不算花。
    public mutating func transferBetweenSides(_ amount: Money, toHome: Bool, shopAccount: String, homeAccount: String) throws {
        try Self.positive(amount)
        let s = try index(shopAccount), h = try index(homeAccount)
        guard accounts[s].side == .biz, accounts[s].kind == .shop else { throw TrialError("「\(shopAccount)」不是店里放钱的账户") }
        guard accounts[h].side == .life, accounts[h].kind == .own else { throw TrialError("「\(homeAccount)」不是生活这边自己的账户") }
        let from = toHome ? s : h, to = toHome ? h : s
        guard accounts[from].balance >= amount else { throw TrialError("\(accounts[from].name)里只有 \(accounts[from].balance.formatted)") }
        accounts[from].balance = accounts[from].balance - amount
        accounts[to].balance = accounts[to].balance + amount
        if !toHome { capital.append(Item(emoji: "💰", name: "自己垫给店里", note: "今天", amount: amount)) }
    }

    /// 店里付钱用哪个账户：给了名字就用它（必须是店里能付钱的），没给就用第一个不是现金的。
    private func shopPayIndex(_ account: String?) throws -> Int {
        if let account {
            guard accounts(for: .pay, side: .biz).contains(where: { $0.name == account }), let i = accounts.firstIndex(where: { $0.name == account }) else {
                throw TrialError("选一个店里能付钱的账户")
            }
            return i
        }
        guard let a = accounts.firstIndex(where: { $0.kind == .shop && !$0.name.contains("现金") }) ?? accounts.firstIndex(where: { $0.kind == .shop }) else { throw TrialError("还没有店里的账户") }
        return a
    }

    public mutating func payShopDebt(_ name: String, from account: String? = nil) throws {
        guard let i = shopDebts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这笔欠款") }
        guard !shopDebts[i].off else { throw TrialError("这笔已经还清了") }
        let a = try shopPayIndex(account)
        guard accounts[a].kind == .shop else { throw TrialError("还欠款要用店里放着钱的账户") }
        guard accounts[a].balance >= shopDebts[i].amount else { throw TrialError("\(accounts[a].name)里只有 \(accounts[a].balance.formatted)") }
        accounts[a].balance = accounts[a].balance - shopDebts[i].amount
        shopDebts[i].off = true; shopDebts[i].note = "刚还清"
    }

    public mutating func addShopDebt(name: String, amount: Money, note: String, owedToShop: Bool) throws {
        try Self.positive(amount)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下欠谁的 / 谁欠的") }
        shopDebts.append(Item(emoji: owedToShop ? "🧑" : "📦", name: clean, note: note, amount: amount, flag: owedToShop))
    }
}

/// 试用账本 + 改动记录。每次写入都经过 `apply`：记一条 ChangeRecord，留下改之前的样子，撤销时放回去。
public struct TrialLedger: Sendable {
    public private(set) var book: TrialBook
    public private(set) var changes: [ChangeRecord]
    private var before: [UUID: TrialBook] = [:]

    public init(book: TrialBook, changes: [ChangeRecord] = []) { self.book = book; self.changes = changes }

    /// 做一次改动。做不成（抛错）就什么都不变、不留记录。
    @discardableResult
    public mutating func apply(_ kind: ChangeRecord.Kind, _ summary: String, author: String, at date: Date = Date(),
                               _ body: (inout TrialBook) throws -> Void) throws -> ChangeRecord {
        var next = book
        try body(&next)
        let record = ChangeRecord(kind: kind, summary: summary, transactionIDs: [], author: author, createdAt: date)
        before[record.id] = book
        book = next
        changes.insert(record, at: 0)
        if changes.count > 200 { let old = changes.removeLast(); before[old.id] = nil }
        return record
    }

    /// 不留记录地改：只给摆示例场景用（启动时、到站的信收进沿途风光）。
    public mutating func patch(_ body: (inout TrialBook) -> Void) { body(&book) }

    /// 彻底忘掉一条记忆：连改动记录里留着的那些「之前的样子」一起抹掉，找不回来，也不能撤销。
    public mutating func forget(memo id: UUID) throws {
        guard book.memos.contains(where: { $0.id == id }) || before.values.contains(where: { $0.memos.contains { $0.id == id } }) else {
            throw TrialError("这一条已经不在了")
        }
        book.memos.removeAll { $0.id == id }
        for key in before.keys { before[key]?.memos.removeAll { $0.id == id } }
    }

    /// 这条能不能撤销：没撤过，而且留着改之前的样子（示例里原来就有的那几条不行）。
    public func canUndo(_ id: UUID) -> Bool {
        changes.contains { $0.id == id && !$0.undone } && before[id] != nil
    }

    /// 最近一条还能撤销的改动。
    public var lastUndoable: ChangeRecord? { changes.first { canUndo($0.id) } }

    /// 撤销一条改动：账本回到它之前的样子。它后面做的改动也一起撤回（因为它们是在它之上做的）。返回一共撤了几条。
    @discardableResult
    public mutating func undo(_ id: UUID) throws -> Int {
        guard let k = changes.firstIndex(where: { $0.id == id }) else { throw TrialError("没找到这条改动") }
        guard !changes[k].undone else { throw TrialError("这条已经撤销过了") }
        guard let snapshot = before[id] else { throw TrialError("这条是示例里原来就有的，撤不了") }
        book = snapshot
        var count = 0
        for i in 0...k where !changes[i].undone && before[changes[i].id] != nil {
            changes[i].undone = true
            count += 1
        }
        return count
    }
}
