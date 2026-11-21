import FinanceCore
import SwiftUI
import UniformTypeIdentifiers

/// 导入对账单：选文件或拖进来 → 先看预览（哪些是新的、哪些已经有了）→ 确认导入。
public struct ImportView: View {
    enum Format: Hashable { case revolut, generic }

    @Environment(LedgerModel.self) private var model
    @State private var accountID = ""
    @State private var format = Format.revolut
    @State private var dateCol = "日期"
    @State private var amountCol = "金额"
    @State private var descCol = "说明"
    @State private var fileName: String?
    @State private var fileText: String?
    @State private var picking = false
    @State private var dropTargeted = false
    @State private var error: String?
    @State private var done: String?

    public init() {}

    /// 读出来的结果和去重后的新流水。
    private var preview: (all: [Transaction], fresh: [Transaction], skipped: [String])? {
        guard let text = fileText, !accountID.isEmpty else { return nil }
        let source = fileName ?? "导入"
        let result: ImportResult
        do {
            switch format {
            case .revolut: result = try Importers.revolutCSV(text, accountID: accountID, source: source)
            case .generic:
                result = try Importers.genericCSV(text, map: .init(date: dateCol, amount: amountCol, description: descCol),
                                                  accountID: accountID, source: source)
            }
        } catch { return ([], [], [error.localizedDescription]) }
        let fresh = Dedup.newTransactions(result.transactions, existing: model.ledger.transactions)
        return (result.transactions, fresh, result.skipped)
    }

    public var body: some View {
        Form {
            Section {
                Picker("导进哪个账户", selection: $accountID) {
                    ForEach(model.visibleAccounts) { a in Text(a.name).tag(a.id) }
                }
                Picker("文件格式", selection: $format) {
                    Text("Revolut 导出的 CSV").tag(Format.revolut)
                    Text("其他银行的 CSV").tag(Format.generic)
                }
                if format == .generic {
                    TextField("日期是哪一列（列名或第几列）", text: $dateCol)
                    TextField("金额是哪一列", text: $amountCol)
                    TextField("说明是哪一列", text: $descCol)
                }
            } footer: {
                Text("CaixaBank、imagin 可以在网银里导出 Excel，另存为 CSV 再拖进来。PDF 对账单先交给 AI 用 fin 导入。")
            }
            Section {
                dropZone
            }
            if let p = preview {
                Section {
                    LabeledContent("文件里有", value: "\(p.all.count) 笔")
                    LabeledContent("已经记过（会跳过）", value: "\(p.all.count - p.fresh.count) 笔")
                    LabeledContent("新的，会导入", value: "\(p.fresh.count) 笔")
                    ForEach(p.fresh.prefix(30)) { t in TransactionRow(tx: t) }
                    if p.fresh.count > 30 { Text("还有 \(p.fresh.count - 30) 笔…").foregroundStyle(.secondary) }
                } header: { Text("预览") }
                if !p.skipped.isEmpty {
                    Section("没读进来的") {
                        ForEach(Array(p.skipped.prefix(20).enumerated()), id: \.offset) { _, s in
                            Text(s).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("导入这 \(p.fresh.count) 笔") { save(p.fresh) }
                        .disabled(p.fresh.isEmpty)
                } footer: {
                    Text("导入的流水先不分类，之后在「流水」里点「还没分类」整理，或者让 AI 帮你分。导错了可以在「改动记录」里一键撤销。")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("导入对账单")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let e): error = e.localizedDescription
            }
        }
        .onAppear {
            if accountID.isEmpty {
                accountID = model.visibleAccounts.first { $0.id == "revolut" }?.id ?? model.visibleAccounts.first?.id ?? ""
            }
        }
        .alert("导入好了", isPresented: Binding(get: { done != nil }, set: { if !$0 { done = nil } })) {
            Button("好") { done = nil }
        } message: { Text(done ?? "") }
        .errorAlert($error)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(Color.coral)
            Text(fileName ?? "把对账单 CSV 拖到这里").font(.headline)
            Button(fileName == nil ? "选一个文件" : "换一个文件") { picking = true }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(dropTargeted ? Color.coral : Color.secondary.opacity(0.4)))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("把对账单拖到这里，或者选一个文件")
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                error = "这个文件读不出文字，可能不是 CSV。"; return
            }
            fileText = text
            fileName = url.lastPathComponent
            if text.contains("Started Date") || text.contains("Completed Date") { format = .revolut }
        } catch { self.error = error.localizedDescription }
    }

    private func save(_ fresh: [Transaction]) {
        do {
            var added = 0
            try model.edit { l in
                let r = try l.importTransactions(fresh, accountID: accountID, source: fileName ?? "导入", author: model.author)
                added = r.added.count
                guard let c = r.change else { throw ImportError.empty }
                return c
            }
            done = "导入了 \(added) 笔。"
            fileText = nil; fileName = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// 一个账户：余额、开账余额、看这个账户的流水。
struct AccountDetailView: View {
    @Environment(LedgerModel.self) private var model
    let account: Account
    @State private var openingText = ""
    @State private var openingDate = Date()
    @State private var error: String?
    @State private var saved = false

    private var existing: Transaction? {
        model.ledger.transactions.first { $0.accountID == account.id && $0.flow == .opening }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("现在余额") {
                    Text((model.balances[account.id] ?? .zero).formatted).monospacedDigit().bold()
                }
                NavigationLink("看这个账户的每一笔") {
                    TransactionsView(filter: TransactionFilter(accountID: account.id), title: account.name)
                }
            }
            Section {
                TextField("开账那天账户里有多少钱", text: $openingText).decimalKeyboard().monospacedDigit()
                DatePicker("开账日期", selection: $openingDate, displayedComponents: .date)
                Button(saved ? "已保存" : "保存开账余额", action: save)
                    .disabled(Money(parsing: openingText) == nil)
            } header: { Text("开账余额") } footer: {
                Text("从哪天开始用账本记，就填那天银行 app 里显示的余额。这样之后的余额才对得上。不算收入也不算支出。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(account.name)
        .onAppear {
            if let t = existing {
                openingText = t.amount.decimalString.replacingOccurrences(of: ".", with: ",")
                openingDate = t.date.asDate
            }
        }
        .onChange(of: openingText) { saved = false }
        .errorAlert($error)
    }

    private func save() {
        guard let m = Money(parsing: openingText) else { return }
        do {
            try model.edit { try $0.setOpeningBalance(accountID: account.id, amount: m, date: LocalDate(openingDate), author: model.author) }
            saved = true
        } catch { self.error = error.localizedDescription }
    }
}
