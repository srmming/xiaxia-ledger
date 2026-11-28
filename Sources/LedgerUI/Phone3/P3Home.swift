#if os(iOS)
import FinanceCore
import SwiftUI

// 总览：一屏看完。最要紧的数是金色贴纸卡；夏夏像微信里的一行会话，有话说才有小红点。

struct P3HomePage: View {
    @Environment(P3State.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            P3Header(title: state.side == .biz ? "店里" : "总览", months: true, sideSwitch: true, meButton: true)
            ScrollView {
                VStack(spacing: 12) {
                    if state.side == .biz { P3BizHome() } else { P3LifeHome() }
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - 生活

struct P3LifeHome: View {
    @Environment(P3State.self) private var state

    var body: some View {
        let b = state.book
        let m = state.monthData
        let now = state.isThisMonth
        hero(b, m, now)
        HStack(spacing: 12) {
            // 「一共花掉」= 固定要付的 + 随手花的，和上面那行四个数分得清
            small(now ? "这个月一共花掉" : "\(state.monthTitle)一共花掉", m.spentTotal.p3, now ? spentNote : "固定的加随手花的", now ? P3.green : P3.ink2) { state.go(.spending) }
            small(now ? "家底 · 净剩" : "\(state.monthTitle)底 · 净剩", (now ? b.totals.net : m.net).p3,
                  now ? state.compare(b.totals.net, state.lastMonthNet) : "那个月最后的家底", now ? P3.green : P3.ink2) { state.go(.wealth) }
        }
        if now {
            goalCard(b.journey)
            today(b)
        } else {
            pastEntries(m)
        }
    }

    private var spentNote: String {
        let d = state.lastMonthSpentSoFar - state.book.month.spentTotal
        return d >= .zero ? "比上月同期少 \(d.p3Short)" : "比上月同期多 \(d.magnitude.p3Short)"
    }

    private func hero(_ b: TrialBook, _ m: TrialBook.MonthData, _ now: Bool) -> some View {
        let live = b.month
        return VStack(alignment: .leading, spacing: 6) {
            P3Label(now ? "\(state.monthTitle) · 现在还能随便花" : "\(state.monthTitle) · 最后剩下")
            P3Gold(amount: m.left, size: 56)
            if now {
                Text(live.left > .zero ? "到月底还有 \(live.daysLeft) 天，一天大概 \(Money(cents: live.perDay.cents / 100 * 100).p3Short)"
                     : "这个月能随便花的用完了，到月底还有 \(live.daysLeft) 天")
                    .font(P3.font(13.5, .bold)).foregroundStyle(live.left > .zero ? P3.green : P3.red)
            }
            HStack(spacing: 0) {
                kv("+" + m.income.p3Short, "进账", P3.green)
                kv((-m.fixed).p3Short, "固定要付")
                kv((-m.forGoals).p3Short, "留给目标")
                kv((-m.spent).p3, "随手花的")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .p3Sticker()
        .accessibilityElement(children: .combine)
    }

    /// 过去的月份：那个月记的几笔。
    private func pastEntries(_ m: TrialBook.MonthData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            P3SectionTitle(title: "\(state.monthTitle)的流水", trail: "\(m.entries.count) 笔 · 全部 ›")
            if m.entries.isEmpty {
                Text("那个月没有记录").font(P3.font(14, .regular)).foregroundStyle(P3.ink2).padding(.vertical, 12)
            }
            ForEach(Array(m.entries.prefix(4).enumerated()), id: \.element.id) { i, e in
                if i > 0 { P3Divider().padding(.leading, 48) }
                P3Row(emoji: e.emoji, name: e.name, meta: e.meta, amount: e.amount.p3, color: e.amount > .zero ? P3.green : P3.navy)
            }
        }
        .p3Card(h: 16, v: 12)
        .onTapGesture { withAnimation { state.tab = .flow } }
    }

    private func kv(_ v: String, _ l: String, _ c: Color = P3.ink) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(P3.num(13, .bold)).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7)
            Text(l).font(P3.font(11, .regular)).foregroundStyle(P3.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ label: String, _ value: String, _ note: String, _ c: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                P3Label(label, size: 12.5)
                Text(value).font(P3.num(20, .heavy)).foregroundStyle(P3.ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(note).font(P3.font(12, .bold)).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.8)
            }
            .p3Card(h: 14, v: 12, radius: 18)
        }
        .buttonStyle(P3Sink())
    }

    @ViewBuilder private func goalCard(_ j: Journey) -> some View {
        if j.total > .zero {
            Button { withAnimation(.snappy(duration: 0.18)) { state.tab = .goals } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(j.name).font(P3.font(15.5, .heavy)).foregroundStyle(P3.ink)
                        P3Tag(text: j.isFinished ? "存够了" : "这一站还差 \(j.remainingToNext.p3Short)", tone: .gold)
                        Spacer()
                        Text("\(j.saved.p3Short) / \((j.nextStation?.target ?? j.total).p3Short)").font(P3.num(14)).foregroundStyle(P3.navy)
                    }
                    HStack(spacing: 12) {
                        P3Bar(fraction: j.position.fraction)
                        Button("+ 存一笔") { state.sheet = .save(nil) }.buttonStyle(.p3(.primary, .small))
                    }
                }
                .p3Card(h: 16, v: 12)
            }
            .buttonStyle(P3Sink())
        } else {
            Button { state.sheet = .newBigGoal } label: {
                Text("+ 定一个大目标").font(P3.font(15, .bold)).foregroundStyle(P3.navy)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(P3.dash, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
            .buttonStyle(P3Sink())
        }
    }

    private func today(_ b: TrialBook) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            P3SectionTitle(title: "今天", trail: "\(b.today.count) 笔")
            if b.today.isEmpty {
                Text("今天还没记。点下面的 + 记一笔").font(P3.font(14, .regular)).foregroundStyle(P3.ink2).padding(.vertical, 12)
            }
            ForEach(Array(b.today.prefix(3).enumerated()), id: \.element.id) { i, e in
                if i > 0 { P3Divider().padding(.leading, 48) }
                Button { state.sheet = .edit(e.id) } label: {
                    P3Row(emoji: e.emoji, name: e.name, meta: e.meta, amount: e.amount.p3, color: e.amount > .zero ? P3.green : P3.navy)
                }
                .buttonStyle(P3Sink(depth: 1))
            }
        }
        .p3Card(h: 16, v: 12)
    }
}

// MARK: - 生意

struct P3BizHome: View {
    @Environment(P3State.self) private var state

    var body: some View {
        let b = state.book
        let m = state.monthData
        let now = state.isThisMonth
        let inn = now ? b.shopFlowIn : m.shopIn, out = now ? b.shopFlowOut : m.shopOut
        VStack(alignment: .leading, spacing: 6) {
            P3Label("\(state.monthTitle) · 店里收进来")
            if inn == .zero && out == .zero {
                Text("那个月没有记生意的账").font(P3.font(20, .heavy)).foregroundStyle(P3.ink2).padding(.vertical, 12)
            } else {
                P3Gold(amount: inn, size: 56)
                Text("花出去 \(out.p3Short)，\(inn >= out ? "剩 \((inn - out).p3Short)" : "亏 \((out - inn).p3Short)")")
                    .font(P3.font(13.5, .bold)).foregroundStyle(inn >= out ? P3.teal : P3.red)
                if now { Text("开了 \(b.shopOpenDays) 天").font(P3.font(12.5, .regular)).foregroundStyle(P3.ink2) }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .p3Sticker()

        HStack(spacing: 12) {
            let w = b.shopWorth
            card("店里有", w.cash.p3, "欠着 \(w.owes.p3Short)") { withAnimation { state.tab = .goals } }
            card("固定开销", b.fixedTotal.p3, "每月要付") { state.go(.fixed) }
        }

        VStack(alignment: .leading, spacing: 2) {
            let rows = b.shopFlow(in: state.monthKey)
            P3SectionTitle(title: now ? "最近" : "\(state.monthTitle)的流水", trail: "全部 ›")
            if rows.isEmpty { Text("那个月没有记录").font(P3.font(14, .regular)).foregroundStyle(P3.ink2).padding(.vertical, 12) }
            ForEach(Array(rows.prefix(4).enumerated()), id: \.element.id) { i, r in
                if i > 0 { P3Divider().padding(.leading, 48) }
                P3Row(emoji: r.emoji, name: r.title, meta: "\(r.day) 号 · \(r.detail)", amount: r.amount.p3Signed, color: r.amount > .zero ? P3.teal : P3.navy)
            }
        }
        .p3Card(h: 16, v: 12)
        .onTapGesture { withAnimation { state.tab = .flow } }
    }

    private func card(_ label: String, _ value: String, _ note: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                P3Label(label, size: 12.5)
                Text(value).font(P3.num(20, .heavy)).foregroundStyle(P3.ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(note).font(P3.font(12, .bold)).foregroundStyle(P3.ink2).lineLimit(1)
            }
            .p3Card(h: 14, v: 12, radius: 18)
        }
        .buttonStyle(P3Sink())
    }
}
#endif
