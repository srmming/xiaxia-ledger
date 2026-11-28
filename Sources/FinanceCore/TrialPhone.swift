import Foundation

// iPhone 界面 v3 用到的两条规则（Mac 以后也能用）。
extension TrialBook {
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
