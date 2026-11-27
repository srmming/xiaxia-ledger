#if os(macOS)
import FinanceCore
import SwiftUI

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
    var body: some View {
        V3Rows(data: rows) { r in
            if let action = r.action {
                Button(action: action) {
                    V3Row(emoji: r.emoji, name: r.name, meta: r.meta, amount: r.amount, color: r.color, tag: r.tag, compact: compact, tagTone: r.tone).contentShape(Rectangle())
                }
                .buttonStyle(V3SinkStyle(depth: 1))
            } else {
                V3Row(emoji: r.emoji, name: r.name, meta: r.meta, amount: r.amount, color: r.color, tag: r.tag, compact: compact, tagTone: r.tone)
            }
        }
    }
}

// MARK: - 花销

struct V3SpendingPage: View {
    @Environment(V3State.self) private var state
    private let weeks: [(Double, Double)] = [(58, 74), (66, 61), (49, 70), (0, 52)]
    private let top: [(String, String, String, Double, Double, UInt32)] = [
        ("🏠", "房租", "650,00", 100, 100, 0x7FA3F0), ("📱", "手机分期", "200,00", 31, 31, 0xC9A0DC), ("🛒", "超市", "142,19", 22, 25, 0x6CC5A8),
        ("🥗", "餐饮", "68,40", 11, 16, 0xF2A65A), ("🔁", "订阅", "42,00", 6.5, 6.5, 0x8FB5F5), ("🚇", "交通", "32,00", 5, 5, 0x9AD0E0), ("☕", "咖啡", "28,80", 4.4, 7, 0xD9A27A),
    ]

    var body: some View {
        let m = state.book.month
        let diff = state.lastMonthSpentSoFar - m.spentTotal
        V3Cols(left: 1.1, right: 1) {
            VStack(spacing: 16) {
                V3Ask(face: diff >= .zero ? "happy" : "calm",
                      text: diff >= .zero ? "比上月同期少花 \(diff.v3Short)，咖啡少 4 杯。" : "比上月同期多花 \(diff.magnitude.v3Short)，跟你说一声。",
                      tone: diff >= .zero ? .good : .plain)
                V3KeyCard(label: "11 月到今天花掉", amount: m.spentTotal, size: 56) {
                    HStack(spacing: 26) {
                        V3KV(value: m.fixed.v3, label: "固定要付的")
                        V3KV(value: m.spent.v3, label: "平时花的")
                    }
                }
                V3GrowCard {
                    V3CardTitle(title: "平时花的 · 每周和上个月比") { EmptyView() } trail: {
                        HStack(spacing: 10) { legend(V3.navy, "这个月"); legend(V3.dash, "上个月") }
                    }
                    HStack(alignment: .bottom, spacing: 26) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                            VStack(spacing: 6) {
                                GeometryReader { g in
                                    HStack(alignment: .bottom, spacing: 6) {
                                        if w.0 > 0 {
                                            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(V3.navy).frame(width: 34, height: g.size.height * w.0 / 100)
                                        } else {
                                            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                                                .strokeBorder(V3.dash, style: StrokeStyle(lineWidth: 2, dash: [5, 4])).frame(width: 34, height: g.size.height * 0.2)
                                        }
                                        UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(V3.dash).frame(width: 34, height: g.size.height * w.1 / 100)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                }
                                V3Label("第 \(i + 1) 周\(i == 2 ? "（到今天）" : "")", size: 13)
                            }
                        }
                    }
                    .padding(.horizontal, 16).frame(maxHeight: .infinity)
                    .accessibilityElement().accessibilityLabel("每周平时花的和上个月比：前三周两周比上个月少")
                }
            }
        } trailing: {
            V3GrowCard(spacing: 0) {
                V3CardTitle("花得最多的").padding(.bottom, 6)
                ForEach(Array(top.enumerated()), id: \.offset) { _, t in
                    Button { state.txQuery = t.1; state.go(.transactions) } label: {
                    HStack(spacing: 12) {
                        V3Ico(emoji: t.0)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.1).font(V3.font(14, .bold))
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(V3.bg)
                                    Capsule().fill(V3.hex(t.5)).frame(width: max(g.size.width * t.3 / 100, 6))
                                    Rectangle().fill(V3.ink).frame(width: 2, height: 15).offset(x: g.size.width * t.4 / 100 - 1)
                                }
                            }
                            .frame(height: 9)
                        }
                        V3Amount("\(t.2)\u{00A0}€").frame(width: 96, alignment: .trailing)
                    }
                    .frame(maxHeight: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 1)).help("去流水里只看「\(t.1)」")
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(t).font(V3.font(13, .semibold)).foregroundStyle(V3.ink2) }
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
    @State private var read = 37
    @State private var paused = false
    @State private var search = ""
    @State private var selected: UUID?
    @State private var lumi: Bool?
    private let total = 52

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
                // 导入进度：一笔一笔跳
                HStack(spacing: 16) {
                    Text("📄").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(read >= total ? "「Revolut 11 月流水」读完了 · \(total) 笔" : "\(paused ? "先停下了" : "正在读")「Revolut 11 月流水」· 已读 \(read) / \(total) 笔")
                            .font(V3.font(14, .bold)).contentTransition(.numericText())
                        V3Bar(fraction: Double(read) / Double(total))
                        V3Label("新的 \(max(read - 6, 0)) 笔 · 跳过重复 6 笔", size: 13)
                    }
                    if read < total {
                        Button(paused ? "接着读" : "先停下") {
                            paused.toggle()
                            state.say(paused ? "先停下了，已读的 \(read) 笔留着" : "好，接着读")
                        }
                        .buttonStyle(.v3(.ghost, .small))
                    } else {
                        Button("再读一遍") { read = 37; paused = false }.buttonStyle(.v3(.ghost, .small))
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 16).v3Sticker(fill: V3.soft, dashed: true)
                .task(id: paused) {
                    while !paused, read < total, !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(650))
                        if !paused, read < total { withAnimation(.snappy(duration: 0.2)) { read += 1 } }
                    }
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
                        Text("🔍")
                        TextField("搜店名、金额、分类", text: $search).textFieldStyle(.plain).font(V3.font(14, .semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
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
                        detail("什么时候", e.daysAgo == 0 ? "今天" : e.daysAgo == 1 ? "昨天" : "\(e.daysAgo) 天前"); V3Divider()
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

// MARK: - 花钱前想想

struct V3ThinkPage: View {
    @Environment(V3State.self) private var state
    @State private var name = "降噪耳机"
    @State private var priceText = "279,00"

    var body: some View {
        if state.thinkBig { V3BigDecision() } else { buy }
    }

    private var price: Money? {
        guard let m = Money(parsing: priceText), m > .zero else { return nil }
        return m
    }

    private var buy: some View {
        let m = state.book.month
        let p = price ?? .zero
        let after = m.left - p
        let perDayAfter = m.daysLeft > 0 && after > .zero ? Money(cents: after.cents / Int64(m.daysLeft) / 100 * 100) : .zero
        let dailyAvg: Int64 = 31_00
        let days = Int((p.cents + dailyAvg - 1) / dailyAvg)
        let weeks = state.book.journey.monthlyPlan > .zero ? Int((Double(p.cents) / Double(state.book.journey.monthlyPlan.cents) * 4.33).rounded()) : 0
        let fitsDaily = p <= state.book.sum(.daily)
        return V3Cols(left: 1.25, right: 1) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Text("想买").font(V3.font(14, .heavy))
                    V3Field(prompt: "想买什么", text: $name).frame(minWidth: 180).layoutPriority(1)
                    V3Field(prompt: "多少钱", text: $priceText, rounded: true).frame(width: 130)
                    Text("€").font(V3.num(16)).foregroundStyle(V3.ink2)
                    Button("放进清单") {
                        let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? "想买的东西" : name
                        state.change("放好了，11 月 20 日再问你") { try $0.addWanted(name: n, price: p) }
                    }
                    .buttonStyle(.v3(.primary, .small)).disabled(price == nil)
                    Button("算个大决定") { withAnimation(.snappy) { state.thinkBig = true } }.buttonStyle(.v3(.ghost, .small))
                }
                .v3Card()
                if price == nil {
                    V3Label("价钱没看懂，写成 279 这样就行。", color: V3.red, weight: .semibold)
                }
                V3KeyCard(label: "买了以后，这个月还能随便花", amount: after) {
                    V3Label(after >= .zero ? "现在是 \(m.left.v3) · 到月底每天从 \(Money(cents: m.perDay.cents / 100 * 100).v3Short) 变成 \(perDayAfter.v3Short)"
                            : "现在是 \(m.left.v3) · 买了这个月就超了 \(after.magnitude.v3Short)", color: after >= .zero ? V3.ink2 : V3.red)
                }
                V3Ask(face: "think", text: "先放清单里，过 48 小时再说？") {
                    HStack(spacing: 8) {
                        Button("放进清单") {
                            let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? "想买的东西" : name
                            state.change("放好了，11 月 20 日我再问你") { try $0.addWanted(name: n, price: p) }
                        }
                        .buttonStyle(.v3(.primary, .small)).disabled(price == nil)
                        Button("现在就买") {
                            state.manualPrefill = (name.trimmingCharacters(in: .whitespaces).isEmpty ? "想买的东西" : name, p)
                            state.open(.manual)
                        }
                        .buttonStyle(.v3(.ghost, .small)).disabled(price == nil)
                    }
                }
                HStack(spacing: 10) {
                    fact(fitsDaily ? "不用动" : "要动", fitsDaily ? .green : .red, "应急钱", fitsDaily ? "买得起，应急钱一分不动。" : "日常的钱不够，得动应急钱。")
                    fact("\(days) 天", .blue, "日常花销", "等于你 \(days) 天平时花的钱。")
                    fact("晚 \(weeks) 周", .red, state.book.journey.name, "如果从目标里拿，电脑晚 \(weeks) 周到手。")
                }
                .frame(maxHeight: .infinity)
            }
        } trailing: {
            V3GrowCard {
                V3CardTitle("想要清单")
                VStack(spacing: 0) {
                    ForEach(Array(state.book.wanted.prefix(5).enumerated()), id: \.element.id) { i, w in
                        if i > 0 { V3Divider() }
                        HStack(spacing: 8) {
                            V3Row(emoji: w.emoji, name: w.name, meta: w.note, amount: w.off ? "+" + w.amount.v3 : w.amount.v3,
                                  color: w.off ? V3.green : V3.navy, tag: w.tag, tagTone: .gold)
                            if !w.off {
                                Button("忍住") {
                                    state.resist(wanted: w)
                                }
                                .buttonStyle(.v3(.ghost, .small))
                                .accessibilityLabel("忍住不买\(w.name)，把钱存进目标")
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                let saved = state.book.wanted.filter(\.off)
                HStack(spacing: 6) {
                    V3Label("这个月忍住")
                    V3Amount("\(saved.count + 2) 次 · \((saved.map(\.amount).reduce(.zero, +) + Money(cents: 28_00)).v3Short)", color: V3.green, size: 15)
                }
            }
        }
    }

    private func fact(_ tag: String, _ tone: V3Tag.Tone, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            V3Tag(text: tag, tone: tone)
            Text(title).font(V3.font(14, .heavy))
            V3Label(text)
        }
        .padding(.horizontal, 18).padding(.vertical, 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).v3Soft()
    }
}

/// 大决定：离职、创业、买大件之前先算一算。
private struct V3BigDecision: View {
    @Environment(V3State.self) private var state
    @State private var pick = 0
    @State private var frugal = false
    private let kinds: [(String, String, String, String, String)] = [
        ("不上班了", "全职接私活", "如果下个月起不上班，只靠私活，不动应急钱能撑", "7,4", "到 2027 年 7 月中。在那之前私活要涨到每月 1.300 € 才接得上。"),
        ("自己开店", "先投一笔钱", "如果先投 8.000 € 开店，头几个月不赚钱，不动应急钱能撑", "3,1", "到 2027 年 2 月底。店要在那之前每月赚到 900 € 才接得上。"),
        ("换份少赚的", "每月少 400 €", "如果换一份每月少 400 € 的工作，照现在这样花能撑", "很久", "每月还能剩 70 €。电脑那条路要慢下来，每月只能存 70 €。"),
        ("买大件", "车、装修", "如果花 6.000 € 买车，不动应急钱还差", "3.899", "能动用的钱只有 2.100,61 €。差的那部分要么借，要么先存 20 个月。"),
    ]

    var body: some View {
        let k = kinds[pick]
        V3Cols(left: 1.3, right: 1) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { i, item in
                        V3Option(picked: pick == i) {
                            withAnimation(.snappy(duration: 0.2)) { pick = i; frugal = false }
                            state.say("算好了：\(item.0)")
                        } content: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.0).font(V3.font(16, .bold)).foregroundStyle(V3.ink)
                                Text(item.1).font(V3.font(13, .regular)).foregroundStyle(V3.ink2)
                            }
                        }
                    }
                }
                .frame(height: 72)
                V3KeyCard(label: frugal && pick == 0 ? "省着过（随便花减一半），不动应急钱能撑" : k.2,
                          whole: frugal && pick == 0 ? "10,2" : k.3,
                          rest: pick == 3 ? " €" : pick == 2 ? "" : " 个月") {
                    V3Label(frugal && pick == 0 ? "到 2027 年 10 月。" : k.4)
                }
                V3GrowCard {
                    V3CardTitle("钱一个月一个月怎么少下去")
                    V3Lines(height: 200, grid: [50, 100, 199], lines: [
                        .init(points: [(0, 20), (70, 42), (140, 64), (210, 86), (280, 108), (350, 128), (420, 146), (518, 150)], color: V3.navy, fill: V3.soft),
                        .init(points: [(0, 150), (560, 150)], color: V3.red, width: 2.5, dash: [7, 6]),
                    ], dot: (518, 150))
                    .frame(maxHeight: .infinity)
                    HStack { V3Label("12 月"); Spacer(); V3Label("2 月"); Spacer(); V3Label("4 月"); Spacer(); V3Label("6 月"); Spacer(); V3Label("7 月中 · 碰到应急钱") }
                }
            }
        } trailing: {
            VStack(spacing: 16) {
                V3Card(spacing: 6) {
                    V3CardTitle(title: "算的时候用的数") { EmptyView() } trail: {
                        Button("回到「买之前算一算」") { withAnimation(.snappy) { state.thinkBig = false } }.buttonStyle(.v3(.ghost, .small))
                    }
                    V3RowList(rows: [
                        .init("💼", "私活每月进账", "最近 6 个月平均", "640,00 €", V3.green), .init("🏠", "每月必须花", "房租、吃饭、分期、话费", state.book.monthlyMust.v3),
                        .init("☕", "每月随便花", "最近 3 个月平均", frugal ? "155,00 €" : "310,00 €"), .init("🏦", "能动用的钱", "不算应急钱和店里的", "2.100,61 €"),
                    ], compact: true)
                }
                V3GrowCard {
                    V3Ask(face: "think", text: "省着过能撑 10,2 个月，要看吗？") {
                        HStack(spacing: 8) {
                            Button(frugal ? "看原来的" : "看省着过的") {
                                withAnimation(.snappy) { frugal.toggle(); pick = 0 }
                                state.say(frugal ? "省着过：能撑 10,2 个月，到 2027 年 10 月" : "回到原来的算法")
                            }
                            .buttonStyle(.v3(.primary, .small))
                            let goal = "攒够 6 个月底气"
                            if state.book.nextGoals.contains(where: { $0.name == goal }) || state.book.journey.name == goal {
                                V3Tag(text: "已经存成目标", tone: .green)
                            } else {
                                Button("存成一个目标") {
                                    let total = Money(cents: state.book.monthlyMust.cents * 6)
                                    let after = state.book.journey.total > .zero ? "，排在「\(state.book.journey.name)」后面" : ""
                                    state.change("存成目标了：\(goal) \(total.v3Short)\(after)", kind: .goal) { try $0.queueGoal(name: goal, total: total) }
                                }
                                .buttonStyle(.v3(.ghost, .small))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        V3Label("想有底气再走？", size: 12.5)
                        Text("再存 2.760\u{00A0}€，就能撑满 12 个月").font(V3.num(16))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(V3.bg))
                }
            }
        }
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
                    Button("加一个订阅") { state.open(.subscription) }.buttonStyle(.v3(.primary, .small))
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
                }
            }
        } trailing: {
            V3GrowCard(spacing: 8) {
                V3CardTitle("先还哪个")
                V3RowList(rows: [
                    card > .zero ? .init("💳", "信用卡", "12 月 5 日 · 拖了要收利息", card.v3, V3.red, tag: "先还这个", tone: .red, action: { state.open(.repay("信用卡")) })
                                 : .init("💳", "信用卡", "这个月的还清了", "0,00 €", V3.green, tag: "还清了", tone: .green),
                    .init("📱", "手机分期", moved ? "这一期挪到 1 月 8 日 · 还剩 \(periodsLeft) 期" : "每月 8 日 · 还剩 \(periodsLeft) 期", "200,00 € / 月", V3.red, tag: "按月还就行"),
                ] + others.prefix(2).map { d in .init(d.emoji, d.name, d.note, d.balance.v3, d.balance > .zero ? V3.red : V3.green, action: d.balance > .zero ? { state.open(.repay(d.name)) } : nil) }, compact: !others.isEmpty)
                V3Periods(total: 12, done: 12 - periodsLeft)
                V3Label("手机分期 · 12 期还了 \(12 - periodsLeft) 期")
                V3CardTitle("别人欠我的").padding(.top, 6)
                V3RowList(rows: b.lent.prefix(3).map { .init($0.emoji, $0.name.replacingOccurrences(of: "借给", with: ""), $0.note, $0.balance.v3) }, compact: b.lent.count > 1)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("记一笔还款") {
                        guard let d = b.debts.first(where: { $0.balance > .zero }) else { state.say("欠的都还清了"); return }
                        state.open(.repay(d.name))
                    }
                    .buttonStyle(.v3(.primary, .small))
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
                    V3RowList(rows: [.init("⭐", "过了一站", "10 月 12 日存到 200 €", ""), .init("⭐", "咖啡少了 6 杯", "省下 19,20 €，都进了目标", ""),
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
