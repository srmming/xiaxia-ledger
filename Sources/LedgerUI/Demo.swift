import FinanceCore
import Foundation

extension Ledger {
    /// 示例账本：所有人名、金额都是编的，只给预览、截图和模拟器演示用。
    public static var demo: Ledger {
        var l = Ledger.starter
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
                Transaction(date: d(m, 3), amount: c(4600 + wiggle * 5), description: "美甲收入（刷卡）", accountID: "caixa", bookID: "miora", category: "营业收入"),
                Transaction(date: d(m, 4), amount: c(700 + wiggle), description: "美甲收入（现金）", accountID: "cash", bookID: "miora", category: "营业收入"),
                Transaction(date: d(m, 5), amount: c(-500), description: "店租", accountID: "caixa", bookID: "miora", category: "店租"),
                Transaction(date: d(m, 8), amount: c(-1200), description: "员工工资", accountID: "caixa", bookID: "miora", category: "员工工资"),
                Transaction(date: d(m, 15), amount: c(-640 - wiggle * 2), description: "甲油胶和耗材", accountID: "caixa", bookID: "miora", category: "耗材"),
                Transaction(date: d(m, 20), amount: c(-115.2), description: "水电", accountID: "caixa", bookID: "miora", category: "水电"),
                Transaction(date: d(m, 25), amount: c(-300), description: "转进应急金", accountID: "caixa", bookID: "personal", category: "储蓄", flow: .saving),
                Transaction(date: d(m, 25), amount: c(300), description: "转进应急金", accountID: "pot", bookID: "personal", category: "储蓄", flow: .saving),
            ]
        }
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
            Goal(name: "应急金", bookID: "personal", target: c(6000), savingsAccountID: "pot"),
            Goal(name: "店铺装修", bookID: "miora", target: c(4000), deadline: LocalDate(year: 2027, month: 6, day: 30)),
        ]
        l.changes = [ChangeRecord(kind: .importBatch, summary: "导入示例数据", transactionIDs: [], author: "示例")]
        return l
    }
}
