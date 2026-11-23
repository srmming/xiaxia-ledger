import FinanceCore
import SwiftUI

/// 欠款与分期：我还欠多少、别人欠我多少？（ming 2026-11-23 从「计划」里拆出来单独一页。）
/// 视觉重心是顶上两个数；下面左边「我欠的」（分期 + 借来的），右边「欠我的」和夏夏说。这些都已经算进家底。
struct DebtsPage: View {
    @Environment(LedgerModel.self) var model
    /// iPhone 的「计划」标签里也用这一页，那里外面已经有滚动了。
    var embedded = false

    var body: some View {
        if embedded { content } else { content.kitPage() }
    }

    @ViewBuilder private var content: some View {
        let installments = filteredInstallments
        let debts = filteredDebts
        if installments.isEmpty && debts.isEmpty {
            VStack(spacing: Kit.gap) {
                VStack(spacing: 12) {
                    KitEmptyState(symbol: "arrow.left.arrow.right", title: "没有欠款，也没有分期",
                                  message: "借钱给别人、跟别人借钱、分期买东西，登记一下就会算进家底，还到哪一期也看得清。",
                                  prompt: "帮我记一笔欠款：朋友借了我 300 €，下个月还", page: "欠款与分期")
                    addButtons
                }
                .kitCard()
                AskAICard(title: "跟夏夏说一句也能记", note: nil, page: "欠款与分期", prompts: model.prompts(for: .debts))
            }
        } else {
            // ming 2026-11-23：分期没还完的也是欠款。按「我欠的 / 欠我的」分两边，分期和借来的钱放在一起。
            VStack(alignment: .leading, spacing: Kit.gap) {
                totalsCard(installments: installments, debts: debts)
                Columns(sideWidth: 340, breakpoint: 640) {
                    iOweCard(installments: installments, borrowed: debts.filter { $0.direction == .iOweThem })
                } side: {
                    owedToMeCard(debts.filter { $0.direction == .theyOweMe })
                    xiaxiaCard(installments: installments, debts: debts)
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

    // MARK: 顶上两个数

    private func totalsCard(installments: [InstallmentStatus], debts: [DebtStatus]) -> some View {
        let o = Plans.obligations(model.ledger, asOf: .today, bookID: model.selectedBookID)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 36) { figures(o) }
                    VStack(alignment: .leading, spacing: 10) { figures(o) }
                }
                Spacer(minLength: 12)
                addButtons
            }
        }
        .kitCard(padding: 20)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func figures(_ o: Obligations) -> some View {
        figure("我还欠", o.iOwe, note: oweNote(o), color: o.iOwe.cents > 0 ? .primary : .fg2)
        figure("别人欠我", o.owedToMe, note: "借出去还没收回", color: o.owedToMe.cents > 0 ? .income : .fg2)
    }

    /// 「分期 989 € + 借款 250 €」：我还欠的是哪几块。
    private func oweNote(_ o: Obligations) -> String {
        var parts: [String] = []
        if o.installments.cents > 0 { parts.append("分期 \(o.installments.rounded)") }
        if o.borrowed.cents > 0 { parts.append("借款 \(o.borrowed.rounded)") }
        return parts.isEmpty ? "什么都不欠" : parts.joined(separator: " + ")
    }

    private func figure(_ label: String, _ money: Money, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Color.fg2)
            Text(money.rounded)
                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(money.cents)))
            Text(note).font(.caption).foregroundStyle(Color.fg3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(money.spoken)")
    }

    // MARK: 夏夏说

    /// ming 2026-11-23：「如果别人有欠用户钱，这里就有一个提示……要不要我们想个办法把钱要回来嘻嘻😁」，按性格换说法。
    /// 先说别人欠我的（过期的优先），再说我自己快到的分期 / 借款，都没有就说一句已经算进家底。
    private func xiaxiaCard(installments: [InstallmentStatus], debts: [DebtStatus]) -> some View {
        let t = xiaxia(installments: installments, debts: debts)
        return XiaxiaSays(page: "debts", pageName: "欠款与分期", sentence: t.sentence, question: t.question,
                          action: t.action ?? "让夏夏细说", asksInsight: t.action == nil)
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
            let others = theirs.count > 1 ? "（还有 \(theirs.count - 1) 笔别人欠你的）" : ""
            let sentence: String
            if d.overdue, let due = d.dueDate {
                let late = max(1, due.days(until: today))
                sentence = switch p {
                case .gentle: "\(who)的 \(amt) 本该 \(due.short) 还，已经过了 \(late) 天。要不要我帮你想句不尴尬的话提醒一下？"
                case .sharp: "\(who)欠你 \(amt)，拖了 \(late) 天了。人家忘了，你也忘了？我来写句催款的，客气但扎心。"
                case .calm: "\(who)的 \(amt) 已逾期 \(late) 天（约定 \(due.short) 归还）。可以发一条提醒。"
                case .cheer: "\(who)还欠你 \(amt)，都过了 \(late) 天啦～要不要我们想个办法把钱要回来，嘻嘻😁"
                }
            } else if let due = d.dueDate {
                sentence = switch p {
                case .gentle: "\(who)说好 \(due.short) 前还你 \(amt)。快到了我再提醒你。"
                case .sharp: "\(who)欠你 \(amt)，\(due.short) 前还。到时候不还，我替你记仇。"
                case .calm: "\(who)应于 \(due.short) 前归还 \(amt)。"
                case .cheer: "\(who)\(due.short) 前会还你 \(amt)，钱钱快回家啦🥰"
                }
            } else {
                sentence = switch p {
                case .gentle: "\(who)还欠你 \(amt)，没约哪天还。要不要我帮你问问什么时候方便？"
                case .sharp: "\(who)欠你 \(amt)，连哪天还都没说。借钱的时候倒挺快。"
                case .calm: "\(who)尚欠 \(amt)，未约定还款日期。"
                case .cheer: "\(who)还欠你 \(amt) 哦～要不要我们想个办法把钱要回来，嘻嘻😁"
                }
            }
            let due = d.dueDate.map { d.overdue ? "，本该 \($0.short) 还，已经过了" : "，说好 \($0.short) 前还" } ?? "，没约还款日期"
            return (sentence + others,
                    "\(who)欠我 \(amt)\(due)。帮我写一条发给\(who)的提醒消息：短一点、自然、不伤感情，按我平时聊天的语气，直接给我能复制的那句话。",
                    "帮我写句提醒")
        }
        // 我自己快到的：过期没还的借款 → 7 天内的分期 → 最早到期的借款
        let mine = debts.filter { $0.direction == .iOweThem }
        let plan = "我还欠的分期和借款都在这页上。帮我排一下接下来几个月怎么还比较轻松，每个月大概要准备多少。"
        if let late = mine.first(where: \.overdue), let due = late.dueDate {
            let s = "欠\(late.counterparty)的 \(late.outstanding.rounded) 本该 \(due.short) 还。"
            return (s + (p == .sharp ? "别让人家来催你。" : p == .cheer ? "还上就轻松啦，加油！" : p == .calm ? "" : "记得还上。"), plan, nil)
        }
        if let next = installments.compactMap({ i in i.nextDate.map { (i, $0) } }).min(by: { $0.1 < $1.1 }), today.days(until: next.1) <= 7 {
            let days = today.days(until: next.1)
            let when = days >= 0 && days <= 2 ? Nudges.dayWord(days) : next.1.short
            let s = "「\(next.0.name)」\(when)扣 \(next.0.perPayment.rounded)，还剩 \(next.0.count - next.0.paidCount) 期。"
            return (s + (p == .sharp ? "账户里留够钱，别透支。" : p == .cheer ? "快还完啦，坚持住！" : p == .calm ? "" : "账户里留够就好。"), plan, nil)
        }
        if let soon = mine.filter({ $0.dueDate != nil }).min(by: { $0.dueDate! < $1.dueDate! }), let due = soon.dueDate {
            return ("欠\(soon.counterparty)的 \(soon.outstanding.rounded) 要在 \(due.short) 前还。" + (p == .calm ? "" : "到时候我提醒你。"), plan, nil)
        }
        return (model.voiced("这些都已经算进家底了。", .neutral), plan, nil)
    }

    private var addButtons: some View {
        HStack(spacing: 8) {
            Button { model.sheet = .newInstallment } label: { Label("记分期", systemImage: "plus") }
                .buttonStyle(.soft)
                .help("登记一笔分期：手机、家电、店里的设备")
            Button { model.sheet = .newDebt } label: { Label("记借款", systemImage: "plus") }
                .buttonStyle(.soft)
                .help("登记谁欠谁：借给别人或跟别人借")
        }
    }

    // MARK: 我欠的（分期 + 借来的）

    private func iOweCard(installments: [InstallmentStatus], borrowed: [DebtStatus]) -> some View {
        let total = installments.reduce(Money.zero) { $0 + $1.remaining } + borrowed.reduce(Money.zero) { $0 + $1.outstanding }
        return VStack(alignment: .leading, spacing: 4) {
            header("我欠的", total)
            if installments.isEmpty && borrowed.isEmpty {
                Text("什么都不欠。分期买东西点「记分期」，跟别人借钱点「记借款」。")
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(installments, id: \.id) { i in
                installmentRow(i)
                if i.id != installments.last?.id || !borrowed.isEmpty { Divider().padding(.leading, 44) }
            }
            ForEach(borrowed, id: \.id) { d in
                debtRow(d)
                if d.id != borrowed.last?.id { Divider().padding(.leading, 42) }
            }
        }
        .kitCard()
    }

    private func installmentRow(_ i: InstallmentStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: "分期", size: 32)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(i.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text("分期").font(.caption2.weight(.semibold)).foregroundStyle(Color.fg2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.sunken, in: Capsule())
                    Spacer()
                    Text("还剩 \(i.remaining.rounded)").font(.kitAmount)
                    PlanRowMenu(target: .installment(i.id), name: i.name)
                }
                SegmentedProgress(done: i.paidCount, total: i.count)
                Text(installmentNote(i)).font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func installmentNote(_ i: InstallmentStatus) -> String {
        var parts = ["第 \(i.paidCount) / \(i.count) 期", "每期 \(i.perPayment.ui)"]
        if let next = i.nextDate { parts.append("下一期 \(next.short)") }
        if let book = model.ledger.installments.first(where: { $0.id == i.id })?.bookID, model.ledger.books.count > 1, model.selectedBookID == nil {
            parts.append(model.bookName(book))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 欠我的

    private func owedToMeCard(_ list: [DebtStatus]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header("欠我的", list.reduce(Money.zero) { $0 + $1.outstanding })
            if list.isEmpty {
                Text("没有借出去还没收回的钱。借给别人时点「记借款」。")
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(list, id: \.id) { d in
                debtRow(d)
                if d.id != list.last?.id { Divider().padding(.leading, 42) }
            }
        }
        .kitCard()
    }

    private func header(_ title: String, _ total: Money) -> some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(title)
            Spacer()
            if total.cents > 0 {
                Text(total.rounded).font(.callout.weight(.semibold)).foregroundStyle(Color.fg2).monospacedDigit()
            }
        }
        .padding(.bottom, 2)
    }

    private func debtRow(_ d: DebtStatus) -> some View {
        HStack(spacing: 6) {
            DebtRow(debt: d)
            PlanRowMenu(target: .debt(d.id), name: d.counterparty)
        }
    }
}
