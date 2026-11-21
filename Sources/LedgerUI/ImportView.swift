import FinanceCore
import SwiftUI
import UniformTypeIdentifiers

/// 导入对账单：把文件拖进来 → 自动认出是哪家银行、哪个账户 → 看一眼预览 → 导入 → 顺手整理没分类的。
public struct ImportView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let inSheet: Bool
    @State private var accountID = ""
    @State private var detected: ImportGuess.Detected?
    @State private var dateCol = ""
    @State private var amountCol = ""
    @State private var descCol = ""
    @State private var fileName: String?
    @State private var fileText: String?
    @State private var picking = false
    @State private var dropTargeted = false
    @State private var autoGuess = true
    @State private var error: String?
    @State private var result: Outcome?

    struct Outcome: Equatable { var added: Int; var guessed: Int; var untidy: Int; var account: String }
    struct Preview { var all: [Transaction]; var fresh: [Transaction]; var guessed: Int; var skipped: [String]; var failure: String? }

    public init() { inSheet = false }
    init(inSheet: Bool) { self.inSheet = inSheet }

    /// 读出来的结果和去重后的新流水。
    private var preview: Preview? {
        guard let text = fileText, let detected, !accountID.isEmpty else { return nil }
        let source = fileName ?? "导入"
        let parsed: ImportResult
        do {
            switch detected.format {
            case .revolut: parsed = try Importers.revolutCSV(text, accountID: accountID, source: source)
            case .generic:
                guard !dateCol.isEmpty, !amountCol.isEmpty, !descCol.isEmpty else {
                    return Preview(all: [], fresh: [], guessed: 0, skipped: [], failure: "先在上面选好日期、金额、说明分别是哪一列。")
                }
                var map = Importers.ColumnMap(date: dateCol, amount: amountCol, description: descCol, skipRows: detected.skipRows)
                if amountCol == detected.debit || amountCol == detected.credit, detected.amount == nil {
                    map = Importers.ColumnMap(date: dateCol, debit: detected.debit, credit: detected.credit, description: descCol, skipRows: detected.skipRows)
                }
                parsed = try Importers.genericCSV(text, map: map, accountID: accountID, source: source)
            }
        } catch { return Preview(all: [], fresh: [], guessed: 0, skipped: [], failure: error.localizedDescription) }
        var fresh = Dedup.newTransactions(parsed.transactions, existing: model.ledger.transactions)
        var guessed = 0
        if autoGuess { (fresh, guessed) = model.ledger.applyingGuesses(to: fresh) }
        return Preview(all: parsed.transactions, fresh: fresh, guessed: guessed, skipped: parsed.skipped, failure: nil)
    }

    public var body: some View {
        Group {
            if let result { finished(result) } else { form }
        }
        .navigationTitle("导入对账单")
        .inlineTitle()
        .toolbar {
            if inSheet { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { r in
            switch r {
            case .success(let url): load(url)
            case .failure(let e): error = e.localizedDescription
            }
        }
        .alert("这个文件导不了", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var form: some View {
        let p = preview
        return Form {
            Section {
                dropZone
            } footer: {
                Text("Revolut：app 里「对账单」选 Excel（CSV）。CaixaBank、imagin：网银里导出 Excel，用 Numbers 打开后「导出为 CSV」。PDF 对账单交给 AI，让它用 fin 导入。同一笔导两次不会重复，放心拖。")
            }
            if fileText != nil, let detected {
                Section {
                    LabeledContent("看起来是", value: detected.format == .revolut ? "Revolut 的对账单" : "银行导出的表格")
                    Picker("这是哪个账户的", selection: $accountID) {
                        ForEach(model.visibleAccounts) { a in Label(a.name, systemImage: a.kind.symbol).tag(a.id) }
                    }
                    if detected.format == .generic {
                        columnPicker("日期是哪一列", $dateCol, detected.header)
                        columnPicker("金额是哪一列", $amountCol, detected.header)
                        columnPicker("说明是哪一列", $descCol, detected.header)
                    }
                    Toggle("按以前的习惯先分好类", isOn: $autoGuess)
                } footer: {
                    Text("以前把「Mercadona」分到过「超市 · 个人」，这次同名的就自动这样分。没见过的商户留着，导完一起整理。")
                }
            }
            if let p {
                if let failure = p.failure {
                    Section { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.coral) }
                } else {
                    Section("预览") {
                        LabeledContent("文件里一共", value: "\(p.all.count) 笔")
                        if p.all.count != p.fresh.count {
                            LabeledContent("账本里已经有（跳过）", value: "\(p.all.count - p.fresh.count) 笔")
                        }
                        LabeledContent("这次会导入", value: "\(p.fresh.count) 笔")
                        if p.guessed > 0 { LabeledContent("其中自动分好类", value: "\(p.guessed) 笔") }
                        ForEach(p.fresh.prefix(12)) { t in TransactionRow(tx: t, showDate: true) }
                        if p.fresh.count > 12 { Text("还有 \(p.fresh.count - 12) 笔…").foregroundStyle(.secondary) }
                    }
                    if !p.skipped.isEmpty {
                        Section("没读进来的 \(p.skipped.count) 行") {
                            ForEach(Array(p.skipped.prefix(12).enumerated()), id: \.offset) { _, s in
                                Text(s).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Button { save(p) } label: {
                            Text(p.fresh.isEmpty ? "没有新的可导入" : "导入这 \(p.fresh.count) 笔").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(p.fresh.isEmpty)
                    } footer: { Text("导错了，在「改动记录」里一键撤销整批。") }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if accountID.isEmpty { accountID = model.defaultAccountID } }
    }

    private func columnPicker(_ title: String, _ value: Binding<String>, _ header: [String]) -> some View {
        Picker(title, selection: value) {
            Text("请选").tag("")
            ForEach(header, id: \.self) { h in Text(h).tag(h) }
        }
    }

    private func finished(_ r: Outcome) -> some View {
        ContentUnavailableView {
            Label("导入了 \(r.added) 笔", systemImage: "checkmark.seal.fill")
        } description: {
            Text("进了「\(r.account)」。" + (r.guessed > 0 ? "其中 \(r.guessed) 笔按以前的习惯分好了类。" : "")
                 + (r.untidy > 0 ? "还有 \(r.untidy) 笔没分类或没分账本。" : "都已经分好类了。"))
        } actions: {
            if r.untidy > 0 {
                Button("现在整理这 \(r.untidy) 笔") {
                    result = nil
                    model.sheet = .triage
                }
                .buttonStyle(.borderedProminent)
            }
            Button("再导一个文件") { result = nil }
            if inSheet { Button("完成") { dismiss() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: fileName == nil ? "tray.and.arrow.down" : "doc.text")
                .font(.system(size: 34)).foregroundStyle(Color.coral)
            Text(fileName ?? dropPrompt).font(.headline).multilineTextAlignment(.center)
            Button(fileName == nil ? "选一个文件" : "换一个文件") { picking = true }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(RoundedRectangle(cornerRadius: 14).fill(dropTargeted ? Color.coral.opacity(0.1) : Color.clear))
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

    private var dropPrompt: String {
        #if os(macOS)
        "把对账单文件拖到这里"
        #else
        "选一个对账单文件（CSV）"
        #endif
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        if ["xlsx", "xls", "numbers"].contains(ext) {
            error = "这是 Excel / Numbers 表格。用 Numbers 打开它，选「文件 → 导出为 → CSV」，再把导出的 CSV 拖进来。"; return
        }
        if ext == "pdf" {
            error = "PDF 对账单 app 里读不了。把它交给 AI（Claude、Codex），说「用 fin 把这份对账单导进账本」。"; return
        }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1), !text.isEmpty else {
                error = "这个文件读不出文字，可能不是 CSV。"; return
            }
            let d = ImportGuess.detect(text)
            detected = d
            dateCol = d.date ?? ""
            amountCol = d.amount ?? d.debit ?? d.credit ?? ""
            descCol = d.description ?? ""
            fileText = text
            fileName = url.lastPathComponent
            if let guess = ImportGuess.account(fileName: url.lastPathComponent, text: text, accounts: model.visibleAccounts) {
                accountID = guess
            } else if d.format == .revolut, let r = model.visibleAccounts.first(where: { $0.name.lowercased().contains("revolut") }) {
                accountID = r.id
            }
        } catch { self.error = "打不开这个文件：\(error.localizedDescription)" }
    }

    private func save(_ p: Preview) {
        let name = model.accountName(accountID)
        do {
            var added: [Transaction] = []
            try model.edit { l in
                let r = try l.importTransactions(p.fresh, accountID: accountID, source: fileName ?? "导入", author: model.author)
                added = r.added
                guard let c = r.change else { throw ImportError.empty }
                return c
            }
            model.lastAccountID = accountID
            let untidy = added.filter { $0.flow == nil && ($0.category == nil || $0.bookID == nil) }.count
            withAnimation { result = Outcome(added: added.count, guessed: p.guessed, untidy: untidy, account: name) }
            fileText = nil; fileName = nil; detected = nil
        } catch { self.error = error.localizedDescription }
    }
}
