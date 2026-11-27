#if os(macOS)
import FinanceCore
import SwiftUI

// 生意这边 7 页：给一个人开店的小老板。同一套样子，主色换成海水青；店的那条路是「回本」。
// 数字是设计稿里那套编的示例（Miora 小店）。

// MARK: - 生意首页

struct V3BizHomePage: View {
    @Environment(V3State.self) private var state
    @State private var todayText = "186,00"
    @State private var recorded: Money?

    var body: some View {
        V3Cols(left: 1.35, right: 1) {
            VStack(spacing: 16) {
                V3Ask(face: "think", text: "周六收得最多，一天顶平时两天。固定开销已经赚回来了，后面收的都是你的。", kicker: "每周一句")
                    .frame(maxWidth: 560).frame(maxWidth: .infinity, alignment: .leading)
                V3KeyCard(label: "11 月 · 真正赚了（已扣掉给自己发的 1.000 € 工资）", amount: Money(cents: 1_520_26), wave: V3.tealSoft) {
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
                    V3Label(recorded == nil ? "今天收了多少" : "今天收了（已经记好）")
                    HStack(spacing: 10) {
                        V3Field(prompt: "0,00", text: $todayText, size: 22, rounded: true)
                        Text("€").font(V3.num(20)).foregroundStyle(V3.ink2)
                        Button(recorded == nil ? "记好" : "改一下") {
                            guard let m = Money(parsing: todayText), m >= .zero else {
                                state.say("这个数我没看懂。写成 186 或者 186,00 这样就行")
                                return
                            }
                            withAnimation(.snappy) { recorded = m }
                            state.say("记好了 · 今天 \(m.v3)\(m >= Money(cents: 60_00) ? "，够付今天的固定开销了" : "，离今天的固定开销还差 \((Money(cents: 60_00) - m).v3Short)")")
                        }
                        .buttonStyle(.v3(.teal))
                    }
                    V3Label("每天只记一个总数，不用记每一单。")
                }
                .padding(.horizontal, 22).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
                V3Card {
                    V3CardTitle("店的这条路 · 回本", note: "照现在 2027 年 9 月")
                    Button { state.go(.payback) } label: {
                        HStack(spacing: 14) {
                            V3Ring(fraction: 0.52)
                            VStack(alignment: .leading, spacing: 2) {
                                V3Label("本钱还差")
                                V3Amount("15.442,00\u{00A0}€", color: V3.ink, size: 26, weight: .heavy)
                                V3Label("回本那天，也有一封信")
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(V3SinkStyle(depth: 2))
                }
                V3GrowCard {
                    V3CardTitle("给自己发工资", note: "每月 1 日")
                    V3RowList(rows: [.init("🏠", "11 月已经发了", "拿回家算「给自己发了」", "1.000,00 €", V3.teal)])
                    V3SayButton("多拿一点回家", "拿多少？我先算算店里够不够（试用版先不真的动钱）", .ghost)
                }
            }
        }
    }
}

// MARK: - 营业额

struct V3SalesPage: View {
    @Environment(V3State.self) private var state
    /// 16 号那天：nil 还没回答，0 = 休息，别的 = 补记的数。
    @State private var day16: Int?
    @State private var asking = false
    @State private var fill = ""

    struct Day { var day: Int; var amount: Int; var kind: Kind
        enum Kind { case open, rest, missing, future } }

    /// 和设计稿同一个算法生成的 11 月每天营业额。
    static let days: [Day] = {
        var r = 11.0
        var out: [Day] = []
        for d in 1...30 {
            r = (r * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
            let wd = (d + 5) % 7
            var amt = 120 + Int((r / 233280 * 140).rounded())
            if wd == 5 { amt += 170 }
            let kind: Day.Kind = d > 18 ? .future : wd == 6 ? .rest : d == 16 ? .missing : .open
            out.append(Day(day: d, amount: amt, kind: kind))
        }
        return out
    }()

    var body: some View {
        let open = Self.days.filter { $0.kind == .open }
        let extra = (day16 ?? 0) > 0 ? day16! : 0
        let total = open.map(\.amount).reduce(0, +) + extra
        let count = open.count + (extra > 0 ? 1 : 0)
        V3Cols(left: 1, right: 1.5) {
            VStack(spacing: 16) {
                if day16 == nil {
                    HStack(alignment: .top, spacing: 10) {
                        V3Face(face: "think")
                        V3Bubble(asking ? "16 号那天收了多少？" : "16 号那天没记，是休息还是忘了？", tone: .warn) {
                            if asking {
                                HStack(spacing: 8) {
                                    V3Field(prompt: "收了多少", text: $fill, rounded: true) { saveFill() }.frame(width: 130)
                                    Button("补上") { saveFill() }.buttonStyle(.v3(.teal, .small))
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Button("是休息") { withAnimation(.snappy) { day16 = 0 }; state.say("好，16 号算休息") }.buttonStyle(.v3(.teal, .small))
                                    Button("忘了，补上") { withAnimation(.snappy) { asking = true } }.buttonStyle(.v3(.ghost, .small))
                                }
                            }
                        }
                    }
                } else {
                    V3Ask(face: "happy", text: day16 == 0 ? "好，16 号算休息。这个月每天都对上了。" : "补上了：16 号收了 \(day16!) €。这个月每天都对上了。", tone: .good)
                }
                V3KeyCard(label: "11 月营业额", whole: Money(cents: Int64(total) * 100).v3Parts.whole, rest: ",00\u{00A0}€", size: 56, wave: V3.tealSoft) {
                    V3Label("\(count) 个营业日 · 平均每天 \(total / max(count, 1)) € · 每天先收 60 € 才够付固定开销")
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
                V3CardTitle("11 月每天收了多少", note: "颜色越深收得越多")
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { d in
                            Text(d).font(V3.font(12, .bold)).foregroundStyle(V3.ink2).frame(maxWidth: .infinity)
                        }
                    }
                    // 11 月 1 日是周日：前面空 6 格
                    let cells: [Day?] = Array(repeating: nil, count: 6) + Self.days.map { Optional($0) }
                    ForEach(0..<6, id: \.self) { row in
                        GridRow {
                            ForEach(0..<7, id: \.self) { col in
                                let i = row * 7 + col
                                if i < cells.count, let d = cells[i] { cell(d) } else { Color.clear }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func saveFill() {
        guard let m = Money(parsing: fill), m > .zero else { state.say("这个数我没看懂。写成 180 这样就行"); return }
        withAnimation(.snappy) { day16 = Int(m.cents / 100); asking = false }
        state.say("补上了：16 号收了 \(m.v3)")
    }

    @ViewBuilder private func cell(_ d: Day) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let kind: Day.Kind = d.day == 16 && day16 != nil ? (day16 == 0 ? .rest : .open) : d.kind
        let amount = d.day == 16 ? (day16 ?? 0) : d.amount
        VStack(alignment: .leading, spacing: 0) {
            Text("\(d.day)").font(V3.font(12, .regular))
            Spacer(minLength: 0)
            switch kind {
            case .open: Text("\(amount) €").font(V3.num(14))
            case .rest: Text("休息").font(V3.font(12, .regular))
            case .missing: Text("没记").font(V3.font(13, .heavy)).foregroundStyle(V3.red)
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
            case .missing: shape.fill(V3.warnBG).overlay(shape.strokeBorder(V3.red, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
            case .future: shape.fill(V3.hex(0xF6F8FF))
            }
        }
        .overlay { if d.day == 18 { shape.strokeBorder(V3.ink, lineWidth: 2.5) } }
        .accessibilityElement()
        .accessibilityLabel("\(d.day) 号，" + (kind == .open ? "收了 \(amount) 欧" : kind == .rest ? "休息" : kind == .missing ? "没记" : "还没到"))
    }
}

// MARK: - 固定开销

struct V3FixedPage: View {
    @Environment(V3State.self) private var state
    @State private var adsOff: Bool?

    var body: some View {
        let monthly = Money(cents: adsOff == true ? 1_710_00 : 1_790_00)
        V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "每月固定要付", amount: monthly, wave: V3.tealSoft) {
                    Text("等于每天一开门，要先收 \(adsOff == true ? 57 : 60) € 才够付").font(V3.font(14, .bold)).foregroundStyle(V3.teal)
                }
                if let adsOff {
                    V3Ask(face: "happy", text: adsOff ? "好，12 月停广告。月底我告诉你客人有没有少。" : "好，广告先留着。", tone: .good)
                } else {
                    V3Ask(face: "think", text: "广告每月 80 €，这三个月看不出带来了新客人。要不要先停一个月试试？我不替你决定。") {
                        HStack(spacing: 8) {
                            Button("停一个月试试") { withAnimation(.snappy) { adsOff = true }; state.say("好，12 月停广告，月底我告诉你客人有没有少") }.buttonStyle(.v3(.teal, .small))
                            Button("先留着") { withAnimation(.snappy) { adsOff = false }; state.say("好，先留着") }.buttonStyle(.v3(.ghost, .small))
                        }
                    }
                }
                V3GrowCard {
                    V3CardTitle("如果停掉可省的")
                    V3Amount("每月省 120,00\u{00A0}€", color: V3.green, size: 28, weight: .heavy)
                    V3Label("广告和预约软件都停掉：每天开门要先收的，从 60 € 变成 56 €")
                }
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                V3CardTitle("按花得多少排", note: "5 样")
                V3RowList(rows: [
                    .init("🧑", "给自己发的工资", "每月 1 日 · 扣掉它才算真赚", "1.000,00 €", V3.teal, tag: "必要", tone: .teal),
                    .init("🏠", "店面房租", "每月 3 日", "600,00 €", tag: "必要", tone: .teal),
                    .init("📣", "广告", adsOff == true ? "12 月先停一个月" : "每月 10 日", adsOff == true ? "0,00 €" : "80,00 €", tag: adsOff == true ? "停着" : "可省", tone: .gold),
                    .init("💡", "水电", "每月 15 日 · 最近 3 个月平均", "70,00 €", tag: "必要", tone: .teal),
                    .init("🗓", "预约软件", "每月 20 日", "40,00 €", tag: "可省", tone: .gold),
                ])
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    V3SayButton("加一样", "好，叫什么、每月多少？（试用版先不能加）", .teal)
                    V3Label("流水里连着 3 个月都有的，我会问你要不要加进来。")
                }
            }
        }
    }
}

// MARK: - 回本

struct V3PaybackPage: View {
    var body: some View {
        V3Cols(left: 1.35, right: 1) {
            VStack(spacing: 16) {
                HStack(spacing: 22) {
                    V3Ring(fraction: 0.52, size: 120)
                    VStack(alignment: .leading, spacing: 4) {
                        V3Label("开店本钱还差")
                        V3Gold(amount: Money(cents: 15_442_00), size: 56)
                        Text("照现在的速度，2027 年 9 月回本").font(V3.font(14, .bold)).foregroundStyle(V3.teal)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22).padding(.vertical, 18).v3Sticker()
                V3GrowCard {
                    V3CardTitle("一点点赚回来的", note: "虚线是照现在的速度")
                    V3Lines(height: 200, grid: [100, 199], lines: [
                        .init(points: [(0, 14), (560, 14)], color: V3.gold, width: 2.5, dash: [7, 6]),
                        .init(points: [(0, 196), (50, 186), (100, 172), (150, 160), (200, 142), (250, 128), (290, 104)], color: V3.teal, fill: V3.tealSoft),
                        .init(points: [(290, 104), (520, 14)], color: V3.teal, width: 3, dash: [3, 7]),
                    ], dot: (290, 104))
                    .frame(maxHeight: .infinity)
                    HStack { V3Label("开店 · 2025 年 10 月"); Spacer(); V3Label("今天"); Spacer(); V3Label("2027 年 9 月 · 回本") }
                }
                .accessibilityLabel("回本走了 52%，照现在的速度 2027 年 9 月回本")
                V3Ask(face: "think", text: "每月多赚 150 €，能早 4 个月回本。回本那天，我给你写一封信。", tone: .good)
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                V3CardTitle("本钱是这几样", note: "一共 32.170 €")
                V3RowList(rows: [
                    .init("🔨", "装修", "2025 年 9 月", "14.000,00 €"), .init("💺", "设备和桌椅", "2025 年 9 月", "9.800,00 €"),
                    .init("📦", "第一批货", "2025 年 10 月", "4.200,00 €"), .init("🔑", "押金", "退租时能拿回", "4.170,00 €"),
                ])
                HStack(spacing: 26) {
                    V3KV(value: "16.728\u{00A0}€", label: "已经赚回来", color: V3.teal)
                    V3KV(value: "15.442\u{00A0}€", label: "还差", color: V3.gold)
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
                V3SayButton("后来又投了钱", "好，投了多少、做什么用？（试用版先不能加）", .teal)
            }
        }
    }
}

// MARK: - 货值

struct V3StockPage: View {
    @Environment(V3State.self) private var state
    @State private var estimating = false
    @State private var text = ""
    @State private var value = Money(cents: 2_600_00)
    @State private var when = "9 月 30 日估的"
    @State private var later = false

    var body: some View {
        V3Cols(left: 1.2, right: 1) {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    V3Face(face: later ? "happy" : "think")
                    if later {
                        V3Bubble("好，12 月 28 日提醒你重新估一次。", tone: .good)
                    } else {
                        V3Bubble(estimating ? "店里的货现在大约值多少？估个总数就行。" : "12 月底是季度末，到时候我提醒你重新估一次。现在想先估也行。") {
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
                }
                V3KeyCard(label: "店里的货，大约值", amount: value, wave: V3.tealSoft) {
                    V3Label("\(when) · 不用一样一样数，估个总数就行")
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
                    V3Label("其中大约 210 € 是过期、打碎这类损耗（按你标的算）。")
                }
            }
        } trailing: {
            VStack(spacing: 16) {
                V3Card(spacing: 6) {
                    V3CardTitle("这个季度进的货", note: "3 次 · 890 €")
                    V3RowList(rows: [.init("📦", "甲油胶补货", "11 月 12 日", "−340,00 €"), .init("📦", "工具和耗材", "10 月 28 日", "−310,00 €"),
                                     .init("📦", "饰品", "10 月 6 日", "−240,00 €")], compact: true)
                    V3SayButton("记一次进货", "进了多少钱的货？（试用版先不能加）", .teal)
                }
                V3GrowCard(spacing: 6) {
                    V3CardTitle("每次估的")
                    V3RowList(rows: (when == "今天估的" ? [.init("📅", "今天", "刚估的", value.v3)] : [])
                              + [.init("📅", "9 月 30 日", "第三季度末", "2.600,00 €"), .init("📅", "6 月 30 日", "第二季度末", "2.400,00 €"),
                                 .init("📅", "开店时", "2025 年 10 月", "4.200,00 €")], compact: true)
                }
            }
        }
    }

    private func save() {
        guard let m = Money(parsing: text), m > .zero else { state.say("这个数我没看懂。写成 2800 这样就行"); return }
        withAnimation(.snappy) { value = m; when = "今天估的"; estimating = false; later = true }
        state.say("记好了：店里的货大约值 \(m.v3)")
    }
}

// MARK: - 店的体检

struct V3CheckupPage: View {
    private let split: [(String, Double, UInt32)] = [("房租", 22, 0x7FA3F0), ("进货", 18, 0xF2A65A), ("水电杂费", 12, 0xC9A0DC), ("给自己的工资", 22, 0x2E3A82), ("真正赚的", 26, 0xF2B93B)]

    var body: some View {
        V3Cols(left: 1.2, right: 1) {
            VStack(spacing: 16) {
                V3KeyCard(label: "值不值得继续开？换算下来，你每小时赚", amount: Money(cents: 10_49), wave: V3.tealSoft) {
                    V3Label("去店里打工大概每小时 9 € · 你多赚一点，店还是你自己的")
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
                V3Question(face: "think", text: "下个季度先试哪一个？一次只试一个，我每周跟你说进展。",
                           answers: [("周六多开 2 小时", "好，这就是店里下个季度的那一站：周六多开 2 小时"), ("停掉广告", "好，下个季度先试停掉广告"), ("先不试", "好，下个季度再问你")])
            }
        } trailing: {
            VStack(spacing: 16) {
                V3GrowCard(spacing: 6) {
                    V3CardTitle("怎么多赚一点", note: "按规则算的，不是瞎猜")
                    V3RowList(rows: [
                        .init("🕑", "周六多开 2 小时", "周六一小时收的是平时的 2 倍", "大约 +160 € / 月", V3.green),
                        .init("📣", "停掉广告试一个月", "每月 80 €，看不出带来客人", "+80 € / 月", V3.green),
                        .init("📦", "进货少囤一点", "上季度损耗 210 €", "大约 +70 € / 月", V3.green),
                    ])
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
    @State private var paid = false
    @State private var moved = false

    var body: some View {
        V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "12 月店里要还", amount: Money(cents: paid ? 350_00 : 670_00), wave: V3.tealSoft) {
                    HStack(spacing: 26) {
                        V3KV(value: Money(cents: paid ? 8_400_00 : 8_720_00).v3, label: "店一共欠", color: V3.red)
                        V3KV(value: "85,00\u{00A0}€", label: "别人欠店里")
                    }
                }
                if paid {
                    V3Ask(face: "happy", text: "供货商那 320 € 还清了，下次还能赊账。", tone: .good)
                } else {
                    V3Ask(face: "worried", text: "供货商那 320 € 12 月 3 日到期，拖了下次不给赊账。店里账户够付。", tone: .warn, kicker: "要留意") {
                        Button("现在记还款") { withAnimation(.snappy) { paid = true }; state.say("还款记好了 · 供货商 320 €") }.buttonStyle(.v3(.teal, .small))
                    }
                }
                V3GrowCard {
                    V3CardTitle("还贷款怎么算")
                    V3Label("每月还的 350 € 里，本金 310 € 不算开销，利息 40 € 才算。所以「真正赚了」只扣利息，「手里实际多了」两样都扣。")
                }
            }
        } trailing: {
            V3GrowCard(spacing: 8) {
                V3CardTitle("先还哪个", note: "拖了有后果的排前面")
                V3RowList(rows: [
                    paid ? .init("📦", "供货商赊账", "刚还清", "0,00 €", V3.green, tag: "还清了", tone: .green)
                         : .init("📦", "供货商赊账", "12 月 3 日到期", "320,00 €", V3.red, tag: "先还这个", tone: .red),
                    .init("🏦", "装修贷款", moved ? "这一期挪到 1 月 15 日 · 还剩 24 期" : "每月 15 日 · 还剩 24 期", "350,00 € / 月", V3.red, tag: "按月还就行"),
                ])
                V3Periods(total: 36, done: 12, color: V3.teal, height: 14)
                V3Label("装修贷款 · 36 期还了 12 期")
                V3CardTitle("别人欠店里的").padding(.top, 6)
                V3RowList(rows: [.init("🧑", "熟客挂账", "11 月 9 日 · 说下次来付", "85,00 €")])
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    V3SayButton("记一笔欠款", "谁欠谁、多少？（试用版先不能加）", .teal)
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
