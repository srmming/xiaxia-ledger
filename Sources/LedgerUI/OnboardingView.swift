import FinanceCore
import SwiftUI

/// 第一次打开：选账户 → 填每个账户现在有多少钱 → 开始用。三步，都能跳过细节。
struct OnboardingView: View {
    struct Draft: Identifiable {
        let id = UUID()
        var name: String
        var kind: AccountKind
        var isPrivate = false
        var on = true
        var balance = ""
    }

    @Environment(LedgerModel.self) private var model
    @State private var step = 0
    @State private var drafts: [Draft] = [
        Draft(name: "CaixaBank", kind: .bank),
        Draft(name: "imagin", kind: .bank),
        Draft(name: "Revolut", kind: .wallet),
        Draft(name: "现金", kind: .cash),
        Draft(name: "私房钱", kind: .cash, isPrivate: true, on: false),
    ]
    @State private var newName = ""
    @State private var error: String?

    private var chosen: [Draft] { drafts.filter(\.on) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if step == 0 { pickAccounts } else { fillBalances }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer.padding(16).frame(maxWidth: 560)
        }
        .background(Color.groupedBackground)
        .errorAlert($error)
        .animation(.snappy, value: step)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sun.max.fill").font(.system(size: 40)).foregroundStyle(Color.coral)
            Text(step == 0 ? "欢迎用夏夏账本" : "现在每个账户里有多少钱？")
                .font(.largeTitle.bold())
            Text(step == 0
                 ? "先告诉我你的钱放在哪几个地方。勾上要用的，之后随时能在「设置」里加、改、删。"
                 : "打开银行 app 看一眼余额填上，这样账本的余额从今天起就和银行对得上。不知道的可以空着，以后再补。")
                .foregroundStyle(.secondary)
            Text("第 \(step + 1) 步，共 2 步").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var pickAccounts: some View {
        Card(spacing: 0) {
            ForEach($drafts) { $d in
                Toggle(isOn: $d.on) {
                    HStack(spacing: 10) {
                        Image(systemName: d.isPrivate ? "lock.fill" : d.kind.symbol)
                            .frame(width: 30, height: 30)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.name)
                            Text(d.isPrivate ? "只有你看得到，平时不显示、不算进总览" : d.kind.label)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
                Divider()
            }
            HStack {
                PromptField("还有别的？写名字，比如「Wise」「店里收银盒」", text: $newName)
                    .onSubmit(addCustom)
                Button("加上", action: addCustom).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 10)
        }
    }

    private var fillBalances: some View {
        Card(spacing: 0) {
            ForEach($drafts) { $d in
                if d.on {
                    HStack(spacing: 10) {
                        Image(systemName: d.isPrivate ? "lock.fill" : d.kind.symbol).frame(width: 26)
                        Text(d.name)
                        Spacer()
                        PromptField("0,00", text: $d.balance)
                            .decimalKeyboard()
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 130)
                        Text("€").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
            }
            Text("信用卡欠着钱就填负数，比如 -320。").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
        }
    }

    private var footer: some View {
        HStack {
            if step == 1 { Button("上一步") { step = 0 } }
            Spacer()
            if step == 0 {
                Button("下一步") { step = 1 }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(chosen.isEmpty)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("开始用", action: finish)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func addCustom() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        drafts.append(Draft(name: name, kind: .bank))
        newName = ""
    }

    private func finish() {
        let list = chosen
        guard !list.isEmpty else { return }
        do {
            try model.edit(quiet: true) { l in
                var last: ChangeRecord?
                for d in list {
                    let account = Account(id: l.newAccountID(for: d.name), name: d.name, kind: d.kind, isPrivate: d.isPrivate)
                    last = try l.createAccount(account, openingBalance: Money(parsing: d.balance), author: model.author)
                }
                guard let last else { throw ManageError.nothingToChange }
                return last
            }
            if list.contains(where: \.isPrivate) { model.showPrivate = true }
            model.section = .overview
        } catch { self.error = error.localizedDescription }
    }
}
