import FinanceCore
import SwiftUI

/// 极简记一笔：花掉 / 进账、金额、常用 8 个分类、账本、账户、日期、备注。3 秒记完。
/// 拆单、分期、借款、导对账单、批量改，都交给 AI。记下的这笔标「你」，写进改动记录，能撤销。
struct QuickAdd: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var income = false
    @State var amountText = ""
    @State var category: String?
    @State var bookID = ""
    @State var accountID = ""
    @State var date = LocalDate.today
    @State var note = ""
    @State var error: String?
    @FocusState var amountFocused: Bool

    private var amount: Money? {
        guard let m = Money(parsing: amountText.replacingOccurrences(of: " ", with: "")), m.cents != 0 else { return nil }
        return m.magnitude
    }

    var body: some View {
        VStack(spacing: 14) {
            Picker("方向", selection: $income) {
                Text("花掉").tag(false)
                Text("进账").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 160)

            amountDisplay

            categoryGrid

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if model.ledger.books.count > 1 {
                        ForEach(model.ledger.books) { b in
                            pill(b.name, on: bookID == b.id) { bookID = b.id }
                        }
                    }
                    Menu {
                        ForEach(model.visibleAccounts) { a in Button(a.name) { accountID = a.id } }
                    } label: { pillLabel(model.accountName(accountID) + " ▾", on: false) }
                        .menuStyle(.button).buttonStyle(.plain).fixedSize()
                    Menu {
                        Button("今天") { date = .today }
                        Button("昨天") { date = LocalDate(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) }
                        Button("前天") { date = LocalDate(Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()) }
                    } label: { pillLabel(date.friendly + " ▾", on: false) }
                        .menuStyle(.button).buttonStyle(.plain).fixedSize()
                }
                .padding(.horizontal, 1)
            }
            TextField("备注（可不填）", text: $note)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            #if os(iOS)
            Keypad(text: $amountText)
            #endif

            Button(action: save) {
                Text("记下").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brand)
            .controlSize(.large)
            .disabled(amount == nil || category == nil)
            .keyboardShortcut(.defaultAction)

            AskAIReader { ask in
                (Text("记下的这笔会标「你」，写进改动记录，能撤销。\n要拆单、记分期、导对账单？") + Text("跟 AI 说更快").foregroundColor(.ai))
                    .font(.caption).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                    .onTapGesture { ask("", page: "记一笔") }
            }
        }
        .padding(20)
        .navigationTitle("记一笔")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        }
        .onAppear(perform: setup)
        .onChange(of: income) { _, _ in category = nil }
        .onChange(of: bookID) { _, _ in if let c = category, !categories.contains(c) { category = nil } }
        .errorAlert($error)
    }

    private var categories: [String] { model.categories(bookID: bookID, income: income, limit: 8) }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            #if os(iOS)
            Text(amountText.isEmpty ? "0" : amountText)
                .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(amountText.isEmpty ? Color.fg3 : (income ? Color.income : .primary))
            #else
            TextField("0", text: $amountText)
                .textFieldStyle(.plain)
                .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(income ? Color.income : .primary)
                .focused($amountFocused)
                .fixedSize()
                .frame(minWidth: 90)
            #endif
            Text("€").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Color.fg3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("金额 \(amount?.spoken ?? "还没填")")
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(categories, id: \.self) { c in
                Button { category = c } label: {
                    VStack(spacing: 4) {
                        CategoryIcon(category: c, size: 30)
                        Text(c).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(category == c ? .primary : Color.fg2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(category == c ? Color.brandSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(category == c ? Color.brand.opacity(0.5) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(category == c ? .isSelected : [])
            }
        }
    }

    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { pillLabel(title, on: on) }.buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pillLabel(_ title: String, on: Bool) -> some View {
        Text(title).font(.subheadline)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? AnyShapeStyle(Color.primary.opacity(0.85)) : AnyShapeStyle(Color.sunken), in: Capsule())
            .contentShape(Capsule())
    }

    private func setup() {
        if bookID.isEmpty { bookID = model.defaultBookID }
        if accountID.isEmpty { accountID = model.defaultAccountID }
        #if os(macOS)
        // 稍等一下再把光标放进金额框：面板刚弹出来时系统还在给它找焦点。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { amountFocused = true }
        #endif
    }

    private func save() {
        guard let amount, let category else { return }
        let text = note.trimmingCharacters(in: .whitespaces)
        let tx = Transaction(date: date, amount: income ? amount : -amount, description: text.isEmpty ? category : text,
                             accountID: accountID, bookID: bookID, category: category, source: "手记")
        do {
            try model.edit { try $0.addTransaction(tx, author: model.author) }
            model.lastAccountID = accountID
            model.lastBookID = bookID
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if os(iOS)
/// iPhone 上的数字键盘：1–9、逗号、0、删除。
struct Keypad: View {
    @Binding var text: String

    var body: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(keys, id: \.self) { k in
                Button { press(k) } label: {
                    Group {
                        if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) }
                    }
                    .font(.title3.weight(.medium))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(k == "⌫" ? "删除" : k == "," ? "小数点" : k)
            }
        }
        .sensoryFeedback(.selection, trigger: text)
    }

    private func press(_ k: String) {
        switch k {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case ",":
            if !text.contains(",") { text += text.isEmpty ? "0," : "," }
        default:
            if let comma = text.firstIndex(of: ","), text.distance(from: comma, to: text.endIndex) > 2 { return }
            if text.count >= 9 { return }
            text = text == "0" ? k : text + k
        }
    }
}
#endif
