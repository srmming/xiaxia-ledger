import FinanceCore
import SwiftUI

/// 改动记录：谁、什么时候、改了什么，能撤销。
public struct HistoryView: View {
    @Environment(LedgerModel.self) private var model
    @State private var error: String?
    @State private var confirming: ChangeRecord?

    public init() {}

    public var body: some View {
        let list = model.ledger.changes.reversed()
        List {
            if list.isEmpty { ContentUnavailableView("还没有改动", systemImage: "clock") }
            ForEach(Array(list)) { c in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.summary).strikethrough(c.undone).foregroundStyle(c.undone ? .secondary : .primary)
                        Text("\(c.author) · \(c.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.undone {
                        Text("已撤销").font(.caption).foregroundStyle(.secondary)
                    } else if c.kind != .delete && (!c.transactionIDs.isEmpty || c.debtID != nil || c.goalID != nil || c.installmentID != nil) {
                        Button("撤销") { confirming = c }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("改动记录")
        .confirmationDialog("撤销这条改动？", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { c in
            Button("撤销", role: .destructive) {
                do { try model.edit { try $0.undo(changeID: c.id, author: model.author) } }
                catch { self.error = error.localizedDescription }
            }
        } message: { c in Text(c.summary) }
        .errorAlert($error)
    }
}

/// 设置：账户（含私房钱）、是否显示私房钱、数据在哪。
public struct SettingsView: View {
    @Environment(LedgerModel.self) private var model
    @State private var adding = false

    public init() {}

    public var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: $model.showPrivate.animation()) {
                    Label("显示私房钱", systemImage: "lock")
                }
            } footer: {
                Text("私房钱账户平时不显示、不算进总览。打开后才看得到。")
            }
            Section {
                ForEach(model.visibleAccounts) { a in
                    NavigationLink { AccountDetailView(account: a) } label: {
                        LabeledContent {
                            Text((model.balances[a.id] ?? .zero).formatted).monospacedDigit()
                        } label: {
                            Label(a.name + (a.isPrivate ? "（私房钱）" : ""), systemImage: a.isPrivate ? "lock.fill" : a.kind.symbol)
                        }
                    }
                }
                Button { adding = true } label: { Label("加一个账户", systemImage: "plus") }
            } header: { Text("账户") } footer: { Text("点一个账户可以填开账余额、看它的每一笔。") }
            Section("账本") {
                ForEach(model.ledger.books) { b in Text(b.name) }
            }
            Section {
                #if os(iOS)
                NavigationLink { ImportView() } label: { Label("导入对账单", systemImage: "tray.and.arrow.down") }
                #endif
                NavigationLink { HistoryView() } label: { Label("改动记录（能撤销）", systemImage: "clock.arrow.circlepath") }
            }
            Section("数据") {
                Text(ledgerLocation(model.store)).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                Button("重新读取") { model.reload() }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .contentMargins(.bottom, 40, for: .scrollContent)
        #endif
        .navigationTitle("设置")
        .sheet(isPresented: $adding) { NavigationStack { AddAccountView() }.sheetSize() }
    }
}

struct AddAccountView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = AccountKind.bank
    @State private var isPrivate = false
    @State private var error: String?

    var body: some View {
        Form {
            TextField("名字，如「Revolut」", text: $name)
            Picker("类型", selection: $kind) {
                ForEach(AccountKind.allCases, id: \.self) { k in Label(k.label, systemImage: k.symbol).tag(k) }
            }
            Toggle("这是私房钱", isOn: $isPrivate)
        }
        .formStyle(.grouped)
        .navigationTitle("加账户")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .errorAlert($error)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var id = trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
        if id.isEmpty || model.ledger.accounts.contains(where: { $0.id == id }) { id = "acct-" + UUID().uuidString.prefix(6).lowercased() }
        let account = Account(id: id, name: trimmed, kind: kind, isPrivate: isPrivate)
        do {
            try model.edit { $0.addAccount(account, author: model.author) }
            if isPrivate { model.showPrivate = true }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
