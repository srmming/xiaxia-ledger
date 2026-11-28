#if os(macOS)
import FinanceCore
import SwiftUI
import UniformTypeIdentifiers

// 生活这边其余的页：花销、趋势、流水、花钱前想想（含大决定）、订阅、欠款与还债、每月小结。
// 数字是设计稿里那套编的示例；能跟着动的（还能随便花、目标）都从同一份状态里算。

/// 点了弹一句提示的小按钮（夏夏气泡里的回答）。
struct V3SayButton: View {
    let title: String
    let toast: String
    var kind: V3ButtonStyle.Kind = .primary
    var size: V3ButtonStyle.Size = .small
    @Environment(V3State.self) private var state
    init(_ title: String, _ toast: String, _ kind: V3ButtonStyle.Kind = .primary, size: V3ButtonStyle.Size = .small) {
        self.title = title; self.toast = toast; self.kind = kind; self.size = size
    }
    var body: some View { Button(title) { state.say(toast) }.buttonStyle(.v3(kind, size)) }
}

/// 夏夏问一句，回答完换成一句「好的」。
struct V3Question: View {
    let face: String
    let text: String
    var tone: V3Bubble<AnyView>.Tone = .plain
    var kicker = ""
    /// (按钮上的字, 点了以后底部说的话)
    let answers: [(String, String)]
    /// 点了第几个按钮以后真的去做的事。
    var onAnswer: (Int) -> Void = { _ in }
    @Environment(V3State.self) private var state
    @State private var answered: String?
    var body: some View {
        V3Ask(face: answered == nil ? face : "happy", text: answered ?? text, tone: answered == nil ? tone : .good, kicker: answered == nil ? kicker : "") {
            AnyView(Group {
                if answered == nil {
                    HStack(spacing: 8) {
                        ForEach(Array(answers.enumerated()), id: \.offset) { i, a in
                            Button(a.0) {
                                state.say(a.1)
                                onAnswer(i)
                                withAnimation(.snappy(duration: 0.2)) { answered = a.1 }
                            }
                            .buttonStyle(.v3(i == 0 ? .primary : .ghost, .small))
                        }
                    }
                }
            })
        }
    }
}

struct V3RowData: Identifiable {
    let id = UUID()
    var emoji: String
    var name: String
    var meta: String
    var amount: String
    var color: Color = V3.navy
    var tag = ""
    var tone: V3Tag.Tone = .blue
    /// 点这一行做什么（没有就不能点）。
    var action: (() -> Void)?
    init(_ emoji: String, _ name: String, _ meta: String, _ amount: String, _ color: Color = V3.navy, tag: String = "", tone: V3Tag.Tone = .blue, action: (() -> Void)? = nil) {
        self.emoji = emoji; self.name = name; self.meta = meta; self.amount = amount; self.color = color; self.tag = tag; self.tone = tone; self.action = action
    }
}

struct V3RowList: View {
    let rows: [V3RowData]
    var compact = false
    /// 把卡片剩下的高度分给每一行（每行最高 120），不让下半张卡空着。
    var fill = false
    var body: some View {
        V3Rows(data: rows) { r in
            Group {
                if let action = r.action {
                    Button(action: action) {
                        V3Row(emoji: r.emoji, name: r.name, meta: r.meta, amount: r.amount, color: r.color, tag: r.tag, compact: compact, tagTone: r.tone)
                            .frame(maxHeight: fill ? .infinity : nil).contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1))
                } else {
                    V3Row(emoji: r.emoji, name: r.name, meta: r.meta, amount: r.amount, color: r.color, tag: r.tag, compact: compact, tagTone: r.tone)
                }
            }
            .frame(maxHeight: fill ? 120 : nil)
        }
    }
}

// MARK: - 花销

struct V3SpendingPage: View {
    @Environment(V3State.self) private var state
    /// 鼠标正指着的那个分类：圆环上那一段和右边那一行一起亮。
    @State private var hot: String?
    static let colors: [UInt32] = [0x7FA3F0, 0xC9A0DC, 0x6CC5A8, 0xF2A65A, 0x8FB5F5, 0x9AD0E0, 0xD9A27A, 0xB8BEDA]

    var body: some View {
        // 切到哪个月，大数、圆环、右边的单子都是那个月的
        let m = state.monthData
        let now = state.isThisMonth
        let diff = state.lastMonthSpentSoFar - m.spentTotal
        let slices = m.topSlices()
        let total = m.sliceTotal
        let biggest = slices.map(\.amount.cents).max() ?? 1
        V3Cols(left: 1.1, right: 1) {
            VStack(spacing: 16) {
                if now, state.canCompareSpend { V3Ask(face: diff >= .zero ? "happy" : "calm",
                      text: diff >= .zero ? "比上月同期少花 \(diff.v3Short)\(state.book.savedPhrase(diff).isEmpty ? "" : "，" + state.book.savedPhrase(diff))。" : "比上月同期多花 \(diff.magnitude.v3Short)，跟你说一声。",
                      tone: diff >= .zero ? .good : .plain) }
                V3KeyCard(label: now ? "\(state.monthLabel)到今天花掉" : "\(state.monthLabel)花掉", amount: m.spentTotal, size: 56) {
                    HStack(spacing: 26) {
                        // 这里说的是「花掉」的，所以固定的只算已经付掉的那部分（还没到日子的在「接下来要付的」里）
                        V3KV(value: (now ? state.book.month.fixedPaid : m.fixed).v3, label: now && state.book.month.fixedLeft > .zero ? "固定的已经付了" : "固定要付的")
                        V3KV(value: m.spent.v3, label: "随手花的")
                    }
                }
                // 按分类的圆环：颜色和右边每一行一一对上，中间是这个月花掉的总数
                V3GrowCard {
                    HStack(spacing: 14) {
                        V3Donut(slices: slices.map { (id: $0.name, value: Double($0.amount.cents)) }, colors: Self.colors, hot: $hot) { name in
                            state.txQuery = name; state.go(.transactions)
                        } center: { side in
                            // 平时是这个月的总数；鼠标指着哪一段，就是那一类的名字和数。不做滚动的数字动画，落下来就是清楚的最终数。
                            let shown = slices.first { $0.name == hot }
                            VStack(spacing: 1) {
                                Text((shown?.amount ?? total).v3Short).font(V3.num(side * 0.13, .heavy)).foregroundStyle(V3.ink)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                Text(shown?.name ?? "花掉").font(V3.font(max(side * 0.058, 11), .semibold)).foregroundStyle(V3.ink2).lineLimit(1)
                            }
                            .frame(width: side * 0.5)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(6)
                        .accessibilityElement().accessibilityLabel("\(state.monthLabel)花掉 \(total.v3)，最多的是\(slices.first?.name ?? "")")
                        // 小的柱状图：每周平时花的。这个月和上个月比，过去的月份只画那个月的
                        VStack(alignment: .leading, spacing: 6) {
                            V3Label("每周平时花的", size: 12.5, weight: .bold)
                            Group { if now { V3WeeklyBars(compact: true) } else { V3MonthBars(weekly: m.weekly) } }.frame(height: 120)
                        }
                        .frame(width: 168).frame(maxHeight: .infinity, alignment: .center)
                    }
                }
            }
        } trailing: {
            V3GrowCard(spacing: 0) {
                V3CardTitle("花得最多的").padding(.bottom, 6)
                ForEach(Array(slices.enumerated()), id: \.element.id) { i, t in
                    Button { state.txQuery = t.name; state.go(.transactions) } label: {
                    HStack(spacing: 12) {
                        V3Ico(emoji: t.emoji)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(V3.font(14, .bold))
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(V3.bg)
                                    Capsule().fill(V3.hex(Self.colors[i % Self.colors.count])).frame(width: max(g.size.width * Double(t.amount.cents) / Double(biggest), 6))
                                    Rectangle().fill(V3.ink).frame(width: 2, height: 15).offset(x: min(g.size.width * Double(t.lastMonth.cents) / Double(biggest), g.size.width) - 1)
                                }
                            }
                            .frame(height: 9)
                        }
                        V3Amount(t.amount.v3).frame(width: 96, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(hot == t.name ? V3.soft : .clear))
                    .opacity(hot == nil || hot == t.name ? 1 : 0.55)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1)).help("去流水里只看「\(t.name)」")
                    .onHover { inside in withAnimation(.snappy(duration: 0.12)) { hot = inside ? t.name : (hot == t.name ? nil : hot) } }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// 圆环图：一段一个分类。鼠标移到哪一段，那一段亮起来、别的变淡；点了做 `pick`。中间放一块自己的内容（给它圆环的边长）。
struct V3Donut<Center: View>: View {
    let slices: [(id: String, value: Double)]
    let colors: [UInt32]
    @Binding var hot: String?
    var pick: (String) -> Void
    @ViewBuilder var center: (CGFloat) -> Center

    /// 鼠标在圆环的哪一段上（不在环上就是 nil）。0 在正上方，顺时针。
    static func slice(at p: CGPoint, side: CGFloat, slices: [(id: String, value: Double)]) -> String? {
        let c = CGPoint(x: side / 2, y: side / 2)
        let dx = p.x - c.x, dy = p.y - c.y
        let r = (dx * dx + dy * dy).squareRoot()
        let outer = side / 2 - 4, inner = outer - side * 0.2
        guard r >= inner - 2, r <= outer + 4 else { return nil }
        var turn = atan2(dx, -dy) / (2 * .pi)
        if turn < 0 { turn += 1 }
        let total = max(slices.map(\.value).reduce(0, +), 1)
        var acc = 0.0
        for s in slices {
            acc += s.value / total
            if turn <= acc { return s.id }
        }
        return slices.last?.id
    }

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let total = max(slices.map(\.value).reduce(0, +), 1)
            let starts = slices.indices.map { i in slices[..<i].map(\.value).reduce(0, +) / total }
            ZStack {
                ForEach(Array(slices.enumerated()), id: \.element.id) { i, s in
                    let on = hot == s.id
                    V3DonutSlice(from: starts[i], to: starts[i] + s.value / total, thickness: side * 0.2)
                        .fill(V3.hex(colors[i % colors.count]))
                        .overlay(V3DonutSlice(from: starts[i], to: starts[i] + s.value / total, thickness: side * 0.2).stroke(V3.ink, lineWidth: 2.5))
                        .scaleEffect(on ? 1.05 : 1)
                        .opacity(hot == nil || on ? 1 : 0.35)
                        .allowsHitTesting(false)
                }
                center(side)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            // 一整块只挂一个悬停：按鼠标的位置算出是哪一段（原来每段各挂一个，最上面那段把所有悬停都吃掉了）
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let id = Self.slice(at: p, side: side, slices: slices)
                    if id != hot { withAnimation(.snappy(duration: 0.15)) { hot = id } }
                case .ended:
                    withAnimation(.snappy(duration: 0.15)) { hot = nil }
                }
            }
            .onTapGesture { if let hot { pick(hot) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 圆环上的一段（0 在正上方，顺时针）。
struct V3DonutSlice: Shape {
    var from: Double
    var to: Double
    var thickness: CGFloat
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 4, inner = outer - thickness
        let a0 = Angle.degrees(from * 360 - 90), a1 = Angle.degrees(to * 360 - 90)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// 平时花的：每周和上个月比（原来在花销页，挪到趋势页）。
struct V3WeeklyBars: View {
    /// 小号：放在花销页圆环旁边。
    var compact = false
    @Environment(V3State.self) private var state
    var body: some View {
        // 从账本现算：每周平时花的，和上个月同一周比。柱子的高矮按两个月里最大的那一周算；还没到的那周画虚框
        let pace = state.book.spendPace
        let count = max(pace.lastWeeks.count, pace.weeks.count, (pace.days + 6) / 7)
        let top = Double(max((pace.weeks + pace.lastWeeks).map(\.cents).max() ?? 0, 1))
        let weeks: [(Double, Double)] = (0..<min(count, 5)).map { i in
            (i < pace.weeks.count ? max(Double(pace.weeks[i].cents) / top * 100, pace.weeks[i] > .zero ? 3 : 0) : 0,
             i < pace.lastWeeks.count ? Double(pace.lastWeeks[i].cents) / top * 100 : 0)
        }
        let fewer = zip(pace.weeks, pace.lastWeeks).filter { $0 < $1 }.count
        let bw: CGFloat = compact ? 13 : 26
        HStack(alignment: .bottom, spacing: compact ? 8 : 18) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                VStack(spacing: 4) {
                    GeometryReader { g in
                        HStack(alignment: .bottom, spacing: compact ? 3 : 5) {
                            if w.0 > 0 {
                                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7).fill(V3.navy).frame(width: bw, height: g.size.height * w.0 / 100)
                            } else {
                                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                                    .strokeBorder(V3.dash, style: StrokeStyle(lineWidth: 2, dash: [5, 4])).frame(width: bw, height: g.size.height * 0.2)
                            }
                            UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7).fill(V3.dash).frame(width: bw, height: g.size.height * w.1 / 100)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    V3Label(compact ? "\(i + 1) 周" : "第 \(i + 1) 周", size: compact ? 11 : 12)
                }
            }
        }
        .accessibilityElement().accessibilityLabel(pace.lastWeeks.isEmpty ? "每周平时花的" : "每周平时花的和上个月比：过了的 \(pace.weeks.count) 周里有 \(fewer) 周比上个月少")
    }
}

/// 过去某个月每周平时花的（小号的柱子）。
struct V3MonthBars: View {
    let weekly: [Money]
    var body: some View {
        let top = max(weekly.map(\.cents).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(weekly.enumerated()), id: \.offset) { i, w in
                VStack(spacing: 4) {
                    GeometryReader { g in
                        UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(V3.navy)
                            .frame(width: 18, height: max(g.size.height * Double(w.cents) / Double(top), 4))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    V3Label("\(i + 1) 周", size: 11)
                }
            }
        }
        .accessibilityElement().accessibilityLabel("每周平时花的")
    }
}

// MARK: - 趋势

struct V3TrendsPage: View {
    @Environment(V3State.self) private var state
    @State private var gym: Bool?

    var body: some View {
        let run = state.book.handRunway
        // 都从账本现算（TrialMonths.swift）：月底大概花、接下来要付的
        let b = state.book
        let due = b.upcomingTotal + (gym == true ? Money(cents: 29_00) : .zero)
        let end = b.projectedMonthSpend
        let last = b.previousMonthData?.spentTotal
        let pace = b.spendPace
        let nowLine: [(Double, Double)] = [(0, 215)] + pace.soFar.enumerated().map { point($0.offset + 1, $0.element, days: pace.days, top: pace.top) }
        let lastLine: [(Double, Double)] = pace.last.isEmpty ? [] : [(0, 215)] + pace.last.enumerated().map { point(min($0.offset + 1, pace.days), $0.element, days: pace.days, top: pace.top) }
        let demo = state.real == nil
        let nextMonth = b.thisMonth.next.month
        V3Cols(left: 1.3, right: 1) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        V3Label("照这样花，月底大概花")
                        V3Gold(amount: end, size: 44)
                        if let last {
                            V3Label(end <= last ? "比上个月少 \((last - end).v3Short)" : "比上个月多 \((end - last).v3Short)", color: end <= last ? V3.green : V3.navy, weight: .bold)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
                    stat("接下来要付", due.v3, b.month.income >= due ? "钱够，还多 \((b.month.income - due).v3Short)" : "比进账多 \((due - b.month.income).v3Short)", b.month.income >= due ? V3.green : V3.red)
                    stat("没收入还能撑", "\(run.monthsText) 个月", "按平时每月花算", V3.ink2)
                }
                .fixedSize(horizontal: false, vertical: true)
                V3GrowCard {
                    V3CardTitle(title: "花钱速度") {
                        if let slower = pace.slower { V3Tag(text: slower ? "比上个月慢" : "比上个月快", tone: slower ? .green : .gold) }
                    } trail: {
                        Text(pace.last.isEmpty ? "━ 这个月　┈ 照这样到月底" : "━ 这个月　┅ 上个月　┈ 照这样到月底").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                    }
                    // 折线从账本现算（TrialMonths.swift 的 spendPace）：横轴是这个月的每一天，纵轴是到那天一共花掉多少
                    V3Lines(height: 220, grid: [55, 110, 165, 219], lines: [
                        .init(points: nowLine, color: .clear, width: 0, fill: V3.soft),
                        .init(points: lastLine, color: V3.dash, width: 3, dash: [6, 6]),
                        .init(points: nowLine, color: V3.navy),
                        .init(points: [nowLine.last ?? (0, 215), point(pace.days, pace.projected, days: pace.days, top: pace.top)], color: V3.navy, width: 3, dash: [3, 7]),
                    ], dot: nowLine.last)
                    .frame(maxHeight: .infinity)
                    // 「今天」写在它那一天的正下方；太靠两头就不写，免得和 1 日、月底叠在一起
                    HStack { V3Label("1 日"); Spacer(); V3Label("\(pace.days) 日") }
                        .overlay {
                            GeometryReader { g in
                                let x = g.size.width * Double(pace.today) / Double(max(pace.days, 1))
                                if x > 70, x < g.size.width - 80 { V3Label("今天 \(pace.today) 日").fixedSize().position(x: x, y: g.size.height / 2) }
                            }
                        }
                }
                .accessibilityLabel(pace.slower == nil ? "花钱速度" : pace.slower == true ? "花钱速度比上个月同期慢" : "花钱速度比上个月同期快")
                if !demo {
                    // 正式账本：真的问。认出来的固定开销里挑最大的一笔，问算不算（和旧界面趋势页是同一套认法、同一个写法）
                    if let g = state.fixedGuesses.max(by: { $0.amount < $1.amount }) {
                        V3Ask(face: "think", text: "\(g.name) \(g.amount.v3Short) 每月 \(g.day) 号左右都有，算固定的吗？") {
                            HStack(spacing: 8) {
                                Button("算") { state.answerFixedGuess(g, fixed: true) }.buttonStyle(.v3(.primary, .small))
                                Button("不算") { state.answerFixedGuess(g, fixed: false) }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                    }
                } else if let gym {
                    V3Ask(face: "happy", text: gym ? "算进去了，12 月要付 1.561 €。" : "好，不算，不再问了。", tone: .good)
                } else {
                    V3Ask(face: "think", text: "健身房 29 € 扣了 3 个月，算固定的吗？") {
                        HStack(spacing: 8) {
                            Button("算") { withAnimation(.snappy) { gym = true }; state.say("好，算进固定开销，12 月要付变成 1.561 €") }.buttonStyle(.v3(.primary, .small))
                            Button("不算") { withAnimation(.snappy) { gym = false }; state.say("好，不算，以后不再问这一笔") }.buttonStyle(.v3(.ghost, .small))
                        }
                    }
                }
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                if demo {
                    V3CardTitle("12 月要付的")
                    V3RowList(rows: [
                        .init("🏠", "房租", "12 月 1 日 · 固定", "650,00 €"), .init("💳", "信用卡", "12 月 5 日 · 固定", "640,00 €", V3.red),
                        .init("📱", "手机分期", "12 月 8 日 · 第 7 / 12 期", "200,00 €", V3.red), .init("🔁", "订阅 5 个", "2 日到 21 日陆续扣", "42,00 €"),
                    ] + (gym == true ? [.init("🏋️", "健身房", "刚算进来的", "29,00 €")] : []), compact: true)
                    V3CardTitle("平时花的").padding(.top, 6)
                    V3RowList(rows: [.init("🛒", "吃饭和超市", "大概", "310,00 €"), .init("🚇", "交通和别的", "大概", "140,00 €")], compact: true)
                    V3CardTitle("提前知道的大开销").padding(.top, 6)
                    V3RowList(rows: [.init("🎁", "过年礼物", "去年 12 月花了 180 €", "大概 180 €", tag: "去年有过", tone: .gold)], compact: true)
                } else {
                    // 正式账本：都从账本里来，没有的就不写
                    V3CardTitle("接下来要付的")
                    if b.upcoming.isEmpty {
                        V3Label("\(nextMonth) 月之前没有已经知道要付的").padding(.vertical, 6)
                    } else {
                        V3RowList(rows: b.upcoming.prefix(5).map { .init($0.emoji, $0.name, $0.meta, $0.amount.magnitude.v3) }, compact: true)
                    }
                    let top = b.spendSlices(limit: 4)
                    if !top.isEmpty {
                        V3CardTitle("这个月花得最多的").padding(.top, 6)
                        V3RowList(rows: top.prefix(3).map { .init($0.emoji, $0.name, "到今天", $0.amount.v3) }, compact: true)
                    }
                }
                V3CardTitle(title: "平时花的 · 每周和上个月比") { EmptyView() } trail: {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) { Circle().fill(V3.navy).frame(width: 8, height: 8); V3Label("这个月", size: 12) }
                        HStack(spacing: 4) { Circle().fill(V3.dash).frame(width: 8, height: 8); V3Label("上个月", size: 12) }
                    }
                }
                .padding(.top, 6)
                V3WeeklyBars().frame(maxHeight: .infinity).padding(.horizontal, 8)
            }
        }
    }

    /// 把「第几天、到那天一共花掉多少」放到图上的位置（图宽 560、高 220，底边留一点）。
    private func point(_ day: Int, _ amount: Money, days: Int, top: Money) -> (Double, Double) {
        let x = Double(day) / Double(max(days, 1)) * 560
        let y = 215 - (top > .zero ? Double(amount.cents) / Double(top.cents) : 0) * 190
        return (x, y)
    }

    private func stat(_ label: String, _ value: String, _ note: String, _ noteColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            V3Label(label).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            V3Amount(value, size: 23, weight: .heavy)
            // 字多了就折成两行，不许顶出卡片盖到旁边
            V3Label(note, color: noteColor, weight: noteColor == V3.ink2 ? .regular : .bold)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).v3Soft()
    }
}

// MARK: - 流水

struct V3TransactionsPage: View {
    @Environment(V3State.self) private var state
    /// 「11 月 18 日」：今天往前数几天的那一天。
    static func dayLabel(_ today: Date, back: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.month, .day], from: cal.date(byAdding: .day, value: -back, to: today) ?? today)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }
    @State private var search = ""
    @State private var selected: UUID?
    @State private var lumi: Bool?
    /// 只看哪段日子：0 全部、1 今天、2 近 7 天、3 近 30 天。
    @State private var range = 0
    static let ranges = ["全部", "今天", "近 7 天", "近 30 天"]

    private func match(_ e: V3State.Entry) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || e.name.contains(q) || e.meta.localizedCaseInsensitiveContains(q) || e.amount.v3.contains(q) || e.tag.contains(q)
    }

    var body: some View {
        let today = state.book.today.filter(match)
        let yest = state.book.entries.filter { $0.daysAgo == 1 && $0.side == .life }.filter(match)
        let all = state.book.entries
        let pick = all.first { $0.id == selected } ?? today.first ?? yest.first ?? all.first
        V3Cols(left: 1.5, right: 1) {
            VStack(spacing: 16) {
                // 导入进度：只在真的正在导入时出现，读完自己消失（结果在底部提示条里说）。
                if let p = state.importProgress {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text").font(.system(size: 15, weight: .semibold)).foregroundStyle(V3.navy)
                        Text("正在读 \(p.name) \(p.read)/\(p.total)").font(V3.font(13.5, .bold)).foregroundStyle(V3.ink).contentTransition(.numericText()).fixedSize()
                        V3Bar(fraction: Double(p.read) / Double(max(p.total, 1)), height: 8)
                        Button("停下") { state.stopImport() }.buttonStyle(.plain).font(V3.font(13, .bold)).foregroundStyle(V3.navy)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10).v3Soft(radius: 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if lumi == nil, state.real == nil {
                    V3Ask(face: "think", text: "Super Lumi 那 18,60 €，算超市？") {
                        HStack(spacing: 8) {
                            Button("好") {
                                withAnimation(.snappy) { lumi = true }
                                if let e = state.book.entries.first(where: { $0.place == "Super Lumi" }) {
                                    state.change("归好了，以后这家店都按超市", kind: .categorize) { try $0.recategorize(entry: e.id, emoji: "🛒", name: "超市", always: true) }
                                }
                            }
                            .buttonStyle(.v3(.primary, .small))
                            Button("不是") { withAnimation(.snappy) { lumi = false }; state.say("好，那先留着，你有空在右边改分类") }.buttonStyle(.v3(.ghost, .small))
                        }
                    }
                }
                V3GrowCard(spacing: 6) {
                    HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("🔍")
                        TextField("搜店名、金额、分类", text: $search).textFieldStyle(.plain).font(V3.font(14, .semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                    Button("导入流水") { state.handToXia() }.buttonStyle(.v3(.ghost, .small)).disabled(state.importProgress != nil)
                    }
                    HStack(spacing: 6) {
                        ForEach(Array(Self.ranges.enumerated()), id: \.offset) { i, t in
                            Button { withAnimation(.snappy(duration: 0.15)) { range = i } } label: {
                                Text(t).font(V3.font(12.5, .bold)).foregroundStyle(range == i ? .white : V3.ink)
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .background(Capsule().fill(range == i ? V3.navy : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                            }
                            .buttonStyle(.plain).accessibilityAddTraits(range == i ? .isSelected : [])
                        }
                        Spacer()
                    }
                    if range > 0 {
                        // 选了一段日子：这段里的每一笔排成一列，新的在前
                        let days = [0, 1, 7, 30][range]
                        let inRange = state.book.entries.filter { $0.side == .life && $0.daysAgo < days }.filter(match).sorted { $0.daysAgo < $1.daysAgo }
                        if inRange.isEmpty { V3Label("这段日子里没有流水。").padding(.top, 10) }
                        else {
                            V3Label("\(Self.ranges[range]) · \(inRange.count) 笔，一共 \(inRange.map(\.amount).reduce(.zero, +).v3)", weight: .bold).padding(.top, 4)
                            list(Array(inRange.prefix(lumi == nil ? 6 : 7)), pick: pick)
                        }
                    } else {
                    if today.isEmpty && yest.isEmpty {
                        V3Label("没找到「\(search)」。换个店名或者金额试试。").padding(.top, 10)
                    }
                    if !today.isEmpty {
                        V3Label("今天 · \(Self.dayLabel(state.book.todayDate, back: 0))", weight: .bold).padding(.top, 4)
                        list(Array(today.prefix(lumi == nil ? 3 : 4)), pick: pick)
                    }
                    if !yest.isEmpty {
                        V3Label("昨天 · \(Self.dayLabel(state.book.todayDate, back: 1))", weight: .bold).padding(.top, 4)
                        list(yest, pick: pick)
                    }
                    let older = state.book.entries.filter { $0.daysAgo > 1 && $0.side == .life }.filter(match)
                    if !older.isEmpty {
                        V3Label("更早", weight: .bold).padding(.top, 4)
                        list(Array(older.prefix(today.count + yest.count > 4 ? 1 : 2)), pick: pick)
                    }
                    }
                }
            }
        } trailing: {
            V3GrowCard {
                if let e = pick {
                    HStack(spacing: 12) {
                        V3Ico(emoji: e.emoji, size: 52)
                        VStack(alignment: .leading) { Text(e.name).font(V3.font(18, .heavy)); V3Label(e.meta) }
                    }
                    V3Amount(e.amount.cents > 0 ? e.amount.v3Signed : e.amount.v3, color: e.amount.cents > 0 ? V3.green : V3.navy, size: 38, weight: .heavy)
                    VStack(spacing: 0) {
                        detail("什么时候", QuickDate.label(daysAgo: e.daysAgo, today: state.book.todayDate)); V3Divider()
                        detail("怎么付的", e.meta.components(separatedBy: " · ").last ?? ""); V3Divider()
                        detail("怎么进来的", e.tag == "跟 AI 说的" ? "你跟 Claude 说了一句" : e.tag == "刚记的" ? "你刚才自己记的" : e.tag.isEmpty ? "自己记的" : e.tag)
                        if e.name == "咖啡", state.real == nil { V3Divider(); detail("这周第几次", "第 2 次 · 上周同期 4 次") }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button("改分类") { state.open(.category(e.id)) }.buttonStyle(.v3(.ghost, .small))
                        Button("改金额") { state.open(.amount(e.id)) }.buttonStyle(.v3(.ghost, .small))
                        if e.amount < .zero {
                            let isOdd = state.book.surprises(in: state.book.thisMonth).contains { $0.id == e.id }
                            Button(isOdd ? "这不算意外" : "算成意外开销") {
                                state.change(isOdd ? "好，这笔不算意外开销" : "好，这笔算成意外开销") { try $0.markSurprise(e.id, !isOdd) }
                            }
                            .buttonStyle(.v3(.ghost, .small))
                        }
                        Button("删掉") {
                            state.change("删掉了：\(e.name) \(e.amount.magnitude.v3)", kind: .remove) { try $0.delete(entry: e.id) }
                        }
                        .buttonStyle(.v3(.danger, .small)).help("删了能撤销")
                    }
                } else {
                    V3Label("点左边一笔，这里看它的来龙去脉。")
                }
            }
        }
        .onAppear { takeFocus() }
    }

    private func takeFocus() {
        if let id = state.txFocus { selected = id; state.txFocus = nil }
        if let q = state.txQuery { search = q; state.txQuery = nil }
    }

    private func list(_ items: [V3State.Entry], pick: V3State.Entry?) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                if i > 0 { V3Divider() }
                Button { withAnimation(.snappy(duration: 0.15)) { selected = e.id } } label: {
                    V3Row(emoji: e.emoji, name: e.name, meta: e.meta, amount: e.amount.cents > 0 ? e.amount.v3Signed : e.amount.v3,
                          color: e.amount.cents > 0 ? V3.green : V3.navy, tag: e.tag, tagTone: e.tag == "等你看一眼" ? .red : .blue)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(pick?.id == e.id ? V3.bg : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack(spacing: 12) { V3Label(k).frame(width: 76, alignment: .leading); Text(v).font(V3.font(14, .bold)); Spacer() }.padding(.vertical, 9)
    }
}

// MARK: - 订阅

struct V3SubscriptionsPage: View {
    @Environment(V3State.self) private var state
    @State private var keepAll = false

    var body: some View {
        let b = state.book
        let monthly = b.subscriptionsMonthly
        let doubt = b.subscriptions.filter { $0.tag == "可以考虑退" && !$0.off }
        let dropped = b.subscriptions.filter(\.off)
        let saved = dropped.map(\.monthly).reduce(.zero, +)
        V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "订阅每月一共", amount: monthly) {
                    V3Label("一年是 \(Money(cents: monthly.cents * 12).v3Short)")
                }
                if keepAll || doubt.isEmpty {
                    V3Ask(face: "happy", text: keepAll ? "好，都留着。" : dropped.isEmpty ? "订阅都看过了，没有该退的。" : "记下了：\(dropped.map(\.name).joined(separator: "、"))要退，到日子叫你。", tone: .good)
                } else {
                    V3Ask(face: "think", text: "\(doubt.map { "「\($0.name)」" }.joined(separator: "、"))好像用得不多，还要吗？") {
                        HStack(spacing: 8) {
                            ForEach(doubt.prefix(2)) { d in
                                Button("退\(d.name)") { state.change("记下了：\(d.name)要退", kind: .subscription) { try $0.setSubscription(d.name, dropped: true) } }.buttonStyle(.v3(.primary, .small))
                            }
                            Button("都留着") { withAnimation(.snappy) { keepAll = true }; state.say("好，都留着") }.buttonStyle(.v3(.ghost, .small))
                        }
                    }
                }
                V3GrowCard {
                    V3CardTitle(dropped.isEmpty ? "如果这几个都退" : "已经省下的")
                    V3Amount("每月省 \((dropped.isEmpty ? doubt.map(\.monthly).reduce(.zero, +) : saved).v3)", color: V3.green, size: 30, weight: .heavy)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                V3CardTitle("按下次扣钱的日子排", note: "\(b.subscriptions.count) 个")
                V3RowList(rows: b.subscriptions.prefix(7).map { x in
                    .init(x.emoji, x.name, x.off ? "要退 · 这个月之后不再扣" : x.note, x.amount.v3 + (x.cycle == 1 ? "" : " / " + ["周", "月", "季", "年"][x.cycle]), tag: x.off ? "要退" : x.tag,
                          tone: x.off || x.flag ? .green : .gold, action: { state.open(.subscriptionInfo(x.name)) })
                }, compact: b.subscriptions.count > 5)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("去流水里找找") { state.go(.transactions) }.buttonStyle(.v3(.ghost, .small)).help(state.real == nil ? "流水里还有 2 笔像订阅的" : "去流水里看看有没有漏掉的订阅")
                }
            }
        }
    }
}

// MARK: - 欠款与还债

struct V3DebtsPage: View {
    @Environment(V3State.self) private var state
    @State private var moved = false

    var body: some View {
        // 接着正式账本：只摆账本里真有的。试用数字里那套示例（信用卡 12 月 5 日、手机分期 12 期、哪天还完）不出现
        if state.real != nil { realBody } else { demoBody }
    }

    private var realBody: some View {
        let b = state.book
        let owed = b.debts.filter { $0.balance > .zero }
        let cards = owed.filter(\.isCreditCard).map(\.balance).reduce(.zero, +)
        let due = cards + b.lifeLoanMonthly
        return V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "\(b.thisMonth.next.month) 月要还", amount: due) {
                    HStack(spacing: 26) {
                        V3KV(value: b.totals.owe.v3, label: "我一共欠", color: V3.red)
                        V3KV(value: b.lent.map(\.balance).reduce(.zero, +).v3, label: "别人欠我")
                    }
                }
                .help("信用卡现在欠的 \(cards.formatted) + 别的欠款和分期这个月该还的 \(b.lifeLoanMonthly.formatted)")
                // 欠的（信用卡除外）每一笔都有还完的日子，才写哪个月不欠了；有一笔没日子就不写
                if let free = b.debtFreeMonth {
                    V3Ask(face: "calm", text: "照现在的计划，\(free)就不欠了。", tone: .good)
                }
                V3GrowCard(spacing: 8) {
                    V3CardTitle("别人欠我的")
                    if b.lent.isEmpty { V3Label("没有").padding(.vertical, 6) }
                    V3RowList(rows: b.lent.prefix(6).map { .init($0.emoji, $0.name.replacingOccurrences(of: "借给", with: ""), $0.note, $0.balance.v3) }, compact: b.lent.count > 2, fill: true)
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 8) {
                V3CardTitle("欠着的")
                if owed.isEmpty { V3Label("一笔都不欠").padding(.vertical, 6) }
                V3RowList(rows: owed.prefix(8).map { d in
                    .init(d.emoji, d.name, b.payoffMonths[d.name].map { "\(d.note) · 照计划 \($0)还完" } ?? d.note, d.balance.v3, V3.red, action: { state.open(.repay(d.name)) })
                }, compact: owed.count > 3, fill: true)
                Spacer(minLength: 0)
                Button("记一笔欠款") { state.open(.debt) }.buttonStyle(.v3(.ghost, .small))
            }
        }
    }

    private var demoBody: some View {
        let b = state.book
        let card = b.debts.first { $0.name == "信用卡" }?.balance ?? .zero
        let phone = b.debts.first { $0.name == "手机分期" }?.balance ?? .zero
        let periodsLeft = Int(phone.cents / 200_00)
        let others = b.debts.filter { $0.name != "信用卡" && $0.name != "手机分期" }
        let dueNow = (card > .zero ? card : .zero) + (phone > .zero && !moved ? Money(cents: 200_00) : .zero)
        let paidFraction = 1 - Double(b.totals.owe.cents) / 3_286_00
        return V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "12 月要还", amount: dueNow) {
                    HStack(spacing: 26) {
                        V3KV(value: b.totals.owe.v3, label: "我一共欠", color: V3.red)
                        V3KV(value: b.lent.map(\.balance).reduce(.zero, +).v3, label: "别人欠我")
                    }
                }
                V3Ask(face: moved ? "calm" : "calm",
                      text: moved ? "这期挪到 1 月，不收利息。明年 6 月还完。" : "这 \(dueNow.v3Short) 钱够还。明年 5 月就不欠了。",
                      tone: .good)
                V3GrowCard {
                    V3CardTitle("还完的那天")
                    V3Amount(moved ? "2027 年 6 月 8 日" : "2027 年 5 月 8 日", size: 30, weight: .heavy)
                    V3Bar(fraction: paidFraction, height: 14)
                    V3Label("已经还掉 \(Int((paidFraction * 100).rounded()))%")
                    V3CardTitle("接下来要还的").padding(.top, 8)
                    V3RowList(rows: (card > .zero ? [V3RowData("💳", "信用卡", "12 月 5 日", card.v3, V3.red)] : [])
                              + (phone > .zero ? [V3RowData("📱", "手机分期", moved ? "1 月 8 日" : "12 月 8 日", "200,00 €", V3.red),
                                                 V3RowData("📱", "手机分期", moved ? "2 月 8 日" : "1 月 8 日", "200,00 €", V3.red)] : []), fill: true)
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 8) {
                V3CardTitle("先还哪个")
                V3RowList(rows: [
                    card > .zero ? .init("💳", "信用卡", "12 月 5 日 · 拖了要收利息", card.v3, V3.red, tag: "先还这个", tone: .red, action: { state.open(.repay("信用卡")) })
                                 : .init("💳", "信用卡", "这个月的还清了", "0,00 €", V3.green, tag: "还清了", tone: .green),
                    .init("📱", "手机分期", moved ? "这一期挪到 1 月 8 日 · 还剩 \(periodsLeft) 期" : "每月 8 日 · 还剩 \(periodsLeft) 期", "200,00 € / 月", V3.red, tag: "按月还就行"),
                ] + others.prefix(2).map { d in .init(d.emoji, d.name, d.note, d.balance.v3, d.balance > .zero ? V3.red : V3.green, action: d.balance > .zero ? { state.open(.repay(d.name)) } : nil) }, compact: !others.isEmpty, fill: true)
                V3Periods(total: 12, done: 12 - periodsLeft)
                V3Label("手机分期 · 12 期还了 \(12 - periodsLeft) 期")
                V3CardTitle("别人欠我的").padding(.top, 6)
                V3RowList(rows: b.lent.prefix(3).map { .init($0.emoji, $0.name.replacingOccurrences(of: "借给", with: ""), $0.note, $0.balance.v3) }, compact: b.lent.count > 1, fill: true)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("记一笔欠款") { state.open(.debt) }.buttonStyle(.v3(.ghost, .small))
                    Button(moved ? "还是按原来的还" : "这个月还不上") {
                        withAnimation(.snappy) { moved.toggle() }
                        state.say(moved ? "没事，我帮你把这一期挪到下个月，看看影响" : "好，还是按原来的日子还")
                    }
                    .buttonStyle(.v3(.ghost, .small))
                }
            }
        }
    }
}

// MARK: - 每月小结

struct V3MonthlyPage: View {
    @Environment(V3State.self) private var state

    var body: some View {
        content.environment(\.v3InlineXia, true)
    }

    private var content: some View {
        let b = state.book
        // 小结写的是哪个月：切到过去的月份就是那个月；停在这个月时写上个月（这个月还没过完）
        let key = state.isThisMonth ? b.thisMonth.previous : state.monthKey
        let label = key.label(thisYear: b.thisMonth.year)
        let odd = b.surprises(in: key)
        let plan = b.journey.monthlyPlan
        return V3Cols(left: 1, right: 1.2) {
            VStack(spacing: 16) {
                // 这几个数都是那个月存下来的（和总览切到那个月看到的是同一份）
                let d = b.monthData(key)
                V3KeyCard(label: "\(label)存下", amount: d.forGoals) {
                    V3Label("进账 \(d.income.v3Short)，花掉 \(d.spentTotal.v3Short)，最后剩下 \(d.left.v3Short)", size: 14, color: V3.ink2, weight: .bold)
                }
                V3Card {
                    V3CardTitle("\(label)底的家底")
                    HStack(spacing: 26) {
                        V3KV(value: d.have.v3Short, label: "有多少")
                        V3KV(value: d.owe.v3Short, label: "欠多少", color: V3.red)
                        V3KV(value: d.net.v3Short, label: b.netChange(in: key).map { "净剩 · 比 \(key.previous.month) 月\($0 >= .zero ? "多" : "少") \($0.magnitude.v3Short)" } ?? "净剩", color: V3.gold)
                    }
                }
                // 这个月的意外开销：大数是合计，下面每笔一行，最多 4 行
                V3GrowCard(spacing: 4) {
                    V3CardTitle("\(label)的意外开销")
                    if odd.isEmpty {
                        V3Label("\(label)没有意外开销", size: 14)
                    } else {
                        V3Amount(odd.map(\.amount).reduce(.zero, +).magnitude.v3, color: V3.navy, size: 26, weight: .heavy)
                        ForEach(Array(odd.prefix(4).enumerated()), id: \.element.id) { i, e in
                            if i > 0 { V3Divider() }
                            HStack(spacing: 10) {
                                V3Ico(emoji: e.emoji, size: 32)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(e.place.isEmpty ? e.name : e.place).font(V3.font(14, .bold)).foregroundStyle(V3.ink).lineLimit(1)
                                    Text(QuickDate.label(daysAgo: e.daysAgo, today: b.todayDate)).font(V3.font(12, .regular)).foregroundStyle(V3.ink2)
                                }
                                Spacer(minLength: 4)
                                V3Amount(e.amount.magnitude.v3, size: 14.5)
                                Button("这不算意外") { state.change("好，\(e.place.isEmpty ? e.name : e.place)不算意外开销") { try $0.markSurprise(e.id, false) } }
                                    .buttonStyle(.v3(.ghost, .small))
                            }
                            .padding(.vertical, 2)
                        }
                        if odd.count > 4 { V3Label("还有 \(odd.count - 4) 笔", size: 12.5) }
                    }
                    Spacer(minLength: 0)
                }
                // 每月存多少：普通的一行，点「改」就能改
                HStack(spacing: 10) {
                    Text("每月存多少").font(V3.font(14.5, .bold)).foregroundStyle(V3.ink)
                    Spacer()
                    V3Amount(plan.v3, size: 17, weight: .heavy)
                    Button("改") { state.open(.monthlyPlan) }.buttonStyle(.v3(.ghost, .small))
                }
                .v3Card(h: 20, v: 12)
            }
        } trailing: {
            VStack(spacing: 16) {
                // 这几段都从那个月的数现算（TrialMonths.swift 的 monthGood / monthWatch），没有就直说没有
                let good = b.monthGood(key), watch = b.monthWatch(key)
                V3Card(spacing: 4) {
                    V3CardTitle(good.isEmpty ? "做得好的" : "做得好的 \(good.count) 件")
                    if good.isEmpty { V3Label("这个月的数还不够，看不出来").padding(.vertical, 6) }
                    V3RowList(rows: good.map { .init($0.emoji, $0.title, $0.detail, $0.amount) })
                }
                V3Card(spacing: 4) {
                    V3CardTitle(watch.isEmpty ? "要留意的" : "要留意的 \(watch.count) 件")
                    if watch.isEmpty { V3Label("没有哪样比上个月多花不少").padding(.vertical, 6) }
                    V3RowList(rows: watch.map { .init($0.emoji, $0.title, $0.detail, $0.amount) })
                }
                V3GrowCard(spacing: 4) {
                    V3CardTitle("接下来要付的")
                    if b.upcoming.isEmpty { V3Label("没有已经知道要付的").padding(.vertical, 6) }
                    V3RowList(rows: b.upcoming.sorted { $0.amount.magnitude > $1.amount.magnitude }.prefix(3).map { .init($0.emoji, $0.name, $0.meta, $0.amount.magnitude.v3) })
                }
            }
        }
    }
}
#endif
