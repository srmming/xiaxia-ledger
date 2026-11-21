import FinanceCore
import Foundation

extension Ledger {
    /// 示例账本：所有人名、金额都是编的，只给预览、截图和模拟器演示用。
    public static var demo: Ledger {
        var l = Ledger.starter
        l.books = [Book(id: "personal", name: "个人"), Book(id: "miora", name: "我的小店")]
        l.accounts = [
            Account(id: "caixa", name: "CaixaBank", kind: .bank, institution: "CaixaBank"),
            Account(id: "imagin", name: "imagin", kind: .bank, institution: "imagin"),
            Account(id: "revolut", name: "Revolut", kind: .wallet, institution: "Revolut"),
            Account(id: "cash", name: "现金", kind: .cash),
            Account(id: "pot", name: "应急金储蓄罐", kind: .savings, institution: "Revolut"),
            Account(id: "stash", name: "私房钱", kind: .cash, isPrivate: true),
        ]
        func d(_ m: Int, _ day: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: day) }
        func c(_ v: Double) -> Money { Money(cents: Int64((v * 100).rounded())) }
        var txs: [Transaction] = []
        for m in 1...11 {
            let wiggle = Double((m * 37) % 11) * 13
            txs += [
                Transaction(date: d(m, 1), amount: c(2900), description: "工资", accountID: "caixa", bookID: "personal", category: "收入"),
                Transaction(date: d(m, 2), amount: c(-950), description: "房租", accountID: "caixa", bookID: "personal", category: "房租"),
                Transaction(date: d(m, 6), amount: c(-180 - wiggle), description: "Mercadona", accountID: "imagin", bookID: "personal", category: "超市"),
                Transaction(date: d(m, 9), amount: c(-96.4 - wiggle / 2), description: "餐厅", accountID: "revolut", bookID: "personal", category: "餐饮"),
                Transaction(date: d(m, 12), amount: c(-54.5), description: "交通卡", accountID: "imagin", bookID: "personal", category: "交通"),
                Transaction(date: d(m, 3), amount: c(4200 + wiggle * 11), description: "美甲收入（刷卡）", accountID: "caixa", bookID: "miora", category: "营业收入"),
                Transaction(date: d(m, 4), amount: c(700 + wiggle), description: "美甲收入（现金）", accountID: "cash", bookID: "miora", category: "营业收入"),
                Transaction(date: d(m, 5), amount: c(-500), description: "店租", accountID: "caixa", bookID: "miora", category: "店租"),
                Transaction(date: d(m, 8), amount: c(-1200), description: "员工工资", accountID: "caixa", bookID: "miora", category: "员工工资"),
                Transaction(date: d(m, 15), amount: c(-640 - wiggle * 2), description: "甲油胶和耗材", accountID: "caixa", bookID: "miora", category: "耗材"),
                Transaction(date: d(m, 20), amount: c(-115.2), description: "水电", accountID: "caixa", bookID: "miora", category: "水电"),
                Transaction(date: d(m, 25), amount: c(-300), description: "转进应急金", accountID: "caixa", bookID: "personal", category: "储蓄", flow: .saving),
                Transaction(date: d(m, 25), amount: c(300), description: "转进应急金", accountID: "pot", bookID: "personal", category: "储蓄", flow: .saving),
            ]
        }
        // 几笔不是每个月都有的，让各个月不一样。
        txs += [
            Transaction(date: d(3, 14), amount: c(-890), description: "新美甲椅", accountID: "caixa", bookID: "miora", category: "设备"),
            Transaction(date: d(4, 20), amount: c(-1480), description: "季度增值税", accountID: "caixa", bookID: "miora", category: "税费"),
            Transaction(date: d(7, 20), amount: c(-1610), description: "季度增值税", accountID: "caixa", bookID: "miora", category: "税费"),
            Transaction(date: d(10, 20), amount: c(-1390), description: "季度增值税", accountID: "caixa", bookID: "miora", category: "税费"),
            Transaction(date: d(8, 2), amount: c(-1240), description: "回国机票", accountID: "revolut", bookID: "personal", category: "旅行"),
            Transaction(date: d(8, 11), amount: c(-460), description: "给家里人买礼物", accountID: "revolut", bookID: "personal", category: "礼物"),
            Transaction(date: d(6, 18), amount: c(-320), description: "牙医", accountID: "caixa", bookID: "personal", category: "医疗"),
            Transaction(date: d(11, 11), amount: c(-139), description: "双十一买衣服", accountID: "revolut", bookID: "personal", category: "购物"),
            Transaction(date: d(11, 7), amount: c(-39.9), description: "手机话费", accountID: "caixa", bookID: "personal", category: "通讯"),
        ]
        txs.append(Transaction(date: d(11, 18), amount: c(-60), description: "偷偷买的香水", accountID: "stash", bookID: "personal", category: "其他"))
        txs.append(Transaction(date: d(10, 1), amount: c(400), description: "攒的私房钱", accountID: "stash", bookID: "personal", category: "收入"))
        let lend = Transaction(date: d(9, 3), amount: c(-500), description: "借给阿华", accountID: "revolut", bookID: "personal", category: "借款往来", flow: .debt)
        let back = Transaction(date: d(10, 20), amount: c(200), description: "阿华还款", accountID: "revolut", bookID: "personal", category: "借款往来", flow: .debt)
        let borrow = Transaction(date: d(6, 1), amount: c(2000), description: "向妈妈借", accountID: "caixa", bookID: "personal", category: "借款往来", flow: .debt)
        let payMom = Transaction(date: d(9, 1), amount: c(-1000), description: "还妈妈", accountID: "caixa", bookID: "personal", category: "借款往来", flow: .debt)
        let lamp = (1...3).map { k in
            Transaction(date: d(8 + k, 5), amount: c(-54.9), description: "美甲灯分期 \(k)/6", accountID: "caixa", bookID: "miora",
                        category: "分期还款", flow: .debt)
        }
        // 分期口径：买的那天全额算支出，同时记一笔分期借款进来；每期还款是还债。
        let lampBuy = Transaction(date: d(8, 20), amount: c(-329.4), description: "美甲灯和打磨机", accountID: "caixa", bookID: "miora", category: "设备")
        let lampLoan = Transaction(date: d(8, 20), amount: c(329.4), description: "美甲灯和打磨机（分期借款）", accountID: "caixa", bookID: "miora",
                                   category: "分期", flow: .debt)
        txs += [lend, back, borrow, payMom, lampBuy, lampLoan] + lamp
        // 账户间转账：取现，不算收支。
        let atm = UUID()
        txs += [
            Transaction(date: d(11, 10), amount: c(-200), description: "取现金", accountID: "caixa", category: "账户间转账", transferID: atm, flow: .internal),
            Transaction(date: d(11, 10), amount: c(200), description: "取现金", accountID: "cash", category: "账户间转账", transferID: atm, flow: .internal),
        ]
        // 刚导入、还没整理的几笔：演示「整理」。Mercadona 以前分过类，会自动猜成「超市 · 个人」。
        txs += [
            Transaction(date: d(11, 17), amount: c(-42.35), description: "MERCADONA", accountID: "imagin", bookID: "personal", category: "超市", source: "imagin-11月.csv"),
            Transaction(date: d(11, 19), amount: c(-27.9), description: "MERCADONA", accountID: "imagin", bookID: "personal", category: "超市", source: "imagin-11月.csv"),
            Transaction(date: d(11, 18), amount: c(-18.6), description: "GLOVO BARCELONA", accountID: "revolut", bookID: "personal", category: "餐饮", source: "revolut-11月.csv"),
            Transaction(date: d(11, 16), amount: c(-64), description: "AMAZON MKTPLACE", accountID: "revolut", bookID: "personal", category: "购物", source: "revolut-11月.csv"),
            Transaction(date: d(11, 14), amount: c(-64.2), description: "AMAZON MKTPLACE", accountID: "revolut", bookID: "personal", category: "购物", source: "revolut-11月.csv"),
            Transaction(date: d(11, 13), amount: c(85), description: "BIZUM 朋友还饭钱", accountID: "caixa", bookID: "personal", category: "收入", source: "caixa-11月.csv"),
        ]
        let openings: [(String, Double)] = [("caixa", 3200), ("imagin", 3600), ("revolut", 2900), ("cash", 180)]
        txs += openings.map { Transaction(date: d(1, 1), amount: c($0.1), description: "期初余额", accountID: $0.0, category: "期初余额", flow: .opening) }
        // 只留到 11 月 20 日，不出现未来日期。
        l.transactions = txs.filter { $0.date <= d(11, 20) }
        l.debts = [
            Debt(counterparty: "阿华", direction: .theyOweMe, principal: c(500), bookID: "personal", startDate: d(9, 3),
                 dueDate: d(10, 31), repaymentIDs: [back.id]),
            Debt(counterparty: "妈妈", direction: .iOweThem, principal: c(2000), bookID: "personal", startDate: d(6, 1),
                 dueDate: LocalDate(year: 2027, month: 3, day: 1), repaymentIDs: [payMom.id]),
        ]
        var lampPlan = Installment(name: "美甲灯和打磨机", bookID: "miora", accountID: "caixa", total: c(329.4), count: 6,
                                   firstDate: d(9, 5), paidIDs: lamp.map(\.id))
        lampPlan.purchaseID = lampBuy.id
        l.installments = [lampPlan]
        l.goals = [
            Goal(name: "应急金", bookID: "personal", target: c(6000), deadline: LocalDate(year: 2027, month: 4, day: 30), savingsAccountID: "pot"),
            Goal(name: "店铺装修", bookID: "miora", target: c(4000)),
        ]
        // 改动记录：借款各带一条，详情页才能看到借出那一笔；再放两条 AI 记的，演示「谁改的」。
        var lendChange = ChangeRecord(kind: .debt, summary: "记欠款：阿华 欠我 500,00 €", transactionIDs: [lend.id], author: "Codex")
        lendChange.debtID = l.debts[0].id
        var borrowChange = ChangeRecord(kind: .debt, summary: "记欠款：我欠 妈妈 2.000,00 €", transactionIDs: [borrow.id], author: "Claude")
        borrowChange.debtID = l.debts[1].id
        let imported = l.transactions.filter { $0.source?.hasSuffix(".csv") == true }
        l.changes = [
            ChangeRecord(kind: .importBatch, summary: "导入示例数据", transactionIDs: [], author: "示例"),
            lendChange, borrowChange,
            ChangeRecord(kind: .importBatch, summary: "导入 11 月对账单，新增 \(imported.count) 笔", transactionIDs: imported.map(\.id), author: "Claude"),
        ]
        // AI 写进来的意见（编的）。
        let nov = YearMonth(year: 2026, month: 11)
        let ago: (Double) -> Date = { Date().addingTimeInterval(-$0 * 3600) }
        l.insights = [
            Insight(month: nov, kind: .monthlyReview, title: "这个月花钱比上月慢，月底大概能剩 1.900 €。",
                    body: "少的主要是店里的耗材。房租和店租都已经付了，剩下的大头是 12 月 5 日的分期 54,90 €，余额够。超市这个月比上月多一点，可以留意。",
                    author: "Claude", createdAt: ago(2)),
            Insight(month: nov, kind: .alert, title: "超市比上月同期多花了一些", body: "多的主要是 Mercadona，去了 4 次。", metric: "category:超市",
                    author: "Claude", createdAt: ago(2)),
            Insight(month: nov, kind: .goodNews, title: "应急金已经存了一半", body: "照现在每月 300 € 的速度，明年 9 月左右存满；想在 4 月底前存满，每月要存 600 €。", author: "Codex", createdAt: ago(30)),
            Insight(month: nov, kind: .action, title: "阿华的 300 € 过了约定日期还没还", body: "10 月 31 日就该还了，要不要提醒一下？", author: "Claude", createdAt: ago(50)),
        ]
        return l
    }
}
