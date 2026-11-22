import FinanceCore
import SwiftUI

/// 家底：我一共有多少钱？视觉重心是净资产 + 12 个月曲线。
struct WealthPage: View {
    @Environment(LedgerModel.self) var model

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
                Columns(sideWidth: 380, breakpoint: 760) {
                    heroCard
                    XiaxiaSays(page: "wealth", pageName: "家底", sentence: xiaxia,
                               question: "看看我的家底：钱放得合不合理？月底的钱够不够还信用卡？")
                    debtsCard
                } side: {
                    accountsCard
                }
            }
        }
        .kitPage()
    }

    private var heroCard: some View {
        let months = Reports.months(endingAt: model.shownMonth, count: 13)
        let series = model.netWorthSeries(months: months)
        let now = series.last?.value ?? model.totalBalance
        let three = series.count > 3 && series[series.count - 4].value.cents != 0 ? now - series[series.count - 4].value : nil
        // 一年前还没开始记账（那时是 0）就不比，否则「一年多了」就等于全部家底。
        let year = series.count > 12 && series[0].value.cents != 0 ? now - series[0].value : nil
        var sentence = Text("")
        if let three {
            sentence = Text("比 3 个月前\(three.isExpense ? "少" : "多")了 ") + em(three.magnitude.rounded, three.isExpense ? .bad : .good)
            if let year { sentence = sentence + Text("，一年\(year.isExpense ? "少" : "多")了 \(year.magnitude.rounded)。") }
            else { sentence = sentence + Text("。") }
        } else {
            sentence = Text("记的月份多了，这里会告诉你比以前多了还是少了。")
        }
        let label = model.showPrivate ? "净资产（所有账户加起来，减掉信用卡，含私房钱）" : "净资产（所有账户加起来，减掉信用卡）"
        return VStack(alignment: .leading, spacing: 16) {
            KeyFigure(label: label, money: now, color: now.isExpense ? .alert : .primary, sentence: sentence,
                      spoken: "净资产 \(now.spoken)")
            NetWorthChart(points: Array(series.suffix(12)))
        }
        .kitCard(padding: 20)
    }

    /// 夏夏先说的一句：比 3 个月前多了还是少了；信用卡欠着的提一句。
    private var xiaxia: String {
        let months = Reports.months(endingAt: model.shownMonth, count: 4)
        let series = model.netWorthSeries(months: months)
        let now = series.last?.value ?? model.totalBalance
        let owed = model.visibleAccounts.filter { $0.kind == .credit }.reduce(Money.zero) { sum, a in sum + (model.balances[a.id] ?? .zero) }
        let card = owed.isExpense ? "信用卡还欠着 \(owed.magnitude.rounded)。" : ""
        guard series.count == 4, series[0].value.cents != 0 else {
            return model.voiced("现在一共有 \(now.rounded)。" + card, .neutral)
        }
        let diff = now - series[0].value
        return diff.isExpense ? model.voiced("家底比 3 个月前少了 \(diff.magnitude.rounded)。" + card, .bad)
            : model.voiced("家底比 3 个月前多了 \(diff.rounded)。" + card, .good)
    }

    @ViewBuilder private var debtsCard: some View {
        let debts = Plans.debts(model.ledger, today: .today)
        if !debts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader("借款往来").padding(.bottom, 6)
                ForEach(debts, id: \.id) { d in
                    DebtRow(debt: d)
                    if d.id != debts.last?.id { Divider().padding(.leading, 42) }
                }
            }
            .kitCard()
        }
    }

    private var accountsCard: some View {
        let balances = model.balances
        let kinds: [AccountKind] = [.bank, .wallet, .credit, .cash, .savings]
        let hiddenCount = model.ledger.accounts.filter(\.isPrivate).count
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
                    Text(kind.label).font(.kitSection).padding(.top, kind == kinds.first { k in model.visibleAccounts.contains { $0.kind == k } } ? 2 : 10)
                        .padding(.bottom, 4)
                    ForEach(list) { a in
                        let b = balances[a.id] ?? .zero
                        HStack(spacing: 12) {
                            AccountIcon(kind: a.kind, isPrivate: a.isPrivate, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(.callout.weight(.medium)).lineLimit(1)
                                Text(subtitle(a)).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
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
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if model.visibleAccounts.contains(where: { model.approxBaseText($0.id) != nil }) {
                Text("外币账户按今天的汇率换成\(Currencies.info(model.ledger.baseCurrency).name)，算进净资产。")
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
        if let d = model.ledger.lastStatementDate[a.id] { parts.append("对账到 \(d.short)") }
        return parts.isEmpty ? a.kind.label : parts.joined(separator: " · ")
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
            Text(debt.outstanding.formatted).font(.kitAmount)
                .foregroundStyle(debt.direction == .theyOweMe ? Color.income : .primary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if debt.repaid.cents > 0 { parts.append("已还 \(debt.repaid.rounded)") }
        if let due = debt.dueDate { parts.append(debt.overdue ? "\(due.short) 就该还了" : "\(due.short) 前还") }
        return parts.isEmpty ? "还没还" : parts.joined(separator: " · ")
    }
}
