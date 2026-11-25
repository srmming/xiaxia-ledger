import FinanceCore
import SwiftUI

/// 生意首页（设计稿 design/mockups/business-mode.html ④，2026-11-25 v2）。
/// 大字是这个月赚了多少（进账 − 成本），下面按四个口袋排：每天进出、开店本钱（回本进度）、每月固定开销、欠款。
/// 算账规矩都在 FinanceCore：还款只有利息算成本；第一批进货算本钱；拿回家的钱不算成本；回本速度按最近 3 个月平均。
struct BusinessHome: View {
    @Environment(LedgerModel.self) var model
    @State private var editingCapital = false

    /// 零碎开销，点一下就记。
    static let quickCosts = ["进货", "耗材", "交通", "其他"]

    var body: some View {
        let today = LocalDate.today
        let report = try? model.ledger.businessReport(month: model.shownMonth, today: today)
        VStack(alignment: .leading, spacing: Kit.gap) {
            Columns(sideWidth: 360) {
                heroCard(report)
            } side: {
                todayCard(report)
            }
            XiaxiaSays(page: "business", pageName: tr("生意"), sentence: xiaxia(report),
                       question: "看看我店里 \(model.shownMonth.month) 月的账：赚了多少、钱花在哪、什么时候能回本？")
            Columns(sideRatio: 0.49) {
                capitalCard
                debtsCard
            } side: {
                fixedCard(report)
                recentCard
            }
        }
        #if os(macOS)
        .sheet(isPresented: $editingCapital) { CapitalEditor().environment(model) }
        #endif
    }

    // MARK: 这个月赚了多少

    private func heroCard(_ r: BusinessReport?) -> some View {
        let month = model.shownMonth
        let current = month == LocalDate.today.yearMonth
        let profit = r?.profit ?? .zero
        let label = current ? tr("\(month.month) 月\(profit.isExpense ? tr("亏了") : tr("赚了")) · 截至 \(LocalDate.today.day) 日")
            : tr("\(month.month) 月\(profit.isExpense ? tr("亏了") : tr("赚了"))")
        return VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(Color.fg2)
            BigMoney(money: profit.magnitude, color: profit.isExpense ? .alert : .shop)
                .animation(.easeOut(duration: 0.3), value: profit)
            if let r {
                (Text(tr("进账 ")) + em(r.income.ui) + Text(tr(" − 成本 ")) + em(r.cost.magnitude.ui))
                    .font(.body)
                compare(r, current: current).font(.body).fixedSize(horizontal: false, vertical: true)
                if r.takenHome.cents > 0 {
                    Text(tr("另外拿回家 \(r.takenHome.ui)，不算成本。")).font(.caption).foregroundStyle(Color.fg2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .kitCard(padding: 20)
    }

    private func compare(_ r: BusinessReport, current: Bool) -> Text {
        let than = current ? tr("比上月同期") : tr("比上个月")
        var t: Text
        if r.changeFromPrevious.cents == 0 {
            t = Text(current ? tr("和上月同期赚得一样。") : tr("和上个月赚得一样。"))
        } else if r.changeFromPrevious.isIncome {
            t = Text(than) + em(tr(" 多赚 \(r.changeFromPrevious.ui)"), .good) + Text(tr("。"))
        } else {
            t = Text(than) + em(tr(" 少赚 \(r.changeFromPrevious.magnitude.ui)"), .bad) + Text(tr("。"))
        }
        if current, r.fixedUpcoming.cents > 0 {
            let left = r.profit - r.fixedUpcoming
            t = t + Text(tr("还有 \(r.fixedUpcoming.ui) 固定开销没到日子，扣完大约\(left.isExpense ? tr("亏") : tr("剩")) "))
                + em(left.magnitude.ui, left.isExpense ? .bad : .plain) + Text(tr("。"))
        }
        return t
    }

    // MARK: 今天（每天进出）

    private func todayCard(_ r: BusinessReport?) -> some View {
        let book = model.ledger.businessBook?.id
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: tr("今天")) {
                Text(LocalDate.today.short).foregroundStyle(Color.shop)
            }
            Button {
                model.addWith(AddPreset(income: true, category: "营业收入", bookID: book))
            } label: {
                Label(tr("记今天进账"), systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color.shop, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("business.addIncome")
            HStack {
                Text(tr("今天进账 ")) + em(r?.todayIncome.ui ?? Money.zero.ui, .good)
                Spacer(minLength: 8)
                Text(tr("今天花了 ")) + em(r?.todayCost.ui ?? Money.zero.ui)
            }
            .font(.subheadline)
            Text(tr("零碎开销，点一下就记：")).font(.caption).foregroundStyle(Color.fg2)
            HStack(spacing: 6) {
                ForEach(Self.quickCosts, id: \.self) { c in
                    Button(trKey(c)) { model.addWith(AddPreset(income: false, category: c, bookID: book)) }
                        .buttonStyle(SoftButtonStyle(color: .shop, background: .shopSoft))
                        .accessibilityHint(tr("记一笔店里的「\(trKey(c))」"))
                }
            }
        }
        .kitCard()
    }

    // MARK: 开店本钱 → 回本进度

    private var capitalCard: some View {
        let progress = model.ledger.capitalProgress(today: .today)
        let capital = model.ledger.business?.capital
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: tr("回本进度")) {
                #if os(macOS)
                Button(capital == nil ? tr("填本钱") : tr("改本钱")) { editingCapital = true }
                    .buttonStyle(.borderless).foregroundStyle(Color.shop)
                #endif
            }
            if let p = progress, let c = capital {
                (Text(p.recovered.magnitude.rounded).font(.title2.weight(.bold).monospacedDigit())
                 + Text(" / \(c.total.rounded)").font(.callout.weight(.semibold)).foregroundColor(.fg2))
                Bar(fraction: p.fraction, color: .shop, height: 8)
                Text(estimate(p)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("还没填开店本钱。")).font(.subheadline.weight(.semibold))
                #if os(macOS)
                Text(tr("填一个总数就行，夏夏用它帮你算什么时候回本。")).font(.caption).foregroundStyle(Color.fg2)
                #else
                Text(tr("在 Mac 上 设置 → 生意模式 里填一个总数，夏夏就能算什么时候回本。")).font(.caption).foregroundStyle(Color.fg2)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .kitCard()
    }

    private func estimate(_ p: CapitalProgress) -> String {
        let percent = Int((p.fraction * 100).rounded())
        switch p.estimate {
        case .done: return tr("已经回本了。之后赚的都是净赚。")
        case .tooEarly: return tr("已回本 \(percent)%。开店不满 1 个月，再记一阵子才能估什么时候回本。")
        case .notRecovering: return tr("已回本 \(percent)%。最近 3 个月没赚到钱，照现在的情况还回不了本。")
        case .months(let n): return tr("已回本 \(percent)%，照最近 3 个月，大约还要 \(n) 个月。")
        }
    }

    // MARK: 每月固定开销

    private func fixedCard(_ r: BusinessReport?) -> some View {
        let rules = r?.fixed ?? []
        let today = LocalDate.today
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: tr("每月固定开销")) {
                if let r, r.fixedTotal.cents > 0 { Text(tr("\(r.fixedTotal.rounded)/月")).foregroundStyle(Color.shop) }
            }
            .padding(.bottom, 4)
            if rules.isEmpty {
                Text(tr("还没有。店租、工资这种每月都有的，记一笔时选「每月重复」，到日子自动记上。"))
                    .font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(rules.prefix(3))) { rule in
                let name = rule.template.category ?? rule.template.description
                let day = rule.start.day
                let done = rule.frequency != .monthly || day <= today.day || model.shownMonth < today.yearMonth
                HStack(spacing: 10) {
                    CategoryIcon(category: rule.template.category)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(trKey(name)).font(.callout).lineLimit(1)
                        Text(rule.frequency == .monthly ? tr("每月 \(day) 号 · \(done ? tr("已记") : tr("还没到"))") : trKey(rule.frequency.label))
                            .font(.caption).foregroundStyle(Color.fg2)
                    }
                    Spacer(minLength: 8)
                    Text(rule.template.amount.magnitude.ui).font(.kitAmount)
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
            }
            if rules.count > 3 {
                Text(tr("还有 \(rules.count - 3) 项")).font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kitCard()
    }

    // MARK: 欠款

    private struct DebtLine: Identifiable {
        let id: String
        let title: String
        let detail: String
        let amount: Money
        let owedToMe: Bool
    }

    private var debtLines: [DebtLine] {
        guard let book = model.ledger.businessBook?.id else { return [] }
        let ledger = model.ledger
        let today = LocalDate.today
        var lines: [DebtLine] = []
        // 我欠的：每张卡、每笔借款、每个分期各一行。
        let debtBooks = Dictionary(ledger.debts.map { ($0.id, $0.bookID) }, uniquingKeysWith: { a, _ in a })
        let statuses = Plans.debts(ledger, today: today).filter { debtBooks[$0.id] == book && $0.outstanding.cents > 0 }
        for d in statuses where d.direction == .iOweThem {
            lines.append(.init(id: d.id.uuidString, title: d.counterparty,
                               detail: d.dueDate.map { tr("\($0.short)前还") } ?? tr("借来的"), amount: d.outstanding, owedToMe: false))
        }
        let instBooks = Dictionary(ledger.installments.map { ($0.id, $0.bookID) }, uniquingKeysWith: { a, _ in a })
        for i in Plans.installments(ledger) where instBooks[i.id] == book && i.remaining.cents > 0 {
            lines.append(.init(id: i.id.uuidString, title: i.name,
                               detail: tr("分期 · 还剩 \(max(0, i.count - i.paidCount)) 期"), amount: i.remaining, owedToMe: false))
        }
        // 别人欠我的：单独几行，到手那天才算进账。
        for d in statuses where d.direction == .theyOweMe {
            lines.append(.init(id: d.id.uuidString, title: tr("别人欠我 · \(d.counterparty)"), detail: tr("到手那天才算进账"), amount: d.outstanding, owedToMe: true))
        }
        for r in ledger.receivables where r.amount.cents > 0 {
            lines.append(.init(id: r.id.uuidString, title: tr("别人欠我 · \(r.name)"), detail: tr("到手那天才算进账"), amount: r.amount, owedToMe: true))
        }
        return lines
    }

    private var debtsCard: some View {
        let lines = debtLines
        let iOwe = lines.filter { !$0.owedToMe }.reduce(Money.zero) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: tr("欠款")) {
                MoreLink(title: tr("欠款与分期"), section: .debts)
            }
            .padding(.bottom, 4)
            if lines.isEmpty {
                Text(tr("店里现在没有欠款。贷款、刷卡分期、别人赊的账，在「欠款与分期」里记，这里就会按卡分开列出来。"))
                    .font(.subheadline).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            } else {
                if iOwe.cents > 0 {
                    (Text(tr("店里还欠 ")) + em(iOwe.ui)).font(.subheadline).padding(.bottom, 2)
                }
                ForEach(Array(lines.prefix(3))) { line in
                    HStack(spacing: 10) {
                        XiaTile(glyph: line.owedToMe ? .revenue : .loan, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.title).font(.callout).lineLimit(1)
                            Text(line.detail).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(line.owedToMe ? "+" + line.amount.ui : line.amount.ui)
                            .font(.kitAmount).foregroundStyle(line.owedToMe ? Color.income : .primary)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
                if lines.count > 3 {
                    Text(tr("还有 \(lines.count - 3) 笔")).font(.caption).foregroundStyle(Color.fg2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kitCard()
    }

    // MARK: 最近几笔

    private var recentCard: some View {
        let book = model.ledger.businessBook?.id
        let recent = Array(model.visibleTransactions.filter { $0.bookID == book && $0.flow != .opening && $0.flow != .`internal` }.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: tr("最近几笔")) {
                MoreLink(title: tr("全部"), section: .transactions)
            }
            .padding(.bottom, 4)
            if recent.isEmpty {
                Text(tr("店里还没有流水。点「记今天进账」记第一笔。")).font(.subheadline).foregroundStyle(Color.fg2)
            }
            ForEach(recent) { t in
                TxRow(tx: t, showDate: true)
                if t.id != recent.last?.id { Divider().padding(.leading, 44) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kitCard()
    }

    // MARK: 夏夏说

    private func xiaxia(_ r: BusinessReport?) -> String {
        guard let r else { return tr("店里的账还读不出来，稍后再看。") }
        let m = model.shownMonth.month
        if r.income.cents == 0 && r.cost.cents == 0 {
            return model.voiced(tr("店里 \(m) 月还没有流水，记一笔今天的进账试试。"), .neutral)
        }
        var fact = r.profit.isExpense ? tr("店里 \(m) 月到现在亏了 \(r.profit.magnitude.rounded)。") : tr("店里 \(m) 月到现在赚了 \(r.profit.rounded)。")
        if let top = r.topCosts.first {
            fact += tr("钱花得最多的是「\(trKey(top.category))」，\(top.amount.rounded)。")
        }
        return model.voiced(fact, r.profit.isExpense ? .bad : .good)
    }
}

#if os(macOS)
/// 填开店本钱（设计稿 ②）：只填一个总数就行；开了一阵子才用的，可以填「开店到现在已经赚回多少」。
struct CapitalEditor: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State private var totalText = ""
    @State private var recoveredText = ""
    @State private var opened = Date()
    @State private var hasOpened = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("开店本钱")).font(.title2.weight(.bold))
            Text(tr("夏夏用它帮你算什么时候回本。不知道可以先跳过，以后在 设置 → 生意模式 里填。"))
                .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            LabeledContent(tr("一共投了多少")) {
                TextField(tr("比如 70000"), text: $totalText).frame(width: 160).multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("capital.total")
            }
            Toggle(tr("填开店日期"), isOn: $hasOpened)
            if hasOpened {
                DatePicker(tr("哪天开的店"), selection: $opened, displayedComponents: .date)
            }
            LabeledContent(tr("开店到现在已经赚回（可以不填）")) {
                TextField("0", text: $recoveredText).frame(width: 160).multilineTextAlignment(.trailing)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Color.alert) }
            HStack {
                Button(tr("先跳过")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(tr("保存")) { save() }
                    .buttonStyle(.borderedProminent).tint(Color.shop)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Money.evaluate(totalText).map { $0.cents > 0 } != true)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            guard let c = model.ledger.business?.capital else { return }
            totalText = c.total.inputText
            if c.recoveredBefore.cents > 0 { recoveredText = c.recoveredBefore.inputText }
            if let d = c.openedOn { opened = d.asDate; hasOpened = true }
        }
    }

    private func save() {
        guard let total = Money.evaluate(totalText), total.cents > 0 else { error = tr("本钱要大于 0"); return }
        let recovered = recoveredText.trimmingCharacters(in: .whitespaces).isEmpty ? Money.zero : (Money.evaluate(recoveredText) ?? .zero)
        let old = model.ledger.business?.capital
        let capital = Capital(total: total, openedOn: hasOpened ? LocalDate(opened) : nil, recoveredBefore: recovered.magnitude, items: old?.items ?? [])
        do {
            try model.edit { try $0.setCapital(capital, author: model.author) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
