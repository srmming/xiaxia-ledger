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
    var author = "你" {
        // 接着 app 的账本：记账人是同一个，改了一起改
        didSet { if let model, model.author != author { model.author = author } }
    }
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
    /// 出图用：新建目标的弹窗直接停在第二步（选钱放哪）。用一次就清掉。
    var goalSheetStep = 0
    // 决策模型（OpenRouter）
    var transport: V3Transport = V3State.defaultTransport()
    var decisionPrefs = V3DecisionPrefs.load()
    var decisionTry = ""
    var decisionTrying = false
    /// 「三组都跑一遍」的结果，一行一句（不含密钥）。
    var decisionReport: [String] = []
    var models: [String] = []
    var modelsLoading = false
    /// 夏夏主动提醒的那一句（D1 判断要说的时候才有）。
    var reminder: V3Reminder?
    var dailyTask: Task<Void, Never>?
    /// 正在看哪个月（nil 是这个月）。总览、花销、趋势、小结、生意那几页共用，换页不变。
    var viewMonth: TrialBook.MonthKey?
    var monthKey: TrialBook.MonthKey { book.clampMonth(viewMonth ?? book.thisMonth) }
    var isThisMonth: Bool { monthKey == book.thisMonth }
    var monthData: TrialBook.MonthData { book.monthData(monthKey) }
    /// 「11 月」「2025 年 12 月」
    var monthLabel: String { monthKey.label(thisYear: book.thisMonth.year) }
    func setMonth(_ k: TrialBook.MonthKey) {
        let c = book.clampMonth(k)
        withAnimation(.snappy(duration: 0.2)) { viewMonth = c == book.thisMonth ? nil : c }
    }
    /// 打开「自己填」时直接停在哪一种（0 支出、1 收入、2 转账）。用一次就清掉。
    var manualStartKind: Int?
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

    /// 接正式账本的第 1 步：从一本正式账本现算出界面要的数，只看不写。
    /// 传进来的是账本的一份副本（值类型），这里不会改它，也不会往盘上写任何东西。
    /// - writable: 第 2 步。记一笔、改分类、改金额、删、撤销会真的写进这份正式账本（内存里的这一份副本；这里不存盘）。
    init(snapshotOf real: Ledger, today: LocalDate = .today, showPrivate: Bool = true, writable: Bool = false) {
        ledger = TrialLedger(book: LedgerBridge.snapshot(of: real, today: today, showPrivate: showPrivate), changes: Array(real.changes.suffix(50).reversed()))
        readOnly = !writable
        self.real = real; realToday = today; realShowsPrivate = showPrivate
        // 一本刚开始的空账本：先走引导，走完才把填的东西写进去
        firstRun = writable && LedgerBridge.isBrandNew(real)
        onboardingStep = firstRun ? 0 : nil
    }

    /// 正式账本是空的、正在走第一次的引导。
    private(set) var firstRun = false
    /// 引导「有多少」那一步填的账户（正式账本上走完引导才写入）。
    var startingAccounts: StartingAccounts?

    /// 引导走完：把填的账户、欠款、想要的那句话写进正式账本。什么都没填就什么都不写。
    func finishFirstRun() {
        guard firstRun, var l = real else { return }
        firstRun = false
        let list = startingAccounts ?? StartingAccounts(rows: [])
        // 引导里选了也管生意：走完以后把生意那一边打开（界面上的选择先记下来，下面重新算数时会被盖掉）
        let wantsBiz = book.showBiz
        defer { if wantsBiz, model?.businessOn == false { setBusiness(on: true); toast = nil } }
        do {
            var records: [ChangeRecord] = []
            if let model {
                if !list.rows.isEmpty || !wish.trimmingCharacters(in: .whitespaces).isEmpty {
                    try model.edit(quiet: true) { live in
                        records = try LedgerBridge.firstSetup(&live, accounts: list, wish: self.wish, today: self.realToday, author: self.author)
                        guard let last = records.last else { throw TrialError("没有要写的") }
                        return last
                    }
                }
                l = model.ledger
            } else {
                records = try LedgerBridge.firstSetup(&l, accounts: list, wish: wish, today: realToday, author: author)
            }
            real = l; resnapshot()
            if !records.isEmpty { realUndo.append(records.map(\.id)) }
            startingAccounts = nil
        } catch let e as TrialError { fail(e.message) } catch { fail((error as? LocalizedError)?.errorDescription ?? "引导里填的没写成，进去以后在「家底」里加") }
    }
    /// 第 9 步：接着 app 里那本正式账本（旧界面用的同一个 `LedgerModel`）。写入和撤销都交给它：它负责存盘、同步、和旧界面保持一致。
    convenience init(model: LedgerModel, today: LocalDate = .today) {
        self.init(snapshotOf: model.ledger, today: today, writable: true)
        self.model = model
        author = model.author
    }
    private(set) weak var model: LedgerModel?
    /// 账本在别处变了（AI、命令行、手机、旧界面）：把界面上的数重新算一遍。
    func refreshFromModel() {
        guard let model, model.ledger != real else { return }
        real = model.ledger
        resnapshot()
    }

    /// 接着的那份正式账本（内存里的副本）。nil 就是在用试用数字。
    private(set) var real: Ledger?
    private var realToday = LocalDate.today
    private var realShowsPrivate = false
    /// 正式账本上最近一次还能撤销的改动。
    private var realUndo: [[UUID]] = []

    /// 正式账本变了以后，界面上的数重新现算一遍。
    private func resnapshot() {
        guard let real else { return }
        ledger = TrialLedger(book: LedgerBridge.snapshot(of: real, today: realToday, showPrivate: realShowsPrivate), changes: Array(real.changes.suffix(50).reversed()))
    }
    /// 只看不写：这一版界面接的是正式账本的只读数，写入还没接。
    var readOnly = false

    /// 交给夏夏的流水文件里的字（文件名 → 内容）。只留在内存里，确认以后才导。
    var statementFiles: [String: String] = [:]

    /// 记住一份流水文件的内容。读不成字的（PDF、Excel、图片）不记。
    func keepStatement(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count < 5_000_000 else { return }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1), !text.contains("\u{0}") else { return }
        statementFiles[url.lastPathComponent] = text
    }

    /// 正式账本里能收流水的账户（银行卡、现金、储蓄、信用卡）。
    var statementAccounts: [String] { real?.accounts.map(\.name) ?? [] }

    /// 一份流水放进某个账户会怎么样：只数，不写。
    func checkStatement(_ name: String, account: String) throws -> LedgerBridge.StatementCheck {
        guard var l = real else { throw TrialError("这是试用数字") }
        guard let text = statementFiles[name] else { throw TrialError("这份文件我在这里读不了") }
        return try LedgerBridge.importStatement(text: text, fileName: name, accountName: account, to: &l, author: author, dryRun: true).check
    }

    /// 把一份流水真的导进正式账本：重复的跳过，整批能撤销。返回进来几笔。
    @discardableResult
    func importStatement(_ name: String, account: String) -> LedgerBridge.StatementCheck? {
        guard !readOnly, var l = real else { fail("这一版还只能看。要导入，先回旧界面"); return nil }
        guard let text = statementFiles[name] else { fail("这份文件我在这里读不了"); return nil }
        do {
            var done: LedgerBridge.StatementCheck?
            var changeID: UUID?
            if let model {
                try model.edit(quiet: true) { live in
                    let r = try LedgerBridge.importStatement(text: text, fileName: name, accountName: account, to: &live, author: self.author)
                    guard let c = r.change else { throw TrialError("没有新的") }
                    done = r.check; changeID = c.id
                    return c
                }
                l = model.ledger
            } else {
                let r = try LedgerBridge.importStatement(text: text, fileName: name, accountName: account, to: &l, author: author)
                done = r.check; changeID = r.change?.id
            }
            withAnimation(.spring(duration: 0.45)) { real = l; resnapshot() }
            if let changeID { realUndo.append([changeID]) }
            localUndo = nil
            if let done { show(Toast(text: "进来 \(done.fresh) 笔\(done.duplicates > 0 ? "，跳过重复 \(done.duplicates) 笔" : "")", canUndo: true)) }
            return done
        } catch let e as TrialError { fail(e.message) } catch { fail((error as? LocalizedError)?.errorDescription ?? "没导成，账本没动") }
        return nil
    }

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
        guard !readOnly else { fail("这一版还只能看。要记、要改，先回旧界面"); return false }
        if var l = real {
            // 接着正式账本：先在界面这份数上试做一遍，看出改了什么，再照样做到正式账本上（带作者、记改动记录）
            do {
                var next = book
                try body(&next)
                var records: [ChangeRecord] = []
                if let model {
                    // 交给 app 的账本模型去改：它存盘成功了才算数
                    let before = book
                    try model.edit(quiet: true) { live in
                        records = try LedgerBridge.apply(before: before, after: next, to: &live, today: self.realToday, author: self.author)
                        return records[records.count - 1]
                    }
                    l = model.ledger
                } else {
                    records = try LedgerBridge.apply(before: book, after: next, to: &l, today: realToday, author: author)
                }
                withAnimation(.spring(duration: 0.45)) { real = l; resnapshot() }
                realUndo.append(records.map(\.id))
                localUndo = nil
                show(Toast(text: text, canUndo: true))
                return true
            } catch let e as TrialError { fail(e.message) } catch { fail((error as? LocalizedError)?.errorDescription ?? "没做成，再试一次") }
            return false
        }
        do {
            try withAnimation(.spring(duration: 0.45)) { _ = try ledger.apply(kind, text, author: author, body) }
            localUndo = nil
            show(Toast(text: text, canUndo: true))
            // 每记一笔、每次导入：跑一次「要不要提醒」（跑测试时不自动跑，测试自己叫）
            if kind == .add || kind == .importBatch, NSClassFromString("XCTestCase") == nil {
                Task { @MainActor [weak self] in await self?.runReminderCheck(newEntries: [text]) }
            }
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
        if var l = real {
            // 正式账本：用它自己的撤销（会再记一条「撤销」的改动）
            // 界面上的一步，在正式账本里可能是好几条改动（比如改一天的收入 = 删旧的 + 记新的）：一起撤，后做的先撤
            guard let ids = realUndo.popLast() else { say("没有能撤销的了"); return }
            do {
                if let model {
                    for id in ids.reversed() { try model.edit(quiet: true) { live in try live.undo(changeID: id, author: self.author) } }
                    l = model.ledger
                } else {
                    for id in ids.reversed() { try l.undo(changeID: id, author: author) }
                }
                withAnimation(.spring(duration: 0.45)) { real = l; resnapshot() }
                show(Toast(text: "撤销了"))
            } catch { fail((error as? LocalizedError)?.errorDescription ?? "这一条撤不了") }
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
    func replaceLedger(_ l: TrialLedger) { guard real == nil else { return }; ledger = l }

    /// 彻底忘掉一条记忆：不留记录，也撤不回来。
    func forget(memo id: UUID) {
        if var l = real {
            // 正式账本：用它自己的「彻底忘掉」（连改动记录里的旧样子一起抹掉，撤不回来）
            guard !readOnly else { fail("这一版还只能看"); return }
            do {
                if let model {
                    try model.edit(quiet: true) { live in try live.forgetMemory(id, author: self.author) }
                    l = model.ledger
                } else { try l.forgetMemory(id, author: author) }
                withAnimation(.spring(duration: 0.45)) { real = l; resnapshot() }
                say("忘掉了")
            } catch { fail((error as? LocalizedError)?.errorDescription ?? "没忘成，再试一次") }
            return
        }
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
            if let i = b.accounts.firstIndex(where: { $0.id == b.bigGoalAccount }) { b.accounts[i].note = Self.goalNote(b.journey) }
        }
        if ok { starDrops += 1 }
        return ok ? reached : []
    }

    @discardableResult
    func addAccount(emoji: String, name: String, note: String, balance: Money, kind: Account.Kind) -> Bool {
        change("加好了：\(name)", kind: .account) { try $0.addAccount(emoji: emoji, name: name, note: note, balance: balance, kind: kind) }
    }

    static func goalNote(_ j: Journey) -> String { TrialBook.goalNote(j) }

    // MARK: 示例数据（设计稿里那一套，全是编的；内容在 FinanceCore/TrialDemo.swift，Mac 和 iPhone 共用）

    static func eur(_ s: String) -> Money { Money(parsing: s) ?? .zero }
    static var demoJourney: Journey { TrialBook.demoJourney }
    static var demoBook: Book { TrialBook.demo }

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
