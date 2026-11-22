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
    /// 计划页「新计划」：存钱目标、分期、借款。
    case plan
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
        /// 停留几秒；不填按有没有撤销决定（3 秒 / 10 秒）。
        public var seconds: Double? = nil
    }

    public let store: any LedgerStore
    public private(set) var ledger: Ledger = .fresh
    public var selectedBookID: String? { didSet { publishView() } }       // nil = 全部
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
    public var section: AppSection? = .overview { didSet { publishView() } }
    public var sheet: AppSheet?
    /// 做完一件事后底部的提示。
    public var toast: Toast?
    /// 这次打开 app 以来自己做的改动，⌥⌘Z 从最后一条往回撤。
    public private(set) var undoStack: [UUID] = []

    /// 总览看哪个月；nil = 最新有流水的月份。
    public var selectedMonth: YearMonth? = nil { didSet { publishView() } }

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
    /// 别人做的新改动记进 `activity`，界面弹「Claude 刚记了 12 笔」。
    public func refreshIfChanged() {
        lastStamp = store.changeStamp()
        guard loadError == nil, let fresh = try? store.load(), fresh != ledger else { return }
        let old = ledger
        ledger = fresh
        cache = nil; authorCache = nil
        dropMissingSelection()
        if let found = ExternalActivity.between(old, fresh, me: author) {
            activity = activity.map { $0.merged(with: found) } ?? found
        }
    }

    // MARK: 外面的 AI 刚做了什么

    #if os(macOS)
    /// 右边的「夏夏」对话栏。
    public let chat = XiaxiaChatState()
    #endif

    /// 外面的 AI（经 fin / MCP）刚改了账本：还没看过的那一批。
    public var activity: ExternalActivity?
    /// 「看看」之后在流水页高亮的那几笔。
    public var highlighted: Set<UUID> = []
    @ObservationIgnored private var lastStamp: String?

    /// 每隔两秒看一眼账本文件，变了（AI 刚写过）就重新读。弹着窗口时先不换，免得正在填的东西被打断。
    public func watch() async {
        publishView()
        lastStamp = store.changeStamp()
        // 账本文件还没建（新用户第一次打开）也一直看着：AI 先写，文件才出现。内存账本的指纹一直是 nil，不会触发。
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard sheet == nil else { continue }
            if AppBridge.hasOpenRequest, let r = AppBridge.takeOpenRequest() { apply(r) }
            let stamp = store.changeStamp()
            guard stamp != nil, stamp != lastStamp else { continue }
            refreshIfChanged()
        }
    }

    /// 流水页选中的那一笔（给外面的 AI 看「用户在看哪一笔」）。
    public var selectedTransactionID: UUID? { didSet { publishView() } }

    /// 把「现在停在哪」写给外面的 AI（MCP current_view）。示例数据、空账本这类内存账本不写，免得 AI 以为是真账本。
    public func publishView() {
        guard !(store is InMemoryLedgerStore) else { return }
        AppBridge.writeView(currentView)
    }

    /// 现在停在哪一页、哪个月、哪个账本、选中了哪一笔。
    public var currentView: AppBridge.View {
        let page = section ?? .overview
        let sel = selectedTransactionID.flatMap { transaction($0) }.flatMap { t in
            page == .transactions ? AppBridge.SelectedTransaction(
                id: t.id, date: t.date.description, amount: t.amount.formatted, description: Merchant.display(t.description),
                category: t.category, account: accountName(t.accountID), book: ledger.books.first { $0.id == t.bookID }?.name) : nil
        }
        return AppBridge.View(page: page.rawValue, month: page.usesMonth ? shownMonth.description : nil,
                              bookID: selectedBookID, bookName: selectedBookID.map { bookName($0) + "账本" } ?? (ledger.books.count == 1 ? ledger.books[0].name + "账本（只有这一个）" : "全部账本"),
                              selected: sel)
    }

    /// 外面的 AI 让 app 跳过去（MCP open_in_app）。
    func apply(_ r: AppBridge.OpenRequest) {
        if let m = r.month.flatMap(YearMonth.init) { selectedMonth = m }
        if let b = r.bookID, ledger.books.contains(where: { $0.id == b }) { selectedBookID = b }
        if !r.transactionIDs.isEmpty {
            highlighted = Set(r.transactionIDs)
            if r.month == nil, let d = r.transactionIDs.compactMap({ transaction($0) }).map(\.date).max() { selectedMonth = d.yearMonth }
            showTransactions(TransactionFilter(ids: Set(r.transactionIDs)))
        } else if let c = r.category {
            showTransactions(TransactionFilter(category: c))
        } else if let s = AppSection(rawValue: r.page) {
            section = s
        }
        let note = r.note.map { "\(r.author)：\($0)" } ?? "\(r.author) 让你看这里"
        toast = Toast(text: note, changeID: nil, seconds: 8)
    }

    /// 「看看」：去流水页，只列这几笔并高亮。
    public func showActivity() {
        guard let a = activity else { return }
        highlighted = Set(a.transactionIDs)
        if let first = a.transactionIDs.compactMap({ transaction($0) }).map(\.date).max() { selectedMonth = first.yearMonth }
        showTransactions(TransactionFilter(ids: Set(a.transactionIDs)))
        activity = nil
    }

    /// 「全部撤销」：把这一批从新到旧撤掉，一次保存。
    public func undoActivity() {
        guard let a = activity else { return }
        var copy = ledger
        var done = 0
        var failed = 0
        for id in a.undoableIDs {
            do { _ = try copy.undo(changeID: id, author: author); done += 1 } catch { failed += 1 }
        }
        activity = nil
        guard done > 0 else {
            toast = Toast(text: "这些改动撤不了，可以去「改动记录」一条条看", changeID: nil, isError: true)
            return
        }
        do {
            try store.save(copy)
            ledger = copy
            lastStamp = store.changeStamp()
            cache = nil; authorCache = nil
            dropMissingSelection()
            toast = Toast(text: failed == 0 ? "撤销了 \(done) 处改动" : "撤销了 \(done) 处，另有 \(failed) 处撤不了", changeID: nil, isError: failed > 0)
        } catch {
            toast = Toast(text: error.localizedDescription, changeID: nil, isError: true)
        }
    }

    /// 改一次账本：成功就保存并在底部给提示（能撤销），失败把错误抛给界面显示。
    @discardableResult
    public func edit(quiet: Bool = false, _ body: (inout Ledger) throws -> ChangeRecord) throws -> ChangeRecord {
        var copy = ledger
        let change = try body(&copy)
        try store.save(copy)
        lastStamp = store.changeStamp()
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
            lastStamp = store.changeStamp()
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
        var used = count.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        // 自己加的分类（还没用过也算），排在常用的后面、默认的前面。
        used += ledger.profile.categories.filter { $0.income == income && !used.contains($0.name) }.map(\.name)
        let defaults = CategoryStyle.defaults(book: ledger.books.first { $0.id == bookID }, income: income)
        // 账本里已经有「交通出行」，就不再另给一个「交通」，免得同一件事记成两个分类。
        let extra = defaults.filter { d in !used.contains { $0 == d || $0.hasPrefix(d) } }
        return Array((used + extra).prefix(limit))
    }

    /// 记一笔时「名称」下面的提示：以前用过的名字（整理过的商户名）和上次用的分类。
    /// 没输入时给最常用的几个，输入了就给包含这几个字的。
    public func nameSuggestions(_ query: String, income: Bool, limit: Int = 5) -> [(name: String, category: String?)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var stats: [String: (count: Int, category: String?, last: LocalDate)] = [:]
        for t in ledger.transactions where t.flow == nil && !t.isTransfer && t.amount.isIncome == income {
            let name = Merchant.display(t.description)
            guard !name.isEmpty, name.count <= 30 else { continue }
            var s = stats[name] ?? (0, t.category, t.date)
            s.count += 1
            if t.date >= s.last { s.last = t.date; if t.category != nil { s.category = t.category } }
            stats[name] = s
        }
        return stats
            .filter { q.isEmpty || ($0.key.lowercased().contains(q) && $0.key.lowercased() != q) }
            .sorted { $0.value.count == $1.value.count ? $0.value.last > $1.value.last : $0.value.count > $1.value.count }
            .prefix(limit).map { (name: $0.key, category: $0.value.category) }
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
