import Charts
import FinanceCore
import SwiftUI

/// 生意首页（ming 2026-11-25：「生活这边升级的很好看，生意这边设计的就一般」——照生活总览的样子做，同一套组件，只换内容）。
/// 最上面夏夏卡叠；左边大卡「这个月真正赚了」+ 一句比上月 + 进账/花掉 + 累计赚钱线；右栏今天的账、回本、给自己发了、最近流水。
/// 不放交税、不放「够不够付房租」提醒块（ming 2026-11-25 都不要）。算账规矩都在 FinanceCore。
struct BusinessHome: View {
    @Environment(LedgerModel.self) var model
    @State private var editingCapital = false
    /// 窗口矮（最小 1000×612）：线图收矮、最近流水不放，一屏放下。
    @State private var short = false
    /// 回本那天庆祝一下，点「收起」后这张卡就不再出现（按生意账本记在这台设备上）。
    @AppStorage("xiaxia.paybackCardHidden") private var paybackHidden = ""

    var body: some View {
        let today = LocalDate.today
        let month = model.shownMonth
        let report = try? model.ledger.businessReport(month: month, today: today)
        let progress = model.ledger.capitalProgress(today: today)
        // ming 2026-11-25：生意首页不要最上面那叠夏夏点评卡，大数字就是整页的重心。
        VStack(alignment: .leading, spacing: Kit.gap) {
            Columns {
                heroCard(report, month: month, today: today)
            } side: {
                if month == today.yearMonth { todayCard(today) }
                if let p = progress, paybackHidden != (model.ledger.businessBook?.id ?? "") { paybackCard(p) }
                homeCard(report)
                if !short { recentCard }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.height < 700 } action: { short = $0 }
        #if os(macOS)
        .sheet(isPresented: $editingCapital) { CapitalEditor().environment(model) }
        #endif
    }

    // MARK: 这个月真正赚了

    private func heroCard(_ r: BusinessReport?, month: YearMonth, today: LocalDate) -> some View {
        let current = month == today.yearMonth
        let profit = r?.profit ?? .zero
        let word = profit.isExpense ? tr("亏了") : tr("真正赚了")
        let label = current ? tr("\(month.month) 月\(word) · 截至 \(today.day) 日") : tr("\(month.month) 月\(word)")
        let line = model.ledger.businessDailyProfit(month: month, today: today)
        let last = model.ledger.businessDailyProfit(month: month.adding(months: -1), today: today)
        return VStack(alignment: .leading, spacing: short ? 8 : 14) {
            KeyFigure(label: label, money: profit.magnitude, color: profit.isExpense ? .alert : .primary,
                      sentence: sentence(r, current: current),
                      spoken: tr("\(label) \(profit.magnitude.spoken)")) {
                if let r { InOutPair(income: r.income, expense: -r.cost).padding(.top, 4) }
            }
            if line.isEmpty || r?.income == .zero && r?.cost == .zero {
                Text(tr("这个月还没有店里的账。每天关店后点「记今天的账」，这里就会画出这个月赚钱的线。"))
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            } else {
                ProfitPaceChart(points: line, lastMonth: last, days: month.dayCount, current: current, height: short ? 90 : 240)
            }
        }
        .kitCard(padding: short ? 14 : 20)
    }

    private func sentence(_ r: BusinessReport?, current: Bool) -> Text {
        let fixed = Text(tr("房租、工资这些固定开销已经扣掉了。")).foregroundColor(.fg2)
        guard let r else { return fixed }
        let than = current ? tr("上月同期") : tr("上个月")
        let d = r.changeFromPrevious
        if d.cents == 0 { return Text(tr("和\(than)赚得一样。")) + fixed }
        return Text(tr("比\(than)\(d.isIncome ? tr("多赚") : tr("少赚")) ")) + em(d.magnitude.rounded, d.isIncome ? .good : .bad) + Text(tr("。")) + fixed
    }

    // MARK: 今天的账

    private func todayCard(_ today: LocalDate) -> some View {
        let t = model.ledger.dailyTakings(on: today)
        let done = t.total > .zero
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(tr("今天的账"))
            if done {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                    Text(tr("今天收了 ")) + Text(t.total.rounded).fontWeight(.semibold)
                }
                .font(.callout)
                Text(tr("现金 \(t.cash.rounded) · 刷卡 \(t.card.rounded)")).font(.caption).foregroundStyle(Color.fg2)
            } else {
                Text(tr("关店后记一下今天收了多少：现金、刷卡各填一个数。"))
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { model.sheet = .daily } label: {
                    Label(done ? tr("又收了一些") : tr("记今天的账"), systemImage: done ? "plus" : "square.and.pencil")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).tint(Color.shopSolid).controlSize(.large)
                .accessibilityIdentifier("business.daily")
                // 店里花了钱（进货、修东西）：直接开记一笔，已经选好生意账本、是支出。
                Button { model.addWith(AddPreset(income: false, category: nil, bookID: model.ledger.businessBook?.id)) } label: {
                    Label(tr("记开销"), systemImage: "minus.circle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.bordered).tint(Color.shop).controlSize(.large)
                .accessibilityIdentifier("business.expense")
            }
        }
        .kitCard()
    }

    // MARK: 回本

    @ViewBuilder private func paybackCard(_ p: CapitalProgress) -> some View {
        if case .done = p.estimate {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40)).symbolRenderingMode(.hierarchical).foregroundStyle(Color.shop)
                    .symbolEffect(.bounce, value: p.fraction)
                Text(tr("回本了！")).font(.title3.weight(.bold))
                Text(tr("开店的本钱全赚回来了，以后赚的都是净赚。"))
                    .font(.callout).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("收起这张卡")) {
                    withAnimation(.snappy) { paybackHidden = model.ledger.businessBook?.id ?? "" }
                }
                .buttonStyle(.soft)
            }
            .frame(maxWidth: .infinity)
            .kitCard()
        } else {
            HStack(spacing: 16) {
                GoalRing(fraction: p.fraction, color: .shop, lineWidth: 10, caption: tr("回本"))
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("开店本钱")).font(.headline)
                    Text(tr("还差 ")) + Text(p.remaining.rounded).fontWeight(.semibold)
                    Text(estimate(p)).font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                    #if os(macOS)
                    Button(tr("改本钱")) { editingCapital = true }.buttonStyle(.link).font(.caption).padding(.top, 2)
                    #endif
                }
                Spacer(minLength: 0)
            }
            .kitCard()
        }
    }

    private func estimate(_ p: CapitalProgress) -> String {
        switch p.estimate {
        case .done: return tr("已经回本了")
        case .tooEarly: return tr("开店不满 1 个月，还估不出来")
        case .notRecovering: return tr("最近 3 个月没赚到钱，还估不出来")
        case .months(let n): return tr("照最近的速度，大约还要 \(n) 个月")
        }
    }

    // MARK: 给自己发了

    private func homeCard(_ r: BusinessReport?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "house.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.shop)
                .frame(width: 34, height: 34).background(Color.shopSoft, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("这个月给自己发了")).font(.caption).foregroundStyle(Color.fg2)
                Text((r?.takenHome ?? .zero).rounded).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            Spacer(minLength: 8)
            Button { model.sheet = .sideTransfer } label: { Label(tr("拿钱回家"), systemImage: "arrow.right") }
                .buttonStyle(.soft)
                .help(tr("从店里的账户转到生活那边的账户，算给自己发了"))
        }
        .kitCard()
    }

    // MARK: 最近流水（店里的）

    private var recentCard: some View {
        let recent = Array(model.visibleTransactions.filter { $0.flow != .opening && $0.flow != .`internal` }.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: tr("店里最近的账")) {
                MoreLink(title: tr("全部"), section: .transactions)
            }
            .padding(.bottom, 4)
            if recent.isEmpty {
                Text(tr("还没有。")).font(.callout).foregroundStyle(Color.fg2)
            }
            ForEach(recent) { t in
                TxRow(tx: t, showDate: true)
                if t.id != recent.last?.id { Divider().padding(.leading, 44) }
            }
        }
        .kitCard()
    }
}

// MARK: - 这个月累计赚了（和生活那边的花钱速度线同一个画法）

/// 实线是这个月每天累计赚了多少（可能是负的），虚线是上个月同一天。
struct ProfitPaceChart: View {
    let points: [Money]
    let lastMonth: [Money]
    let days: Int
    let current: Bool
    var height: CGFloat = 170
    private var compact: Bool { height < 100 }

    private struct P: Identifiable { let day: Int; let v: Double; var id: Int { day } }

    var body: some View {
        let now = points.enumerated().map { P(day: $0.offset + 1, v: Double($0.element.cents) / 100) }
        let before = lastMonth.enumerated().map { P(day: $0.offset + 1, v: Double($0.element.cents) / 100) }
        let all = (now + before).map(\.v) + [0]
        let lo = min(0, all.min() ?? 0), hi = max(10, all.max() ?? 0)
        let pad = (hi - lo) * 0.12
        let today = now.last
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                legend(Color.shop, tr("这个月累计赚了"), dashed: false)
                legend(Color.fg3, tr("上月同期"), dashed: true)
            }
            .font(.caption).foregroundStyle(Color.fg2)
            Chart {
                ForEach(before) { p in
                    LineMark(x: .value(tr("日"), p.day), y: .value(tr("赚了"), p.v), series: .value(tr("线"), tr("上月")))
                        .foregroundStyle(Color.fg3)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                ForEach(now) { p in
                    AreaMark(x: .value(tr("日"), p.day), yStart: .value(tr("零"), 0), yEnd: .value(tr("赚了"), p.v))
                        .foregroundStyle(LinearGradient(colors: [Color.shop.opacity(0.22), Color.shop.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value(tr("日"), p.day), y: .value(tr("赚了"), p.v), series: .value(tr("线"), tr("本月")))
                        .foregroundStyle(Color.shop)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                if lo < 0 { RuleMark(y: .value(tr("零"), 0)).foregroundStyle(Color.fg3.opacity(0.4)) }
                if let t = today {
                    PointMark(x: .value(tr("日"), t.day), y: .value(tr("赚了"), t.v))
                        .foregroundStyle(Color.shop).symbolSize(50)
                        .annotation(position: .topLeading, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if !compact {
                                Text("\(current ? tr("今天") : tr("月底")) \(Money(cents: Int64(t.v * 100)).rounded)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(Color.cardBackground.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                                    .fixedSize()
                            }
                        }
                }
            }
            .chartXScale(domain: 1...max(days, 2))
            .chartYScale(domain: (lo - (lo < 0 ? pad : 0))...(hi + pad))
            .chartXAxis {
                AxisMarks(values: [1, 10, 20, days]) { v in
                    AxisValueLabel { if let d = v.as(Int.self) { Text(tr("\(d)日")) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: compact ? 2 : 4)) { v in
                    AxisGridLine().foregroundStyle(Color.fg3.opacity(0.18))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Money(cents: Int64(d * 100)).rounded.replacingOccurrences(of: " €", with: "")) } }
                }
            }
            .frame(height: height)
            .revealFromLeading()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("这个月累计赚钱的线：到今天 \(points.last?.rounded ?? "0")，上月同一天 \(lastMonth.indices.contains(points.count - 1) ? lastMonth[points.count - 1].rounded : "—")。"))
        }
    }

    private func legend(_ color: Color, _ title: String, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: dashed ? 8 : 12, height: 2.5)
            Text(title)
        }
    }
}

// MARK: - 每天记账

/// 每天记账（ming 2026-11-25 定的方向）：一屏两个框，现金、刷卡各填今天收了多少；下面带出今天花了、今天赚了没。
/// 「今天赚了没」只在这一屏出现，首页不放。
struct DailyTakingsSheet: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    /// 每种收款方式填的数（按收款方式的 id）。
    @State private var texts: [UUID: String] = [:]
    /// 这次记到哪个账户（默认是收款方式自己的账户，可以临时换）。
    @State private var accounts: [UUID: String] = [:]
    @State private var date = Date()
    @State private var error: String?
    @State private var adding = false
    @State private var newName = ""
    @State private var newAccount = ""
    @FocusState private var focus: UUID?
    @FocusState private var newNameFocused: Bool

    private var day: LocalDate { LocalDate(date) }
    private var methods: [PaymentMethod] { model.ledger.paymentMethods }

    private func value(_ m: PaymentMethod) -> Money? {
        let t = (texts[m.id] ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? .zero : Money.evaluate(t)
    }
    private var lines: [(method: PaymentMethod, amount: Money)]? {
        var out: [(method: PaymentMethod, amount: Money)] = []
        for m in methods {
            guard let v = value(m), v >= .zero else { return nil }
            var x = m
            x.accountID = accounts[m.id] ?? m.accountID
            out.append((x, v))
        }
        return out
    }
    private var typed: Money { (lines ?? []).reduce(.zero) { $0 + $1.amount } }
    private var canSave: Bool {
        guard let lines, typed > .zero else { return false }
        return lines.allSatisfy { $0.amount == .zero || !$0.method.accountID.isEmpty }
    }

    /// 选账户：店里的账户在前；一个都没有就列全部（不含私房钱）。
    private var choices: [Account] {
        let shop = Set(model.ledger.businessAccountIDs)
        let open = model.ledger.accounts.filter { !$0.isPrivate }
        let mine = open.filter { shop.contains($0.id) }
        return mine.isEmpty ? open : mine
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { content.padding(20) }
            Divider()
            HStack(spacing: 10) {
                Button(tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                Spacer()
                Button(action: save) {
                    Text(tr("记下")).font(.headline).padding(.vertical, 6).frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent).tint(Color.shopSolid).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .accessibilityIdentifier("daily.save")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        #if os(macOS)
        .frame(width: 480)
        #endif
        .navigationTitle(tr("记今天的账"))
        .onAppear { focus = methods.first?.id }
    }

    private var content: some View {
        let already = model.ledger.dailyTakings(on: day)
        let report = try? model.ledger.businessReport(month: day.yearMonth, today: day)
        let spent = report?.todayCost ?? .zero
        let received = already.total + typed
        let earned = received - spent
        return VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(tr("今天收了多少")).font(.title2.weight(.bold))
                DatePicker(tr("哪天"), selection: $date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden().fixedSize()
            }
            // 每种收款方式一行：名字、多少、进哪个账户。Tab 一行行往下填（ming 2026-11-25：能加更多收款方式）。
            VStack(spacing: 0) {
                ForEach(Array(methods.enumerated()), id: \.element.id) { i, m in
                    methodRow(m)
                    if i < methods.count - 1 { Divider() }
                }
                Divider()
                addRow
            }
            .padding(.horizontal, 14)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous).strokeBorder(Color.fg3.opacity(0.25)))
            if already.total > .zero {
                Label(tr("这天已经记了 \(already.total.rounded)，这次填的会接着加上。"), systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Color.income)
            }
            VStack(spacing: 8) {
                row(tr("收了"), received.rounded)
                row(tr("花了（这天记的开销）"), (-spent).rounded)
                Divider()
                // 还没填收入时不下「亏了」的结论，免得一打开就吓人。
                let undecided = received == .zero && already.total == .zero
                HStack {
                    Text(undecided ? tr("填了收入就算赚没赚") : earned.isExpense ? tr("这天亏了") : tr("这天赚了")).font(.headline)
                        .foregroundStyle(undecided ? Color.fg2 : Color.primary)
                    Spacer()
                    Text(undecided ? "—" : earned.magnitude.rounded).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                        .foregroundStyle(undecided ? Color.fg3 : earned.isExpense ? Color.alert : Color.income)
                        .contentTransition(.numericText(value: Double(earned.cents)))
                        .animation(.snappy, value: earned)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(16)
            .background(Color.sunken.opacity(0.6), in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
            if let error { Text(error).font(.caption).foregroundStyle(Color.alert) }
            Text(tr("都算营业收入，空着的不记。右键一种收款方式可以拿掉。"))
                .font(.caption).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func symbol(_ m: PaymentMethod) -> String {
        if m.id == PaymentMethod.cashID || m.name.contains("现金") { return "banknote" }
        if m.id == PaymentMethod.cardID || m.name.contains("卡") { return "creditcard" }
        return "iphone.gen3"
    }

    private func methodRow(_ m: PaymentMethod) -> some View {
        let account = Binding(get: { accounts[m.id] ?? m.accountID }, set: { accounts[m.id] = $0 })
        return HStack(spacing: 10) {
            Image(systemName: symbol(m)).foregroundStyle(Color.shop).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(trKey(m.name)).font(.callout.weight(.semibold))
                Picker(tr("记到"), selection: account) {
                    if account.wrappedValue.isEmpty { Text(tr("选账户")).tag("") }
                    ForEach(choices) { a in Text(a.name).tag(a.id) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize().font(.caption).tint(Color.shop)
                #if os(macOS)
                .buttonStyle(.borderless)
                #endif
            }
            Spacer(minLength: 8)
            TextField("0", text: Binding(get: { texts[m.id] ?? "" }, set: { texts[m.id] = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
                .focused($focus, equals: m.id)
                .onSubmit(save)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityLabel(tr("\(trKey(m.name))收了多少"))
                .accessibilityIdentifier(m.id == PaymentMethod.cashID ? "daily.cash" : m.id == PaymentMethod.cardID ? "daily.card" : "daily.\(m.name)")
            Text("€").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Color.fg3)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { focus = m.id }
        .contextMenu {
            if methods.count > 1 {
                Button(role: .destructive) { model.perform { try $0.removePaymentMethod(m.id, author: model.author) } } label: {
                    Label(tr("拿掉这种收款方式"), systemImage: "minus.circle")
                }
            }
        }
    }

    @ViewBuilder private var addRow: some View {
        if adding {
            HStack(spacing: 8) {
                TextField(tr("叫什么"), text: $newName, prompt: Text(tr("比如 Bizum、外卖平台")))
                    .textFieldStyle(.roundedBorder)
                    .focused($newNameFocused)
                    .onSubmit(addMethod)
                Picker(tr("进哪个账户"), selection: $newAccount) {
                    ForEach(choices) { a in Text(a.name).tag(a.id) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Button(tr("加上"), action: addMethod).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newAccount.isEmpty)
                Button { adding = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.fg3) }
                    .buttonStyle(.plain).accessibilityLabel(tr("不加了"))
            }
            .padding(.vertical, 10)
        } else {
            Button {
                newName = ""; newAccount = model.ledger.dailyAccounts().card ?? choices.first?.id ?? ""
                adding = true
                DispatchQueue.main.async { newNameFocused = true }
            } label: {
                Label(tr("加一种收款方式"), systemImage: "plus").font(.callout).foregroundStyle(Color.shop)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("daily.addMethod")
        }
    }

    private func addMethod() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !newAccount.isEmpty else { return }
        do {
            _ = try model.edit(quiet: true) { try $0.addPaymentMethod(name: n, accountID: newAccount, author: model.author) }
            adding = false
            if let m = methods.first(where: { $0.name == n }) { focus = m.id }
        } catch { self.error = error.localizedDescription }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.fg2)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func save() {
        guard let lines, canSave else { error = tr("金额看不懂，只填数字就行"); return }
        do {
            let change = try model.edit { try $0.recordDailyTakings(lines, date: day, author: model.author) }
            model.toast = LedgerModel.Toast(text: tr("记好了：收了 \(typed.rounded)"), changeID: change.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
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
                    .buttonStyle(.borderedProminent).tint(Color.shopSolid)
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
