#if os(iOS)
import FinanceCore
import SwiftUI

// 手机上也能动账户：加 / 改 / 删账户，自己账户之间转钱，还一笔欠款。规则都在 FinanceCore（和 Mac 同一套）。

/// 一排可选的小胶囊（账户、种类）。
struct P3Chips: View {
    let items: [String]
    @Binding var selected: String
    var tint: Color = P3.navy
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { n in
                    let on = selected == n
                    Button { selected = n } label: {
                        Text(n).font(P3.font(13.5, .bold)).foregroundStyle(on ? .white : P3.ink2).lineLimit(1).fixedSize()
                            .padding(.horizontal, 14).frame(height: 34).background(Capsule().fill(on ? tint : P3.soft))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - 转钱（自己账户之间；转给欠款就是还款）

struct P3TransferSheet: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var to = ""
    @State private var amount = ""

    var body: some View {
        let b = state.book
        let side = state.side
        let sources = b.transferSources(side).map(\.name)
        let fromSide = b.account(from)?.side ?? side
        let targets = (b.transferTargets(fromSide) + b.crossTargets(from: fromSide)).map(\.name).filter { $0 != from }
        VStack(alignment: .leading, spacing: 14) {
            Text("转钱").font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
            Text("自己账户之间挪钱，不算花也不算收。转给信用卡、分期就是还款。").font(P3.font(13, .regular)).foregroundStyle(P3.ink2)
            P3Label("从")
            P3Chips(items: sources, selected: $from, tint: side == .biz ? P3.teal : P3.navy)
            P3Label("到")
            P3Chips(items: targets, selected: $to, tint: side == .biz ? P3.teal : P3.navy)
            TextField("多少钱", text: $amount).keyboardType(.decimalPad).p3Field()
            if let f = b.account(from), let t = b.account(to), f.side != t.side {
                Text("这笔会从\(f.side == .biz ? "店里" : "生活")转到\(t.side == .biz ? "店里" : "生活")，两边的账都会记下。").font(P3.font(12.5, .regular)).foregroundStyle(P3.gold)
            }
            Spacer(minLength: 0)
            Button("转过去") {
                guard let m = Money(parsing: amount), m > .zero else { state.fail("填一下转多少"); return }
                let f = from, t = to
                if state.change("转好了：\(f) → \(t) \(m.p3Short)", kind: .transfer, { _ = try $0.transferAny(m, from: f, to: t) }) { dismiss() }
            }
            .buttonStyle(.p3(side == .biz ? .teal : .primary, .wide))
            .disabled(from.isEmpty || to.isEmpty)
        }
        .padding(16).padding(.top, 12)
        .onAppear {
            from = sources.first ?? ""
            let fs = b.account(from)?.side ?? side
            to = (b.transferTargets(fs) + b.crossTargets(from: fs)).map(\.name).first { $0 != from } ?? ""
        }
        .onChange(of: from) { _, f in
            let fs = b.account(f)?.side ?? side
            let t = (b.transferTargets(fs) + b.crossTargets(from: fs)).map(\.name).filter { $0 != f }
            if !t.contains(to) { to = t.first ?? "" }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 还一笔欠款

struct P3RepaySheet: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    let debt: String
    @State private var from = ""
    @State private var amount = ""

    var body: some View {
        let b = state.book
        let d = b.account(debt)
        let sources = b.transferSources(d?.side ?? .life).map(\.name)
        VStack(alignment: .leading, spacing: 14) {
            Text("还一笔：\(debt)").font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
            if let d { Text("现在欠 \(d.balance.p3) · \(d.note.replacingOccurrences(of: "欠 · ", with: ""))").font(P3.font(13.5, .regular)).foregroundStyle(P3.ink2) }
            P3Label("从哪出")
            P3Chips(items: sources, selected: $from)
            TextField("还多少", text: $amount).keyboardType(.decimalPad).p3Field()
            if let d { Button("全还清 \(d.balance.p3Short)") { amount = d.balance.formatted.replacingOccurrences(of: " €", with: "").replacingOccurrences(of: ".", with: "") }.buttonStyle(.p3(.ghost, .small)) }
            Spacer(minLength: 0)
            Button("还了") {
                guard let m = Money(parsing: amount), m > .zero else { state.fail("填一下还多少"); return }
                let f = from, n = debt
                if state.change("还好了：\(n) \(m.p3Short)，从\(f)出", kind: .repay, { try $0.repay(debt: n, amount: m, from: f) }) { dismiss() }
            }
            .buttonStyle(.p3(.primary, .wide))
            .disabled(from.isEmpty)
        }
        .padding(16).padding(.top, 12)
        .onAppear { from = sources.first ?? "" }
        .presentationDetents([.medium])
    }
}

// MARK: - 加 / 改账户

struct P3AccountEditor: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    /// nil 是加一个新的。
    let editing: String?
    @State private var name = ""
    @State private var balance = ""
    @State private var kind = "我有的"
    @State private var confirmDelete = false

    private var biz: Bool { state.side == .biz }
    private var kinds: [String] { biz ? ["能用的", "欠着的"] : ["我有的", "我欠的", "别人欠我"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? (biz ? "给店里加一个账户" : "加一个账户") : "改「\(editing ?? "")」").font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
            TextField("名字，比如「工资卡」", text: $name).p3Field()
            TextField(editing == nil ? "现在里面有多少（欠的就填欠多少）" : "现在的余额", text: $balance).keyboardType(.decimalPad).p3Field()
            if editing == nil {
                P3Label("是哪一种")
                P3Chips(items: kinds, selected: $kind, tint: biz ? P3.teal : P3.navy)
            }
            Spacer(minLength: 0)
            Button(editing == nil ? "加上" : "改好了") { save() }.buttonStyle(.p3(biz ? .teal : .primary, .wide))
            if let n = editing {
                Button("删掉这个账户") { confirmDelete = true }.buttonStyle(.p3(.danger, .wide))
                    .confirmationDialog("删掉「\(n)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("删掉", role: .destructive) {
                            if state.change("删掉了账户：\(n)", kind: .account, { try $0.removeAccount(n) }) { dismiss() }
                        }
                    } message: { Text("里面还有流水的账户删不了。删错了点提示条上的「撤销」。") }
            }
        }
        .padding(16).padding(.top, 12)
        .onAppear {
            kind = kinds[0]
            if let n = editing, let a = state.book.account(n) {
                name = a.name
                balance = a.balance.formatted.replacingOccurrences(of: " €", with: "").replacingOccurrences(of: ".", with: "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let m = Money(parsing: balance.isEmpty ? "0" : balance), m >= .zero else { state.fail("余额填一个数"); return }
        let n = name, k = kind, isBiz = biz
        let ok: Bool
        if let old = editing {
            ok = state.change("改好了：\(n) \(m.p3Short)", kind: .account) { try $0.editAccount(old, newName: n, balance: m, secret: false) }
        } else if isBiz {
            ok = state.change("加好了：\(n)", kind: .account) { try $0.addShopAccount(emoji: k == "欠着的" ? "💳" : "🏦", name: n, balance: m, owes: k == "欠着的") }
        } else {
            let kindValue: TrialBook.Account.Kind = k == "我欠的" ? .debt : k == "别人欠我" ? .lent : .own
            let emoji = k == "我欠的" ? "💳" : k == "别人欠我" ? "🤝" : "🏦"
            ok = state.change("加好了：\(n)", kind: .account) { try $0.addAccount(emoji: emoji, name: n, note: k, balance: m, kind: kindValue) }
        }
        if ok { dismiss() }
    }
}

/// 家底页、店的家底页顶上的两个按钮。
struct P3AccountActions: View {
    @Environment(P3State.self) private var state
    var body: some View {
        HStack(spacing: 10) {
            Button("+ 加账户") { state.open(.account(nil)) }.buttonStyle(.p3(.ghost, .small))
            if state.book.canTransfer(on: state.side) {
                Button("转钱") { state.open(.transfer) }.buttonStyle(.p3(.ghost, .small))
            }
            Spacer()
        }
    }
}
#endif
