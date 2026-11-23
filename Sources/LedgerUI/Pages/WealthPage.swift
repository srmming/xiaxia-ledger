import FinanceCore
import SwiftUI

/// 家底：现在能随便花多少、总存款多少、是怎么一步步算出来的。（ming 2026-11-23：家底曲线在趋势页，这里主图是下楼梯图。）
struct WealthPage: View {
    @Environment(LedgerModel.self) var model
    @State private var viewport = CGSize(width: 1000, height: 800)
    /// 下楼梯图里点开的那一步（一次只开一步，一屏放得下）。
    @State private var expanded: String?

    var body: some View {
        Group {
            if model.ledger.accounts.isEmpty {
                VStack(spacing: Kit.gap) {
                    KitEmptyState(symbol: "building.columns", title: "还没有账户",
                                  message: "第一次导入对账单时，AI 会顺手把账户建好。也可以自己加一个。",
                                  prompt: "帮我在夏夏账本里建一个银行账户，现在余额是 1.000 €", page: "家底")
                    Button { model.sheet = .accounts } label: { Label("自己加一个账户", systemImage: "plus") }
                        .buttonStyle(.soft)
                }
                .kitCard()
            } else {
                let w = model.wealthBreakdown(model.shownMonth)
                VStack(alignment: .leading, spacing: Kit.gap) {
                    // 夏夏卡放最上面，说有用的：能随便花的钱够过几个月、欠款还不还得上、比 3 个月前多了还是少了。
                    let nudges = Nudges.wealth(w, monthlySpend: model.averageMonthlySpend(), threeMonthsAgo: threeMonthsAgo,
                                               currency: model.ledger.baseCurrency)
                    let insights = [model.ledger.insight(forPage: "wealth", month: model.shownMonth, bookID: nil)].compactMap { $0 }
                    XiaxiaCards(nudges: nudges, insights: insights, page: "家底")
                    Columns(sideWidth: 380) {
                        heroCard(w)
                        // 窗口矮时不放这一行（侧栏里就有「欠款与分期」），一屏放下。
                        if !Viewport.isShort(viewport) { debtsCard }
                    } side: {
                        accountsCard
                    }
                }
            }
        }
        .kitPage()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
    }

    /// 3 个月前的真家底；那时还没开始记账（是 0）就不比。
    private var threeMonthsAgo: Money? {
        let months = Reports.months(endingAt: model.shownMonth, count: 4)
        guard let first = model.recordedMonths.min(), first <= months[0] else { return nil }
        let v = model.netWorthSeries(months: months).first?.value
        return v?.cents == 0 ? nil : v
    }

    /// 下楼梯图的一步。
    private struct Step: Identifiable {
        enum Kind { case total, minus, result }
        var id: String
        var label: String
        var amount: Money
        var kind: Kind
        var color: Color
        var sources: [WealthBreakdown.Source] = []
        /// 这一步之前、之后还剩多少（画条用）。
        var before: Int64 = 0
        var after: Int64 = 0
    }

    private func steps(_ w: WealthBreakdown) -> [Step] {
        var list = [Step(id: "total", label: "一共有（总存款）", amount: w.total, kind: .total, color: .fg2, sources: w.sources.total)]
        // 「店里要用」只在有只给生意账本用的账户时才有；只有个人账本就没有这一步，不猜。
        if w.shop.cents > 0 {
            list.append(Step(id: "shop", label: WealthBreakdown.shopLabel(model.ledger), amount: w.shop, kind: .minus, color: .warn, sources: w.sources.shop))
        }
        if w.saved.cents > 0 {
            list.append(Step(id: "saved", label: "存着不动", amount: w.saved, kind: .minus, color: .ai, sources: w.sources.saved))
        }
        if w.owed.cents > 0 {
            list.append(Step(id: "owed", label: "要还的", amount: w.owed, kind: .minus, color: .alert, sources: w.sources.owed))
        }
        list.append(Step(id: "free", label: "能随便花", amount: w.spendable, kind: .result, color: .income))
        var left = w.total.cents
        for k in list.indices {
            switch list[k].kind {
            case .total: list[k].before = left; list[k].after = left
            case .minus: list[k].before = left; left -= list[k].amount.cents; list[k].after = left
            case .result: list[k].before = left; list[k].after = left
            }
        }
        return list
    }

    /// 主图（ming 2026-11-23：「我需要我一看我就能理解」「也要用总存款」）：
    /// 一个大数字「现在能随便花多少、够花几个月」，下面一张下楼梯图：一共有 − 店里要用 − 存着不动 − 要还的 = 能随便花。点每一步看是哪几个账户。
    private func heroCard(_ w: WealthBreakdown) -> some View {
        let short = Viewport.isShort(viewport)
        let list = steps(w)
        let spend = model.averageMonthlySpend()
        let free = w.spendable
        let sentence: Text = {
            if free.cents < 0 {
                return Text("手头的钱还不够还欠的，差 ") + em(free.magnitude.rounded, .bad) + Text("。总存款 ") + em(w.total.rounded) + Text("。")
            }
            if let months = w.months(monthlySpend: spend) {
                return Text("够花 ") + em("\(WealthBreakdown.monthsText(months)) 个月") + Text("（最近每月花 \(spend.rounded)）。总存款 ") + em(w.total.rounded) + Text("。")
            }
            return Text("总存款 ") + em(w.total.rounded) + Text("。记满一个月的开销，就能算出够花几个月。")
        }()
        return VStack(alignment: .leading, spacing: short ? 10 : 14) {
            KeyFigure(label: "现在能随便花" + (model.showPrivate ? "（含私房钱）" : ""), money: free,
                      color: free.cents < 0 ? .alert : .primary, sentence: sentence,
                      spoken: "现在能随便花 \(free.spoken)，总存款 \(w.total.spoken)")
            if w.total.cents <= 0 && w.owed.cents == 0 {
                Text("账户里还没有钱，记了第一笔这里会画出钱是怎么一步步算出来的。").font(.callout).foregroundStyle(Color.fg2)
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { step in
                        stepRow(step, whole: max(1, w.total.cents), short: short)
                        if step.id != list.last?.id { Divider().opacity(0.5) }
                    }
                }
                if w.owedToMe.cents > 0 {
                    Text("另外别人还欠你 \(w.owedToMe.rounded)，收回来再算进能花的。")
                        .font(.caption).foregroundStyle(Color.fg2)
                }
            }
        }
        .kitCard(padding: 20)
    }

    private func stepRow(_ step: Step, whole: Int64, short: Bool) -> some View {
        let open = expanded == step.id
        let canOpen = !step.sources.isEmpty
        let sign = step.kind == .minus ? "\u{2212} " : step.kind == .result ? "= " : ""
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard canOpen else { return }
                withAnimation(.snappy) { expanded = open ? nil : step.id }
            } label: {
                VStack(alignment: .leading, spacing: short ? 3 : 5) {
                    HStack(spacing: 8) {
                        Text(sign + step.label)
                            .font(step.kind == .minus ? .callout : .callout.weight(.semibold))
                            .foregroundStyle(step.kind == .result ? Color.income : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text((step.kind == .minus ? "\u{2212}" : "") + step.amount.ui).font(.kitAmount)
                            .foregroundStyle(step.kind == .result ? (step.amount.cents < 0 ? Color.alert : Color.income) : .primary)
                            .lineLimit(1).fixedSize()
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Color.fg3)
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .opacity(canOpen ? 1 : 0)
                    }
                    GeometryReader { g in
                        let w = g.size.width
                        let x0 = w * CGFloat(max(0, min(step.after, whole))) / CGFloat(whole)
                        let x1 = w * CGFloat(max(0, min(step.before, whole))) / CGFloat(whole)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.sunken)
                            switch step.kind {
                            case .total:
                                Capsule().fill(step.color).frame(width: max(4, x1))
                            case .minus:
                                // 还剩下的画淡的，这一步拿走的那一截画深的：一截一截往左退，像下楼梯。
                                Capsule().fill(Color.fg3.opacity(0.35)).frame(width: max(0, x0))
                                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(step.color)
                                    .frame(width: max(4, x1 - x0)).offset(x: max(0, min(x0, w - 4)))
                            case .result:
                                Capsule().fill(step.color).frame(width: step.amount.cents > 0 ? max(4, x1) : 0)
                            }
                        }
                    }
                    .frame(height: short ? 6 : 8)
                    .accessibilityHidden(true)
                }
                .padding(.vertical, short ? 5 : 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stepSpoken(step))
            .accessibilityHint(canOpen ? (open ? "收起来源" : "展开看是哪几个账户") : "")
            .accessibilityIdentifier("wealth.step.\(step.id)")
            if open {
                VStack(spacing: 2) {
                    ForEach(step.sources.prefix(6)) { src in
                        HStack(spacing: 8) {
                            Circle().fill(step.color).frame(width: 5, height: 5)
                            Text(src.name).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(src.amount.ui).font(.caption).monospacedDigit().foregroundStyle(Color.fg2)
                        }
                    }
                    if step.sources.count > 6 {
                        let rest = step.sources.dropFirst(6).reduce(Money.zero) { $0 + $1.amount }
                        HStack(spacing: 8) {
                            Circle().fill(step.color).frame(width: 5, height: 5)
                            Text("还有 \(step.sources.count - 6) 项").font(.caption).foregroundStyle(Color.fg2)
                            Spacer(minLength: 8)
                            Text(rest.ui).font(.caption).monospacedDigit().foregroundStyle(Color.fg2)
                        }
                    }
                }
                .padding(.leading, 4).padding(.trailing, 20).padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }

    private func stepSpoken(_ step: Step) -> String {
        switch step.kind {
        case .total: "一共有，总存款 \(step.amount.spoken)"
        case .minus: "减掉\(step.label) \(step.amount.spoken)"
        case .result: "等于能随便花 \(step.amount.spoken)"
        }
    }

    /// 欠款、分期搬去了自己那一页（ming 2026-11-23），这里只留一行合计，点了过去看。
    @ViewBuilder private var debtsCard: some View {
        let o = Plans.obligations(model.ledger, asOf: .today)
        if !o.isEmpty {
            Button { withAnimation(.snappy) { model.section = .debts } } label: {
                HStack(spacing: 12) {
                    XiaIcon(.debt, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("欠款与分期").font(.callout.weight(.medium))
                        Text("我还欠 \(o.iOwe.rounded) · 别人欠我 \(o.owedToMe.rounded) · 要还的已经从上面减掉了")
                            .font(.caption).foregroundStyle(Color.fg2).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
                }
                .contentShape(Rectangle())
                .kitCard()
            }
            .buttonStyle(.pressable)
            .accessibilityHint("打开欠款与分期")
        }
    }

    private var accountsCard: some View {
        let balances = model.balances
        let kinds: [AccountKind] = [.bank, .wallet, .credit, .cash, .savings]
        let hiddenCount = model.ledger.accounts.filter(\.isPrivate).count
        // 账户多（7 个以上）也按矮窗口的排法：不分组写标题、每行收紧，一屏放下。
        let short = Viewport.isShort(viewport) || model.visibleAccounts.count > 6
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "账户") {
                Button { model.sheet = .accounts } label: { Label("管理", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.soft)
                    .help("加账户、改名、删除")
            }
            .padding(.bottom, 6)
            ForEach(kinds, id: \.self) { kind in
                let list = model.visibleAccounts.filter { $0.kind == kind }
                if !list.isEmpty {
                    // 窗口矮：不分组写标题（图标已经看得出是哪种），每行收紧，一屏放下。
                    if !short {
                        Text(kind.label).font(.kitSection).padding(.top, kind == kinds.first { k in model.visibleAccounts.contains { $0.kind == k } } ? 2 : 10)
                            .padding(.bottom, 4)
                    }
                    ForEach(list) { a in
                        let b = balances[a.id] ?? .zero
                        HStack(spacing: 12) {
                            AccountIcon(kind: a.kind, isPrivate: a.isPrivate, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(a.name).font(.callout.weight(.medium)).lineLimit(1)
                                    // 超过 35 天没对账：一个小黄点提醒，数可能不准了。
                                    if stale(a) {
                                        Circle().fill(Color.warn).frame(width: 6, height: 6)
                                            .help("超过一个月没对账，余额可能不准了")
                                            .accessibilityLabel("超过一个月没对账")
                                    }
                                }
                                let sub = subtitle(a)
                                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Color.fg2).lineLimit(1) }
                            }
                            Spacer()
                            if let approx = model.approxBaseText(a.id) {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(model.balanceText(a.id)).font(.kitAmount).foregroundStyle(b.isExpense ? Color.alert : .primary)
                                    Text(approx).font(.caption2).foregroundStyle(Color.fg2).monospacedDigit()
                                }
                            } else {
                                Text(b.balance).font(.kitAmount).foregroundStyle(b.isExpense ? Color.alert : .primary)
                            }
                        }
                        .padding(.vertical, short ? 2 : 6)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if model.visibleAccounts.contains(where: { model.approxBaseText($0.id) != nil }) {
                Text("外币账户按今天的汇率换成\(Currencies.info(model.ledger.baseCurrency).name)，算进总存款。")
                    .font(.caption).foregroundStyle(Color.fg2).padding(.top, 6)
            }
            if hiddenCount > 0 {
                Divider().padding(.vertical, 6)
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(Color.fg2)
                        .frame(width: 30, height: 30).background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("私房钱 · \(hiddenCount) 个账户").font(.callout.weight(.medium))
                        Text(model.showPrivate ? "现在算进上面的数了" : "默认藏起来，不算进上面的数").font(.caption).foregroundStyle(Color.fg2)
                    }
                    Spacer()
                    Button { withAnimation(.snappy) { model.showPrivate.toggle() } } label: {
                        Label(model.showPrivate ? "藏起来" : "显示", systemImage: model.showPrivate ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.soft)
                }
            }
        }
        .kitCard()
    }

    /// 对过账、但上次对账已经是 35 天前的账户。
    private func stale(_ a: Account) -> Bool {
        guard let d = model.ledger.lastStatementDate[a.id] else { return false }
        return d.days(until: .today) > 35
    }

    private func subtitle(_ a: Account) -> String {
        let books = Set(model.ledger.transactions.filter { $0.accountID == a.id && $0.flow == nil }.compactMap(\.bookID))
        var parts: [String] = []
        // 只在一个账本里用就写账本名，几个账本混用就都写上，每个账户都是同一种写法。
        if !books.isEmpty { parts.append(books.sorted().map { model.bookName($0) }.joined(separator: " + ")) }
        if let i = a.institution, i != a.name { parts.append(i) }
        if let d = model.ledger.lastStatementDate[a.id], !Viewport.isShort(viewport) { parts.append("对账到 \(d.short)") }
        // 什么都没有时写账户类型；窗口够高时上面已经有类型的小标题，或者名字本身就是类型（「银行卡」），就不再写一遍。
        if parts.isEmpty { return (Viewport.isShort(viewport) || model.visibleAccounts.count > 6) && a.kind.label != a.name ? a.kind.label : "" }
        return parts.joined(separator: " · ")
    }
}

/// 一笔借款往来：谁欠谁、还了多少。
struct DebtRow: View {
    let debt: DebtStatus
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: debt.direction == .theyOweMe ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(debt.direction == .theyOweMe ? Color.income : Color.warn)
                .frame(width: 30, height: 30)
                .background((debt.direction == .theyOweMe ? Color.incomeSoft : Color.warnSoft), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.direction == .theyOweMe ? "\(debt.counterparty)欠我" : "我欠\(debt.counterparty)").font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(debt.overdue ? Color.alert : Color.fg2)
            }
            Spacer()
            Text(debt.outstanding.ui).font(.kitAmount)
                .foregroundStyle(debt.direction == .theyOweMe ? Color.income : .primary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if debt.repaid.cents > 0 { parts.append("已还 \(debt.repaid.rounded)") }
        // 过期的只说过了几天，短一点，窄窗口也一行放得下（哪天到期在夏夏说里有）。
        if let due = debt.dueDate { parts.append(debt.overdue ? "过期 \(max(1, due.days(until: .today))) 天" : "\(due.short) 前还") }
        return parts.isEmpty ? "还没还" : parts.joined(separator: " · ")
    }
}
