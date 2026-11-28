#if os(iOS)
import FinanceCore
import SwiftUI

// 「我的」：底部五格放不下的页都在这里。生活和生意各一套，只列当前这一边的。

struct P3MePage: View {
    @Environment(P3State.self) private var state
    @AppStorage("p3.voicePause") private var voicePause = VoiceRules.defaultIndex
    @AppStorage("p3.voiceLanguage") private var voiceLanguage = VoiceRules.defaultLanguageIndex

    var body: some View {
        @Bindable var state = state
        NavigationStack(path: $state.mePath) {
            VStack(spacing: 0) {
                P3Header(title: "我的", sideSwitch: true) {
                    Button("完成") { state.meOpen = false }.font(P3.font(16, .bold)).foregroundStyle(P3.navy).padding(.leading, 4)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if state.side == .biz {
                            group("店里的钱", [.sales, .shopWealth, .fixed, .shopDebts])
                        } else {
                            group("看钱", [.spending, .wealth, .debts, .subscriptions])
                        }
                        VStack(spacing: 0) {
                            NavigationLink(value: P3State.Page.ai) { rowLabel("sparkles", "夏夏的 AI", state.ai.hasKey ? "OpenRouter" : "没填密钥") }
                            P3Divider().padding(.leading, 52)
                            NavigationLink(value: P3State.Page.memory) { rowLabel(P3State.Page.memory.symbol, "夏夏记住的事", "\(state.book.memos.count) 件") }
                        }
                        .p3Group()
                        VStack(spacing: 0) {
                            NavigationLink(value: P3State.Page.sides) {
                                rowLabel("square.split.2x1", "管哪边", state.book.showLife && state.book.showBiz ? "生活和生意" : state.book.showBiz ? "只管生意" : "只管生活")
                            }
                            P3Divider().padding(.leading, 52)
                            NavigationLink(value: P3State.Page.changes) { rowLabel("clock.arrow.circlepath", "改动记录", "\(state.ledger.changes.count) 条") }
                            P3Divider().padding(.leading, 52)
                            HStack(spacing: 12) {
                                Image(systemName: "mic").font(.system(size: 17, weight: .semibold)).foregroundStyle(state.side == .biz ? P3.teal : P3.navy).frame(width: 26)
                                Text("说完停多久自动发").font(P3.font(15.5, .bold)).foregroundStyle(P3.ink)
                                Spacer()
                                Picker("", selection: $voicePause) {
                                    ForEach(VoiceRules.pauses.indices, id: \.self) { Text(VoiceRules.title($0)).tag($0) }
                                }
                                .labelsHidden().tint(P3.ink2)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 50)
                            P3Divider().padding(.leading, 52)
                            HStack(spacing: 12) {
                                Image(systemName: "character.bubble").font(.system(size: 17, weight: .semibold)).foregroundStyle(state.side == .biz ? P3.teal : P3.navy).frame(width: 26)
                                Text("说话用哪种语言").font(P3.font(15.5, .bold)).foregroundStyle(P3.ink)
                                Spacer()
                                Picker("", selection: $voiceLanguage) {
                                    ForEach(VoiceRules.languages.indices, id: \.self) { Text(VoiceRules.languageTitle($0)).tag($0) }
                                }
                                .labelsHidden().tint(P3.ink2)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 50)
                            P3Divider().padding(.leading, 52)
                            rowLabel("icloud", "和 Mac 同步", state.isReal ? "用 iCloud 里同一本账" : "示例账本，不同步", chevron: false)
                        }
                        .p3Group()
                        if !state.isReal {
                            Text("这是示例账本：数字都是编的，只在手机内存里，关掉 app 就没了。")
                                .font(P3.font(12.5, .regular)).foregroundStyle(P3.ink2).padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
            .background(P3.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: P3State.Page.self) { p in
                P3PageView(page: p).toolbar(.visible, for: .navigationBar)
            }
        }
    }

    private func group(_ title: String, _ pages: [P3State.Page]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            P3Label(title).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element) { i, p in
                    if i > 0 { P3Divider().padding(.leading, 52) }
                    NavigationLink(value: p) { rowLabel(p.symbol, p.title, note(p)) }
                }
            }
            .p3Group()
        }
    }

    private func note(_ p: P3State.Page) -> String {
        let b = state.book
        switch p {
        case .spending: return b.month.spentTotal.p3Short
        case .wealth: return "净剩 \(b.totals.net.p3Short)"
        case .debts: return "欠 \(b.totals.owe.p3Short)"
        case .subscriptions: return "每月 \(b.subscriptionsMonthly.p3Short)"
        case .sales: return b.shopSalesTotal.p3Short
        case .fixed: return "每月 \(b.fixedTotal.p3Short)"
        case .shopDebts: return "\(b.shopDebts.count) 笔"
        default: return ""
        }
    }

    private func rowLabel(_ symbol: String, _ title: String, _ note: String, chevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(state.side == .biz ? P3.teal : P3.navy).frame(width: 26)
            Text(title).font(P3.font(15.5, .bold)).foregroundStyle(P3.ink)
            Spacer(minLength: 6)
            Text(note).font(P3.num(13.5, .semibold)).foregroundStyle(P3.ink2).lineLimit(1)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(P3.dash) }
        }
        .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
    }

    private func toggle(_ symbol: String, _ title: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(P3.navy).frame(width: 26)
                Text(title).font(P3.font(15.5, .bold)).foregroundStyle(P3.ink)
            }
        }
        .tint(P3.navy)
        .padding(.horizontal, 14).frame(minHeight: 50)
    }
}

extension View {
    func p3Group() -> some View {
        background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white))
    }
}

// MARK: - 点进去的每一页

struct P3PageView: View {
    let page: P3State.Page
    var body: some View {
        switch page {
        case .spending: P3SpendingPage()
        case .wealth: P3WealthPage()
        case .debts: P3DebtsPage()
        case .subscriptions: P3SubscriptionsPage()
        case .memory: P3MemoryPage()
        case .changes: P3ChangesPage()
        case .sides: P3SidesPage()
        case .ai: P3AIPage()
        case .sales: P3SalesPage()
        case .shopWealth: P3ShopWealthPage(isTab: false)
        case .fixed: P3FixedPage()
        case .shopDebts: P3ShopDebtsPage()
        }
    }
}

// MARK: 花销：圆环 + 每一类，月份能翻

struct P3SpendingPage: View {
    @Environment(P3State.self) private var state
    static let colors: [Color] = [P3.navy, P3.sky, P3.gold, P3.teal, P3.hex(0xE58C7A), P3.hex(0x9B8FE0), P3.hex(0x7CC4A0), P3.dash]

    var body: some View {
        let slices = state.shownSlices
        let total = slices.map(\.amount).reduce(.zero, +)
        P3SubPage(title: "花销") {
            HStack { P3MonthSwitch(); Spacer() }
            if slices.isEmpty {
                Text("\(state.monthTitle)没有记账").font(P3.font(16, .bold)).foregroundStyle(P3.ink2).frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ZStack {
                    P3Donut(values: slices.map { Double($0.amount.cents) }, colors: Self.colors)
                        .frame(width: 236, height: 236)
                    VStack(spacing: 2) {
                        P3Label("\(state.monthTitle)花掉")
                        Text(total.p3Short).font(P3.num(22, .heavy)).foregroundStyle(P3.gold).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: 130).contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .p3Sticker()
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    ForEach(Array(slices.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { P3Divider().padding(.leading, 48) }
                        HStack(spacing: 10) {
                            P3Icon(emoji: s.emoji, size: 34)
                            Circle().fill(Self.colors[i % Self.colors.count]).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.name).font(P3.font(15, .bold)).foregroundStyle(P3.ink)
                                if state.isThisMonth, s.lastMonth > .zero {
                                    let d = s.amount - s.lastMonth
                                    Text(d == .zero ? "和上个月一样" : d < .zero ? "比上个月少 \(d.magnitude.p3Short)" : "比上个月多 \(d.p3Short)")
                                        .font(P3.font(12, .semibold)).foregroundStyle(d <= .zero ? P3.green : P3.red)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(s.amount.p3).font(P3.num(15.5)).foregroundStyle(P3.navy)
                                Text("\(Int((Double(s.amount.cents) / Double(max(total.cents, 1)) * 100).rounded())) %").font(P3.font(11.5, .regular)).foregroundStyle(P3.ink2)
                            }
                        }
                        .frame(minHeight: 52)
                    }
                }
                .padding(.horizontal, 14).p3Group()
            }
        }
    }
}

struct P3Donut: View {
    let values: [Double]
    let colors: [Color]
    @State private var shown = 0.0
    var body: some View {
        let sum = max(values.reduce(0, +), 1)
        ZStack {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let start = values.prefix(i).reduce(0, +) / sum
                Circle()
                    .trim(from: start * shown, to: (start + v / sum) * shown)
                    .stroke(colors[i % colors.count], style: StrokeStyle(lineWidth: 34, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Circle().strokeBorder(P3.ink, lineWidth: 2).padding(-17)
            Circle().strokeBorder(P3.ink, lineWidth: 2).padding(17)
        }
        .padding(17)
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { shown = 1 } }
    }
}

// MARK: 家底

struct P3WealthPage: View {
    @Environment(P3State.self) private var state
    var body: some View {
        let b = state.book
        P3SubPage(title: "家底") {
            VStack(alignment: .leading, spacing: 4) {
                P3Label("净剩（有的减欠的）")
                P3Gold(amount: b.totals.net, size: 44)
                Text((state.canCompareNet ? state.compare(b.totals.net, state.lastMonthNet) + " · " : "") + "手里的钱够撑 \(b.handRunway.monthsText) 个月").font(P3.font(13, .bold)).foregroundStyle(P3.green)
                HStack(spacing: 20) {
                    kv("一共有", b.totals.have.p3, P3.ink)
                    kv("欠别人", b.totals.owe.p3, P3.red)
                }
                .padding(.top, 4)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).p3Sticker()
            P3AccountActions()
            P3AccountCards(accounts: b.pinned(on: .life))
            ForEach(b.listed(on: .life)) { g in
                P3AccountGroup(title: g.title, accounts: g.accounts)
            }
        }
    }
    private func kv(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            P3Label(l, size: 12)
            Text(v).font(P3.num(17, .heavy)).foregroundStyle(c)
        }
    }
}

/// 置顶的账户：做成银行卡的样子，横着滑。
struct P3AccountCards: View {
    let accounts: [TrialBook.Account]
    static let looks: [(Color, Color)] = [(P3.navy, .white), (P3.sky, .white), (P3.teal, .white), (P3.gold, .white), (P3.debtBG, P3.red), (P3.ink, .white)]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(accounts) { a in
                    let look = Self.looks[a.cardLook % Self.looks.count]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(a.name).font(P3.font(14, .bold))
                            Spacer()
                            Text(a.emoji)
                        }
                        Spacer(minLength: 0)
                        Text(a.isDebt ? "欠 " + a.balance.p3 : a.balance.p3).font(P3.num(22, .heavy))
                        Text(a.note).font(P3.font(11, .regular)).opacity(0.85).lineLimit(1)
                    }
                    .foregroundStyle(look.1)
                    .padding(14)
                    .frame(width: 200, height: 116, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(look.0))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(P3.ink, lineWidth: 2))
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(P3.ink).offset(y: 3))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4).padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }
}

struct P3AccountGroup: View {
    @Environment(P3State.self) private var state
    let title: String
    let accounts: [TrialBook.Account]
    /// 点一个账户：默认是改它；欠款页里是还一笔。
    var repay = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            P3Label(title).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { P3Divider().padding(.leading, 48) }
                    Button { state.open(repay && a.isDebt ? .repay(a.name) : .account(a.name)) } label: {
                        P3Row(emoji: a.emoji, name: a.name, meta: a.note, amount: a.isDebt ? (-a.balance).p3 : a.balance.p3,
                              color: a.isDebt ? (a.balance > .zero ? P3.red : P3.ink2) : a.side == .biz ? P3.teal : P3.navy, tag: repay && a.isDebt && a.balance > .zero ? "还一笔" : "", tagTone: .red)
                    }
                    .buttonStyle(P3Sink(depth: 1))
                }
            }
            .padding(.horizontal, 14).p3Group()
        }
    }
}

// MARK: 欠款

struct P3DebtsPage: View {
    @Environment(P3State.self) private var state
    var body: some View {
        let b = state.book
        P3SubPage(title: "欠款与还债") {
            VStack(alignment: .leading, spacing: 4) {
                P3Label("一共欠")
                Text(b.totals.owe.p3).font(P3.num(36, .heavy)).foregroundStyle(P3.red)
                Text("别人欠我 \(b.lent.map(\.balance).reduce(.zero, +).p3Short)").font(P3.font(13, .bold)).foregroundStyle(P3.green)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).p3Sticker()
            P3AccountGroup(title: "我欠的 · 点一下还一笔", accounts: b.debts, repay: true)
            if !b.lent.isEmpty { P3AccountGroup(title: "别人欠我", accounts: b.lent) }
            VStack(alignment: .leading, spacing: 6) {
                P3Label("接下来要付的").padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(b.upcoming.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { P3Divider().padding(.leading, 48) }
                        P3Row(emoji: e.emoji, name: e.name, meta: e.meta, amount: e.amount.p3, color: e.red ? P3.red : P3.navy)
                    }
                }
                .padding(.horizontal, 14).p3Group()
            }
        }
    }
}

// MARK: 订阅

struct P3SubscriptionsPage: View {
    @Environment(P3State.self) private var state
    var body: some View {
        let b = state.book
        P3SubPage(title: "订阅") {
            VStack(alignment: .leading, spacing: 4) {
                P3Label("订阅每月一共")
                P3Gold(amount: b.subscriptionsMonthly, size: 44)
                Text("一年是 \(Money(cents: b.subscriptionsMonthly.cents * 12).p3Short)").font(P3.font(13, .bold)).foregroundStyle(P3.ink2)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).p3Sticker()
            VStack(spacing: 0) {
                ForEach(Array(b.subscriptions.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { P3Divider().padding(.leading, 48) }
                    HStack {
                        P3Row(emoji: s.emoji, name: s.name, meta: s.note, amount: s.amount.p3, color: s.off ? P3.dash : P3.navy,
                              tag: s.off ? "要退" : s.tag, tagTone: s.off ? .red : s.flag ? .teal : .gold)
                    }
                    .contextMenu {
                        Button(s.off ? "不退了" : "标成要退") {
                            state.change(s.off ? "好，\(s.name)不退了" : "记下了：\(s.name)要退，每月省 \(s.monthly.p3Short)", kind: .subscription) {
                                try $0.setSubscription(s.name, dropped: !s.off)
                            }
                        }
                    }
                    .onTapGesture {
                        state.change(s.off ? "好，\(s.name)不退了" : "记下了：\(s.name)要退，每月省 \(s.monthly.p3Short)", kind: .subscription) {
                            try $0.setSubscription(s.name, dropped: !s.off)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).p3Group()
            if let ask = b.subscriptionsQuestion { Text(ask).font(P3.font(13.5, .bold)).foregroundStyle(P3.ink) }
            Text("点一行标成「要退」，再点一下取消。").font(P3.font(12.5, .regular)).foregroundStyle(P3.ink2)
        }
    }
}

// MARK: 夏夏记住的事

struct P3MemoryPage: View {
    @Environment(P3State.self) private var state
    var body: some View {
        P3SubPage(title: "夏夏记住的事") {
            ForEach(state.book.memos) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.topic).font(P3.font(15.5, .heavy)).foregroundStyle(P3.ink)
                        P3Tag(text: m.kind == .rule ? "规矩" : m.kind == .lesson ? "学到的" : "记得的", tone: m.kind == .rule ? .gold : .blue)
                        Spacer()
                    }
                    ForEach(m.lines, id: \.self) { l in Text(l).font(P3.font(14, .regular)).foregroundStyle(P3.ink) }
                    Text(m.source).font(P3.font(12, .regular)).foregroundStyle(P3.ink2)
                }
                .p3Card(h: 16, v: 12, radius: 18)
            }
        }
    }
}

// MARK: 改动记录

struct P3ChangesPage: View {
    @Environment(P3State.self) private var state
    var body: some View {
        P3SubPage(title: "改动记录") {
            VStack(spacing: 0) {
                ForEach(Array(state.ledger.changes.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { P3Divider() }
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.summary).font(P3.font(14.5, .semibold)).foregroundStyle(c.undone ? P3.ink2 : P3.ink).strikethrough(c.undone)
                            Text("\(c.author) · \(c.createdAt.formatted(date: .omitted, time: .shortened))").font(P3.font(12, .regular)).foregroundStyle(P3.ink2)
                        }
                        Spacer(minLength: 6)
                        if state.canUndo(c.id) {
                            Button("撤销") { state.undo(change: c.id) }.buttonStyle(.p3(.ghost, .small))
                        } else if c.undone {
                            P3Tag(text: "撤销了")
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14).p3Group()
        }
    }
}

// MARK: 管哪边

struct P3SidesPage: View {
    @Environment(P3State.self) private var state
    var body: some View {
        let b = state.book
        P3SubPage(title: "管哪边") {
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { b.showLife }, set: { state.setSides(life: $0, biz: b.showBiz) })) {
                    Text("生活").font(P3.font(15.5, .bold)).foregroundStyle(P3.ink)
                }
                .tint(P3.navy).padding(.horizontal, 14).frame(minHeight: 50)
                P3Divider().padding(.leading, 14)
                Toggle(isOn: Binding(get: { b.showBiz }, set: { state.setSides(life: b.showLife, biz: $0) })) {
                    Text("生意 · \(b.shopName)").font(P3.font(15.5, .bold)).foregroundStyle(P3.ink)
                }
                .tint(P3.teal).padding(.horizontal, 14).frame(minHeight: 50)
            }
            .p3Group()
            Text("生活和生意的账户完全分开，记账也只记在当前这一边。关掉一边只是不显示，账还在。")
                .font(P3.font(13, .regular)).foregroundStyle(P3.ink2)
        }
    }
}

// MARK: - 生意那边

struct P3SalesPage: View {
    @Environment(P3State.self) private var state
    /// 这个月 1 号是周几：周一开头的日历，前面空几格。
    private func lead(_ b: TrialBook) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let k = b.thisMonth
        guard let first = cal.date(from: DateComponents(year: k.year, month: k.month, day: 1)) else { return 0 }
        return (cal.component(.weekday, from: first) + 5) % 7
    }

    var body: some View {
        let b = state.book
        P3SubPage(title: "营业额") {
            VStack(alignment: .leading, spacing: 4) {
                P3Label("\(state.monthTitle) · 收进来")
                P3Gold(amount: state.isThisMonth ? b.shopSalesTotal : b.shopMonth(state.monthKey).income, size: 44)
                if state.isThisMonth {
                    Text("开了 \(b.shopOpenDays) 天 · 每个开门的日子收够 \(b.dailyBreakEven.p3Short) 才不亏").font(P3.font(13, .bold)).foregroundStyle(P3.teal)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).p3Sticker()
            if !state.isThisMonth {
                // 过去的月份没有日历：列出那个月记过的收入；只有合计的就说清楚
                let rows = b.shopFlow(in: state.monthKey).filter { $0.amount > .zero }
                VStack(alignment: .leading, spacing: 2) {
                    if rows.isEmpty {
                        Text(b.shopFlowTotalsLine(in: state.monthKey) ?? "那个月没有记店里收的钱").font(P3.font(14, .regular)).foregroundStyle(P3.ink2).padding(.vertical, 8)
                    }
                    ForEach(rows) { r in P3Row(emoji: r.emoji, name: "\(r.day) 号", meta: r.detail, amount: r.amount.p3, color: P3.teal) }
                }
                .p3Card(h: 16, v: 12)
            } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(P3.font(11.5, .bold)).foregroundStyle(P3.ink2) }
                // 1 号前面空几格（周一开头）
                ForEach((0..<lead(b)).map { "lead-\($0)" }, id: \.self) { _ in Color.clear.frame(height: 50) }
                ForEach(b.shopDays, id: \.day) { d in
                    let low = d.state == .open && d.total < b.dailyBreakEven
                    Button {
                        guard d.state != .future else { return }
                        // 就在这页上弹出「那天收了多少」，记完还在日历
                        state.open(.shopDay(d.day))
                    } label: {
                    VStack(spacing: 1) {
                        Text("\(d.day)").font(P3.font(11, .bold)).foregroundStyle(d.day == b.todayDay ? P3.teal : P3.ink2)
                        Text(d.state == .open ? "\(d.total.cents / 100)" : d.state == .rest ? "休" : d.state == .missing ? "没记" : "")
                            .font(P3.num(12, .bold)).foregroundStyle(d.state == .open ? (low ? P3.red : P3.ink) : P3.ink2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(d.state == .missing ? P3.warnBG : d.state == .future ? .clear : .white))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(d.day == b.todayDay ? P3.teal : .clear, lineWidth: 2))
                    }
                    .buttonStyle(P3Sink(depth: 1))
                    .disabled(d.state == .future)
                    .accessibilityLabel("\(d.day) 号，\(d.state == .open ? "收了 \(d.total.p3Short)" : d.state == .rest ? "休息" : d.state == .missing ? "没记" : "还没到")")
                }
            }
            Text("红字是没收够「不亏线」的那天。点哪天就记哪天收了多少。").font(P3.font(12.5, .regular)).foregroundStyle(P3.ink2)
            }
        }
    }
}

struct P3ShopWealthPage: View {
    @Environment(P3State.self) private var state
    let isTab: Bool
    var body: some View {
        let b = state.book
        let w = b.shopWorth
        let have = w.cash, owe = w.owes
        let content = Group {
            VStack(alignment: .leading, spacing: 4) {
                P3Label("店里能用的钱")
                P3Gold(amount: have, size: 44)
                Text("欠着 \(owe.p3Short) · 和生活的钱完全分开").font(P3.font(13, .bold)).foregroundStyle(P3.teal)
                // 店的净值是负数时说一句（和 Mac 同一句话）
                if let note = b.shopWorthNote { Text(note).font(P3.font(13, .bold)).foregroundStyle(P3.red) }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).p3Sticker()
            P3AccountActions()
            P3AccountCards(accounts: b.pinned(on: .biz))
            ForEach(b.listed(on: .biz)) { g in P3AccountGroup(title: g.title, accounts: g.accounts) }
        }
        if isTab {
            VStack(spacing: 0) {
                P3Header(title: "店的家底", sideSwitch: true, meButton: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { content }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
            .background(P3.bg)
            .toolbar(.hidden, for: .navigationBar)
        } else {
            P3SubPage(title: "店的家底") { content }
        }
    }
}

struct P3FixedPage: View {
    @Environment(P3State.self) private var state
    var body: some View {
        let b = state.book
        P3SubPage(title: "固定开销") {
            VStack(alignment: .leading, spacing: 4) {
                P3Label("每月固定要付")
                P3Gold(amount: b.fixedTotal, size: 44)
                Text("每个开门的日子收够 \(b.dailyBreakEven.p3Short) 才不亏").font(P3.font(13, .bold)).foregroundStyle(P3.teal)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).p3Sticker()
            VStack(spacing: 0) {
                ForEach(Array(b.fixedCosts.enumerated()), id: \.element.id) { i, f in
                    if i > 0 { P3Divider().padding(.leading, 48) }
                    P3Row(emoji: f.emoji, name: f.name, meta: "每月 \(f.day) 日 · 从\(f.account)扣", amount: f.amount.p3, color: P3.navy)
                }
            }
            .padding(.horizontal, 14).p3Group()
            let rises = b.fixedRises
            if !rises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    P3Label("比上个月多了的").padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(rises.enumerated()), id: \.offset) { i, r in
                            if i > 0 { P3Divider().padding(.leading, 48) }
                            P3Row(emoji: r.item.emoji, name: r.item.name, meta: "上个月 \((r.item.lastMonth ?? .zero).p3Short)", amount: "+\(r.rise.p3Short)", color: P3.red)
                        }
                    }
                    .padding(.horizontal, 14).p3Group()
                }
            }
        }
    }
}

struct P3ShopDebtsPage: View {
    @Environment(P3State.self) private var state
    var body: some View {
        let b = state.book
        P3SubPage(title: "店的欠款") {
            if !b.shopOwedAccounts.isEmpty {
                P3AccountGroup(title: "店欠的（卡、贷款）· 点一下还一笔", accounts: b.shopOwedAccounts, repay: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                P3Label("分期、赊账和挂账").padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(b.shopDebts.enumerated()), id: \.element.id) { i, d in
                        if i > 0 { P3Divider().padding(.leading, 48) }
                        P3Row(emoji: d.emoji, name: d.name, meta: d.note, amount: d.amount.p3, color: d.flag ? P3.green : P3.red,
                              tag: d.flag ? "别人欠店里" : "店欠别人", tagTone: d.flag ? .green : .red)
                    }
                }
                .padding(.horizontal, 14).p3Group()
            }
        }
    }
}
#endif
