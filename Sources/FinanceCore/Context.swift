import Foundation

/// 「说明书」：给 AI 一次读懂财务背景。`fin context` 输出的就是它。
public struct LedgerContext: Codable, Sendable {
    public struct BookInfo: Codable, Sendable { public var id: String; public var name: String; public var transactions: Int }
    public struct AccountInfo: Codable, Sendable {
        public var id: String; public var name: String; public var kind: String
        public var balance: String; public var lastStatementDate: String?
        /// 私房钱：只回答用户本人，不写进给别人看的报表。
        public var isPrivate: Bool
        /// 账户币种（三个字母）。balance 是这个币种的；balanceInBase 是换成主币种的（只有外币账户有）。
        public var currency: String
        public var balanceInBase: String?
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
    /// 主币种：所有汇总、月报都换成它。
    public var baseCurrency: String
    /// 订阅：在续的个数、每月合计、一年合计（主币种），以及 7 天内要扣的。
    public var subscriptions: Int
    public var subscriptionsMonthly: String
    public var subscriptionsYearly: String
    public var subscriptionsDueSoon: [String]
    /// 缺汇率的外币（还没联网取过）。
    public var missingRates: [String]
    /// 夏夏（app 里 AI 的名字）的说话方式：写意见、回答用户时照这个口吻。
    public var voice: String
    public var persona: String
    /// 用户想让夏夏帮他做到什么。给意见时围着它说。
    public var aim: String?
    /// 夏夏的记忆：用户定的规矩（全文）、其它记忆的目录、记忆怎么用。
    public var memory: MemoryBrief
    /// 每月固定进出（工资、房租、话费……），从最近 12 个月的流水现算。用户问「工资多少」「每月固定要花多少」先看这里。
    public var regulars: [String]
    /// 问什么用哪个工具。
    public var toolGuide: [String]
    public var rules: [String]

    public static let rules: [String] = [
        "金额：正数是收入，负数是支出；显示用西班牙格式 1.234,56 €。",
        "多币种：每个账户有自己的币种（accounts[].currency），流水金额就是这个账户币种的数（美元卡记美元）。汇总、月报都换成主币种（baseCurrency），外币按那天的欧洲央行汇率；银行实际扣了多少主币种以银行为准，用 fin fx set-rate --bank 改。欧元卡在国外刷外币：金额记银行扣的欧元，原价用 --original 记成备注。",
        "订阅：每月 / 每年固定在扣的钱（会员、软件、健身房、云服务）。用户说「我订了什么」用 fin subscriptions 回答；fin subscription find 能从流水里认出可能是订阅的，先在对话里问用户哪些是，确认后再 fin subscription add；涨价了用 fin subscription edit，不续了用 fin subscription cancel。",
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
        "用户欠别人钱时：帮着看这个月哪些分类花多了、能省出多少，排一个每月还多少、哪个月还清的计划。夏夏偶尔会开玩笑说「要不我们想个法子赖掉吧」，用户真附和也马上说是逗他们的，拉回还钱计划；绝不帮着赖账、躲债或编理由骗人。",
        "锁定的储蓄目标（locked）存进去就不能动，不要建议从里面取钱。",
        "拿不准的事（属于哪个账本、怎么分类）先在对话里问用户，确认后再写；不要猜着写。",
        "每次写入都记进改动记录（谁改的、改了什么），可以用 fin undo 撤销。",
        "不动钱、不碰银行密码；银行数据只读。",
        "记忆：memory.rules 是用户定的规矩，每次照做；memory.howTo 说了什么时候记、什么不记。用户说「记住……」「以后都……」「别再……」就用 remember 记下来。",
        "app 里的 AI 叫「夏夏」。写意见（add_insight）时照 voice 的口吻，围着 aim（用户的目标）说；page 填写给哪一页（overview / spending / trends / wealth / plans / debts）。",
    ]

    /// 问什么用哪个工具：免得问收入去翻支出、问余额去加流水。
    public static let toolGuide: [String] = [
        "先看 memory.rules：用户对「收益」「结余」「生活费」这些词有自己的说法时，照他的说法算。",
        "收入、支出、结余、某个分类花了多少（一个月 / 一年 / 一段时间）→ summary。只问收入就只答收入那一行，不用把支出明细念一遍。",
        "工资多少、每月固定进出多少 → context 里的 regulars（或 regulars 工具），不用自己翻流水加。",
        "某几笔、某家店、某个标签、某天花了什么 → list_transactions（用 query / category / month 缩小范围）。",
        "卡里、账户里现在有多少 → accounts。不要拿流水自己加。",
        "订阅 → subscriptions；谁欠谁 → debts；分期 → installments；存钱进度 → goals。",
        "要一段能直接读给用户的月度总结 → monthly_report。",
        "用户说「这笔」「这页」「我在看的」→ current_view。",
        "聊到 memory.index 里有的话题、或要做导入 / 对账 / 月报之前 → memory（填 id 或 query）把那条读出来。",
    ]

    public init(ledger: Ledger) {
        let balances = ledger.accountBalances()
        books = ledger.books.map { b in
            BookInfo(id: b.id, name: b.name, transactions: ledger.transactions.filter { $0.bookID == b.id }.count)
        }
        accounts = ledger.accounts.map { a in
            let code = ledger.currency(ofAccount: a.id)
            let b = balances[a.id] ?? (.zero, .zero)
            return AccountInfo(id: a.id, name: a.name, kind: a.kind.rawValue,
                        balance: b.native.formatted(in: code),
                        lastStatementDate: ledger.lastStatementDate[a.id]?.description, isPrivate: a.isPrivate,
                        currency: code, balanceInBase: code == ledger.baseCurrency ? nil : b.base.formatted(in: ledger.baseCurrency))
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
        baseCurrency = ledger.baseCurrency
        let subs = Subscriptions.status(ledger)
        let totals = Subscriptions.totals(subs)
        subscriptions = totals.activeCount
        subscriptionsMonthly = totals.monthly.formatted(in: ledger.baseCurrency)
        subscriptionsYearly = totals.yearly.formatted(in: ledger.baseCurrency)
        subscriptionsDueSoon = subs.filter { $0.cancelledOn == nil && $0.isDueSoon }
            .map { "\($0.name) \($0.nextDate?.description ?? "") \($0.amount.formatted(in: $0.currency))" }
        missingRates = ledger.missingRateCurrencies
        persona = ledger.profile.persona.label
        voice = ledger.profile.persona.instruction
        aim = ledger.profile.aim
        memory = MemoryBrief(ledger: ledger)
        regulars = Regulars.lines(ledger)
        toolGuide = Self.toolGuide
        rules = Self.rules
    }
}
