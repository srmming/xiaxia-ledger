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
            } else if model.ledger.accounts.isEmpty {
                GettingStartedView()
            } else if model.ledger.transactions.isEmpty {
                ContentUnavailableView {
                    Label("还没有流水", systemImage: "tray")
                } description: {
                    Text("点右上角 ＋ 记一笔；在 Mac 上可以到「导入」把对账单拖进来。也可以先到「设置」里给每个账户填开账余额。")
                }
            } else {
                content
            }
        }
        .navigationTitle("总览")
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { grown = true } }
        .onChange(of: model.selectedBookID) { regrow() }
        .onChange(of: model.selectedMonth) { regrow() }
    }

    private func regrow() {
        grown = false
        withAnimation(.easeOut(duration: 0.7)) { grown = true }
    }

    /// 上个月 / 下个月。
    private func step(_ delta: Int) {
        let m = model.shownMonth
        let k = m.year * 12 + (m.month - 1) + delta
        let next = YearMonth(year: k / 12, month: k % 12 + 1)
        guard next <= LocalDate.today.yearMonth else { return }
        model.selectedMonth = next == model.currentMonth ? nil : next
    }

    private var content: some View {
        let month = model.shownMonth
        let s = model.summary(month)
        let unsorted = model.visibleTransactions.filter { $0.flow == nil && ($0.category == nil || $0.bookID == nil) }.count
        let series = model.recentMonths(11).map { ($0, model.summary($0).net) }
        let cats = s.byCategory.filter { $0.value.isExpense }.sorted { $0.value < $1.value }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BookPicker()
                if unsorted > 0 {
                    NavigationLink {
                        TransactionsView(filter: { var f = TransactionFilter(); f.onlyUncategorized = true; return f }(), title: "还没分类")
                    } label: {
                        Label("有 \(unsorted) 笔还没分类或没分账本，点这里整理", systemImage: "tray.full")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                card {
                    HStack {
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless).accessibilityLabel("上个月")
                        Text("\(month.label)结余 · \(model.bookName(model.selectedBookID))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless).accessibilityLabel("下个月")
                            .disabled(month >= LocalDate.today.yearMonth)
                        Spacer()
                        if let rate = Plans.savingsRate(s), s.income.cents > 0 {
                            Text("存下 \(rate)%").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
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
                            NavigationLink {
                                TransactionsView(filter: TransactionFilter(accountID: a.id), title: a.name)
                            } label: {
                            HStack(spacing: 8) {
                                Image(systemName: a.isPrivate ? "lock.fill" : a.kind.symbol)
                                    .frame(width: 28, height: 28)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.name).font(.caption).foregroundStyle(.secondary)
                                    Text((model.balances[a.id] ?? .zero).formatted)
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle((model.balances[a.id] ?? .zero).isExpense ? Color.coral : .primary)
                                }
                            }
                            .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !cats.isEmpty {
                    card {
                        HStack {
                            Text("钱花在哪").font(.headline)
                            Spacer()
                            Text("点一项看每一笔").font(.caption).foregroundStyle(.secondary)
                        }
                        let top = cats.first?.value.magnitude.cents ?? 1
                        ForEach(cats, id: \.key) { name, amount in
                            NavigationLink {
                                TransactionsView(filter: TransactionFilter(month: month, category: name), title: name)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(name)
                                        Spacer()
                                        Text(amount.magnitude.formatted).monospacedDigit().foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                    GeometryReader { geo in
                                        Capsule().fill(Color.coral.gradient)
                                            .frame(width: grown ? max(4, geo.size.width * CGFloat(amount.magnitude.cents) / CGFloat(max(top, 1))) : 4)
                                    }
                                    .frame(height: 6)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, 60)   // iPhone 底部标签栏会盖住最后几行
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

/// 第一次打开：一键加常用账户。
struct GettingStartedView: View {
    @Environment(LedgerModel.self) private var model
    @State private var error: String?

    static let presets: [Account] = [
        Account(id: "caixa", name: "CaixaBank", kind: .bank, institution: "CaixaBank"),
        Account(id: "imagin", name: "imagin", kind: .bank, institution: "imagin"),
        Account(id: "revolut", name: "Revolut", kind: .wallet, institution: "Revolut"),
        Account(id: "cash", name: "现金", kind: .cash),
    ]

    var body: some View {
        ContentUnavailableView {
            Label("欢迎用夏夏账本", systemImage: "sparkles")
        } description: {
            Text("先加上你常用的账户：CaixaBank、imagin、Revolut 和现金。之后可以在「设置」里改名、加私房钱、填开账余额。")
        } actions: {
            Button("一键加上这 4 个账户") {
                do {
                    try model.edit { l in
                        var last: ChangeRecord?
                        for a in Self.presets where !l.accounts.contains(where: { $0.id == a.id }) {
                            last = l.addAccount(a, author: model.author)
                        }
                        return last ?? l.addAccount(Account(id: "cash2", name: "现金", kind: .cash), author: model.author)
                    }
                } catch { self.error = error.localizedDescription }
            }
            .buttonStyle(.borderedProminent)
        }
        .errorAlert($error)
    }
}
