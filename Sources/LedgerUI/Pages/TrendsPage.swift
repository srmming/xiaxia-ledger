import FinanceCore
import SwiftUI

/// 预测（ming 2026-11-25 改版，替换原来的图表）：每张卡一个大数字 + 一句大白话，不画图。
/// 生活：月底大概花、下个月要付、钱还能撑几个月。生意：这个月大概收、下个月店里要付、月底账户大概剩。
/// 全是本机用简单算术算的（FinanceCore/Outlook.swift），不靠 AI。数据不到一个月就不出卡。
/// 认出来像每月固定要付的，最上面问一次「算不算固定开销」。
struct TrendsPage: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var phone: Bool { sizeClass == .compact }
    private var shop: Bool { model.side == .business }

    var body: some View {
        let guesses = model.fixedGuessesHere()
        let biz = shop ? model.shopOutlook() : nil
        let life = shop ? nil : model.lifeOutlook()
        let cards = biz.map(shopCards) ?? life.map(lifeCards)
        let due = biz?.next ?? life?.next
        VStack(alignment: .leading, spacing: Kit.gap) {
            if !guesses.isEmpty { FixedGuessCard(guesses: guesses) }
            if let cards {
                if phone {
                    VStack(spacing: Kit.gap) { ForEach(cards) { OutlookCard(item: $0) } }
                } else {
                    HStack(alignment: .top, spacing: Kit.gap) { ForEach(cards) { OutlookCard(item: $0) } }
                    if let due, !due.isEmpty {
                        NextMonthDueCard(due: due, shop: shop)
                    }
                }
                Label(tr("都是按你记的账用加减乘除算的，没有用 AI。记得越全越准。"), systemImage: "function")
                    .font(.caption).foregroundStyle(Color.fg3)
            } else {
                KitEmptyState(symbol: "chart.line.uptrend.xyaxis", title: tr("记满一个月就能算"),
                              message: shop ? tr("店里有一整个月的进出，这里就能估出这个月大概收多少、月底账户大概剩多少。")
                                            : tr("有一整个月的进出，这里就能算出月底大概花多少、下个月要付多少、钱还能撑几个月。"),
                              prompt: "帮我把上个月的银行对账单导进夏夏账本", page: "趋势")
                    .kitCard()
            }
        }
        .kitPage()
    }

    // MARK: 生活三张

    private func lifeCards(_ o: Outlook.Life) -> [OutlookItem] {
        var out: [OutlookItem] = []
        let fixedPart = o.fixedLeft.cents > 0 ? tr("，还有 \(o.fixedLeft.rounded) 固定的没付") : ""
        out.append(OutlookItem(id: "monthEnd", symbol: "calendar", title: tr("\(o.today.month) 月底大概花"),
                               value: o.monthEnd.rounded,
                               sentence: tr("已经花了 \(o.spentSoFar.rounded)\(fixedPart)，剩下 \(o.daysLeft) 天按平时每天 \(o.dailyAverage.rounded) 算。"),
                               spoken: tr("\(o.today.month) 月底大概一共花 \(o.monthEnd.spoken)")))
        out.append(dueItem(o.next, title: tr("下个月要付")))
        if let r = o.runway {
            let months = r < 0 ? 0 : r
            let value = months >= 24 ? tr("两年以上") : tr("\(WealthBreakdown.monthsText(months)) 个月")
            out.append(OutlookItem(id: "runway", symbol: "hourglass", title: tr("钱还能撑"), value: value,
                                   sentence: tr("现在能随便花 \(o.balance.rounded)，平时每月花 \(o.monthlySpend.rounded)。"),
                                   spoken: tr("现在的钱还能撑 \(value)"), tone: months < 2 ? .bad : .plain))
        }
        return out
    }

    // MARK: 生意三张

    private func shopCards(_ o: Outlook.Business) -> [OutlookItem] {
        [
            OutlookItem(id: "income", symbol: "chart.bar.fill", title: tr("这个月大概收"), value: o.monthIncome.rounded,
                        sentence: tr("已经收了 \(o.received.rounded)，剩下的日子按过去 \(o.weeks) 周每个星期几的平均估还能收 \(o.estimateRest.rounded)。"),
                        spoken: tr("这个月大概收 \(o.monthIncome.spoken)")),
            dueItem(o.next, title: tr("下个月店里要付")),
            OutlookItem(id: "end", symbol: "building.columns", title: tr("月底账户大概剩"), value: o.endBalance.rounded,
                        sentence: tr("现在 \(o.balance.rounded)，加上还会收的 \(o.estimateRest.rounded)，减掉还没付的固定开销 \(o.fixedLeft.rounded) 和剩下几天平时的开销 \(o.usualRest.rounded)。"),
                        spoken: tr("月底店里账户大概剩 \(o.endBalance.spoken)"), tone: o.endBalance.cents < 0 ? .bad : .plain),
        ]
    }

    private func dueItem(_ d: Outlook.Due, title: String) -> OutlookItem {
        let fixed = d.fixed.isEmpty ? tr("没有固定要付的") : tr("固定的 \(d.fixedTotal.rounded)（\(d.fixed.count) 样）")
        let variable = d.variable.isEmpty ? "" : tr("，平时的吃穿用度大概 \(d.variableTotal.rounded)")
        return OutlookItem(id: "next", symbol: "tray.full", title: title, value: d.total.rounded,
                           sentence: fixed + variable + tr("。"), spoken: tr("\(title) \(d.total.spoken)"))
    }
}

struct OutlookItem: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let value: String
    let sentence: String
    let spoken: String
    var tone: Tone = .plain
}

/// 一张预测卡：标题、一个大数字、一句话。
struct OutlookCard: View {
    let item: OutlookItem
    @Environment(LedgerModel.self) var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.title, systemImage: item.symbol).font(.callout.weight(.medium)).foregroundStyle(Color.fg2)
            Text(item.value)
                .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(item.tone == .bad ? Color.alert : (model.side == .business ? Color.shop : Color.primary))
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(item.sentence).font(.callout).foregroundStyle(Color.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .kitCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.spoken + "。" + item.sentence)
    }
}

/// 下个月要付：每一样、多少钱，最后合计。固定的一块，平时会变的一块（按最近 3 个月平均）。
/// 家底页（两边）和预测页都用。
struct NextMonthDueCard: View {
    let due: Outlook.Due
    var shop = false
    var maxRows = 6
    /// 家底页用：「平时的」只给一行合计，不列明细，一屏放下。
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: shop ? tr("下个月店里要付") : tr("下个月要付")) {
                Text(due.total.rounded).font(.kitAmount).monospacedDigit()
            }
            // 宽的时候两块并排，窄（侧栏里）就上下放。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { blocks }.frame(minWidth: 520)
                VStack(alignment: .leading, spacing: 12) { blocks }
            }
        }
        .kitCard()
    }

    @ViewBuilder private var blocks: some View {
        block(tr("固定的"), due.fixed, total: due.fixedTotal, empty: tr("没有登记的固定开销"))
        if !due.variable.isEmpty {
            if compact {
                block(tr("平时的（最近 3 个月平均）"), [], total: due.variableTotal,
                      empty: due.variable.prefix(3).map { trKey($0.name) }.joined(separator: tr("、")) + (due.variable.count > 3 ? tr("等") : ""))
            } else {
                block(tr("平时的（最近 3 个月平均）"), due.variable, total: due.variableTotal, empty: "")
            }
        }
    }

    private func block(_ title: String, _ lines: [Outlook.Line], total: Money, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.fg2)
            if lines.isEmpty {
                Text(empty).font(.callout).foregroundStyle(Color.fg3)
            }
            ForEach(lines.prefix(maxRows)) { l in
                HStack(spacing: 8) {
                    Text(l.date.map { tr("\($0.day) 号") } ?? "").font(.caption).foregroundStyle(Color.fg3)
                        .frame(width: 34, alignment: .leading)
                    Text(trKey(l.name)).font(.callout).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(l.amount.rounded).font(.callout).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            if lines.count > maxRows {
                let rest = lines.dropFirst(maxRows).reduce(Money.zero) { $0 + $1.amount }
                HStack {
                    Text(tr("还有 \(lines.count - maxRows) 样")).font(.caption).foregroundStyle(Color.fg2)
                    Spacer()
                    Text(rest.rounded).font(.caption).monospacedDigit().foregroundStyle(Color.fg2)
                }
            }
            Divider()
            HStack {
                Text(tr("合计")).font(.callout.weight(.semibold))
                Spacer()
                Text(total.rounded).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 认出来像每月固定要付的：问一次「算不算固定开销」。算 → 加进固定开销；不算 → 以后不再问。都能撤销。
struct FixedGuessCard: View {
    let guesses: [Outlook.FixedGuess]
    @Environment(LedgerModel.self) var model
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(guesses.count == 1 ? tr("这一样像是每个月固定要付的，算进固定开销吗？") : tr("这几样像是每个月固定要付的，算进固定开销吗？"))
                .font(.callout.weight(.semibold))
            Text(tr("没点之前，下面先按「算」估。点「不算」就不再问，数字也会跟着变。"))
                .font(.caption).foregroundStyle(Color.fg2)
            ForEach(guesses.prefix(3)) { g in
                HStack(spacing: 10) {
                    CategoryIcon(category: g.category, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(tr("连着 3 个月，每月 \(g.day) 号左右 · \(trKey(g.category))")).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(g.amount.rounded).font(.callout.weight(.semibold)).monospacedDigit()
                    Button(tr("不算")) { reject(g) }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button(tr("算")) { accept(g) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .tint(model.side == .business ? Color.shop : Color.brand)
                }
                .accessibilityElement(children: .contain)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Color.alert) }
        }
        .kitCard()
    }

    private func accept(_ g: Outlook.FixedGuess) {
        let book = g.bookID ?? model.ledger.books.first { !$0.isBusiness }?.id
        do {
            _ = try model.edit {
                try $0.addFixedCost(name: g.name, amount: g.amount, day: g.day, accountID: g.accountID, category: g.category,
                                    bookID: book, author: model.author)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func reject(_ g: Outlook.FixedGuess) {
        do { _ = try model.edit { $0.markNotFixed(g.key, name: g.name, author: model.author) } }
        catch { self.error = error.localizedDescription }
    }
}
