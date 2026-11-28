#if os(macOS)
import FinanceCore
import SwiftUI

// 生意这边 7 页：给一个人开店的小老板。同一套样子，主色换成海水青；店的那条路是「回本」。
// 数字是设计稿里那套编的示例（晴空小花店）。

// MARK: - 生意首页

struct V3BizHomePage: View {
    @Environment(V3State.self) private var state
    @State private var todayText = ""

    /// 只填一个总数：先都算刷卡收的，想分开再点「分开填」。
    private func quick() {
        guard let m = V3Form.amount(todayText) else { state.fail("这个数没看懂，写成 186 这样就行"); return }
        let need = state.book.dailyBreakEven
        let day = state.book.todayDay
        state.change(m >= need ? "记好了 · 今天 \(m.v3)，今天不亏了" : "记好了 · 今天 \(m.v3)，离不亏还差 \((need - m).v3Short)", kind: .add) { try $0.recordShopDay(day, cash: .zero, card: m) }
    }

    var body: some View {
        let b = state.book
        let today = b.shopDays.first { $0.day == b.todayDay }
        let done = today?.state == .open
        let back = b.shopBack
        // 店里赚多少只有一个算法（ShopNumbers.swift）：真正赚了 = 收的 − 开销；手里实际多了 = 再减进的货和还的贷款
        let m = b.shopMonth()
        V3Cols(left: 1.35, right: 1) {
            VStack(spacing: 16) {
                V3KeyCard(label: "\(state.monthLabel) · 真正赚了", amount: m.earned, wave: V3.tealSoft) {
                    HStack(spacing: 26) {
                        V3KV(value: m.income.v3, label: "收了", color: V3.teal)
                        V3KV(value: m.costs.v3, label: "开销", color: V3.red)
                    }
                }
                V3GrowCard {
                    V3CardTitle("「赚了」和「手里实际多了」为什么不一样")
                    HStack(spacing: 16) {
                        V3Tile(label: "真正赚了", value: m.earned.v3, color: V3.teal)
                        V3Label("差的 \((m.earned - m.cashChange).v3Short) 去了").fixedSize()
                        V3Tile(label: "手里实际多了", value: m.cashChange.v3, color: V3.teal)
                    }
                    V3RowList(rows: [.init("📦", "进了货", "还在店里，卖掉才算", (-m.purchases).v3), .init("🏦", "还贷款", "是还钱，不算开销", (-m.loanPaid).v3)])
                }
            }
        } trailing: {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    V3Label(done ? "今天收了" : today?.state == .rest ? "今天休息" : "今天收了多少")
                    HStack(spacing: 10) {
                        if done, let today {
                            V3Amount(today.total.v3, color: V3.teal, size: 30, weight: .heavy)
                            if today.total >= b.dailyBreakEven { V3Tag(text: "今天不亏了", tone: .teal).help(b.breakEvenNote) }
                        }
                        if !done {
                            V3Field(prompt: "0,00", text: $todayText, size: 22, rounded: true) { quick() }
                            Text("€").font(V3.num(20)).foregroundStyle(V3.ink2)
                            Button("记好") { quick() }.buttonStyle(.v3(.teal))
                        }
                        Spacer(minLength: 0)
                        Button(done ? "改一下" : "按渠道填") { state.open(.shopDay(b.todayDay)) }.buttonStyle(.v3(.ghost, .small))
                    }
                    // 按收款渠道：每个店账户今天收了多少
                    if done, let today {
                        HStack(spacing: 14) {
                            ForEach(b.channels(of: today).prefix(4)) { c in
                                HStack(spacing: 5) {
                                    Text(c.account).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
                                    V3Amount(c.amount.v3Short, color: V3.ink, size: 13.5)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
                V3Card {
                    V3CardTitle("店的这条路 · 回本", note: b.paybackDateLabel().map { $0 == "已经回本" ? $0 : "照现在 \($0)" } ?? "")
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
                Button { state.go(.shopWealth) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            V3Label("店的家底")
                            V3Amount(b.shopWorth.net.v3, color: V3.teal, size: 24, weight: .heavy)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(V3.ink2)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).v3Soft()
                    .contentShape(Rectangle())
                }
                .buttonStyle(V3SinkStyle(depth: 2)).help("店里一共值多少")
                V3GrowCard {
                    V3CardTitle("给自己发工资")
                    if let paid = b.ownerPaidThisMonth {
                        // 正式账本：这个月从店里拿回家的，从两边转钱的流水算
                        V3RowList(rows: [.init("🏠", paid > .zero ? "\(b.thisMonth.month) 月拿回家了" : "\(b.thisMonth.month) 月还没拿过", "拿回家算「给自己发了」", paid.v3, V3.teal)])
                    } else {
                        V3RowList(rows: [.init("🏠", "11 月已经发了", "拿回家算「给自己发了」", "1.000,00 €", V3.teal)])
                    }
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
                        let avgs = b.shopWeekdayAverages
                        let top = max(avgs.map(\.cents).max() ?? 1, 1)
                        ForEach(Array(zip(avgs.map { Double($0.cents) / Double(top) * 100 }, ["一", "二", "三", "四", "五", "六", "日"]).enumerated()), id: \.offset) { _, w in
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
                    .accessibilityElement().accessibilityLabel("一周里每天平均收多少")
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
        let rises = b.fixedRises
        V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "每月固定要付", amount: b.fixedTotal, wave: V3.tealSoft) {
                    Text("每个开门的日子收够 \(b.dailyBreakEven.v3Short) 才不亏").font(V3.font(14, .bold)).foregroundStyle(V3.teal)
                        .help(b.breakEvenNote)
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
                // 比上个月多了的：哪一样涨了、涨多少。没有就不出现。
                if !rises.isEmpty {
                    V3GrowCard {
                        V3CardTitle("比上个月多了的")
                        V3Amount("多付 \(rises.map(\.rise).reduce(.zero, +).v3)", color: V3.red, size: 28, weight: .heavy)
                        V3RowList(rows: rises.prefix(4).map { r in
                            .init(r.item.emoji, r.item.name, "上个月 \((r.item.lastMonth ?? .zero).v3Short)，现在 \(r.item.amount.v3Short)", "+\(r.rise.v3)", V3.red,
                                  action: { state.open(.fixedEdit(r.item.name)) })
                        }, fill: true)
                        Spacer(minLength: 0)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                V3CardTitle("按花得多少排", note: "\(b.fixedCosts.count) 样")
                V3RowList(rows: b.fixedCosts.prefix(7).map { c in
                    .init(c.emoji, c.name, c.off ? "先停着" : c.note, c.off ? "0,00 €" : c.amount.v3, c.name.contains("工资") ? V3.teal : V3.navy,
                          tag: c.off ? "停着" : "", tone: .teal, action: { state.open(.fixedEdit(c.name)) })
                }, compact: b.fixedCosts.count > 5, fill: true)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 回本

struct V3PaybackPage: View {
    @Environment(V3State.self) private var state

    /// 回本那条线在图上的点（图宽 560、高 200；金线在 y=14，底在 y=196）。横轴一格是一个月：已经过去的月份 + 还要几个月回本。
    static func curve(_ b: TrialBook) -> (done: [(Double, Double)], ahead: [(Double, Double)]) {
        let pts = b.paybackCurve
        let total = max(b.capitalTotal.cents, 1)
        func y(_ m: Money) -> Double { 196 - min(max(Double(m.cents) / Double(total), 0), 1) * 182 }
        let ahead = b.paybackLeft == .zero ? 0 : (b.paybackMonths() ?? 0)
        // 第一个点前面留一格当「开店那天还没赚回来」；没有过去的数时，就只有开店和今天两个点
        let steps = Double(max(pts.count + min(ahead, 120), 1))
        var done: [(Double, Double)] = [(0, 196)]
        for (i, p) in pts.enumerated() { done.append((Double(i + 1) / steps * 560, y(p.back))) }
        guard ahead > 0, let last = done.last else { return (done, []) }
        return (done, [last, (560, 14)])
    }

    var body: some View {
        let b = state.book
        let back = b.shopBack
        let left = b.paybackLeft
        let frac = b.paybackFraction
        let months = b.paybackMonths()
        let faster = b.paybackMonths(extra: Money(cents: 150_00))
        let line = Self.curve(b)
        V3Cols(left: 1.35, right: 1) {
            VStack(spacing: 16) {
                HStack(spacing: 22) {
                    V3Ring(fraction: frac, size: 120)
                    VStack(alignment: .leading, spacing: 4) {
                        V3Label("开店本钱还差")
                        V3Gold(amount: left, size: 56)
                        Text(months.map { "\(b.paybackSpeedNote)，再 \($0) 个月回本" } ?? "最近没赚到钱，算不出什么时候回本").font(V3.font(14, .bold)).foregroundStyle(V3.teal)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22).padding(.vertical, 18).v3Sticker()
                V3GrowCard {
                    V3CardTitle("一点点赚回来的")
                    // 按账本画：过去每个月底一共赚回来多少，最后一个点是今天；虚线接到回本的那个月；顶上那条金线是开店本钱
                    V3Lines(height: 200, grid: [100, 199], lines: [
                        .init(points: [(0, 14), (560, 14)], color: V3.gold, width: 2.5, dash: [7, 6]),
                        .init(points: line.done, color: V3.teal, fill: V3.tealSoft),
                        .init(points: line.ahead, color: V3.teal, width: 3, dash: [3, 7]),
                    ], dot: line.done.last)
                    .frame(maxHeight: .infinity)
                    HStack { V3Label(b.capital.first.map { $0.note.isEmpty ? "开店" : "开店 · \($0.note)" } ?? "开店"); Spacer(); V3Label(b.paybackDateLabel().map { $0 == "已经回本" ? $0 : "\($0) · 回本" } ?? "回本") }
                        .overlay {
                            // 「今天」写在今天那个点的正下方；太靠两头就不写
                            GeometryReader { g in
                                let x = g.size.width * (line.done.last?.0 ?? 0) / 560
                                if x > 150, x < g.size.width - 150 { V3Label("今天").fixedSize().position(x: x, y: g.size.height / 2) }
                            }
                        }
                }
                .accessibilityLabel("回本走了 \(Int(frac * 100))%")
                if let months, let faster, months > faster {
                    V3Ask(face: "think", text: "每月多赚 150 €，早 \(months - faster) 个月回本。", tone: .good)
                }
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
                    V3Ask(face: "happy", text: fresh ? "记好了，季度末再估一次。" : state.real != nil ? "好，想估的时候再来。" : "好，12 月 28 日再叫你。", tone: .good)
                } else {
                    V3Ask(face: "think", text: estimating ? "货架上的货大约值多少？" : state.real != nil ? (latest == nil ? "还没估过货，现在估一次？" : "隔一阵估一次货，心里有数。") : "12 月底该估货了，现在先估也行。") {
                        if estimating {
                            HStack(spacing: 8) {
                                V3Field(prompt: "大约值多少", text: $text, rounded: true) { save() }.frame(width: 150)
                                Button("就这个数") { save() }.buttonStyle(.v3(.teal, .small))
                            }
                        } else {
                            HStack(spacing: 8) {
                                Button("现在估") { withAnimation(.snappy) { estimating = true } }.buttonStyle(.v3(.teal, .small))
                                Button("到时候再说") { withAnimation(.snappy) { later = true }; state.say(state.real != nil ? "好，想估的时候再来" : "好，12 月 28 日提醒你") }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                    }
                }
                V3KeyCard(label: "店里的货，大约值", amount: value, wave: V3.tealSoft) {
                    V3Label(when)
                }
                V3GrowCard {
                    // 这一块的算式是试用里的示例；正式账本上估过两次以上才算得出来，这一版先不写
                    if state.real == nil {
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
                    }
                    V3CardTitle("每次估的").padding(.top, state.real == nil ? 8 : 0)
                    if b.stockEstimates.isEmpty { V3Label("还没估过").padding(.vertical, 6) }
                    V3RowList(rows: b.stockEstimates.prefix(4).map { .init($0.emoji, $0.name, $0.note, $0.amount.v3) }, fill: true)
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                // 这个月进的货：和流水页是同一份，不另记一本
                let bought = b.purchasesThisMonth
                V3CardTitle("这个月进的货", note: "\(bought.count) 次 · \(bought.map(\.amount).reduce(.zero, +).magnitude.v3Short)")
                V3RowList(rows: bought.prefix(5).map { .init($0.emoji, $0.detail.isEmpty ? $0.title : $0.detail, "\(state.monthKey.month) 月 \($0.day) 日", $0.amount.v3) }, fill: true)
                Spacer(minLength: 0)
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
    @Environment(V3State.self) private var state
    private static let colors: [UInt32] = [0x7FA3F0, 0xF2A65A, 0xC9A0DC, 0xF2B93B]

    var body: some View {
        let b = state.book
        let m = b.shopMonth()
        let split = b.shopPer100
        let ads = b.fixedCosts.first { $0.name == "广告" && !$0.off }
        V3Cols(left: 1.2, right: 1) {
            VStack(spacing: 16) {
                V3KeyCard(label: "\(state.monthLabel) · 真正赚了", amount: m.earned, wave: V3.tealSoft) {
                    HStack(spacing: 26) {
                        V3KV(value: m.income.v3, label: "收了", color: V3.teal)
                        V3KV(value: m.costs.v3, label: "开销", color: V3.red)
                        V3KV(value: m.cashChange.v3, label: "手里实际多了")
                    }
                }
                if !split.isEmpty {
                    V3Card {
                        V3CardTitle("营业额每 100 € 去哪了")
                        GeometryReader { g in
                            HStack(spacing: 0) {
                                ForEach(Array(split.enumerated()), id: \.offset) { i, s in
                                    Rectangle().fill(V3.hex(Self.colors[i % 4])).frame(width: g.size.width * CGFloat(max(s.euros, 0)) / 100)
                                }
                            }
                        }
                        .frame(height: 30).clipShape(Capsule()).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2.5))
                        HStack(spacing: 22) {
                            ForEach(Array(split.enumerated()), id: \.offset) { i, s in
                                VStack(alignment: .leading, spacing: 0) {
                                    V3Amount("\(s.euros) €", color: i == 3 ? V3.gold : V3.ink, size: 17)
                                    HStack(spacing: 4) { Circle().fill(V3.hex(Self.colors[i % 4])).frame(width: 8, height: 8); Text(s.name).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1).fixedSize() }
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        } trailing: {
            VStack(spacing: 16) {
                V3GrowCard(spacing: 6) {
                    V3CardTitle("怎么多赚一点")
                    // 只放从账本里看得出来的：和钱无关的（排班、开门时间）不放
                    if let ads {
                        V3RowList(rows: [.init("📣", "停掉广告试一个月", "每月 \(ads.amount.v3Short)", "+\(ads.amount.v3Short) / 月", V3.green,
                                               action: { state.open(.fixedEdit(ads.name)) })], fill: true)
                    } else {
                        V3Label("这个月没有看得出来能省的。", size: 14)
                    }
                    Spacer(minLength: 0)
                }
                V3Card {
                    V3CardTitle("回本")
                    HStack(spacing: 26) {
                        V3KV(value: "\(Int((b.paybackFraction * 100).rounded()))%", label: "回本走到")
                        V3KV(value: b.paybackLeft.v3Short, label: "还差", color: V3.gold)
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
        // 能一次还清的里面最该先还的那笔（一期一期还的分期、贷款不在这里催）
        let first = owe.first { !$0.off && !TrialBook.paidMonthlyTags.contains($0.tag) }
        // 试用数字里那几块贷款的示例（装修贷款 36 期、本金利息怎么分）在正式账本上不出现
        let demo = state.real == nil
        let monthly = owe.filter { !$0.off && TrialBook.paidMonthlyTags.contains($0.tag) }
        V3Cols(left: 1, right: 1.3) {
            VStack(spacing: 16) {
                V3KeyCard(label: "\(b.thisMonth.next.month) 月店里要还", amount: b.shopDueNext, wave: V3.tealSoft) {
                    HStack(spacing: 26) {
                        V3KV(value: b.shopOwesTotal.v3, label: "店一共欠", color: V3.red)
                        V3KV(value: owed.filter { !$0.off }.map(\.amount).reduce(.zero, +).v3, label: "别人欠店里")
                    }
                }
                if let first {
                    V3Ask(face: "worried", text: "\(first.name)那 \(first.amount.v3Short)\(first.note.isEmpty ? "" : "，" + first.note)。拖了下次不给赊。", tone: .warn, kicker: "要留意") {
                        HStack(spacing: 8) {
                            ForEach(b.shopHeld.prefix(3)) { a in
                                Button("从\(a.name)还") {
                                    state.change("还款记好了 · \(first.name) \(first.amount.v3)，从\(a.name)出", kind: .repay) { try $0.payShopDebt(first.name, from: a.name) }
                                }
                                .buttonStyle(.v3(a.id == b.shopHeld.first?.id ? .teal : .ghost, .small))
                            }
                        }
                    }
                } else {
                    V3Ask(face: "happy", text: "赊的账都清了。", tone: .good)
                }
                if !demo {
                    V3GrowCard {
                        V3CardTitle("每月要还的", note: b.shopLoanMonthly > .zero ? "每月 \(b.shopLoanMonthly.v3Short)" : "")
                        if monthly.isEmpty { V3Label("没有一期一期还的").padding(.vertical, 6) }
                        V3RowList(rows: monthly.prefix(4).map { .init($0.emoji, $0.name, $0.note, $0.amount.v3, V3.red) }, fill: true)
                        Spacer(minLength: 0)
                    }
                } else {
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
            }
        } trailing: {
            V3GrowCard(spacing: 8) {
                V3CardTitle("先还哪个")
                if !demo, first == nil, b.shopOwedAccounts.filter(\.isCreditCard).isEmpty { V3Label("没有要一次还清的").padding(.vertical, 6) }
                V3RowList(rows: owe.filter { demo || !TrialBook.paidMonthlyTags.contains($0.tag) }.prefix(3).map { d in
                    d.off ? .init(d.emoji, d.name, d.note, "0,00 €", V3.green, tag: "还清了", tone: .green)
                          : .init(d.emoji, d.name, d.note, d.amount.v3, V3.red, tag: d.id == first?.id ? "先还这个" : "", tone: .red)
                } + b.shopOwedAccounts.filter(\.isCreditCard).map { c in
                    .init(c.emoji, c.name, c.note, c.balance.v3, V3.red, action: { state.accountFocus = c.name; state.open(.accounts) })
                } + (demo ? [.init("🏦", "装修贷款", moved ? "这一期挪到 1 月 15 日 · 还剩 24 期" : "每月 15 日 · 还剩 24 期", "\(b.shopLoanMonthly.v3) / 月", V3.red, tag: "按月还就行")] : []),
                          compact: owe.count > 2, fill: true)
                if demo {
                    V3Periods(total: 36, done: 12, color: V3.teal, height: 14)
                    V3Label("装修贷款 · 36 期还了 12 期")
                }
                V3CardTitle("别人欠店里的").padding(.top, 6)
                if owed.isEmpty { V3Label("没有").padding(.vertical, 6) }
                V3RowList(rows: owed.prefix(3).map { .init($0.emoji, $0.name, $0.note, $0.amount.v3) }, compact: owed.count > 1, fill: true)
                Spacer(minLength: 0)
                if demo {
                HStack(spacing: 8) {
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
}

// MARK: - 店的家底

/// 店里到底有多少钱：和生活的家底一个样子。最大的数是「店里一共值多少」。
struct V3ShopWealthPage: View {
    @Environment(V3State.self) private var state

    // 和生活的家底一个摆法：上面几个数；中间一排置顶的卡片；下面其余账户的列表。
    var body: some View {
        let b = state.book
        let w = b.shopWorth
        GeometryReader { g in
            let leftW = (g.size.width - 18) * 1.5 / 2.5
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    HStack(spacing: 12) {
                        stat("手里的现金和账户", w.cash.v3, V3.teal)
                        stat("欠着的", w.owes.v3, V3.red)
                        VStack(alignment: .leading, spacing: 2) {
                            V3Label("店里一共值")
                            V3Gold(amount: w.net, size: 40, whole: w.net.cents % 100 == 0)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).v3Sticker()
                        .layoutPriority(1)
                    }
                    .frame(width: leftW)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            V3CardTitle("手里的钱够店撑")
                            V3Amount("\(w.monthsText) 个月", size: 22, weight: .heavy)
                        }
                        V3Bar(fraction: min(w.months / 6, 1), height: 14, color: V3.teal)
                        HStack { V3Label("每月固定要付 \(w.monthlyFixed.v3Short)", size: 12.5); Spacer(); V3Label("6 个月", size: 12.5) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).v3Soft()
                }
                .fixedSize(horizontal: false, vertical: true)
                V3PinnedCards(side: .biz)
                HStack(alignment: .top, spacing: 18) {
                    V3AccountList(side: .biz).frame(width: leftW, alignment: .topLeading)
                    V3Card {
                        V3CardTitle("这些钱在哪")
                        V3RowList(rows: [
                            .init("💶", "手里的现金和账户", "", w.cash.v3, V3.teal),
                            .init("📦", "压在货上的", b.stockEstimates.first.map { "\($0.name)估的" } ?? "还没估过", w.stock.v3, action: { state.go(.stock) }),
                            .init("🧑", "别人欠店的", "", w.owedToShop.v3, action: { state.go(.bizDebts) }),
                            .init("🏦", "店欠别人的", "", (-w.owes).v3, V3.red, action: { state.go(.bizDebts) }),
                        ], compact: true)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            V3Label(label)
            V3Amount(value, color: color, size: 22, weight: .heavy)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).v3Soft()
    }
}

// MARK: - 生意流水

/// 这个月店里的每一笔：每天按渠道收的钱 + 记的每笔开销。一屏放不下就翻页。
struct V3ShopFlowPage: View {
    @Environment(V3State.self) private var state
    @State private var filter = 0
    @State private var page = 0
    private let perPage = 9

    var body: some View {
        let b = state.book
        let now = state.isThisMonth
        let d = state.monthData
        // 过去的月份：正式账本上是那个月一笔笔的流水；试用数字里只有补记的那几笔，别的只有合计
        let all = now ? b.shopFlow : b.shopFlow(in: state.monthKey)
        let rows = all.filter { filter == 0 || (filter == 1 ? $0.amount > .zero : $0.amount < .zero) }
        let pages = max((rows.count + perPage - 1) / perPage, 1)
        let at = min(page, pages - 1)
        let shown = Array(rows.dropFirst(at * perPage).prefix(perPage))
        // 花在哪：按分类加起来，多的在前
        let cats = Dictionary(grouping: all.filter { $0.amount < .zero }, by: { $0.title })
            .map { (name: $0.key, emoji: $0.value.first?.emoji ?? "🧾", total: $0.value.map(\.amount).reduce(.zero, +).magnitude) }
            .sorted { $0.total > $1.total }
        V3Cols(left: 1, right: 1.5) {
            VStack(spacing: 16) {
                let sm = b.shopMonth(state.monthKey)
                V3KeyCard(label: "\(state.monthLabel) · 真正赚了", amount: sm.earned, wave: V3.tealSoft) {
                    HStack(spacing: 26) {
                        V3KV(value: sm.income.v3, label: "收了", color: V3.teal)
                        V3KV(value: sm.costs.v3, label: "开销", color: V3.red)
                        if sm.purchases > .zero { V3KV(value: sm.purchases.v3, label: "进货（卖掉才算开销）") }
                    }
                }
                V3GrowCard {
                    V3CardTitle("花在哪")
                    V3RowList(rows: cats.prefix(5).map { c in .init(c.emoji, c.name, "", c.total.v3) }, compact: true, fill: true)
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            V3GrowCard(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(Array(["全部", "收的", "花的"].enumerated()), id: \.offset) { i, t in
                        Button { filter = i; page = 0 } label: {
                            Text(t).font(V3.font(13.5, .bold)).foregroundStyle(filter == i ? .white : V3.ink)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(filter == i ? V3.teal : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    V3Label("\(rows.count) 笔", size: 12.5)
                }
                // 只有合计、没有逐笔的月份：就写一行说清楚（这句话在核心里，手机一样）
                if let line = b.shopFlowTotalsLine(in: state.monthKey) {
                    V3Label(line, size: 14).padding(.vertical, 10)
                }
                V3RowList(rows: shown.map { r in
                    .init(r.emoji, r.title, "\(state.monthKey.month) 月 \(r.day) 日" + (r.detail.isEmpty ? "" : " · \(r.detail)"),
                          (r.amount > .zero ? "+" : "") + r.amount.v3, r.amount > .zero ? V3.teal : V3.navy,
                          action: { if now, r.entryID == nil { state.open(.shopDay(r.day)) } else if let id = r.entryID { state.open(.amount(id)) } })
                }, compact: true, fill: true)
                Spacer(minLength: 0)
                if pages > 1 {
                    HStack(spacing: 10) {
                        Spacer()
                        Button { page = max(at - 1, 0) } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28).background(Circle().fill(V3.bg)) }
                            .buttonStyle(.plain).disabled(at == 0).accessibilityLabel("上一页")
                        Text("\(at + 1) / \(pages)").font(V3.num(13.5, .heavy)).foregroundStyle(V3.ink2)
                        Button { page = min(at + 1, pages - 1) } label: { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28).background(Circle().fill(V3.bg)) }
                            .buttonStyle(.plain).disabled(at >= pages - 1).accessibilityLabel("下一页")
                    }
                }
            }
        }
    }
}
#endif
