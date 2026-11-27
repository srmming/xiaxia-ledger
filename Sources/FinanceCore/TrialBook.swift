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
        public init(id: UUID = UUID(), emoji: String, name: String, note: String, balance: Money,
                    kind: Kind = .own, block: Block = .daily, short: String = "") {
            self.id = id; self.emoji = emoji; self.name = name; self.note = note; self.balance = balance
            self.kind = kind; self.block = block; self.short = short
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
        public init(id: UUID = UUID(), emoji: String, name: String, note: String, amount: Money, tag: String = "", off: Bool = false, flag: Bool = false, cycle: Int = 1) {
            self.id = id; self.emoji = emoji; self.name = name; self.note = note; self.amount = amount; self.tag = tag; self.off = off; self.flag = flag; self.cycle = cycle
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

    /// 店里某一天收了多少。
    public struct ShopDay: Equatable, Sendable {
        public enum State: Sendable { case open, rest, missing, future }
        public var day: Int
        public var cash: Money
        public var card: Money
        public var state: State
        public var total: Money { cash + card }
        public init(day: Int, cash: Money, card: Money, state: State) { self.day = day; self.cash = cash; self.card = card; self.state = state }
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

    /// 两本账的名字。
    public var lifeName = "生活"
    public var shopName = "Miora 小店"
    public var categories: [Category] = [
        .init("🛒", "超市"), .init("🥗", "餐饮"), .init("☕", "咖啡"), .init("🚇", "交通"), .init("🏠", "房租"), .init("🔁", "订阅"),
        .init("💊", "看病"), .init("🎬", "娱乐"), .init("👕", "衣服"), .init("📱", "话费"), .init("🎁", "送礼"), .init("❓", "还没分"),
    ]
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
    /// 每天开门要先收多少才够付固定开销。
    public var dailyBreakEven: Money { Money(cents: (fixedTotal.cents + 1500) / 3000 * 100) }
    public var fixedTotal: Money { fixedCosts.filter { !$0.off }.map(\.amount).reduce(.zero, +) }
    public var capitalTotal: Money { capital.map(\.amount).reduce(.zero, +) }

    public init(accounts: [Account], entries: [Entry], upcoming: [Entry], month: FreeToSpend, journey: Journey,
                letters: [Letter] = [], splitWithEmergency: Bool? = nil, monthlyMust: Money) {
        self.accounts = accounts; self.entries = entries; self.upcoming = upcoming; self.month = month
        self.journey = journey; self.letters = letters; self.splitWithEmergency = splitWithEmergency; self.monthlyMust = monthlyMust
    }

    // MARK: 现算的数

    public var today: [Entry] { entries.filter { $0.daysAgo == 0 && $0.side == .life } }
    public var owned: [Account] { accounts.filter { $0.kind == .own || $0.kind == .shop } }
    public var debts: [Account] { accounts.filter { $0.kind == .debt } }
    public var lent: [Account] { accounts.filter { $0.kind == .lent } }
    public var totals: HouseholdTotals { HouseholdTotals(holdings: owned.map(\.balance), debts: debts.map(\.balance)) }
    public func sum(_ block: Account.Block) -> Money { owned.filter { $0.block == block }.map(\.balance).reduce(.zero, +) }
    public var runway: EmergencyRunway { EmergencyRunway(fund: sum(.emergency), monthlyMust: monthlyMust) }
    public func account(_ name: String) -> Account? { accounts.first { $0.name == name } }
    /// 能拿来付钱的账户（自己的、店里的；不含欠款、借出、私房钱）。
    public func payable(_ side: Side) -> [Account] {
        accounts.filter { side == .biz ? $0.kind == .shop : ($0.kind == .own && $0.block == .daily) }
    }
    public var shopSalesTotal: Money { shopDays.filter { $0.state == .open }.map(\.total).reduce(.zero, +) }
    public var shopOpenDays: Int { shopDays.filter { $0.state == .open }.count }

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
        var useName = clean, useEmoji = emoji
        if let rule = placeRules[place], rule.count == 2 { useEmoji = rule[0]; useName = rule[1] }
        accounts[i].balance = income ? accounts[i].balance + amount : accounts[i].balance - amount
        if side == .life {
            if income { month.income = month.income + amount } else { month.spent = month.spent + amount }
        }
        let e = Entry(emoji: useEmoji, name: useName, meta: (place.isEmpty ? "" : place + " · ") + account,
                      amount: income ? amount : -amount, tag: tag, daysAgo: daysAgo, side: side, place: place, account: account, note: note)
        entries.insert(e, at: 0)
        return e
    }

    /// 删一笔：钱回到账户，「还能随便花」跟着回去。
    @discardableResult
    public mutating func delete(entry id: UUID) throws -> Entry {
        guard let k = entries.firstIndex(where: { $0.id == id }) else { throw TrialError("这一笔已经不在了") }
        let e = entries.remove(at: k)
        if let i = accounts.firstIndex(where: { $0.name == e.account }) { accounts[i].balance = accounts[i].balance - e.amount }
        if e.side == .life {
            if e.amount.cents < 0 { month.spent = month.spent + e.amount } else { month.income = month.income - e.amount }
        }
        return e
    }

    /// 改分类。`always`：以后这家店都按这一类。
    public mutating func recategorize(entry id: UUID, emoji: String, name: String, always: Bool) throws {
        guard let k = entries.firstIndex(where: { $0.id == id }) else { throw TrialError("这一笔已经不在了") }
        let place = entries[k].place.isEmpty ? entries[k].name : entries[k].place
        entries[k].place = place
        entries[k].emoji = emoji; entries[k].name = name
        entries[k].meta = entries[k].account.isEmpty ? place : "\(place) · \(entries[k].account)"
        if entries[k].tag == "等你看一眼" { entries[k].tag = "你认的" }
        if always {
            placeRules[place] = [emoji, name]
            for j in entries.indices where entries[j].place == place { entries[j].emoji = emoji; entries[j].name = name }
        }
    }

    /// 改金额（传正数；支出还是支出，收入还是收入）。
    public mutating func setAmount(entry id: UUID, to amount: Money) throws {
        try Self.positive(amount)
        guard let k = entries.firstIndex(where: { $0.id == id }) else { throw TrialError("这一笔已经不在了") }
        let old = entries[k].amount
        let new = old.cents < 0 ? -amount : amount
        let diff = new - old
        entries[k].amount = new
        if let i = accounts.firstIndex(where: { $0.name == entries[k].account }) { accounts[i].balance = accounts[i].balance + diff }
        if entries[k].side == .life {
            if old.cents < 0 { month.spent = month.spent - diff } else { month.income = month.income + diff }
        }
    }

    /// 自己两个账户之间挪钱：不算花也不算赚。
    public mutating func move(_ amount: Money, from: String, to: String) throws {
        try Self.positive(amount)
        guard from != to else { throw TrialError("两边选了同一个账户") }
        let f = try index(from), t = try index(to)
        guard accounts[f].balance >= amount else { throw TrialError("\(from)里只有 \(accounts[f].balance.formatted)") }
        accounts[f].balance = accounts[f].balance - amount
        accounts[t].balance = accounts[t].balance + amount
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
        guard accounts[i].block != .goal, accounts[i].block != .emergency, accounts[i].kind != .shop else { throw TrialError("「\(name)」别的地方还在用，不能删") }
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
        monthlyMust = .zero; splitWithEmergency = nil
        for i in shopDays.indices where shopDays[i].state == .open || shopDays[i].state == .rest {
            shopDays[i] = ShopDay(day: shopDays[i].day, cash: .zero, card: .zero, state: shopDays[i].day <= todayDay ? .missing : .future)
        }
        fixedCosts = []; purchases = []; stockEstimates = []; capital = []; shopDebts = []; nextGoals = []
    }

    // MARK: 目标

    /// 存一笔进目标：从 `from` 挪到目标罐（答应过对半分就一半进应急钱）。返回刚到的站。
    @discardableResult
    public mutating func deposit(_ amount: Money, from: String? = nil, resisted: Bool = false) throws -> [Journey.Station] {
        try Self.positive(amount, "存的钱")
        let source = from ?? accounts.first { $0.block == .daily && $0.kind == .own }?.name ?? ""
        let i = try index(source)
        guard accounts[i].balance >= amount else { throw TrialError("\(source)里只有 \(accounts[i].balance.formatted)") }
        let half = splitWithEmergency == true && !resisted
        let toGoal = half ? Money(cents: amount.cents / 2) : amount
        let toEmergency = amount - toGoal
        accounts[i].balance = accounts[i].balance - amount
        if let g = accounts.firstIndex(where: { $0.block == .goal }) { accounts[g].balance = accounts[g].balance + toGoal }
        if toEmergency > .zero, let e = accounts.firstIndex(where: { $0.block == .emergency }) { accounts[e].balance = accounts[e].balance + toEmergency }
        let reached = journey.deposit(toGoal)
        if resisted { journey.resisted += 1 }
        return reached
    }

    /// 从头定一个目标：拆成四站（一成、四分之一、一半、四分之三）再到终点。
    public mutating func startGoal(name: String, total: Money) throws {
        try Self.positive(total, "目标的钱")
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下想要什么") }
        guard journey.total == .zero else { throw TrialError("已经有一个目标在走了") }
        guard total.cents >= 20_00 else { throw TrialError("目标至少 20 €") }
        let stops = [10, 25, 50, 75, 100].map { Money(cents: total.cents * Int64($0) / 100 / 100 * 100) }
        journey = Journey(name: clean, stops: stops, saved: sum(.goal))
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
        accounts.append(Account(emoji: emoji, name: clean, note: note, balance: balance, kind: kind, block: kind == .own ? .daily : .none))
    }

    /// 还一笔欠款：从 `from` 出钱，欠的减少。还清了就从「接下来要付的」里拿掉。
    public mutating func repay(debt name: String, amount: Money, from: String) throws {
        try Self.positive(amount, "还的钱")
        let d = try index(name)
        guard accounts[d].kind == .debt else { throw TrialError("「\(name)」不是欠款") }
        guard amount <= accounts[d].balance else { throw TrialError("\(name)只欠 \(accounts[d].balance.formatted)，不用还这么多") }
        let f = try index(from)
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
    public mutating func addInstallment(name: String, total: Money, periods: Int, paid: Int, day: Int) throws {
        try Self.positive(total)
        guard (2...60).contains(periods) else { throw TrialError("分期填 2 到 60 期") }
        guard (0..<periods).contains(paid) else { throw TrialError("已经还的期数要比总期数少") }
        guard (1...28).contains(day) else { throw TrialError("每月几号扣，填 1 到 28") }
        let each = Money(cents: total.cents / Int64(periods))
        let left = total - Money(cents: each.cents * Int64(paid))
        try addAccount(emoji: "🧾", name: name, note: "欠 · 还剩 \(periods - paid) 期，每月 \(each.formatted)", balance: left, kind: .debt)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        upcoming.append(Entry(emoji: "🧾", name: clean, meta: "12 月 \(day) 日 · 第 \(paid + 1) / \(periods) 期", amount: each, red: true))
    }

    /// 排在现在这个目标后面的下一个目标（大决定页「存成一个目标」）。
    public var nextGoals: [Item] = []

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

    /// 记某一天收了多少（现金、刷卡各一个总数）。改已经记过的那天就是改数。
    public mutating func recordShopDay(_ day: Int, cash: Money, card: Money) throws {
        guard cash >= .zero, card >= .zero else { throw TrialError("这里填正数就行") }
        guard cash + card > .zero else { throw TrialError("现金和刷卡至少填一个") }
        guard let i = shopDays.firstIndex(where: { $0.day == day }) else { throw TrialError("没有 \(day) 号这一天") }
        guard day <= todayDay else { throw TrialError("\(day) 号还没到") }
        let old = shopDays[i].state == .open ? shopDays[i] : ShopDay(day: day, cash: .zero, card: .zero, state: .open)
        if let a = accounts.firstIndex(where: { $0.kind == .shop }) {
            accounts[a].balance = accounts[a].balance + (cash + card) - old.total
        }
        shopDays[i] = ShopDay(day: day, cash: cash, card: card, state: .open)
    }

    public mutating func markShopRest(_ day: Int) throws {
        guard let i = shopDays.firstIndex(where: { $0.day == day }) else { throw TrialError("没有 \(day) 号这一天") }
        if shopDays[i].state == .open, let a = accounts.firstIndex(where: { $0.kind == .shop }) {
            accounts[a].balance = accounts[a].balance - shopDays[i].total
        }
        shopDays[i] = ShopDay(day: day, cash: .zero, card: .zero, state: .rest)
    }

    public mutating func addFixedCost(name: String, amount: Money, note: String, canSkip: Bool) throws {
        try Self.positive(amount)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrialError("先写一下这样开销叫什么") }
        guard !fixedCosts.contains(where: { $0.name == clean }) else { throw TrialError("已经有「\(clean)」这一样了") }
        fixedCosts.append(Item(emoji: "🧾", name: clean, note: note, amount: amount, tag: canSkip ? "可省" : "必要", flag: canSkip))
        fixedCosts.sort { $0.amount > $1.amount }
    }

    public mutating func editFixedCost(_ name: String, amount: Money) throws {
        try Self.positive(amount)
        guard let i = fixedCosts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这样开销") }
        fixedCosts[i].amount = amount
        fixedCosts.sort { $0.amount > $1.amount }
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
    public mutating func addPurchase(name: String, amount: Money, note: String) throws {
        try Self.positive(amount)
        guard let a = accounts.firstIndex(where: { $0.kind == .shop }) else { throw TrialError("还没有店里的账户") }
        guard accounts[a].balance >= amount else { throw TrialError("\(accounts[a].name)里只有 \(accounts[a].balance.formatted)") }
        accounts[a].balance = accounts[a].balance - amount
        purchases.insert(Item(emoji: "📦", name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "进货" : name, note: note, amount: amount), at: 0)
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
        let from = toHome ? s : h, to = toHome ? h : s
        guard accounts[from].balance >= amount else { throw TrialError("\(accounts[from].name)里只有 \(accounts[from].balance.formatted)") }
        accounts[from].balance = accounts[from].balance - amount
        accounts[to].balance = accounts[to].balance + amount
        if !toHome { capital.append(Item(emoji: "💰", name: "自己垫给店里", note: "今天", amount: amount)) }
    }

    public mutating func payShopDebt(_ name: String) throws {
        guard let i = shopDebts.firstIndex(where: { $0.name == name }) else { throw TrialError("没找到「\(name)」这笔欠款") }
        guard !shopDebts[i].off else { throw TrialError("这笔已经还清了") }
        guard let a = accounts.firstIndex(where: { $0.kind == .shop }) else { throw TrialError("还没有店里的账户") }
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
