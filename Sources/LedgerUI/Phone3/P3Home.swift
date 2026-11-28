#if os(iOS)
import FinanceCore
import SwiftUI

// 总览：一屏看完。最要紧的数是金色贴纸卡；夏夏像微信里的一行会话，有话说才有小红点。

struct P3HomePage: View {
    @Environment(P3State.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            P3Header(title: state.side == .biz ? "店里" : "总览", months: true, sideSwitch: true)
            ScrollView {
                VStack(spacing: 12) {
                    P3XiaRow()
                    if state.side == .biz { P3BizHome() } else { P3LifeHome() }
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// 夏夏的入口：像微信会话列表里的一行（头像、名字、时间、最后一句、小红点）。
struct P3XiaRow: View {
    @Environment(P3State.self) private var state
    var body: some View {
        let c = state.chat
        Button { state.chatOpen = true; state.chat.unread = 0 } label: {
            HStack(spacing: 12) {
                P3.face(c.unread > 0 ? "talk" : "calm").resizable().scaledToFill()
                    .frame(width: 46, height: 46)
                    .background(P3.soft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if c.unread > 0 {
                            Text("\(c.unread)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18).background(Circle().fill(P3.red)).offset(x: 6, y: -6)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("夏夏").font(P3.font(16, .bold)).foregroundStyle(P3.ink)
                        Spacer()
                        Text(c.lastTime).font(P3.font(12, .regular)).foregroundStyle(P3.ink2)
                    }
                    Text(c.lastLine).font(P3.font(13.5, .regular)).foregroundStyle(P3.ink2).lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .p3Soft(radius: 18)
        }
        .buttonStyle(P3Sink(depth: 1))
        .accessibilityLabel(c.unread > 0 ? "夏夏，\(c.unread) 条新消息：\(c.lastLine)" : "夏夏：\(c.lastLine)")
        .accessibilityHint("打开和夏夏的对话")
    }
}

// MARK: - 生活

struct P3LifeHome: View {
    @Environment(P3State.self) private var state

    var body: some View {
        let b = state.book
        if state.isThisMonth {
            hero(b)
        } else {
            past
        }
        HStack(spacing: 12) {
            let spent = state.isThisMonth ? b.month.spentTotal : state.pastSlices.map(\.amount).reduce(.zero, +)
            small("\(state.monthTitle)花掉", spent.p3, state.isThisMonth ? "比上月同期少 86 €" : "看看花在哪", P3.green) { state.go(.spending) }
            small("家底 · 净剩", b.totals.net.p3, "比上个月多 490 €", P3.green) { state.go(.wealth) }
        }
        goalCard(b.journey)
        today(b)
    }

    private func hero(_ b: TrialBook) -> some View {
        let m = b.month
        return VStack(alignment: .leading, spacing: 6) {
            P3Label("\(state.monthTitle) · 现在还能随便花")
            P3Gold(amount: m.left, size: 56)
            Text(m.left > .zero ? "到月底还有 \(m.daysLeft) 天，一天大概 \(Money(cents: m.perDay.cents / 100 * 100).p3Short)"
                 : "这个月能随便花的用完了，到月底还有 \(m.daysLeft) 天")
                .font(P3.font(13.5, .bold)).foregroundStyle(m.left > .zero ? P3.green : P3.red)
            HStack(spacing: 0) {
                kv("+" + m.income.p3Short, "进账", P3.green)
                kv((-m.fixed).p3Short, "固定要付")
                kv((-m.forGoals).p3Short, "留给目标")
                kv((-m.spent).p3, "已经花掉")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .p3Sticker()
        .accessibilityElement(children: .combine)
    }

    private var past: some View {
        let slices = state.pastSlices
        let spent = slices.map(\.amount).reduce(.zero, +)
        return VStack(alignment: .leading, spacing: 6) {
            P3Label("\(state.monthTitle) · 一共存下")
            if slices.isEmpty {
                Text("那个月还没有记账").font(P3.font(20, .heavy)).foregroundStyle(P3.ink2).padding(.vertical, 12)
                Text("在 Mac 上导入那个月的流水后，这里就有数了").font(P3.font(13, .regular)).foregroundStyle(P3.ink2)
            } else {
                P3Gold(amount: state.lastMonthIncome - spent, size: 56)
                Text("进账 \(state.lastMonthIncome.p3Short)，花掉 \(spent.p3Short)").font(P3.font(13.5, .bold)).foregroundStyle(P3.green)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .p3Sticker()
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
        VStack(alignment: .leading, spacing: 6) {
            P3Label("\(state.monthTitle) · 营业额")
            if state.isThisMonth {
                P3Gold(amount: b.shopSalesTotal, size: 56)
                Text("开了 \(b.shopOpenDays) 天 · 一天收够 \(b.dailyBreakEven.p3Short) 就不亏").font(P3.font(13.5, .bold)).foregroundStyle(P3.teal)
            } else {
                Text("那个月还没有记账").font(P3.font(20, .heavy)).foregroundStyle(P3.ink2).padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .p3Sticker()

        if let d = b.shopDays.first(where: { $0.day == b.todayDay }), d.state == .missing, state.isThisMonth {
            P3Bubble(face: "talk", text: "今天（\(b.todayDay) 号）收了多少还没记。") {
                Button("记今天的账") { state.sheet = .add }.buttonStyle(.p3(.teal, .small))
            }
        }

        HStack(spacing: 12) {
            let w = b.shopAccounts
            let have = w.filter { $0.kind == .shop }.map(\.balance).reduce(.zero, +)
            let owe = w.filter { $0.kind == .debt }.map(\.balance).reduce(.zero, +)
            card("店里有", have.p3, "欠着 \(owe.p3Short)") { withAnimation { state.tab = .goals } }
            card("固定开销", b.fixedTotal.p3, "每月要付") { state.go(.fixed) }
        }

        VStack(alignment: .leading, spacing: 2) {
            P3SectionTitle(title: "最近", trail: "全部 ›")
            ForEach(Array(b.shopFlow.prefix(4).enumerated()), id: \.element.id) { i, r in
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
