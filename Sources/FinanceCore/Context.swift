import Foundation

/// 「说明书」：给 AI 一次读懂财务背景。`fin context` 输出的就是它。
public struct LedgerContext: Codable, Sendable {
    public struct BookInfo: Codable, Sendable { public var id: String; public var name: String; public var transactions: Int }
    public struct AccountInfo: Codable, Sendable {
        public var id: String; public var name: String; public var kind: String
        public var balance: String; public var lastStatementDate: String?
        /// 私房钱：只回答用户本人，不写进给别人看的报表。
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
    /// 夏夏（app 里 AI 的名字）的说话方式：写意见、回答用户时照这个口吻。
    public var voice: String
    public var persona: String
    /// 用户想让夏夏帮他做到什么。给意见时围着它说。
    public var aim: String?
    public var rules: [String]

    public static let rules: [String] = [
        "金额：正数是收入，负数是支出；显示用西班牙格式 1.234,56 €。",
        "每笔流水单独归一个账本；账户（银行卡、现金等）不固定属于某个账本。",
        "账本间转账两边各记一笔、共用 transferID；单个账本照常统计，「全部」汇总时抵消。",
        "去重：同账户 + 同日期 + 同金额 + 描述归一化后相同 = 同一笔。",
        "借出、借入、还款记为「往来」（flow=debt），存进目标记为「储蓄」（flow=saving），都不算收入或支出。",
        "自己账户之间转钱（给另一张卡充值、还信用卡、两个银行账户互转）记为「互转」（flow=internal），两边各一笔，不算收入或支出。新记用 fin transfer move，已导入的流水用 fin transfer mark 标成互转。",
        "退款（之前花的钱退回来）沿用原来那笔支出的分类，金额记正数：它冲减这个分类的支出，不算收入。",
        "分期：买的那天按全额记支出；之后每期扣款是还债（flow=debt），不进收支；手续费、利息单独记支出。用 fin installment add 建、fin installment pay 记一期，导入的扣款用 --tx 认领；fin installments 看还剩几期。",
        "用户问「谁欠我钱」「我还欠谁」，用 fin debts 回答；问存钱进度，用 fin goals。",
        "私房钱（isPrivate 的账户）：用户本人问才说；做给别人看（合伙人、会计）的报表时不要算进去。",
        "记欠款用 fin debt add，记还款用 fin debt repay；先用 fin debts 确认是哪一笔、还欠多少。",
        "锁定的储蓄目标（locked）存进去就不能动，不要建议从里面取钱。",
        "拿不准的事（属于哪个账本、怎么分类）先在对话里问用户，确认后再写；不要猜着写。",
        "每次写入都记进改动记录（谁改的、改了什么），可以用 fin undo 撤销。",
        "不动钱、不碰银行密码；银行数据只读。",
        "app 里的 AI 叫「夏夏」。写意见（add_insight）时照 voice 的口吻，围着 aim（用户的目标）说；page 填写给哪一页（overview / spending / trends / wealth / plans）。",
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
        persona = ledger.profile.persona.label
        voice = ledger.profile.persona.instruction
        aim = ledger.profile.aim
        rules = Self.rules
    }
}
