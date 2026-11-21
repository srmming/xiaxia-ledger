import FinanceCore
import Foundation
import Observation

/// app 里能弹出来的窗口。导入、整理、记欠款这些都交给 AI 了，app 里只留极简「记一笔」。
public enum AppSheet: String, Identifiable, Hashable {
    case add
    /// 管理账本、账户、分类。
    case books, accounts, categories
    /// 连上你的 AI（Mac 第一次打开、设置里）。
    case connectAI
    public var id: String { rawValue }
}

/// app 里的账本状态。和 fin 读写同一份账本，所有写入都走 FinanceCore 的规则，记进改动记录。
@MainActor @Observable
public final class LedgerModel {
    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public var text: String
        public var changeID: UUID?
        public var isError = false
    }

    public let store: any LedgerStore
    public private(set) var ledger: Ledger = .fresh
    public var selectedBookID: String?        // nil = 全部
    public var showPrivate = false            // 私房钱默认藏起来
    public var loadError: String?
    public var isLoading = true
    /// app 里的写入记在谁名下：设置里填的名字，没填就用这台设备的用户名。
    public var author: String = LedgerModel.defaultAuthor {
        didSet { UserDefaults.standard.set(author, forKey: "xiaxia.userName") }
    }

    static var defaultAuthor: String {
        if let saved = UserDefaults.standard.string(forKey: "xiaxia.userName"), !saved.isEmpty { return saved }
        #if os(macOS)
        return NSUserName()
        #else
        return "我"
        #endif
    }

    @ObservationIgnored var authorCache: (count: Int, map: [UUID: String])?

    /// 现在在哪一页、弹着哪个窗口。
    public var section: AppSection? = .overview
    public var sheet: AppSheet?
    /// 做完一件事后底部的提示。
    public var toast: Toast?
    /// 这次打开 app 以来自己做的改动，⌥⌘Z 从最后一条往回撤。
    public private(set) var undoStack: [UUID] = []

    /// 总览看哪个月；nil = 最新有流水的月份。
    public var selectedMonth: YearMonth? = nil

    public init(store: any LedgerStore) {
        self.store = store
        reload()
    }

    public func reload() {
        isLoading = true
        defer { isLoading = false }
        do { ledger = try store.load(); loadError = nil; cache = nil; authorCache = nil }
        catch { loadError = error.localizedDescription }
    }

    /// 回到 app 时看一眼账本有没有被别处改过（比如 AI 刚用 fin 记了几笔），有就换成新的。
    public func refreshIfChanged() {
        guard loadError == nil, let fresh = try? store.load(), fresh != ledger else { return }
        ledger = fresh
        cache = nil; authorCache = nil
        authorCache = nil
    }

    /// 改一次账本：成功就保存并在底部给提示（能撤销），失败把错误抛给界面显示。
    @discardableResult
    public func edit(quiet: Bool = false, _ body: (inout Ledger) throws -> ChangeRecord) throws -> ChangeRecord {
        var copy = ledger
        let change = try body(&copy)
        try store.save(copy)
        ledger = copy
        cache = nil; authorCache = nil
        dropMissingSelection()
        if change.canUndo { undoStack.append(change.id) }
        if !quiet { toast = Toast(text: change.summary, changeID: change.canUndo ? change.id : nil) }
        return change
    }

    /// 不想让页面自己处理错误时用：出错就在底部提示。
    public func perform(_ body: (inout Ledger) throws -> ChangeRecord) {
        do { try edit(body) }
        catch { toast = Toast(text: error.localizedDescription, changeID: nil, isError: true) }
    }

    public func undo(_ changeID: UUID) {
        do {
            var copy = ledger
            let change = try copy.undo(changeID: changeID, author: author)
            try store.save(copy)
            ledger = copy
            cache = nil; authorCache = nil
            dropMissingSelection()
            undoStack.removeAll { $0 == changeID }
            toast = Toast(text: change.summary, changeID: nil)
        } catch {
            toast = Toast(text: error.localizedDescription, changeID: nil, isError: true)
        }
    }

    /// 正在看的账本被删了：回到「全部」。
    private func dropMissingSelection() {
        if let b = selectedBookID, !ledger.books.contains(where: { $0.id == b }) { selectedBookID = nil }
    }

    public func undoLast() {
        guard let last = undoStack.last else { return }
        undo(last)
    }

    // MARK: 给界面用的派生数据（算一次存着，账本一变就重算）

    private struct Cache {
        var showPrivate: Bool
        var balances: [String: Money]
        var suggester: Suggester
    }
    @ObservationIgnored private var cache: Cache?

    private func cached() -> Cache {
        if let c = cache, c.showPrivate == showPrivate { return c }
        let c = Cache(showPrivate: showPrivate, balances: Summaries.balances(ledger.transactions), suggester: Suggester(ledger.transactions))
        cache = c
        return c
    }

    public var hiddenAccounts: Set<String> { showPrivate ? [] : ledger.privateAccountIDs }

    public var visibleAccounts: [Account] { ledger.accounts.filter { showPrivate || !$0.isPrivate } }

    public var visibleTransactions: [FinanceCore.Transaction] {
        let hidden = hiddenAccounts
        return ledger.transactions.filter { !hidden.contains($0.accountID) }
            .filter { selectedBookID == nil || $0.bookID == selectedBookID }
            .sorted { ($0.date, $0.description) > ($1.date, $1.description) }
    }

    public var balances: [String: Money] { cached().balances }
    public var suggester: Suggester { cached().suggester }

    public var totalBalance: Money {
        let b = balances
        return visibleAccounts.reduce(.zero) { $0 + (b[$1.id] ?? .zero) }
    }

    /// 最新有流水的月份（不超过本月）；没有流水就是本月。
    public var currentMonth: YearMonth {
        let today = LocalDate.today.yearMonth
        let latest = ledger.transactions.map(\.date).max()?.yearMonth ?? today
        return min(latest, today)
    }

    public var shownMonth: YearMonth { selectedMonth ?? currentMonth }

    public func summary(_ month: YearMonth) -> MonthlySummary {
        Summaries.monthly(ledger.transactions, month: month, bookID: selectedBookID, hiddenAccounts: hiddenAccounts)
    }

    public func summaries(_ months: [YearMonth], bookID: String?) -> [MonthlySummary] {
        Reports.summaries(ledger.transactions, months: months, bookID: bookID, hiddenAccounts: hiddenAccounts)
    }

    public func summaries(_ months: [YearMonth]) -> [MonthlySummary] { summaries(months, bookID: selectedBookID) }

    /// 最近 n 个月（含当月），从早到晚。
    public func recentMonths(_ n: Int) -> [YearMonth] { Reports.months(endingAt: currentMonth, count: n) }

    /// 有流水的年份，从新到旧。
    public var years: [Int] {
        let ys = Set(ledger.transactions.map(\.date.year)).union([LocalDate.today.year])
        return ys.sorted(by: >)
    }

    public func bookName(_ id: String?) -> String {
        guard let id else { return "全部" }
        return ledger.books.first { $0.id == id }?.name ?? id
    }

    public func accountName(_ id: String) -> String { ledger.accounts.first { $0.id == id }?.name ?? id }

    public func transaction(_ id: UUID) -> FinanceCore.Transaction? { ledger.transactions.first { $0.id == id } }

    /// 流水里出现过的分类（含「未分类」），筛选用。
    public var usedCategories: [String] {
        Array(Set(ledger.transactions.filter { $0.flow == nil }.map { $0.category ?? "未分类" })).sorted()
    }

    /// 记一笔、整理时给的分类建议：这个账本、这个方向（收入 / 支出）用得最多的排前面，再补上常用的。
    public func categories(bookID: String?, income: Bool, limit: Int = 14) -> [String] {
        var count: [String: Int] = [:]
        for t in ledger.transactions where t.flow == nil && !t.isTransfer && t.amount.isIncome == income {
            guard let c = t.category, bookID == nil || t.bookID == bookID else { continue }
            count[c, default: 0] += 1
        }
        let used = count.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        let defaults = CategoryStyle.defaults(book: ledger.books.first { $0.id == bookID }, income: income)
        // 账本里已经有「交通出行」，就不再另给一个「交通」，免得同一件事记成两个分类。
        let extra = defaults.filter { d in !used.contains { $0 == d || $0.hasPrefix(d) } }
        return Array((used + extra).prefix(limit))
    }

    // MARK: 记住上次用的账户和账本

    private static let lastAccountKey = "xiaxia.lastAccount"
    private static let lastBookKey = "xiaxia.lastBook"

    public var lastAccountID: String? {
        get {
            let id = UserDefaults.standard.string(forKey: Self.lastAccountKey)
            return visibleAccounts.contains { $0.id == id } ? id : nil
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastAccountKey) }
    }

    public var lastBookID: String? {
        get {
            let id = UserDefaults.standard.string(forKey: Self.lastBookKey)
            return ledger.books.contains { $0.id == id } ? id : nil
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastBookKey) }
    }

    /// 新记一笔时默认的账本：正在看的那个，否则上次用的，否则第一个。
    public var defaultBookID: String { selectedBookID ?? lastBookID ?? ledger.books.first?.id ?? "" }
    public var defaultAccountID: String { lastAccountID ?? visibleAccounts.first?.id ?? "" }

    /// 跳到流水页并带上筛选。
    public var pendingFilter: TransactionFilter?
    /// 按 ⌘F 去流水页时，把光标放进搜索框。
    public var focusSearch = false
    public func showTransactions(_ filter: TransactionFilter) {
        pendingFilter = filter
        section = .transactions
    }
}

extension LedgerModel {
    /// 预览和截图用的内存账本，数字全是编的。
    public static func demo() -> LedgerModel { LedgerModel(store: InMemoryLedgerStore(.demo)) }
    /// 空账本：看第一次打开的样子。
    public static func empty() -> LedgerModel { LedgerModel(store: InMemoryLedgerStore(.fresh)) }
}
