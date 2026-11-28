import Foundation

// iPhone 界面 v3 用到的两条规则（Mac 以后也能用）。
extension TrialBook {
    /// 删掉大目标：存进去的钱从目标罐回到日常的账户，「留给目标」的那部分不再从每月随便花里扣。小目标不动。
    public mutating func dropMainGoal() throws {
        guard journey.total > .zero else { throw TrialError("现在没有大目标") }
        let back = journey.saved
        if back > .zero, let jar = accounts.firstIndex(where: { $0.block == .goal }),
           let daily = accounts.firstIndex(where: { $0.kind == .own && $0.block == .daily }) {
            let m = min(back, accounts[jar].balance)
            accounts[jar].balance = accounts[jar].balance - m
            accounts[daily].balance = accounts[daily].balance + m
        }
        journey = Journey(name: "", stations: [], saved: .zero, monthlyPlan: .zero)
        month.forGoals = .zero
    }

    /// 生意那边记一笔收的钱：加到那天这个渠道已经收的上面。
    public mutating func addShopIncome(_ amount: Money, account: String, daysAgo: Int) throws {
        guard amount > .zero else { throw TrialError("金额要比 0 大") }
        let day = todayDay - daysAgo
        guard let d = shopDays.first(where: { $0.day == day }) else { throw TrialError("只能记这个月的营业额") }
        var parts = channels(of: d)
        if let k = parts.firstIndex(where: { $0.account == account }) { parts[k].amount = parts[k].amount + amount } else { parts.append(ShopChannel(account, amount)) }
        try recordShopDay(day, channels: parts)
    }
}
