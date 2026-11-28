#if os(macOS)
import FinanceCore
import SwiftUI

/// 界面 v3 开发版的全部状态。数字是设计稿里那套编的示例，只在内存里：不读、不写任何账本文件。
@MainActor @Observable
final class V3State {
    enum Mode: String { case life, biz, both }
    enum Side { case life, biz }

    enum Page: String, CaseIterable, Identifiable {
        case overview, goals, wealth, spending, trends, transactions, subscriptions, debts, monthly
        case settings
        case bizHome, sales, shopFlow, shopWealth, fixed, payback, stock, checkup, bizDebts
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "总览"
            case .goals: "目标"
            case .wealth: "家底"
            case .spending: "花销"
            case .trends: "趋势"
            case .transactions: "流水"
            case .subscriptions: "订阅"
            case .debts: "欠款与还债"
            case .monthly: "每月小结"
            case .settings: "设置"
            case .bizHome: "生意首页"
            case .sales: "营业额"
            case .shopFlow: "流水"
            case .shopWealth: "店的家底"
            case .fixed: "固定开销"
            case .payback: "回本"
            case .stock: "货值"
            case .checkup: "店的体检"
            case .bizDebts: "欠款"
            }
        }
        var symbol: String {
            switch self {
            case .overview: "house"
            case .goals: "flag"
            case .wealth: "wallet.bifold"
            case .spending: "chart.pie"
            case .trends: "waveform.path.ecg"
            case .transactions, .shopFlow: "list.bullet"
            case .subscriptions: "arrow.triangle.2.circlepath"
            case .debts, .fixed, .bizDebts: "creditcard"
            case .monthly: "doc.text"
            case .settings: "gearshape"
            case .bizHome: "storefront"
            case .sales: "calendar"
            case .shopWealth: "building.columns"
            case .payback: "flag"
            case .stock: "shippingbox"
            case .checkup: "waveform.path.ecg"
            }
        }
        // 哪页属于哪边写在核心里一处（TrialBook.lifePages / bizPages），这里只是换成页面。
        static let life: [Page] = TrialBook.lifePages.compactMap(Page.init(rawValue:))
        static let biz: [Page] = TrialBook.bizPages.compactMap(Page.init(rawValue:))
        /// 导航里一组一组的页面（组之间画细线）。
        static func groups(_ side: Side) -> [[Page]] { (side == .biz ? TrialBook.bizGroups : TrialBook.lifeGroups).map { $0.compactMap(Page.init(rawValue:)) } }
    }

    // 账本里的东西都在核心（FinanceCore/TrialBook.swift）里，这里只起个短名字。
    typealias Account = TrialBook.Account
    typealias Entry = TrialBook.Entry
    typealias Letter = TrialBook.Letter
    typealias Book = TrialBook

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var canUndo = false
        /// 没做成：不带撤销，停久一点。
        var isError = false
    }

    // MARK: 状态

    /// 试用账本 + 改动记录。写入只走 change(…)，规则都在核心里。
    private(set) var ledger: TrialLedger
    var book: Book { ledger.book }
    /// 记账人：写进每条改动记录。
    var author = "你"
    var page: Page = .overview
    var side: Side = .life
    /// 管哪边（存在账本里：showLife / showBiz）。引导里选的就是给这两个开关设初值，不留改动记录。
    var mode: Mode {
        get { book.showLife && book.showBiz ? .both : book.showBiz ? .biz : .life }
        set { patch { try? $0.setSides(life: newValue != .biz, biz: newValue != .life) }; settleSide() }
    }
    var showsLife: Bool { book.showLife }
    var showsBiz: Bool { book.showBiz }

    /// 设置里改「管哪边」：留改动记录，能撤销。想把最后一个也关掉：不改，返回 false（开关自己弹回去）。
    @discardableResult
    func setSides(life: Bool, biz: Bool) -> Bool {
        guard life || biz else { return false }
        let text = life && biz ? "好，两边都管" : life ? "好，只管生活。生意的账还在" : "好，只管生意。生活的账还在"
        let ok = change(text) { try $0.setSides(life: life, biz: biz) }
        settleSide()
        return ok
    }

    /// 正停在被关掉的那一边：换到还开着的那边的第一页。
    func settleSide() {
        if side == .biz, !book.showBiz { side = .life }
        if side == .life, !book.showLife { side = .biz }
        if !book.shows(page: page.rawValue) { page = side == .biz ? .bizHome : .overview }
    }
    /// 引导走到第几步（0…4）；nil = 引导走完了。
    var onboardingStep: Int? = 0
    /// 引导里写的那句想要的（存进夏夏的记忆）。
    var wish = ""
    /// 连着哪个 AI；nil = 没连。
    var ai: String?
    var toast: Toast?
    /// 每存一笔加 1，星星瓶就掉一颗星。
    var starDrops = 0
    var showAddAccount = false
    /// 打开「记今天的账」时直接停在「店里的开销」。
    var shopDayExpense = false
    var showAdd = false
    /// 正开着的弹窗（自己填、存一笔、改分类……）。
    var sheet: V3Sheet?
    /// 和夏夏聊天的那一页开着没有。
    var chatOpen = false
    var chat: [ChatMessage] = []
    /// 夏夏的消息：正滑下来的那句、收成小红点的那句、今天点掉的、今天说了几句、这一页说过没有。
    var sayCardID: String?
    var sayUnreadID: String?
    var sayDismissed: Set<String> = []
    var sayPopsToday = 0
    var sayPoppedThisPage = false
    var sayReplay = 0
    @ObservationIgnored var sayTask: Task<Void, Never>?
    /// 「花钱前想想」里的第二种：大决定。
    /// 设置里点进去的改动记录。
    var showLog = false
    /// 设置里正开着的那一页（nil = 设置首页）。
    var settingsSub: SettingsSub?
    /// 上锁：规则、现在锁没锁、谁来验证。
    var lockPolicy = V3State.savedLockPolicy()
    var locked = false
    var unlocking = false
    var awaySince: Date?
    var authenticator: V3Authenticator = V3State.defaultAuthenticator()
    /// 「存一笔」小窗先选中哪个小目标（nil = 大目标）。
    var saveTarget: UUID?
    /// 正在导入的那份流水读到第几笔了（没在导入是 nil）。
    var importProgress: (name: String, read: Int, total: Int)?
    var importTask: Task<Void, Never>?
    /// 夏夏最后说的一句和时间（左下角那一行会话的预览）。
    var lastSaid: (text: String, at: Date)?
    /// 聊天输入框上面带着的那张图或那个链接。
    var chatAttachment: V3Attachment?
    /// 夏夏刚问了「多少钱？」，在等价钱的那样东西。
    var pendingWant: String?
    /// 查到的新版本号（没有就是 nil）。试用版不会真的去查，用 `-XiaxiaV3FakeUpdate` 演示。
    var updateVersion: String?
    /// 放 AI 密钥的地方（app 里是钥匙串）。密钥存进去以后不再读出来。
    var keyStore: SecretStore = V3State.defaultKeyStore()
    /// 密钥存了 / 删了就加一，让界面重新问一次「有没有」。
    var keyRevision = 0
    /// 从别的页点过来：流水页要选中哪一笔、先搜什么；管理账户先选中谁；自己填先填好什么。
    var txFocus: UUID?
    var txQuery: String?
    var accountFocus: String?
    var manualPrefill: (name: String, amount: Money)?
    /// 硬摆出来的「在读 / 出错」（重新读取时、截图检查时）。
    var forced: Forced?
    var prefs = V3Prefs()
    var aiLinks = V3AILink.demo
    var backups = V3Backup.demo
    /// 目标的三个时刻：定第一步、改小步子、到站的信。
    var moment: V3Moment?

    let today = "11 月 18 日 · 周三"
    let lastMonthNetDelta = Money(cents: 490_00)
    let spentLessThanLastMonth = Money(cents: 86_00)

    private var toastTask: Task<Void, Never>?
    private var localUndo: (() -> Void)?

    init() { ledger = TrialLedger(book: Self.demoBook, changes: Self.demoChanges) }

    // MARK: 做一件事：马上有回应，能撤销

    func say(_ text: String) { localUndo = nil; show(Toast(text: text)) }

    /// 不进账本的小改动（引导里删一行账户）：提示条也带「撤销」，点了就做 `undo`。
    func say(_ text: String, undo: @escaping () -> Void) {
        localUndo = undo
        show(Toast(text: text, canUndo: true))
    }

    /// 没做成时说人话：不带撤销，停 5 秒。
    func fail(_ text: String) { show(Toast(text: text, isError: true)) }

    /// 改账本里的东西：规则在核心里（body 里调用 TrialBook 的方法），记一条改动记录（写明记账人），底部弹提示带「撤销」。
    /// 做不成就什么都不变，底部说清为什么。返回做成了没有。
    @discardableResult
    func change(_ text: String, kind: ChangeRecord.Kind = .edit, _ body: (inout Book) throws -> Void) -> Bool {
        do {
            try withAnimation(.spring(duration: 0.45)) { _ = try ledger.apply(kind, text, author: author, body) }
            localUndo = nil
            show(Toast(text: text, canUndo: true))
            return true
        } catch let e as TrialError {
            fail(e.message)
        } catch {
            fail("没做成，再试一次")
        }
        return false
    }

    /// 撤销最近一次改动（⌥⌘Z、提示条上的「撤销」）。
    func undo() {
        if let local = localUndo {
            localUndo = nil
            withAnimation(.spring(duration: 0.3)) { local() }
            show(Toast(text: "撤销了"))
            return
        }
        guard let last = ledger.lastUndoable else { say("没有能撤销的了"); return }
        undo(change: last.id)
    }

    /// 撤销某一条改动（改动记录里点「撤销」）。它后面做的也会一起撤回。
    func undo(change id: UUID) {
        do {
            var n = 0
            try withAnimation(.spring(duration: 0.45)) { n = try ledger.undo(id) }
            settleSide()
            show(Toast(text: n > 1 ? "撤销了，连后面的 \(n - 1) 步一起" : "撤销了"))
        } catch let e as TrialError { fail(e.message) } catch { fail("没撤成，再试一次") }
    }

    /// 整本换掉（从备份恢复、换回示例）。
    func replaceLedger(_ l: TrialLedger) { ledger = l }

    /// 彻底忘掉一条记忆：不留记录，也撤不回来。
    func forget(memo id: UUID) {
        do { try ledger.forget(memo: id); say("忘掉了") } catch let e as TrialError { fail(e.message) } catch { fail("没忘成，再试一次") }
    }

    /// 不留记录地摆场景（启动参数、信收进沿途风光）。
    func patch(_ body: (inout Book) -> Void) { ledger.patch(body) }

    private func show(_ t: Toast) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.28, bounce: 0.35)) { toast = t }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(t.isError ? 5 : t.canUndo ? 4 : 2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) { self?.toast = nil }
        }
    }

    func go(_ p: Page) {
        guard book.shows(page: p.rawValue) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            page = p
            showLog = false; chatOpen = false; settingsSub = nil
            if p != page { sayPoppedThisPage = false; sayCardID = nil; sayUnreadID = nil }
            if Page.biz.contains(p) { side = .biz } else if Page.life.contains(p) { side = .life }
        }
    }

    /// 记一笔（⌘N）：管生活时是记一笔的小窗；只管生意时是记今天的账。
    func quickAdd() {
        if showsLife { withAnimation(.snappy(duration: 0.2)) { showAdd = true } } else { open(.shopDay(book.todayDay)) }
    }

    func switchSide(_ s: Side) {
        guard s != side, s == .biz ? book.showBiz : book.showLife else { return }
        withAnimation(.snappy(duration: 0.22)) {
            side = s
            page = s == .biz ? .bizHome : .overview
        }
    }

    // MARK: 具体动作

    /// 记一笔开销（说一句、问夏夏用）。
    @discardableResult
    func record(_ q: QuickPhrase, account: String, place: String = "", daysAgo: Int = 0) -> Bool {
        change("记好了 · \(q.name) \(q.amount.v3) · \(account)", kind: .add) {
            try $0.record(name: q.name, emoji: q.emoji, amount: q.amount, account: account, place: place, daysAgo: daysAgo)
        }
    }

    /// 存一笔进目标：钱从账户挪到目标罐，星星掉进瓶子。返回这一笔刚到的站。
    @discardableResult
    func deposit(_ amount: Money = Money(cents: 20_00), from: String? = nil, resisted: Bool = false) -> [Journey.Station] {
        var reached: [Journey.Station] = []
        let text = resisted ? "算你忍住一次 +\(amount.v3Short)" : "存好了 +\(amount.v3Short) · 瓶里多了一颗星"
        let ok = change(text, kind: .goalDeposit) { b in
            reached = try b.deposit(amount, from: from, resisted: resisted)
            if let i = b.accounts.firstIndex(where: { $0.block == .goal }) { b.accounts[i].note = Self.goalNote(b.journey) }
        }
        if ok { starDrops += 1 }
        return ok ? reached : []
    }

    @discardableResult
    func addAccount(emoji: String, name: String, note: String, balance: Money, kind: Account.Kind) -> Bool {
        change("加好了：\(name)", kind: .account) { try $0.addAccount(emoji: emoji, name: name, note: note, balance: balance, kind: kind) }
    }

    static func goalNote(_ j: Journey) -> String {
        guard let next = j.nextStation, !j.isFinished else { return "\(j.name) · 走完了" }
        return "\(j.name) · 这一站 \(j.saved.v3Short.replacingOccurrences(of: "\u{00A0}€", with: "")) / \(next.target.v3Short.replacingOccurrences(of: "\u{00A0}€", with: ""))"
    }

    // MARK: 示例数据（设计稿里那一套，全是编的）

    static func eur(_ s: String) -> Money { Money(parsing: s) ?? .zero }

    static var demoJourney: Journey {
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
        return j
    }

    static var demoBook: Book {
        let j = demoJourney
        func item(_ e: String, _ n: String, _ note: String, _ a: String, tag: String = "", off: Bool = false, flag: Bool = false) -> TrialBook.Item {
            .init(emoji: e, name: n, note: note, amount: eur(a), tag: tag, off: off, flag: flag)
        }
        var b = Book(
            accounts: [
                Account(emoji: "💳", name: "日常卡", note: "晴空银行 · 今天刚导入", balance: eur("1496,61")),
                Account(emoji: "🏦", name: "储蓄", note: "存着 · 不动", balance: eur("2400"), block: .emergency, short: "储蓄"),
                Account(emoji: "⭐", name: "目标罐", note: goalNote(j), balance: eur("519"), block: .goal),
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
            ],
            upcoming: [
                Entry(emoji: "🏠", name: "房租", meta: "12 月 1 日 · 13 天后", amount: eur("650")),
                Entry(emoji: "💳", name: "信用卡", meta: "12 月 5 日 · 日常卡够付", amount: eur("640"), red: true),
                Entry(emoji: "📱", name: "手机分期", meta: "12 月 8 日 · 第 7 / 12 期", amount: eur("200"), red: true),
            ],
            month: FreeToSpend(income: eur("2340"), fixed: eur("892"), forGoals: eur("200"), spent: eur("271,39"), daysLeft: 12),
            journey: j,
            letters: [
                Letter(title: "第一步", quote: "「两周，50 €，你没断过一天…」", date: "9 月 20 日",
                       tag: "第 1 站 · 存到 50 € · 第一步", headline: "第一步，走出来了。",
                       paragraphs: ["小满：", "两周，50 €，你没断过一天。", "那天你说先试试看。现在试过了：你做得到。",
                                    "下一站是 200。不急，照这个步子走就行。"],
                       facts: [["17 天", "从出发到这儿"], ["3 次", "忍住没买"], ["0 次", "断过"]]),
                Letter(title: "200 €", quote: "「那周你推掉了两顿外卖…」", date: "10 月 12 日",
                       tag: "第 2 站 · 存到 200 €", headline: "200 了。",
                       paragraphs: ["小满：", "那周你推掉了两顿外卖，自己煮了面。省下的 31 块，你顺手就存进来了。",
                                    "我没提醒你，是你自己想起来的。", "电脑还远，可是你已经在路上了。"],
                       facts: [["39 天", "从出发到这儿"], ["8 次", "忍住没买"], ["2 顿", "外卖换成自己煮"]]),
            ],
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
        b.wanted = [
            item("⌚", "运动手表", "还要冷静 21 小时", "189"),
            item("👟", "跑鞋", "冷静完了，还想要吗？", "95", tag: "该回答了"),
            item("🎮", "游戏手柄", "上周忍住了 · 存进目标", "59", off: true),
        ]
        func fixed(_ e: String, _ n: String, _ day: Int, _ a: String, last: String? = nil, flag: Bool = false) -> TrialBook.Item {
            .init(emoji: e, name: n, note: "每月 \(day) 日 · 小店账户", amount: eur(a), tag: flag ? "可省" : "必要", flag: flag,
                  account: "小店账户", day: day, lastMonth: last.map { eur($0) })
        }
        b.fixedCosts = [
            fixed("🧑", "给自己发的工资", 1, "1000"),
            fixed("🏠", "店面房租", 3, "600"),
            fixed("📣", "广告", 10, "80", flag: true),
            fixed("💡", "水电", 15, "70", last: "58"),
            fixed("🗓", "预约软件", 20, "40", last: "35", flag: true),
        ]
        b.purchases = [item("📦", "鲜花补货", "11 月 12 日", "340"), item("📦", "包装纸和丝带", "10 月 28 日", "310"), item("📦", "花瓶和花器", "10 月 6 日", "240")]
        b.stockEstimates = [item("📅", "9 月 30 日", "第三季度末", "2600"), item("📅", "6 月 30 日", "第二季度末", "2400"), item("📅", "开店时", "2025 年 10 月", "4200")]
        b.capital = [item("🔨", "装修", "2025 年 9 月", "14000"), item("💺", "设备和桌椅", "2025 年 9 月", "9800"),
                     item("📦", "第一批货", "2025 年 10 月", "4200"), item("🔑", "押金", "退租时能拿回", "4170")]
        b.shopDebts = [item("📦", "供货商赊账", "12 月 3 日到期", "320"), item("🧑", "熟客挂账", "11 月 9 日 · 说下次来付", "85", flag: true)]
        b.memos = [
            .init(kind: .topic, topic: "我想要的", lines: ["三年后不用为钱发愁", "先换台电脑，剪自己的片子"], source: "你说的", important: true),
            .init(kind: .rule, topic: "转给妈妈的钱", lines: ["每月 5 日转 150 €，不算支出，算家里的"], source: "你纠正的"),
            .init(kind: .topic, topic: "工资", lines: ["每月 28 日前后到，晚几天不用提醒", "私活的钱不固定，别算进每月进账"], source: "夏夏看出来的，你确认过"),
            .init(kind: .topic, topic: "Café Nube", lines: ["付现金。一周超过 4 次时说一声"], source: "你说的"),
            .init(kind: .rule, topic: "超过 100 € 的东西", lines: ["先放进想要清单冷静 48 小时"], source: "你说的"),
            .init(kind: .rule, topic: "店里和家里", lines: ["店里的钱不拿来付家里的开销，要用就走「两边转钱」"], source: "你说的"),
            .init(kind: .lesson, topic: "晴空银行 的流水", lines: ["「To EUR」开头的是自己账户之间转，不算花"], source: "夏夏看出来的，你确认过"),
            .init(kind: .lesson, topic: "Super Lumi", lines: ["小票上印的是总公司的名字，认成超市"], source: "你纠正的"),
        ]
        // 11 月每天收了多少：和设计稿同一个算法。11 月 1 日是周日；周日休息；16 号没记；18 号是今天，还没记。
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
        // 11 月店里的开销（全是编的）：哪天、哪一类、从哪个账户出
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
        spend(7, "平台抽成", "外送平台 10 月抽成", "28,60")
        spend(5, "包装耗材", "包装纸和丝带", "46")
        spend(4, "进货", "绿植和多肉", "120")
        spend(3, "房租", "店面房租", "600")
        spend(2, "员工工资", "周末帮工", "180")
        // 置顶成卡片的几张
        for n in ["日常卡", "储蓄", "信用卡", "小店账户", "店里现金", "店的信用卡"] { try? b.setPinned(n, true) }
        return b
    }

    /// 示例里原来就有的几条改动（撤不了：没有留它们之前的样子）。
    static var demoChanges: [ChangeRecord] {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date() }
        return [
            ChangeRecord(kind: .capture, summary: "记一笔：午饭 12,50 € · 日常卡", transactionIDs: [], author: "拍小票", createdAt: at(13, 5)),
            ChangeRecord(kind: .categorize, summary: "「Super Sol」归进超市，以后这家店都这样", transactionIDs: [], author: "夏夏", createdAt: at(10, 42)),
            ChangeRecord(kind: .subscription, summary: "把「健身房 29 €」标成像订阅，等你确认", transactionIDs: [], author: "Claude", createdAt: at(10, 41)),
            ChangeRecord(kind: .importBatch, summary: "导入「晴空银行 11 月流水」31 笔，跳过重复 6 笔", transactionIDs: [], author: "流水导入", createdAt: at(10, 40)),
            ChangeRecord(kind: .add, summary: "记一笔：咖啡 3,20 € · 现金", transactionIDs: [], author: "Claude", createdAt: at(9, 12)),
            ChangeRecord(kind: .goalDeposit, summary: "存一笔 20 € 进「换新电脑」", transactionIDs: [], author: "你", createdAt: at(8, 30)),
        ]
    }
}
#endif
