#if os(iOS)
import FinanceCore
import SwiftUI

/// iPhone 界面 v3 的开关：包里写了 XiaxiaV3，或启动参数带 `-XiaxiaV3`（`-XiaxiaV3 0` 关）。
public enum PhoneV3Launch {
    /// 试用版（只用编的示例数）：启动参数优先，其次包里写的 XiaxiaV3。
    public static var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-XiaxiaV3") { return i + 1 >= args.count || args[i + 1] != "0" }
        return Bundle.main.object(forInfoDictionaryKey: "XiaxiaV3") as? Bool == true
    }
    /// 正式的 app 要不要用新界面打开正式账本（和 Mac 同一个开关、同一个偏好名）。默认还是旧界面。
    public static let newLookKey = "xiaxia.ui.newLook"
    public static var newLook: Bool {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-XiaxiaNewLook") { return i + 1 >= args.count || args[i + 1] != "0" }
        return UserDefaults.standard.bool(forKey: newLookKey)
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
        case transfer
        case account(String?)
        case repay(String)
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
            case .transfer: "transfer"
            case .account(let n): "account-\(n ?? "new")"
            case .repay(let n): "repay-\(n)"
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
    var sheet: Sheet?
    /// 「我的」开着时，里面再弹的（一个界面同时只能弹一层）。
    var meSheet: Sheet?
    /// 弹一个：「我的」开着就弹在它上面。
    func open(_ s: Sheet) { if meOpen { meSheet = s } else { sheet = s } }
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

    // MARK: 接着正式账本（和 Mac 的 V3State(model:) 同一个做法）

    /// 接着 app 里那本正式账本（旧界面用的同一个 LedgerModel）。写入、存盘、撤销都交给它。
    private(set) weak var model: LedgerModel?
    /// 正式账本的内存副本；nil 是在用试用的示例数。
    private var real: Ledger?
    private var realToday = LocalDate.today
    /// 这次打开以来在正式账本上做的改动（能撤销的就是这些）。
    /// 正式账本上能撤销的：每次界面上的一个动作是一组（apply 可能返回好几条改动），撤销时整组一起、后做的先撤。
    private var realUndo: [[UUID]] = []
    var isReal: Bool { real != nil }

    convenience init(model: LedgerModel, today: LocalDate = .today) {
        self.init()
        self.model = model
        real = model.ledger; realToday = today
        author = model.author
        resnapshot()
        settleSide()
    }

    private func resnapshot() {
        guard let real else { return }
        ledger = TrialLedger(book: LedgerBridge.snapshot(of: real, today: realToday, showPrivate: true), changes: Array(real.changes.suffix(50).reversed()))
    }

    /// 账本在别处变了（AI、命令行、Mac、旧界面）：界面上的数重新算一遍。
    func refreshFromModel() {
        guard let model, model.ledger != real else { return }
        real = model.ledger
        resnapshot()
        settleSide()
    }

    init() {
        ledger = TrialLedger(book: TrialBook.demo, changes: Self.demoChanges)
        if let s = PhoneV3Launch.value("-P3Side"), s == "biz" { side = .biz }
        if let t = PhoneV3Launch.value("-P3Tab"), let tab = Tab(rawValue: t) { self.tab = tab }
        if let p = PhoneV3Launch.value("-P3Page"), let page = Page(rawValue: p) { meOpen = true; mePath = [page] }
        if PhoneV3Launch.value("-P3Me") != nil { meOpen = true }
        if let m = PhoneV3Launch.value("-P3Month"), let n = Int(m), n < 0 { var k = book.thisMonth; for _ in 0..<(-n) { k = k.previous }; viewMonth = book.clampMonth(k) }
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

    // MARK: 月份（和 Mac 用同一套：TrialBook.months / monthData）

    /// 选着看的月份；nil 是这个月。
    var viewMonth: TrialBook.MonthKey?
    var monthKey: TrialBook.MonthKey { book.clampMonth(viewMonth ?? book.thisMonth) }
    var isThisMonth: Bool { monthKey == book.thisMonth }
    var monthData: TrialBook.MonthData { book.monthData(monthKey) }
    var monthTitle: String { monthKey.label(thisYear: book.thisMonth.year) }
    var canGoBack: Bool { monthKey > (book.months.first ?? book.thisMonth) }
    func flipMonth(_ d: Int) {
        let k = book.clampMonth(d < 0 ? monthKey.previous : monthKey.next)
        withAnimation(.snappy(duration: 0.2)) { viewMonth = k == book.thisMonth ? nil : k }
    }
    /// 看的那个月的花销分类。这个月：分好类的那些，加上手机上刚记的（还没归类的合成「刚记的」），总数和总览对得上。
    /// 看的那个月的花销分类（共用算法：大数 = 圆环 = 分类合计）。
    var shownSlices: [Book.SpendSlice] { monthData.topSlices(limit: 8) }
    /// 和上个月比的两个数：从账本里存的上个月的数来，不写死。上个月的数不全时不说「比上个月…」。
    var lastMonthSpentSoFar: Money { book.previousMonthData?.sameDaySpent ?? book.month.spentTotal }
    var lastMonthNet: Money { book.previousMonthData?.net ?? book.totals.net }
    var canCompareSpend: Bool { book.spentLessThanLastMonthSameDay != nil }
    var canCompareNet: Bool { book.netMoreThanLastMonth != nil }
    /// 「比上个月多 / 少 …」，跟着数变。
    func compare(_ now: Money, _ before: Money) -> String {
        let d = now - before
        return d == .zero ? "和上个月一样" : d > .zero ? "比上个月多 \(d.p3Short)" : "比上个月少 \(d.magnitude.p3Short)"
    }

    // MARK: 做一件事：马上有回应，能撤销

    func say(_ text: String) { show(Toast(text: text)) }
    func fail(_ text: String) { show(Toast(text: text, isError: true)) }

    @discardableResult
    func change(_ text: String, kind: ChangeRecord.Kind = .edit, _ body: (inout Book) throws -> Void) -> Bool {
        if let model, real != nil {
            // 正式账本：界面上先改一份快照，再把前后两份交给 LedgerBridge 照样做到账本上，由 app 的模型存盘
            do {
                var next = book
                try body(&next)
                let before = book
                var records: [ChangeRecord] = []
                _ = try model.edit(quiet: true) { live in
                    records = try LedgerBridge.apply(before: before, after: next, to: &live, today: self.realToday, author: self.author)
                    guard let last = records.last else { throw TrialError("没有要改的") }
                    return last
                }
                withAnimation(.spring(duration: 0.45)) { real = model.ledger; resnapshot() }
                realUndo.append(records.map(\.id))
                show(Toast(text: text, canUndo: true))
                return true
            } catch let e as TrialError {
                fail(e.message)
            } catch {
                fail((error as? LocalizedError)?.errorDescription ?? "没做成，再试一次")
            }
            return false
        }
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
        if real != nil {
            guard let id = realUndo.last?.last else { say("没有能撤销的了"); return }
            undo(change: id)
            return
        }
        guard let last = ledger.lastUndoable else { say("没有能撤销的了"); return }
        undo(change: last.id)
    }

    func undo(change id: UUID) {
        if let model, real != nil {
            // 正式账本用它自己的撤销（会再记一条「撤销」）
            do {
                let group = realUndo.first { $0.contains(id) } ?? [id]
                _ = try model.edit(quiet: true) { live in
                    var last: ChangeRecord?
                    for one in group.reversed() { last = try live.undo(changeID: one, author: self.author) }
                    guard let last else { throw TrialError("没有要撤的") }
                    return last
                }
                realUndo.removeAll { $0.contains(id) }
                withAnimation(.spring(duration: 0.45)) { real = model.ledger; resnapshot() }
                settleSide()
                show(Toast(text: "撤销了"))
            } catch { fail((error as? LocalizedError)?.errorDescription ?? "这一条撤不了") }
            return
        }
        do {
            var n = 0
            try withAnimation(.spring(duration: 0.45)) { n = try ledger.undo(id) }
            settleSide()
            show(Toast(text: n > 1 ? "撤销了，连后面的 \(n - 1) 步一起" : "撤销了"))
        } catch let e as TrialError { fail(e.message) } catch { fail("没撤成，再试一次") }
    }

    func canUndo(_ id: UUID) -> Bool { real != nil ? realUndo.contains { $0.contains(id) } : ledger.canUndo(id) }

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
}

#endif
