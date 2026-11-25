import FinanceCore
import SwiftUI

/// 生意首页 · 简约版（设计稿 design/mockups/business-simple.html v3，2026-11-25 ming：「流程我看不懂，界面我希望简约现代」）。
/// 只回答一个问题：这个月赚了多少。下面两个按钮记账，最底下一条回本进度和三个小数字；
/// 钱花在哪、每一笔流水、欠款明细都在各自的页面里，首页不放。
/// 算账规矩都在 FinanceCore：还款只有利息算成本；第一批进货算本钱；拿回家的钱不算成本；回本速度按最近 3 个月平均。
struct BusinessHome: View {
    @Environment(LedgerModel.self) var model
    @State private var editingCapital = false

    #if os(macOS)
    private let bigSize: CGFloat = 64
    private let inset: CGFloat = 48
    #else
    private let bigSize: CGFloat = 52
    private let inset: CGFloat = 8
    #endif

    var body: some View {
        let today = LocalDate.today
        let report = try? model.ledger.businessReport(month: model.shownMonth, today: today)
        let book = model.ledger.businessBook?.id
        VStack(alignment: .leading, spacing: 0) {
            hero(report)
            buttons(book).padding(.top, 32)
            VStack(alignment: .leading, spacing: 0) {
                payback
                Divider().padding(.vertical, 16)
                stats(report, book: book)
            }
            .padding(.top, 56)
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, inset)
        .padding(.top, inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(macOS)
        .sheet(isPresented: $editingCapital) { CapitalEditor().environment(model) }
        #endif
    }

    // MARK: 这个月赚了多少

    private func hero(_ r: BusinessReport?) -> some View {
        let month = model.shownMonth
        let profit = r?.profit ?? .zero
        let current = month == LocalDate.today.yearMonth
        return VStack(alignment: .leading, spacing: 6) {
            Text(tr("\(month.month) 月\(profit.isExpense ? tr("亏了") : tr("赚了"))"))
                .font(.subheadline).foregroundStyle(Color.fg2)
            BigMoney(money: profit.magnitude, size: bigSize, color: profit.isExpense ? .alert : .primary)
                .animation(.easeOut(duration: 0.3), value: profit)
            if let r { compare(r, current: current).font(.subheadline).foregroundStyle(Color.fg2) }
        }
        .accessibilityElement(children: .combine)
    }

    private func compare(_ r: BusinessReport, current: Bool) -> Text {
        let than = current ? tr("比上月同期") : tr("比上个月")
        let d = r.changeFromPrevious
        if d.cents == 0 { return Text(current ? tr("和上月同期一样") : tr("和上个月一样")) }
        return Text(than + " ") + em(tr("\(d.isIncome ? tr("多") : tr("少")) \(d.magnitude.rounded)"), d.isIncome ? .good : .bad)
    }

    // MARK: 记进账 / 记开销

    /// Mac 上两个按钮并排，iPhone 上下叠。
    private var buttonLayout: AnyLayout {
        #if os(macOS)
        return AnyLayout(HStackLayout(spacing: 12))
        #else
        return AnyLayout(VStackLayout(spacing: 10))
        #endif
    }

    private func buttons(_ book: String?) -> some View {
        buttonLayout {
            Button { model.addWith(AddPreset(income: true, category: "营业收入", bookID: book)) } label: {
                Label(tr("记进账"), systemImage: "plus").bigButton(filled: true)
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("business.addIncome")
            Button { model.addWith(AddPreset(income: false, category: nil, bookID: book)) } label: {
                Text(tr("记开销")).bigButton(filled: false)
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("business.addCost")
        }
        .frame(maxWidth: 440)
    }

    // MARK: 回本

    @ViewBuilder private var payback: some View {
        if let p = model.ledger.capitalProgress(today: .today) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("回本 \(Int((p.fraction * 100).rounded()))%")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Text(estimate(p)).font(.subheadline).foregroundStyle(Color.fg2).multilineTextAlignment(.trailing)
                #if os(macOS)
                Button(tr("改")) { editingCapital = true }.buttonStyle(.borderless).foregroundStyle(Color.shop).font(.subheadline)
                #endif
            }
            Bar(fraction: p.fraction, color: .shop, height: 6).padding(.top, 8)
        } else {
            HStack {
                #if os(macOS)
                Text(tr("还没填开店本钱，填了就能算什么时候回本。")).font(.subheadline).foregroundStyle(Color.fg2)
                Spacer(minLength: 12)
                Button(tr("填本钱")) { editingCapital = true }.buttonStyle(.borderless).foregroundStyle(Color.shop).font(.subheadline.weight(.semibold))
                #else
                Text(tr("在 Mac 上 设置 → 生意模式 填开店本钱，就能算什么时候回本。")).font(.subheadline).foregroundStyle(Color.fg2)
                #endif
            }
        }
    }

    private func estimate(_ p: CapitalProgress) -> String {
        switch p.estimate {
        case .done: return tr("已经回本了")
        case .tooEarly: return tr("开店不满 1 个月，还估不出来")
        case .notRecovering: return tr("最近 3 个月没赚到钱，还估不出来")
        case .months(let n): return tr("大约还要 \(n) 个月")
        }
    }

    // MARK: 三个小数字

    private func stats(_ r: BusinessReport?, book: String?) -> some View {
        let owe = book.map { Plans.obligations(model.ledger, asOf: .today, bookID: $0).iOwe } ?? .zero
        return HStack(alignment: .top, spacing: 28) {
            stat(tr("今天进账"), r?.todayIncome ?? .zero)
            stat(tr("每月固定"), r?.fixedTotal ?? .zero)
            SectionLink(section: .debts) { stat(tr("店里欠款"), owe) }
        }
    }

    private func stat(_ title: String, _ money: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Color.fg2)
            Text(money.rounded).font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit()).foregroundStyle(Color.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// 首页那两个大按钮：实心是「记进账」，浅色是「记开销」。
    func bigButton(filled: Bool) -> some View {
        self.font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(filled ? Color.white : Color.shop)
            .background(filled ? Color.shop : Color.shopSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
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
