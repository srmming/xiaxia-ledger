import FinanceCore
import SwiftUI

// 订阅（Mac 侧栏单独一页「订阅」，iPhone 在计划页「订阅」那一格）：每月固定在扣多少、下次哪天扣、快到的和涨价的标出来；流水里像订阅的列在下面，点「加上」确认后登记。

/// 订阅页（Mac）。ming 2026-11-23：「订阅要单独拆解出来」「放在一个导航页上面」；同一天又定了只回答
/// 「我每月固定被扣多少，有没有白花的？」：最上面夏夏点名可以考虑退的；顶上固定每月共多少、一年共多少、这周要扣几笔；
/// 左边清单按下次扣款排、一行一个（行矮，一屏放 10 来个），多了分组折叠；右边快要扣的分期、流水里像订阅的、问夏夏。
struct SubscriptionsPage: View {
    @Environment(LedgerModel.self) var model
    @State private var viewport = CGSize(width: 1000, height: 800)

    var body: some View {
        let book = model.selectedBookID
        // 7 天内要扣的分期（ming 2026-11-23：分期快扣了也在这里提一句）。订阅自己的在左边清单「这周要扣」里。
        let soon = Plans.installmentsDue(model.ledger, today: .today, within: 7).filter { book == nil || $0.bookID == book }
        let found = model.subscriptionCandidates.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        let short = Viewport.isShort(viewport)
        VStack(alignment: .leading, spacing: Kit.gap) {
            SubscriptionsXiaxia()
            if model.subscriptionStatus.contains(where: { $0.cancelledOn == nil }) { SubscriptionTotalsStrip(compact: short) }
            Columns(sideWidth: 340) {
                SubscriptionsCard(part: .list, maxRows: short ? 4 : 11, compact: short)
            } side: {
                if !soon.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("分期也快扣了")
                        ForEach(soon) { s in
                            HStack(spacing: 10) {
                                CategoryIcon(category: "分期", size: 26)
                                Text(s.name).font(.callout.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(Nudges.dayWord(s.daysLeft)).font(.caption).foregroundStyle(s.daysLeft <= 3 ? Color.warn : Color.fg2)
                                Text(s.amount.ui(in: s.currency)).font(.kitAmount).lineLimit(1)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .kitCard()
                }
                if !found.isEmpty { SubscriptionsCard(part: .found, maxFound: short ? 3 : 6) }
                // 窗口矮又有「流水里像订阅的」时，问夏夏那张先不放（夏夏卡上已经有按钮），一屏放下。
                if !(short && !found.isEmpty) {
                AskAICard(title: "让夏夏帮你看订阅", note: nil, page: "订阅", prompts: Array(model.prompts(for: .subscriptions).prefix(found.isEmpty ? 3 : 2)))
                }
            }
        }
        .kitPage()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
    }
}

/// 订阅页最上面的夏夏：点名「可以考虑退」的，没有就说快要扣的。
struct SubscriptionsXiaxia: View {
    @Environment(LedgerModel.self) var model

    var body: some View {
        let book = model.selectedBookID
        let list = model.subscriptionStatus.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        XiaxiaSays(page: "subscriptions", pageName: "订阅", sentence: sentence(list),
                   question: "帮我看看我的订阅：哪些涨价了、哪些可能很久没用、退掉哪个最划算？一个一个问我常不常用，我说很少用的用 edit_subscription 标 rarely_used=true。")
    }

    private func sentence(_ list: [SubscriptionStatus]) -> String {
        let active = list.filter { $0.cancelledOn == nil }
        let base = model.ledger.baseCurrency
        guard !active.isEmpty else { return model.voiced("还没有登记订阅。让我从流水里找找？", .neutral) }
        let review = active.filter(\.worthReviewing)
        let p = model.persona
        if !review.isEmpty {
            let names = review.prefix(2).map { s -> String in
                s.priceUp ? "「\(s.name)」刚涨价" : "「\(s.name)」你说很少用"
            }.joined(separator: "，")
            let monthly = review.reduce(Money.zero) { $0 + $1.monthlyBase }
            let more = review.count > 2 ? "，还有 \(review.count - 2) 个" : ""
            // 一句话说完（每月多少顶上那条有），夏夏卡矮一点，一屏放得下。
            let s = "\(names)\(more)，一年加起来 \(Money(cents: monthly.cents * 12).rounded)，可以考虑退。"
            return switch p {
            case .sharp: s + "不用还交钱，图什么？"
            case .cheer: s + "退掉的钱拿去存目标吧～"
            case .gentle: s + "要我帮你一个个看看吗？"
            case .calm: s
            }
        }
        if let next = active.first(where: \.isDueVerySoon), let d = next.daysLeft {
            return model.voiced("「\(next.name)」\(Nudges.dayWord(d))扣 \(next.amount.ui(in: next.currency))，账户里留够钱。", .neutral)
        }
        let t = Subscriptions.totals(active)
        return model.voiced("每月固定扣 \(t.monthly.ui(in: base))，一年约 \(t.yearly.rounded)。暂时没看到白花的。", .good)
    }
}

/// 订阅页顶上固定的一条：每月共多少、一年共多少、这周要扣几笔。
struct SubscriptionTotalsStrip: View {
    @Environment(LedgerModel.self) var model
    /// 窗口矮：数字小一号、卡片边距小一点。
    var compact = false
    @State private var adding: SubscriptionDraft?

    var body: some View {
        let book = model.selectedBookID
        let list = model.subscriptionStatus.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        let t = Subscriptions.totals(list, bookID: book)
        let base = model.ledger.baseCurrency
        HStack(alignment: .top) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) { figures(t, base, size: compact ? 26 : 32) }
                HStack(alignment: .top, spacing: 18) { figures(t, base, size: 24) }
                VStack(alignment: .leading, spacing: 8) { figures(t, base, size: 24) }
            }
            Spacer(minLength: 12)
            Button { adding = SubscriptionDraft(model: model) } label: { Label("登记订阅", systemImage: "plus") }
                .buttonStyle(.soft)
                .help("登记一个订阅")
        }
        .kitCard(padding: compact ? 14 : 18)
        .accessibilityElement(children: .contain)
        .sheet(item: $adding) { draft in
            NavigationStack { SubscriptionEditor(draft: draft) }
                .environment(model)
                #if os(macOS)
                .frame(width: 480, height: 520)
                #endif
        }
    }

    @ViewBuilder private func figures(_ t: SubscriptionTotals, _ base: String, size: CGFloat) -> some View {
        figure("每月共", t.monthly.ui(in: base), note: "\(t.activeCount) 个在续", color: .primary, size: size)
        figure("一年共", Money(cents: (t.yearly.cents + 50) / 100 * 100).rounded, note: "年付的也摊进来了", color: .primary, size: size)
        figure("这周要扣", "\(t.weekCount) 笔", note: t.weekCount > 0 ? "共 \(t.weekAmount.ui(in: base))" : "这周没有", color: t.weekCount > 0 ? .warn : .fg2, size: size)
        if t.reviewCount > 0 {
            figure("可以考虑退", "\(t.reviewCount) 个", note: "每月 \(t.reviewMonthly.ui(in: base))", color: .alert, size: size)
        }
    }

    private func figure(_ label: String, _ value: String, note: String, color: Color, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Color.fg2)
            Text(value).font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(color).fixedSize()
            Text(note).font(.caption).foregroundStyle(Color.fg3).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 订阅卡片。Mac 在「订阅」页，iPhone 在计划页「订阅」那一格。
struct SubscriptionsCard: View {
    @Environment(LedgerModel.self) var model
    /// Mac 订阅页把「流水里像订阅的」放到右栏，左边只放清单（一屏放下）；iPhone 一张卡全放。
    enum Part { case all, list, found }
    var part: Part = .all
    /// 不分组时最多列几行（Mac 矮窗口少列几行，一屏放下）；分组时只管展开的那组。
    var maxRows = 12
    /// 窗口矮：超过 maxRows 不分组，只列前几行，剩下的收进「还有 N 个」（分组展开会撑出一屏）。
    var compact = false
    /// 「流水里像订阅的」最多列几个。
    var maxFound = 6
    @State private var showMore = false
    @State private var editing: SubscriptionDraft?
    /// 分组折叠时哪些组是展开的。默认只展开「可以考虑退」和最近要扣的那一组。
    @State private var expanded: Set<String>?
    @State private var confirmDelete: Subscription?
    @State private var showCancelled = false

    var body: some View {
        let all = model.subscriptionStatus
        let book = model.selectedBookID
        let shown = all.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        let active = shown.filter { $0.cancelledOn == nil }
        let stopped = shown.filter { $0.cancelledOn != nil }
        let found = model.subscriptionCandidates.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        let base = model.ledger.baseCurrency

        VStack(alignment: .leading, spacing: 10) {
            if part != .found {
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
                let groups = Subscriptions.groups(shown)
                if active.count <= maxRows || compact {
                    // 不多：一个列表，可以考虑退的在最上面。窗口矮又多的：先列前几行，剩下的点开看。
                    let ordered = (groups.first { $0.kind == .review }?.items ?? []) + active.filter { !$0.worthReviewing }
                    let cut = active.count <= maxRows ? ordered.count : max(1, maxRows - 1)
                    VStack(spacing: 0) {
                        ForEach(ordered.prefix(cut)) { s in
                            row(s)
                            if s.id != ordered.prefix(cut).last?.id { Divider().padding(.leading, 36) }
                        }
                    }
                    if ordered.count > cut {
                        DisclosureGroup(isExpanded: $showMore) {
                            VStack(spacing: 0) {
                                ForEach(ordered.dropFirst(cut)) { s in
                                    Divider().padding(.leading, 36)
                                    row(s)
                                }
                            }
                        } label: {
                            Text("还有 \(ordered.count - cut) 个，往后扣的").font(.caption).foregroundStyle(Color.fg2)
                        }
                    }
                } else {
                    // 多了分组折叠：可以考虑退 / 这周要扣 / 这个月 / 下个月以后 / 年付和季付。
                    let open = expanded ?? Set([groups.first { $0.kind == .review }?.id, groups.first { $0.kind != .review }?.id].compactMap { $0 })
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(groups) { g in
                            DisclosureGroup(isExpanded: Binding(get: { open.contains(g.id) },
                                                                set: { on in var x = open; if on { x.insert(g.id) } else { x.remove(g.id) }; expanded = x })) {
                                VStack(spacing: 0) {
                                    ForEach(g.items) { s in
                                        row(s)
                                        if s.id != g.items.last?.id { Divider().padding(.leading, 36) }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(g.title).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(g.kind == .review ? Color.alert : Color.primary)
                                    Text("\(g.items.count) 个").font(.caption).foregroundStyle(Color.fg2)
                                    Spacer()
                                    Text(g.items.reduce(Money.zero) { $0 + $1.monthlyBase }.ui(in: base) + "/月")
                                        .font(.caption).foregroundStyle(Color.fg2).monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }

            }
            if !found.isEmpty && part != .list {
                if part == .all { Divider().padding(.vertical, 2) }
                Label("流水里像订阅的 \(found.count) 个", systemImage: "sparkle.magnifyingglass")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.ai)
                ForEach(found.prefix(maxFound)) { c in candidateRow(c) }
                if found.count > maxFound {
                    Text("还有 \(found.count - maxFound) 个，跟夏夏说「帮我把流水里的订阅都找出来」一起处理。")
                        .font(.caption).foregroundStyle(Color.fg2)
                }
            }

            if !stopped.isEmpty && part != .found {
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

    /// 一行一个，行矮（一屏放 10 来个）：图标、名字、金额、几天后扣；3 天内要扣的、可以考虑退的标出来。
    private func row(_ s: SubscriptionStatus) -> some View {
        let stopped = s.cancelledOn != nil
        return HStack(spacing: 10) {
            CategoryIcon(category: subscriptionIcon(s.name, category: s.category), size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(s.name).font(.callout.weight(.medium)).lineLimit(1)
                        .foregroundStyle(stopped ? Color.fg3 : Color.primary)
                    if s.reviewReason != nil {
                        // 标签只写「可以考虑退」，为什么写在下面那行小字里（窄窗口也不会被截断）。
                        Text("可以考虑退").font(.caption2.weight(.semibold)).foregroundStyle(Color.alert)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.alertSoft, in: Capsule())
                            .lineLimit(1).fixedSize()
                    }
                }
                Text(detail(s)).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !stopped, let d = s.daysLeft {
                Text(d == 0 ? "今天扣" : d <= 2 ? Nudges.dayWord(d) + "扣" : "\(d) 天后")
                    .font(.caption.weight(s.isDueVerySoon ? .semibold : .regular))
                    .foregroundStyle(s.isDueVerySoon ? Color.warn : Color.fg2)
                    .padding(.horizontal, s.isDueVerySoon ? 6 : 0).padding(.vertical, s.isDueVerySoon ? 1 : 0)
                    .background(s.isDueVerySoon ? Color.warnSoft : Color.clear, in: Capsule())
                    .lineLimit(1).fixedSize()
            }
            Text(s.amount.ui(in: s.currency)).font(.kitAmount).lineLimit(1)
                .foregroundStyle(stopped ? Color.fg3 : Color.primary)
                .frame(minWidth: 64, alignment: .trailing)
            menu(s)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 「每月 · 12 月 3 日」「每年 · 折合每月 8 €」「涨到 12,99 €」。
    private func detail(_ s: SubscriptionStatus) -> String {
        var parts = [s.cycle.label]
        if let why = s.reviewReason { parts.insert(why, at: 0) }
        if let c = s.cancelledOn { parts.append("\(c.short)停了") }
        else {
            if s.cycle != .monthly { parts.append("折合每月 \(s.monthlyAmount.ui(in: s.currency))") }
            else if let n = s.nextDate { parts.append(n.short) }
            if s.currency != model.ledger.baseCurrency {
                parts.append("≈ " + model.ledger.toBase(s.amount, currency: s.currency, on: .today).ui(in: model.ledger.baseCurrency))
            }
        }
        if s.priceChanged, let last = s.lastChargeAmount { parts.append("最近扣了 \(last.ui(in: s.currency))") }
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
                    } label: { Label("按最近一次改成 \(last.ui(in: s.currency))", systemImage: "arrow.up.circle") }
                }
                if sub.isActive {
                    Button {
                        var u = sub; u.rarelyUsed = sub.rarelyUsed == true ? nil : true
                        model.perform { try $0.editSubscription(u, author: model.author) }
                    } label: {
                        sub.rarelyUsed == true ? Label("其实常用（取消「可以考虑退」）", systemImage: "hand.thumbsup")
                                               : Label("最近很少用（标「可以考虑退」）", systemImage: "hand.thumbsdown")
                    }
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
            CategoryIcon(category: subscriptionIcon(c.name, category: c.category), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.callout).lineLimit(1)
                Text("\(c.cycle.label) \(c.amount.ui(in: c.currency)) · 扣过 \(c.count) 次，最近 \(c.lastDate.short)")
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
        var text = "\(draft.cycle.label) \(amount.ui(in: draft.currency))"
        if draft.cycle != .monthly { text += "，摊到每月约 \(monthly.ui(in: draft.currency))" }
        if draft.currency != base {
            text += "，约合 \(model.ledger.toBase(amount, currency: draft.currency, on: .today).ui(in: base))"
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

/// 订阅的图标：分类写的是笼统的「订阅」（或没写）时，按名字猜一个更具体的，免得一排全是同一个圆圈。
/// 视频会员 → 电影，音乐 → 音乐，健身 → 健身房，网站域名 → 网站，云盘、软件、字体、系统月费 → 软件。
func subscriptionIcon(_ name: String, category: String?) -> String {
    if let c = category, !c.isEmpty, c != "订阅" { return c }
    let n = name.lowercased()
    let rules: [([String], String)] = [
        (["视频", "影视", "video", "stream", "netflix", "disney", "hbo", "youtube", "爱奇艺", "腾讯视频", "优酷", "bilibili", "b站"], "电影"),
        (["音乐", "music", "spotify", "tune", "网易云", "qq音乐"], "音乐"),
        (["健身", "gym", "fit", "瑜伽", "yoga"], "健身房"),
        (["网站", "域名", "domain", "hosting", "服务器"], "网站"),
        (["手机", "话费", "流量", "电话", "sim"], "通讯"),
        (["宽带", "网费", "fibra", "internet"], "网费"),
        (["保险", "seguro", "insurance"], "保险"),
        (["读书", "书", "kindle", "阅读", "杂志", "报"], "书"),
        (["云", "cloud", "icloud", "drive", "网盘", "存储"], "数码"),
        (["收银", "pos", "刷卡"], "设备"),
        (["字体", "font", "设计", "canva", "figma"], "文具"),
        (["软件", "app", "系统", "adobe", "office", "chatgpt", "claude", "ai "], "软件"),
    ]
    for (words, icon) in rules where words.contains(where: { n.contains($0) }) { return icon }
    return "订阅"
}
