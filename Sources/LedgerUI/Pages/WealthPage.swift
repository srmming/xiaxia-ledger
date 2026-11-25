import FinanceCore
import SwiftUI

/// 家底：现在能随便花多少、总存款多少、总存款分在哪几块。（ming 2026-11-23：家底曲线在趋势页，这里主图是「总存款分几块」。）
struct WealthPage: View {
    @Environment(LedgerModel.self) var model
    @State private var viewport = CGSize(width: 1000, height: 800)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 主图卡片有多宽：够宽时几张小卡排一行，不够就两列。
    @State private var heroWidth: CGFloat = 560
    /// 打开页面时那根条长出来、小卡一张张出现。
    @State private var shown = false

    var body: some View {
        Group {
            if model.businessOn && model.side == .business {
                // 生意那边：店里一共多少、店里的账户、两边之间的钱（ming 2026-11-25：账户两边完全分开）。
                BusinessWealth()
            } else if model.ledger.accounts.isEmpty {
                VStack(spacing: Kit.gap) {
                    KitEmptyState(symbol: "building.columns", title: tr("还没有账户"),
                                  message: tr("第一次导入对账单时，AI 会顺手把账户建好。也可以自己加一个。"),
                                  prompt: "帮我在夏夏账本里建一个银行账户，现在余额是 1.000 €", page: "家底")
                    Button { model.sheet = .accounts } label: { Label(tr("自己加一个账户"), systemImage: "plus") }
                        .buttonStyle(.soft)
                }
                .kitCard()
            } else {
                let w = model.wealthBreakdown(model.shownMonth)
                VStack(alignment: .leading, spacing: Kit.gap) {
                    // 夏夏卡放最上面，说有用的：能随便花的钱够过几个月、欠款还不还得上、比 3 个月前多了还是少了。
                    let nudges = Nudges.wealth(w, monthlySpend: model.personalMonthlySpend(), threeMonthsAgo: threeMonthsAgo,
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

    /// 总存款分成的一块：店里要用 / 存着不动 / 要还的 / 能随便花。
    private struct Part: Identifiable {
        var id: String
        var label: String
        var amount: Money
        var color: Color
        var soft: Color
        var sources: [WealthBreakdown.Source] = []
        var isResult = false
        /// 在总存款那根条上占多少（分）。
        var bar: Int64 = 0
    }

    private func parts(_ w: WealthBreakdown) -> [Part] {
        var list: [Part] = []
        // 「店里要用」只在有只给生意账本用的账户时才有；只有个人账本就没有这一块，不猜。
        if w.shop.cents > 0 {
            list.append(Part(id: "shop", label: WealthBreakdown.shopLabel(model.ledger), amount: w.shop, color: .shop, soft: .shopSoft,
                             sources: w.sources.shop, bar: w.shop.cents))
        }
        if w.saved.cents > 0 {
            list.append(Part(id: "saved", label: tr("存着不动"), amount: w.saved, color: .ai, soft: .aiSoft, sources: w.sources.saved, bar: w.saved.cents))
        }
        if w.owed.cents > 0 {
            // 要还的是从手头的钱里出的；手头不够时条上最多画到手头那么多。
            list.append(Part(id: "owed", label: tr("要还的"), amount: w.owed, color: .alert, soft: .alertSoft, sources: w.sources.owed,
                             bar: max(0, min(w.owed.cents, w.liquid.cents))))
        }
        let free = w.spendable
        list.append(Part(id: "free", label: tr("能随便花"), amount: free, color: free.cents < 0 ? .alert : .income,
                         soft: free.cents < 0 ? .alertSoft : .incomeSoft, isResult: true, bar: max(0, free.cents)))
        return list
    }

    /// 主图（ming 2026-11-23：「我需要我一看我就能理解」「也要用总存款」「要好看 直观」）：
    /// 一个大数字「现在能随便花多少、够花几个月」；下面一根粗条是总存款，按颜色切成几块；
    /// 再下面每块一张同色的小卡：店里要用 / 存着不动 / 要还的各是哪几个账户，最后一张绿的就是能随便花的。
    private func heroCard(_ w: WealthBreakdown) -> some View {
        let short = Viewport.isShort(viewport)
        let list = parts(w)
        let spend = model.personalMonthlySpend()
        let free = w.spendable
        let hasShop = model.ledger.books.contains(where: \.isBusiness)
        let sentence: Text = {
            if free.cents < 0 {
                return Text(tr("手头的钱还不够还欠的，差 ")) + em(free.magnitude.rounded, .bad) + Text(tr("。"))
            }
            if let months = w.months(monthlySpend: spend) {
                return Text(tr("够花 ")) + em(tr("\(WealthBreakdown.monthsText(months)) 个月"), .good)
                    + Text(tr("，按\(hasShop ? tr("你自己") : tr("最近"))每月花 \(spend.rounded) 算。"))
            }
            return Text(tr("记满一个月的开销，就能算出够花几个月。"))
        }()
        return VStack(alignment: .leading, spacing: short ? 10 : 16) {
            KeyFigure(label: tr("现在能随便花") + (model.showPrivate ? tr("（含私房钱）") : ""), money: free,
                      color: free.cents < 0 ? .alert : .primary, sentence: sentence,
                      spoken: tr("现在能随便花 \(free.spoken)，总存款 \(w.total.spoken)"))
            if w.total.cents <= 0 && w.owed.cents == 0 {
                Text(tr("账户里还没有钱，记了第一笔这里会画出钱分在哪几块。")).font(.callout).foregroundStyle(Color.fg2)
            } else {
                VStack(alignment: .leading, spacing: short ? 6 : 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(tr("总存款")).font(.callout.weight(.semibold))
                        Text(w.total.ui).font(.kitAmount)
                        Spacer(minLength: 8)
                        Text(model.businessOn ? tr("生活这边的账户加起来") : tr("所有账户里的钱加起来"))
                            .font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(tr("总存款 \(w.total.spoken)，所有账户里的钱加起来"))
                    if w.total.cents > 0 { splitBar(list, short: short) }
                }
                if list.count == 1 {
                    Text(tr("没有要留给店里、存着不动或者要还的钱，总存款都能随便花。")).font(.callout).foregroundStyle(Color.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if short {
                    // 窗口矮：每块只留一行（颜色、名字、多少），一屏放下。
                    VStack(spacing: 4) { ForEach(list) { compactRow($0) } }
                } else {
                    tiles(list)
                }
                if model.businessOn {
                    // 两边加起来的总数，生意那边家底页写的是同一个数。
                    (Text(tr("生活和生意加起来的真家底 ")) + em(model.wealthBreakdown(model.shownMonth, bothSides: true).net.rounded) + Text(tr("（扣掉要还的，加上别人欠你的）。")))
                        .font(.caption).foregroundStyle(Color.fg2)
                }
                if w.owedToMe.cents > 0 {
                    Text(tr("另外别人还欠你 \(w.owedToMe.rounded)，收回来再算进能花的。"))
                        .font(.caption).foregroundStyle(Color.fg2)
                }
            }
        }
        .kitCard(padding: 20)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { heroWidth = $0 }
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.smooth(duration: 0.7)) { shown = true } }
        }
    }

    /// 总存款那根粗条：按颜色切成几块，打开页面时从左往右长出来。
    private func splitBar(_ list: [Part], short: Bool) -> some View {
        let segs = list.filter { $0.bar > 0 }
        let sum = CGFloat(max(1, segs.reduce(Int64(0)) { $0 + $1.bar }))
        let gap: CGFloat = 3
        return GeometryReader { g in
            let usable = max(0, g.size.width - gap * CGFloat(max(0, segs.count - 1)))
            HStack(spacing: gap) {
                ForEach(segs) { p in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(p.color)
                        .frame(width: max(4, usable * CGFloat(p.bar) / sum))
                }
            }
            .frame(width: g.size.width, alignment: .leading)
        }
        .frame(height: short ? 14 : 20)
        .clipShape(Capsule())
        .mask(alignment: .leading) { Rectangle().scaleEffect(x: shown ? 1 : 0.02, anchor: .leading) }
        .accessibilityHidden(true)
    }

    /// 每块一张同色小卡。主栏够宽就排一行，不够就两列；最后一行只剩一张时让它占满。
    private func tiles(_ list: [Part]) -> some View {
        let cols = heroWidth >= 760 ? list.count : 2
        let rows = stride(from: 0, to: list.count, by: cols).map { Array(list[$0..<min($0 + cols, list.count)]) }
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.element.id) { c, p in
                        tile(p)
                            .gridCellColumns(row.count == 1 ? cols : 1)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 8)
                            .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.12 + 0.07 * Double(r * cols + c)), value: shown)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ p: Part) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(p.color).frame(width: 10, height: 10)
                Text((p.isResult ? "= " : "") + p.label).font(.caption.weight(.semibold))
                    .foregroundStyle(p.isResult ? p.color : Color.fg2).lineLimit(1)
            }
            Text((p.isResult ? "" : "\u{2212} ") + p.amount.balance)
                .font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(p.isResult ? p.color : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if p.isResult {
                Text(p.amount.cents < 0 ? tr("手头的钱不够还，先还最快到期的。") : tr("总存款减掉前面几块，剩下的。"))
                    .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            } else {
                // 4 项以内全列出来；再多就列前 3 项，剩下的合成一行。
                let all = p.sources.count <= 4
                VStack(spacing: 2) {
                    ForEach(p.sources.prefix(all ? 4 : 3)) { sourceLine($0.name, $0.amount) }
                    if !all {
                        sourceLine(tr("还有 \(p.sources.count - 3) 项"), p.sources.dropFirst(3).reduce(Money.zero) { $0 + $1.amount })
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if p.isResult { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.color.opacity(0.35), lineWidth: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(p))
        .accessibilityIdentifier("wealth.part.\(p.id)")
    }

    private func sourceLine(_ name: String, _ amount: Money) -> some View {
        let label = Text(name).font(.caption).foregroundStyle(Color.fg2)
        let money = Text(amount.ui).font(.caption).monospacedDigit().foregroundStyle(Color.fg2).lineLimit(1).fixedSize()
        // 一行四张卡时每张很窄：名字和金额一行放不下，就名字占一整行、金额放到下一行靠右，名字不被拆开。
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                label.lineLimit(1).fixedSize()
                Spacer(minLength: 4)
                money
            }
            VStack(alignment: .trailing, spacing: 0) {
                label.lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                money
            }
        }
    }

    private func compactRow(_ p: Part) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(p.color).frame(width: 10, height: 10)
            Text((p.isResult ? "= " : "\u{2212} ") + p.label)
                .font(p.isResult ? .callout.weight(.semibold) : .callout)
                .foregroundStyle(p.isResult ? p.color : .primary).lineLimit(1)
            Spacer(minLength: 8)
            Text(p.amount.balance).font(.kitAmount).foregroundStyle(p.isResult ? p.color : .primary).lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(p))
        .accessibilityIdentifier("wealth.part.\(p.id)")
    }

    private func spoken(_ p: Part) -> String {
        if p.isResult { return tr("等于能随便花 \(p.amount.spoken)") }
        let from = p.sources.prefix(4).map { "\($0.name) \($0.amount.spoken)" }.joined(separator: "，")
        return tr("减掉\(p.label) \(p.amount.spoken)") + (from.isEmpty ? "" : "：\(from)")
    }

    /// 欠款、分期搬去了自己那一页（ming 2026-11-23），这里只留一行合计，点了过去看。
    @ViewBuilder private var debtsCard: some View {
        let o = Plans.obligations(model.lifeLedger, asOf: .today)
        if !o.isEmpty {
            Button { withAnimation(.snappy) { model.section = .debts } } label: {
                HStack(spacing: 12) {
                    XiaIcon(.debt, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("欠款与分期")).font(.callout.weight(.medium))
                        Text(tr("借的钱和分期还欠 \(o.iOwe.rounded) · 别人欠我 \(o.owedToMe.rounded)"))
                            .font(.caption).foregroundStyle(Color.fg2).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
                }
                .contentShape(Rectangle())
                .kitCard()
            }
            .buttonStyle(.pressable)
            .accessibilityHint(tr("打开欠款与分期"))
        }
    }

    /// 账户列表：开着生意模式时只列生活这边的（店里的在生意那边的家底页）。
    private var listedAccounts: [Account] {
        guard model.businessOn else { return model.visibleAccounts }
        let shop = WealthBreakdown.businessAccounts(model.ledger)
        return model.visibleAccounts.filter { !shop.contains($0.id) }
    }

    private var accountsCard: some View {
        let balances = model.balances
        let kinds: [AccountKind] = [.bank, .wallet, .credit, .cash, .savings]
        let hiddenCount = model.ledger.accounts.filter(\.isPrivate).count
        // 账户多（7 个以上）也按矮窗口的排法：不分组写标题、每行收紧，一屏放下。
        let short = Viewport.isShort(viewport) || listedAccounts.count > 6
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: tr("账户")) {
                Button { model.sheet = .accounts } label: { Label(tr("管理"), systemImage: "slider.horizontal.3") }
                    .buttonStyle(.soft)
                    .help(tr("加账户、改名、删除"))
            }
            .padding(.bottom, 6)
            ForEach(kinds, id: \.self) { kind in
                let list = listedAccounts.filter { $0.kind == kind }
                if !list.isEmpty {
                    // 窗口矮：不分组写标题（图标已经看得出是哪种），每行收紧，一屏放下。
                    if !short {
                        Text(kind.label).font(.kitSection).padding(.top, kind == kinds.first { k in listedAccounts.contains { $0.kind == k } } ? 2 : 10)
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
                                            .help(tr("超过一个月没对账，余额可能不准了"))
                                            .accessibilityLabel(tr("超过一个月没对账"))
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
                        .contentShape(Rectangle())
                        .contextMenu { MoveSideButton(account: a) }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if listedAccounts.contains(where: { model.approxBaseText($0.id) != nil }) {
                Text(tr("外币账户按今天的汇率换成\(Currencies.info(model.ledger.baseCurrency).name)，算进总存款。"))
                    .font(.caption).foregroundStyle(Color.fg2).padding(.top, 6)
            }
            if hiddenCount > 0 {
                Divider().padding(.vertical, 6)
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(Color.fg2)
                        .frame(width: 30, height: 30).background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("私房钱 · \(hiddenCount) 个账户")).font(.callout.weight(.medium))
                        Text(model.showPrivate ? tr("现在算进上面的数了") : tr("默认藏起来，不算进上面的数")).font(.caption).foregroundStyle(Color.fg2)
                    }
                    Spacer()
                    Button { withAnimation(.snappy) { model.showPrivate.toggle() } } label: {
                        Label(model.showPrivate ? tr("藏起来") : tr("显示"), systemImage: model.showPrivate ? "eye.slash" : "eye")
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
        if let d = model.ledger.lastStatementDate[a.id], !Viewport.isShort(viewport) { parts.append(tr("对账到 \(d.short)")) }
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
                Text(debt.direction == .theyOweMe ? tr("\(debt.counterparty)欠我") : tr("我欠\(debt.counterparty)")).font(.callout.weight(.medium))
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
        if debt.repaid.cents > 0 { parts.append(tr("已还 \(debt.repaid.rounded)")) }
        // 过期的只说过了几天，短一点，窄窗口也一行放得下（哪天到期在夏夏说里有）。
        if let due = debt.dueDate { parts.append(debt.overdue ? tr("过期 \(max(1, due.days(until: .today))) 天") : tr("\(due.short) 前还")) }
        return parts.isEmpty ? tr("还没还") : parts.joined(separator: " · ")
    }
}
