import Foundation

/// 「说明书」：给 AI 一次读懂财务背景。`fin context` 输出的就是它。
public struct LedgerContext: Codable, Sendable {
    public struct BookInfo: Codable, Sendable { public var id: String; public var name: String; public var transactions: Int }
    public struct AccountInfo: Codable, Sendable {
        public var id: String; public var name: String; public var kind: String
        public var balance: String; public var lastStatementDate: String?
        /// 私房钱：只回答 ming 本人，不写进给别人看的报表。
        public var isPrivate: Bool
    }

    public var books: [BookInfo]
    public var accounts: [AccountInfo]
    public var transactionCount: Int
    public var firstDate: String?
    public var lastDate: String?
    public var recentChanges: [String]
    /// 别人欠我（未还清）合计、我欠别人合计、进行中的分期数、目标数。
    public var owedToMe: String
    public var iOwe: String
    public var openDebts: Int
    public var activeInstallments: Int
    public var goals: Int
    public var unassignedCount: Int
    public var rules: [String]

    public static let rules: [String] = [
        "金额：正数是收入，负数是支出；显示用西班牙格式 1.234,56 €。",
        "每笔流水单独归一个账本；账户（银行卡、现金等）不固定属于某个账本。",
        "账本间转账两边各记一笔、共用 transferID；单个账本照常统计，「全部」汇总时抵消。",
        "去重：同账户 + 同日期 + 同金额 + 描述归一化后相同 = 同一笔。",
        "借出、借入、还款记为「往来」（flow=debt），存进目标记为「储蓄」（flow=saving），都不算收入或支出。",
        "自己账户之间转钱（转去 Revolut 充值、还信用卡、主账户和 imagin 互转）记为「互转」（flow=internal），两边各一笔，不算收入或支出。新记用 fin transfer move，已导入的流水用 fin transfer mark 标成互转。",
        "分期：买的那天按全额记支出；之后每期扣款是还债（flow=debt），不进收支；手续费、利息单独记支出。用 fin installment add 建、fin installment pay 记一期，导入的扣款用 --tx 认领；fin installments 看还剩几期。",
        "用户问「谁欠我钱」「我还欠谁」，用 fin debts 回答；问存钱进度，用 fin goals。",
        "私房钱（isPrivate 的账户）：ming 问才说；做给店里、合伙人、gestoría 的报表时不要算进去。",
        "记欠款用 fin debt add，记还款用 fin debt repay；先用 fin debts 确认是哪一笔、还欠多少。",
        "锁定的储蓄目标（locked）存进去就不能动，不要建议从里面取钱。",
        "拿不准的事（属于哪个账本、怎么分类）先在对话里问 ming，确认后再写；不要猜着写。",
        "每次写入都记进改动记录（谁改的、改了什么），可以用 fin undo 撤销。",
        "不动钱、不碰银行密码；银行数据只读。",
    ]

    public init(ledger: Ledger) {
        let balances = Summaries.balances(ledger.transactions)
        books = ledger.books.map { b in
            BookInfo(id: b.id, name: b.name, transactions: ledger.transactions.filter { $0.bookID == b.id }.count)
        }
        accounts = ledger.accounts.map { a in
            AccountInfo(id: a.id, name: a.name, kind: a.kind.rawValue,
                        balance: (balances[a.id] ?? .zero).formatted,
                        lastStatementDate: ledger.lastStatementDate[a.id]?.description, isPrivate: a.isPrivate)
        }
        transactionCount = ledger.transactions.count
        let dates = ledger.transactions.map(\.date).sorted()
        firstDate = dates.first?.description
        lastDate = dates.last?.description
        let debtList = Plans.debts(ledger, today: .today)
        owedToMe = debtList.filter { $0.direction == .theyOweMe }.reduce(Money.zero) { $0 + $1.outstanding }.formatted
        iOwe = debtList.filter { $0.direction == .iOweThem }.reduce(Money.zero) { $0 + $1.outstanding }.formatted
        openDebts = debtList.count
        activeInstallments = Plans.installments(ledger).filter { $0.paidCount < $0.count }.count
        goals = ledger.goals.count
        recentChanges = ledger.changes.filter { !$0.undone }.suffix(5).reversed().map { "\($0.author)：\($0.summary)" }
        unassignedCount = ledger.transactions.filter { $0.bookID == nil }.count
        rules = Self.rules
    }
}
