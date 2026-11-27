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

    struct Account: Identifiable, Equatable {
        enum Kind { case own, shop, debt, lent, secret }
        enum Block { case daily, emergency, goal, shop, none }
        var id = UUID()
        var emoji: String
        var name: String
        /// 家底页卡片下面那行小字。
        var note: String
        var balance: Money
        var kind: Kind = .own
        var block: Block = .daily
        /// 总览小卡片上的短名字。
        var short: String = ""
        var label: String { short.isEmpty ? name : short }
        var isDebt: Bool { kind == .debt }
    }

    struct Entry: Identifiable, Equatable {
        var id = UUID()
        var emoji: String
        var name: String
        var meta: String
        var amount: Money
        var tag: String = ""
        var red = false
    }

    struct Letter: Identifiable, Equatable {
        var id = UUID()
        var title: String
        var quote: String
        var date: String
        /// 信纸上面那行小标签和大标题。
        var tag = ""
        var headline = "你做到了。"
        var paragraphs: [String] = []
        /// 小卡片上的三个数。
        var facts: [[String]] = []
    }

    /// 能撤销的那部分。
    struct Book: Equatable {
        var accounts: [Account]
        var today: [Entry]
        var upcoming: [Entry]
        var month: FreeToSpend
        var journey: Journey
        var letters: [Letter]
        /// 应急钱和目标对半分：nil = 还没回答。
        var splitWithEmergency: Bool?
        var monthlyMust: Money

        var owned: [Account] { accounts.filter { $0.kind == .own || $0.kind == .shop } }
        var debts: [Account] { accounts.filter { $0.kind == .debt } }
        var lent: [Account] { accounts.filter { $0.kind == .lent } }
        var totals: HouseholdTotals { HouseholdTotals(holdings: owned.map(\.balance), debts: debts.map(\.balance)) }
        func sum(_ block: Account.Block) -> Money { owned.filter { $0.block == block }.map(\.balance).reduce(.zero, +) }
        var runway: EmergencyRunway { EmergencyRunway(fund: sum(.emergency), monthlyMust: monthlyMust) }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var canUndo = false
    }

    // MARK: 状态

    var book: Book
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
    var showAddAccount = false
    /// 目标的三个时刻：定第一步、改小步子、到站的信。
    var moment: V3Moment?

    let today = "11 月 18 日 · 周三"
    let lastMonthNetDelta = Money(cents: 490_00)
    let spentLessThanLastMonth = Money(cents: 86_00)

    private var undoStack: [Book] = []
    private var toastTask: Task<Void, Never>?
    private var secretTask: Task<Void, Never>?

    init() { book = Self.demoBook }

    // MARK: 做一件事：马上有回应，能撤销

    func say(_ text: String) { show(Toast(text: text)) }

    /// 改账本里的东西：记下改之前的样子，底部弹提示带「撤销」。
    func change(_ text: String, _ body: (inout Book) -> Void) {
        undoStack.append(book)
        if undoStack.count > 30 { undoStack.removeFirst() }
        withAnimation(.spring(duration: 0.45)) { body(&book) }
        show(Toast(text: text, canUndo: true))
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        withAnimation(.spring(duration: 0.45)) { book = last }
        show(Toast(text: "撤销了，回到刚才的样子"))
    }

    private func show(_ t: Toast) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.28, bounce: 0.35)) { toast = t }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(t.canUndo ? 4 : 2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) { self?.toast = nil }
        }
    }

    func go(_ p: Page) {
        withAnimation(.snappy(duration: 0.22)) {
            page = p
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

    /// 右上角「+ 记一笔」的示例：一杯咖啡，现金付的。
    func quickAddCoffee() {
        let amount = Money(cents: 3_20)
        change("记好了 · 咖啡 \(amount.v3)") { b in
            b.month.spent = b.month.spent + amount
            if let i = b.accounts.firstIndex(where: { $0.name == "现金" }) { b.accounts[i].balance = b.accounts[i].balance - amount }
            b.today.insert(Entry(emoji: "☕", name: "咖啡", meta: "Café Nube · 现金", amount: -amount, tag: "刚记的"), at: 0)
            if b.today.count > 3 { b.today.removeLast() }
        }
    }

    /// 存一笔进目标：钱从日常卡挪到目标罐，星星掉进瓶子。返回这一笔刚到的站。
    @discardableResult
    func deposit(_ amount: Money = Money(cents: 20_00), resisted: Bool = false) -> [Journey.Station] {
        var reached: [Journey.Station] = []
        let text = resisted ? "算你忍住一次 +\(amount.v3Short)" : "存好了 +\(amount.v3Short) · 瓶里多了一颗星"
        change(text) { b in
            let half = b.splitWithEmergency == true && !resisted
            let toGoal = half ? Money(cents: amount.cents / 2) : amount
            let toEmergency = amount - toGoal
            if let i = b.accounts.firstIndex(where: { $0.block == .daily && $0.kind == .own }) { b.accounts[i].balance = b.accounts[i].balance - amount }
            if let i = b.accounts.firstIndex(where: { $0.block == .goal }) { b.accounts[i].balance = b.accounts[i].balance + toGoal }
            if toEmergency > .zero, let i = b.accounts.firstIndex(where: { $0.block == .emergency }) {
                b.accounts[i].balance = b.accounts[i].balance + toEmergency
            }
            reached = b.journey.deposit(toGoal)
            if resisted { b.journey.resisted += 1 }
            if let i = b.accounts.firstIndex(where: { $0.block == .goal }) { b.accounts[i].note = Self.goalNote(b.journey) }
        }
        starDrops += 1
        return reached
    }

    func revealSecret() {
        secretTask?.cancel()
        withAnimation(.snappy) { secretShown = true }
        say("私房钱显示出来了，3 秒后自己藏回去")
        secretTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.secretShown = false }
        }
    }

    func addAccount(emoji: String, name: String, note: String, balance: Money, kind: Account.Kind) {
        change("加好了：\(name)") { b in
            b.accounts.append(Account(emoji: emoji, name: name, note: note, balance: balance, kind: kind,
                                      block: kind == .own ? .daily : .none))
        }
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
        return Book(
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
            today: [
                Entry(emoji: "🛒", name: "超市", meta: "Mercadona · 日常卡", amount: eur("-23,40"), tag: "流水导入"),
                Entry(emoji: "☕", name: "咖啡", meta: "Café Nube · 现金", amount: eur("-3,20"), tag: "跟 AI 说的"),
                Entry(emoji: "🥗", name: "午饭", meta: "La Tasca · 日常卡", amount: eur("-12,50"), tag: "拍小票"),
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
    }
}
#endif
