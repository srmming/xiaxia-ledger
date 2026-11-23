import FinanceCore
import SwiftUI

/// 家底：我的钱现在在哪、真正属于我的有多少。（ming 2026-11-23：家底曲线挪到趋势页，这里主图是分段长条。）
struct WealthPage: View {
    @Environment(LedgerModel.self) var model
    @State private var viewport = CGSize(width: 1000, height: 800)

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
                    // 夏夏卡放最上面，说有用的：能随时用的钱够过几个月、欠款还不还得上、比 3 个月前多了还是少了。
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

    private struct Part: Identifiable {
        var name: String
        var hint: String
        var amount: Money
        var color: Color
        var minus = false
        var id: String { name }
    }

    /// 主图：真家底的大数字 + 一根分段长条，一眼看出钱在哪。
    private func heroCard(_ w: WealthBreakdown) -> some View {
        let short = Viewport.isShort(viewport)
        let parts = [
            Part(name: "能随时用的", hint: w.earmarked.cents > 0 ? "银行卡、现金、钱包（不含划给目标的 \(w.earmarked.rounded)）" : "银行卡、现金、钱包", amount: w.liquid, color: .income),
            Part(name: "存着的", hint: "存款、存钱目标里的钱", amount: w.saved, color: .ai),
            Part(name: "店里的", hint: "只在生意账本里用的账户", amount: w.shop, color: .warn),
            Part(name: "别人欠我的", hint: "借出去还没还的", amount: w.owedToMe, color: .fg3),
            Part(name: "欠款", hint: "信用卡、借的钱、分期没还完的", amount: w.owed, color: .alert, minus: true),
        ].filter { $0.amount.cents > 0 }
        let whole = Double(max(1, parts.reduce(Int64(0)) { $0 + $1.amount.cents }))
        let label = "真家底（所有账户，减掉信用卡和欠款，加上别人欠我的" + (model.showPrivate ? "，含私房钱）" : "）")
        let sentence = w.owed.cents > 0
            ? Text("一共有 ") + em(w.assets.rounded) + Text("，减掉欠着的 ") + em(w.owed.rounded, .bad) + Text("，真正属于你的是这么多。")
            : Text("没有欠款，这些都是你的。")
        return VStack(alignment: .leading, spacing: short ? 12 : 16) {
            KeyFigure(label: label, money: w.net, color: w.net.isExpense ? .alert : .primary, sentence: sentence,
                      spoken: "真家底 \(w.net.spoken)")
            if parts.isEmpty {
                Text("账户里还没有钱，记了第一笔这里会画出钱在哪。").font(.callout).foregroundStyle(Color.fg2)
            } else {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(parts) { p in
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(p.color)
                                .frame(width: max(4, (g.size.width - CGFloat(parts.count - 1) * 2) * Double(p.amount.cents) / whole))
                        }
                    }
                }
                .frame(height: short ? 16 : 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(parts) { p in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(p.color).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.callout.weight(.medium))
                                if !short, parts.count <= 4 || p.id == "能随时用的" { Text(p.hint).font(.caption).foregroundStyle(Color.fg2).lineLimit(1) }
                            }
                            Spacer(minLength: 8)
                            Text("\(Int((Double(p.amount.cents) / whole * 100).rounded()))%").font(.caption).foregroundStyle(Color.fg2).monospacedDigit()
                            Text((p.minus ? "\u{2212}" : "") + p.amount.ui).font(.kitAmount)
                                .foregroundStyle(p.minus ? Color.alert : .primary)
                                .lineLimit(1).fixedSize()
                                .frame(minWidth: 96, alignment: .trailing)
                        }
                        .padding(.vertical, short ? 3 : parts.count > 4 ? 4 : 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(p.name)\(p.minus ? "，要减掉" : "") \(p.amount.spoken)")
                        if p.id != parts.last?.id { Divider() }
                    }
                }
            }
        }
        .kitCard(padding: 20)
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
                        Text("我还欠 \(o.iOwe.rounded) · 别人欠我 \(o.owedToMe.rounded) · 已经算进上面的真家底")
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
                                Text(a.name).font(.callout.weight(.medium)).lineLimit(1)
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
                Text("外币账户按今天的汇率换成\(Currencies.info(model.ledger.baseCurrency).name)，算进真家底。")
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
