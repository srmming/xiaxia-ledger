import FinanceCore
import SwiftUI

/// logo 的珊瑚色，只用在重点处。
public extension Color {
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.29)
    static let income = Color(red: 0.12, green: 0.54, blue: 0.36)
}

/// 金额：等宽数字，收入绿色，支出正常色。
struct AmountText: View {
    let money: Money
    var signed = true
    var font: Font = .body

    var body: some View {
        Text(signed ? money.formatted : money.magnitude.formatted)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(money.isIncome && signed ? Color.income : Color.primary)
            .contentTransition(.numericText(value: Double(money.cents)))
            .accessibilityLabel(money.formatted)
    }
}

/// 大数字（总览顶部）：圆体。
struct BigAmount: View {
    let money: Money
    var body: some View {
        Text(money.formatted)
            .font(.system(size: 38, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(money.cents)))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

/// 账本切换：全部 / 个人 / Miora 美甲店。
struct BookPicker: View {
    @Environment(LedgerModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Picker("账本", selection: $model.selectedBookID.animation(.snappy)) {
            Text("全部").tag(String?.none)
            ForEach(model.ledger.books) { b in Text(b.name).tag(Optional(b.id)) }
        }
        .pickerStyle(.segmented)
    }
}

extension AccountKind {
    var symbol: String {
        switch self {
        case .bank: "building.columns"
        case .credit: "creditcard"
        case .cash: "banknote"
        case .wallet: "wallet.bifold"
        case .savings: "dollarsign.bank.building"
        }
    }
    var label: String {
        switch self {
        case .bank: "银行卡"
        case .credit: "信用卡"
        case .cash: "现金"
        case .wallet: "电子钱包"
        case .savings: "储蓄"
        }
    }
}

extension LocalDate {
    /// 「11 月 20 日」
    var short: String { "\(month) 月 \(day) 日" }
    var asDate: Date { Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date() }
    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1)
    }
}

extension YearMonth {
    var label: String { "\(year) 年 \(month) 月" }
    var shortLabel: String { "\(month)月" }
}

/// 出错提示：保存失败等。
struct ErrorBanner: ViewModifier {
    @Binding var error: String?
    func body(content: Content) -> some View {
        content.alert("没保存成功", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
}

extension View {
    func errorAlert(_ error: Binding<String?>) -> some View { modifier(ErrorBanner(error: error)) }

    /// 只在 iOS 上用数字键盘。
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
