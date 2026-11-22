import FinanceCore
import SwiftUI

// 订阅（计划页）：每月固定在扣多少、下次哪天扣、快到的和涨价的标出来；流水里像订阅的列在下面，点「加上」确认后登记。

/// 订阅卡片。Mac 在计划页右栏，iPhone 在计划页「订阅」那一格。
struct SubscriptionsCard: View {
    @Environment(LedgerModel.self) var model
    @State private var editing: SubscriptionDraft?
    @State private var confirmDelete: Subscription?
    @State private var showCancelled = false

    var body: some View {
        let all = model.subscriptionStatus
        let book = model.selectedBookID
        let shown = all.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        let active = shown.filter { $0.cancelledOn == nil }
        let stopped = shown.filter { $0.cancelledOn != nil }
        let totals = Subscriptions.totals(shown, bookID: book)
        let found = model.subscriptionCandidates.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        let base = model.ledger.baseCurrency

        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "订阅") {
                HStack(spacing: 10) {
                    if !active.isEmpty { Text("按下次扣款排").font(.caption).foregroundStyle(Color.fg2) }
                    Button { editing = SubscriptionDraft(model: model) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("登记一个订阅")
                        .accessibilityLabel("登记订阅")
                        .accessibilityIdentifier("addSubscription")
                }
            }

            if active.isEmpty {
                Text(found.isEmpty ? "会员、软件、健身房、云盘……每月或每年固定扣的钱，登记在这里，就知道一个月一共在扣多少。"
                                   : "还没有登记订阅。下面是流水里看着像订阅的，点「加上」确认一下。")
                    .font(.subheadline).foregroundStyle(Color.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { totalsText(totals, base: base) }
                    VStack(alignment: .leading, spacing: 2) { totalsText(totals, base: base) }
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: 0) {
                    ForEach(active) { s in
                        row(s)
                        if s.id != active.last?.id { Divider().padding(.leading, 44) }
                    }
                }
            }

            if !found.isEmpty {
                Divider().padding(.vertical, 2)
                Label("流水里像订阅的 \(found.count) 个", systemImage: "sparkle.magnifyingglass")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.ai)
                ForEach(found.prefix(6)) { c in candidateRow(c) }
                if found.count > 6 {
                    Text("还有 \(found.count - 6) 个，跟夏夏说「帮我把流水里的订阅都找出来」一起处理。")
                        .font(.caption).foregroundStyle(Color.fg2)
                }
            }

            if !stopped.isEmpty {
                DisclosureGroup(isExpanded: $showCancelled) {
                    VStack(spacing: 0) { ForEach(stopped) { row($0) } }
                } label: {
                    Text("已经停了的 \(stopped.count) 个").font(.caption).foregroundStyle(Color.fg2)
                }
            }
        }
        .kitCard()
        .sheet(item: $editing) { draft in
            NavigationStack { SubscriptionEditor(draft: draft) }
                .environment(model)
                #if os(macOS)
                .frame(width: 480, height: 520)
                #endif
        }
        .confirmationDialog("删除订阅「\(confirmDelete?.name ?? "")」？", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let s = confirmDelete { model.perform { try $0.removeSubscription(s.id, author: model.author) } }
                confirmDelete = nil
            }
        } message: { Text("只删登记，不动流水。不再续费请用「不续了」，能留着记录。删错了可以撤销。") }
    }

    @ViewBuilder private func totalsText(_ t: SubscriptionTotals, base: String) -> some View {
        Text(t.monthly.formatted(in: base))
            .font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
            .contentTransition(.numericText(value: Double(t.monthly.cents)))
        Text("每月固定在扣 · 一年约 \(roundedText(t.yearly, base))")
            .font(.subheadline).foregroundStyle(Color.fg2)
    }

    private func roundedText(_ m: Money, _ code: String) -> String {
        Money(cents: (m.cents + 50) / 100 * 100).formatted(in: code).replacingOccurrences(of: ",00 ", with: " ")
    }

    private func row(_ s: SubscriptionStatus) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: s.category ?? "订阅")
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name).font(.callout.weight(.medium)).lineLimit(1)
                    .foregroundStyle(s.cancelledOn == nil ? Color.primary : Color.fg3)
                Text(detail(s)).font(.caption).foregroundStyle(s.priceChanged ? Color.alert : Color.fg2).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(s.amount.formatted(in: s.currency)).font(.kitAmount).lineLimit(1)
                    .foregroundStyle(s.cancelledOn == nil ? Color.primary : Color.fg3)
                if s.currency != model.ledger.baseCurrency, s.cancelledOn == nil {
                    Text("≈ " + model.ledger.toBase(s.amount, currency: s.currency, on: .today).formatted(in: model.ledger.baseCurrency))
                        .font(.caption2).foregroundStyle(Color.fg2)
                }
            }
            menu(s)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ s: SubscriptionStatus) -> String {
        var parts = [s.cycle.label]
        if let c = s.cancelledOn { parts.append("\(c.short)停了") }
        else if let n = s.nextDate, let d = s.daysLeft {
            parts.append("下次 \(n.short)" + (d == 0 ? "（今天）" : d <= 14 ? "（\(d) 天后）" : ""))
        }
        if s.priceChanged, let last = s.lastChargeAmount { parts.append("最近一次扣了 \(last.formatted(in: s.currency))，可能涨价了") }
        if let a = s.accountID, model.ledger.accounts.count > 1 { parts.append(model.accountName(a)) }
        return parts.joined(separator: " · ")
    }

    private func menu(_ s: SubscriptionStatus) -> some View {
        Menu {
            if let sub = model.ledger.subscriptions.first(where: { $0.id == s.id }) {
                Button { editing = SubscriptionDraft(sub, model: model) } label: { Label("改…", systemImage: "pencil") }
                if s.priceChanged, let last = s.lastChargeAmount {
                    Button {
                        var u = sub; u.amount = last
                        model.perform { try $0.editSubscription(u, author: model.author) }
                    } label: { Label("按最近一次改成 \(last.formatted(in: s.currency))", systemImage: "arrow.up.circle") }
                }
                if sub.isActive {
                    Button { model.perform { try $0.cancelSubscription(sub.id, author: model.author) } } label: {
                        Label("不续了", systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        var u = sub; u.cancelledOn = nil
                        model.perform { try $0.editSubscription(u, author: model.author) }
                    } label: { Label("又续上了", systemImage: "arrow.clockwise.circle") }
                }
                Button(role: .destructive) { confirmDelete = sub } label: { Label("删除…", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(Color.fg2)
        }
        .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        .accessibilityLabel("\(s.name) 的操作")
    }

    private func candidateRow(_ c: SubscriptionCandidate) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: c.category ?? "订阅", size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.callout).lineLimit(1)
                Text("\(c.cycle.label) \(c.amount.formatted(in: c.currency)) · 扣过 \(c.count) 次，最近 \(c.lastDate.short)")
                    .font(.caption).foregroundStyle(Color.fg2).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("加上") { editing = SubscriptionDraft(candidate: c, model: model) }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityLabel("把 \(c.name) 登记成订阅")
        }
        .padding(.vertical, 4)
    }
}

/// 编辑窗口里的草稿：新登记、从流水里认出来的、改已有的。
struct SubscriptionDraft: Identifiable {
    let id = UUID()
    var existing: Subscription?
    var name = ""
    var amountText = ""
    var currency: String
    var cycle: Subscription.Cycle = .monthly
    var nextDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    var accountID = ""
    var bookID = ""
    var category = ""
    var match = ""
    var note = ""

    @MainActor init(model: LedgerModel) {
        currency = model.ledger.baseCurrency
        bookID = model.selectedBookID ?? ""
    }

    @MainActor init(_ s: Subscription, model: LedgerModel) {
        existing = s
        name = s.name
        currency = s.currency ?? s.accountID.map { model.ledger.currency(ofAccount: $0) } ?? model.ledger.baseCurrency
        amountText = s.amount.formatted(in: currency).components(separatedBy: " ").first ?? ""
        cycle = s.cycle
        nextDate = Subscriptions.upcoming(s, today: .today).asDate
        accountID = s.accountID ?? ""
        bookID = s.bookID ?? ""
        category = s.category ?? ""
        match = s.match ?? ""
        note = s.note ?? ""
    }

    @MainActor init(candidate c: SubscriptionCandidate, model: LedgerModel) {
        name = c.name
        currency = c.currency
        amountText = c.amount.formatted(in: c.currency).components(separatedBy: " ").first ?? ""
        cycle = c.cycle
        nextDate = c.nextDate.asDate
        accountID = c.accountID
        bookID = c.bookID ?? ""
        category = c.category ?? ""
        match = c.key
    }
}

/// 登记 / 改一个订阅。
struct SubscriptionEditor: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var draft: SubscriptionDraft
    @State private var error: String?

    init(draft: SubscriptionDraft) { _draft = State(initialValue: draft) }

    private var amount: Money? {
        guard let m = Money(parsing: draft.amountText.replacingOccurrences(of: " ", with: "")), m.cents != 0 else { return nil }
        return m.magnitude
    }

    var body: some View {
        Form {
            Section {
                FormField("名字", "比如「视频会员」", text: $draft.name)
                HStack {
                    FormField("每次扣多少", "比如 13,99", text: $draft.amountText).decimalKeyboard()
                    Picker("币种", selection: $draft.currency) {
                        ForEach(currencyChoices, id: \.self) { Text(Currencies.info($0).symbol + " " + Currencies.info($0).name).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .accessibilityLabel("币种")
                }
                Picker("多久扣一次", selection: $draft.cycle) {
                    ForEach(Subscription.Cycle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                DatePicker("下次哪天扣", selection: $draft.nextDate, displayedComponents: .date)
            } footer: {
                if let amount { Text(verbatim: footer(amount)) }
            }
            Section {
                Picker("从哪个账户扣", selection: $draft.accountID) {
                    Text("不指定").tag("")
                    ForEach(model.visibleAccounts) { Text($0.name).tag($0.id) }
                }
                if model.ledger.books.count > 1 {
                    Picker("账本", selection: $draft.bookID) {
                        Text("不指定").tag("")
                        ForEach(model.ledger.books) { Text($0.name).tag($0.id) }
                    }
                }
                FormField("分类", "比如「娱乐」", text: $draft.category)
                FormField("流水里怎么认它", "商户名，比如 netflix", text: $draft.match)
            } footer: {
                Text("写上商户名，app 会在流水里找它最近一次扣了多少；和登记的不一样会提醒你可能涨价了。")
            }
            if draft.existing != nil {
                Section { FormField("备注", "可以不填", text: $draft.note) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.existing == nil ? "登记订阅" : "改订阅")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(amount == nil || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: draft.accountID) { _, id in
            // 选了外币账户：币种跟着账户走。
            if !id.isEmpty { draft.currency = model.ledger.currency(ofAccount: id) }
        }
        .errorAlert($error)
    }

    private var currencyChoices: [String] {
        var list = [model.ledger.baseCurrency] + model.ledger.foreignCurrencies.sorted()
        for c in ["EUR", "USD", "CNY", "GBP"] where !list.contains(c) { list.append(c) }
        if !list.contains(draft.currency) { list.append(draft.currency) }
        return list
    }

    private func footer(_ amount: Money) -> String {
        let base = model.ledger.baseCurrency
        let monthly = perMonth(amount)
        var text = "\(draft.cycle.label) \(amount.formatted(in: draft.currency))"
        if draft.cycle != .monthly { text += "，摊到每月约 \(monthly.formatted(in: draft.currency))" }
        if draft.currency != base {
            text += "，约合 \(model.ledger.toBase(amount, currency: draft.currency, on: .today).formatted(in: base))"
        }
        return text + "。"
    }

    private func perMonth(_ m: Money) -> Money {
        switch draft.cycle {
        case .weekly: Money(cents: m.cents * 52 / 12)
        case .monthly: m
        case .quarterly: Money(cents: m.cents / 3)
        case .yearly: Money(cents: m.cents / 12)
        }
    }

    private func save() {
        guard let amount else { return }
        let accountCurrency = draft.accountID.isEmpty ? model.ledger.baseCurrency : model.ledger.currency(ofAccount: draft.accountID)
        func opt(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
        var s = draft.existing ?? Subscription(name: "", amount: amount, cycle: draft.cycle, nextDate: .today)
        s.name = draft.name.trimmingCharacters(in: .whitespaces)
        s.amount = amount
        s.currency = draft.currency == accountCurrency ? nil : draft.currency
        s.cycle = draft.cycle
        s.nextDate = LocalDate(draft.nextDate)
        s.accountID = opt(draft.accountID)
        s.bookID = opt(draft.bookID)
        s.category = opt(draft.category)
        s.match = opt(draft.match)
        s.note = opt(draft.note)
        let author = model.author
        do {
            if draft.existing == nil {
                try model.edit { try $0.addSubscription(s, author: author) }
            } else if s != draft.existing {
                try model.edit { try $0.editSubscription(s, author: author) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

extension LedgerModel {
    /// 订阅现在的状态（下次哪天、合计、涨价）。
    var subscriptionStatus: [SubscriptionStatus] { Subscriptions.status(ledger) }
    /// 流水里像订阅、还没登记的。私房钱藏着时不列私房钱账户的。
    var subscriptionCandidates: [SubscriptionCandidate] {
        let hidden = hiddenAccounts
        return Subscriptions.detect(ledger).filter { !hidden.contains($0.accountID) }
    }
}
