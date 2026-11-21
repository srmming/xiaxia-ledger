import FinanceCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "总览", trends = "趋势", categories = "分类", transactions = "流水", pending = "待确认", importer = "导入"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .trends: "chart.line.uptrend.xyaxis"
        case .categories: "chart.pie"
        case .transactions: "list.bullet.rectangle"
        case .pending: "checkmark.circle.badge.questionmark"
        case .importer: "square.and.arrow.down"
        }
    }
}

struct RootView: View {
    @Environment(LedgerModel.self) private var model
    @State private var section: SidebarItem? = .overview

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                if let error = model.loadError {
                    ContentUnavailableView("账本读不出来", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    switch section ?? .overview {
                    case .overview: OverviewView()
                    default:
                        // 其他页面等设计稿定稿后再做，见 design/。
                        ContentUnavailableView((section ?? .overview).rawValue, systemImage: (section ?? .overview).symbol,
                                               description: Text("这个页面还在设计中。"))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("账本", selection: $model.selectedBookID) {
                        Text("全部").tag(String?.none)
                        ForEach(model.ledger.books) { b in Text(b.name).tag(Optional(b.id)) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

struct OverviewView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        let txs = model.ledger.transactions
        if txs.isEmpty {
            ContentUnavailableView {
                Label("还没有流水", systemImage: "tray")
            } description: {
                Text("把对账单拖进来，或用 fin import 导入。")
            }
        } else {
            let latest = txs.map(\.date).max()!.yearMonth
            let s = Summaries.monthly(txs, month: latest, bookID: model.selectedBookID)
            Form {
                LabeledContent("月份", value: latest.description)
                LabeledContent("收入") { Text(s.income.formatted).monospacedDigit() }
                LabeledContent("支出") { Text(s.expense.formatted).monospacedDigit() }
                LabeledContent("结余") { Text(s.net.formatted).monospacedDigit().bold() }
            }
            .formStyle(.grouped)
        }
    }
}
