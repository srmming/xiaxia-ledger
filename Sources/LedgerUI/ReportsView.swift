import Charts
import FinanceCore
import SwiftUI
import UniformTypeIdentifiers

/// 报表：一整年每个月进了多少、花了多少、剩多少；钱都花在哪些分类；个人和店各自怎么样。
public struct ReportsView: View {
    @Environment(LedgerModel.self) private var model
    @State private var year = LocalDate.today.year
    @State private var showIncome = false
    @State private var exporting = false
    @State private var exportDoc: CSVDocument?

    public init() {}

    public var body: some View {
        let months = Reports.months(of: year).filter { $0 <= LocalDate.today.yearMonth }
        let list = model.summaries(months)
        let active = list.filter { $0.income.cents != 0 || $0.expense.cents != 0 }
        let income = list.reduce(Money.zero) { $0 + $1.income }
        let expense = list.reduce(Money.zero) { $0 + $1.expense }
        let net = income + expense
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BookPicker()
                Spacer()
                Picker("年份", selection: $year) {
                    ForEach(model.years, id: \.self) { y in Text(verbatim: "\(y) 年").tag(y) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if active.isEmpty {
                ContentUnavailableView {
                    Label("\(String(year)) 年还没有收支", systemImage: "chart.bar.xaxis")
                } description: { Text("记几笔或导入对账单之后，这里会按月汇总。") }
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                tiles(income: income, expense: expense, net: net, months: active.count)
                betweenBooksNote(list, months: months, net: net)
                chartCard(list)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    monthsCard(list)
                    categoriesCard(list, total: showIncome ? income : expense.magnitude, months: active.count)
                    if model.selectedBookID == nil, model.ledger.books.count > 1 { booksCard(months) }
                }
            }
        }
        .padding(.bottom, 70)
        .pageScroll(maxWidth: 1040)
        .navigationTitle("报表")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { exportDoc = CSVDocument(text: exportText); exporting = true } label: { Label("导出 CSV", systemImage: "square.and.arrow.up") }
                    .help("把这一年的流水导出成表格，给 gestoría 或用 Numbers 打开")
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .commaSeparatedText,
                      defaultFilename: "夏夏账本-\(year)-\(model.bookName(model.selectedBookID))") { result in
            if case .success = result { model.toast = .init(text: "导出好了", changeID: nil) }
        }
    }

    private var exportText: String {
        Reports.csv(model.visibleTransactions.filter { $0.date.year == year }, ledger: model.ledger)
    }

    /// 看单个账本时：这一年和别的账本之间净挪了多少钱（从店里拿回家的 / 老板拿走的）。
    /// 互转没对上时在下面标出来，不悄悄算进去。
    @ViewBuilder private func betweenBooksNote(_ list: [MonthlySummary], months: [YearMonth], net: Money) -> some View {
        let moved = list.reduce(Money.zero) { $0 + $1.betweenBooks }
        if let bookID = model.selectedBookID, moved.cents != 0 {
            let unmatched = Summaries.unmatchedInternal(model.ledger.transactions, months: months,
                                                        hiddenAccounts: model.hiddenAccounts)
            Card(spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label(Reports.betweenBooksLabel(moved, bookID: bookID, books: model.ledger.books), systemImage: "arrow.left.arrow.right")
                        .font(.headline)
                    Spacer()
                    Text(moved.magnitude.formatted).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                }
                Text("自己账户之间挪的钱，不算收入也不算支出。算上它，这一年实际剩 \((net + moved).formatted)。")
                    .font(.footnote).foregroundStyle(.secondary)
                if unmatched.count > 0 {
                    Label("另有 \(unmatched.count) 笔转账只记了一边（共 \(unmatched.total.formatted)），可能也是两个账本之间的，没算进来。", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    private func tiles(income: Money, expense: Money, net: Money, months: Int) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            tile("进账", income.formatted, color: .income)
            tile("花掉", expense.magnitude.formatted, color: .coral)
            tile("剩下", net.formatted, color: net.isExpense ? .coral : .primary)
            tile("平均每月花", Money(cents: expense.magnitude.cents / Int64(max(months, 1))).formatted, color: .primary)
        }
    }

    private func tile(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(color)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }

    private func chartCard(_ list: [MonthlySummary]) -> some View {
        Card {
            CardHeader("每个月进账和花掉")
            Chart {
                ForEach(list, id: \.month) { m in
                    BarMark(x: .value("月份", m.month.shortLabel), y: .value("金额", Double(m.income.cents) / 100), width: .ratio(0.7))
                        .foregroundStyle(by: .value("类型", "进账"))
                        .position(by: .value("类型", "进账"))
                    BarMark(x: .value("月份", m.month.shortLabel), y: .value("金额", Double(m.expense.magnitude.cents) / 100), width: .ratio(0.7))
                        .foregroundStyle(by: .value("类型", "花掉"))
                        .position(by: .value("类型", "花掉"))
                }
                ForEach(list, id: \.month) { m in
                    LineMark(x: .value("月份", m.month.shortLabel), y: .value("金额", Double(m.net.cents) / 100), series: .value("线", "剩下"))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
                        .symbol(.circle)
                        .symbolSize(24)
                }
            }
            .chartForegroundStyleScale(["进账": Color.income, "花掉": Color.coral])
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(OverviewView.compact(v)).font(.caption2) } }
                }
            }
            .frame(height: 220)
            .accessibilityLabel("\(String(year)) 年每个月进账、花掉的柱状图，虚线是每月剩下的")
            Text("虚线是每个月剩下的钱。").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func monthsCard(_ list: [MonthlySummary]) -> some View {
        Card(spacing: 6) {
            CardHeader("按月")
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("月份").gridColumnAlignment(.leading)
                    Text("进账").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("花掉").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("剩下").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(list.reversed(), id: \.month) { m in
                    GridRow {
                        Button(m.month.shortLabel) { model.showTransactions(TransactionFilter(month: m.month)) }
                            .buttonStyle(.borderless)
                        Text(m.income.formatted).foregroundStyle(Color.income)
                        Text(m.expense.magnitude.formatted)
                        Text(m.net.formatted).fontWeight(.semibold).foregroundStyle(m.net.isExpense ? Color.coral : .primary)
                    }
                    .font(.subheadline).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Text("点月份看那个月的每一笔。").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func categoriesCard(_ list: [MonthlySummary], total: Money, months: Int) -> some View {
        let cats = Reports.categoryTotals(list, expense: !showIncome)
        let top = max(cats.first?.amount.cents ?? 1, 1)
        return Card {
            CardHeader(title: showIncome ? "钱从哪来" : "钱花在哪") {
                Picker("看什么", selection: $showIncome.animation(.snappy)) {
                    Text("花掉").tag(false)
                    Text("进账").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if cats.isEmpty { Text("没有。").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(cats, id: \.name) { c in
                Button {
                    model.showTransactions(TransactionFilter(year: year, category: c.name, sign: showIncome ? .income : .expense))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: CategoryStyle.symbol(c.name) ?? "tag").font(.caption)
                                .foregroundStyle(showIncome ? Color.income : Color.coral).frame(width: 18)
                            Text(c.name)
                            Text("\(Int((Double(c.amount.cents) / Double(max(total.cents, 1)) * 100).rounded()))%")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(c.amount.formatted).monospacedDigit()
                                Text("月均 \(Money(cents: c.amount.cents / Int64(max(months, 1))).formatted)")
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .font(.subheadline)
                        Bar(fraction: Double(c.amount.cents) / Double(top), color: c.name == "未分类" ? .gray : showIncome ? .income : .coral)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .hoverHighlight()
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 看「全部」时：个人和店分开各是多少。
    private func booksCard(_ months: [YearMonth]) -> some View {
        Card {
            CardHeader("各个账本")
            ForEach(model.ledger.books) { b in
                let list = model.summaries(months, bookID: b.id)
                let income = list.reduce(Money.zero) { $0 + $1.income }
                let expense = list.reduce(Money.zero) { $0 + $1.expense }
                Button { withAnimation(.snappy) { model.selectedBookID = b.id } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(b.name).fontWeight(.medium)
                            Spacer()
                            Text("剩 \((income + expense).formatted)").monospacedDigit()
                                .foregroundStyle((income + expense).isExpense ? Color.coral : .primary)
                        }
                        Text("进 \(income.formatted) · 花 \(expense.magnitude.formatted)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("账本之间转的钱（比如从店里拿钱回家），单看一个账本时算进去，看「全部」时两边抵消。")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// 导出用的 CSV 文件。
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // 加 BOM，Excel 打开中文不乱码。
        FileWrapper(regularFileWithContents: Data("\u{FEFF}".utf8) + Data(text.utf8))
    }
}
