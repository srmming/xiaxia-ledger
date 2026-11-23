import FinanceCore
import SwiftUI

/// 欠款与分期：我一共欠多少、什么时候能还清？（ming 2026-11-23 从「计划」里拆出来单独一页，同一天又加了「欠款改分期」。）
/// 最上面夏夏说一句（别人欠的到期没还就俏皮催一下）；顶上三个数：我欠的、欠我的、本月要还多少，下面一条「还清时间线」；
/// 再往下左边「我欠的」（分期 + 借来的），右边「欠我的」。本月要还的排最前，快到期的标红。这些都已经算进家底。
struct DebtsPage: View {
    @Environment(LedgerModel.self) var model
    /// iPhone 的「计划」标签里也用这一页，那里外面已经有滚动了。
    var embedded = false
    @State private var viewport = CGSize(width: 1000, height: 800)
    private var short: Bool { Viewport.isShort(viewport) }

    var body: some View {
        if embedded { content } else {
            content.kitPage()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        }
    }

    @ViewBuilder private var content: some View {
        let installments = filteredInstallments
        let debts = filteredDebts
        if installments.isEmpty && debts.isEmpty {
            VStack(spacing: Kit.gap) {
                VStack(spacing: 12) {
                    KitEmptyState(symbol: "arrow.left.arrow.right", title: tr("没有欠款，也没有分期"),
                                  message: tr("借钱给别人、跟别人借钱、分期买东西，登记一下就会算进家底。欠款还能排成每月还多少的计划，还到哪一期、哪个月还清都看得清。"),
                                  prompt: "帮我记一笔欠款：朋友借了我 300 €，下个月还", page: "欠款与分期")
                    addButtons
                }
                .kitCard()
                AskAICard(title: tr("跟夏夏说一句也能记"), note: nil, page: "欠款与分期", prompts: model.prompts(for: .debts))
            }
        } else {
            let lines = debtLines(installments: installments, debts: debts)
            VStack(alignment: .leading, spacing: Kit.gap) {
                xiaxiaCard(installments: installments, debts: debts)
                totalsCard()
                Columns(sideWidth: 360, breakpoint: 640, sideRatio: 0.42) {
                    iOweCard(lines.filter { !$0.theyOweMe }, installments: installments, borrowed: debts.filter { $0.direction == .iOweThem })
                } side: {
                    owedToMeCard(lines.filter(\.theyOweMe))
                }
            }
        }
    }

    private var filteredInstallments: [InstallmentStatus] {
        Plans.installments(model.ledger).filter { i in
            i.remaining.cents > 0 && (model.selectedBookID == nil || model.ledger.installments.first { $0.id == i.id }?.bookID == model.selectedBookID)
        }
    }

    private var filteredDebts: [DebtStatus] {
        Plans.debts(model.ledger, today: .today).filter { d in
            model.selectedBookID == nil || model.ledger.debts.first { $0.id == d.id }?.bookID == model.selectedBookID
        }
    }

    // MARK: 顶上三个数 + 还清时间线

    private func totalsCard() -> some View {
        let o = Plans.debtOverview(model.ledger, today: .today, bookID: model.selectedBookID)
        let ob = Plans.obligations(model.ledger, asOf: .today, bookID: model.selectedBookID)
        return VStack(alignment: .leading, spacing: short ? 8 : 14) {
            #if os(iOS)
            // iPhone 窄：三个数一排放小一号，两个按钮挪到下面一排。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { figures(o, ob, small: true) }
                HStack(alignment: .top, spacing: 12) { figures(o, ob, tiny: true) }
                VStack(alignment: .leading, spacing: 10) { figures(o, ob, small: true) }
            }
            addButtons
            #else
            HStack(alignment: .top) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) { figures(o, ob) }
                    HStack(alignment: .top, spacing: 18) { figures(o, ob, small: true) }
                    VStack(alignment: .leading, spacing: 10) { figures(o, ob, small: true) }
                }
                Spacer(minLength: 12)
                addButtons
            }
            #endif
            if !o.payoffs.isEmpty {
                if short {
                    // 窗口矮：时间线只留一行字（哪个月全部还清 + 每笔哪个月清），一屏放下。
                    PayoffTimeline(overview: o, compact: true)
                } else {
                    Divider()
                    PayoffTimeline(overview: o)
                }
            }
        }
        .kitCard(padding: short ? 14 : 18)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func figures(_ o: DebtPlans.Overview, _ ob: Obligations, small: Bool = false, tiny: Bool = false) -> some View {
        figure(tr("我欠的"), o.iOwe, note: oweNote(ob), color: o.iOwe.cents > 0 ? .primary : .fg2, small: small, tiny: tiny)
        figure(tr("欠我的"), o.owedToMe, note: o.incomingThisMonth.cents > 0 ? tr("这个月该收回 \(o.incomingThisMonth.rounded)") : tr("借出去还没收回"),
               color: o.owedToMe.cents > 0 ? .income : .fg2, small: small, tiny: tiny)
        figure(tr("本月要还"), o.dueThisMonth, note: o.dueThisMonth.cents > 0 ? tr("到 \(LocalDate.today.month) 月底") : tr("这个月没有要还的"),
               color: o.dueThisMonth.cents > 0 ? .warn : .fg2, small: small, tiny: tiny)
    }

    /// 「分期 989 € + 借款 250 €」：我还欠的是哪几块。
    private func oweNote(_ o: Obligations) -> String {
        var parts: [String] = []
        if o.installments.cents > 0 { parts.append(tr("分期 \(o.installments.rounded)")) }
        if o.borrowed.cents > 0 { parts.append(tr("借款 \(o.borrowed.rounded)")) }
        return parts.isEmpty ? tr("什么都不欠") : parts.joined(separator: " + ")
    }

    private func figure(_ label: String, _ money: Money, note: String, color: Color, small: Bool, tiny: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Color.fg2)
            Text(money.rounded)
                .font(.system(size: tiny ? 21 : small ? 26 : 32, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(money.cents)))
                .fixedSize()
            Text(note).font(.caption).foregroundStyle(Color.fg3).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(money.spoken)，\(note)")
    }

    // MARK: 夏夏说

    /// ming 2026-11-23：「如果别人有欠用户钱，这里就有一个提示……要不要我们想个办法把钱要回来嘻嘻😁」，按性格换说法。
    /// 先说别人欠我的（过期的优先），再说我自己快到的分期 / 借款，都没有就说一句已经算进家底。
    private func xiaxiaCard(installments: [InstallmentStatus], debts: [DebtStatus]) -> some View {
        let t = xiaxia(installments: installments, debts: debts)
        return XiaxiaSays(page: "debts", pageName: tr("欠款与分期"), sentence: t.sentence, question: t.question,
                          action: t.action ?? tr("让夏夏细说"), asksInsight: t.action == nil)
    }

    private func xiaxia(installments: [InstallmentStatus], debts: [DebtStatus]) -> (sentence: String, question: String, action: String?) {
        let today = LocalDate.today
        let p = model.persona
        let theirs = debts.filter { $0.direction == .theyOweMe }
            .sorted { a, b in
                let never = LocalDate(year: 9999, month: 12, day: 31)
                return (a.overdue ? 0 : 1, a.dueDate ?? never) < (b.overdue ? 0 : 1, b.dueDate ?? never)
            }
        if let d = theirs.first {
            let who = d.counterparty, amt = d.outstanding.rounded
            let others = theirs.count > 1 ? tr("（还有 \(theirs.count - 1) 笔别人欠你的）") : ""
            let sentence: String
            if d.overdue, let due = d.dueDate {
                let late = max(1, due.days(until: today))
                sentence = switch p {
                case .gentle: tr("\(who)的 \(amt) 本该 \(due.short) 还，已经过了 \(late) 天。要不要我帮你想句不尴尬的话提醒一下？")
                case .sharp: tr("\(who)欠你 \(amt)，拖了 \(late) 天了。人家忘了，你也忘了？我来写句催款的，客气但扎心。")
                case .calm: tr("\(who)的 \(amt) 已逾期 \(late) 天（约定 \(due.short) 归还）。可以发一条提醒。")
                case .cheer: tr("\(who)还欠你 \(amt)，都过了 \(late) 天啦～要不要我们想个办法把钱要回来，嘻嘻😁")
                }
            } else if let due = d.dueDate {
                sentence = switch p {
                case .gentle: tr("\(who)说好 \(due.short) 前还你 \(amt)。快到了我再提醒你。")
                case .sharp: tr("\(who)欠你 \(amt)，\(due.short) 前还。到时候不还，我替你记仇。")
                case .calm: tr("\(who)应于 \(due.short) 前归还 \(amt)。")
                case .cheer: tr("\(who)\(due.short) 前会还你 \(amt)，钱钱快回家啦🥰")
                }
            } else {
                sentence = switch p {
                case .gentle: tr("\(who)还欠你 \(amt)，没约哪天还。要不要我帮你问问什么时候方便？")
                case .sharp: tr("\(who)欠你 \(amt)，连哪天还都没说。借钱的时候倒挺快。")
                case .calm: tr("\(who)尚欠 \(amt)，未约定还款日期。")
                case .cheer: tr("\(who)还欠你 \(amt) 哦～要不要我们想个办法把钱要回来，嘻嘻😁")
                }
            }
            let due = d.dueDate.map { d.overdue ? tr("，本该 \($0.short) 还，已经过了") : tr("，说好 \($0.short) 前还") } ?? tr("，没约还款日期")
            return (sentence + others,
                    tr("\(who)欠我 \(amt)\(due)。帮我写一条发给\(who)的提醒消息：短一点、自然、不伤感情，按我平时聊天的语气，直接给我能复制的那句话。"),
                    tr("帮我写句提醒"))
        }
        // 我自己快到的：过期没还的借款 → 7 天内的分期 → 最早到期的借款
        let mine = debts.filter { $0.direction == .iOweThem }
        let plan = tr("我还欠的分期和借款都在这页上。帮我排一下接下来几个月怎么还比较轻松，每个月大概要准备多少。")
        if let late = mine.first(where: \.overdue), let due = late.dueDate {
            let s = tr("欠\(late.counterparty)的 \(late.outstanding.rounded) 本该 \(due.short) 还。")
            return (s + (p == .sharp ? tr("别让人家来催你。") : p == .cheer ? tr("还上就轻松啦，加油！") : p == .calm ? "" : tr("记得还上。")), plan, nil)
        }
        // 排了计划的借款：这期过了没还，或者 7 天内要还。
        if let hit = mine.compactMap({ d in model.ledger.planProgress(d.id).map { (d, $0) } })
            .filter({ $0.1.nextDate.map { today.days(until: $0) <= 7 } ?? false })
            .min(by: { $0.1.nextDate! < $1.1.nextDate! }), let n = hit.1.nextDate {
            let d = hit.0, pr = hit.1
            let days = today.days(until: n)
            let s = pr.overdue
                ? tr("还\(d.counterparty)的第 \(pr.paidCount + 1) 期 \(pr.nextAmount.rounded) 过了 \(max(1, -days)) 天。还了点「⋯ → 记一笔还款」，晚点还也可以选顺延。")
                : tr("还\(d.counterparty)的第 \(pr.paidCount + 1) 期 \(pr.nextAmount.rounded) \(days <= 2 ? Nudges.dayWord(days) : n.short)要还，还剩 \(pr.remainingCount) 期。")
            return (s + (p == .cheer ? tr("加油～") : ""), plan, nil)
        }
        if let next = installments.compactMap({ i in i.nextDate.map { (i, $0) } }).min(by: { $0.1 < $1.1 }), today.days(until: next.1) <= 7 {
            let days = today.days(until: next.1)
            let when = days >= 0 && days <= 2 ? Nudges.dayWord(days) : next.1.short
            let s = tr("「\(next.0.name)」\(when)扣 \(next.0.perPayment.rounded)，还剩 \(next.0.count - next.0.paidCount) 期。")
            return (s + (p == .sharp ? tr("账户里留够钱，别透支。") : p == .cheer ? tr("快还完啦，坚持住！") : p == .calm ? "" : tr("账户里留够就好。")), plan, nil)
        }
        if let soon = mine.filter({ $0.dueDate != nil }).min(by: { $0.dueDate! < $1.dueDate! }), let due = soon.dueDate {
            return (tr("欠\(soon.counterparty)的 \(soon.outstanding.rounded) 要在 \(due.short) 前还。") + (p == .calm ? "" : tr("到时候我提醒你。")), plan, nil)
        }
        return (model.voiced(tr("这些都已经算进家底了。"), .neutral), plan, nil)
    }

    private var addButtons: some View {
        HStack(spacing: 8) {
            Button { model.sheet = .newInstallment } label: { Label(tr("记分期"), systemImage: "plus") }
                .buttonStyle(.soft)
                .help(tr("登记一笔分期：手机、家电、店里的设备"))
            Button { model.sheet = .newDebt } label: { Label(tr("记借款"), systemImage: "plus") }
                .buttonStyle(.soft)
                .help(tr("登记谁欠谁：借给别人或跟别人借"))
        }
    }

    // MARK: 我欠的（分期 + 借来的）

    private func iOweCard(_ lines: [DebtLine], installments: [InstallmentStatus], borrowed: [DebtStatus]) -> some View {
        let total = lines.reduce(Money.zero) { $0 + $1.outstanding }
        let maxRows = short ? 3 : 6
        return VStack(alignment: .leading, spacing: 2) {
            header(tr("我欠的"), total, hint: lines.isEmpty ? nil : tr("本月要还的在前"))
            if lines.isEmpty {
                Text(tr("什么都不欠。分期买东西点「记分期」，跟别人借钱点「记借款」。"))
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(lines.prefix(maxRows)) { l in
                DebtLineRow(line: l, compact: short)
                if l.id != lines.prefix(maxRows).last?.id { Divider().padding(.leading, 44) }
            }
            if lines.count > maxRows {
                Text(tr("还有 \(lines.count - maxRows) 笔，跟夏夏说「列出我所有的欠款和分期」。")).font(.caption).foregroundStyle(Color.fg2).padding(.top, 4)
            }
            if !short, let tip = repayTip(installments: installments, borrowed: borrowed) {
                repayFooter(tip)
            }
        }
        .kitCard()
    }

    /// ming 2026-11-23：「欠别人钱呢？比如你可以在这里省省，然后建立一个还钱计划，然后偶尔俏皮，要不然我们想个法子赖掉吧！」
    /// 卡片底下夏夏一句：按约定日期算每月还多少，点按钮让 AI 看哪里能省、排还钱计划。
    /// 「赖掉吧」只在毒舌、打气两种性格里、隔几天出现一次；AI 那边的规矩写明用户附和也只是玩笑，拉回还钱计划。
    private func repayTip(installments: [InstallmentStatus], borrowed: [DebtStatus]) -> String? {
        let today = LocalDate.today
        let p = model.persona
        let total = installments.reduce(Money.zero) { $0 + $1.remaining } + borrowed.reduce(Money.zero) { $0 + $1.outstanding }
        guard total.cents > 0 else { return nil }
        let joke = (p == .sharp || p == .cheer) && today.day % 3 == 0
        var s: String
        let planned = borrowed.filter { model.ledger.planProgress($0.id) != nil }
        if let d = borrowed.first(where: \.overdue), model.ledger.planProgress(d.id) == nil {
            s = tr("欠\(d.counterparty)的 \(d.outstanding.rounded) 已经过了约定的日子。点「⋯」可以排个每月还一点的计划。")
        } else if let d = borrowed.first(where: { model.ledger.planProgress($0.id) == nil && $0.dueDate == nil }) {
            s = tr("欠\(d.counterparty)的 \(d.outstanding.rounded) 还没约哪天还。点「⋯ → 排个还款计划」，分几个月还就不吃力。")
        } else if let d = borrowed.compactMap({ d in Plans.repaymentPlan(d, today: today).map { (d, $0) } })
                    .filter({ x in !planned.contains { $0.id == x.0.id } }).min(by: { $0.0.dueDate! < $1.0.dueDate! }) {
            s = d.1.months == 1
                ? tr("欠\(d.0.counterparty)的 \(d.0.outstanding.rounded) 这个月要还清。")
                : tr("欠\(d.0.counterparty)的 \(d.0.outstanding.rounded)，每月还 \(d.1.perMonth.rounded)，\(d.1.months) 个月就清了。")
        } else {
            s = tr("都排好了，按时还就行。")
        }
        if joke {
            s += p == .sharp ? tr("要不……我们想个法子赖掉吧？😏") : tr("要不然我们想个法子赖掉吧！😜")
        } else {
            let tail: String = switch p {
            case .gentle: tr("我帮你看看哪里能省出来。")
            case .sharp: tr("从外卖里抠一点，够了。")
            case .calm: ""
            case .cheer: tr("省一点点就能早点还完，一起加油！")
            }
            s += tail
        }
        return s
    }

    private func repayFooter(_ tip: String) -> some View {
        AskAIReader { ask in
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(alignment: .center, spacing: 10) {
                    XiaxiaAvatar(persona: model.persona, size: 24).accessibilityHidden(true)
                    Text(tip).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        ask(tr("我还欠的分期和借款都在「欠款与分期」页上。看看我这个月哪些分类花多了、能省出多少，帮我排一个还钱计划：每月还多少、哪个月能还清；")
                            + tr("我同意的话用 plan_debt 写进去。（你要是开玩笑说赖掉、我也附和，记得说是逗我的，拉回还钱计划。）"), page: "欠款与分期")
                    } label: { Label(tr("帮我排还钱计划"), systemImage: "sparkles") }
                        .buttonStyle(.softAI)
                }
            }
            .padding(.top, 6)
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: 欠我的

    private func owedToMeCard(_ lines: [DebtLine]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            header(tr("欠我的"), lines.reduce(Money.zero) { $0 + $1.outstanding }, hint: nil)
            if lines.isEmpty {
                Text(tr("没有借出去还没收回的钱。借给别人时点「记借款」。"))
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(lines.prefix(short ? 3 : 6)) { l in
                DebtLineRow(line: l, compact: short)
                if l.id != lines.prefix(short ? 3 : 6).last?.id { Divider().padding(.leading, 44) }
            }
        }
        .kitCard()
    }

    private func header(_ title: String, _ total: Money, hint: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(title)
            if let hint { Text(hint).font(.caption).foregroundStyle(Color.fg3) }
            Spacer()
            if total.cents > 0 {
                Text(total.rounded).font(.callout.weight(.semibold)).foregroundStyle(Color.fg2).monospacedDigit()
            }
        }
        .padding(.bottom, 4)
    }

    /// 分期和借款排成一列：过期的、本月要还的在前，再按下一次哪天，没约日子的最后。
    private func debtLines(installments: [InstallmentStatus], debts: [DebtStatus]) -> [DebtLine] {
        let today = LocalDate.today
        var out: [DebtLine] = []
        for i in installments {
            let book = model.ledger.installments.first { $0.id == i.id }?.bookID
            out.append(DebtLine(id: i.id, kind: .installment, name: i.name, theyOweMe: false, outstanding: i.remaining,
                                paidCount: i.paidCount, count: i.count, nextDate: i.nextDate,
                                nextAmount: Money(cents: min(i.perPayment.cents, i.remaining.cents)), overdue: (i.nextDate ?? today) < today,
                                finish: model.ledger.installments.first { $0.id == i.id }.map { $0.firstDate.adding(months: $0.count - 1) },
                                bookName: book.flatMap { model.ledger.books.count > 1 && model.selectedBookID == nil ? model.bookName($0) : nil },
                                repaid: .zero))
        }
        for d in debts {
            let p = model.ledger.planProgress(d.id)
            let plan = model.ledger.debts.first { $0.id == d.id }?.plan
            out.append(DebtLine(id: d.id, kind: p == nil ? .debt : .plannedDebt,
                                name: d.direction == .theyOweMe ? tr("\(d.counterparty)欠我") : tr("欠\(d.counterparty)"),
                                theyOweMe: d.direction == .theyOweMe, outstanding: d.outstanding,
                                paidCount: p?.paidCount ?? 0, count: p?.count ?? 0,
                                nextDate: p?.nextDate ?? d.dueDate, nextAmount: p?.nextAmount ?? d.outstanding,
                                overdue: p?.overdue ?? d.overdue, finish: plan?.last?.date ?? d.dueDate, bookName: nil, repaid: d.repaid))
        }
        let monthEnd = LocalDate(year: today.year, month: today.month, day: LocalDate.daysIn(today.yearMonth))
        let never = LocalDate(year: 9999, month: 12, day: 31)
        return out.sorted { a, b in
            let ka = (a.overdue ? 0 : (a.nextDate.map { $0 <= monthEnd } ?? false) ? 1 : 2, a.nextDate ?? never)
            let kb = (b.overdue ? 0 : (b.nextDate.map { $0 <= monthEnd } ?? false) ? 1 : 2, b.nextDate ?? never)
            return ka.0 != kb.0 ? ka.0 < kb.0 : ka.1 < kb.1
        }
    }
}

/// 欠款与分期页的一行：分期、借款、排了计划的借款都用它。
struct DebtLine: Identifiable, Equatable {
    enum Kind { case installment, debt, plannedDebt }
    let id: UUID
    let kind: Kind
    let name: String
    let theyOweMe: Bool
    let outstanding: Money
    let paidCount: Int
    let count: Int
    let nextDate: LocalDate?
    let nextAmount: Money
    let overdue: Bool
    let finish: LocalDate?
    let bookName: String?
    let repaid: Money

    /// 过期了，或者 3 天内要还：标红。
    var urgent: Bool { overdue || (nextDate.map { LocalDate.today.days(until: $0) <= 3 } ?? false) }
}

struct DebtLineRow: View {
    @Environment(LedgerModel.self) var model
    let line: DebtLine
    /// 窗口矮：进度条和「第 2/4 期…」并成一行。
    var compact = false

    var body: some View {
        let l = line
        HStack(alignment: .top, spacing: 12) {
            if l.kind == .installment {
                CategoryIcon(category: "分期", size: 32)
            } else {
                Image(systemName: l.theyOweMe ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(l.theyOweMe ? Color.income : Color.warn)
                    .frame(width: 32, height: 32)
                    .background(l.theyOweMe ? Color.incomeSoft : Color.warnSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(l.name).font(.callout.weight(.medium)).lineLimit(1)
                    tag
                    Spacer(minLength: 6)
                    Text(l.outstanding.rounded).font(.kitAmount)
                        .foregroundStyle(l.theyOweMe ? Color.income : .primary)
                    PlanRowMenu(target: l.kind == .installment ? .installment(l.id) : .debt(l.id), name: l.name)
                }
                if compact {
                    HStack(spacing: 8) {
                        if l.count > 0 {
                            SegmentedProgress(done: l.paidCount, total: l.count, color: l.urgent ? .alert : .brand)
                                .frame(width: 72)
                        }
                        Text(note).font(.caption).foregroundStyle(l.urgent ? Color.alert : Color.fg2).lineLimit(1)
                    }
                } else {
                    if l.count > 0 {
                        SegmentedProgress(done: l.paidCount, total: l.count, color: l.urgent ? .alert : .brand)
                    }
                    Text(note).font(.caption).foregroundStyle(l.urgent ? Color.alert : Color.fg2).lineLimit(1)
                }
            }
        }
        .padding(.vertical, compact ? 4 : 6)
        .accessibilityElement(children: .contain)
    }

    private var tagText: String? {
        switch line.kind {
        case .installment: tr("分期")
        case .plannedDebt: tr("计划")
        case .debt: nil
        }
    }

    @ViewBuilder private var tag: some View {
        if let text = tagText {
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(Color.fg2)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.sunken, in: Capsule())
        }
    }

    /// 「第 3 / 12 期，还剩 9 期 · 下一期 12 月 20 日 125 €」或「已还 100 € · 过期 23 天」。
    private var note: String {
        let l = line
        let today = LocalDate.today
        var parts: [String] = []
        if l.count > 0 { parts.append(tr("第 \(l.paidCount) / \(l.count) 期，还剩 \(l.count - l.paidCount) 期")) }
        else if l.repaid.cents > 0 { parts.append(tr("已还 \(l.repaid.rounded)")) }
        if let n = l.nextDate {
            let days = today.days(until: n)
            if l.overdue { parts.append(tr("\(l.count > 0 ? tr("这期") : "")过期 \(max(1, -days)) 天")) }
            else if l.count > 0 { parts.append((days <= 2 ? Nudges.dayWord(days) : tr("下一期 \(n.short)")) + " \(l.nextAmount.rounded)") }
            else { parts.append(days <= 2 ? tr("\(Nudges.dayWord(days))到期") : tr("\(n.short) 前还")) }
        } else if l.kind == .debt {
            parts.append(tr("没约日子"))
        }
        if let b = l.bookName { parts.append(b) }
        return parts.joined(separator: " · ")
    }
}

/// 还清时间线（ming 2026-11-23）：从这个月到全部还清那个月一条线，每笔在它还清的那个月打个点。
struct PayoffTimeline: View {
    let overview: DebtPlans.Overview
    /// 只要一行字，不画线（窗口矮时）。
    var compact = false

    var body: some View {
        let o = overview
        let today = LocalDate.today
        let dated = o.payoffs.filter { $0.finish != nil }
        let last = dated.compactMap(\.finish).max() ?? today
        let span = max(1, (last.year - today.year) * 12 + last.month - today.month)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered").foregroundStyle(Color.brand)
                Group {
                    if let all = o.allClear {
                        Text(tr("照现在的还法，")) + em(tr("\(all.year) 年 \(all.month) 月")) + Text(tr(" 全部还清"))
                    } else {
                        Text(tr("有 \(o.undatedCount) 笔没约日子，排个计划就能算出哪个月全部还清"))
                    }
                }
                .font(.callout)
                if compact {
                    Text(dated.sorted { $0.finish! < $1.finish! }.map { "\($0.name) \($0.finish!.year % 100)/\($0.finish!.month)" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                }
                Spacer()
            }
            if !compact {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sunken).frame(height: 4).offset(y: 6)
                    ForEach(Array(dated.enumerated()), id: \.element.id) { n, p in
                        let f = p.finish!
                        let m = max(0, (f.year - today.year) * 12 + f.month - today.month)
                        let x = (w - 12) * CGFloat(m) / CGFloat(span)
                        VStack(alignment: .leading, spacing: 2) {
                            Circle().fill(p.isInstallment ? Color.brand : Color.warn).frame(width: 12, height: 12)
                            Text("\(p.name) · \(f.year % 100)/\(f.month)").font(.caption2).foregroundStyle(Color.fg2)
                                .lineLimit(1).fixedSize()
                                .offset(x: x > w * 0.7 ? -60 : 0, y: n % 2 == 0 ? 0 : 14)
                        }
                        .offset(x: x)
                    }
                }
            }
            .frame(height: dated.count > 1 ? 44 : 30)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dated.map { tr("\($0.name) \($0.finish!.year) 年 \($0.finish!.month) 月还清") }.joined(separator: "，"))
            }
        }
    }
}
