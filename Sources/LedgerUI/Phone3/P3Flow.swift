#if os(iOS)
import FinanceCore
import SwiftUI

// 流水：每天一组，右边是这天的合计。一笔往左滑，露出「改」和「删」。

struct P3FlowPage: View {
    @Environment(P3State.self) private var state
    @State private var query = ""

    private struct Row: Identifiable {
        var id: String
        var emoji: String
        var name: String
        var meta: String
        var amount: Money
        var tag: String
        var entryID: UUID?
        /// 店里按天记的营业额：点了改那天收了多少
        var shopDay: Int?
    }

    private struct Day: Identifiable {
        var id: Int
        var title: String
        var rows: [Row]
        var total: Money { rows.map(\.amount).reduce(.zero, +) }
    }

    private var days: [Day] {
        let b = state.book
        let now = state.isThisMonth
        let monthEntries = now ? b.entries : state.monthData.entries
        let q = query.trimmingCharacters(in: .whitespaces)
        func hit(_ s: String...) -> Bool { q.isEmpty || s.contains { $0.localizedCaseInsensitiveContains(q) } }
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: b.todayDate)
        // 按「离今天几天」分组：过去月份的、生意按几号记的，都先换成离今天几天
        var byDay: [Int: [Row]] = [:]
        if state.side == .biz {
            let k = state.monthKey
            for r in b.shopFlow(in: k) where hit(r.title, r.detail) {
                let d = cal.date(from: DateComponents(year: k.year, month: k.month, day: r.day)) ?? today
                let ago = cal.dateComponents([.day], from: d, to: today).day ?? 0
                byDay[ago, default: []].append(Row(id: r.id, emoji: r.emoji, name: r.title, meta: r.detail, amount: r.amount, tag: "", entryID: r.entryID,
                                                     shopDay: r.entryID == nil && r.amount > .zero && state.isThisMonth ? r.day : nil))
            }
        } else {
            for e in monthEntries where e.side == .life && hit(e.name, e.meta, e.place) {
                byDay[e.daysAgo, default: []].append(Row(id: e.id.uuidString, emoji: e.emoji, name: e.name, meta: e.meta, amount: e.amount, tag: e.tag == "等你看一眼" ? e.tag : "", entryID: now ? e.id : nil))
            }
        }
        return byDay.keys.sorted().map { ago in
            let d = cal.date(byAdding: .day, value: -ago, to: today) ?? today
            let c = cal.dateComponents([.month, .day, .weekday], from: d)
            let label = ago == 0 ? "今天" : ago == 1 ? "昨天" : ago == 2 ? "前天" : "周" + ["日", "一", "二", "三", "四", "五", "六"][((c.weekday ?? 1) - 1) % 7]
            return Day(id: ago, title: "\(label) · \(c.month ?? 0) 月 \(c.day ?? 0) 日", rows: byDay[ago] ?? [])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            P3Header(title: "流水", months: true, sideSwitch: true, meButton: true)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(P3.ink2)
                TextField("找一笔，比如「咖啡」", text: $query).font(P3.font(15, .regular)).submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(P3.ink2) }.accessibilityLabel("清空")
                }
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P3.soft.opacity(0.8)))
            .padding(.horizontal, 16).padding(.bottom, 4)

            let list = days
            if list.isEmpty {
                VStack(spacing: 10) {
                    P3.face("think").resizable().scaledToFit().frame(width: 80).blendMode(.multiply)
                    Text(!state.isThisMonth ? "\(state.monthTitle)还没有记录" : query.isEmpty ? "这个月还没有记录" : "没找到「\(query)」")
                        .font(P3.font(15, .bold)).foregroundStyle(P3.ink2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(list) { d in
                        Section {
                            ForEach(d.rows) { r in
                                row(r)
                            }
                        } header: {
                            HStack {
                                Text(d.title)
                                Spacer()
                                Text(d.total.p3Signed).foregroundStyle(d.total > .zero ? P3.green : P3.ink2)
                            }
                            .font(P3.font(12.5, .semibold)).foregroundStyle(P3.ink2).textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .listSectionSpacing(8)
                .environment(\.defaultMinListRowHeight, 48)
            }
        }
    }

    private func row(_ r: Row) -> some View {
        let biz = state.side == .biz
        return Button {
            if let id = r.entryID { state.sheet = .edit(id) } else if let d = r.shopDay { state.sheet = .shopDay(d) }
        } label: {
            P3Row(emoji: r.emoji, name: r.name, meta: r.meta, amount: r.amount.p3, color: r.amount > .zero ? (biz ? P3.teal : P3.green) : P3.navy,
                  tag: r.tag, tagTone: .gold)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.white)
        .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let id = r.entryID {
                Button(role: .destructive) {
                    state.change("删掉了：\(r.name) \(r.amount.magnitude.p3)", kind: .remove) { _ = try $0.delete(entry: id) }
                } label: { Label("删", systemImage: "trash") }
                .tint(P3.red)
                Button { state.sheet = .edit(id) } label: { Label("改", systemImage: "pencil") }.tint(P3.navy)
            }
        }
    }
}
#endif
