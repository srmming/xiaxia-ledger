import FinanceCore
import SwiftUI

/// 目标：离存钱目标还差多少？视觉重心是最快到期（或最接近完成）的目标，一个大进度环。右上角「新目标」自己登记。
/// （ming 2026-11-23：以前叫「计划」、还放着分期和借款；分期、借款搬去「欠款与分期」，这页只放存钱目标。）
struct PlansPage: View {
    @Environment(LedgerModel.self) var model
    /// iPhone 上分三格：目标 / 订阅 / 欠款（Mac 上这三个各是一页）。
    @State private var tab = 0
    /// 页面能看到多大：窗口矮（1000×612）时小卡格子只放一排，一屏放下。
    @State private var viewport = CGSize(width: 1000, height: 800)
    private var short: Bool { Viewport.isShort(viewport) }

    var body: some View {
        #if os(iOS)
        VStack(spacing: Kit.gap) {
            Picker("看哪个", selection: $tab) {
                Text("目标").tag(0)
                Text("订阅").tag(1)
                Text("欠款").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("plansTab")
            switch tab {
            case 1:
                SubscriptionsXiaxia()
                if model.subscriptionStatus.contains(where: { $0.cancelledOn == nil }) { SubscriptionTotalsStrip() }
                SubscriptionsCard()
                AskAICard(title: "让夏夏帮你找订阅", note: nil, page: "订阅",
                          prompts: [AIPrompt(kind: "订阅", text: "帮我从流水里找出所有订阅，问我哪些是，再写进夏夏账本")])
            case 2:
                DebtsPage(embedded: true)
            default:
                plans
            }
        }
        .kitPage()
        .onAppear { if model.section == .debts { tab = 2 } else if model.section == .subscriptions { tab = 1 } }
        #else
        plans.kitPage()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        #endif
    }

    @ViewBuilder private var plans: some View {
        let all = forecasts
        if all.isEmpty {
            VStack(spacing: Kit.gap) {
                VStack(spacing: 12) {
                    KitEmptyState(symbol: "target", title: "还没有存钱目标",
                                  message: "想为什么事存钱？旅行、换电脑、应急金……定个数，这里会告诉你还差多少、照现在的存法哪个月能到、来不来得及。自己登记或者跟夏夏说一句都行。",
                                  prompt: "帮我建一个 2.000 € 的存钱目标，明年 6 月前存够", page: "目标")
                    newPlanButton
                }
                .kitCard()
                AskAICard(title: "想定个存钱目标？", note: nil, page: "目标", prompts: model.prompts(for: .plans))
            }
        } else {
            GoalsBoard(goals: all, short: short)
        }
    }

    /// 这个账本的目标和预测，按钉住 → 拖过的顺序 → 急不急排好。
    private var forecasts: [GoalForecast] {
        let book = model.selectedBookID
        let ids = Set(model.ledger.goals.filter { book == nil || $0.bookID == book }.map(\.id))
        return Plans.sortedGoals(Plans.goalForecasts(model.ledger).filter { ids.contains($0.id) })
    }

    private var newPlanButton: some View {
        Button { model.sheet = .plan } label: { Label("新目标", systemImage: "plus") }
            .buttonStyle(.soft)
            .help("登记一个存钱目标")
    }
}

/// 目标页（ming 2026-11-23）：只回答「我离想要的还差多远、来得及吗？」
/// 最上面夏夏挑最急的目标说一句；下面一个大卡是最急的（或钉住的）目标：进度环、还差多少、照现在的存法哪个月到、要多存多少；
/// 其余的做成小卡格子，一排 3 个（名字、进度环、还差多少），放不下左右翻页，不上下拉；存够了的收进「已完成」。小卡可以拖动排序。
struct GoalsBoard: View {
    @Environment(LedgerModel.self) var model
    let goals: [GoalForecast]
    var short = false
    @State private var page = 0
    @State private var showDone = false

    var body: some View {
        let open = goals.filter { !$0.isDone }
        let done = goals.filter(\.isDone)
        let hero = open.first ?? goals[0]
        let rest = open.filter { $0.id != hero.id }
        VStack(alignment: .leading, spacing: Kit.gap) {
            XiaxiaSays(page: "plans", pageName: "目标", sentence: xiaxiaSentence(open.isEmpty ? goals : open),
                       question: "看看我的存钱目标：照现在的速度来得及吗？最急的是哪个，每月要怎么调整？")
            HStack(alignment: .firstTextBaseline) {
                Text("存钱目标").font(.kitSection).accessibilityAddTraits(.isHeader)
                Text(summaryLine(open: open, done: done)).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
                Spacer(minLength: 8)
                if !done.isEmpty {
                    Button { showDone = true } label: { Label("已完成 \(done.count)", systemImage: "checkmark.seal") }
                        .buttonStyle(.borderless).font(.subheadline)
                        .popover(isPresented: $showDone, arrowEdge: .bottom) { doneList(done) }
                        .accessibilityIdentifier("goalsDone")
                }
                Button { model.sheet = .plan } label: { Label("新目标", systemImage: "plus") }
                    .buttonStyle(.soft)
                    .help("登记一个存钱目标")
            }
            if !open.isEmpty || done.isEmpty {
                GoalHeroCard(goal: hero, compact: short)
            } else {
                allDoneCard(done)
            }
            if !rest.isEmpty { grid(rest) }
        }
    }

    // MARK: 小卡格子

    /// iPhone 窄，一排 2 个；Mac 一排 3 个。
    private var perRow: Int {
        #if os(iOS)
        2
        #else
        3
        #endif
    }
    /// iPhone 上小卡一律用紧凑样式（「还差 2.000 €」一行，不会被挤没）。
    private var compactTiles: Bool {
        #if os(iOS)
        true
        #else
        short
        #endif
    }
    private var rowsPerPage: Int {
        #if os(iOS)
        2
        #else
        short ? 1 : 2
        #endif
    }

    @ViewBuilder private func grid(_ list: [GoalForecast]) -> some View {
        let per = perRow * rowsPerPage
        let pages = max(1, (list.count + per - 1) / per)
        let p = min(page, pages - 1)
        let slice = Array(list.dropFirst(p * per).prefix(per))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("其它目标")
                Spacer()
                if pages > 1 {
                    Button { withAnimation(.snappy) { page = max(0, p - 1) } } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless).disabled(p == 0).accessibilityLabel("上一页目标")
                    Text("\(p + 1) / \(pages)").font(.caption).foregroundStyle(Color.fg2).monospacedDigit()
                    Button { withAnimation(.snappy) { page = min(pages - 1, p + 1) } } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless).disabled(p == pages - 1).accessibilityLabel("下一页目标")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: perRow), spacing: 10) {
                ForEach(slice) { g in
                    GoalTile(goal: g, compact: compactTiles)
                        .draggable(g.id.uuidString) { GoalTile(goal: g).frame(width: 160).environment(model) }
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let id = UUID(uuidString: raw), id != g.id else { return false }
                            move(id, before: g.id)
                            return true
                        }
                }
            }
            .id(p)
            .transition(.push(from: .trailing))
            #if os(iOS)
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
                // iPhone 上左右滑翻页（拖动排序要先长按，不冲突）。Mac 上用右上角的箭头翻。
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                withAnimation(.snappy) { page = v.translation.width < 0 ? min(pages - 1, p + 1) : max(0, p - 1) }
            })
            #endif
            if pages == 1 && list.count > 1 && !short {
                Text("拖动小卡可以调顺序，⋯ 里能把一个钉到最上面。").font(.caption2).foregroundStyle(Color.fg3)
            }
        }
        .kitCard()
    }

    /// 拖动排序：把 id 挪到 target 前面，按现在看到的顺序存下来（大卡那个保持最前）。
    private func move(_ id: UUID, before target: UUID) {
        var order = goals.map(\.id)
        guard let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        let to = order.firstIndex(of: target) ?? order.count
        order.insert(id, at: to)
        model.perform { try $0.reorderGoals(order, author: model.author) }
    }

    private func doneList(_ done: [GoalForecast]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已完成的目标").font(.headline)
            ForEach(done) { g in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                    Text(g.name).font(.callout)
                    Spacer(minLength: 12)
                    Text(g.target.rounded).font(.kitAmount)
                    PlanRowMenu(target: .goal(g.id), name: g.name)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 280)
    }

    private func allDoneCard(_ done: [GoalForecast]) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(Color.income)
            VStack(alignment: .leading, spacing: 4) {
                Text("目标都存够了").font(.title3.weight(.semibold))
                Text("\(done.count) 个目标已经完成，点右上角「已完成」看看。再定一个新的吧。").font(.callout).foregroundStyle(Color.fg2)
            }
            Spacer()
        }
        .kitCard(padding: 20)
    }

    // MARK: 文字

    /// 「3 个在存 · 每月一共存约 450 €」
    private func summaryLine(open: [GoalForecast], done: [GoalForecast]) -> String {
        guard !open.isEmpty else { return "" }
        let pace = open.reduce(Money.zero) { $0 + $1.monthlyPace }
        var parts = ["\(open.count) 个在存"]
        if pace.cents > 0 { parts.append("最近每月一共存约 \(pace.rounded)") }
        let behind = open.filter { $0.pace == .behind }.count
        if behind > 0 { parts.append("\(behind) 个赶不上") }
        return parts.joined(separator: " · ")
    }

    /// 夏夏挑最急的目标说一句（不管钉没钉）。
    private func xiaxiaSentence(_ list: [GoalForecast]) -> String {
        let urgent = Plans.sortedGoals(list.map { var g = $0; g.pinned = false; g.rank = nil; return g })
        guard let g = urgent.first else { return model.voiced("还没有存钱目标，定一个吧。", .neutral) }
        let p = model.persona
        switch g.pace {
        case .done:
            return model.voiced("「\(g.name)」已经存够了。", .good)
        case .behind:
            if let due = g.deadline, due < .today {
                return model.voiced("「\(g.name)」定的 \(due.year) 年 \(due.month) 月已经过了，还差 \(g.left.rounded)。改个日子，或者咬咬牙一次补上？", .bad)
            }
            let late = g.monthsLate.map { "晚 \($0) 个月" } ?? "赶不上"
            let extra = g.extraPerMonth.map { "每月再多存 \($0.rounded) 就能按时到。" } ?? ""
            let s = "「\(g.name)」照现在的存法要\(g.eta.map { "到 \($0.year) 年 \($0.month) 月" } ?? "很久")，比你定的\(late)。" + extra
            return switch p {
            case .sharp: s + "外卖少点两次就有了。"
            case .cheer: s + "差一点点，冲！"
            case .gentle: s + "要不要我帮你看看哪里能省出来？"
            case .calm: s
            }
        case .stalled:
            if let need = g.neededPerMonth, let due = g.deadline {
                return model.voiced("「\(g.name)」最近三个月没往里存。要在 \(due.year) 年 \(due.month) 月前存够，每月得存 \(need.rounded)。", .bad)
            }
            return model.voiced("「\(g.name)」还差 \(g.left.rounded)，最近没在存。定个日子，我帮你算每月存多少。", .neutral)
        case .onTrack:
            let when = g.eta.map { "\($0.year) 年 \($0.month) 月就能存够" } ?? "能存够"
            return model.voiced("「\(g.name)」照现在每月存 \(g.monthlyPace.rounded)，\(when)" + (g.deadline == nil ? "。" : "，赶得上。"), .good)
        }
    }
}

/// 最急（或钉住）的那个目标：大进度环 + 还差多少 + 哪个月能到 + 要多存多少。
struct GoalHeroCard: View {
    @Environment(LedgerModel.self) var model
    let goal: GoalForecast
    /// 窗口矮：环小一点、大数字小一点，好让下面的小卡一屏放下。
    var compact = false

    var body: some View {
        let g = goal
        HStack(alignment: .center, spacing: 22) {
            GoalRing(fraction: Double(g.percent) / 100, color: ringColor(g))
                .frame(width: ringSize, height: ringSize)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if g.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.brand).accessibilityLabel("钉住了") }
                    Text(g.name).font(.headline).lineLimit(1)
                    if g.locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(Color.fg3).accessibilityLabel("锁定的") }
                    PaceTag(goal: g)
                    Spacer()
                    PlanRowMenu(target: .goal(g.id), name: g.name)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(g.left.cents > 0 ? "还差 " : "已存 ").font(.title3.weight(.semibold)).foregroundStyle(Color.fg2)
                        Text(g.left.cents > 0 ? g.left.rounded : g.saved.rounded)
                            .font(.system(size: compact ? 28 : 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("已存 \(g.saved.rounded) / \(g.target.rounded)").font(.callout).foregroundStyle(Color.fg3)
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: 0) {
                        Text((g.left.cents > 0 ? "还差 " : "已存 ") + (g.left.cents > 0 ? g.left.rounded : g.saved.rounded))
                            .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().fixedSize()
                        Text("已存 \(g.saved.rounded) / \(g.target.rounded)").font(.caption).foregroundStyle(Color.fg3)
                    }
                }
                GoalForecastText(goal: g).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .kitCard(padding: compact ? 14 : 18)
        .accessibilityElement(children: .contain)
    }

    private var ringSize: CGFloat {
        #if os(iOS)
        104
        #else
        compact ? 84 : 128
        #endif
    }
}

/// 「照现在每月存 150 €，要到 2027 年 9 月，比你定的晚 3 个月。每月再多存 50 € 就能按时到。」
struct GoalForecastText: View {
    let goal: GoalForecast

    var body: some View { sentence }

    private func ym(_ m: YearMonth) -> String { "\(m.year) 年 \(m.month) 月" }

    /// 一段一段拼，免得编译器算不过来。
    private var sentence: Text {
        let g = goal
        var t: Text
        switch g.pace {
        case .done:
            t = Text("已经存够了 🎉")
        case .behind:
            if let due = g.deadline, due < .today {
                t = Text("定的 \(ym(due.yearMonth)) 已经过了。改个日子，或者一次补上 ")
                t = t + em(g.left.rounded)
                t = t + Text("。")
            } else {
                t = Text("照现在每月存 \(g.monthlyPace.rounded)，要到 ")
                t = t + em(g.eta.map(ym) ?? "很久以后")
                t = t + Text("，比你定的晚 ")
                t = t + em("\(g.monthsLate ?? 0) 个月", .bad)
                t = t + Text("。")
                if let extra = g.extraPerMonth {
                    t = t + Text("每月再多存 ")
                    t = t + em(extra.rounded, .good)
                    t = t + Text(" 就能按时到。")
                }
            }
        case .stalled:
            if let need = g.neededPerMonth, let due = g.deadline {
                t = Text("最近三个月没往里存。要在 \(ym(due.yearMonth)) 前存够，每月得存 ")
                t = t + em(need.rounded)
                t = t + Text("。")
            } else {
                t = Text("最近没在存，也没定日子。定个日子，我帮你算每月存多少。")
            }
        case .onTrack:
            t = Text("照现在每月存 \(g.monthlyPace.rounded)，")
            t = t + em(g.eta.map(ym) ?? "很快")
            if let due = g.deadline {
                t = t + Text(" 就能存够，赶得上 \(ym(due.yearMonth)) 的期限。")
            } else {
                t = t + Text(" 能存够。")
            }
        }
        return t
    }
}

/// 小卡：名字、进度环、还差多少。
struct GoalTile: View {
    @Environment(LedgerModel.self) var model
    let goal: GoalForecast
    /// 窗口矮：环小一点，「晚 3 个月」挪到金额下面，少一行。
    var compact = false

    var body: some View {
        let g = goal
        if compact { compactBody(g) } else { fullBody(g) }
    }

    private func compactBody(_ g: GoalForecast) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text(g.name).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                PlanRowMenu(target: .goal(g.id), name: g.name)
            }
            HStack(spacing: 10) {
                MiniRing(fraction: Double(g.percent) / 100, color: ringColor(g))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.left.cents > 0 ? "还差 \(g.left.rounded)" : "存够了 \(g.target.rounded)")
                        .font(.kitAmount).lineLimit(1).minimumScaleFactor(0.8)
                    Text(tileNote(g)).font(.caption2).foregroundStyle(g.pace == .behind ? Color.alert : Color.fg2).lineLimit(1)
                }
            }
        }
        .padding(10)
        .modifier(TileChrome(label: "\(g.name)，已存 \(g.percent)%，还差 \(g.left.spoken)，\(tileNote(g))"))
    }

    private func fullBody(_ g: GoalForecast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                Text(g.name).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                PlanRowMenu(target: .goal(g.id), name: g.name)
            }
            HStack(spacing: 10) {
                MiniRing(fraction: Double(g.percent) / 100, color: ringColor(g))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.left.cents > 0 ? "还差" : "存够了").font(.caption2).foregroundStyle(Color.fg2)
                    Text(g.left.cents > 0 ? g.left.rounded : g.target.rounded).font(.kitAmount).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Text(tileNote(g)).font(.caption2).foregroundStyle(g.pace == .behind ? Color.alert : Color.fg2).lineLimit(1)
        }
        .padding(12)
        .modifier(TileChrome(label: "\(g.name)，已存 \(g.percent)%，还差 \(g.left.spoken)，\(tileNote(g))"))
    }

    private func tileNote(_ g: GoalForecast) -> String {
        switch g.pace {
        case .done: return "已完成"
        case .behind: return g.monthsLate.map { "晚 \($0) 个月" } ?? "过期了"
        case .stalled: return "最近没在存"
        case .onTrack: return g.eta.map { "\($0.year % 100) 年 \($0.month) 月能到" } ?? "赶得上"
        }
    }
}

/// 小卡里的小进度环（中间写百分比）。
struct MiniRing: View {
    let fraction: Double
    var color: Color
    var body: some View {
        let f = min(max(fraction, 0), 1)
        ZStack {
            Circle().stroke(Color.sunken, lineWidth: 6)
            Circle().trim(from: 0, to: f).stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int((f * 100).rounded()))%").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .accessibilityHidden(true)
    }
}

/// 赶得上是粉色（原来的颜色），赶不上橙色，存够了绿色。
func ringColor(_ g: GoalForecast) -> Color {
    switch g.pace {
    case .done: .income
    case .behind, .stalled: .warn
    case .onTrack: Color.kit(0xF4607A, 0xFF7A90)
    }
}

/// 大卡名字旁边的小标签：「赶得上」「晚 3 个月」「最近没存」。
struct PaceTag: View {
    let goal: GoalForecast
    var body: some View {
        let g = goal
        let text: String
        let fg: Color
        let bg: Color
        switch g.pace {
        case .done: text = "存够了"; fg = .income; bg = .incomeSoft
        case .behind: text = g.monthsLate.map { $0 > 0 ? "晚 \($0) 个月" : "过期了" } ?? "赶不上"; fg = .warn; bg = .warnSoft
        case .stalled: text = "最近没存"; fg = .warn; bg = .warnSoft
        case .onTrack: text = g.deadline == nil ? "没定日子" : "赶得上"; fg = .fg2; bg = .sunken
        }
        return Text(text).font(.caption2.weight(.semibold)).foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(bg, in: Capsule())
    }
}

/// 小卡的底色、圆角和读屏文字（大小两种小卡共用）。
private struct TileChrome: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sunken.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
    }
}
