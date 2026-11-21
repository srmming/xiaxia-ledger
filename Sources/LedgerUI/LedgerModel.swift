import FinanceCore
import Foundation
import Observation

/// app 里的账本状态。和 fin 读写同一份账本，所有写入都走 FinanceCore 的规则，记进改动记录。
@MainActor @Observable
public final class LedgerModel {
    public let store: any LedgerStore
    public private(set) var ledger: Ledger = .starter
    public var selectedBookID: String?        // nil = 全部
    public var showPrivate = false            // 私房钱默认藏起来
    public var loadError: String?
    public var lastMessage: String?           // 保存、撤销后的提示
    public var isLoading = true
    /// app 里的写入都算 ming 记的。
    public var author = "ming"

    public init(store: any LedgerStore) {
        self.store = store
        reload()
    }

    public func reload() {
        isLoading = true
        defer { isLoading = false }
        do { ledger = try store.load(); loadError = nil }
        catch { loadError = error.localizedDescription }
    }

    /// 改一次账本：成功就保存并给提示，失败把错误抛给界面显示。
    @discardableResult
    public func edit(_ body: (inout Ledger) throws -> ChangeRecord) throws -> ChangeRecord {
        var copy = ledger
        let change = try body(&copy)
        try store.save(copy)
        ledger = copy
        lastMessage = change.summary
        return change
    }

    // MARK: 给界面用的派生数据

    public var hiddenAccounts: Set<String> { showPrivate ? [] : ledger.privateAccountIDs }

    public var visibleAccounts: [Account] { ledger.accounts.filter { showPrivate || !$0.isPrivate } }

    public var visibleTransactions: [FinanceCore.Transaction] {
        ledger.transactions.filter { !hiddenAccounts.contains($0.accountID) }
            .filter { selectedBookID == nil || $0.bookID == selectedBookID }
            .sorted { ($0.date, $0.description) > ($1.date, $1.description) }
    }

    public var balances: [String: Money] { Summaries.balances(ledger.transactions) }

    public var totalBalance: Money {
        visibleAccounts.reduce(.zero) { $0 + (balances[$1.id] ?? .zero) }
    }

    /// 最新有流水的月份；没有流水就是本月。
    public var currentMonth: YearMonth { ledger.transactions.map(\.date).max()?.yearMonth ?? LocalDate.today.yearMonth }

    public func summary(_ month: YearMonth) -> MonthlySummary {
        Summaries.monthly(ledger.transactions, month: month, bookID: selectedBookID, hiddenAccounts: hiddenAccounts)
    }

    /// 最近 n 个月（含当月），从早到晚。
    public func recentMonths(_ n: Int) -> [YearMonth] {
        let cur = currentMonth
        return (0..<n).reversed().map { k in
            let m = cur.year * 12 + (cur.month - 1) - k
            return YearMonth(year: m / 12, month: m % 12 + 1)
        }
    }

    public func bookName(_ id: String?) -> String {
        guard let id else { return "全部" }
        return ledger.books.first { $0.id == id }?.name ?? id
    }

    public func accountName(_ id: String) -> String { ledger.accounts.first { $0.id == id }?.name ?? id }

    /// 流水里出现过的分类（含「未分类」），筛选用。
    public var usedCategories: [String] {
        Array(Set(ledger.transactions.filter { $0.flow == nil }.map { $0.category ?? "未分类" })).sorted()
    }

    /// 总览看哪个月；nil = 最新有流水的月份。
    public var selectedMonth: YearMonth? = nil
    public var shownMonth: YearMonth { selectedMonth ?? currentMonth }

    /// 用过的分类，按次数排，记一笔时给建议。
    public var knownCategories: [String] {
        var count: [String: Int] = [:]
        for t in ledger.transactions { if let c = t.category, t.flow == nil { count[c, default: 0] += 1 } }
        let used = count.sorted { $0.value > $1.value }.map(\.key)
        let defaults = ["餐饮", "超市", "交通", "房租", "耗材", "店租", "工资", "水电", "收入", "其他"]
        return used + defaults.filter { !used.contains($0) }
    }
}

extension LedgerModel {
    /// 预览和截图用的内存账本，数字全是编的。
    public static func demo() -> LedgerModel { LedgerModel(store: InMemoryLedgerStore(.demo)) }
}
