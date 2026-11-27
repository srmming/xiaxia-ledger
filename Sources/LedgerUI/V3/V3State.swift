#if os(macOS)
import FinanceCore
import SwiftUI

/// 界面 v3 开发版的全部状态。数字是设计稿里那套编的示例，只在内存里：不读、不写任何账本文件。
@MainActor @Observable
final class V3State {
    enum Mode: String { case life, biz, both }
    enum Side { case life, biz }

    enum Page: String, CaseIterable, Identifiable {
        case overview, goals, wealth, spending, trends, transactions, think, subscriptions, debts, monthly
        case settings
        case bizHome, sales, fixed, payback, stock, checkup, bizDebts
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "总览"
            case .goals: "目标"
            case .wealth: "家底"
            case .spending: "花销"
            case .trends: "趋势"
            case .transactions: "流水"
            case .think: "花钱前想想"
            case .subscriptions: "订阅"
            case .debts: "欠款与还债"
            case .monthly: "每月小结"
            case .settings: "设置"
            case .bizHome: "生意首页"
            case .sales: "营业额"
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
            case .transactions: "list.bullet"
            case .think: "questionmark.circle"
            case .subscriptions: "arrow.triangle.2.circlepath"
            case .debts, .fixed, .bizDebts: "creditcard"
            case .monthly: "doc.text"
            case .settings: "gearshape"
            case .bizHome: "storefront"
            case .sales: "calendar"
            case .payback: "flag"
            case .stock: "shippingbox"
            case .checkup: "waveform.path.ecg"
            }
        }
        static let life: [Page] = [.overview, .goals, .wealth, .spending, .trends, .transactions, .think, .subscriptions, .debts, .monthly]
        static let biz: [Page] = [.bizHome, .sales, .fixed, .payback, .stock, .checkup, .bizDebts]
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
    var mode: Mode = .both
    /// 引导走到第几步（0…4）；nil = 引导走完了。
    var onboardingStep: Int? = 0
    /// 引导里写的那句想要的（存进夏夏的记忆）。
    var wish = ""
    /// 连着哪个 AI；nil = 没连。
    var ai: String?
    var toast: Toast?
    /// 每存一笔加 1，星星瓶就掉一颗星。
    var starDrops = 0
    var secretShown = false
    /// 设置里打开了「一直显示私房钱」。
    var secretPinned = false { didSet { secretShown = secretPinned } }
    var showAddAccount = false
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
    var thinkBig = false
    /// 设置里点进去的改动记录。
    var showLog = false
    /// 设置里正开着的那一页（nil = 设置首页）。
    var settingsSub: SettingsSub?
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
    private var secretTask: Task<Void, Never>?

    init() { ledger = TrialLedger(book: Self.demoBook, changes: Self.demoChanges) }

    // MARK: 做一件事：马上有回应，能撤销

    func say(_ text: String) { show(Toast(text: text)) }

    /// 没做成时说人话：不带撤销，停 5 秒。
    func fail(_ text: String) { show(Toast(text: text, isError: true)) }

    /// 改账本里的东西：规则在核心里（body 里调用 TrialBook 的方法），记一条改动记录（写明记账人），底部弹提示带「撤销」。
    /// 做不成就什么都不变，底部说清为什么。返回做成了没有。
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

    /// 撤销最近一次改动（⌥⌘Z、提示条上的「撤销」）。
    func undo() {
        guard let last = ledger.lastUndoable else { say("没有能撤销的了"); return }
        undo(change: last.id)
    }

    /// 撤销某一条改动（改动记录里点「撤销」）。它后面做的也会一起撤回。
    func undo(change id: UUID) {
        do {
            var n = 0
            try withAnimation(.spring(duration: 0.45)) { n = try ledger.undo(id) }
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
        withAnimation(.snappy(duration: 0.22)) {
            page = p
            thinkBig = false; showLog = false; chatOpen = false; settingsSub = nil
            if p != page { sayPoppedThisPage = false; sayCardID = nil; sayUnreadID = nil }
            if Page.biz.contains(p) { side = .biz } else if Page.life.contains(p) { side = .life }
        }
    }

    func switchSide(_ s: Side) {
        guard s != side else { return }
        withAnimation(.snappy(duration: 0.22)) {
            side = s
            page = s == .biz ? .bizHome : .overview
        }
    }

    // MARK: 具体动作

    /// 记一笔开销（说一句、问夏夏用）。
    @discardableResult
    func record(_ q: QuickPhrase, account: String, place: String = "") -> Bool {
        change("记好了 · \(q.name) \(q.amount.v3) · \(account)", kind: .add) {
            try $0.record(name: q.name, emoji: q.emoji, amount: q.amount, account: account, place: place)
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

    func revealSecret() {
        secretTask?.cancel()
        withAnimation(.snappy) { secretShown = true }
        say("私房钱显示出来了，3 秒后自己藏回去")
        secretTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            guard let self, !self.secretPinned else { return }
            withAnimation(.snappy) { self.secretShown = false }
        }
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
                Account(emoji: "💳", name: "日常卡", note: "Revolut · 今天刚导入", balance: eur("1496,61")),
                Account(emoji: "🏦", name: "储蓄", note: "应急钱放这里 · 不动", balance: eur("2400"), block: .emergency, short: "储蓄 · 应急钱"),
                Account(emoji: "⭐", name: "目标罐", note: goalNote(j), balance: eur("519"), block: .goal),
                Account(emoji: "💶", name: "现金", note: "钱包里 · 上次点数 11 月 10 日", balance: eur("85")),
                Account(emoji: "🏪", name: "小店账户", note: "算在生意那边", balance: eur("3919,39"), kind: .shop, block: .shop),
                Account(emoji: "💳", name: "信用卡", note: "欠 · 12 月 5 日要还", balance: eur("640"), kind: .debt, block: .none, short: "信用卡 · 欠"),
                Account(emoji: "📱", name: "手机分期", note: "欠 · 还剩 6 期，每月 200 €", balance: eur("1200"), kind: .debt, block: .none, short: "手机分期 · 欠"),
                Account(emoji: "🧑", name: "借给小李", note: "他欠我 · 说好 12 月还", balance: eur("120"), kind: .lent, block: .none, short: "小李欠我"),
                Account(emoji: "🙈", name: "私房钱", note: "默认藏着，点一下才显示，不算进上面的数", balance: eur("1250"), kind: .secret, block: .none),
            ],
            entries: [
                Entry(emoji: "🛒", name: "超市", meta: "Mercadona · 日常卡", amount: eur("-23,40"), tag: "流水导入", place: "Mercadona", account: "日常卡"),
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
        b.fixedCosts = [
            item("🧑", "给自己发的工资", "每月 1 日", "1000", tag: "必要"),
            item("🏠", "店面房租", "每月 3 日", "600", tag: "必要"),
            item("📣", "广告", "每月 10 日", "80", tag: "可省", flag: true),
            item("💡", "水电", "每月 15 日", "70", tag: "必要"),
            item("🗓", "预约软件", "每月 20 日", "40", tag: "可省", flag: true),
        ]
        b.purchases = [item("📦", "甲油胶补货", "11 月 12 日", "340"), item("📦", "工具和耗材", "10 月 28 日", "310"), item("📦", "饰品", "10 月 6 日", "240")]
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
            .init(kind: .lesson, topic: "Revolut 的流水", lines: ["「To EUR」开头的是自己账户之间转，不算花"], source: "夏夏看出来的，你确认过"),
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
        return b
    }

    /// 示例里原来就有的几条改动（撤不了：没有留它们之前的样子）。
    static var demoChanges: [ChangeRecord] {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date() }
        return [
            ChangeRecord(kind: .capture, summary: "记一笔：午饭 12,50 € · 日常卡", transactionIDs: [], author: "拍小票", createdAt: at(13, 5)),
            ChangeRecord(kind: .categorize, summary: "「Mercadona」归进超市，以后这家店都这样", transactionIDs: [], author: "夏夏", createdAt: at(10, 42)),
            ChangeRecord(kind: .subscription, summary: "把「健身房 29 €」标成像订阅，等你确认", transactionIDs: [], author: "Claude", createdAt: at(10, 41)),
            ChangeRecord(kind: .importBatch, summary: "导入「Revolut 11 月流水」31 笔，跳过重复 6 笔", transactionIDs: [], author: "流水导入", createdAt: at(10, 40)),
            ChangeRecord(kind: .add, summary: "记一笔：咖啡 3,20 € · 现金", transactionIDs: [], author: "Claude", createdAt: at(9, 12)),
            ChangeRecord(kind: .goalDeposit, summary: "存一笔 20 € 进「换新电脑」", transactionIDs: [], author: "你", createdAt: at(8, 30)),
        ]
    }
}
#endif
