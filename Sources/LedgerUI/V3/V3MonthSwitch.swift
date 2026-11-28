#if os(macOS)
import SwiftUI
import FinanceCore

/// 共用的月份切换「‹ 11 月 ›」：点两边前后翻一个月，点中间弹出月份来挑。最早到有数据的那个月，不能选还没到的。
/// 总览、花销、趋势、每月小结、生意首页 / 营业额 / 流水都用它，换页以后还是同一个月。
struct V3MonthSwitch: View {
    @Environment(V3State.self) private var state
    @State private var picking = false

    static let pages: Set<V3State.Page> = [.overview, .spending, .trends, .monthly, .bizHome, .sales, .shopFlow]

    var body: some View {
        let b = state.book
        let k = state.monthKey
        let all = b.months
        let tint = state.side == .biz ? V3.teal : V3.navy
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                arrow("chevron.left", "上个月", enabled: k > (all.first ?? k)) { state.setMonth(k.previous) }
                Button { picking = true } label: {
                    Text(state.monthLabel).font(V3.num(14.5, .heavy)).foregroundStyle(V3.ink).lineLimit(1).fixedSize()
                        .padding(.horizontal, 6).frame(height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("挑一个月")
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(92), spacing: 8), count: 3), spacing: 8) {
                        ForEach(all.reversed(), id: \.self) { m in
                            Button { state.setMonth(m); picking = false } label: {
                                Text(m.label(thisYear: b.thisMonth.year)).font(V3.font(13.5, .bold)).foregroundStyle(m == k ? .white : V3.ink)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Capsule().fill(m == k ? tint : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                }
                arrow("chevron.right", "下个月", enabled: k < b.thisMonth) { state.setMonth(k.next) }
            }
            .padding(.horizontal, 3)
            .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
            if !state.isThisMonth {
                Button("回到这个月") { state.setMonth(b.thisMonth) }.buttonStyle(.plain)
                    .font(V3.font(13, .bold)).foregroundStyle(tint).fixedSize()
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("正在看\(state.monthLabel)")
    }

    private func arrow(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(V3.ink).frame(width: 26, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.25).accessibilityLabel(label)
    }
}

/// 过去某个月、这一页又没有那个月的明细时：只摆那个月有的几个数。
struct V3PastMonthPage: View {
    let title: String
    let amount: Money
    var teal = false
    let facts: [(label: String, value: String)]
    var weekly: [Money] = []

    var body: some View {
        V3Cols(left: 1, right: 1.2) {
            VStack(spacing: 16) {
                V3KeyCard(label: title, amount: amount, wave: teal ? V3.tealSoft : V3.soft) {
                    HStack(spacing: 26) { ForEach(Array(facts.enumerated()), id: \.offset) { _, f in V3KV(value: f.value, label: f.label) } }
                }
                Spacer(minLength: 0)
            }
        } trailing: {
            if weekly.isEmpty { Color.clear } else {
                V3GrowCard {
                    V3CardTitle("每周平时花的")
                    let top = max(weekly.map(\.cents).max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 18) {
                        ForEach(Array(weekly.enumerated()), id: \.offset) { i, w in
                            VStack(spacing: 4) {
                                GeometryReader { g in
                                    UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7).fill(V3.navy)
                                        .frame(width: 34, height: max(g.size.height * Double(w.cents) / Double(top), 4))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                }
                                V3Amount(w.v3Short, size: 12.5)
                                V3Label("第 \(i + 1) 周", size: 12)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity).padding(.horizontal, 8)
                }
            }
        }
    }
}
#endif
