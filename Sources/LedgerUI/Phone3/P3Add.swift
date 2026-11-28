#if os(iOS)
import FinanceCore
import SwiftUI

// 记一笔：从底下升上来。先填数，再点分类，再选账户，三下记完。
// 在生活就只记生活那边，在生意就只记店里（账户也只列那一边的）。日子默认今天，可以改。

struct P3AddSheet: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var income = false
    @State private var digits = ""
    @State private var category = ""
    @State private var account = ""
    @State private var name = ""
    @State private var daysAgo = 0
    @State private var pickDate = false
    @State private var date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)) ?? Date()
    @State private var voice = SpeechDictation()
    @State private var started = false
    @FocusState private var writing: Bool

    private var biz: Bool { state.side == .biz }
    private var tint: Color { biz ? P3.teal : P3.navy }
    private var amount: Money { Money(parsing: digits.isEmpty ? "0" : digits) ?? .zero }

    private var categories: [TrialBook.Category] {
        if biz { return income ? [] : TrialBook.shopCategories }
        return income ? TrialBook.incomeCategories : state.book.categories
    }
    private var accounts: [TrialBook.Account] {
        let b = state.book
        if biz { return income ? b.shopHeld : b.accounts(for: .pay, side: .biz) }
        return b.accounts(for: income ? .receive : .pay, side: .life)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(biz ? "记一笔店里的" : "记一笔").font(P3.font(17, .heavy)).foregroundStyle(P3.ink)
                P3Tag(text: biz ? state.book.shopName : "生活", tone: biz ? .teal : .blue)
                Spacer()
            }
            Picker("", selection: $income) {
                Text(biz ? "店里花的" : "花了").tag(false)
                Text(biz ? "收进来的" : "收入").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: income) { _, _ in category = ""; account = "" }

            // 数
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(income ? "+" : "").font(P3.num(30)).foregroundStyle(P3.green)
                Text(digits.isEmpty ? "0" : digits).font(P3.num(40, .heavy)).foregroundStyle(digits.isEmpty ? P3.dash : P3.ink)
                    .contentTransition(.numericText())
                Text("€").font(P3.num(22)).foregroundStyle(P3.ink2)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("金额 \(amount.p3)")

            if !categories.isEmpty { categoryRow }
            pills("从哪" , accounts.map(\.name), selected: $account, prefix: income ? "进到" : "从")
            dateRow

            HStack(spacing: 8) {
                TextField(voice.listening ? "在听，比如说「咖啡三块二」" : biz ? (income ? "备注（可不填）" : "买了什么（可不填），比如「鲜花补货」") : "写一句（可不填），或点麦克风说", text: $name)
                    .font(P3.font(15, .regular))
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                    .focused($writing)
                    .submitLabel(.done)
                P3MicButton(voice: voice, live: { name = $0 }) { said in heard(said) }
                    .background(Circle().fill(.white))
            }
            .onChange(of: voice.error) { _, e in if let e { state.fail(e) } }

            // 写备注时键盘会盖住数字键：先收起数字键，让「记下」留在键盘上面
            if !writing { keypad }
            Button(income ? "记下这笔收入" : "记下") { save() }
                .buttonStyle(.p3(biz ? .teal : .primary, .wide))
                .disabled(amount <= .zero)
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            // 只在第一次出现时定日子：单子重画时不能把「补记 16 号」又改回今天
            guard !started else { return }
            started = true
            date = state.book.todayDate
            if let p = state.addPreset {
                state.addPreset = nil
                income = p.income; daysAgo = p.daysAgo
                date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -p.daysAgo, to: state.book.todayDate) ?? state.book.todayDate
                pickDate = p.daysAgo > 2
            }
            if account.isEmpty { account = accounts.first?.name ?? "" }
        }
        .onChange(of: income) { _, _ in account = accounts.first?.name ?? "" }
        .presentationDetents([.large])
    }

    /// 分类排成两行，一眼看全，不用横着滑去猜。
    private var categoryRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 8) {
            ForEach(categories, id: \.name) { c in
                let on = category == c.name
                Button { category = c.name } label: {
                    VStack(spacing: 3) {
                        P3Icon(emoji: c.emoji, size: 38)
                            .overlay(Circle().strokeBorder(on ? tint : .clear, lineWidth: 3).padding(-4))
                        Text(c.name).font(P3.font(11, on ? .bold : .medium)).foregroundStyle(on ? tint : P3.ink2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func pills(_ label: String, _ items: [String], selected: Binding<String>, prefix: String) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { n in
                    let on = selected.wrappedValue == n
                    Button { selected.wrappedValue = n } label: {
                        Text(n).font(P3.font(13.5, .bold)).foregroundStyle(on ? .white : P3.ink2)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(on ? tint : P3.soft))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(prefix)\(n)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var dateRow: some View {
        let options = [(0, "今天"), (1, "昨天"), (2, "前天")]
        return HStack(spacing: 6) {
            Image(systemName: "calendar").foregroundStyle(P3.ink2).font(.system(size: 14))
            ForEach(options, id: \.0) { o in
                let on = !pickDate && daysAgo == o.0
                Button {
                    pickDate = false; daysAgo = o.0
                    date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -o.0, to: state.book.todayDate) ?? state.book.todayDate
                } label: {
                    Text(o.1).font(P3.font(13, .bold)).foregroundStyle(on ? tint : P3.ink2)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Capsule().strokeBorder(on ? tint : P3.line, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            DatePicker("选日子", selection: $date, in: earliest...state.book.todayDate, displayedComponents: .date)
                .labelsHidden()
                .scaleEffect(0.88, anchor: .trailing)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .onChange(of: date) { _, d in
                    let cal = Calendar(identifier: .gregorian)
                    daysAgo = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: state.book.todayDate)).day ?? 0)
                    // 选到今天、昨天、前天：左边那几个跟着亮；更早的才算「自己挑的日子」
                    pickDate = daysAgo > 2
                }
                .opacity(pickDate ? 1 : 0.55)
        }

    }

    /// 生意那边的营业额只到这个月 1 号；生活往前一年。
    private var earliest: Date {
        let cal = Calendar(identifier: .gregorian)
        let back = biz ? -(state.book.todayDay - 1) : -365
        return cal.date(byAdding: .day, value: back, to: state.book.todayDate) ?? state.book.todayDate
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { k in
                Button { press(k) } label: {
                    Group {
                        if k == "⌫" { Image(systemName: "delete.left").font(.system(size: 19, weight: .semibold)) }
                        else { Text(k).font(P3.num(22, .semibold)) }
                    }
                    .foregroundStyle(P3.ink)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P3.soft.opacity(0.75)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(P3Sink(depth: 1))
                .accessibilityLabel(k == "⌫" ? "删一位" : k == "," ? "小数点" : k)
            }
        }
    }

    /// 说了一句：认出金额和是什么，填进去，等你点「记下」。
    private func heard(_ said: String) {
        guard let q = QuickPhrase.parse(said) else { name = said; return }
        withAnimation(.snappy(duration: 0.2)) {
            digits = q.amount.formatted.replacingOccurrences(of: " €", with: "").replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",00", with: "")
            if let c = categories.first(where: { $0.name == q.name || $0.emoji == q.emoji }) { category = c.name; name = "" } else { name = q.name }
        }
    }

    private func press(_ k: String) {
        withAnimation(.snappy(duration: 0.12)) {
            switch k {
            case "⌫": if !digits.isEmpty { digits.removeLast() }
            case ",": if !digits.contains(",") { digits += digits.isEmpty ? "0," : "," }
            default:
                if let c = digits.firstIndex(of: ","), digits.distance(from: c, to: digits.endIndex) > 2 { return }
                if digits == "0" { digits = k } else if digits.count < 8 { digits += k }
            }
        }
    }

    private func save() {
        let b = state.book
        let when = daysAgo == 0 ? "" : daysAgo == 1 ? " · 昨天" : " · \(daysAgo) 天前"
        let ok: Bool
        if biz {
            if income {
                ok = state.change("记好了 · 收进 \(amount.p3) · \(account)\(when)", kind: .add) { try $0.addShopIncome(amount, account: account, daysAgo: daysAgo) }
            } else {
                let cat = category.isEmpty ? "其他" : category
                ok = state.change("记好了 · \(cat) \(amount.p3) · \(account)\(when)", kind: .add) {
                    try $0.recordShopExpense(name: name, amount: amount, category: cat, account: account, daysAgo: daysAgo)
                }
            }
        } else {
            let list = income ? TrialBook.incomeCategories : b.categories
            let cat = list.first { $0.name == category } ?? (income ? TrialBook.Category("💰", "收入") : TrialBook.Category("❓", "还没分"))
            let title = cat.name
            ok = state.change("记好了 · \(title) \(amount.p3)\(when)", kind: .add) {
                try $0.record(name: title, emoji: cat.emoji, amount: amount, income: income, account: account,
                              place: name.trimmingCharacters(in: .whitespaces), tag: "手机上记的", daysAgo: daysAgo, side: .life)
            }
        }
        if ok { dismiss() }
    }
}

// MARK: - 改一笔

struct P3EditSheet: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var text = ""

    var body: some View {
        if let e = state.book.entries.first(where: { $0.id == entryID }) {
            let cats = e.side == .biz ? TrialBook.shopCategories : e.amount > .zero ? TrialBook.incomeCategories : state.book.categories
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    P3Icon(emoji: e.emoji, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.name).font(P3.font(18, .heavy)).foregroundStyle(P3.ink)
                        Text(e.meta).font(P3.font(13, .regular)).foregroundStyle(P3.ink2)
                    }
                    Spacer()
                    Text(e.amount.p3).font(P3.num(22, .heavy)).foregroundStyle(e.amount > .zero ? P3.green : P3.navy)
                }
                P3Label("金额")
                HStack {
                    TextField("金额", text: $text).keyboardType(.decimalPad).font(P3.num(18))
                        .padding(.horizontal, 12).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                    Button("改") {
                        guard let m = Money(parsing: text), m > .zero else { state.fail("填一个比 0 大的数"); return }
                        let ok = state.change("改好了：\(e.name) \(m.p3)") { try $0.setAmount(entry: e.id, to: m) }
                        if ok { dismiss() }
                    }
                    .buttonStyle(.p3(.primary))
                }
                P3Label("分类")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 10) {
                    ForEach(cats, id: \.name) { c in
                        Button {
                            let ok = state.change("「\(e.name)」改成\(c.name)", kind: .categorize) { try $0.recategorize(entry: e.id, emoji: c.emoji, name: c.name, always: false) }
                            if ok { dismiss() }
                        } label: {
                            VStack(spacing: 3) {
                                P3Icon(emoji: c.emoji, size: 38)
                                Text(c.name).font(P3.font(11, .medium)).foregroundStyle(c.name == e.name ? P3.navy : P3.ink2).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Button("删掉这笔") {
                    let ok = state.change("删掉了：\(e.name) \(e.amount.magnitude.p3)", kind: .remove) { _ = try $0.delete(entry: e.id) }
                    if ok { dismiss() }
                }
                .buttonStyle(.p3(.danger, .wide))
            }
            .padding(16).padding(.top, 22)
            .onAppear { text = e.amount.magnitude.formatted.replacingOccurrences(of: " €", with: "").replacingOccurrences(of: ".", with: "") }
            .presentationDetents([.medium, .large])
        } else {
            Text("这一笔已经不在了").font(P3.font(15, .bold)).foregroundStyle(P3.ink2).presentationDetents([.fraction(0.25)])
        }
    }
}
#endif
