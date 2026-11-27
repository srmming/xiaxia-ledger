#if os(macOS)
import FinanceCore
import SwiftUI

// 生意这边 7 页：给一个人开店的小老板。同一套样子，主色换成海水青；店的那条路是「回本」。
// 数字是设计稿里那套编的示例（Miora 小店）。

// MARK: - 生意首页

struct V3BizHomePage: View {
    @Environment(V3State.self) private var state
    @State private var todayText = ""

    /// 只填一个总数：先都算刷卡收的，想分开再点「分开填」。
    private func quick() {
        guard let m = V3Form.amount(todayText) else { state.fail("这个数没看懂，写成 186 这样就行"); return }
        let need = state.book.dailyBreakEven
        let day = state.book.todayDay
        state.change(m >= need ? "记好了 · 今天 \(m.v3)，够付今天的固定开销了" : "记好了 · 今天 \(m.v3)，还差 \((need - m).v3Short)", kind: .add) { try $0.recordShopDay(day, cash: .zero, card: m) }
    }

    var body: some View {
        let b = state.book
        let today = b.shopDays.first { $0.day == b.todayDay }
        let done = today?.state == .open
        let back = Money(cents: 16_728_00)
        V3Cols(left: 1.35, right: 1) {
            VStack(spacing: 16) {
                V3Ask(face: "think", text: "周六一天顶两天。后面收的都是你的了。", kicker: "每周一句")
                    .frame(maxWidth: 560).frame(maxWidth: .infinity, alignment: .leading)
                V3KeyCard(label: "11 月 · 真正赚了", amount: Money(cents: 1_520_26), wave: V3.tealSoft) {
                    V3Label("比上个月同期多 140 €", size: 14, color: V3.green, weight: .bold)
                }
                V3GrowCard {
                    V3CardTitle("「赚了」和「手里实际多了」为什么不一样")
                    HStack(spacing: 16) {
                        V3Tile(label: "账上赚了", value: "1.520,26\u{00A0}€", color: V3.teal)
                        V3Label("差的 690 € 去了").fixedSize()
                        V3Tile(label: "手里实际多了", value: "830,26\u{00A0}€", color: V3.teal)
                    }
                    V3RowList(rows: [.init("📦", "多进了货", "还在店里，没卖完", "−340,00 €"), .init("🏦", "还贷款本金", "不算开销，但钱出去了", "−350,00 €")])
                }
            }
        } trailing: {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    V3Label(done ? "今天收了" : today?.state == .rest ? "今天休息" : "今天收了多少")
                    HStack(spacing: 10) {
                        if done, let today {
                            V3Amount(today.total.v3, color: V3.teal, size: 30, weight: .heavy)
                            if today.total >= b.dailyBreakEven { V3Tag(text: "够付今天的固定开销", tone: .teal) }
                        }
                        if !done {
                            V3Field(prompt: "0,00", text: $todayText, size: 22, rounded: true) { quick() }
                            Text("€").font(V3.num(20)).foregroundStyle(V3.ink2)
                            Button("记好") { quick() }.buttonStyle(.v3(.teal))
                        }
                        Spacer(minLength: 0)
                        Button(done ? "改一下" : "分开填") { state.open(.shopDay(b.todayDay)) }.buttonStyle(.v3(.ghost, .small)).help("现金和刷卡分开填")
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
                V3Card {
                    V3CardTitle("店的这条路 · 回本", note: "照现在 2027 年 9 月")
                    Button { state.go(.payback) } label: {
                        HStack(spacing: 14) {
                            V3Ring(fraction: Double(back.cents) / Double(max(b.capitalTotal.cents, 1)))
                            VStack(alignment: .leading, spacing: 2) {
                                V3Label("本钱还差")
                                V3Amount((b.capitalTotal - back).v3, color: V3.ink, size: 26, weight: .heavy)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 2))
                }
                V3GrowCard {
                    V3CardTitle("给自己发工资")
                    V3RowList(rows: [.init("🏠", "11 月已经发了", "拿回家算「给自己发了」", "1.000,00 €", V3.teal)])
                    Button("两边转钱") { state.open(.transfer) }.buttonStyle(.v3(.ghost, .small)).help("从店里拿回家，或者自己垫钱给店里")
                }
            }
        }
    }
}

// MARK: - 营业额

struct V3SalesPage: View {
    @Environment(V3State.self) private var state

    var body: some View {
        let b = state.book
        let total = Int(b.shopSalesTotal.cents / 100)
        let count = b.shopOpenDays
        let gap = b.shopDays.first { $0.state == .missing && $0.day < b.todayDay }
        V3Cols(left: 1, right: 1.5) {
            VStack(spacing: 16) {
                if let gap {
                    V3Ask(face: "think", text: "\(gap.day) 号没记，休息还是忘了？", tone: .warn) {
                        HStack(spacing: 8) {
                            Button("是休息") { state.change("好，\(gap.day) 号算休息") { try $0.markShopRest(gap.day) } }.buttonStyle(.v3(.teal, .small))
                            Button("忘了，补上") { state.open(.shopDay(gap.day)) }.buttonStyle(.v3(.ghost, .small))
                        }
                    }
                } else {
                    V3Ask(face: "happy", text: "这个月每天都对上了。", tone: .good)
                }
                V3KeyCard(label: "11 月营业额", whole: Money(cents: Int64(total) * 100).v3Parts.whole, rest: ",00\u{00A0}€", size: 56, wave: V3.tealSoft) {
                    V3Label("\(count) 个营业日 · 平均每天 \(total / max(count, 1)) €")
                }
                V3GrowCard {
                    V3CardTitle("一周里哪天最旺")
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array([(42.0, "一"), (48, "二"), (45, "三"), (55, "四"), (70, "五"), (100, "六"), (0, "日")].enumerated()), id: \.offset) { _, w in
                            VStack(spacing: 4) {
                                GeometryReader { g in
                                    UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                                        .fill(w.0 == 100 ? V3.teal : V3.hex(0xA9D9DF))
                                        .frame(height: max(g.size.height * w.0 / 100, 4)).frame(maxHeight: .infinity, alignment: .bottom)
                                }
                                V3Label(w.1, size: 13)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .accessibilityElement().accessibilityLabel("一周里周六最旺，周日休息")
                }
            }
        } trailing: {
            V3GrowCard {
                V3CardTitle("11 月每天收了多少")
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { d in
                            Text(d).font(V3.font(12, .bold)).foregroundStyle(V3.ink2).frame(maxWidth: .infinity)
                        }
                    }
                    // 11 月 1 日是周日：前面空 6 格
                    let cells: [TrialBook.ShopDay?] = Array(repeating: nil, count: 6) + b.shopDays.map { Optional($0) }
                    ForEach(0..<6, id: \.self) { row in
                        GridRow {
                            ForEach(0..<7, id: \.self) { col in
                                let i = row * 7 + col
                                if i < cells.count, let d = cells[i] {
                                    if d.state == .future { cell(d) } else {
                                        Button { state.open(.shopDay(d.day)) } label: { cell(d) }.buttonStyle(V3SinkStyle(depth: 2)).help("点一下记这天或者改这天")
                                    }
                                } else { Color.clear }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func cell(_ d: TrialBook.ShopDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let kind = d.state
        let isToday = d.day == state.book.todayDay
        let amount = Int(d.total.cents / 100)
        VStack(alignment: .leading, spacing: 0) {
            Text("\(d.day)").font(V3.font(12, .regular))
            Spacer(minLength: 0)
            switch kind {
            case .open: Text("\(amount) €").font(V3.num(14))
            case .rest: Text("休息").font(V3.font(12, .regular))
            case .missing: Text(isToday ? "今天" : "没记").font(V3.font(13, .heavy)).foregroundStyle(isToday ? V3.teal : V3.red)
            case .future: EmptyView()
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(kind == .future ? V3.dash : kind == .rest ? V3.ink2 : kind == .open && Double(amount - 100) / 340 > 0.55 ? .white : V3.ink)
        .background {
            switch kind {
            case .open: shape.fill(V3.teal.opacity(0.12 + min(1, max(0, Double(amount - 100) / 340)) * 0.6))
            case .rest: shape.fill(.white).overlay(shape.strokeBorder(V3.hex(0xC9D3F2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            case .missing:
                if isToday { shape.fill(.white) } else {
                    shape.fill(V3.warnBG).overlay(shape.strokeBorder(V3.red, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                }
            case .future: shape.fill(V3.hex(0xF6F8FF))
            }
        }
        .overlay { if isToday { shape.strokeBorder(V3.ink, lineWidth: 2.5) } }
        .accessibilityElement()
        .accessibilityLabel("\(d.day) 号，" + (kind == .open ? "收了 \(amount) 欧" : kind == .rest ? "休息" : kind == .missing ? "还没记" : "还没到"))
    }
}

// MARK: - 固定开销

struct V3FixedPage: View {
    @Environment(V3State.self) private var state
    @State private var kept = false

    var body: some View {
        let b = state.book
        let ads = b.fixedCosts.first { $0.name == "广告" }
        let canSave = b.fixedCosts.filter { $0.flag && !$0.off }.map(\.amount).reduce(.zero, +)
        V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "每月固定要付", amount: b.fixedTotal, wave: V3.tealSoft) {
                    Text("等于每天一开门，要先收 \(b.dailyBreakEven.v3Short) 才够付").font(V3.font(14, .bold)).foregroundStyle(V3.teal)
                }
                if let ads {
                    if ads.off {
                        V3Ask(face: "happy", text: "12 月停广告，月底看客人少没少。", tone: .good) {
                            Button("还是开着") { state.change("好，广告接着投") { try $0.setFixedCost("广告", paused: false) } }.buttonStyle(.v3(.ghost, .small))
                        }
                    } else if kept {
                        V3Ask(face: "happy", text: "好，广告先留着。", tone: .good)
                    } else {
                        V3Ask(face: "think", text: "广告每月 \(ads.amount.v3Short)，没见带来新客人。停一个月试试？") {
                            HStack(spacing: 8) {
                                Button("停一个月试试") { state.change("好，12 月停广告") { try $0.setFixedCost("广告", paused: true) } }.buttonStyle(.v3(.teal, .small))
                                Button("先留着") { withAnimation(.snappy) { kept = true }; state.say("好，先留着") }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                    }
                }
                V3GrowCard {
                    V3CardTitle("如果停掉可省的")
                    V3Amount("每月省 \(canSave.v3)", color: V3.green, size: 28, weight: .heavy)
                    V3RowList(rows: b.fixedCosts.filter { $0.flag && !$0.off }.prefix(4).map { c in
                        .init(c.emoji, c.name, c.note, c.amount.v3, action: { state.open(.fixedEdit(c.name)) })
                    }, fill: true)
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                V3CardTitle("按花得多少排", note: "\(b.fixedCosts.count) 样")
                V3RowList(rows: b.fixedCosts.prefix(7).map { c in
                    .init(c.emoji, c.name, c.off ? "先停着" : c.note, c.off ? "0,00 €" : c.amount.v3, c.name.contains("工资") ? V3.teal : V3.navy,
                          tag: c.off ? "停着" : c.tag, tone: c.flag ? .gold : .teal, action: { state.open(.fixedEdit(c.name)) })
                }, compact: b.fixedCosts.count > 5, fill: true)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("加一样") { state.open(.fixed) }.buttonStyle(.v3(.teal, .small))
                }
            }
        }
    }
}

// MARK: - 回本

struct V3PaybackPage: View {
    @Environment(V3State.self) private var state

    var body: some View {
        let b = state.book
        let back = Money(cents: 16_728_00)
        let left = b.capitalTotal - back
        let frac = Double(back.cents) / Double(max(b.capitalTotal.cents, 1))
        V3Cols(left: 1.35, right: 1) {
            VStack(spacing: 16) {
                HStack(spacing: 22) {
                    V3Ring(fraction: frac, size: 120)
                    VStack(alignment: .leading, spacing: 4) {
                        V3Label("开店本钱还差")
                        V3Gold(amount: left, size: 56)
                        Text("照现在的速度，2027 年 9 月回本").font(V3.font(14, .bold)).foregroundStyle(V3.teal)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22).padding(.vertical, 18).v3Sticker()
                V3GrowCard {
                    V3CardTitle("一点点赚回来的")
                    V3Lines(height: 200, grid: [100, 199], lines: [
                        .init(points: [(0, 14), (560, 14)], color: V3.gold, width: 2.5, dash: [7, 6]),
                        .init(points: [(0, 196), (50, 186), (100, 172), (150, 160), (200, 142), (250, 128), (290, 104)], color: V3.teal, fill: V3.tealSoft),
                        .init(points: [(290, 104), (520, 14)], color: V3.teal, width: 3, dash: [3, 7]),
                    ], dot: (290, 104))
                    .frame(maxHeight: .infinity)
                    HStack { V3Label("开店 · 2025 年 10 月"); Spacer(); V3Label("今天"); Spacer(); V3Label("2027 年 9 月 · 回本") }
                }
                .accessibilityLabel("回本走了 \(Int(frac * 100))%")
                V3Ask(face: "think", text: "每月多赚 150 €，早 4 个月回本。", tone: .good)
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                V3CardTitle("本钱是这几样", note: "一共 \(b.capitalTotal.v3Short)")
                V3RowList(rows: b.capital.prefix(6).map { .init($0.emoji, $0.name, $0.note, $0.amount.v3) }, compact: b.capital.count > 4, fill: true)
                HStack(spacing: 26) {
                    V3KV(value: back.v3Short, label: "已经赚回来", color: V3.teal)
                    V3KV(value: left.v3Short, label: "还差", color: V3.gold)
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("后来又投了钱") { state.open(.capital) }.buttonStyle(.v3(.teal, .small))
                    Button("改总数") { state.open(.capitalTotal) }.buttonStyle(.v3(.ghost, .small))
                }
            }
        }
    }
}

// MARK: - 货值

struct V3StockPage: View {
    @Environment(V3State.self) private var state
    @State private var estimating = false
    @State private var text = ""
    @State private var later = false

    var body: some View {
        let b = state.book
        let latest = b.stockEstimates.first
        let value = latest?.amount ?? .zero
        let when = latest.map { "\($0.name)估的" } ?? "还没估过"
        let fresh = latest?.name == "今天"
        V3Cols(left: 1.2, right: 1) {
            VStack(spacing: 16) {
                if later || fresh {
                    V3Ask(face: "happy", text: fresh ? "记好了，季度末再估一次。" : "好，12 月 28 日再叫你。", tone: .good)
                } else {
                    V3Ask(face: "think", text: estimating ? "货架上的货大约值多少？" : "12 月底该估货了，现在先估也行。") {
                        if estimating {
                            HStack(spacing: 8) {
                                V3Field(prompt: "大约值多少", text: $text, rounded: true) { save() }.frame(width: 150)
                                Button("就这个数") { save() }.buttonStyle(.v3(.teal, .small))
                            }
                        } else {
                            HStack(spacing: 8) {
                                Button("现在估") { withAnimation(.snappy) { estimating = true } }.buttonStyle(.v3(.teal, .small))
                                Button("到时候再说") { withAnimation(.snappy) { later = true }; state.say("好，12 月 28 日提醒你") }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                    }
                }
                V3KeyCard(label: "店里的货，大约值", amount: value, wave: V3.tealSoft) {
                    V3Label(when)
                }
                V3GrowCard {
                    V3CardTitle("上个季度用掉和损耗了多少")
                    HStack(spacing: 8) {
                        V3Tile(label: "6 月底估的", value: "2.400 €"); Text("+").font(V3.font(16, .heavy))
                        V3Tile(label: "那三个月进货", value: "1.150 €"); Text("−").font(V3.font(16, .heavy))
                        V3Tile(label: "9 月底估的", value: "2.600 €"); Text("=").font(V3.font(16, .heavy))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("用掉和损耗").font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                            Text("950 €").font(V3.num(20)).foregroundStyle(V3.gold)
                        }
                        .lineLimit(1).padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(V3.goodBG))
                    }
                    V3CardTitle("每次估的").padding(.top, 8)
                    V3RowList(rows: b.stockEstimates.prefix(4).map { .init($0.emoji, $0.name, $0.note, $0.amount.v3) }, fill: true)
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                V3CardTitle("这个季度进的货", note: "\(b.purchases.count) 次 · \(b.purchases.map(\.amount).reduce(.zero, +).v3Short)")
                V3RowList(rows: b.purchases.prefix(5).map { .init($0.emoji, $0.name, $0.note, (-$0.amount).v3) }, fill: true)
                Spacer(minLength: 0)
                Button("记一次进货") { state.open(.purchase) }.buttonStyle(.v3(.teal, .small))
            }
        }
    }

    private func save() {
        guard let m = V3Form.amount(text) else { state.fail("这个数我没看懂。写成 2800 这样就行"); return }
        if state.change("记好了：店里的货大约值 \(m.v3)", { try $0.estimateStock(m, note: "刚估的") }) {
            withAnimation(.snappy) { estimating = false; later = true }
        }
    }
}

// MARK: - 店的体检

struct V3CheckupPage: View {
    private let split: [(String, Double, UInt32)] = [("房租", 22, 0x7FA3F0), ("进货", 18, 0xF2A65A), ("水电杂费", 12, 0xC9A0DC), ("给自己的工资", 22, 0x2E3A82), ("真正赚的", 26, 0xF2B93B)]

    var body: some View {
        V3Cols(left: 1.2, right: 1) {
            VStack(spacing: 16) {
                V3KeyCard(label: "你每小时赚", amount: Money(cents: 10_49), wave: V3.tealSoft) {
                }
                V3Card {
                    V3CardTitle("营业额每 100 € 去哪了")
                    GeometryReader { g in
                        HStack(spacing: 0) {
                            ForEach(Array(split.enumerated()), id: \.offset) { _, s in Rectangle().fill(V3.hex(s.2)).frame(width: g.size.width * s.1 / 100) }
                        }
                    }
                    .frame(height: 30).clipShape(Capsule()).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2.5))
                    HStack(spacing: 22) {
                        ForEach(Array(split.enumerated()), id: \.offset) { i, s in
                            VStack(alignment: .leading, spacing: 0) {
                                V3Amount("\(Int(s.1)) €", color: i == 4 ? V3.gold : V3.ink, size: 17)
                                HStack(spacing: 4) { Circle().fill(V3.hex(s.2)).frame(width: 8, height: 8); Text(s.0).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1).fixedSize() }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                V3Question(face: "think", text: "下个季度先试哪个？一次试一个。",
                           answers: [("周六多开 2 小时", "好，这就是店里下个季度的那一站：周六多开 2 小时"), ("停掉广告", "好，下个季度先试停掉广告"), ("先不试", "好，下个季度再问你")])
            }
        } trailing: {
            VStack(spacing: 16) {
                V3GrowCard(spacing: 6) {
                    V3CardTitle("怎么多赚一点")
                    V3RowList(rows: [
                        .init("🕑", "周六多开 2 小时", "周六一小时收的是平时的 2 倍", "大约 +160 € / 月", V3.green),
                        .init("📣", "停掉广告试一个月", "每月 80 €，看不出带来客人", "+80 € / 月", V3.green),
                        .init("📦", "进货少囤一点", "上季度损耗 210 €", "大约 +70 € / 月", V3.green),
                    ], fill: true)
                    Spacer(minLength: 0)
                }
                V3Card {
                    V3CardTitle("和上个季度比")
                    HStack(spacing: 26) {
                        V3KV(value: "+6%", label: "营业额", color: V3.green)
                        V3KV(value: "+0,80\u{00A0}€", label: "每小时赚的", color: V3.green)
                        V3KV(value: "52%", label: "回本走到")
                    }
                }
            }
        }
    }
}

// MARK: - 生意欠款

struct V3BizDebtsPage: View {
    @Environment(V3State.self) private var state
    @State private var moved = false

    var body: some View {
        let b = state.book
        let owe = b.shopDebts.filter { !$0.flag }
        let owed = b.shopDebts.filter(\.flag)
        let open = owe.filter { !$0.off }.map(\.amount).reduce(.zero, +)
        let first = owe.first { !$0.off }
        V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "12 月店里要还", amount: Money(cents: 350_00) + open, wave: V3.tealSoft) {
                    HStack(spacing: 26) {
                        V3KV(value: (Money(cents: 8_400_00) + open).v3, label: "店一共欠", color: V3.red)
                        V3KV(value: owed.filter { !$0.off }.map(\.amount).reduce(.zero, +).v3, label: "别人欠店里")
                    }
                }
                if let first {
                    V3Ask(face: "worried", text: "\(first.name)那 \(first.amount.v3Short)\(first.note.isEmpty ? "" : "，" + first.note)。拖了下次不给赊。", tone: .warn, kicker: "要留意") {
                        Button("现在记还款") { state.change("还款记好了 · \(first.name) \(first.amount.v3)", kind: .repay) { try $0.payShopDebt(first.name) } }.buttonStyle(.v3(.teal, .small))
                    }
                } else {
                    V3Ask(face: "happy", text: "赊的账都清了。", tone: .good)
                }
                V3GrowCard {
                    V3CardTitle("还贷款怎么算", note: "每月 350 €")
                    GeometryReader { g in
                        HStack(spacing: 0) {
                            Rectangle().fill(V3.teal).frame(width: g.size.width * 310 / 350)
                            Rectangle().fill(V3.star)
                        }
                    }
                    .frame(height: 22).clipShape(Capsule()).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2.5))
                    V3RowList(rows: [.init("🏦", "本金", "不算开销", "310,00 €", V3.teal), .init("💸", "利息", "才算开销", "40,00 €", V3.gold),
                                     .init("📅", "还剩 24 期", "2028 年 11 月还完", "")], fill: true)
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 8) {
                V3CardTitle("先还哪个")
                V3RowList(rows: owe.prefix(3).map { d in
                    d.off ? .init(d.emoji, d.name, d.note, "0,00 €", V3.green, tag: "还清了", tone: .green)
                          : .init(d.emoji, d.name, d.note, d.amount.v3, V3.red, tag: d.id == first?.id ? "先还这个" : "", tone: .red)
                } + [.init("🏦", "装修贷款", moved ? "这一期挪到 1 月 15 日 · 还剩 24 期" : "每月 15 日 · 还剩 24 期", "350,00 € / 月", V3.red, tag: "按月还就行")],
                          compact: owe.count > 2, fill: true)
                V3Periods(total: 36, done: 12, color: V3.teal, height: 14)
                V3Label("装修贷款 · 36 期还了 12 期")
                V3CardTitle("别人欠店里的").padding(.top, 6)
                V3RowList(rows: owed.prefix(3).map { .init($0.emoji, $0.name, $0.note, $0.amount.v3) }, compact: owed.count > 1, fill: true)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("记一笔欠款") { state.open(.shopDebt) }.buttonStyle(.v3(.teal, .small))
                    Button(moved ? "还是按原来的还" : "这个月还不上") {
                        withAnimation(.snappy) { moved.toggle() }
                        state.say(moved ? "没事，贷款这一期挪到下个月要多付 6 € 利息，供货商那笔不能拖" : "好，还是按原来的日子还")
                    }
                    .buttonStyle(.v3(.ghost, .small))
                }
            }
        }
    }
}
#endif
