#if os(macOS)
import FinanceCore
import SwiftUI

// 生活这边最要紧的三页：总览、家底、目标。每页一屏，一个金币金的大数字。

extension V3State {
    /// 路上每站下面的小字。
    var roadCaptions: [Int: String] {
        var out: [Int: String] = [:]
        let j = book.journey
        for (i, st) in j.stations.enumerated() where !st.title.isEmpty && i > 0 { out[i] = st.title }
        for (i, d) in reachedDates where j.stations.indices.contains(i) && j.stations[i].target <= j.saved { out[i] = d }
        if !j.isFinished { out[j.nextIndex] = "这一站" }
        return out
    }
    /// 哪天到的哪一站：只读账本里的（试用数字是示例数据里带的，正式账本是从目标账户的余额历史算的），界面自己不写日子。
    var reachedDates: [Int: String] { book.stationDates }
    /// 以前这里写死过一个「12 月 20 日前」：没有依据，不写了（ming 2026-11-28：说的话要能算出来）。
    var deadline: String { "" }
    /// 照现在的速度，月底大概能存到多少（示例：再存 30 €）。
    var projectedThisMonth: Money { book.projectedSavedThisMonth }
    // 和上个月比的两个数：都从账本里存的上个月的数来，不写死（核心里 TrialMonths.swift）
    var lastMonthSpentSoFar: Money { book.previousMonthData?.sameDaySpent ?? book.month.spentTotal }
    var lastMonthNet: Money { book.previousMonthData?.net ?? book.totals.net }
    /// 上个月的数不全时，不写「比上个月…」那句。
    var canCompareSpend: Bool { book.spentLessThanLastMonthSameDay != nil }
    var canCompareNet: Bool { book.netMoreThanLastMonth != nil }
}

// MARK: - 总览

struct V3OverviewPage: View {
    @Environment(V3State.self) private var state

    var body: some View {
        GeometryReader { g in
            let leftW = (g.size.width - 18) * 1.3 / 2.3
            HStack(alignment: .top, spacing: 18) {
                left(width: leftW).frame(width: leftW)
                right
            }
        }
    }

    private func left(width: CGFloat) -> some View {
        let b = state.book
        let live = b.month
        // 切到过去的月份：大卡是那个月最后剩下的，四个数照算
        let m = state.monthData
        let now = state.isThisMonth
        let j = b.journey
        return VStack(spacing: 14) {
            if now {
                // 这个月出了意外开销：先说这件；没有才说平常那句
                if let odd = b.surprises(in: b.thisMonth).first {
                    let n = b.surprises(in: b.thisMonth).count
                    V3Ask(face: "worried", text: n == 1 ? "这个月有一笔意外开销 \(odd.amount.magnitude.v3Short)，后面几天省着点。" : "这个月有 \(n) 笔意外开销，后面几天省着点。", tone: .warn) {
                        Button("看看") { state.go(.monthly) }.buttonStyle(.v3(.primary, .small))
                    }
                } else if let remark = b.savingRemark {
                    // 这句从这个月的数算出来（定了每月存多少、已经存了多少、还剩多少能花）；没定就不说
                    V3Ask(face: "calm", text: remark) {
                        Button("看看") { state.go(.goals) }.buttonStyle(.v3(.primary, .small))
                    }
                }
            }
            // 这一页最重要的数
            VStack(alignment: .leading, spacing: 8) {
                V3Label(now ? "\(state.monthLabel) · 现在还能随便花" : "\(state.monthLabel) · 最后剩下")
                V3Gold(amount: m.left, size: 72)
                if now {
                    Text(live.left > .zero ? "到月底还有 \(live.daysLeft) 天，平均每天能花 \(Money(cents: live.perDay.cents / 100 * 100).v3Short)"
                         : "这个月能随便花的已经用完了，到月底还有 \(live.daysLeft) 天")
                        .font(V3.font(14, .bold)).foregroundStyle(live.left > .zero ? V3.green : V3.red).contentTransition(.numericText())
                }
                HStack(spacing: 26) {
                    V3KV(value: m.income.v3Signed, label: "进账", color: V3.green)
                    V3KV(value: (-m.fixed).v3Signed, label: "固定要付的")
                    V3KV(value: (-m.forGoals).v3Signed, label: "留给目标")
                    V3KV(value: (-m.spent).v3Signed, label: "随手花的")
                }
                .padding(.top, 2)
            }
            .padding(.init(top: 18, leading: 24, bottom: 34, trailing: 24))
            .frame(maxWidth: .infinity, alignment: .leading)
            .v3Sticker().v3WaveBottom()
            .accessibilityElement(children: .combine)

            HStack(spacing: 14) {
                let diff = state.lastMonthSpentSoFar - m.spentTotal
                smallCard(now ? "这个月一共花掉" : "\(state.monthLabel)一共花掉", m.spentTotal.v3,
                          !now || !state.canCompareSpend ? "" : diff >= .zero ? "比上月同期少 \(diff.v3Short)" : "比上月同期多 \(diff.magnitude.v3Short)",
                          diff >= .zero ? V3.green : V3.navy) { state.go(.spending) }
                let delta = b.totals.net - state.lastMonthNet
                smallCard(now ? "家底 · 净剩" : "\(state.monthLabel)底 · 净剩", (now ? b.totals.net : m.net).v3,
                          !now || !state.canCompareNet ? "" : delta >= .zero ? "比上个月多 \(delta.v3Short)" : "比上个月少 \(delta.magnitude.v3Short)",
                          delta >= .zero ? V3.green : V3.navy) { state.go(.wealth) }
            }

            VStack(alignment: .leading, spacing: 4) {
                V3CardTitle("\(j.name)的路", note: j.isFinished ? "走完了" : state.readOnly || state.deadline.isEmpty ? "下一站 \(j.nextStation?.target.v3Short ?? "")" : "\(state.deadline)前到 \(j.nextStation?.target.v3Short ?? "")") {
                    V3Tag(text: j.isFinished ? "到终点了" : "这一站还差 \(j.remainingToNext.v3Short)", tone: .gold)
                }
                HStack(spacing: 16) {
                    V3Road(journey: j, mini: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        Button("+ 存一笔") { state.open(.save) }.buttonStyle(.v3)
                        Button("忍住了一笔") { state.open(.holdBack) }.buttonStyle(.v3(.ghost, .small))
                    }
                    .padding(.bottom, 6)
                }
            }
            .padding(.init(top: 10, leading: 20, bottom: 8, trailing: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .v3Soft()
        }
    }

    private func smallCard(_ label: String, _ value: String, _ note: String, _ noteColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                V3Label(label)
                V3Amount(value, size: 24, weight: .heavy)
                Text(note).font(V3.font(13.5, .bold)).foregroundStyle(noteColor).contentTransition(.numericText())
            }
            .v3Card(h: 18, v: 12)
        }
        .buttonStyle(V3SinkStyle(depth: 2))
        .accessibilityLabel("\(label) \(value)，\(note)")
    }

    private var right: some View {
        let b = state.book
        let list = b.owned + b.debts + b.lent
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                V3CardTitle(title: "我的账户") { EmptyView() } trail: {
                    Button { state.go(.wealth) } label: {
                        Text("有 \(b.totals.have.v3Short) · 欠 \(b.totals.owe.v3Short) · 全部 ›")
                            .font(V3.font(13, .semibold)).foregroundStyle(V3.ink2).contentTransition(.numericText())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(list.prefix(8)) { a in
                        Button { state.go(.wealth) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(a.emoji) \(a.label)").font(V3.font(12, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
                                V3Amount(a.balance.v3, color: a.isDebt ? V3.red : a.kind == .shop ? V3.teal : V3.navy)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(a.isDebt ? V3.debtBG : V3.bg))
                        }
                        .buttonStyle(V3SinkStyle(depth: 1))
                        .accessibilityLabel("\(a.label) \(a.balance.v3)")
                    }
                    Button { if list.count > 8 { state.go(.wealth) } else { state.showAddAccount = true } } label: {
                        Text(list.count > 8 ? "全部 \(list.count) 个 ›" : "+ 加账户").font(V3.font(12.5, .bold)).foregroundStyle(V3.navy)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(V3.dash, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1))
                }
            }
            .v3Card(h: 16, v: 12)

            VStack(alignment: .leading, spacing: 6) {
                let recent = state.isThisMonth ? b.today : state.monthData.entries
                V3CardTitle(title: state.isThisMonth ? "今天自己进来的" : "这个月记的") { EmptyView() } trail: {
                    Button { state.go(.transactions) } label: {
                        Text("\(recent.count) 笔 · 全部 ›").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                    }
                    .buttonStyle(V3SinkStyle(depth: 1))
                }
                V3Rows(data: Array(recent.prefix(3))) { e in
                    Button { state.txFocus = e.id; state.go(.transactions) } label: {
                        V3Row(emoji: e.emoji, name: e.name, meta: e.meta, amount: e.amount.v3, tag: e.tag, compact: true).contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1))
                }
            }
            .v3Card(h: 16, v: 14)

            // 接下来要付的：只有看这个月时才有
            if !state.isThisMonth { Spacer(minLength: 0) } else {
            VStack(alignment: .leading, spacing: 6) {
                V3CardTitle(title: "接下来要付的") { EmptyView() } trail: { V3Tag(text: "钱够", tone: .green) }
                V3Rows(data: Array(b.upcoming.prefix(3))) { e in
                    Button { state.go(e.red ? .debts : e.name == "房租" ? .trends : .subscriptions) } label: {
                        V3Row(emoji: e.emoji, name: e.name, meta: e.meta, amount: e.amount.v3, color: e.red ? V3.red : V3.navy, compact: true).contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .v3Soft()
            }
        }
    }
}

// MARK: - 家底

struct V3WealthPage: View {
    @Environment(V3State.self) private var state

    // 三层：上面三个数 + 两块钱；中间一排置顶的卡片；下面其余账户的列表。
    var body: some View {
        GeometryReader { g in
            let leftW = (g.size.width - 18) * 1.5 / 2.5
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    numbers.frame(width: leftW)
                    blocks
                }
                .fixedSize(horizontal: false, vertical: true)
                V3PinnedCards(side: .life)
                V3AccountList(side: .life, wide: true)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var numbers: some View {
        let b = state.book
        let delta = b.totals.net - state.lastMonthNet
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                V3Label("一共有")
                V3Amount(b.totals.have.v3, size: 25, weight: .heavy)
                // 自动算的一小行：手里的钱按平时每月花，够撑几个月。没有设置。
                V3Label("够撑 \(b.handRunway.monthsText) 个月", size: 12.5).help("按平时每个月花 \(b.usualMonthlySpend.v3Short) 算")
            }
            .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).v3Soft()
            VStack(alignment: .leading, spacing: 4) { V3Label("欠别人"); V3Amount(b.totals.owe.v3, color: V3.red, size: 25, weight: .heavy) }
                .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).v3Soft()
            VStack(alignment: .leading, spacing: 2) {
                V3Label("净剩")
                V3Gold(amount: b.totals.net, size: 36)
                if state.canCompareNet {
                    Text(delta >= .zero ? "比上个月多 \(delta.v3Short)" : "比上个月少 \(delta.magnitude.v3Short)")
                        .font(V3.font(13.5, .bold)).foregroundStyle(delta >= .zero ? V3.green : V3.navy).contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
            .layoutPriority(1)
        }
    }

    private var blocks: some View {
        let b = state.book
        let colors: [String: Color] = ["存在目标里": V3.star, "存着不动": V3.navy, "日常能用": V3.sky, "借出去的": V3.hex(0xC9A0DC)]
        let parts: [(String, Money, Color)] = b.wealthBlocks.map { ($0.name, $0.amount, colors[$0.name] ?? V3.sky) }
        let total = max(b.totals.have.cents, 1)
        return VStack(alignment: .leading, spacing: 10) {
                V3CardTitle("这些钱分成\(["零", "一", "两", "三", "四"][min(parts.count, 4)])块")
                GeometryReader { g in
                    HStack(spacing: 0) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                            Rectangle().fill(p.2).frame(width: g.size.width * CGFloat(p.1.cents) / CGFloat(total))
                        }
                    }
                }
                .frame(height: 26).clipShape(Capsule()).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2.5))
                .animation(.spring(duration: 0.5), value: b.totals)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                Circle().fill(p.2).frame(width: 9, height: 9)
                                Text(p.0).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                            }
                            V3Amount(p.1.v3Short, color: V3.ink, size: 14)
                        }
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
        }
        .padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).v3Soft()
    }
}

// MARK: - 目标

struct V3GoalsPage: View {
    @Environment(V3State.self) private var state

    var body: some View {
        GeometryReader { g in
            let leftW = (g.size.width - 18) * 1.45 / 2.45
            HStack(alignment: .top, spacing: 18) {
                Group {
                    if state.book.journey.total > .zero { left(width: leftW) } else { noBigGoal }
                }
                .frame(width: leftW)
                right
            }
        }
    }

    /// 没有大目标时，路卡是空的：一句话 + 两个按钮。
    private var noBigGoal: some View {
        let small = state.book.smallGoals
        return VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "flag").font(.system(size: 34, weight: .semibold)).foregroundStyle(V3.dash)
            Text("现在没有大目标").font(V3.font(22, .heavy)).foregroundStyle(V3.ink)
            HStack(spacing: 10) {
                if !small.isEmpty {
                    Menu {
                        ForEach(small) { g in
                            Button("「\(g.name)」") { state.change("好，「\(g.name)」现在是大目标", kind: .goal) { try $0.promoteSmallGoal(g.id) } }
                        }
                    } label: { Text("从小目标里挑一个").font(V3.font(14, .bold)).foregroundStyle(V3.ink).padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2))) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                Button("定一个新的大目标") { state.open(.goalNew) }.buttonStyle(.v3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v3Sticker()
    }

    // 左边：大目标那条路。「这一站还差」写在卡头，「这个月的计划」和收到的信在卡底一行。
    private func left(width: CGFloat) -> some View {
        let j = state.book.journey
        let plan = j.monthlyPlan
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                V3CardTitle(title: "\(j.name)的路", size: 19) {
                    if !j.why.isEmpty { V3Tag(text: j.why, tone: .gold) }
                } trail: {
                    HStack(spacing: 8) {
                        if !j.isFinished { Text("这一站还差").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2) }
                        Text(j.isFinished ? "都存够了" : j.remainingToNext.v3Short).font(V3.num(22, .heavy)).foregroundStyle(V3.gold).contentTransition(.numericText())
                        // 「…」：改、换、删这个大目标
                        Menu { bigGoalMenu } label: {
                            Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(V3.ink)
                                .frame(width: 30, height: 30).background(Circle().fill(V3.bg)).contentShape(Circle())
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        .help("改、换、删这个大目标").accessibilityLabel("大目标的更多操作")
                    }
                }
                V3Road(journey: j, captions: state.roadCaptions, onLetter: { i in
                    // 路上第 i 站的信：有就打开，没有（示例里原来就走过的站）就现写一封
                    let letters = state.book.letters
                    if letters.indices.contains(i - 1) { state.openMoment(.letter(letters[i - 1])) }
                    else if j.stations.indices.contains(i) { state.openMoment(.letter(state.arrivalLetter(for: j.stations[i]))) }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if j.isFinished {
                    // 存够了：这个目标完成了，接下来走哪条
                    HStack(spacing: 10) {
                        Text("这个目标完成了").font(V3.font(15, .heavy)).foregroundStyle(V3.gold).lineLimit(1).fixedSize()
                        Spacer(minLength: 6)
                        if !state.book.smallGoals.isEmpty {
                            Menu {
                                ForEach(state.book.smallGoals) { g in
                                    Button("「\(g.name)」") {
                                        state.change("「\(j.name)」收进走完的路，「\(g.name)」现在是大目标", kind: .goal) { try $0.archiveBigGoal(); try $0.promoteSmallGoal(g.id) }
                                    }
                                }
                            } label: {
                                Text("从小目标里挑一个当大目标").font(V3.font(13, .bold)).foregroundStyle(V3.ink).padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                            }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        }
                        Button("定一个新的大目标") {
                            if state.change("「\(j.name)」收进走完的路了", kind: .goal, { try $0.archiveBigGoal() }) { state.open(.goalNew) }
                        }
                        .buttonStyle(.v3(.primary, .small))
                    }
                } else {
                    let over = j.savedThisMonth - plan
                    HStack(spacing: 10) {
                        Button { state.open(.monthlyPlan) } label: {
                            HStack(spacing: 8) {
                                V3Bar(fraction: plan > .zero ? min(Double(j.savedThisMonth.cents) / Double(plan.cents), 1) : 0, height: 10,
                                      color: plan > .zero && j.savedThisMonth >= plan ? V3.star : V3.navy).frame(width: 120)
                                Text(plan > .zero && over > .zero ? "这个月存了 \(j.savedThisMonth.v3Short)，比计划多存了 \(over.v3Short)" : "这个月存了 \(j.savedThisMonth.v3Short)")
                                    .font(V3.font(13.5, .bold)).foregroundStyle(V3.ink).lineLimit(1).fixedSize()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(V3SinkStyle(depth: 1)).help("改每月存多少")
                        Spacer(minLength: 6)
                        if j.remainingToNext > Money(cents: 20_00) {
                            Button("存够这一站") { state.depositAndCelebrate(j.remainingToNext) }.buttonStyle(.v3(.ghost, .small))
                        }
                    }
                }
            }
            .padding(.init(top: 16, leading: 20, bottom: 26, trailing: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v3Sticker().v3WaveBottom()
            .contextMenu { bigGoalMenu }
            Group {
                if j.isFinished {
                    V3Ask(face: "celebrate", text: "走完了！\(j.total.v3Short) 都存够了。", tone: .good)
                } else if j.total > .zero {
                    let name = j.nextStation.flatMap { $0.title.isEmpty ? nil : "「\($0.title)」那一站" } ?? "下一站"
                    // 只说还差多少，不编日子、不说「有点悬」。照现在的速度这个月打算存的到不了（算出来的），才给「看看办法」
                    if state.book.savingIsBehind, state.real == nil {
                        V3Ask(face: "happy", text: "离\(name)还差 \(j.remainingToNext.v3Short)。") {
                            Button("看看办法") { state.openMoment(.smallerStep) }.buttonStyle(.v3(.primary, .small))
                        }
                    } else {
                        V3Ask(face: "happy", text: "离\(name)还差 \(j.remainingToNext.v3Short)。")
                    }
                }
            }
            .frame(width: width * 0.86).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 大目标的菜单（右上「…」和右键是同一个）。
    @ViewBuilder private var bigGoalMenu: some View {
        let b = state.book
        Button("改名字、金额…") { state.open(.goalEdit) }
        if !b.smallGoals.isEmpty {
            Menu("换掉这个大目标") {
                ForEach(b.smallGoals) { g in
                    Button("换成「\(g.name)」") { state.change("好，「\(g.name)」现在是大目标", kind: .goal) { try $0.promoteSmallGoal(g.id) } }
                }
            }
        }
        Divider()
        Button("删掉这个目标…", role: .destructive) { state.open(.goalDelete(nil)) }
    }

    // 右边：最多 3 个小目标；下面是「先放着想想的」。
    private var right: some View {
        let b = state.book
        let small = b.smallGoals
        return VStack(spacing: 12) {
            V3CardTitle(title: "小目标") { V3Tag(text: "\(b.activeSmallGoals.count) / \(Plans.maxSmallGoals)") } trail: { EmptyView() }
            ForEach(small.prefix(4)) { g in smallCard(g) }
            if b.canAddSmallGoal {
                Button { state.open(.smallGoal(nil)) } label: {
                    Text("+ 加一个小目标").font(V3.font(14, .bold)).foregroundStyle(V3.navy)
                        .frame(maxWidth: .infinity).frame(height: small.isEmpty ? 110 : 54)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(V3.dash, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(V3SinkStyle(depth: 2))
            }
            // 想要清单：问夏夏「要不要买」时点了「先放着想想」的东西。空的时候这一块不出现。
            let waiting = b.wanted.filter { !$0.off }
            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    V3CardTitle("先放着想想的", note: "\(waiting.count) 样")
                    ForEach(Array(waiting.prefix(2).enumerated()), id: \.element.id) { i, w in
                        if i > 0 { V3Divider() }
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(w.name).font(V3.font(14, .bold)).lineLimit(1)
                                Text(w.note).font(V3.font(12, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            V3Amount(w.amount.v3Short, size: 14.5)
                            Button("不要了，钱进目标") { state.resist(wanted: w) }.buttonStyle(.v3(.ghost, .small)).help("这笔钱从平时花的账户挪进大目标")
                            Button { state.change("从清单里拿掉了：\(w.name)", kind: .remove) { try $0.removeWanted(w.id) } } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain).accessibilityLabel("从清单里拿掉\(w.name)")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .v3Card(h: 20, v: 14)
            }
            // 走完的路：存够了的目标收在这里
            if !b.finishedGoals.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    V3CardTitle("走完的路", note: "\(b.finishedGoals.count) 条")
                    ForEach(Array(b.finishedGoals.prefix(3).enumerated()), id: \.element.id) { i, f in
                        if i > 0 { V3Divider() }
                        Button { state.open(.finishedGoal(f.id)) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 14)).foregroundStyle(V3.star)
                                Text(f.name).font(V3.font(14, .bold)).foregroundStyle(V3.ink).lineLimit(1)
                                Text(f.date).font(V3.font(12, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
                                Spacer(minLength: 4)
                                V3Amount(f.total.v3Short, size: 14.5)
                            }
                            .padding(.vertical, 3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .v3Card(h: 20, v: 14)
            }
            Spacer(minLength: 0)
        }
    }

    private func smallCard(_ g: TrialBook.SmallGoal) -> some View {
        V3SmallGoalCard(goal: g)
    }
}

/// 一个小目标的卡片：鼠标移上去浮起来、变成手形，点一下出菜单。
private struct V3SmallGoalCard: View {
    let goal: TrialBook.SmallGoal
    @Environment(V3State.self) private var state
    @State private var hover = false

    var body: some View { card(goal) }

    private func card(_ g: TrialBook.SmallGoal) -> some View {
        Menu {
            Button("存一笔") { state.saveTarget = g.id; state.open(.save) }
            Button("设成大目标") { state.change("好，「\(g.name)」现在是大目标", kind: .goal) { try $0.promoteSmallGoal(g.id) } }
            Button("改名字、金额、日子…") { state.open(.smallGoal(g.id)) }
            Divider()
            Button("删掉…", role: .destructive) { state.open(.goalDelete(g.id)) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(g.name).font(V3.font(14.5, .heavy)).foregroundStyle(V3.ink).lineLimit(1)
                    if g.isDone { V3Tag(text: "存够了", tone: .green) }
                    Spacer(minLength: 4)
                    Text("\(g.saved.v3Short) / \(g.target.v3Short)").font(V3.num(13.5)).foregroundStyle(V3.navy)
                }
                V3Bar(fraction: g.fraction, height: 10)
                if !g.due.isEmpty { Text(g.due).font(V3.font(12, .regular)).foregroundStyle(V3.ink2).lineLimit(1) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .v3Soft(radius: 18)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain)
        .offset(y: hover ? -3 : 0).shadow(color: V3.ink.opacity(hover ? 0.14 : 0), radius: 8, y: 5)
        .animation(.snappy(duration: 0.15), value: hover)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityLabel("小目标 \(g.name)，存了 \(g.saved.v3Short)，一共要 \(g.target.v3Short)")
    }
}
#endif
