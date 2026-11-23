import Foundation

/// 示例账本：一个虚构的人，有一份兼职工资，自己还开了一家小花店（带咖啡角），过了一年多的账。
/// 人名、店名、银行、商户、金额全是编的，和任何真实的人、店、银行都没关系。
/// 给 app 的示例模式（-XiaxiaDemo）、App Store 截图、发给别人看、开发自测、`fin demo` 用。
///
/// 覆盖所有功能：两个账本（个人 + 小店）、8 个账户（含信用卡、储蓄罐、私房钱）、各类收支、
/// 自己账户间转账（还信用卡、充值、取现、老板提款）、账本间转账、退款、订阅（含涨价、停掉的、没登记的）、
/// 分期（含手续费）、借出 / 借入 / 还款（含逾期、已还清）、存钱目标（挂储蓄罐、在账户里划出、锁定）、
/// 夏夏建议、改动记录（导入、手记、改分类、分账本、撤销）、还没整理的几笔。
///
/// 时间跟着「今天」走：从 12 个月前的 1 号到今天，所以图表永远有完整的一年，本月永远有数据。
/// 同一个「今天」+ 同一个种子，生成的账本一模一样（连 id 都一样）。
public enum DemoData {
    public static let defaultSeed: UInt64 = 20_261_122
    public static let shopBookID = "shop"
    /// 第一条改动记录的说明，用来认出「这是示例账本」（fin demo 只肯覆盖示例账本）。
    public static let marker = "生成示例账本（人、店、金额全是编的）"

    public static func make(endingOn end: LocalDate = .today, seed: UInt64 = defaultSeed) -> Ledger {
        var b = DemoBuilder(end: end, seed: seed)
        b.build()
        return b.finish()
    }

    /// 这本账是不是示例账本。
    public static func isDemo(_ ledger: Ledger) -> Bool {
        ledger.changes.contains { $0.summary == marker }
    }
}

extension Ledger {
    /// 示例账本（全是编的），今天为止的 13 个月。
    public static var demo: Ledger { DemoData.make() }
}

extension LedgerStores {
    /// 真实账本可能在的位置（不看 XIAXIA_LEDGER_PATH）。fin demo 绝不往这些地方写。
    public static var standardLocations: [URL] {
        [containerDocumentsOnDisk, iCloudFolder, appSupportFolder].flatMap {
            [$0.appendingPathComponent("ledger.sqlite"), $0.appendingPathComponent("ledger.json")]
        }
    }
}

// MARK: - 随机数（固定种子，可重复）

struct DemoRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    /// SplitMix64。
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
    /// lo 到 hi 之间的金额（欧元），精确到分。
    mutating func euros(_ lo: Double, _ hi: Double) -> Money {
        Money(cents: Int64(((lo + (hi - lo) * unit()) * 100).rounded()))
    }

    /// 一个固定的 UUID（版本 4 的样子）。
    mutating func uuidString() -> String {
        let hex = Array(String(format: "%016llX%016llX", next(), next()))
        let variant = Array("89AB")[Int(next() % 4)]
        return String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-4" + String(hex[13..<16]) + "-"
            + String(variant) + String(hex[17..<20]) + "-" + String(hex[20..<32])
    }
}

// MARK: - 日期小工具

func demoDaysIn(_ ym: YearMonth) -> Int {
    switch ym.month {
    case 2: return (ym.year % 4 == 0 && ym.year % 100 != 0) || ym.year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
}

func demoShift(_ ym: YearMonth, _ n: Int) -> YearMonth {
    let total = ym.year * 12 + (ym.month - 1) + n
    return YearMonth(year: total / 12, month: total % 12 + 1)
}

/// 某月第几天；超过月底就是月底。
func demoDay(_ ym: YearMonth, _ d: Int) -> LocalDate {
    LocalDate(year: ym.year, month: ym.month, day: min(max(d, 1), demoDaysIn(ym)))
}

func demoNextDay(_ d: LocalDate) -> LocalDate {
    d.day < demoDaysIn(d.yearMonth) ? LocalDate(year: d.year, month: d.month, day: d.day + 1) : demoDay(demoShift(d.yearMonth, 1), 1)
}

// MARK: - 生成

struct DemoBuilder {
    static let P = "personal"
    static let S = DemoData.shopBookID
    /// 有对账单、靠导入的账户；其余（现金、店里现金、私房钱）是手记的。
    static let statementAccounts: Set<String> = ["daily", "credit", "wallet", "shop", "usd"]

    let end: LocalDate
    var rng: DemoRandom
    var l = Ledger()
    /// 13 个月，最后一个是「今天」所在的月。
    let months: [YearMonth]
    /// 导入的流水：按「账户|月份」攒着，最后每批记一条改动（像真的每月导一次对账单）。
    var batches: [String: [UUID]] = [:]
    var batchOrder: [String] = []
    /// 已经定好时间的改动条数。
    var stamped = 0
    /// 「今天」的改动按先后排在凌晨，一条隔一分钟。
    var todayTick = 0

    var goalPot = UUID(), goalLaptop = UUID(), goalLocked = UUID(), goalShop = UUID()
    var instCoffee = UUID(), instPhone = UUID()

    init(end: LocalDate, seed: UInt64) {
        self.end = end
        rng = DemoRandom(seed: seed)
        months = (0...12).map { demoShift(end.yearMonth, $0 - 12) }
    }

    var start: LocalDate { demoDay(months[0], 1) }
    /// 最近两个月的手记，每笔单独一条改动（app 里能看到「你记了一笔」）；更早的按月合成「补录」。
    var recentFrom: LocalDate { demoDay(months[11], 1) }

    // MARK: 时间戳

    func moment(_ d: LocalDate, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = d.year; c.month = d.month; c.day = d.day
        // 「今天」的改动从早上 7 点排起（stamp 里处理），这里只管别的日子。
        c.hour = d >= end ? 0 : hour
        c.minute = minute
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// 给还没定时间的改动定时间。
    mutating func stamp(_ d: LocalDate, hour: Int? = nil) {
        let date = min(d, end)
        var at = moment(date, hour ?? rng.int(9...22), rng.int(0...59))
        if date >= end {
            at = moment(end, 0, 0).addingTimeInterval(Double(7 * 3600 + todayTick * 60))
            todayTick += 1
        }
        while stamped < l.changes.count {
            l.changes[stamped].createdAt = at
            stamped += 1
        }
    }

    // MARK: 记流水

    func accountName(_ id: String) -> String { l.accounts.first { $0.id == id }?.name ?? id }

    @discardableResult
    mutating func add(_ date: LocalDate, _ amount: Money, _ text: String, _ account: String, book: String?, cat: String?,
                      flow: Transaction.Flow? = nil, transferID: UUID? = nil) -> UUID? {
        guard date >= start, date <= end, amount.cents != 0 else { return nil }
        let fromStatement = Self.statementAccounts.contains(account)
        let source = fromStatement ? "\(accountName(account))-\(date.yearMonth).csv" : "手记"
        let tx = Transaction(date: date, amount: amount, description: text, accountID: account, bookID: book, category: cat,
                             transferID: transferID, source: source, flow: flow)
        l.transactions.append(tx)
        if fromStatement || date < recentFrom {
            let key = "\(account)|\(date.yearMonth)"
            if batches[key] == nil { batchOrder.append(key) }
            batches[key, default: []].append(tx.id)
        } else {
            // 最近手记的：多半是自己在 app 里记的，有几笔是跟 AI 说了让它记的。
            let who = rng.chance(0.3) ? rng.pick(["Claude", "Codex"]) : "你"
            l.record(.add, "记一笔 \(amount.formatted) \(text)", ids: [tx.id], author: who)
            stamp(date)
        }
        return tx.id
    }

    mutating func spend(_ date: LocalDate, _ amount: Money, _ text: String, _ account: String, _ book: String, _ cat: String) {
        add(date, -amount.magnitude, text, account, book: book, cat: cat)
    }

    mutating func earn(_ date: LocalDate, _ amount: Money, _ text: String, _ account: String, _ book: String, _ cat: String) {
        add(date, amount.magnitude, text, account, book: book, cat: cat)
    }

    /// 自己账户之间挪钱（还信用卡、充值、取现、老板提款）：一出一进，不算收支。
    mutating func move(_ date: LocalDate, _ amount: Money, from: String, to: String, _ text: String,
                       fromBook: String?, toBook: String?) {
        guard amount.cents > 0 else { return }
        let tid = UUID()
        add(date, -amount, text, from, book: fromBook, cat: "账户间转账", flow: .internal, transferID: tid)
        add(date, amount, text, to, book: toBook, cat: "账户间转账", flow: .internal, transferID: tid)
    }

    func total(_ account: String, in ym: YearMonth, outflowOnly: Bool = false) -> Money {
        l.transactions.filter { $0.accountID == account && $0.date.yearMonth == ym && (!outflowOnly || $0.amount.isExpense) }
            .reduce(Money.zero) { $0 + $1.amount }
    }

    func balance(_ account: String, upTo d: LocalDate) -> Money {
        l.transactions.filter { $0.accountID == account && $0.date <= d }.reduce(Money.zero) { $0 + $1.amount }
    }

    /// 前 12 个整月里某个月份（1–12）是哪个月。
    func past(_ month: Int) -> YearMonth { months[0..<12].first { $0.month == month } ?? months[0] }

    func eur(_ v: Double) -> Money { Money(cents: Int64((v * 100).rounded())) }

    // MARK: 整体

    mutating func build() {
        setUp()
        plans()
        // 一次性的和借款先记：每月初还信用卡、充值时要把它们也算进去。
        oneOffs()
        debts()
        for (i, ym) in months.enumerated() {
            personalMonth(i, ym)
            shopMonth(i, ym)
        }
        // 店里账户刷的一笔五金店，导入时没分账本，后面再分到小店。
        let hardware = add(demoDay(months[11], 17), eur(-23.4), "COMPRA TARJ. FERRETERIA ALBA 3310", "shop", book: nil, cat: "维修")
        closeBatches()
        edits(hardware)
        untidy()
        closeBatches()
        subscriptions()
        openingBalances()
        l.fillMissingFX()
        insights()
        memories()
    }

    mutating func setUp() {
        l.books = [Book(id: Self.P, name: "个人", kind: .personal), Book(id: Self.S, name: "我的小店", kind: .business)]
        l.accounts = [
            Account(id: "daily", name: "日常卡", kind: .bank, institution: "晴空银行"),
            Account(id: "credit", name: "信用卡", kind: .credit, institution: "晴空银行"),
            Account(id: "wallet", name: "电子钱包", kind: .wallet, institution: "云付"),
            Account(id: "cash", name: "现金", kind: .cash),
            Account(id: "pot", name: "应急金储蓄罐", kind: .savings, institution: "云付"),
            Account(id: "shop", name: "店里账户", kind: .bank, institution: "晴空银行"),
            Account(id: "till", name: "店里现金", kind: .cash),
            Account(id: "stash", name: "私房钱", kind: .cash, isPrivate: true),
            Account(id: "usd", name: "美元账户", kind: .wallet, institution: "云付", currency: "USD"),
        ]
        // 汇率写死在示例里（每月 1 号和 15 号各一个点，在 1,05–1,13 之间慢慢走），不联网。
        var rates: [RatePoint] = []
        var rate = 1.08
        for ym in months {
            for day in [1, 15] where demoDay(ym, day) <= end {
                rate = min(1.13, max(1.05, rate + (rng.unit() - 0.5) * 0.02))
                rates.append(RatePoint(date: demoDay(ym, day), perEUR: (rate * 10_000).rounded() / 10_000))
            }
        }
        l.currency = CurrencySettings(base: "EUR", rates: ["USD": rates])
        l.profile = Profile(persona: .gentle, aim: "每个月存下 300 €", categories: [CustomCategory(name: "宠物", income: false)])
        l.changes.append(ChangeRecord(kind: .importBatch, summary: DemoData.marker, transactionIDs: [], author: "示例"))
        var shopBook = PlanSnapshot()
        shopBook.addedBookIDs = [Self.S]
        l.changes.append(l.snapshotChange(.account, "建账本「我的小店」", before: shopBook, author: "你"))
        for a in l.accounts {
            l.changes.append(l.snapshotChange(.account, "加账户「\(a.name)」\(a.isPrivate ? "（私房钱）" : "")",
                                              before: PlanSnapshot(addedAccountIDs: [a.id]), author: "你"))
        }
        stamp(start, hour: 10)
    }

    /// 目标和分期先建好，每个月往里存、按期还。
    mutating func plans() {
        let P = Self.P, S = Self.S
        if let gResult = try? l.addGoal(name: "应急金", bookID: P, target: eur(5000), deadline: demoDay(demoShift(end.yearMonth, 6), 30),
                                       savingsAccountID: "pot", author: "你") { goalPot = gResult.0.id }
        stamp(demoDay(months[0], 2))
        if let gResult = try? l.addGoal(name: "店面重新装修", bookID: S, target: eur(6000), deadline: demoDay(demoShift(end.yearMonth, 9), 1),
                                       author: "Claude") { goalShop = gResult.0.id }
        stamp(demoDay(months[6], 24))
        if let gResult = try? l.addGoal(name: "换新电脑", bookID: P, target: eur(1400), deadline: demoDay(demoShift(end.yearMonth, 5), 30),
                                       author: "你") { goalLaptop = gResult.0.id }
        stamp(demoDay(months[6], 25))
        if let gResult = try? l.addGoal(name: "锁起来的存钱罐", bookID: P, target: eur(1000), locked: true, author: "你") { goalLocked = gResult.0.id }
        stamp(demoDay(months[7], 27))
        // 店里的咖啡机：分 12 期，有手续费。
        if let instResult = try? l.addInstallment(name: "咖啡机", bookID: S, accountID: "shop", total: eur(1800), count: 12,
                                                 purchaseDate: demoDay(months[3], 9), firstPayment: demoDay(months[4], 10),
                                                 category: "设备", fee: eur(36), author: "Claude") { instCoffee = instResult.0.id }
        stamp(demoDay(months[3], 9))
        // 自己的新手机：分 10 期，免息。
        if let instResult = try? l.addInstallment(name: "新手机", bookID: P, accountID: "daily", total: eur(899), count: 10,
                                                 purchaseDate: demoDay(months[8], 14), firstPayment: demoDay(months[9], 15),
                                                 category: "数码", author: "你") { instPhone = instResult.0.id }
        stamp(demoDay(months[8], 14))
    }

    // MARK: 个人

    mutating func personalMonth(_ i: Int, _ ym: YearMonth) {
        let P = Self.P
        let d: (Int) -> LocalDate = { demoDay(ym, $0) }

        // 月初：充值电子钱包、还上个月的信用卡、交房租。
        if i == 0 {
            move(d(1), eur(150), from: "daily", to: "wallet", "电子钱包充值", fromBook: P, toBook: P)
        } else {
            let prev = months[i - 1]
            // 充到够上个月花的再多留 50 €，凑整到 50。
            let used = total("wallet", in: prev, outflowOnly: true).magnitude.cents
            let need = used + 5_000 - balance("wallet", upTo: d(1)).cents
            if need >= 5_000 { move(d(1), Money(cents: (need + 4_999) / 5_000 * 5_000), from: "daily", to: "wallet", "电子钱包充值", fromBook: P, toBook: P) }
            let owed = -l.transactions.filter { $0.accountID == "credit" && $0.date.yearMonth == prev && $0.flow != .internal }
                .reduce(Money.zero) { $0 + $1.amount }.cents
            if owed > 0 { move(d(3), Money(cents: owed), from: "daily", to: "credit", "信用卡还款", fromBook: P, toBook: P) }
        }
        spend(d(1), eur(780), "房租", "daily", P, "房租")
        spend(d(1), eur(20), "公交月票", "wallet", P, "交通")
        spend(d(2), eur(34.9), "FitBox 健身房", "daily", P, "运动")
        spend(d(3), eur(2.99), "云存储 50GB", "credit", P, "订阅")
        spend(d(5), eur(35), "RECIBO TELEFONIA NUBEMOVIL", "daily", P, "通讯")
        let heating: [Int: Double] = [1: 38, 2: 32, 7: 24, 8: 28, 12: 34]
        let season = heating[ym.month] ?? 0
        spend(d(10), rng.euros(52 + season, 68 + season), "RECIBO LUZ Y GAS ENERLUZ", "daily", P, "水电")
        // 订阅：视频会员 4 个月前涨价；健身 app 3 个月前停了；语言课每月扣、但没登记成订阅。
        spend(d(7), eur(i >= 9 ? 12.99 : 11.99), "StreamBox 视频会员", "credit", P, "订阅")
        spend(d(15), eur(10.99), "Tuneo 音乐会员", "credit", P, "订阅")
        if i < 9 { spend(d(20), eur(7.99), "FitPlan 健身 App", "credit", P, "订阅") }
        if i >= 3 { spend(d(18), eur(9.99), "LINGUAPAL *SUSCRIPCION", "credit", P, "学习") }

        // 收入：兼职工资，6 月和 12 月多发一份；偶尔接设计的活。
        earn(d(27), eur(1380), "工资", "daily", P, "工资")
        if ym.month == 6 || ym.month == 12 { earn(d(27), eur(1380), ym.month == 6 ? "年中双薪" : "年终双薪", "daily", P, "工资") }
        if rng.chance(0.4) { earn(d(rng.int(8...24)), rng.euros(220, 620), "设计接单稿费", "daily", P, "副业") }
        // 海外客户用美元付稿费，进美元账户；字体会员用美元扣。
        if i % 3 == 1 { earn(d(rng.int(10...20)), rng.euros(300, 600), "海外客户稿费", "usd", P, "副业") }
        if i >= 2 { spend(d(11), eur(14.99), "FONTHUB SUBSCRIPTION", "usd", P, "订阅") }

        // 日常花销。
        for _ in 0..<rng.int(7...10) {
            let r = rng.unit(), day = d(rng.int(1...28))
            if r < 0.55 { spend(day, rng.euros(22, 78), "COMPRA TARJ. SUPER LUMI 4821", "credit", P, "超市") }
            else if r < 0.8 { spend(day, rng.euros(8, 26), "菜市场", "cash", P, "超市") }
            else { spend(day, rng.euros(6, 18), "COMPRA TARJ. FRUTERIA SOL 1180", "credit", P, "超市") }
        }
        let dining: [(String, String, Double, Double)] = [
            ("Café Nube", "credit", 3.2, 9.8), ("Bar La Esquina", "credit", 12, 35), ("Ramen Koji", "wallet", 14, 32),
            ("ComidaYa 外卖", "wallet", 13, 28), ("Pizzería Nonna", "credit", 18, 46),
        ]
        for _ in 0..<rng.int(4...8) {
            let (name, acct, lo, hi) = rng.pick(dining)
            spend(d(rng.int(1...28)), rng.euros(lo, hi), name, acct, P, "餐饮")
        }
        for _ in 0..<rng.int(0...2) { spend(d(rng.int(1...28)), rng.euros(8, 22), "出租车", "wallet", P, "交通") }
        let shops: [(String, String, Double, Double)] = [
            ("Tienda Mar 服装", "credit", 19, 89), ("网购 · 包裹一号", "wallet", 9, 65), ("Libros Faro 书店", "credit", 12, 30),
        ]
        for _ in 0..<rng.int(1...3) {
            let (name, acct, lo, hi) = rng.pick(shops)
            spend(d(rng.int(1...28)), rng.euros(lo, hi), name, acct, P, "购物")
        }
        if ym.month == 1 || ym.month == 7 { spend(d(rng.int(5...15)), rng.euros(35, 90), "Tienda Mar 打折季", "credit", P, "购物") }
        // 上个月的猫粮先被分到了「购物」，后面 Codex 改成「宠物」（演示改分类）。
        let petCategory = i == 11 ? "购物" : "宠物"
        for _ in 0..<rng.int(1...2) { spend(d(rng.int(1...28)), rng.euros(18, 42), "Miau Miau 宠物店", "credit", P, petCategory) }
        if i % 2 == 0 { spend(d(rng.int(5...25)), rng.euros(28, 42), "Peluquería Rizo 理发", "credit", P, "个人护理") }
        for _ in 0..<rng.int(0...2) { spend(d(rng.int(1...28)), rng.euros(7, 9.5), "电影票", "wallet", P, "娱乐") }
        if rng.chance(0.3) { spend(d(rng.int(1...28)), rng.euros(6, 28), "药店", "cash", P, "医疗") }

        // 取现、存私房钱。
        let atm = d(rng.int(4...12))
        if balance("cash", upTo: atm).cents < 12_000 { move(atm, eur(100), from: "daily", to: "cash", "ATM 取现", fromBook: P, toBook: P) }
        move(d(15), eur(40), from: "cash", to: "stash", "存进私房钱", fromBook: P, toBook: P)

        // 存钱、还分期。
        deposit(goalPot, eur(250), from: "daily", on: d(26), author: "你")
        if i >= 6 { deposit(goalLaptop, eur(100), from: "daily", on: d(26), author: "你") }
        if i >= 7 { deposit(goalLocked, eur(50), from: "daily", on: d(28), author: "你") }
        if i >= 9 { pay(instPhone, on: d(15)) }
    }

    mutating func deposit(_ goal: UUID, _ amount: Money, from: String, on date: LocalDate, author: String) {
        guard date <= end else { return }
        _ = try? l.deposit(goalID: goal, amount: amount, fromAccount: from, date: date, author: author)
        stamp(date)
    }

    mutating func pay(_ inst: UUID, on date: LocalDate) {
        guard date <= end, let it = l.installments.first(where: { $0.id == inst }), it.paidIDs.count < it.count else { return }
        _ = try? l.payInstallment(inst, date: date, author: "Claude")
        stamp(date)
    }

    // MARK: 小店

    mutating func shopMonth(_ i: Int, _ ym: YearMonth) {
        let S = Self.S
        let d: (Int) -> LocalDate = { demoDay(ym, $0) }
        // 花店的淡旺季：情人节、母亲节、圣诞多，八月少。
        let seasons: [Int: Double] = [1: 0.85, 2: 1.25, 3: 1.0, 4: 1.05, 5: 1.3, 6: 1.0, 7: 0.9, 8: 0.7, 9: 0.95, 10: 1.0, 11: 1.05, 12: 1.35]
        let season = seasons[ym.month] ?? 1

        spend(d(1), eur(1100), "店租", "shop", S, "店租")
        // 每个月 1 号老板给自己发生活费：店里账户 → 日常卡。
        move(d(1), eur(700), from: "shop", to: "daily", "老板提款 · 生活费", fromBook: S, toBook: Self.P)
        var card = Money.zero
        for day in [7, 14, 21, 28] {
            let m = rng.euros(1350 * season * 0.85, 1350 * season * 1.15)
            if d(day) <= end { card = card + m }
            earn(d(day), m, "刷卡收款（周结）", "shop", S, "营业收入")
        }
        for day in [6, 13, 20, 27] { earn(d(day), rng.euros(110 * season * 0.8, 110 * season * 1.2), "现金收入", "till", S, "营业收入") }
        for day in [2, 9, 16, 23] {
            spend(d(day), rng.euros(300 * season * 0.85, 300 * season * 1.15), "COMPRA TARJ. VIVERO MAYOR 0932", "shop", S, "花材")
        }
        for day in [4, 18] { spend(d(day), rng.euros(55, 95), "Café Origen 咖啡豆", "shop", S, "原料") }
        spend(d(rng.int(8...20)), rng.euros(80, 150), "Pack&Co 包装耗材", "shop", S, "包装耗材")
        spend(d(5), eur(29), "收银系统月费", "shop", S, "订阅")
        spend(d(12), rng.euros(140, 190) + (ym.month >= 6 && ym.month <= 9 ? eur(40) : .zero), "店里水电", "shop", S, "水电")
        spend(d(28), eur(310), "自雇社保", "shop", S, "社保")
        if card.cents > 0 { spend(d(28), Money(cents: card.cents * 12 / 1000), "刷卡手续费", "shop", S, "手续费") }
        spend(d(30), eur(1050), "兼职店员工资", "shop", S, "员工工资")
        if [1, 4, 7, 10].contains(ym.month) { spend(d(20), rng.euros(780, 1150), "季度增值税", "shop", S, "税费") }
        if [2, 5, 11].contains(ym.month) { spend(d(10), rng.euros(60, 120), "社交平台推广", "shop", S, "推广") }
        if ym.month == 3 { spend(d(14), eur(96), "网站和域名年费", "shop", S, "订阅") }

        // 月底把店里现金存进店里账户，留 100 € 找零。
        let cashDay = d(29)
        if cashDay <= end {
            let keep = balance("till", upTo: cashDay).cents - 10_000
            if keep >= 10_000 { move(cashDay, Money(cents: keep / 5_000 * 5_000), from: "till", to: "shop", "现金存进店里账户", fromBook: S, toBook: S) }
        }
        if i >= 6 { deposit(goalShop, eur(200), from: "shop", on: d(25), author: "Claude") }
        if i >= 4 { pay(instCoffee, on: d(10)) }
    }

    // MARK: 不是每个月都有的

    mutating func oneOffs() {
        let P = Self.P, S = Self.S
        let dec = past(12)
        for k in 0..<3 { spend(demoDay(dec, 10 + k * 4), rng.euros(25, 80), "圣诞礼物", "credit", P, "礼物") }
        spend(demoDay(dec, 24), eur(65), "平安夜聚餐", "credit", P, "餐饮")
        spend(demoDay(past(1), 12), eur(140), "Casa Pino 家居", "credit", P, "家居")
        spend(demoDay(past(3), 3), eur(168), "房屋保险年费", "daily", P, "保险")
        spend(demoDay(past(5), 9), eur(60), "妈妈生日礼物", "credit", P, "礼物")
        spend(demoDay(past(6), 17), eur(90), "Clínica Dental Sonrisa 洗牙", "credit", P, "医疗")
        // 欧元信用卡在海外网店刷美元：金额记银行扣的欧元，原价 45 US$ 记作备注。
        if let id = add(demoDay(past(4), 23), eur(-41.37), "海外网店 · 手工陶杯", "credit", book: P, cat: "购物"),
           let k = l.transactions.firstIndex(where: { $0.id == id }) {
            l.transactions[k].original = ForeignAmount(amount: eur(45), currency: "USD")
        }
        // 暑假去海边城市玩几天。
        let aug = past(8)
        move(demoDay(aug, 9), eur(600), from: "daily", to: "wallet", "出门前给电子钱包充值", fromBook: P, toBook: P)
        spend(demoDay(aug, 2), eur(186), "Vuela Air 机票", "credit", P, "旅行")
        spend(demoDay(aug, 10), eur(420), "海边民宿", "wallet", P, "旅行")
        for k in 0..<4 { spend(demoDay(aug, 11 + k), rng.euros(14, 38), "旅行吃饭", "wallet", P, "旅行") }
        spend(demoDay(aug, 12), eur(6.8), "电车一日票", "wallet", P, "旅行")
        // 退款：退货、取消的外卖。冲减原来的分类，不算收入。
        earn(demoDay(past(7), 22), eur(39.95), "Tienda Mar 退货退款", "credit", P, "购物")
        earn(demoDay(past(10), 9), eur(18.4), "ComidaYa 订单取消退款", "wallet", P, "餐饮")
        earn(demoDay(months[9], 19), eur(42), "Vivero Mayor 坏花退款", "shop", S, "花材")
        spend(demoDay(months[5], 21), eur(185), "冷柜维修", "shop", S, "设备")
        // 私房钱：只有自己看。
        spend(demoDay(months[9], 8), eur(68), "偷偷买的香水", "stash", P, "购物")
        spend(demoDay(months[11], 13), eur(95), "演唱会门票", "stash", P, "娱乐")
        // 账本间转账：同一个钱箱里，店里的现金拿回家用。
        let day = demoDay(months[10], 16)
        _ = try? l.addTransfer(amount: eur(80), fromBook: S, toBook: P, accountID: "till", date: day, note: "店里现金拿回家买菜", author: "你")
        stamp(day)
    }

    // MARK: 借款往来

    mutating func debts() {
        let P = Self.P
        // 向姐姐借了 1.500 € 周转，隔一个月还 250 €。
        let sisterDay = demoDay(months[1], 12)
        if let sisResult = try? l.addDebt(counterparty: "姐姐", direction: .iOweThem, amount: eur(1500), bookID: P, date: sisterDay,
                                          accountID: "daily", dueDate: demoDay(demoShift(end.yearMonth, 4), 30), author: "你") {
            stamp(sisterDay)
            for k in [3, 5, 7, 9, 11] { repay(sisResult.0.id, eur(250), on: demoDay(months[k], 20), account: "daily", author: "Claude") }
        }
        // 借给阿杰 300 €，约好两个月还，只还了 100 €（过期了）。
        let ajDay = demoDay(months[7], 9)
        if let ajResult = try? l.addDebt(counterparty: "阿杰", direction: .theyOweMe, amount: eur(300), bookID: P, date: ajDay,
                                         accountID: "wallet", dueDate: demoDay(months[9], 30), note: "他搬家时周转", author: "Codex") {
            stamp(ajDay)
            repay(ajResult.0.id, eur(100), on: demoDay(months[10], 5), account: "wallet", author: "你")
        }
        // 帮 Lucía 垫了饭钱，三天后还清。
        let luDay = demoDay(months[10], 18)
        if let luResult = try? l.addDebt(counterparty: "Lucía", direction: .theyOweMe, amount: eur(45), bookID: P, date: luDay,
                                         accountID: "credit", author: "你") {
            stamp(luDay)
            repay(luResult.0.id, eur(45), on: demoDay(months[10], 21), account: "wallet", author: "你")
        }
    }

    mutating func repay(_ debt: UUID, _ amount: Money, on date: LocalDate, account: String, author: String) {
        guard date <= end else { return }
        _ = try? l.repay(debtID: debt, amount: amount, date: date, accountID: account, author: author)
        stamp(date)
    }

    // MARK: 改分类、分账本、撤销、没整理的

    mutating func edits(_ hardware: UUID?) {
        let prev = months[11], fixDay = demoDay(end.yearMonth, 6)
        // 上个月的猫粮被分到了「购物」，Codex 改成「宠物」。
        let pets = l.transactions.filter { $0.date.yearMonth == prev && $0.description.hasPrefix("Miau Miau") }.map(\.id)
        if !pets.isEmpty { l.categorize(pets, category: "宠物", author: "Codex"); stamp(fixDay, hour: 20) }
        if let hardware {
            _ = try? l.assignBook([hardware], bookID: Self.S, author: "Claude")
            stamp(fixDay, hour: 21)
        }
    }

    mutating func untidy() {
        // 这个月刚导入、还没整理的几笔（没分类、没分账本）。
        let ym = end.yearMonth, today = end.day
        let recent = { (back: Int) -> LocalDate in demoDay(ym, max(1, today - back)) }
        add(recent(1), eur(-31.15), "COMPRA TARJ. SUPER LUMI 4821", "credit", book: nil, cat: nil)
        add(recent(2), eur(-12.6), "COMPRA TARJ. BAZAR ORIENTE 7712", "credit", book: nil, cat: nil)
        add(recent(3), eur(60), "TRANSFERENCIA RECIBIDA M. ROSA", "daily", book: nil, cat: nil)
        // 记重了一笔，马上撤销。
        let dup = Transaction(date: end, amount: eur(-14.2), description: "菜市场", accountID: "cash", bookID: Self.P, category: "超市", source: "手记")
        if let change = try? l.addTransaction(dup, author: "你") {
            stamp(end)
            _ = try? l.undo(changeID: change.id, author: "你")
            stamp(end)
        }
    }

    /// 导入的流水每批（每个账户每个月）记一条改动：下个月初导入上个月的对账单，这个月的今天刚导入。
    mutating func closeBatches() {
        for key in batchOrder {
            guard let ids = batches[key], !ids.isEmpty, let first = l.transactions.first(where: { $0.id == ids[0] }) else { continue }
            let account = first.accountID, ym = first.date.yearMonth
            let fromStatement = Self.statementAccounts.contains(account)
            let name = accountName(account)
            let summary = fromStatement
                ? "导入 \(name) \(ids.count) 笔（\(name)-\(ym).csv，跳过重复 \(rng.int(0...2)) 笔）"
                : "补录 \(name) \(ym.month) 月 \(ids.count) 笔（从以前的记账表格）"
            let author = fromStatement ? rng.pick(["Claude", "Claude", "Claude", "Codex", "DeepSeek"]) : "Claude"
            l.record(.importBatch, summary, ids: ids, author: author)
            let when = ym == end.yearMonth ? end : demoDay(demoShift(ym, 1), rng.int(2...5))
            stamp(when)
            if fromStatement, let last = l.transactions.filter({ $0.accountID == account }).map(\.date).max() {
                l.lastStatementDate[account] = last
            }
        }
        batches = [:]
        batchOrder = []
    }

    /// 订阅：大部分登记了；视频会员登记的还是涨价前的价（app 会提示涨价）；健身 App 停了；
    /// 语言课每月扣、故意没登记，留给「从流水认出疑似订阅」。
    mutating func subscriptions() {
        let P = Self.P, S = Self.S
        func next(day: Int) -> LocalDate { end.day < day ? demoDay(end.yearMonth, day) : demoDay(demoShift(end.yearMonth, 1), day) }
        let monthly: [(String, Double, String?, String, String, String, Int, String)] = [
            ("StreamBox 视频会员", 11.99, nil, "credit", P, "streambox", 7, "你"),
            ("Tuneo 音乐会员", 10.99, nil, "credit", P, "tuneo", 15, "Claude"),
            ("云存储 50GB", 2.99, nil, "credit", P, "云存储", 3, "Claude"),
            ("FontHub 字体会员", 14.99, "USD", "usd", P, "fonthub", 11, "Codex"),
            ("收银系统月费", 29, nil, "shop", S, "收银系统", 5, "Claude"),
        ]
        for (k, m) in monthly.enumerated() {
            let sub = Subscription(name: m.0, amount: eur(m.1), currency: m.2, cycle: .monthly, nextDate: next(day: m.6),
                                   accountID: m.3, bookID: m.4, category: "订阅", match: m.5)
            _ = try? l.addSubscription(sub, author: m.7)
            stamp(demoDay(months[2], 4 + k))
        }
        let march = past(3)
        let yearly = Subscription(name: "网站和域名年费", amount: eur(96), cycle: .yearly,
                                  nextDate: demoDay(LocalDate(year: march.year, month: 3, day: 14) < end ? YearMonth(year: march.year + 1, month: 3) : march, 14),
                                  accountID: "shop", bookID: S, category: "订阅", match: "网站和域名")
        _ = try? l.addSubscription(yearly, author: "Claude")
        stamp(demoDay(months[2], 10))
        let fit = Subscription(name: "FitPlan 健身 App", amount: eur(7.99), cycle: .monthly, nextDate: demoDay(months[2], 20),
                               accountID: "credit", bookID: P, category: "订阅", match: "fitplan")
        _ = try? l.addSubscription(fit, author: "Claude")
        stamp(demoDay(months[2], 11))
        _ = try? l.cancelSubscription(fit.id, on: demoDay(months[8], 21), author: "你")
        stamp(demoDay(months[8], 21))
    }

    /// 期初余额：够这一年里每个账户都不透支（信用卡、储蓄罐除外）。
    mutating func openingBalances() {
        let base: [(String, Double)] = [("daily", 2400), ("wallet", 120), ("cash", 80), ("shop", 3500), ("till", 150), ("stash", 200), ("usd", 150)]
        let sorted = l.transactions.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
        for (account, amount) in base {
            var running: Int64 = 0, lowest: Int64 = 0
            for t in sorted where t.accountID == account {
                running += t.amount.cents
                lowest = min(lowest, running)
            }
            // 最低时也要剩 150 €，凑成整百。
            let need = max(Int64(amount * 100), (-lowest + 15_000 + 9_999) / 10_000 * 10_000)
            _ = try? l.setOpeningBalance(accountID: account, amount: Money(cents: need), date: start, author: "你")
        }
        stamp(start, hour: 11)
    }

    // MARK: 夏夏建议（数字从账本里算，和图表对得上）

    mutating func insights() {
        let hidden = l.privateAccountIDs
        let cur = end.yearMonth, prev = months[11]
        let all = l.baseTransactions
        // 上个月只看到同一天，比「同期」。
        let prevSame = all.filter { !($0.date.yearMonth == prev && $0.date.day > end.day) }
        func compare(_ diff: Money) -> String {
            diff.cents <= 0 ? "比上个月同期少 \(diff.magnitude.formatted)" : "比上个月同期多 \(diff.formatted)"
        }
        func top(_ s: MonthlySummary, _ n: Int) -> [(String, Money)] {
            s.byCategory.filter { $0.value.isExpense }.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.prefix(n).map { ($0.key, $0.value.magnitude) }
        }

        // 上个月的点评（已经看过了）。
        let last = Summaries.monthly(all, month: prev, bookID: nil, hiddenAccounts: hidden)
        let lastTop = top(last, 2).map { "「\($0.0)」\($0.1.formatted)" }.joined(separator: "、")
        write(Insight(month: prev, kind: .monthlyReview,
                      title: "\(prev.month) 月进账 \(last.income.formatted)，花了 \(last.expense.magnitude.formatted)，剩 \(last.net.formatted)。",
                      body: "花得最多的是\(lastTop)。应急金照常存了 250 €，店里的咖啡机分期也按时还了。", author: "Claude"),
              on: demoDay(cur, 1), hour: 9, dismissed: true)

        // 小店的本月点评（先写：看「全部」时显示后写的那条总的）。
        let shopNow = Summaries.monthly(all, month: cur, bookID: Self.S, hiddenAccounts: hidden)
        let shopBefore = Summaries.monthly(prevSame, month: prev, bookID: Self.S, hiddenAccounts: hidden)
        let diff = shopNow.income - shopBefore.income
        let flowers = (shopNow.byCategory["花材"] ?? .zero).magnitude
        write(Insight(month: cur, bookID: Self.S, kind: .monthlyReview,
                      title: "小店这个月到今天进账 \(shopNow.income.formatted)，\(diff.cents >= 0 ? "比上个月同期多 \(diff.formatted)" : "比上个月同期少 \(diff.magnitude.formatted)")。",
                      body: "花材进货花了 \(flowers.formatted)。装修基金每个月存 200 €，按计划走。", author: "Claude"), on: end, hour: 0)

        // 本月点评。
        let now = Summaries.monthly(all, month: cur, bookID: nil, hiddenAccounts: hidden)
        let before = Summaries.monthly(prevSame, month: prev, bookID: nil, hiddenAccounts: hidden)
        let nowTop = top(now, 2).map { "「\($0.0)」\($0.1.formatted)" }.joined(separator: "和")
        write(Insight(month: cur, kind: .monthlyReview,
                      title: "这个月到今天花了 \(now.expense.magnitude.formatted)，\(compare(now.expense.magnitude - before.expense.magnitude))。",
                      body: "花得最多的是\(nowTop)。房租和店租月初已经付了，月底还有员工工资和社保，店里账户的钱够。",
                      author: "Claude"), on: end, hour: 0)

        // 留意：个人账本里比上个月同期涨得最多的分类。
        let p = Summaries.monthly(all, month: cur, bookID: Self.P, hiddenAccounts: hidden)
        let pBefore = Summaries.monthly(prevSame, month: prev, bookID: Self.P, hiddenAccounts: hidden)
        let rises = p.byCategory.compactMap { e -> (String, Money, Money)? in
            guard e.value.isExpense else { return nil }
            let was = (pBefore.byCategory[e.key] ?? .zero).magnitude
            return (e.key, e.value.magnitude, was)
        }.sorted { ($1.1 - $1.2, $0.0) < ($0.1 - $0.2, $1.0) }
        if let r = rises.first, r.1 > r.2 {
            let (c, x, was) = r
            write(Insight(month: cur, kind: .alert, title: "「\(c)」比上个月同期多花了 \((x - was).formatted)",
                          body: "这个月到今天「\(c)」花了 \(x.formatted)，上个月同期是 \(was.formatted)。", metric: "category:\(c)",
                          page: "spending", author: "Claude"), on: end, hour: 0)
        } else if let t = top(p, 1).first {
            let (c, x) = t
            write(Insight(month: cur, kind: .alert, title: "这个月「\(c)」花得最多：\(x.formatted)",
                          body: "各项都没比上个月同期多，「\(c)」是大头，可以看看有没有能省的。", metric: "category:\(c)",
                          page: "spending", author: "Claude"), on: end, hour: 0)
        }

        // 好消息：应急金进度。
        if let g = Plans.goals(l).first(where: { $0.id == goalPot }) {
            let left = g.target - g.saved
            let monthsLeft = max(1, Int((left.cents + 24_999) / 25_000))
            write(Insight(month: cur, kind: .goodNews, title: "应急金存到 \(g.percent)% 了",
                          body: "已经存了 \(g.saved.formatted)，目标 \(g.target.formatted)。照每个月 250 € 的速度，再存 \(monthsLeft) 个月就满。",
                          page: "plans", author: "Codex"), on: end, hour: 0)
        }

        // 要处理：阿杰过期没还。
        if let aj = Plans.debts(l, today: end).first(where: { $0.counterparty == "阿杰" && $0.overdue }), let due = aj.dueDate {
            write(Insight(month: cur, kind: .action, title: "阿杰的 \(aj.outstanding.formatted) 过了约定日期还没还",
                          body: "约好 \(due.month) 月 \(due.day) 日前还清，已经还了 \(aj.repaid.formatted)。要不要提醒一下？",
                          page: "wealth", author: "Claude"), on: end, hour: 0)
        }

        // 建议：订阅。
        let subs = all.filter { $0.date.yearMonth == prev && $0.amount.isExpense && ($0.category == "订阅" || $0.description.hasPrefix("LINGUAPAL")) }
            .reduce(Money.zero) { $0 + $1.amount }.magnitude
        write(Insight(month: cur, kind: .tip, title: "订阅每个月扣 \(subs.formatted)，一年就是 \(Money(cents: subs.cents * 12).formatted)",
                      body: "StreamBox 视频会员从 11,99 € 涨到了 12,99 €；LinguaPal 语言课每月扣 9,99 €，还没记成订阅。不常用的可以停掉。",
                      page: "trends", author: "Claude"), on: end, hour: 0)
    }

    mutating func write(_ insight: Insight, on date: LocalDate, hour: Int, dismissed: Bool = false) {
        guard (try? l.addInsight(insight, author: insight.author)) != nil else { return }
        stamp(date, hour: hour)
        if let k = l.insights.firstIndex(where: { $0.id == insight.id }) {
            let at = l.changes[l.changes.count - 1].createdAt
            l.insights[k].createdAt = at
            if dismissed { l.insights[k].dismissedAt = at.addingTimeInterval(3600) }
        }
    }

    // MARK: 夏夏的记忆

    /// 示例记忆：规矩、记得的事、做事经验都有；有一条到期的、一条挂的订阅已经退了的、一条半年没动的，
    /// 这样「该整理了」的提示条在示例账本里看得到。全是编的。
    mutating func memories() {
        let S = Self.S
        let nextJan = LocalDate(year: end.year + 1, month: 1, day: 31)
        // 我的规矩
        memo(.rule, "还姐姐的钱", "还给姐姐的钱不算花销，算还款。", .said, by: "Claude", on: demoDay(months[3], 20),
             quote: "还我姐的钱别算进花销里", links: ["person:姐姐"])
        memo(.rule, "收益", "我说「收益」是指小店赚的钱（店里收入减店里开销），不包括工资。", .corrected, by: "Claude", on: demoDay(months[6], 8),
             quote: "我问收益是问店里赚了多少，不是问工资", story: "第一次问「这个月收益多少」，答成了工资加店里收入的合计。", links: ["book:\(S)"])
        memo(.rule, "记账习惯", "咖啡、奶茶都记在「餐饮」，不单独分一类。", .written, by: "你", on: demoDay(months[8], 14))
        // 记得的事
        memo(.topic, "工资", "6 月和 12 月各多发一份双薪。", .confirmed, by: "Claude", on: demoDay(months[7], 28), links: ["category:工资"])
        memo(.topic, "工资", "明年 1 月起每月涨 120 €。", .said, by: "Claude", on: demoDay(months[11], 6),
             quote: "老板说明年一月给我涨一百二", reviewOn: nextJan)
        memo(.topic, "房租", "合同签到明年 8 月底，到期可能要涨。", .said, by: "Codex", on: demoDay(months[9], 2), links: ["category:房租"])
        memo(.topic, "阿杰借的钱", "他说月底前把剩下的 200 € 还清。", .said, by: "你", on: demoDay(months[10], 5),
             reviewOn: demoDay(months[11], 28), links: ["person:阿杰"])
        memo(.topic, "FitPlan 健身 App", "试用完觉得不值，已经退了，不用再提醒续费。", .said, by: "Claude", on: demoDay(months[8], 21),
             links: ["subscription:FitPlan 健身 App"])
        memo(.topic, "夏天去海边", "夏天想去海边玩一周，预算 800 € 左右。", .said, by: "Claude", on: demoDay(months[1], 15))
        // 做事经验
        memo(.lesson, "导入对账单", "信用卡对账单里的「信用卡还款」是自己账户之间转钱，要标成账户互转，别记成支出。", .corrected, by: "Claude",
             on: demoDay(months[9], 3), story: "第一次导入时把还款也算成了支出，那个月的花销多出一大截，后来改成账户互转才对上。")
        memo(.lesson, "对账", "先对日常账户，再对电子钱包：钱包充值会在两边各出现一次，别当成漏记。", .observed, by: "Codex", on: demoDay(months[10], 2))
        if let i = l.memories.firstIndex(where: { $0.title == "还姐姐的钱" }) { l.memories[i].pinned = true }
    }

    /// 记一条示例记忆，时间定在那一天（不用「现在」：同一个种子每次生成的要一模一样）。
    mutating func memo(_ kind: Memory.Kind, _ title: String, _ text: String, _ source: Memory.Source, by author: String, on date: LocalDate,
                       quote: String? = nil, story: String? = nil, reviewOn: LocalDate? = nil, links: [String] = []) {
        guard (try? l.remember(kind: kind, title: title, text: text, source: source, quote: quote, story: story, date: date,
                               reviewOn: reviewOn, links: links, allowNew: true, author: author)) != nil else { return }
        let at = moment(min(date, demoDay(months[11], 28)), 21, 10 + l.memories.count)
        l.changes[l.changes.count - 1].createdAt = at
        stamped = l.changes.count
        guard let i = l.memories.firstIndex(where: { $0.title == title }) else { return }
        if l.memories[i].notes.count == 1 { l.memories[i].createdAt = at }
        l.memories[i].updatedAt = at
        l.memories[i].notes[l.memories[i].notes.count - 1].createdAt = at
    }

    // MARK: 收尾

    /// 排好顺序，把所有随机 id 换成由种子算出来的固定 id。
    mutating func finish() -> Ledger {
        // 同一天里期初余额排最前。
        l.transactions = l.transactions.enumerated()
            .sorted { ($0.element.date, $0.element.flow == .opening ? 0 : 1, $0.offset) < ($1.element.date, $1.element.flow == .opening ? 0 : 1, $1.offset) }
            .map(\.element)
        l.changes = l.changes.enumerated()
            .sorted { ($0.element.createdAt, $0.offset) < ($1.element.createdAt, $1.offset) }.map(\.element)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(l),
              let regex = try? NSRegularExpression(pattern: "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}") else { return l }
        let text = String(decoding: data, as: UTF8.self) as NSString
        var ids = DemoRandom(seed: rng.next())
        var map: [String: String] = [:]
        var out = ""
        var cursor = 0
        for m in regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let old = text.substring(with: m.range)
            let new: String
            if let known = map[old] { new = known } else { new = ids.uuidString(); map[old] = new }
            out += text.substring(with: NSRange(location: cursor, length: m.range.location - cursor)) + new
            cursor = m.range.location + m.range.length
        }
        out += text.substring(from: cursor)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Ledger.self, from: Data(out.utf8))) ?? l
    }
}
