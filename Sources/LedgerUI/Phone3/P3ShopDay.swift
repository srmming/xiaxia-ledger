#if os(iOS)
import FinanceCore
import SwiftUI

// 店里某一天收了多少：按收款的账户分开填（刷卡进店里账户、现金进店里现金……）。
// 改的是那天的总数：从银行导进来的那部分也算在里面，账本只把差的那部分记成「每天记账」。

struct P3ShopDaySheet: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    let day: Int
    @State private var values: [String: String] = [:]
    @FocusState private var focus: String?

    var body: some View {
        let b = state.book
        let held = b.shopHeld.map(\.name)
        let total = held.compactMap { Money(parsing: values[$0] ?? "") }.reduce(Money.zero, +)
        VStack(alignment: .leading, spacing: 14) {
            Text("\(state.monthTitle) \(day) 号收了多少").font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
            Text("按进到哪个账户分开填，没有的空着。填的是那天的总数。").font(P3.font(13, .regular)).foregroundStyle(P3.ink2)
            ForEach(held, id: \.self) { n in
                HStack {
                    Text(n).font(P3.font(15, .bold)).foregroundStyle(P3.ink)
                    Spacer()
                    TextField("0", text: Binding(get: { values[n] ?? "" }, set: { values[n] = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(P3.num(18, .bold)).frame(width: 140)
                        .focused($focus, equals: n)
                    Text("€").font(P3.num(16)).foregroundStyle(P3.ink2)
                }
                .padding(.horizontal, 14).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            }
            HStack {
                P3Label("一共")
                Spacer()
                Text(total.p3).font(P3.num(18, .heavy)).foregroundStyle(P3.teal)
            }
            Spacer(minLength: 0)
            Button("记好这天") { save(held) }
                .buttonStyle(.p3(.teal, .wide))
                .disabled(total <= .zero)
        }
        .padding(16).padding(.top, 12)
        .onAppear {
            guard let d = b.shopDays.first(where: { $0.day == day }) else { return }
            for c in b.channels(of: d) { values[c.account] = Self.plain(c.amount) }
            focus = held.first
        }
        .presentationDetents([.medium, .large])
    }

    private func save(_ held: [String]) {
        let parts = held.compactMap { n -> TrialBook.ShopChannel? in
            guard let m = Money(parsing: values[n] ?? ""), m > .zero else { return nil }
            return TrialBook.ShopChannel(n, m)
        }
        let total = parts.map(\.amount).reduce(Money.zero, +)
        let d = day
        if state.change("记好了 · \(d) 号收了 \(total.p3)", kind: .add, { try $0.recordShopDay(d, channels: parts) }) { dismiss() }
    }

    static func plain(_ m: Money) -> String {
        m.formatted.replacingOccurrences(of: " €", with: "").replacingOccurrences(of: ".", with: "")
    }
}
#endif
