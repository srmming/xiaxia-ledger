import Charts
import FinanceCore
import SwiftUI

/// 总览：本月结余、收入支出、近 11 个月走势、各账户余额、钱花在哪。
public struct OverviewView: View {
    @Environment(LedgerModel.self) private var model
    @State private var grown = false

    public init() {}

    public var body: some View {
        Group {
            if model.isLoading {
                ProgressView("正在读账本…")
            } else if model.ledger.transactions.isEmpty {
                ContentUnavailableView {
                    Label("还没有流水", systemImage: "tray")
                } description: {
                    Text("点右上角记一笔，或在 Mac 上用 fin 导入对账单。")
                }
            } else {
                content
            }
        }
        .navigationTitle("总览")
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { grown = true } }
        .onChange(of: model.selectedBookID) {
            grown = false
            withAnimation(.easeOut(duration: 0.7)) { grown = true }
        }
    }

    private var content: some View {
        let month = model.currentMonth
        let s = model.summary(month)
        let series = model.recentMonths(11).map { ($0, model.summary($0).net) }
        let cats = s.byCategory.filter { $0.value.isExpense }.sorted { $0.value < $1.value }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BookPicker()
                card {
                    Text("\(month.label)结余 · \(model.bookName(model.selectedBookID))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    BigAmount(money: grown ? s.net : .zero)
                    HStack(spacing: 16) {
                        Label { AmountText(money: grown ? s.income : .zero) } icon: { Image(systemName: "arrow.up") }
                            .foregroundStyle(Color.income)
                        Label { AmountText(money: grown ? s.expense : .zero, signed: false) } icon: { Image(systemName: "arrow.down") }
                    }
                    .font(.subheadline.weight(.semibold))
                    Chart(series, id: \.0) { m, net in
                        AreaMark(x: .value("月份", m.shortLabel), y: .value("结余", grown ? Double(net.cents) / 100 : 0))
                            .foregroundStyle(.linearGradient(colors: [Color.coral.opacity(0.3), Color.coral.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("月份", m.shortLabel), y: .value("结余", grown ? Double(net.cents) / 100 : 0))
                            .foregroundStyle(Color.coral)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 120)
                    .accessibilityLabel("近 11 个月每月结余走势")
                }
                card {
                    HStack {
                        Text("账户").font(.headline)
                        Spacer()
                        Text("合计 ").foregroundStyle(.secondary) + Text(model.totalBalance.formatted).monospacedDigit().bold()
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 12) {
                        ForEach(model.visibleAccounts) { a in
                            HStack(spacing: 8) {
                                Image(systemName: a.isPrivate ? "lock.fill" : a.kind.symbol)
                                    .frame(width: 28, height: 28)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.name).font(.caption).foregroundStyle(.secondary)
                                    AmountText(money: model.balances[a.id] ?? .zero, signed: false, font: .subheadline.weight(.semibold))
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !cats.isEmpty {
                    card {
                        Text("钱花在哪").font(.headline)
                        Chart(cats.prefix(6), id: \.key) { name, amount in
                            BarMark(x: .value("金额", grown ? Double(amount.magnitude.cents) / 100 : 0), y: .value("分类", name))
                                .foregroundStyle(Color.coral.gradient)
                                .annotation(position: .trailing) {
                                    Text(amount.magnitude.formatted).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(min(cats.count, 6)) * 32)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8, content: c)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension Color {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
