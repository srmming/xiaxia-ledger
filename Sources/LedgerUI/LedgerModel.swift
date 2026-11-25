import FinanceCore
import Foundation
import Observation

/// app 里能弹出来的窗口。导入、整理、记欠款这些都交给 AI 了，app 里只留极简「记一笔」。
public enum AppSheet: String, Identifiable, Hashable {
    case add
    /// 管理账本、账户、分类。
    case books, accounts, categories
    /// 夏夏的记忆（设置里进）。
    case memory
    /// 新建分类：先挑图标再填名字。
    case newCategory
    /// 连上你的 AI（Mac 第一次打开、设置里）。
    case connectAI
    /// 目标页「新目标」：一步一页的设目标引导（小金猪）。
    case plan
    /// 欠款与分期页：直接打开登记分期 / 借款。
    case newInstallment, newDebt
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
        /// 提示里的一个按钮（比如「打开 Claude」）：由用户自己点，不替用户跳走。
        public var actionLabel: String? = nil
        public var actionURL: URL? = nil
        /// 按钮的链接打不开时改开这个（Claude app 没装 → 网页版）。
        public var fallbackURL: URL? = nil
    }

    /// 现在读写的账本。平时是真账本；「看看演示数据」时换成内存里的示例账本（不写任何文件），退出再换回来。
    public private(set) var store: any LedgerStore
    /// 正在看演示数据时，真账本的存储先放在这儿。
    @ObservationIgnored private var realStore: (any LedgerStore)?
    /// 正在看演示数据（设置 → 数据 里进的，不是启动参数那种）。
    public private(set) var isTryingDemo = false
    public private(set) var ledger: Ledger = .fresh {
        didSet { CategoryStyle.customIcons = ledger.categoryIcons }
    }
    public var selectedBookID: String? { didSet { publishView() } }       // nil = 全部
    public var showPrivate = false            // 私房钱默认藏起来
    public var loadError: String?
    public var isLoading = true
    /// app 里的写入记在谁名下：设置里填的名字，没填就用这台设备的用户名。
    /// 助手现在叫什么（默认「夏夏」），和把界面文字里的「夏夏」换成这个名字。
    /// 夏夏的名字。没改过名、界面又不是中文时叫 Xiaxia。
    var xiaName: String {
        let name = ledger.profile.xiaName
        return name == "夏夏" && L10n.language != .zhHans ? "Xiaxia" : name
    }
    func xia(_ text: String) -> String { ledger.profile.renamed(text) }

    public var author: String = LedgerModel.defaultAuthor {
        didSet { UserDefaults.standard.set(author, forKey: "xiaxia.userName") }
    }

    static var defaultAuthor: String {
        if let saved = UserDefaults.standard.string(forKey: "xiaxia.userName"), !saved.isEmpty { return saved }
        #if os(macOS)
        return NSUserName()
        #else
        return tr("我")
        #endif
    }

    @ObservationIgnored var authorCache: (count: Int, map: [UUID: String])?

    /// 现在在哪一页、弹着哪个窗口。
    public var section: AppSection? = .overview { didSet { publishView() } }
    public var sheet: AppSheet?
    /// 「改这一笔」：打开记一笔面板前设好，面板就按这一笔填好、按钮变「保存」。
    public var editingID: UUID?
    /// 「记一笔」按这个预先填好（生意首页的「记今天进账」等），面板打开时用掉就清空。
    public var addPreset: AddPreset?
    /// 第一次打开的开始引导（夏夏带着建账本、账户、连 AI）正在显示。
    public var showWelcome = false
    /// 从「问夏夏」的「去连接」进引导：跳过账本、账户，直接到连 AI 那一步。
    public var welcomeAtAI = false
    /// 做完一件事后底部的提示。
    public var toast: Toast?
    /// 这次打开 app 以来自己做的改动，⌥⌘Z 从最后一条往回撤。
    public fileprivate(set) var undoStack: [UUID] = []

    /// 总览看哪个月；nil = 最新有流水的月份。
    public var selectedMonth: YearMonth? = nil { didSet { publishView() } }

    public init(store: any LedgerStore) {
        self.store = store
        reload()
        postDueRecurring()
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
        // app 一直开着跨了天（Mac 常这样）：回来时把到日子的重复记账补上。
        defer { postDueRecurring() }
        lastStamp = store.changeStamp()
        guard loadError == nil, let fresh = try? store.load(), fresh != ledger else { return }
        let old = ledger
        ledger = fresh
        cache = nil; authorCache = nil
        dropMissingSelection()
        let found = ExternalActivity.between(old, fresh, me: author)
        activity = (found.map { f in activity.map { $0.merged(with: f) } ?? f } ?? activity)?.current(in: fresh)
        // AI 在外面记了账：夏夏也拿笔写一下（同类 3 秒内只反应一次）。
        if found != nil { MascotMood.shared.note(.recorded) }
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
    @ObservationIgnored fileprivate var lastStamp: String?

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
                              bookID: selectedBookID, bookName: selectedBookID.map { bookName($0) + tr("账本") } ?? (ledger.books.count == 1 ? ledger.books[0].name + tr("账本（只有这一个）") : tr("全部账本")),
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
        let note = r.note.map { "\(r.author)：\($0)" } ?? tr("\(r.author) 让你看这里")
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
            toast = Toast(text: tr("这些改动撤不了，可以去「改动记录」一条条看"), changeID: nil, isError: true)
            return
        }
        do {
            try store.save(copy)
            ledger = copy
            lastStamp = store.changeStamp()
            cache = nil; authorCache = nil
            dropMissingSelection()
            toast = Toast(text: failed == 0 ? tr("撤销了 \(done) 处改动") : tr("撤销了 \(done) 处，另有 \(failed) 处撤不了"), changeID: nil, isError: failed > 0)
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
        let oldIDs = Set(ledger.transactions.map(\.id))
        let today = LocalDate.today
        let wasRecovered = ledger.capitalProgress(today: today)?.estimate == .done
        ledger = copy
        reactMascot(to: change, wasRecovered: wasRecovered, today: today)
        cache = nil; authorCache = nil
        dropMissingSelection()
        revealAdded(copy.transactions.filter { !oldIDs.contains($0.id) })
        if change.canUndo { undoStack.append(change.id) }
        if !quiet { toast = Toast(text: change.summary, changeID: change.canUndo ? change.id : nil) }
        return change
    }

    /// 夏夏对这次改动的反应：记了一笔就拿笔写一下，存进目标或生意回本就庆祝（见 MascotMood）。
    private func reactMascot(to change: ChangeRecord, wasRecovered: Bool, today: LocalDate) {
        let mood = MascotMood.shared
        if !wasRecovered, ledger.capitalProgress(today: today)?.estimate == .done { return mood.note(.recovered) }
        switch change.kind {
        case .add, .importBatch, .transfer, .capture: mood.note(.recorded)
        // 「取出」也记成 goalDeposit，只有存进去才庆祝（这句话由 FinanceCore 生成，不翻译）。
        case .goalDeposit where !change.summary.contains("取出"): mood.note(.saved)
        default: mood.wake()
        }
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

    /// 刚记的流水不在正在看的月份 / 账本里：跳过去，免得记了却「没出来」。
    func revealAdded(_ added: [FinanceCore.Transaction]) {
        guard let latest = added.map(\.date).max() else { return }
        // 开着生意模式时不回到「全部」，跳到刚记的那一边。
        if let b = selectedBookID, !added.contains(where: { $0.bookID == b }) { selectedBookID = businessOn ? added.last?.bookID ?? b : nil }
        if !added.contains(where: { $0.date.yearMonth == shownMonth }) { selectedMonth = latest.yearMonth }
    }

    /// 正在看的账本被删了：回到「全部」。
    fileprivate func dropMissingSelection() {
        if let b = selectedBookID, !ledger.books.contains(where: { $0.id == b }) { selectedBookID = nil }
    }

    public func undoLast() {
        guard let last = undoStack.last else { return }
        undo(last)
    }

    // MARK: 给界面用的派生数据（算一次存着，账本一变就重算）

    fileprivate struct Cache {
        var showPrivate: Bool
        var balances: [String: Money]
        var suggester: Suggester
        /// 金额换成主币种的流水（没有外币账户时就是原来的）。
        var baseTxs: [FinanceCore.Transaction]
        /// 账户自己币种的余额。
        var nativeBalances: [String: Money]
    }
    @ObservationIgnored fileprivate var cache: Cache?

    private func cached() -> Cache {
        if let c = cache, c.showPrivate == showPrivate { return c }
        let base = ledger.baseTransactions
        let all = ledger.accountBalances()
        let c = Cache(showPrivate: showPrivate, balances: all.mapValues(\.base), suggester: Suggester(ledger.transactions),
                      baseTxs: base, nativeBalances: all.mapValues(\.native))
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

    /// 每个账户的余额，换成主币种（外币按今天的汇率）。加起来算家底用它。
    public var balances: [String: Money] { cached().balances }
    /// 每个账户自己币种的余额（美元卡就是美元）。
    public var nativeBalances: [String: Money] { cached().nativeBalances }
    /// 换成主币种的流水：所有「加起来」的统计都用它。
    public var baseTransactions: [FinanceCore.Transaction] { cached().baseTxs }
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
        Summaries.monthly(baseTransactions, month: month, bookID: selectedBookID, hiddenAccounts: hiddenAccounts)
    }

    public func summaries(_ months: [YearMonth], bookID: String?) -> [MonthlySummary] {
        Reports.summaries(baseTransactions, months: months, bookID: bookID, hiddenAccounts: hiddenAccounts)
    }

    public func summaries(_ months: [YearMonth]) -> [MonthlySummary] { summaries(months, bookID: selectedBookID) }

    /// 最近 n 个月（含当月），从早到晚。
    public func recentMonths(_ n: Int) -> [YearMonth] { Reports.months(endingAt: currentMonth, count: n) }

    /// 有记录的月份（选月份的面板里加小点）。
    public var recordedMonths: Set<YearMonth> {
        let hidden = hiddenAccounts
        return Set(ledger.transactions.lazy.filter { !hidden.contains($0.accountID) }.map(\.date.yearMonth))
    }

    /// 有流水的年份，从新到旧。
    public var years: [Int] {
        let ys = Set(ledger.transactions.map(\.date.year)).union([LocalDate.today.year])
        return ys.sorted(by: >)
    }

    public func bookName(_ id: String?) -> String {
        guard let id else { return tr("全部") }
        return ledger.books.first { $0.id == id }?.name ?? id
    }

    public func accountName(_ id: String) -> String { ledger.accounts.first { $0.id == id }?.name ?? id }

    public func transaction(_ id: UUID) -> FinanceCore.Transaction? { ledger.transactions.first { $0.id == id } }

    /// 流水里出现过的分类（含「未分类」），筛选用。
    public var usedCategories: [String] {
        Array(Set(ledger.transactions.filter { $0.flow == nil }.map { $0.category ?? tr("未分类") })).sorted()
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

// MARK: 演示数据、删除数据、从备份恢复（设置 → 数据）

extension LedgerModel {
    /// 换一个账本来看：页面、月份、选中的东西都回到开头。
    /// 换一本账（iPhone 接上 / 断开 iCloud 文件夹时）。
    public func useStore(_ new: any LedgerStore) { switchStore(to: new) }

    private func switchStore(to new: any LedgerStore) {
        store = new
        selectedBookID = nil
        selectedMonth = nil
        selectedTransactionID = nil
        highlighted = []
        activity = nil
        pendingFilter = nil
        undoStack = []
        reload()
        lastStamp = store.changeStamp()
    }

    /// 「看看演示数据」：换成内存里的示例账本，随便点随便改，都不会存进自己的账本。
    public func enterDemo() {
        guard !isTryingDemo else { return }
        realStore = store
        var l = Ledger.demo
        // 夏夏的名字、性格、称呼跟自己设的一样，看起来还是「自己的 app」。
        l.profile.persona = ledger.profile.persona
        l.profile.assistantName = ledger.profile.assistantName
        l.profile.userCallName = ledger.profile.userCallName
        isTryingDemo = true
        switchStore(to: InMemoryLedgerStore(l))
        // 每页顶上有一条「正在看演示数据」，这里不再弹一句一样的话。
        section = .overview
        toast = nil
    }

    /// 「退出演示」：回到自己的账本。演示里改的东西都不留。
    public func exitDemo() {
        guard isTryingDemo, let real = realStore else { return }
        realStore = nil
        isTryingDemo = false
        switchStore(to: real)
        toast = Toast(text: tr("回到你自己的账本了"), changeID: nil)
    }

    /// 账本文件在哪；示例数据、演示数据没有文件。
    public var ledgerFileURL: URL? { LedgerBackup.fileURL(of: store) }

    /// 删除前的备份，从新到旧。
    public var backups: [LedgerBackup.Item] { ledgerFileURL.map { LedgerBackup.list(for: $0) } ?? [] }

    /// 删除数据：先把账本文件复制一份到「删除前备份」，复制不成就不删。返回备份的位置（内存账本没有）。
    @discardableResult
    public func wipe(_ scope: WipeScope) throws -> URL? {
        var backup: URL?
        if let file = ledgerFileURL { backup = try LedgerBackup.make(of: file, label: "删除前") }
        var copy = ledger
        try copy.wipe(scope, author: author, backupNote: backup.map { "\(LedgerBackup.folderName)/\($0.lastPathComponent)" })
        try store.save(copy)
        lastStamp = store.changeStamp()
        ledger = copy
        cache = nil; authorCache = nil
        undoStack = []
        selectedMonth = nil
        selectedTransactionID = nil
        highlighted = []
        activity = nil
        dropMissingSelection()
        return backup
    }

    /// 从备份恢复：先把现在的账本也备份一份，再把备份里的内容存回来。
    public func restore(_ item: LedgerBackup.Item) throws {
        // 带上这个窗口读到的账本：恢复期间别处改过账本，保存会被拒，不会盖掉别人刚记的。
        let old = try LedgerBackup.load(item.url, replacing: ledger)
        if let file = ledgerFileURL { try LedgerBackup.make(of: file, label: "恢复前") }
        try store.save(old)
        lastStamp = store.changeStamp()
        ledger = old
        cache = nil; authorCache = nil
        undoStack = []
        selectedMonth = nil
        dropMissingSelection()
    }
}

extension LedgerModel {
    /// 预览和截图用的内存账本，数字全是编的。
    /// persona：截图时看不同性格（-XiaxiaPersona cheer），只改内存里的示例账本。
    public static func demo(persona: Persona? = nil) -> LedgerModel {
        var l = Ledger.demo
        if let persona { l.profile.persona = persona }
        return LedgerModel(store: InMemoryLedgerStore(l))
    }
    /// 空账本：看第一次打开的样子。
    public static func empty() -> LedgerModel { LedgerModel(store: InMemoryLedgerStore(.fresh)) }
}
