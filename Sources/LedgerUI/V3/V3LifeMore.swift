#if os(macOS)
import FinanceCore
import SwiftUI
import UniformTypeIdentifiers

// 生活这边其余的页：花销、趋势、流水、花钱前想想（含大决定）、订阅、欠款与还债、每月小结。
// 数字是设计稿里那套编的示例；能跟着动的（还能随便花、目标、应急钱）都从同一份状态里算。

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
        let m = state.book.month
        let diff = state.lastMonthSpentSoFar - m.spentTotal
        let slices = state.book.spendSlices()
        let total = state.book.spendSliceTotal
        let biggest = slices.map(\.amount.cents).max() ?? 1
        V3Cols(left: 1.1, right: 1) {
            VStack(spacing: 16) {
                V3Ask(face: diff >= .zero ? "happy" : "calm",
                      text: diff >= .zero ? "比上月同期少花 \(diff.v3Short)\(state.book.savedPhrase(diff).isEmpty ? "" : "，" + state.book.savedPhrase(diff))。" : "比上月同期多花 \(diff.magnitude.v3Short)，跟你说一声。",
                      tone: diff >= .zero ? .good : .plain)
                V3KeyCard(label: "11 月到今天花掉", amount: m.spentTotal, size: 56) {
                    HStack(spacing: 26) {
                        V3KV(value: m.fixed.v3, label: "固定要付的")
                        V3KV(value: m.spent.v3, label: "平时花的")
                    }
                }
                // 按分类的圆环：颜色和右边每一行一一对上，中间是这个月花掉的总数
                V3GrowCard {
                    V3Donut(slices: slices.map { (id: $0.name, value: Double($0.amount.cents)) }, colors: Self.colors, hot: $hot) { name in
                        state.txQuery = name; state.go(.transactions)
                    } center: {
                        VStack(spacing: 0) {
                            let shown = slices.first { $0.name == hot }
                            Text((shown?.amount ?? total).v3Short).font(V3.num(30, .heavy)).foregroundStyle(V3.ink).contentTransition(.numericText())
                            Text(shown?.name ?? "花掉").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(6)
                    .accessibilityElement().accessibilityLabel("这个月花掉 \(total.v3)，最多的是\(slices.first?.name ?? "")")
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(hot == t.name ? V3.bg : .clear))
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

/// 圆环图：一段一个分类。鼠标移上去那一段微微外扩，点了做 `pick`。中间放一块自己的内容。
struct V3Donut<Center: View>: View {
    let slices: [(id: String, value: Double)]
    let colors: [UInt32]
    @Binding var hot: String?
    var pick: (String) -> Void
    @ViewBuilder var center: Center

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
                        .contentShape(V3DonutSlice(from: starts[i], to: starts[i] + s.value / total, thickness: side * 0.2))
                        .onHover { inside in withAnimation(.spring(duration: 0.2)) { hot = inside ? s.id : (hot == s.id ? nil : hot) } }
                        .onTapGesture { pick(s.id) }
                }
                center
            }
            .frame(width: side, height: side)
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
    private let weeks: [(Double, Double)] = [(58, 74), (66, 61), (49, 70), (0, 52)]
    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                VStack(spacing: 4) {
                    GeometryReader { g in
                        HStack(alignment: .bottom, spacing: 5) {
                            if w.0 > 0 {
                                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7).fill(V3.navy).frame(width: 26, height: g.size.height * w.0 / 100)
                            } else {
                                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                                    .strokeBorder(V3.dash, style: StrokeStyle(lineWidth: 2, dash: [5, 4])).frame(width: 26, height: g.size.height * 0.2)
                            }
                            UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7).fill(V3.dash).frame(width: 26, height: g.size.height * w.1 / 100)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    V3Label("第 \(i + 1) 周", size: 12)
                }
            }
        }
        .accessibilityElement().accessibilityLabel("每周平时花的和上个月比：前三周有两周比上个月少")
    }
}

// MARK: - 趋势

struct V3TrendsPage: View {
    @Environment(V3State.self) private var state
    @State private var gym: Bool?

    var body: some View {
        let run = state.book.runway
        let due = Money(cents: gym == true ? 1_561_00 : 1_532_00)
        V3Cols(left: 1.3, right: 1) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        V3Label("照这样花，月底大概花")
                        V3Gold(amount: Money(cents: 1_344_00), size: 44, whole: true)
                        V3Label("比上个月少 96 €", color: V3.green, weight: .bold)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
                    stat("12 月要付", due.v3, "钱够，还多 \((Money(cents: 2_340_00) - due).v3Short)", V3.green)
                    stat("没了收入，钱还能撑", "\(run.monthsText) 个月", "和家底里的应急钱同一个算法", V3.ink2)
                }
                .fixedSize(horizontal: false, vertical: true)
                V3GrowCard {
                    V3CardTitle(title: "花钱速度") { V3Tag(text: "正常", tone: .green) } trail: {
                        Text("━ 这个月　┅ 上个月　┈ 照这样到月底").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                    }
                    V3Lines(height: 220, grid: [55, 110, 165, 219], lines: [
                        .init(points: [(0, 215), (60, 196), (120, 188), (180, 170), (240, 158), (300, 140), (336, 128)], color: .clear, width: 0, fill: V3.soft),
                        .init(points: [(0, 215), (60, 190), (120, 176), (180, 160), (240, 140), (300, 118), (360, 100), (420, 84), (480, 66), (560, 44)], color: V3.dash, width: 3, dash: [6, 6]),
                        .init(points: [(0, 215), (60, 196), (120, 188), (180, 170), (240, 158), (300, 140), (336, 128)], color: V3.navy),
                        .init(points: [(336, 128), (560, 62)], color: V3.navy, width: 3, dash: [3, 7]),
                    ], dot: (336, 128))
                    .frame(maxHeight: .infinity)
                    HStack { V3Label("1 日"); Spacer(); V3Label("10 日"); Spacer(); V3Label("今天 18 日"); Spacer(); V3Label("30 日") }
                }
                .accessibilityLabel("花钱速度正常，比上个月同期慢")
                if let gym {
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
                V3CardTitle("12 月要付的")
                V3RowList(rows: [
                    .init("🏠", "房租", "12 月 1 日 · 固定", "650,00 €"), .init("💳", "信用卡", "12 月 5 日 · 固定", "640,00 €", V3.red),
                    .init("📱", "手机分期", "12 月 8 日 · 第 7 / 12 期", "200,00 €", V3.red), .init("🔁", "订阅 5 个", "2 日到 21 日陆续扣", "42,00 €"),
                ] + (gym == true ? [.init("🏋️", "健身房", "刚算进来的", "29,00 €")] : []), compact: true)
                V3CardTitle("平时花的").padding(.top, 6)
                V3RowList(rows: [.init("🛒", "吃饭和超市", "大概", "310,00 €"), .init("🚇", "交通和别的", "大概", "140,00 €")], compact: true)
                V3CardTitle("提前知道的大开销").padding(.top, 6)
                V3RowList(rows: [.init("🎁", "过年礼物", "去年 12 月花了 180 €", "大概 180 €", tag: "去年有过", tone: .gold)], compact: true)
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

    private func stat(_ label: String, _ value: String, _ note: String, _ noteColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            V3Label(label)
            V3Amount(value, size: 23, weight: .heavy)
            V3Label(note, color: noteColor, weight: noteColor == V3.ink2 ? .regular : .bold)
        }
        .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).v3Soft()
    }
}

// MARK: - 流水

struct V3TransactionsPage: View {
    @Environment(V3State.self) private var state
    @State private var search = ""
    @State private var selected: UUID?
    @State private var lumi: Bool?

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
                if lumi == nil {
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
                    Button("导入流水") { state.importSample() }.buttonStyle(.v3(.ghost, .small)).disabled(state.importProgress != nil).help("也可以把文件拖到这一页")
                    }
                    if today.isEmpty && yest.isEmpty {
                        V3Label("没找到「\(search)」。换个店名或者金额试试。").padding(.top, 10)
                    }
                    if !today.isEmpty {
                        V3Label("今天 · 11 月 18 日", weight: .bold).padding(.top, 4)
                        list(Array(today.prefix(lumi == nil ? 3 : 4)), pick: pick)
                    }
                    if !yest.isEmpty {
                        V3Label("昨天 · 11 月 17 日", weight: .bold).padding(.top, 4)
                        list(yest, pick: pick)
                    }
                    let older = state.book.entries.filter { $0.daysAgo > 1 && $0.side == .life }.filter(match)
                    if !older.isEmpty {
                        V3Label("更早", weight: .bold).padding(.top, 4)
                        list(Array(older.prefix(today.count + yest.count > 4 ? 1 : 3)), pick: pick)
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
                        if e.name == "咖啡" { V3Divider(); detail("这周第几次", "第 2 次 · 上周同期 4 次") }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button("改分类") { state.open(.category(e.id)) }.buttonStyle(.v3(.ghost, .small))
                        Button("改金额") { state.open(.amount(e.id)) }.buttonStyle(.v3(.ghost, .small))
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
        .onDrop(of: [.fileURL], isTargeted: nil) { _ in state.importSample(dropped: true); return true }
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
                    Button("去流水里找找") { state.go(.transactions) }.buttonStyle(.v3(.ghost, .small)).help("流水里还有 2 笔像订阅的")
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
        let b = state.book
        let card = b.debts.first { $0.name == "信用卡" }?.balance ?? .zero
        let phone = b.debts.first { $0.name == "手机分期" }?.balance ?? .zero
        let periodsLeft = Int(phone.cents / 200_00)
        let others = b.debts.filter { $0.name != "信用卡" && $0.name != "手机分期" }
        let dueNow = (card > .zero ? card : .zero) + (phone > .zero && !moved ? Money(cents: 200_00) : .zero)
        let paidFraction = 1 - Double(b.totals.owe.cents) / 3_286_00
        V3Cols(left: 1, right: 1.3) {
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
        V3Cols(left: 1, right: 1.2) {
            VStack(spacing: 16) {
                V3KeyCard(label: "10 月存下", amount: Money(cents: 200_00)) {
                    V3Label("计划 200 €，做到了", size: 14, color: V3.green, weight: .bold)
                }
                V3Card {
                    V3CardTitle("月底的家底")
                    HStack(spacing: 26) {
                        V3KV(value: "8.130\u{00A0}€", label: "有多少")
                        V3KV(value: "2.040\u{00A0}€", label: "欠多少", color: V3.red)
                        V3KV(value: "6.090\u{00A0}€", label: "净剩 · 比 9 月多 310 €", color: V3.gold)
                    }
                }
                Spacer(minLength: 0)
                V3Question(face: "happy", text: "过了 200 € 那站。11 月还存 200 €？", tone: .good,
                           answers: [("还是 200 €", "好，11 月还是 200 €"), ("想少一点", "好，11 月存 100 €"), ("想多一点", "好，11 月存 250 €")],
                           onAnswer: { i in
                               let plan = Money(cents: [200_00, 100_00, 250_00][i])
                               state.change("定好了：11 月存 \(plan.v3Short)") { try $0.setMonthlyPlan(plan) }
                           })
            }
        } trailing: {
            VStack(spacing: 16) {
                V3Card(spacing: 4) {
                    V3CardTitle("做得好的 3 件")
                    V3RowList(rows: [.init("⭐", "过了一站", "10 月 12 日存到 200 €", ""), .init("⭐", "小东西少买了 6 次", "省下 19,20 €，都进了目标", ""),
                                     .init("⭐", "信用卡按时还清", "没有多付一分利息", "")])
                }
                V3Card(spacing: 4) {
                    V3CardTitle("要留意的 1 件")
                    V3RowList(rows: [.init("👀", "外卖", "比 9 月多了 4 次", "+46,00 €")])
                }
                V3GrowCard(spacing: 4) {
                    V3CardTitle("11 月提前知道")
                    V3RowList(rows: [.init("🚗", "车险", "11 月 25 日 · 一年一次", "310,00 €", tag: "大开销", tone: .gold)])
                }
            }
        }
    }
}
#endif
