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
    var reachedDates: [Int: String] { [0: "9 月 3 日", 2: "10 月 12 日"] }
    var deadline: String { "12 月 20 日" }
    /// 照现在的速度，月底大概能存到多少（示例：再存 30 €）。
    var projectedThisMonth: Money { book.journey.savedThisMonth + Money(cents: 30_00) }
    var lastMonthSpentSoFar: Money { Money(cents: 1_249_39) }
    var lastMonthNet: Money { Money(cents: 2_170_61) }
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
        let m = b.month
        let j = b.journey
        return VStack(spacing: 14) {
            if b.emergencyAccounts.isEmpty {
                V3Ask(face: "calm", text: "要不要把一个账户设成应急钱？") {
                    Button("设一下") { state.closeChat(); state.open(.emergency) }.buttonStyle(.v3(.primary, .small))
                }
            } else {
                V3Ask(face: "calm", text: "照这样花，这个月存钱差一点。") {
                    Button("看看") { state.go(.goals) }.buttonStyle(.v3(.primary, .small))
                }
            }
            // 这一页最重要的数
            VStack(alignment: .leading, spacing: 8) {
                V3Label("11 月 · 现在还能随便花")
                V3Gold(amount: m.left, size: 72)
                Text(m.left > .zero ? "到月底还有 \(m.daysLeft) 天，平均每天能花 \(Money(cents: m.perDay.cents / 100 * 100).v3Short)"
                     : "这个月能随便花的已经用完了，到月底还有 \(m.daysLeft) 天")
                    .font(V3.font(14, .bold)).foregroundStyle(m.left > .zero ? V3.green : V3.red).contentTransition(.numericText())
                HStack(spacing: 26) {
                    V3KV(value: m.income.v3Signed, label: "进账", color: V3.green)
                    V3KV(value: (-m.fixed).v3Signed, label: "固定要付的")
                    V3KV(value: (-m.forGoals).v3Signed, label: "留给目标")
                    V3KV(value: (-m.spent).v3Signed, label: "已经花掉")
                }
                .padding(.top, 2)
            }
            .padding(.init(top: 18, leading: 24, bottom: 34, trailing: 24))
            .frame(maxWidth: .infinity, alignment: .leading)
            .v3Sticker().v3WaveBottom()
            .accessibilityElement(children: .combine)

            HStack(spacing: 14) {
                let diff = state.lastMonthSpentSoFar - m.spentTotal
                smallCard("这个月花掉", m.spentTotal.v3,
                          diff >= .zero ? "比上月同期少 \(diff.v3Short)" : "比上月同期多 \(diff.magnitude.v3Short)",
                          diff >= .zero ? V3.green : V3.navy) { state.go(.spending) }
                let delta = b.totals.net - state.lastMonthNet
                smallCard("家底 · 净剩", b.totals.net.v3,
                          delta >= .zero ? "比上个月多 \(delta.v3Short)" : "比上个月少 \(delta.magnitude.v3Short)",
                          delta >= .zero ? V3.green : V3.navy) { state.go(.wealth) }
            }

            VStack(alignment: .leading, spacing: 4) {
                V3CardTitle("\(j.name)的路", note: j.isFinished ? "走完了" : "\(state.deadline)前到 \(j.nextStation?.target.v3Short ?? "")") {
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
                V3CardTitle(title: "今天自己进来的") { EmptyView() } trail: {
                    Button { state.go(.transactions) } label: {
                        Text("\(b.today.count) 笔 · 全部 ›").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                    }
                    .buttonStyle(V3SinkStyle(depth: 1))
                }
                V3Rows(data: Array(b.today.prefix(3))) { e in
                    Button { state.txFocus = e.id; state.go(.transactions) } label: {
                        V3Row(emoji: e.emoji, name: e.name, meta: e.meta, amount: e.amount.v3, tag: e.tag, compact: true).contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1))
                }
            }
            .v3Card(h: 16, v: 14)

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

// MARK: - 家底

struct V3WealthPage: View {
    @Environment(V3State.self) private var state
    private let cols3 = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        GeometryReader { g in
            let leftW = (g.size.width - 18) * 1.5 / 2.5
            HStack(alignment: .top, spacing: 18) {
                left.frame(width: leftW)
                right
            }
        }
    }

    private var left: some View {
        let b = state.book
        let delta = b.totals.net - state.lastMonthNet
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) { V3Label("一共有"); V3Amount(b.totals.have.v3, size: 25, weight: .heavy) }.v3Card(h: 18, v: 14)
                VStack(alignment: .leading, spacing: 4) { V3Label("欠别人"); V3Amount(b.totals.owe.v3, color: V3.red, size: 25, weight: .heavy) }.v3Card(h: 18, v: 14)
                VStack(alignment: .leading, spacing: 2) {
                    V3Label("净剩")
                    V3Gold(amount: b.totals.net, size: 36)
                    Text(delta >= .zero ? "比上个月多 \(delta.v3Short)" : "比上个月少 \(delta.magnitude.v3Short)")
                        .font(V3.font(13.5, .bold)).foregroundStyle(delta >= .zero ? V3.green : V3.navy).contentTransition(.numericText())
                }
                .padding(.horizontal, 18).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
                .frame(width: nil).layoutPriority(1)
            }
            V3CardTitle(title: "我的账户") { V3Tag(text: "\(b.owned.count) 个") } trail: {
                EmptyView()
            }
            LazyVGrid(columns: cols3, spacing: 12) {
                ForEach(b.owned) { a in card(a) }
                if let s = b.accounts.first(where: { $0.kind == .secret }) { secret(s) }
            }
            V3CardTitle("欠的和借出去的")
            LazyVGrid(columns: cols3, spacing: 12) {
                ForEach(b.debts + b.lent) { a in card(a) }
            }
            Spacer(minLength: 0)
        }
    }

    private func card(_ a: V3State.Account) -> some View {
        Button {
            if a.kind == .debt || a.kind == .lent { state.go(.debts) } else { state.accountFocus = a.name; state.open(.accounts) }
        } label: { cardBody(a) }
        .buttonStyle(V3SinkStyle(depth: 2))
        .help(a.kind == .debt || a.kind == .lent ? "去欠款与还债" : "改这个账户")
    }

    private func cardBody(_ a: V3State.Account) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                V3Ico(emoji: a.emoji, size: 32)
                Text(a.name).font(V3.font(14, .heavy)).foregroundStyle(V3.ink).lineLimit(1)
            }
            V3Amount(a.balance.v3, color: a.isDebt ? V3.red : a.kind == .shop ? V3.teal : V3.navy, size: 21, weight: .heavy)
            Text(a.note).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
        .v3Soft(radius: 18, fill: a.isDebt ? V3.hex(0xFFF6F5) : .white)
        .accessibilityElement(children: .combine)
    }

    /// 私房钱：默认藏着，点一下显示 3 秒，不算进上面的数。
    private func secret(_ a: V3State.Account) -> some View {
        Button { state.revealSecret() } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    V3Ico(emoji: state.secretShown ? "👀" : "🙈", size: 32)
                    Text(a.name).font(V3.font(14, .heavy)).foregroundStyle(V3.ink)
                }
                V3Amount(state.secretShown ? a.balance.v3 : "•••••\u{00A0}€", size: 21, weight: .heavy)
                Text(a.note).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(V3.dash, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            .contentShape(Rectangle())
        }
        .buttonStyle(V3SinkStyle(depth: 2))
        .accessibilityLabel(state.secretShown ? "私房钱 \(a.balance.v3)" : "私房钱，藏着，点一下显示")
    }

    private var right: some View {
        let b = state.book
        let parts: [(String, Money, Color)] = [
            ("应急钱，不动", b.sum(.emergency), V3.navy), ("存在目标里", b.sum(.goal), V3.star),
            ("日常能用", b.sum(.daily), V3.sky),
        ]
        let total = max(b.totals.have.cents, 1)
        let run = b.runway
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                V3CardTitle("这些钱分成三块")
                GeometryReader { g in
                    HStack(spacing: 0) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                            Rectangle().fill(p.2).frame(width: g.size.width * CGFloat(p.1.cents) / CGFloat(total))
                        }
                    }
                }
                .frame(height: 26).clipShape(Capsule()).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2.5))
                .animation(.spring(duration: 0.5), value: b.totals)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        HStack(spacing: 5) {
                            V3Amount(p.1.v3Short, color: V3.ink, size: 14.5)
                            Circle().fill(p.2).frame(width: 9, height: 9)
                            Text(p.0).font(V3.font(13, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
                        }
                    }
                }
            }
            .v3Card()

            VStack(alignment: .leading, spacing: 10) {
                if b.emergencyAccounts.isEmpty {
                    V3CardTitle("应急钱")
                    Text("还没设应急钱").font(V3.font(20, .heavy)).foregroundStyle(V3.ink)
                    Button("设一下") { state.open(.emergency) }.buttonStyle(.v3(.primary, .small))
                } else {
                    // 点这一块：改放在哪几个账户、想存够几个月
                    Button { state.open(.emergency) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            V3CardTitle(title: "应急钱") { V3Tag(text: b.emergencyAccounts.map(\.name).joined(separator: "、")) } trail: {
                                Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold)).foregroundStyle(V3.ink2)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                V3Label("万一没了收入，能撑")
                                V3Amount("\(run.monthsText) 个月", size: 32, weight: .heavy)
                            }
                            V3Bar(fraction: run.fraction(of: Double(b.emergencyGoalMonths)), height: 16)
                            HStack {
                                V3Label("有 \(b.sum(.emergency).v3Short)", size: 12.5)
                                Spacer()
                                V3Label("想存够 \(b.emergencyGoalMonths) 个月 · \(b.emergencyGoal.v3Short)", size: 12.5)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 2)).help("改应急钱放在哪、想存够几个月")
                }
                Spacer(minLength: 0)
                switch b.emergencyAccounts.isEmpty ? Bool?.some(false) : b.splitWithEmergency {
                case nil:
                    V3Ask(face: "calm", text: "应急钱才 \(run.monthsText) 个月。存的钱分一半给它？") {
                        HStack(spacing: 8) {
                            Button("好，一半一半") { state.change("好，以后存钱自动对半分") { $0.splitWithEmergency = true } }.buttonStyle(.v3(.primary, .small))
                            Button("全给电脑") { state.change("好，全给电脑") { $0.splitWithEmergency = false } }.buttonStyle(.v3(.ghost, .small))
                        }
                    }
                case true?:
                    V3Ask(face: "happy", text: "记住了，以后对半分。", tone: .good)
                case false?:
                    V3Ask(face: "calm", text: "好，全给电脑。想改再说。")
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .v3Soft()
        }
    }
}

// MARK: - 目标

struct V3GoalsPage: View {
    @Environment(V3State.self) private var state

    var body: some View {
        GeometryReader { g in
            let leftW = (g.size.width - 18) * 1.45 / 2.45
            HStack(alignment: .top, spacing: 18) {
                left(width: leftW).frame(width: leftW)
                right
            }
        }
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
                    }
                }
                V3Road(journey: j, captions: state.roadCaptions).frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 10) {
                    Button { state.open(.monthlyPlan) } label: {
                        HStack(spacing: 8) {
                            Text("这个月").font(V3.font(13, .bold)).foregroundStyle(V3.ink)
                            V3Bar(fraction: plan > .zero ? Double(j.savedThisMonth.cents) / Double(plan.cents) : 0, height: 10).frame(width: 120)
                            Text("\(j.savedThisMonth.v3Short) / \(plan.v3Short)").font(V3.num(13.5)).foregroundStyle(V3.navy)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1)).help("改每月存多少")
                    Spacer(minLength: 6)
                    // 到站收到的信：点信封打开
                    ForEach(state.book.letters.suffix(3)) { l in
                        Button { state.openMoment(.letter(l)) } label: {
                            Label(l.title, systemImage: "envelope").font(V3.font(12.5, .bold)).foregroundStyle(V3.ink)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(V3.paper).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                        }
                        .buttonStyle(V3SinkStyle(depth: 2)).accessibilityLabel("\(l.date)的信：\(l.title)")
                    }
                    if !j.isFinished, j.remainingToNext > Money(cents: 20_00) {
                        Button("存够这一站") { state.depositAndCelebrate(j.remainingToNext) }.buttonStyle(.v3(.ghost, .small))
                    }
                }
            }
            .padding(.init(top: 16, leading: 20, bottom: 26, trailing: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v3Sticker().v3WaveBottom()
            Group {
                if j.isFinished {
                    V3Ask(face: "celebrate", text: "走完了！\(j.total.v3Short) 都存够了。", tone: .good)
                } else {
                    let name = j.nextStation.flatMap { $0.title.isEmpty ? nil : "「\($0.title)」那一站" } ?? "下一站"
                    V3Ask(face: "happy", text: "离\(name)还差 \(j.remainingToNext.v3Short)，\(state.deadline)前有点悬。") {
                        HStack(spacing: 8) {
                            Button("看看办法") { state.openMoment(.smallerStep) }.buttonStyle(.v3(.primary, .small))
                            Button("先不用") { state.say("好，我 12 月 10 日再看一眼") }.buttonStyle(.v3(.ghost, .small))
                        }
                    }
                }
            }
            .frame(width: width * 0.86).frame(maxWidth: .infinity, alignment: .leading)
        }
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
                            Button("不要了，钱进目标") { state.resist(wanted: w) }.buttonStyle(.v3(.ghost, .small)).help("这笔钱从日常卡挪进大目标")
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
            Spacer(minLength: 0)
        }
    }

    private func smallCard(_ g: TrialBook.SmallGoal) -> some View {
        Menu {
            Button("存一笔") { state.saveTarget = g.id; state.open(.save) }
            Button("设成大目标") { state.change("好，「\(g.name)」现在是大目标", kind: .goal) { try $0.promoteSmallGoal(g.id) } }
            Button("改名字、金额、日子…") { state.open(.smallGoal(g.id)) }
            Divider()
            Button("删掉（存的钱回日常卡）") { state.change("删掉了：\(g.name)", kind: .remove) { try $0.removeSmallGoal(g.id) } }
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
        .accessibilityLabel("小目标 \(g.name)，存了 \(g.saved.v3Short)，一共要 \(g.target.v3Short)")
    }
}
#endif
