import FinanceCore

/// debts 工具后面附上的还款计划（欠款改分期）：每笔还到第几期、下一期哪天还多少，以及这个月要还多少、哪天全部还清。
func debtPlansText(_ ledger: Ledger, today: LocalDate = .today) -> String {
    var lines: [String] = []
    for d in ledger.debts where !d.closed {
        guard let plan = d.plan, let p = ledger.planProgress(d.id, today: today), p.currentIndex != nil else { continue }
        let who = d.direction == .theyOweMe ? "\(d.counterparty)还我" : "我还\(d.counterparty)"
        var line = "  \(who)：第 \(p.paidCount) / \(p.count) 期，还剩 \(p.remainingCount) 期"
        if let n = p.nextDate { line += "；下一期 \(n) 还 \(p.nextAmount.formatted)" + (p.overdue ? "（已过期）" : "") }
        if let f = plan.last?.date { line += "；\(f) 还清" }
        lines.append(line)
    }
    let o = Plans.debtOverview(ledger, today: today)
    var head = "\n\n这个月我要还 \(o.dueThisMonth.formatted)"
    if o.incomingThisMonth.cents > 0 { head += "，该收回 \(o.incomingThisMonth.formatted)" }
    if let all = o.allClear { head += "；照现在的还法 \(all.year) 年 \(all.month) 月全部还清" }
    else if o.undatedCount > 0 { head += "；有 \(o.undatedCount) 笔没约日子，算不出哪天全部还清" }
    if lines.isEmpty { return head + "。还没有排还款计划的欠款（可以用 plan_debt 排）。" }
    return head + "。\n还款计划：\n" + lines.joined(separator: "\n")
}
