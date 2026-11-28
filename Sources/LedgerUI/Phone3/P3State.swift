#if os(iOS)
import FinanceCore
import SwiftUI

/// iPhone 界面 v3 的开关：包里写了 XiaxiaV3，或启动参数带 `-XiaxiaV3`（`-XiaxiaV3 0` 关）。
public enum PhoneV3Launch {
    public static var enabled: Bool {
        if Bundle.main.object(forInfoDictionaryKey: "XiaxiaV3") as? Bool == true { return true }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-XiaxiaV3") else { return false }
        return i + 1 >= args.count || args[i + 1] != "0"
    }
    static func value(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

/// iPhone v3 的全部状态。数字都是编的示例，只在内存里：不读、不写任何账本文件。
@MainActor @Observable
final class P3State {
    typealias Book = TrialBook
    typealias Side = TrialBook.Side

    enum Tab: String { case home, flow, goals, xia }

    enum Page: String, Hashable, Identifiable {
        case spending, wealth, debts, subscriptions, memory, changes, sides, ai
        case sales, shopWealth, fixed, shopDebts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .spending: "花销"
            case .wealth: "家底"
            case .debts: "欠款与还债"
            case .subscriptions: "订阅"
            case .memory: "夏夏记住的事"
            case .changes: "改动记录"
            case .sides: "管哪边"
            case .ai: "夏夏的 AI"
            case .sales: "营业额"
            case .shopWealth: "店的家底"
            case .fixed: "固定开销"
            case .shopDebts: "店的欠款"
            }
        }
        var symbol: String {
            switch self {
            case .spending: "chart.pie"
            case .wealth, .shopWealth: "wallet.bifold"
            case .debts, .shopDebts: "creditcard"
            case .subscriptions: "arrow.triangle.2.circlepath"
            case .memory: "brain"
            case .changes: "clock.arrow.circlepath"
            case .sides: "square.split.2x1"
            case .ai: "sparkles"
            case .sales: "calendar"
            case .fixed: "calendar.badge.clock"
            }
        }
    }

    enum Sheet: Identifiable, Equatable {
        case add
        case edit(UUID)
        case save(UUID?)
        case holdBack
        case smallerStep
        case newBigGoal
        case editBigGoal
        case smallGoal(UUID?)
        var id: String {
            switch self {
            case .add: "add"
            case .edit(let i): "edit-\(i)"
            case .save(let i): "save-\(i?.uuidString ?? "big")"
            case .holdBack: "hold"
            case .smallerStep: "smaller"
            case .newBigGoal: "newBig"
            case .editBigGoal: "editBig"
            case .smallGoal(let i): "small-\(i?.uuidString ?? "new")"
            }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var canUndo = false
        var isError = false
    }

    private(set) var ledger: TrialLedger
    var book: Book { ledger.book }
    var author = "你"
    var tab: Tab = .home
    var side: Side = .life
    /// 0 = 这个月（示例里是 11 月），-1 = 上个月…
    var monthOffset = 0
    var sheet: Sheet?
    /// 「我的」：从总览右上角的头像点开（底部那格让给了夏夏）。
    var meOpen = false
    /// 长按中间的 + 选了「拍照」「说话」：打开夏夏后马上开相机 / 开始听。用一次就清掉。
    enum ChatIntent { case camera, voice }
    var chatIntent: ChatIntent?
    /// 打开记一笔时先摆好的：收入还是花的、哪天（营业额日历点某一天用）。用一次就清掉。
    var addPreset: (income: Bool, daysAgo: Int)?
    var mePath: [Page] = []
    var toast: Toast?
    var chat = P3Chat()
    let ai = P3AI()
    /// 每存一笔加 1（星星掉进瓶子用）。
    var starDrops = 0

    private var toastTask: Task<Void, Never>?

    init() {
        ledger = TrialLedger(book: Self.demoBook, changes: Self.demoChanges)
        if let s = PhoneV3Launch.value("-P3Side"), s == "biz" { side = .biz }
        if let t = PhoneV3Launch.value("-P3Tab"), let tab = Tab(rawValue: t) { self.tab = tab }
        if let p = PhoneV3Launch.value("-P3Page"), let page = Page(rawValue: p) { meOpen = true; mePath = [page] }
        if PhoneV3Launch.value("-P3Me") != nil { meOpen = true }
        if let m = PhoneV3Launch.value("-P3Month"), let n = Int(m) { monthOffset = n }
        switch PhoneV3Launch.value("-P3Sheet") {
        case "add": sheet = .add
        case "smaller": sheet = .smallerStep
        case "save": sheet = .save(nil)
        default: break
        }
        if PhoneV3Launch.value("-P3Chat") != nil { tab = .xia; chat.unread = 0 }
        if PhoneV3Launch.value("-P3NoGoal") != nil { ledger.patch { try? $0.removeBigGoal() } }
        if PhoneV3Launch.value("-P3Chat") == "want" { chat.demoWant(book: book) }
    }

    // MARK: 月份

    /// 示例里的「今天」：2026 年 11 月 18 日。
    var monthNumber: Int { ((11 - 1 + monthOffset) % 12 + 12) % 12 + 1 }
    var monthTitle: String {
        let year = 2026 + Int((Double(11 - 1 + monthOffset) / 12).rounded(.down))
        return year == 2026 ? "\(monthNumber) 月" : "\(year) 年 \(monthNumber) 月"
    }
    var isThisMonth: Bool { monthOffset == 0 }
    func flipMonth(_ d: Int) {
        let next = monthOffset + d
        guard next <= 0, next >= -11 else { return }
        withAnimation(.snappy(duration: 0.2)) { monthOffset = next }
    }
    /// 上个月的花销（示例只有上个月有数，再早就是空的）。
    var pastSlices: [Book.SpendSlice] {
        guard monthOffset == -1 else { return [] }
        return book.spendByCategory.map { .init(emoji: $0.emoji, name: $0.name, amount: $0.lastMonth, lastMonth: .zero) }.filter { $0.amount > .zero }
    }
    /// 这个月的花销：示例里分好类的那些，加上在手机上刚记的（还没归进那几类的合成「刚记的」），总数和总览对得上。
    var thisMonthSlices: [Book.SpendSlice] {
        var s = book.spendSlices(limit: 8)
        let extra = book.month.spentTotal - book.spendSliceTotal
        if extra > .zero { s.append(.init(emoji: "🧾", name: "刚记的", amount: extra, lastMonth: .zero)) }
        return s.sorted { $0.amount > $1.amount }
    }
    /// 示例里上个月的几个数（和 Mac 试用版同一套）：上个月同期花了多少、上个月底家底净剩多少。
    var lastMonthSpentSoFar: Money { Money(cents: 1_249_39) }
    var lastMonthNet: Money { Money(cents: 2_170_61) }
    /// 「比上个月多 / 少 …」，跟着数变。
    func compare(_ now: Money, _ before: Money, more: String = "多", less: String = "少") -> String {
        let d = now - before
        return d == .zero ? "和上个月一样" : d > .zero ? "比上个月\(more) \(d.p3Short)" : "比上个月\(less) \(d.magnitude.p3Short)"
    }
    var lastMonthIncome: Money { Money(cents: 2_340_00) }

    // MARK: 做一件事：马上有回应，能撤销

    func say(_ text: String) { show(Toast(text: text)) }
    func fail(_ text: String) { show(Toast(text: text, isError: true)) }

    @discardableResult
    func change(_ text: String, kind: ChangeRecord.Kind = .edit, _ body: (inout Book) throws -> Void) -> Bool {
        do {
            try withAnimation(.spring(duration: 0.45)) { _ = try ledger.apply(kind, text, author: author, body) }
            show(Toast(text: text, canUndo: true))
            return true
        } catch let e as TrialError {
            fail(e.message)
        } catch {
            fail("没做成，再试一次")
        }
        return false
    }

    func undo() {
        guard let last = ledger.lastUndoable else { say("没有能撤销的了"); return }
        undo(change: last.id)
    }

    func undo(change id: UUID) {
        do {
            var n = 0
            try withAnimation(.spring(duration: 0.45)) { n = try ledger.undo(id) }
            settleSide()
            show(Toast(text: n > 1 ? "撤销了，连后面的 \(n - 1) 步一起" : "撤销了"))
        } catch let e as TrialError { fail(e.message) } catch { fail("没撤成，再试一次") }
    }

    func canUndo(_ id: UUID) -> Bool { ledger.canUndo(id) }

    private func show(_ t: Toast) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.18, bounce: 0.35)) { toast = t }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(t.isError ? 4 : t.canUndo ? 4 : 2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) { self?.toast = nil }
        }
    }

    // MARK: 生活、生意

    func switchSide(_ s: Side) {
        guard s != side, s == .biz ? book.showBiz : book.showLife else { return }
        withAnimation(.snappy(duration: 0.2)) {
            side = s
            if tab == .goals && s == .biz { tab = .home }
        }
    }

    func settleSide() {
        if side == .biz, !book.showBiz { side = .life }
        if side == .life, !book.showLife { side = .biz }
    }

    func setSides(life: Bool, biz: Bool) {
        guard life || biz else { fail("至少要管一边"); return }
        let text = life && biz ? "好，两边都管" : life ? "好，只管生活。生意的账还在" : "好，只管生意。生活的账还在"
        change(text) { try $0.setSides(life: life, biz: biz) }
        settleSide()
    }

    func go(_ page: Page) {
        mePath = [page]
        meOpen = true
    }

    // MARK: 目标

    @discardableResult
    func deposit(_ amount: Money, from: String? = nil) -> Bool {
        let ok = change("存好了 +\(amount.p3Short) · 瓶里多了一颗星", kind: .goalDeposit) { try $0.deposit(amount, from: from) }
        if ok { starDrops += 1 }
        return ok
    }

    // MARK: 示例数据（和 Mac v3 试用版同一套，全是编的）

    static func eur(_ s: String) -> Money { Money(parsing: s) ?? .zero }

    static let demoChanges: [ChangeRecord] = {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date() }
        return [
            ChangeRecord(kind: .capture, summary: "记一笔：午饭 12,50 € · 日常卡", transactionIDs: [], author: "拍小票", createdAt: at(13, 5)),
            ChangeRecord(kind: .categorize, summary: "「Super Sol」归进超市，以后这家店都这样", transactionIDs: [], author: "夏夏", createdAt: at(10, 42)),
            ChangeRecord(kind: .importBatch, summary: "导入「晴空银行 11 月流水」31 笔，跳过重复 6 笔", transactionIDs: [], author: "流水导入", createdAt: at(10, 40)),
            ChangeRecord(kind: .add, summary: "记一笔：咖啡 3,20 € · 现金", transactionIDs: [], author: "Claude", createdAt: at(9, 12)),
            ChangeRecord(kind: .goalDeposit, summary: "存一笔 20 € 进「换新电脑」", transactionIDs: [], author: "你", createdAt: at(8, 30)),
        ]
    }()

    static var demoBook: Book {
        var j = Journey(name: "换新电脑", why: "为了剪自己的片子",
                        stations: [
                            .init(id: 0, target: .zero, title: "出发"),
                            .init(id: 1, target: eur("50"), title: "第一步"),
                            .init(id: 2, target: eur("200")),
                            .init(id: 3, target: eur("700"), title: "走到一半"),
                            .init(id: 4, target: eur("1050")),
                            .init(id: 5, target: eur("1400"), title: "电脑到手"),
                        ],
                        saved: eur("519"), monthlyPlan: eur("200"), savedThisMonth: eur("80"), resisted: 13)
        j.resisted = 13
        func item(_ e: String, _ n: String, _ note: String, _ a: String, tag: String = "", off: Bool = false, flag: Bool = false) -> TrialBook.Item {
            .init(emoji: e, name: n, note: note, amount: eur(a), tag: tag, off: off, flag: flag)
        }
        typealias Account = TrialBook.Account
        typealias Entry = TrialBook.Entry
        var b = Book(
            accounts: [
                Account(emoji: "💳", name: "日常卡", note: "晴空银行 · 今天刚导入", balance: eur("1496,61")),
                Account(emoji: "🏦", name: "储蓄", note: "存着 · 不动", balance: eur("2400"), block: .emergency, short: "储蓄"),
                Account(emoji: "⭐", name: "换新电脑 存钱罐", note: "存给「换新电脑」", balance: eur("519"), block: .goal),
                Account(emoji: "🧳", name: "周末短途旅行 存钱罐", note: "存给「周末短途旅行」", balance: eur("120"), block: .goal),
                Account(emoji: "👟", name: "新跑鞋 存钱罐", note: "存给「新跑鞋」", balance: eur("60"), block: .goal),
                Account(emoji: "🎁", name: "给妈妈的生日礼物 存钱罐", note: "存给「给妈妈的生日礼物」", balance: eur("15"), block: .goal),
                Account(emoji: "💶", name: "现金", note: "钱包里 · 上次点数 11 月 10 日", balance: eur("85")),
                Account(emoji: "🏪", name: "小店账户", note: "店的银行卡 · 晴空银行", balance: eur("3679,39"), kind: .shop, block: .shop),
                Account(emoji: "💶", name: "店里现金", note: "收银抽屉里", balance: eur("240"), kind: .shop, block: .shop),
                Account(emoji: "💳", name: "店的信用卡", note: "欠 · 每月 10 日还", balance: eur("180"), kind: .debt, block: .none, side: .biz),
                Account(emoji: "🏦", name: "装修贷款", note: "欠 · 还剩 24 期，每月 350 €", balance: eur("8400"), kind: .debt, block: .none, side: .biz),
                Account(emoji: "💳", name: "信用卡", note: "欠 · 12 月 5 日要还", balance: eur("640"), kind: .debt, block: .none, short: "信用卡 · 欠"),
                Account(emoji: "📱", name: "手机分期", note: "欠 · 还剩 6 期，每月 200 €", balance: eur("1200"), kind: .debt, block: .none, short: "手机分期 · 欠"),
                Account(emoji: "🧑", name: "借给小李", note: "他欠我 · 说好 12 月还", balance: eur("120"), kind: .lent, block: .none, short: "小李欠我"),
            ],
            entries: [
                Entry(emoji: "🛒", name: "超市", meta: "Super Sol · 日常卡", amount: eur("-23,40"), tag: "流水导入", place: "Super Sol", account: "日常卡"),
                Entry(emoji: "☕", name: "咖啡", meta: "Café Nube · 现金", amount: eur("-3,20"), tag: "跟 AI 说的", place: "Café Nube", account: "现金"),
                Entry(emoji: "🥗", name: "午饭", meta: "La Tasca · 日常卡", amount: eur("-12,50"), tag: "拍小票", place: "La Tasca", account: "日常卡"),
                Entry(emoji: "💼", name: "私活进账", meta: "小林工作室 · 日常卡", amount: eur("420"), tag: "流水导入", daysAgo: 1, place: "小林工作室", account: "日常卡"),
                Entry(emoji: "❓", name: "Super Lumi", meta: "Super Lumi · 日常卡", amount: eur("-18,60"), tag: "等你看一眼", daysAgo: 1, place: "Super Lumi", account: "日常卡"),
                Entry(emoji: "🚇", name: "地铁", meta: "十次票 · 日常卡", amount: eur("-12,20"), daysAgo: 1, place: "地铁", account: "日常卡"),
                Entry(emoji: "🔁", name: "音乐", meta: "每月 · 日常卡", amount: eur("-10,99"), daysAgo: 2, place: "音乐", account: "日常卡"),
                Entry(emoji: "☕", name: "咖啡", meta: "Café Nube · 现金", amount: eur("-2,80"), daysAgo: 2, place: "Café Nube", account: "现金"),
                Entry(emoji: "🛒", name: "超市", meta: "Super Sol · 日常卡", amount: eur("-31,75"), daysAgo: 3, place: "Super Sol", account: "日常卡"),
                Entry(emoji: "🥡", name: "外卖", meta: "晚饭 · 信用卡", amount: eur("-14,90"), daysAgo: 4, place: "外卖", account: "信用卡"),
            ],
            upcoming: [
                Entry(emoji: "🏠", name: "房租", meta: "12 月 1 日 · 13 天后", amount: eur("650")),
                Entry(emoji: "💳", name: "信用卡", meta: "12 月 5 日 · 日常卡够付", amount: eur("640"), red: true),
                Entry(emoji: "📱", name: "手机分期", meta: "12 月 8 日 · 第 7 / 12 期", amount: eur("200"), red: true),
            ],
            month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
            journey: j,
            letters: [],
            splitWithEmergency: nil,
            monthlyMust: eur("860"))
        b.usualDailySpend = eur("31")
        b.smallGoals = [
            .init(name: "周末短途旅行", target: eur("300"), saved: eur("120"), due: "明年 3 月前"),
            .init(name: "新跑鞋", target: eur("95"), saved: eur("60"), due: "12 月底前"),
            .init(name: "给妈妈的生日礼物", target: eur("80"), saved: eur("15"), due: "明年 2 月 9 日前"),
        ]
        b.spendByCategory = [
            .init(emoji: "🏠", name: "房租", amount: eur("650"), lastMonth: eur("650")), .init(emoji: "📱", name: "手机分期", amount: eur("200"), lastMonth: eur("200")),
            .init(emoji: "🛒", name: "超市", amount: eur("142,19"), lastMonth: eur("162")), .init(emoji: "🥗", name: "餐饮", amount: eur("68,40"), lastMonth: eur("104")),
            .init(emoji: "🔁", name: "订阅", amount: eur("42"), lastMonth: eur("42")), .init(emoji: "🚇", name: "交通", amount: eur("32"), lastMonth: eur("32")),
            .init(emoji: "☕", name: "咖啡", amount: eur("28,80"), lastMonth: eur("45,50")),
        ]
        b.subscriptions = [
            item("☁️", "云盘 Plus", "12 月 2 日扣 · 3 个月没怎么用", "4,99", tag: "可以考虑退"),
            item("🎬", "视频会员", "12 月 4 日扣 · 和另一个重了", "9,99", tag: "可以考虑退"),
            item("🎵", "音乐", "12 月 9 日扣", "10,99"),
            item("✂️", "剪辑软件", "12 月 15 日扣", "12,04", tag: "赚钱用的", flag: true),
            item("📰", "新闻", "12 月 21 日扣", "3,99"),
        ]
        func fixed(_ e: String, _ n: String, _ day: Int, _ a: String, last: String? = nil) -> TrialBook.Item {
            .init(emoji: e, name: n, note: "每月 \(day) 日 · 小店账户", amount: eur(a), account: "小店账户", day: day, lastMonth: last.map { eur($0) })
        }
        b.fixedCosts = [
            fixed("🧑", "给自己发的工资", 1, "1000"),
            fixed("🏠", "店面房租", 3, "600"),
            fixed("📣", "广告", 10, "80"),
            fixed("💡", "水电", 15, "70", last: "58"),
            fixed("🗓", "预约软件", 20, "40", last: "35"),
        ]
        b.shopDebts = [item("📦", "供货商赊账", "12 月 3 日到期", "320"), item("🧑", "熟客挂账", "11 月 9 日 · 说下次来付", "85", flag: true)]
        b.memos = [
            .init(kind: .topic, topic: "我想要的", lines: ["三年后不用为钱发愁", "先换台电脑，剪自己的片子"], source: "你说的", important: true),
            .init(kind: .rule, topic: "转给妈妈的钱", lines: ["每月 5 日转 150 €，不算支出，算家里的"], source: "你纠正的"),
            .init(kind: .topic, topic: "Café Nube", lines: ["付现金。一周超过 4 次时说一声"], source: "你说的"),
            .init(kind: .rule, topic: "超过 100 € 的东西", lines: ["先放进想要清单冷静 48 小时"], source: "你说的"),
            .init(kind: .rule, topic: "店里和家里", lines: ["店里的钱不拿来付家里的开销，要用就走「两边转钱」"], source: "你说的"),
        ]
        // 11 月每天收了多少：和 Mac 试用版同一个算法。周日休息；16 号没记；18 号是今天，还没记。
        var r = 11.0
        for d in 1...30 {
            r = (r * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
            let wd = (d + 5) % 7
            var amt = 120 + Int((r / 233280 * 140).rounded())
            if wd == 5 { amt += 170 }
            let state: TrialBook.ShopDay.State = d > 18 ? .future : wd == 6 ? .rest : d == 16 || d == 18 ? .missing : .open
            let cash = state == .open ? Money(cents: Int64(amt * 2 / 5) * 100) : .zero
            let card = state == .open ? Money(cents: Int64(amt) * 100) - cash : .zero
            b.shopDays.append(.init(day: d, cash: cash, card: card, state: state))
        }
        func spend(_ day: Int, _ cat: String, _ what: String, _ a: String, from: String = "小店账户") {
            let c = TrialBook.shopCategories.first { $0.name == cat } ?? TrialBook.Category("🧾", "其他")
            b.entries.append(.init(emoji: c.emoji, name: c.name, meta: "\(what) · \(from)", amount: -eur(a), tag: "自己记的", daysAgo: 18 - day,
                                   side: .biz, place: what, account: from))
        }
        spend(17, "设备", "新花剪两把", "24,90", from: "店里现金")
        spend(15, "水电网", "11 月水电", "70")
        spend(14, "维修", "修冷柜", "60", from: "店里现金")
        spend(12, "进货", "鲜花补货", "340")
        spend(10, "广告", "街区小报广告", "80", from: "店的信用卡")
        spend(9, "交通运输", "送花的油费", "35", from: "店里现金")
        spend(5, "包装耗材", "包装纸和丝带", "46")
        spend(3, "房租", "店面房租", "600")
        // 一个目标对一个账户：各自的存钱罐（和 Mac 试用版一样）
        b.bigGoalAccount = b.account("换新电脑 存钱罐")?.id
        for i in b.smallGoals.indices { b.smallGoals[i].account = b.account(TrialBook.jarName(b.smallGoals[i].name))?.id }
        for n in ["日常卡", "换新电脑 存钱罐", "储蓄", "信用卡", "小店账户", "店里现金", "店的信用卡"] { try? b.setPinned(n, true) }
        return b
    }
}

#endif
