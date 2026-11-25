import FinanceCore
import SwiftUI

// 生意那边的另外几页：固定开销、家底（店里的账户和两边之间的钱）、加固定开销、两边转钱。
// 和生活那边同一套组件（KeyFigure、Columns、kitCard、SectionHeader）。规则都在 FinanceCore/BusinessDaily.swift。

// MARK: - 固定开销

struct FixedCostsPage: View {
    @Environment(LedgerModel.self) var model
    @State private var confirmStop: Recurring?

    var body: some View {
        let today = LocalDate.today
        let rules = model.ledger.businessFixedCosts
        let active = rules.filter { !$0.paused }
        let monthly = active.reduce(Money.zero) { $0 + $1.template.amount.magnitude }
        let thisMonth = active.filter { $0.nextDate.yearMonth == today.yearMonth && $0.nextDate > today }
        let left = thisMonth.reduce(Money.zero) { $0 + $1.template.amount.magnitude }
        Columns(sideWidth: 340) {
            VStack(alignment: .leading, spacing: 16) {
                KeyFigure(label: tr("每个月固定要付"), money: monthly,
                          sentence: Text(rules.isEmpty ? tr("房租、工资这些每个月都要付的，加一次就行，到日子自动记上。")
                                         : tr("到日子自动记上，不用手记。首页「真正赚了」已经扣掉了。")))
                if rules.isEmpty {
                    Button { model.sheet = .fixedCost } label: { Label(tr("加第一项（比如房租）"), systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(Color.shop).controlSize(.large)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rules) { r in
                            row(r)
                            if r.id != rules.last?.id { Divider().padding(.leading, 44) }
                        }
                    }
                    // 加一项：放在清单下面、店里的颜色，一眼看得到（ming 2026-11-25：以前太不显眼）。
                    Button { model.sheet = .fixedCost } label: { Label(tr("加一项"), systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(Color.shop).controlSize(.large)
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                        .help(tr("加一项固定开销（⌘⇧N）"))
                }
            }
            .kitCard(padding: 20)
        } side: {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(tr("这个月还没扣的"))
                if thisMonth.isEmpty {
                    Text(rules.isEmpty ? tr("还没有固定开销。") : tr("这个月的都扣完了。"))
                        .font(.callout).foregroundStyle(Color.fg2)
                } else {
                    ForEach(thisMonth) { r in
                        HStack {
                            Text(r.template.description).font(.callout)
                            Text(r.nextDate.short).font(.caption).foregroundStyle(Color.fg2)
                            Spacer()
                            Text(r.template.amount.magnitude.rounded).font(.kitAmount)
                        }
                    }
                    Divider()
                    HStack {
                        Text(tr("一共")).foregroundStyle(Color.fg2)
                        Spacer()
                        Text(left.rounded).font(.kitAmount)
                    }
                    .font(.callout)
                }
            }
            .kitCard()
        }
        .kitPage()
        .confirmationDialog(tr("停掉「\(confirmStop?.template.description ?? "")」？"), isPresented: Binding(get: { confirmStop != nil }, set: { if !$0 { confirmStop = nil } })) {
            Button(tr("停掉"), role: .destructive) {
                if let r = confirmStop { model.perform { try $0.removeRecurring(r.id, author: model.author) } }
                confirmStop = nil
            }
        } message: { Text(tr("以后不再自动记。已经记了的不动，能在改动记录里撤销。")) }
    }

    private func row(_ r: Recurring) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: r.template.category, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.template.description).font(.callout.weight(.medium))
                Text(r.paused ? tr("暂停中") : tr("每月 \(r.start.day) 号 · \(model.accountName(r.template.accountID)) · 下次 \(r.nextDate.short)"))
                    .font(.caption).foregroundStyle(r.paused ? Color.alert : Color.fg2)
            }
            Spacer()
            Text(r.template.amount.magnitude.rounded).font(.kitAmount).foregroundStyle(r.paused ? Color.fg3 : .primary)
            Menu {
                actions(r)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(tr("\(r.template.description) 的操作"))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu { actions(r) }
    }

    @ViewBuilder private func actions(_ r: Recurring) -> some View {
        Button(r.paused ? tr("继续自动记") : tr("先暂停")) {
            var x = r
            x.paused.toggle()
            model.perform { try $0.updateRecurring(x, author: model.author) }
        }
        Divider()
        Button(tr("停掉…"), role: .destructive) { confirmStop = r }
    }
}

/// 加一项固定开销：叫什么、多少、每月几号、从哪个账户付。
struct FixedCostEditor: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var amountText = ""
    @State private var day = 1
    @State private var account = ""
    @State private var category = "店租"
    @State private var error: String?

    // 和店里的分类叫法一样（店租、员工工资），首页、花销页才对得上。
    private static let kinds = ["店租", "员工工资", "水电", "网费", "保险", "会计", "其他"]

    @FocusState private var amountFocused: Bool

    private var amount: Money? { Money.evaluate(amountText).flatMap { $0 > .zero ? $0 : nil } }

    var body: some View {
        // 一行一项，打开就能打金额；回车加上，Esc 取消（ming 2026-11-25 重做）。
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent(tr("每月多少")) {
                        TextField(tr("每月多少"), text: $amountText, prompt: Text("0,00"))
                            .labelsHidden()
                            .font(.title2.weight(.semibold)).monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                            .onSubmit(save)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    Picker(tr("是什么"), selection: $category) {
                        ForEach(Self.kinds, id: \.self) { Text(trKey($0)).tag($0) }
                    }
                    TextField(tr("名字"), text: $name, prompt: Text(tr("比如 店面房租")))
                }
                Section {
                    Picker(tr("每月几号"), selection: $day) {
                        ForEach(1...31, id: \.self) { Text(tr("\($0) 号")).tag($0) }
                    }
                    Picker(tr("从哪个账户付"), selection: $account) {
                        ForEach(choices) { a in Text(a.name).tag(a.id) }
                    }
                } footer: {
                    Text(amount.map { tr("每月 \(day) 号从「\(model.accountName(account))」付 \($0.rounded)，从下一个 \(day) 号开始自动记，记在生意这边。") }
                         ?? tr("从下一个 \(day) 号开始，每月自动记一笔，记在生意这边。"))
                        .font(.caption).foregroundStyle(Color.fg2)
                }
                if let error { Text(error).foregroundStyle(Color.alert) }
            }
            .formStyle(.grouped)
            #if os(macOS)
            Divider()
            HStack {
                Button(tr("取消")) { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                Spacer()
                Button(action: save) { Text(tr("加上")).frame(minWidth: 80) }
                    .buttonStyle(.borderedProminent).tint(Color.shop).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(amount == nil || account.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            #endif
        }
        .navigationTitle(tr("加固定开销"))
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("加上"), action: save).disabled(amount == nil || account.isEmpty)
            }
        }
        #endif
        .onAppear {
            account = model.ledger.dailyAccounts().card ?? choices.first?.id ?? ""
            if name.isEmpty { name = trKey(category) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { amountFocused = true }
        }
        .onChange(of: category) { old, new in
            if name.isEmpty || name == trKey(old) { name = new == "其他" ? "" : trKey(new) }
        }
    }

    private var choices: [Account] {
        let shop = Set(model.ledger.businessAccountIDs)
        let open = model.ledger.accounts.filter { !$0.isPrivate }
        let mine = open.filter { shop.contains($0.id) }
        return mine.isEmpty ? open : mine
    }

    private func save() {
        guard let amount = Money.evaluate(amountText), amount > .zero else { error = tr("金额看不懂"); return }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? trKey(category) : name
        do {
            _ = try model.edit {
                try $0.addFixedCost(name: title, amount: amount, day: day, accountID: account, category: category, author: model.author)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 家底（生意那边）

/// 店里一共多少钱、店里的账户、这个月两边之间来回的钱。生活和生意加起来的总数写在大数字下面。
struct BusinessWealth: View {
    @Environment(LedgerModel.self) var model

    var body: some View {
        let shopIDs = Set(model.ledger.businessAccountIDs)
        let accounts = model.visibleAccounts.filter { shopIDs.contains($0.id) }
        let balances = model.balances
        let shopTotal = accounts.reduce(Money.zero) { $0 + (balances[$1.id] ?? .zero) }
        // 两边加起来的真家底（减掉信用卡、借的、分期），生活那边家底页写的是同一个数。
        let all = model.wealthBreakdown(model.shownMonth, bothSides: true).net
        let moves = model.ledger.sideTransfers(month: model.shownMonth)
        Columns(sideWidth: 360) {
            VStack(alignment: .leading, spacing: 16) {
                KeyFigure(label: tr("店里一共"), money: shopTotal, color: shopTotal.isExpense ? .alert : .primary,
                          sentence: Text(tr("生活和生意加起来的真家底 ")) + em(all.rounded) + Text(tr("（扣掉要还的，加上别人欠你的）。")))
                Divider()
                if accounts.isEmpty {
                    Text(tr("生意这边还没有账户。在这边加的账户就算店里的。"))
                        .font(.callout).foregroundStyle(Color.fg2)
                }
                ForEach(accounts) { a in
                    accountRow(a, balance: balances[a.id] ?? .zero)
                }
                HStack {
                    Button { model.sheet = .accounts } label: { Label(tr("加店里的账户"), systemImage: "plus") }
                        .buttonStyle(.soft)
                    Spacer()
                    Text(tr("右键账户可以挪到生活那边")).font(.caption).foregroundStyle(Color.fg3)
                }
            }
            .kitCard(padding: 20)
        } side: {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: tr("两边之间的钱")) {
                    Button { model.sheet = .sideTransfer } label: { Label(tr("两边转钱"), systemImage: "arrow.left.arrow.right") }
                        .buttonStyle(.soft)
                }
                .padding(.bottom, 4)
                if moves.isEmpty {
                    Text(tr("这个月还没有。从店里拿钱回家、自己垫钱给店里，都在这里记。"))
                        .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(moves) { m in
                    HStack(spacing: 10) {
                        Image(systemName: m.amount.isExpense ? "house.fill" : "storefront.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.shop)
                            .frame(width: 30, height: 30).background(Color.shopSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.amount.isExpense ? tr("拿回家") : tr("垫给店里")).font(.callout.weight(.medium))
                            Text("\(m.date.short) · \(model.accountName(m.accountID))").font(.caption).foregroundStyle(Color.fg2)
                        }
                        Spacer()
                        Text(m.amount.magnitude.rounded).font(.kitAmount)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                Text(tr("两边之间的钱不算收入也不算开销。拿回家的算进「这个月给自己发了」。"))
                    .font(.caption).foregroundStyle(Color.fg2).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .kitCard()
            if let due = model.shopOutlook()?.next, !due.isEmpty {
                NextMonthDueCard(due: due, shop: true, maxRows: 4)
            }
        }
    }

    private func accountRow(_ a: Account, balance: Money) -> some View {
        HStack(spacing: 12) {
            AccountIcon(kind: a.kind, isPrivate: a.isPrivate, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(a.institution ?? a.kind.label).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
            }
            Spacer()
            Text(model.balanceText(a.id)).font(.kitAmount).foregroundStyle(balance.isExpense ? Color.alert : .primary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu { MoveSideButton(account: a) }
        .accessibilityElement(children: .combine)
    }
}

/// 右键菜单里的「挪到另一边」。生活那边的账户列表也用。
struct MoveSideButton: View {
    @Environment(LedgerModel.self) var model
    let account: Account
    var body: some View {
        if model.businessOn {
            let side = model.ledger.side(ofAccount: account.id)
            Button(side == .business ? tr("挪到生活那边") : tr("挪到生意那边")) {
                model.perform { try $0.setAccountSide(account.id, side: side == .business ? .life : .business, author: model.author) }
            }
        }
    }
}

// MARK: - 两边转钱

/// 从店里拿钱回家，或者自己的钱垫给店里。两边各记一笔，不算收入也不算开销。
struct SideTransferSheet: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State private var home = true
    @State private var amountText = ""
    @State private var from = ""
    @State private var to = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var error: String?

    private func accounts(_ side: Side) -> [Account] {
        model.ledger.accounts.filter { !$0.isPrivate && model.ledger.side(ofAccount: $0.id) == side }
    }

    var body: some View {
        let shop = accounts(.business), life = accounts(.life)
        Form {
            Section {
                Picker(tr("哪种"), selection: $home) {
                    Text(tr("从店里拿钱回家")).tag(true)
                    Text(tr("自己的钱垫给店里")).tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextField(tr("多少"), text: $amountText, prompt: Text("500"))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Picker(tr("从"), selection: $from) {
                    ForEach(home ? shop : life) { a in Text(a.name).tag(a.id) }
                }
                Picker(tr("到"), selection: $to) {
                    ForEach(home ? life : shop) { a in Text(a.name).tag(a.id) }
                }
                DatePicker(tr("哪天"), selection: $date, in: ...Date(), displayedComponents: .date)
                TextField(tr("备注"), text: $note, prompt: Text(tr("可以不写")))
            } footer: {
                Text(home ? tr("算进「这个月给自己发了」，不算店里的开销。") : tr("只是钱换了地方，不算店里的收入。"))
            }
            if shop.isEmpty || life.isEmpty {
                Text(shop.isEmpty ? tr("生意这边还没有账户，先到家底页加一个。") : tr("生活这边还没有账户。"))
                    .foregroundStyle(Color.alert)
            }
            if let error { Text(error).foregroundStyle(Color.alert) }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("两边转钱"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("记下"), action: save)
                    .disabled(Money.evaluate(amountText).map { $0 > .zero } != true || from.isEmpty || to.isEmpty)
            }
        }
        .onAppear { pick() }
        .onChange(of: home) { _, _ in pick() }
    }

    private func pick() {
        let shop = accounts(.business), life = accounts(.life)
        let a = home ? shop : life, b = home ? life : shop
        if !a.contains(where: { $0.id == from }) { from = a.first?.id ?? "" }
        if !b.contains(where: { $0.id == to }) { to = b.first?.id ?? "" }
    }

    private func save() {
        guard let amount = Money.evaluate(amountText), amount > .zero else { error = tr("金额看不懂"); return }
        do {
            let change = try model.edit {
                try $0.transferBetweenSides(amount: amount, from: from, to: to, date: LocalDate(date), note: note, author: model.author)
            }
            model.toast = LedgerModel.Toast(text: home ? tr("记好了：拿回家 \(amount.rounded)") : tr("记好了：垫给店里 \(amount.rounded)"), changeID: change.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
