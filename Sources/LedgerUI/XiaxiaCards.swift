import FinanceCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

// 总览最上面的夏夏卡片：一张说一件事，左右拖动看下一张（Mac 触控板两指左右滑，也可以点两边的箭头或下面的小圆点）。
// 先是 app 自己算的（离目标、留意、快要扣钱、夸一句，见 FinanceCore/Nudges.swift），后面是 AI 写的本月点评。

extension LedgerModel {
    /// 只在看本月时算：说的都是「接下来该做什么」。
    func overviewNudges(_ s: MonthStatus) -> [Nudge] {
        guard s.isCurrent else { return [] }
        let today = LocalDate.today
        let m = today.yearMonth
        let book = selectedBookID
        let expenses = [m, m.previous, m.previous.previous].flatMap { expenseTransactions($0, bookID: book) }
        let subs = subscriptionStatus.filter { book == nil || $0.bookID == nil || $0.bookID == book }
        let installments = Plans.installmentsDue(ledger, today: today, within: 3).filter { book == nil || $0.bookID == book }
        let native = nativeBalances
        return Nudges.overview(expenses: expenses, today: today, currency: ledger.baseCurrency, aim: ledger.profile.aim,
                               projectedEnd: s.projectedEnd, spentSoFar: s.spentSoFar, lastMonthSameDaySpent: s.lastMonthSameDaySpent,
                               subscriptions: subs, installments: installments,
                               accountName: { self.accountName($0) }, balance: { native[$0] })
    }
}

struct XiaxiaCards: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let nudges: [Nudge]
    let insight: Insight?
    @State private var current: String?
    /// 上面那张跟手移动的距离；松手过线就飞出去，下面那张补上来。
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 800
    /// 「知道了」：当天不再显示这一张（第二天情况变了会重新算）。存成「id@日期」一行一个。
    @AppStorage("xiaxia.nudgesDismissed") private var dismissedRaw = ""

    enum Item: Identifiable {
        case nudge(Nudge), insight(Insight)
        var id: String {
            switch self {
            case .nudge(let n): n.id
            case .insight(let i): "insight-\(i.id)"
            }
        }
    }

    var items: [Item] {
        let today = LocalDate.today.description
        let hidden = Set(dismissedRaw.split(separator: "\n").map(String.init))
        var list: [Item] = nudges.filter { !hidden.contains("\($0.id)@\(today)") }.map { .nudge($0) }
        if let insight { list.append(.insight(insight)) }
        return list
    }

    // ming 2026-11-23：像一叠卡——后面露出下一张、再下一张的边；滑一下，上面那张飞走，下面那张补上来。
    // 卡叠的高度跟着最上面那张的内容走，不按最高那张留空白。
    var body: some View {
        let list = items
        let index = min(list.firstIndex { $0.id == current } ?? 0, max(0, list.count - 1))
        let behind = max(0, min(2, list.count - 1 - index))
        let progress = min(1, abs(drag) / max(1, width * 0.5))
        VStack(spacing: 6) {
            if let item = list.indices.contains(index) ? list[index] : nil {
                card(item, number: index + 1, of: list.count)
                    .id(item.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.97, anchor: .bottom).combined(with: .opacity),
                                                                      removal: .opacity))
                    .offset(x: drag)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag / 40).clamped(-6, 6)), anchor: .bottom)
                    .background(alignment: .bottom) {
                        // 后面露出的卡边：越往后越窄、越淡、越往下错开，带一点点旋转。拖上面那张时，后面那张慢慢补到前面的位置。
                        ZStack {
                            ForEach((0..<behind).reversed(), id: \.self) { k in
                                let depth = CGFloat(k + 1) - (k == 0 ? progress : progress * 0.5)
                                peek
                                    .scaleEffect(x: 1 - 0.025 * depth, y: 1, anchor: .bottom)
                                    .offset(y: 7 * depth)
                                    .rotationEffect(.degrees(reduceMotion ? 0 : (k == 0 ? -0.5 : 0.7) * Double(depth)), anchor: .bottom)
                                    .opacity(1 - 0.28 * Double(depth))
                            }
                        }
                    }
                    .padding(.bottom, CGFloat(behind) * 7)
                    .gesture(swipe(list, index))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    .accessibilityAction(named: "下一张") { flip(list, index, by: 1) }
                    .accessibilityAction(named: "上一张") { flip(list, index, by: -1) }
                #if os(macOS)
                    .background(SwipeCatcher { flip(list, index, by: $0) })
                #endif
            }
            if list.count > 1 {
                HStack(spacing: 14) {
                    arrow("chevron.left", label: "上一张", enabled: index > 0) { flip(list, index, by: -1) }
                    HStack(spacing: 7) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                            Button { flip(list, index, by: i - index) } label: {
                                Circle().fill(i == index ? Color.ai : Color.fg3.opacity(0.35))
                                    .frame(width: i == index ? 8 : 6, height: i == index ? 8 : 6)
                                    .frame(width: 14, height: 14).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("第 \(i + 1) 张")
                        }
                    }
                    arrow("chevron.right", label: "下一张", enabled: index < list.count - 1) { flip(list, index, by: 1) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("xiaxiaCards.pager")
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15), value: current)
        .accessibilityIdentifier("xiaxiaCards")
        .onAppear {
            // 截图用：-XiaxiaCard 2 直接停在第 2 张。
            let n = UserDefaults.standard.integer(forKey: "XiaxiaCard")
            if n > 1, list.indices.contains(n - 1) { current = list[n - 1].id }
        }
    }

    /// 后面那几张只画卡的样子（和夏夏卡同样的底色和描边），不画内容。
    private var peek: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous)
        return shape.fill(Color.cardBackground)
            .overlay(shape.fill(Color.aiSoft.opacity(0.6)))
            .overlay(shape.strokeBorder(Color.aiLine, lineWidth: 1))
    }

    private func swipe(_ list: [Item], _ index: Int) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                // 第一张往右、最后一张往左拉不动太远，像拉到头。
                let atEdge = (v.translation.width > 0 && index == 0) || (v.translation.width < 0 && index == list.count - 1)
                drag = atEdge ? v.translation.width / 4 : v.translation.width
            }
            .onEnded { v in
                let dx = v.predictedEndTranslation.width
                if dx < -width * 0.3, index < list.count - 1 { flip(list, index, by: 1) }
                else if dx > width * 0.3, index > 0 { flip(list, index, by: -1) }
                else { withAnimation(.spring(duration: 0.3, bounce: 0.2)) { drag = 0 } }
            }
    }

    /// 翻到前/后几张：往后翻时上面那张往左飞走，往回翻时往右飞走，再换成新的那张（从后面浮上来）。
    private func flip(_ list: [Item], _ index: Int, by step: Int) {
        let target = index + step
        guard step != 0, list.indices.contains(target) else { return }
        if reduceMotion {
            drag = 0
            withAnimation(.easeInOut(duration: 0.2)) { current = list[target].id }
            return
        }
        let out = (step > 0 ? -1 : 1) * (width + 80)
        withAnimation(.easeIn(duration: 0.18)) { drag = out } completion: {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { drag = 0 }
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) { current = list[target].id }
        }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.bold)).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.ai : Color.fg3.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func card(_ item: Item, number: Int, of count: Int) -> some View {
        switch item {
        case .insight(let i): InsightCard(insight: i, bodyLines: 3)
        case .nudge(let n): nudgeCard(n, number: number, of: count)
        }
    }

    private func nudgeCard(_ n: Nudge, number: Int, of count: Int) -> some View {
        AskAIReader { ask in
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label {
                            Text("夏夏 · \(n.label)")
                        } icon: {
                            MascotView(.xiaxia, size: 20, face: true, animated: false)
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ai)
                        Spacer()
                        if count > 1 { Text("\(number)/\(count)").font(.caption).foregroundStyle(Color.fg2).monospacedDigit() }
                    }
                    Text(n.title.keepingAmountsTogether).font(.headline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Text(n.advice.keepingAmountsTogether).font(.subheadline).foregroundStyle(Color.fg2).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { ask(n.question, page: "总览") } label: {
                            Label(n.question, systemImage: "sparkles").lineLimit(1)
                        }
                        .buttonStyle(.softAI)
                        .accessibilityHint("问夏夏这个问题")
                        Button { dismiss(n) } label: { Text("知道了").lineLimit(1).fixedSize() }
                            .buttonStyle(.soft)
                        Spacer(minLength: 8)
                        MoreLink(title: "夏夏建议", section: .insights)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MascotView(.xiaxia, pose: pose(n), size: 80)
                    .accessibilityHidden(true)
            }
            .aiCard()
        }
        .accessibilityElement(children: .contain)
    }

    private func pose(_ n: Nudge) -> MascotPose {
        switch n.kind {
        case .goal: .write
        case .unusual: .think
        case .upcoming: .worried
        case .praise: .celebrate
        }
    }

    private func dismiss(_ n: Nudge) {
        let today = LocalDate.today.description
        // 只留今天的记录，免得越存越长。
        var keep = dismissedRaw.split(separator: "\n").map(String.init).filter { $0.hasSuffix("@\(today)") }
        keep.append("\(n.id)@\(today)")
        withAnimation(.snappy) { dismissedRaw = keep.joined(separator: "\n") }
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(hi, Swift.max(lo, self)) }
}

#if os(macOS)
/// Mac 触控板两指左右滑：滑过一小段就翻一张（一次手势只翻一张），上下滑照常滚页面。
/// 放在卡片背后、不接鼠标点击，只看落在卡片范围里的横向滚动。
struct SwipeCatcher: NSViewRepresentable {
    var onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onSwipe = onSwipe
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.onSwipe = onSwipe }

    static func dismantleNSView(_ v: CatcherView, coordinator: ()) { v.stop() }

    final class CatcherView: NSView {
        var onSwipe: ((Int) -> Void)?
        private var monitor: Any?
        private var sum: CGFloat = 0
        private var fired = false
        private var horizontal = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self else { return e }
                return self.handle(e)
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ e: NSEvent) -> NSEvent? {
            // 只管触控板（有手势阶段的）；普通鼠标滚轮照常。
            guard e.window === window, e.hasPreciseScrollingDeltas else { return e }
            if !e.momentumPhase.isEmpty { return horizontal ? nil : e }
            if e.phase == .began || e.phase == .mayBegin {
                sum = 0; fired = false
                let p = convert(e.locationInWindow, from: nil)
                horizontal = bounds.contains(p) && abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY)
            }
            guard horizontal else { return e }
            sum += e.scrollingDeltaX
            if !fired, abs(sum) > 40 {
                fired = true
                // 手指往左滑（内容往左走）= 看下一张。
                let natural = e.isDirectionInvertedFromDevice
                let toLeft = natural ? sum < 0 : sum > 0
                onSwipe?(toLeft ? 1 : -1)
            }
            if e.phase == .ended || e.phase == .cancelled { sum = 0 }
            return nil
        }
    }
}
#endif
