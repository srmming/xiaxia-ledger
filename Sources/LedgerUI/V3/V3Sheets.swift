#if os(macOS)
import FinanceCore
import SwiftUI

// 弹出来填的小窗（规格稿「补的弹窗」）：自己填一笔、存一笔、改分类、改金额、还款、欠款、订阅，
// 和生意那边的：记今天的账、固定开销、进货、盘货、本钱、两边转钱、店里欠款。
// 规则都在核心（FinanceCore/TrialBook.swift）里，这里只管收字、预览、把没做成的原因说出来。

enum V3Sheet: Equatable {
    case manual, save, category(UUID), amount(UUID), subscription, debt, repay(String)
    case shopDay(Int), fixed, purchase, stock, capital, transfer, shopDebt
    // 设置里的
    case memoAdd, memoForget(UUID), deleteAsk, deleteConfirm, restore(UUID), feedback, books, accounts, categories, baseCurrency, goalNew, capitalTotal, memoTidy, memoMeet, monthlyPlan, subscriptionInfo(String), fixedEdit(String), apiKey, smallGoal(UUID?), holdBack, shopAccount

    /// 启动参数 `-XiaxiaV3Page sheet-xxx`：截图和检查用。
    @MainActor static func fromLaunch(_ p: String, _ state: V3State) {
        let map: [String: (V3State.Page, V3State.Side, V3Sheet)] = [
            "sheet-manual": (.overview, .life, .manual), "sheet-save": (.goals, .life, .save),
            "sheet-sub": (.subscriptions, .life, .subscription), "sheet-debt": (.debts, .life, .debt),
            "sheet-repay": (.debts, .life, .repay("信用卡")),
            "sheet-plan": (.goals, .life, .monthlyPlan), "sheet-subinfo": (.subscriptions, .life, .subscriptionInfo("云盘 Plus")),
            "sheet-fixededit": (.fixed, .biz, .fixedEdit("广告")), "sheet-holdback": (.overview, .life, .holdBack), "sheet-smallgoal": (.goals, .life, .smallGoal(nil)),
            "sheet-daily": (.bizHome, .biz, .shopDay(18)), "sheet-fixed": (.fixed, .biz, .fixed),
            "sheet-purchase": (.stock, .biz, .purchase), "sheet-stock": (.stock, .biz, .stock),
            "sheet-capital": (.payback, .biz, .capital), "sheet-transfer": (.bizHome, .biz, .transfer),
            "sheet-shopdebt": (.bizDebts, .biz, .shopDebt), "sheet-captotal": (.payback, .biz, .capitalTotal),
        ]
        if let (page, side, sheet) = map[p] { state.side = side; state.page = page; state.sheet = sheet }
        let set: [String: (V3State.SettingsSub?, V3Sheet)] = [
            "sheet-memo": (.memory, .memoAdd), "sheet-del1": (.data, .deleteAsk), "sheet-del2": (.data, .deleteConfirm),
            "sheet-feedback": (nil, .feedback), "sheet-books": (.books, .books), "sheet-accounts": (.books, .accounts),
            "sheet-cats": (.books, .categories), "sheet-base": (.sync, .baseCurrency), "sheet-tidy": (.memory, .memoTidy), "sheet-meet": (.memory, .memoMeet),
        ]
        if let (sub, sheet) = set[p] { state.page = .settings; state.settingsSub = sub; state.sheet = sheet }
        if p == "sheet-forget", let m = state.book.memos.last { state.page = .settings; state.settingsSub = .memory; state.sheet = .memoForget(m.id) }
        if p == "sheet-restore", let b = state.backups.first { state.page = .settings; state.settingsSub = .data; state.sheet = .restore(b.id) }
        if p == "sheet-cat" || p == "sheet-amount", let e = state.book.entries.first(where: { $0.place == "Super Lumi" }) {
            state.page = .transactions
            state.sheet = p == "sheet-cat" ? .category(e.id) : .amount(e.id)
        }
    }
}

extension V3State {
    func open(_ s: V3Sheet) { withAnimation(.snappy(duration: 0.2)) { sheet = s } }
    func closeSheet() { withAnimation(.snappy(duration: 0.2)) { sheet = nil } }
}

struct V3SheetHost: View {
    let sheet: V3Sheet
    @Environment(V3State.self) private var state

    var body: some View {
        ZStack {
            V3.ink.opacity(0.42).onTapGesture { state.closeSheet() }.accessibilityHidden(true)
            Group {
                switch sheet {
                case .manual: V3ManualSheet()
                case .save: V3SaveSheet()
                case .category(let id): V3CategorySheet(id: id)
                case .amount(let id): V3AmountSheet(id: id)
                case .subscription: V3SubscriptionSheet()
                case .debt: V3DebtSheet()
                case .repay(let name): V3RepaySheet(debt: name)
                case .shopDay(let d): V3ShopDaySheet(start: d)
                case .fixed: V3FixedSheet()
                case .purchase: V3SimpleSheet(kind: .purchase)
                case .stock: V3SimpleSheet(kind: .stock)
                case .capital: V3SimpleSheet(kind: .capital)
                case .transfer: V3TransferSheet()
                case .shopDebt: V3ShopDebtSheet()
                case .memoAdd: V3MemoAddSheet()
                case .memoForget(let id): V3MemoForgetSheet(id: id)
                case .deleteAsk: V3DeleteAskSheet()
                case .deleteConfirm: V3DeleteConfirmSheet()
                case .restore(let id): V3RestoreSheet(id: id)
                case .feedback: V3FeedbackSheet()
                case .books: V3BooksSheet()
                case .accounts: V3AccountsSheet()
                case .categories: V3CategoriesSheet()
                case .baseCurrency: V3BaseCurrencySheet()
                case .goalNew: V3GoalNewSheet()
                case .capitalTotal: V3CapitalTotalSheet()
                case .memoTidy: V3MemoTidySheet()
                case .memoMeet: V3MemoMeetSheet()
                case .monthlyPlan: V3MonthlyPlanSheet()
                case .subscriptionInfo(let n): V3SubscriptionInfoSheet(name: n)
                case .fixedEdit(let n): V3FixedEditSheet(name: n)
                case .apiKey: V3APIKeySheet()
                case .smallGoal(let id): V3SmallGoalSheet(id: id)
                case .holdBack: V3HoldBackSheet()
                case .shopAccount: V3ShopAccountSheet()
                }
            }
            .accessibilityAddTraits(.isModal)
        }
    }
}

// MARK: - 搭弹窗用的几块

/// 弹窗的壳：标题、内容、底下一行（左边一句话，右边 取消 + 主按钮）。
struct V3SheetBox<Content: View, Extra: View>: View {
    var width: CGFloat = 540
    let title: String
    var sub = ""
    var foot = ""
    /// 不占地方的说明：鼠标移到主按钮上才出来。
    var hint = ""
    var primary = "记好"
    var teal = false
    var danger = false
    var canSave = true
    /// 底部只留一个主按钮（没有「取消」）。
    var single = false
    var save: () -> Void
    @ViewBuilder var extra: Extra
    @ViewBuilder var content: Content
    @Environment(V3State.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(V3.font(22, .heavy))
                if !sub.isEmpty { V3Label(sub) }
                Spacer()
                Button { state.closeSheet() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("关掉")
            }
            content
            HStack(spacing: 10) {
                if !foot.isEmpty { V3Label(foot, size: 13).lineLimit(2) }
                Spacer(minLength: 8)
                if !single { Button("取消") { state.closeSheet() }.buttonStyle(.v3(.ghost)) }
                extra
                Button(primary, action: save).buttonStyle(.v3(danger ? .danger : teal ? .teal : .primary)).disabled(!canSave).keyboardShortcut(.defaultAction).help(hint)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .frame(width: width)
        .v3Sticker(radius: 26, depth: 6)
        .foregroundStyle(V3.ink)
    }
}

extension V3SheetBox where Extra == EmptyView {
    init(width: CGFloat = 540, title: String, sub: String = "", foot: String = "", hint: String = "", primary: String = "记好", teal: Bool = false, danger: Bool = false,
         canSave: Bool = true, single: Bool = false, save: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.init(width: width, title: title, sub: sub, foot: foot, hint: hint, primary: primary, teal: teal, danger: danger, canSave: canSave, single: single, save: save,
                  extra: { EmptyView() }, content: content)
    }
}

/// 一格：上面小标题，下面输入框。
struct V3FormField: View {
    let label: String
    var prompt = ""
    @Binding var text: String
    var big = false
    var focus = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            V3Label(label, size: 12.5, weight: .bold)
            TextField(prompt, text: $text).textFieldStyle(.plain)
                .font(big ? V3.num(24, .heavy) : V3.font(15, .bold)).foregroundStyle(V3.ink).focused($focused)
                .padding(.horizontal, 16).padding(.vertical, big ? 9 : 9)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(V3.ink, lineWidth: 2)))
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if focus { focused = true } }
    }
}

/// 一格：上面小标题，下面几个选一个。
struct V3FormPick: View {
    let label: String
    let options: [String]
    @Binding var pick: Int
    var teal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !label.isEmpty { V3Label(label, size: 12.5, weight: .bold) }
            // 放不下一行就换行，不截掉
            FlowLayout(spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                    Button { withAnimation(.snappy(duration: 0.15)) { pick = i } } label: {
                        Text(o).font(V3.font(13.5, .bold)).foregroundStyle(pick == i ? .white : V3.ink).lineLimit(1)
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .background(Capsule().fill(pick == i ? (teal ? V3.teal : V3.navy) : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                    }
                    .buttonStyle(V3SinkStyle(depth: 2))
                    .accessibilityAddTraits(pick == i ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 弹窗里那块浅底的预览：左边一句话，右边一个数。
struct V3FormPreview: View {
    let text: String
    var amount = ""
    var good = true
    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(V3.font(14, .bold)).foregroundStyle(good ? V3.ink : V3.red).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if !amount.isEmpty { Text(amount).font(V3.num(20, .heavy)).foregroundStyle(V3.navy).contentTransition(.numericText()) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(good ? V3.bg : V3.warnBG))
    }
}

/// 弹窗里带开关的一行。
struct V3FormSwitch: View {
    let title: String
    var sub = ""
    @Binding var on: Bool
    var teal = false
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(V3.font(14.5, .bold))
                if !sub.isEmpty { V3Label(sub, size: 12.5) }
            }
            Spacer()
            V3Switch(on: $on, label: title, tint: teal ? V3.teal : V3.navy)
        }
    }
}

/// 没看懂的数：红字说一句怎么写。
private struct V3AmountHint: View {
    let text: String
    var body: some View {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty, V3Form.amount(text) == nil {
            V3Label("这个数我没看懂。写成 12,5 或者 1.250,00 这样就行。", color: V3.red, weight: .semibold)
        }
    }
}

enum V3Form {
    /// 读一个比 0 大的数。
    static func amount(_ text: String) -> Money? {
        guard let m = Money(parsing: text), m > .zero else { return nil }
        return m
    }

    /// 可以空着的数：空着算 0。
    static func amountOrZero(_ text: String) -> Money? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? .zero : Money(parsing: text).flatMap { $0 >= .zero ? $0 : nil }
    }

    static func plain(_ m: Money) -> String { m.v3Parts.whole + m.v3Parts.rest.filter { $0.isNumber || $0 == "," } }
}

// MARK: - 记一笔 · 自己填

struct V3ManualSheet: View {
    /// 嵌在「记一笔」小窗的「自己填」那一段里：不要自己的壳，记好以后叫 `done`。
    var embedded = false
    var done: () -> Void = {}
    @Environment(V3State.self) private var state
    @State private var kind = 0
    @State private var amount = ""
    @State private var place = ""
    @State private var cat = 2
    @State private var incomeCat = 0
    @State private var account = 0
    @State private var from = ""
    @State private var to = ""
    @State private var daysAgo = 0
    @State private var pickingDate = false
    @State private var note = ""

    /// 在哪一边打开的，就只记哪一边。
    private var bookSide: TrialBook.Side { state.side == .biz ? .biz : .life }
    private var accounts: [V3State.Account] { state.book.accounts(for: kind == 1 ? .receive : .pay, side: bookSide) }

    var body: some View {
        let m = V3Form.amount(amount)
        let names = accounts.map(\.name)
        let life = bookSide == .life
        let left = state.book.month.left - (kind == 0 && life ? m ?? .zero : .zero) + (kind == 1 && life ? m ?? .zero : .zero)
        let foot = kind == 2 ? (m.map { "从 \(from) 拿 \($0.v3) 放进 \(to)" } ?? "") : (life ? "记完这个月还能随便花 \(left.v3)" : "")
        let ok = m != nil && (kind == 2 ? (from != to && !from.isEmpty && !to.isEmpty) : !names.isEmpty)
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: 12) {
                    fields(m, names)
                    HStack(spacing: 10) {
                        V3Label(foot, size: 13)
                        Spacer(minLength: 8)
                        Button("记好 ↩") { if save(m) { done() } }.buttonStyle(.v3).disabled(!ok).keyboardShortcut(.defaultAction)
                        // ⌘↩：记好，清空接着记下一笔
                        Button("") { if save(m) { amount = ""; place = ""; note = "" } }.keyboardShortcut(.return, modifiers: .command).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                    }
                }
            } else {
                V3SheetBox(width: 660, title: "记一笔 · 自己填", foot: foot, canSave: ok,
                           save: { if save(m) { state.closeSheet() } },
                           extra: { Button("记好，再记一笔") { if save(m) { amount = ""; place = ""; note = "" } }.buttonStyle(.v3(.ghost)).disabled(!ok) }) {
                    fields(m, names)
                }
            }
        }
        .onAppear {
            if let pre = state.manualPrefill { place = pre.name; amount = V3Form.plain(pre.amount); cat = max(state.book.categories.count - 1, 0); state.manualPrefill = nil }
            let s = bookSide == .life ? state.book.transferShortcuts.first : nil
            from = s?.from ?? state.book.transferSources(bookSide).first?.name ?? ""
            to = s?.to ?? state.book.transferTargets(bookSide).first { $0.name != from }?.name ?? ""
        }
        .onChange(of: kind) { _, _ in account = 0 }
    }

    @ViewBuilder private func fields(_ m: Money?, _ names: [String]) -> some View {
        V3FormPick(label: "", options: ["支出", "收入", "转账"], pick: $kind)
        if kind == 2 {
            transferFields
        } else {
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "多少钱", prompt: "3,20", text: $amount, big: true, focus: true).frame(width: 200)
                V3FormField(label: kind == 1 ? "谁给的" : "给谁 / 哪家店", prompt: kind == 1 ? "小林工作室" : "Café Nube", text: $place, big: true)
            }
            V3AmountHint(text: amount)
            VStack(alignment: .leading, spacing: 5) {
                V3Label("分类", size: 12.5, weight: .bold)
                if kind == 1 { V3CatGrid(pick: incomeCat, items: TrialBook.incomeCategories) { incomeCat = $0 } }
                else { V3CatGrid(pick: cat) { cat = $0 } }
            }
            V3FormPick(label: kind == 1 ? "进到哪个账户" : "怎么付的", options: names, pick: $account)
            dayPick
            V3FormField(label: "备注", prompt: "可不填", text: $note)
        }
    }

    /// 哪天：今天、昨天，或者点开小日历选一天（只能选今天和以前）。
    private var dayPick: some View {
        let today = state.book.todayDate
        let cal = Calendar(identifier: .gregorian)
        return VStack(alignment: .leading, spacing: 5) {
            V3Label("哪天", size: 12.5, weight: .bold)
            HStack(spacing: 6) {
                dayChip("今天", daysAgo == 0) { daysAgo = 0 }
                dayChip("昨天", daysAgo == 1) { daysAgo = 1 }
                dayChip(daysAgo > 1 ? QuickDate.label(daysAgo: daysAgo, today: today, calendar: cal) : "选日期", daysAgo > 1) { pickingDate = true }
                    .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
                        DatePicker("", selection: Binding(
                            get: { cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today },
                            set: { d in daysAgo = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: today)).day ?? 0) }),
                                   in: ...today, displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden().padding(12).frame(width: 300)
                    }
            }
        }
    }

    private func dayChip(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy(duration: 0.15)) { action() } } label: {
            Text(title).font(V3.font(13.5, .bold)).foregroundStyle(on ? .white : V3.ink).lineLimit(1)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(on ? V3.navy : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
        }
        .buttonStyle(V3SinkStyle(depth: 2)).accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 转账：从哪 → 到哪，一眼看得懂

    @ViewBuilder private var transferFields: some View {
        let b = state.book
        let shortcuts = bookSide == .life ? b.transferShortcuts : []
        if !shortcuts.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, sc in
                    V3Chip(text: sc.title, size: 13) { withAnimation(.snappy(duration: 0.15)) { from = sc.from; to = sc.to } }
                }
            }
        }
        V3FormField(label: "多少钱", prompt: "200", text: $amount, big: true, focus: true).frame(width: 220).frame(maxWidth: .infinity)
        V3AmountHint(text: amount)
        HStack(spacing: 10) {
            accountCard("从", from, b.transferSources(bookSide)) { from = $0; if to == $0 { to = b.transferTargets(bookSide).first { $0.name != from }?.name ?? "" } }
            VStack(spacing: 6) {
                Image(systemName: "arrow.right").font(.system(size: 24, weight: .heavy)).foregroundStyle(V3.navy)
                Button {
                    // 对调：只有两边都能当「从」时才调得过来
                    if b.transferSources(bookSide).contains(where: { $0.name == to }) { withAnimation(.snappy(duration: 0.15)) { (from, to) = (to, from) } }
                    else { state.fail("「\(to)」里的钱转不出来，调不过来") }
                } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 26, height: 22)
                        .background(Capsule().fill(V3.bg))
                }
                .buttonStyle(.plain).help("对调").accessibilityLabel("从和到对调")
            }
            accountCard("到", to, b.transferTargets(bookSide).filter { $0.name != from }) { to = $0 }
        }
    }

    private func accountCard(_ label: String, _ name: String, _ choices: [V3State.Account], pick: @escaping (String) -> Void) -> some View {
        let a = state.book.account(name)
        return Menu {
            ForEach(choices) { c in Button("\(c.emoji) \(c.name) · \(c.balance.v3)") { pick(c.name) } }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(V3.font(12, .bold)).foregroundStyle(V3.ink2)
                HStack(spacing: 8) {
                    V3Ico(emoji: a?.emoji ?? "💳", size: 30)
                    Text(a?.name ?? "选一个").font(V3.font(15, .heavy)).foregroundStyle(V3.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(V3.ink2)
                }
                Text(a.map { ($0.kind == .debt ? "还欠 " : "") + $0.balance.v3 } ?? "").font(V3.num(14)).foregroundStyle(a?.kind == .debt ? V3.red : V3.navy)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(V3.ink, lineWidth: 2)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain)
        .accessibilityLabel("\(label)：\(a?.name ?? "还没选")")
    }

    private func save(_ m: Money?) -> Bool {
        guard let m else { return false }
        if kind == 2 {
            var reached: [Journey.Station] = []
            let ok = state.change("转好了 · 从 \(from) 拿 \(m.v3) 放进 \(to)", kind: .transfer) { reached = try $0.transfer(m, from: from, to: to) }
            if ok, !reached.isEmpty { state.starDrops += 1 }
            return ok
        }
        guard accounts.indices.contains(account) else { return false }
        let acc = accounts[account].name
        let shop = place.trimmingCharacters(in: .whitespaces)
        let c = kind == 1 ? TrialBook.incomeCategories[min(incomeCat, TrialBook.incomeCategories.count - 1)]
                          : state.book.categories[min(cat, state.book.categories.count - 1)]
        return state.change("记好了 · \(c.name) \(m.v3) · \(acc)", kind: .add) {
            try $0.record(name: c.name, emoji: c.emoji, amount: m, income: kind == 1, account: acc, place: shop,
                          tag: "自己记的", daysAgo: daysAgo, side: bookSide, note: note)
        }
    }
}

/// 12 个分类排两行，点一下就选。
private struct V3CatGrid: View {
    let pick: Int?
    /// 不给就是账本里支出的那些分类。
    var items: [TrialBook.Category]? = nil
    var choose: (Int) -> Void
    @Environment(V3State.self) private var state
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(Array((items ?? state.book.categories).prefix(18).enumerated()), id: \.offset) { i, c in
                Button { choose(i) } label: {
                    VStack(spacing: 3) {
                        V3Ico(emoji: c.emoji, size: 30)
                        Text(c.name).font(V3.font(12.5, .bold)).foregroundStyle(V3.ink)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 14).fill(pick == i ? V3.goodBG : .white)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(V3.ink, lineWidth: pick == i ? 2.5 : 1.5)))
                }
                .buttonStyle(V3SinkStyle(depth: 2))
                .accessibilityLabel(c.name).accessibilityAddTraits(pick == i ? .isSelected : [])
            }
        }
    }
}

// MARK: - 存一笔

private struct V3SaveSheet: View {
    @Environment(V3State.self) private var state
    @State private var amount = "20"
    @State private var account = 0
    /// 存进哪个目标：0 是大目标，后面是小目标。
    @State private var goal = 0

    var body: some View {
        let j = state.book.journey
        let small = state.book.activeSmallGoals
        let accounts = state.book.accounts(for: .moveOut).filter { $0.kind == .own }
        let m = V3Form.amount(amount)
        let from = accounts.indices.contains(account) ? accounts[account] : nil
        let enough = m.map { ($0) <= (from?.balance ?? .zero) } ?? true
        let picked = goal > 0 && small.indices.contains(goal - 1) ? small[goal - 1] : nil
        let gap = (picked.map { $0.target - $0.saved } ?? j.remainingToNext) - (m ?? .zero)
        V3SheetBox(width: 540, title: "存一笔", primary: "存好",
                   canSave: m != nil && enough && from != nil,
                   save: {
                       guard let m, let from else { return }
                       if let picked {
                           if state.change("存好了 +\(m.v3Short) · \(picked.name)", kind: .goalDeposit, { try $0.depositSmall(picked.id, amount: m, from: from.name) }) { state.closeSheet() }
                       } else if state.depositAndCelebrate(m, from: from.name) { state.closeSheet() }
                   }) {
            if !small.isEmpty { V3FormPick(label: "存进哪个目标", options: [j.name] + small.map(\.name), pick: $goal) }
            V3FormField(label: "存多少", prompt: "20", text: $amount, big: true, focus: true)
            V3AmountHint(text: amount)
            HStack(spacing: 6) {
                ForEach([10, 20, 50], id: \.self) { n in V3Chip(text: "\(n) €", size: 13) { amount = "\(n)" } }
                if picked == nil, j.remainingToNext > .zero { V3Chip(text: "这一站差的 \(j.remainingToNext.v3Short)", size: 13) { amount = V3Form.plain(j.remainingToNext) } }
                if let picked, picked.target > picked.saved { V3Chip(text: "还差的 \((picked.target - picked.saved).v3Short)", size: 13) { amount = V3Form.plain(picked.target - picked.saved) } }
            }
            V3FormPick(label: "从哪个账户拿", options: accounts.map { "\($0.name) · \($0.balance.v3)" }, pick: $account)
            if !enough, let from {
                V3FormPreview(text: "\(from.name)里只有 \(from.balance.v3)，不够存这么多。", good: false)
            } else if m != nil {
                V3FormPreview(text: gap > .zero ? (picked == nil ? "存完这一站还差" : "存完还差") : (picked == nil ? "这一笔存完就到站了" : "这一笔存完就够了"), amount: gap > .zero ? gap.v3Short : "⭐")
            }
        }
        .onAppear {
            if let t = state.saveTarget, let i = small.firstIndex(where: { $0.id == t }) { goal = i + 1 }
            state.saveTarget = nil
        }
    }
}

/// 加一个小目标，或者改一个。
struct V3SmallGoalSheet: View {
    let id: UUID?
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    @State private var due = ""
    var body: some View {
        let m = V3Form.amount(amount)
        let ok = m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
        V3SheetBox(width: 520, title: id == nil ? "加一个小目标" : "改小目标", primary: id == nil ? "加上" : "改好", canSave: ok,
                   save: {
                       guard let m else { return }
                       let done = id.map { gid in state.change("改好了：\(name)", kind: .goal) { try $0.editSmallGoal(gid, name: name, target: m, due: due) } }
                           ?? state.change("加上了：\(name) \(m.v3Short)", kind: .goal) { try $0.addSmallGoal(name: name, target: m, due: due) }
                       if done { state.closeSheet() }
                   }) {
            V3FormField(label: "想要什么", prompt: "周末短途旅行", text: $name, focus: true)
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "一共要多少", prompt: "300", text: $amount, big: true)
                V3FormField(label: "想哪天前存够", prompt: "可不填，比如：明年 3 月前", text: $due)
            }
            V3AmountHint(text: amount)
        }
        .onAppear {
            if let id, let g = state.book.smallGoals.first(where: { $0.id == id }) { name = g.name; amount = V3Form.plain(g.target); due = g.due }
        }
    }
}

/// 忍住了一笔：没买的那样东西和它的钱，存进大目标。默认填你最近最常买的小东西；流水里看不出来就空着。
struct V3HoldBackSheet: View {
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    var body: some View {
        let m = V3Form.amount(amount)
        let j = state.book.journey
        V3SheetBox(width: 500, title: "忍住了一笔", sub: j.total > .zero ? "存进「\(j.name)」" : "", primary: "存进去", canSave: m != nil,
                   save: {
                       guard let m else { return }
                       var reached: [Journey.Station] = []
                       let what = name.trimmingCharacters(in: .whitespaces)
                       if state.change("算你忍住一次 +\(m.v3Short)\(what.isEmpty ? "" : " · \(what)")", kind: .goalDeposit, { reached = try $0.holdBack(name: name, amount: m) }) {
                           state.starDrops += 1
                           state.closeSheet()
                           state.celebrate(reached)
                       }
                   }) {
            V3FormField(label: "忍住了什么", prompt: "可不填", text: $name)
            V3FormField(label: "多少钱", prompt: "3", text: $amount, big: true, focus: true)
            V3AmountHint(text: amount)
            HStack(spacing: 6) { ForEach([3, 10, 30], id: \.self) { n in V3Chip(text: "\(n) €", size: 13) { amount = "\(n)" } } }
        }
        .onAppear {
            if let h = state.book.smallHabit { name = h.name; amount = V3Form.plain(h.typical) }
        }
    }
}

// MARK: - 这笔算哪一类

private struct V3CategorySheet: View {
    let id: UUID
    @Environment(V3State.self) private var state
    @State private var always = true

    var body: some View {
        let e = state.book.entries.first { $0.id == id }
        let place = e.map { $0.place.isEmpty ? $0.name : $0.place } ?? ""
        let now = state.book.categories.firstIndex { $0.name == e?.name }
        V3SheetBox(width: 580, title: "这笔算哪一类", sub: e.map { "\(place) · \($0.amount.v3)" } ?? "", foot: "点图标就选好，不用再点确定。", primary: "不改了",
                   save: { state.closeSheet() }) {
            V3CatGrid(pick: now) { i in
                let c = state.book.categories[i]
                let text = always ? "归好了，以后「\(place)」都按\(c.name)" : "归好了：\(c.name)"
                if state.change(text, kind: .categorize, { try $0.recategorize(entry: id, emoji: c.emoji, name: c.name, always: always) }) { state.closeSheet() }
            }
            V3FormSwitch(title: "以后这家店都按这一类", sub: "关掉就只改这一笔", on: $always)
        }
    }
}

// MARK: - 改金额

private struct V3AmountSheet: View {
    let id: UUID
    @Environment(V3State.self) private var state
    @State private var amount = ""

    var body: some View {
        let e = state.book.entries.first { $0.id == id }
        let m = V3Form.amount(amount)
        V3SheetBox(width: 440, title: "改金额", sub: e.map { "\($0.name) · 现在是 \($0.amount.magnitude.v3)" } ?? "", primary: "改好",
                   canSave: m != nil && m != e?.amount.magnitude,
                   save: {
                       guard let m, let e else { return }
                       if state.change("改好了：\(e.name) \(e.amount.magnitude.v3) → \(m.v3)", { try $0.setAmount(entry: id, to: m) }) { state.closeSheet() }
                   }) {
            V3FormField(label: "改成多少", prompt: "", text: $amount, big: true, focus: true)
            V3AmountHint(text: amount)
        }
        .onAppear { if let e { amount = V3Form.plain(e.amount.magnitude) } }
    }
}

// MARK: - 加一个订阅

private struct V3SubscriptionSheet: View {
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    @State private var cycle = 1
    /// 下次哪天扣：离今天几天（nil = 还没选）。
    @State private var nextIn: Int?
    @State private var pickingDate = false
    @State private var account = 0
    @State private var forWork = false

    var body: some View {
        let m = V3Form.amount(amount)
        let accounts = state.book.accounts(for: .pay, side: .life)
        let today = state.book.todayDate
        let cal = Calendar(identifier: .gregorian)
        let nextDate = nextIn.flatMap { cal.date(byAdding: .day, value: $0, to: today) }
        let nextLabel = nextDate.map { "\(cal.component(.month, from: $0)) 月 \(cal.component(.day, from: $0)) 日" }
        let ok = m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
        let yearly = m.map { TrialBook.Item(emoji: "", name: "", note: "", amount: $0, cycle: cycle).yearly }
        V3SheetBox(width: 560, title: "加一个订阅", foot: yearly.map { "一年是 \($0.v3Short)。" } ?? "", primary: "加好",
                   canSave: ok,
                   save: {
                       guard let m else { return }
                       let cyc = TrialBook.Item.cycleNames[cycle]
                       let day = nextLabel ?? ""
                       let acc = accounts.indices.contains(account) ? accounts[account].name : ""
                       let note = [day.isEmpty ? "\(cyc)扣" : "\(day)扣", acc].filter { !$0.isEmpty }.joined(separator: " · ")
                       if state.change("加好了：\(name) \(cyc) \(m.v3)", kind: .subscription, { try $0.addSubscription(name: name, amount: m, note: note, forWork: forWork, cycle: cycle) }) { state.closeSheet() }
                   }) {
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "叫什么", prompt: "健身房", text: $name, focus: true)
                V3FormField(label: "每次扣多少", prompt: "29,00", text: $amount).frame(width: 170)
            }
            V3AmountHint(text: amount)
            V3FormPick(label: "多久扣一次", options: TrialBook.Item.cycleNames, pick: $cycle)
            VStack(alignment: .leading, spacing: 5) {
                V3Label("下次哪天扣", size: 12.5, weight: .bold)
                Button { pickingDate = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 12, weight: .semibold))
                        Text(nextLabel ?? "选日期").font(V3.font(13.5, .bold))
                    }
                    .foregroundStyle(nextIn == nil ? V3.ink : .white)
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(Capsule().fill(nextIn == nil ? .white : V3.navy).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                }
                .buttonStyle(V3SinkStyle(depth: 2))
                .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
                    DatePicker("", selection: Binding(get: { nextDate ?? today },
                                                    set: { d in nextIn = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: d)).day ?? 0) }),
                               in: today..., displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden().padding(12).frame(width: 300)
                }
            }
            V3FormPick(label: "从哪个账户扣", options: accounts.map(\.name), pick: $account)
            V3FormSwitch(title: "工作要用，别劝我退", on: $forWork)
        }
    }
}

// MARK: - 记一笔欠款

private struct V3DebtSheet: View {
    @Environment(V3State.self) private var state
    @State private var who = 0
    @State private var name = ""
    @State private var amount = ""
    @State private var note = ""
    @State private var periods = "12"
    @State private var paid = "0"
    @State private var day = "8"

    var body: some View {
        let m = V3Form.amount(amount)
        let n = Int(periods.trimmingCharacters(in: .whitespaces)), done = Int(paid.trimmingCharacters(in: .whitespaces)), d = Int(day.trimmingCharacters(in: .whitespaces))
        let each = m.flatMap { m in n.flatMap { $0 > 0 ? Money(cents: m.cents / Int64($0)) : nil } }
        let ok = m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty && (who != 2 || (n != nil && done != nil && d != nil))
        V3SheetBox(width: 600, title: "记一笔欠款", foot: who == 2 ? "每月要还的会从「能随便花」里先扣掉。" : "借钱和还钱不算花也不算赚。", primary: "记上", canSave: ok,
                   save: {
                       guard let m else { return }
                       let saved: Bool
                       if who == 2, let n, let done, let d {
                           saved = state.change("记上了：\(name) 分 \(n) 期", kind: .installment) { try $0.addInstallment(name: name, total: m, periods: n, paid: done, day: d) }
                       } else {
                           let label = who == 1 ? "借给\(name)" : name
                           saved = state.change("记上了：\(label) \(m.v3)", kind: .debt) { try $0.addDebt(name: label, amount: m, owedToMe: who == 1, note: note) }
                       }
                       if saved { state.closeSheet() }
                   }) {
            V3FormPick(label: "", options: ["我欠别人", "别人欠我", "分期"], pick: $who)
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: who == 1 ? "谁欠我" : who == 2 ? "买的什么" : "欠谁的", prompt: who == 1 ? "小李" : who == 2 ? "新冰箱" : "朋友阿杰", text: $name, focus: true)
                V3FormField(label: "一共多少", prompt: "300,00", text: $amount).frame(width: 170)
            }
            V3AmountHint(text: amount)
            if who == 2 {
                HStack(alignment: .top, spacing: 12) {
                    V3FormField(label: "分几期", prompt: "12", text: $periods)
                    V3FormField(label: "已经还了几期", prompt: "0", text: $paid)
                    V3FormField(label: "每月几号扣", prompt: "8", text: $day)
                }
                if let each, let n, let done, done < n, let m {
                    V3FormPreview(text: "每期 \(each.v3) · 还剩 \(n - done) 期，还欠", amount: (m - Money(cents: each.cents * Int64(done))).v3)
                } else if m != nil {
                    V3FormPreview(text: "期数没看懂：分几期填 2 到 60，已经还的要比它少。", good: false)
                }
            } else {
                V3FormField(label: "说好什么时候还", prompt: "可不填，比如：12 月还", text: $note)
            }
        }
    }
}

// MARK: - 记一笔还款

private struct V3RepaySheet: View {
    let debt: String
    @Environment(V3State.self) private var state
    @State private var amount = ""
    @State private var account = 0

    var body: some View {
        let owed = state.book.account(debt)?.balance ?? .zero
        let accounts = state.book.accounts(for: .moveOut).filter { $0.kind == .own }
        let from = accounts.indices.contains(account) ? accounts[account] : nil
        let m = V3Form.amount(amount)
        let tooMuch = (m ?? .zero) > owed
        let enough = (m ?? .zero) <= (from?.balance ?? .zero)
        V3SheetBox(width: 520, title: "记一笔还款", sub: "\(debt) · 还欠 \(owed.v3)", primary: "记上", canSave: m != nil && !tooMuch && enough && from != nil,
                   save: {
                       guard let m, let from else { return }
                       if state.change("还款记好了 · \(debt) \(m.v3)", kind: .repay, { try $0.repay(debt: debt, amount: m, from: from.name) }) { state.closeSheet() }
                   }) {
            V3FormField(label: "还了多少", prompt: "", text: $amount, big: true, focus: true)
            V3AmountHint(text: amount)
            HStack(spacing: 6) {
                V3Chip(text: "全还 \(owed.v3Short)", size: 13) { amount = V3Form.plain(owed) }
                V3Chip(text: "一半 \(Money(cents: owed.cents / 2).v3Short)", size: 13) { amount = V3Form.plain(Money(cents: owed.cents / 2)) }
                V3Chip(text: "最低 \(Money(cents: owed.cents / 10).v3Short)", size: 13) { amount = V3Form.plain(Money(cents: owed.cents / 10)) }
            }
            V3FormPick(label: "从哪个账户还", options: accounts.map { "\($0.name) · \($0.balance.v3)" }, pick: $account)
            if let m, let from {
                if tooMuch {
                    V3FormPreview(text: "\(debt)只欠 \(owed.v3)，不用还这么多。", good: false)
                } else if !enough {
                    V3FormPreview(text: "\(from.name)里只有 \(from.balance.v3)，不够还这么多。", good: false)
                } else {
                    V3FormPreview(text: m == owed ? "还完这笔，\(debt)就清了。\(from.name)还剩" : "还完还欠 \((owed - m).v3)。\(from.name)还剩", amount: (from.balance - m).v3)
                }
            }
        }
        .onAppear { amount = V3Form.plain(owed) }
    }
}

// MARK: - 生意：记今天的账

private struct V3ShopDaySheet: View {
    let start: Int
    @Environment(V3State.self) private var state
    @State private var cash = ""
    @State private var card = ""
    @State private var day = 18

    var body: some View {
        let b = state.book
        let c = V3Form.amountOrZero(cash), k = V3Form.amountOrZero(card)
        let total = (c ?? .zero) + (k ?? .zero)
        let known = b.shopDays.first { $0.day == day }
        let need = b.dailyBreakEven
        let missing = b.shopDays.filter { $0.state == .missing && $0.day < b.todayDay && $0.day != day }.map(\.day)
        V3SheetBox(width: 520, title: day == b.todayDay ? "记今天的账" : "补 \(day) 号的账", sub: "11 月 \(day) 日 · 每天只记总数",
                   foot: known?.state == .open ? "这天记过了，再记就是改数。" : "", teal: true,
                   canSave: c != nil && k != nil && total > .zero,
                   save: {
                       guard let c, let k else { return }
                       if state.change("记好了 · 11 月 \(day) 日收了 \(total.v3)", kind: .add, { try $0.recordShopDay(day, cash: c, card: k) }) { state.closeSheet() }
                   }) {
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "收的现金", prompt: "0", text: $cash, big: true, focus: true)
                V3FormField(label: "刷卡收的", prompt: "0", text: $card, big: true)
            }
            if c == nil || k == nil { V3Label("这个数我没看懂。写成 74 或者 74,50 这样就行。", color: V3.red, weight: .semibold) }
            V3FormPreview(text: total >= need ? "这天一共 · 够付这天的固定开销了" : "这天一共 · 离够付固定开销还差 \((need - total).v3Short)", amount: total.v3)
            HStack(spacing: 8) {
                V3Label("哪天", size: 12.5, weight: .bold)
                Button { if day > 1 { day -= 1 } } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28).background(Circle().fill(V3.bg)) }
                    .buttonStyle(.plain).accessibilityLabel("前一天")
                Text("11 月 \(day) 日").font(V3.num(15, .heavy)).frame(width: 96).contentTransition(.numericText())
                Button { if day < b.todayDay { day += 1 } } label: { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28).background(Circle().fill(V3.bg)) }
                    .buttonStyle(.plain).disabled(day >= b.todayDay).accessibilityLabel("后一天")
                ForEach(missing, id: \.self) { d in V3Chip(text: "\(d) 号还没记", size: 12.5) { day = d } }
                Spacer()
                Button("这天休息") {
                    if state.change("记好了 · 11 月 \(day) 日休息", { try $0.markShopRest(day) }) { state.closeSheet() }
                }
                .buttonStyle(.v3(.ghost, .small))
            }
        }
        .onAppear { day = start; fill() }
        .onChange(of: day) { _, _ in fill() }
    }

    private func fill() {
        if let d = state.book.shopDays.first(where: { $0.day == day }), d.state == .open {
            cash = V3Form.plain(d.cash); card = V3Form.plain(d.card)
        } else { cash = ""; card = "" }
    }
}

// MARK: - 生意：加一样固定开销

private struct V3FixedSheet: View {
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    @State private var day = "1"
    @State private var skip = 0

    var body: some View {
        let b = state.book
        let m = V3Form.amount(amount)
        let ok = m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
        let after = b.fixedTotal + (m ?? .zero)
        V3SheetBox(width: 540, title: "加一样固定开销", sub: "不管开不开门，每个月都要付的", primary: "加好", teal: true, canSave: ok,
                   save: {
                       guard let m else { return }
                       let d = Int(day.trimmingCharacters(in: .whitespaces)).flatMap { (1...31).contains($0) ? $0 : nil } ?? 1
                       if state.change("加好了：\(name) 每月 \(m.v3)", { try $0.addFixedCost(name: name, amount: m, note: "每月 \(d) 日", canSkip: skip == 1) }) { state.closeSheet() }
                   }) {
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "叫什么", prompt: "店面保险", text: $name, focus: true)
                V3FormField(label: "每月多少", prompt: "35,00", text: $amount).frame(width: 150)
                V3FormField(label: "每月几号付", prompt: "12", text: $day).frame(width: 110)
            }
            V3AmountHint(text: amount)
            V3FormPick(label: "这笔能不能省", options: ["必要", "可省"], pick: $skip, teal: true)
            if m != nil {
                V3FormPreview(text: "每月固定要付，从 \(b.fixedTotal.v3Short) 变成", amount: after.v3Short)
            }
        }
    }
}

// MARK: - 生意：进货、盘货、又投了钱（都是「叫什么 + 多少」）

private struct V3SimpleSheet: View {
    enum Kind { case purchase, stock, capital }
    let kind: Kind
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""

    var body: some View {
        let m = V3Form.amount(amount)
        let shop = state.book.accounts.first { $0.kind == .shop }
        let short = kind == .purchase && (m ?? .zero) > (shop?.balance ?? .zero)
        V3SheetBox(width: 520, title: title, hint: [sub, foot].filter { !$0.isEmpty }.joined(separator: "。"), primary: kind == .stock ? "记下" : "记好", teal: true, canSave: m != nil && !short,
                   save: {
                       guard let m else { return }
                       let ok: Bool
                       switch kind {
                       case .purchase: ok = state.change("记好了 · 进货 \(m.v3)", kind: .add) { try $0.addPurchase(name: name, amount: m, note: "今天") }
                       case .stock: ok = state.change("记下了 · 店里的货大概值 \(m.v3)") { try $0.estimateStock(m, note: "刚估的") }
                       case .capital: ok = state.change("记好了 · 又投了 \(m.v3)") { try $0.addCapital(name: name, amount: m, note: "今天") }
                       }
                       if ok { state.closeSheet() }
                   }) {
            HStack(alignment: .top, spacing: 12) {
                if kind != .stock { V3FormField(label: kind == .purchase ? "进的什么" : "做什么用", prompt: kind == .purchase ? "鲜花补货" : "新设备", text: $name, focus: true) }
                V3FormField(label: kind == .stock ? "现在店里的货大概值多少" : "多少钱", prompt: "0", text: $amount, big: kind == .stock, focus: kind == .stock)
                    .frame(width: kind == .stock ? nil : 170)
            }
            V3AmountHint(text: amount)
            if short, let shop {
                V3FormPreview(text: "\(shop.name)里只有 \(shop.balance.v3)，不够付这次进货。", good: false)
            } else if kind == .purchase, let m, let shop {
                V3FormPreview(text: "\(shop.name)付完还剩", amount: (shop.balance - m).v3)
            } else if kind == .capital, let m {
                V3FormPreview(text: "开店本钱，从 \(state.book.capitalTotal.v3Short) 变成", amount: (state.book.capitalTotal + m).v3Short)
            }
        }
    }

    private var title: String { kind == .purchase ? "记一次进货" : kind == .stock ? "估一下现在的货" : "后来又投了钱" }
    private var sub: String { kind == .purchase ? "钱从店里账户出去" : kind == .stock ? "大概的数就行" : "本钱变多，回本的路变长" }
    private var foot: String { kind == .capital ? "本钱改了，回本的进度马上重算。" : "" }
}

/// 改开店本钱的总数。
struct V3CapitalTotalSheet: View {
    @Environment(V3State.self) private var state
    @State private var amount = ""
    var body: some View {
        let m = V3Form.amount(amount)
        let many = state.book.capital.count > 1
        V3SheetBox(width: 520, title: "开店本钱", hint: many ? "改了总数，下面的几样会合成一行。改错了能撤销。" : "本钱改了，回本的进度马上重算。", primary: "存好", teal: true,
                   canSave: m != nil && m != state.book.capitalTotal,
                   save: {
                       guard let m else { return }
                       if state.change("存好了：本钱 \(m.v3)", { try $0.setCapitalTotal(m) }) { state.closeSheet() }
                   }) {
            V3FormField(label: "一共投了", prompt: "32000", text: $amount, big: true, focus: true)
            V3AmountHint(text: amount)
        }
        .onAppear { if state.book.capitalTotal > .zero { amount = V3Form.plain(state.book.capitalTotal) } }
    }
}

/// 改每月存多少（目标页点「这个月的计划」）。
struct V3MonthlyPlanSheet: View {
    @Environment(V3State.self) private var state
    @State private var amount = ""
    var body: some View {
        let m = V3Form.amount(amount)
        let j = state.book.journey
        let months = m.flatMap { j.monthsToFinish(monthly: $0) }
        V3SheetBox(width: 460, title: "每月存多少", primary: "定好", canSave: m != nil && m != j.monthlyPlan,
                   save: {
                       guard let m else { return }
                       if state.change("定好了：每月存 \(m.v3Short)", { try $0.setMonthlyPlan(m) }) { state.closeSheet() }
                   }) {
            V3FormField(label: "每月存", prompt: "200", text: $amount, big: true, focus: true)
            V3AmountHint(text: amount)
            HStack(spacing: 6) { ForEach([100, 150, 200, 250], id: \.self) { n in V3Chip(text: "\(n) €", size: 13) { amount = "\(n)" } } }
            if let months { V3FormPreview(text: "照这个数，\(j.name)大概", amount: V3State.monthName(after: months) + "到手") }
        }
        .onAppear { amount = V3Form.plain(j.monthlyPlan) }
    }
}

/// 一个订阅的详情：每次多少、一年多少，退不退。
struct V3SubscriptionInfoSheet: View {
    let name: String
    @Environment(V3State.self) private var state
    var body: some View {
        let x = state.book.subscriptions.first { $0.name == name }
        V3SheetBox(width: 480, title: name, sub: x?.note ?? "", hint: "app 不能替你去退，到日子叫你。", primary: "好了", save: { state.closeSheet() },
                   extra: {
                       if let x {
                           Button(x.off ? "还是留着" : "标成要退") {
                               if state.change(x.off ? "好，\(name)留着" : "记下了：\(name)要退", kind: .subscription, { try $0.setSubscription(name, dropped: !x.off) }) { state.closeSheet() }
                           }
                           .buttonStyle(.v3(.ghost))
                       }
                   }) {
            if let x {
                V3FormPreview(text: "\(TrialBook.Item.cycleNames[min(max(x.cycle, 0), 3)])扣", amount: x.amount.v3)
                V3FormPreview(text: "一年是", amount: x.yearly.v3)
                if x.flag { V3Label("赚钱要用的，我不会叫你退。", weight: .semibold) }
            }
        }
    }
}

/// 改一样固定开销，或者不再付这笔了。
struct V3FixedEditSheet: View {
    let name: String
    @Environment(V3State.self) private var state
    @State private var amount = ""
    var body: some View {
        let x = state.book.fixedCosts.first { $0.name == name }
        let m = V3Form.amount(amount)
        V3SheetBox(width: 500, title: name, sub: x?.note ?? "", primary: "存好", teal: true, canSave: m != nil && m != x?.amount,
                   save: {
                       guard let m else { return }
                       if state.change("改好了：\(name) 每月 \(m.v3)", { try $0.editFixedCost(name, amount: m) }) { state.closeSheet() }
                   },
                   extra: {
                       Button("不再付这笔了") {
                           if state.change("拿掉了：\(name)", kind: .remove, { try $0.removeFixedCost(name) }) { state.closeSheet() }
                       }
                       .buttonStyle(.v3(.danger))
                   }) {
            V3FormField(label: "每月多少", prompt: "", text: $amount, big: true, focus: true)
            V3AmountHint(text: amount)
            if let x {
                V3FormSwitch(title: "先停一个月", sub: "停着的不算进每月要付的", on: Binding(get: { x.off }, set: { v in
                    state.change(v ? "好，\(name)先停着" : "好，\(name)接着付") { try $0.setFixedCost(name, paused: v) }
                }), teal: true)
            }
        }
        .onAppear { if let x { amount = V3Form.plain(x.amount) } }
    }
}


/// 给店里加一个账户：现金、银行卡、信用卡、收款机里没结的、储蓄、贷款、欠供应商的，或者自己起名。
struct V3ShopAccountSheet: View {
    @Environment(V3State.self) private var state
    @State private var pick = 0
    @State private var name = ""
    @State private var amount = ""
    @State private var customOwes = 0
    static let kinds: [(emoji: String, name: String, owes: Bool)] = [
        ("💶", "店里现金", false), ("🏪", "银行卡", false), ("💳", "信用卡", true), ("🧾", "收款机待结算", false),
        ("🏦", "储蓄", false), ("🏦", "贷款", true), ("📦", "欠供应商的", true), ("🏷", "自己起名", false),
    ]

    var body: some View {
        let k = Self.kinds[pick]
        let custom = pick == Self.kinds.count - 1
        let owes = custom ? customOwes == 1 : k.owes
        let m = V3Form.amountOrZero(amount)
        let useName = name.trimmingCharacters(in: .whitespaces).isEmpty ? (custom ? "" : (k.name == "信用卡" ? "店的信用卡 2" : "店的" + k.name)) : name
        V3SheetBox(width: 600, title: "给店里加一个账户", primary: "加上", teal: true, canSave: m != nil && !useName.isEmpty,
                   save: {
                       guard let m else { return }
                       if state.change("加好了：\(useName)", kind: .account, { try $0.addShopAccount(emoji: k.emoji, name: useName, balance: m, owes: owes) }) { state.closeSheet() }
                   }) {
            V3FormPick(label: "是哪一种", options: Self.kinds.map(\.name), pick: $pick, teal: true)
            if custom { V3FormPick(label: "", options: ["是店里有的钱", "是店里欠的钱"], pick: $customOwes, teal: true) }
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "叫什么", prompt: custom ? "起个名字" : "不填就叫「\(useName)」", text: $name, focus: true)
                V3FormField(label: owes ? "现在欠多少" : "现在有多少", prompt: "0", text: $amount).frame(width: 190)
            }
            if m == nil { V3Label("这个数没看懂，写成 1500 这样就行。", color: V3.red, weight: .semibold) }
        }
    }
}

// MARK: - 生意：两边转钱

private struct V3TransferSheet: View {
    @Environment(V3State.self) private var state
    @State private var toHome = true
    @State private var amount = ""
    @State private var shopPick = 0
    @State private var homePick = 0

    var body: some View {
        let b = state.book
        let shops = b.accounts(for: .receive, side: .biz), homes = b.accounts(for: .receive, side: .life)
        let shop = shops.indices.contains(shopPick) ? shops[shopPick] : shops.first
        let home = homes.indices.contains(homePick) ? homes[homePick] : homes.first
        let m = V3Form.amount(amount)
        let from = toHome ? shop : home
        let short = (m ?? .zero) > (from?.balance ?? .zero)
        V3SheetBox(width: 580, title: "两边转钱", sub: "两边各记一笔，不算赚也不算花", primary: "转好", teal: true, canSave: m != nil && !short && shop != nil && home != nil,
                   save: {
                       guard let m, let shop, let home else { return }
                       let text = toHome ? "转好了 · 从店里拿回家 \(m.v3)" : "转好了 · 垫给店里 \(m.v3)"
                       if state.change(text, kind: .transfer, { try $0.transferBetweenSides(m, toHome: toHome, shopAccount: shop.name, homeAccount: home.name) }) { state.closeSheet() }
                   }) {
            HStack(spacing: 12) {
                V3Option(picked: toHome) { withAnimation(.snappy(duration: 0.15)) { toHome = true } } content: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("🏪 → 🏠 从店里拿回家").font(V3.font(15, .bold)).foregroundStyle(V3.ink)
                        Text("算「给自己发了」").font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                    }
                }
                V3Option(picked: !toHome) { withAnimation(.snappy(duration: 0.15)) { toHome = false } } content: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("🏠 → 🏪 自己垫钱给店里").font(V3.font(15, .bold)).foregroundStyle(V3.ink)
                        Text("算「又投了一笔本钱」").font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                    }
                }
            }
            .frame(height: 70)
            V3FormField(label: "多少", prompt: "300", text: $amount, big: true, focus: true)
            V3FormPick(label: "店里的哪个账户", options: shops.map(\.name), pick: $shopPick, teal: true)
            V3FormPick(label: "家里的哪个账户", options: homes.map(\.name), pick: $homePick)
            V3AmountHint(text: amount)
            if let m, let from {
                if short {
                    V3FormPreview(text: "\(from.name)里只有 \(from.balance.v3)，不够转这么多。", good: false)
                } else {
                    V3FormPreview(text: "\(from.name)转走以后还剩", amount: (from.balance - m).v3)
                }
            }
        }
    }
}

// MARK: - 生意：记一笔欠款

private struct V3ShopDebtSheet: View {
    @Environment(V3State.self) private var state
    @State private var who = 0
    @State private var name = ""
    @State private var amount = ""
    @State private var note = ""

    var body: some View {
        let m = V3Form.amount(amount)
        let ok = m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
        V3SheetBox(width: 560, title: "记一笔欠款", sub: "店里的", primary: "记上", teal: true, canSave: ok,
                   save: {
                       guard let m else { return }
                       if state.change("记上了：\(name) \(m.v3)", kind: .debt, { try $0.addShopDebt(name: name, amount: m, note: note, owedToShop: who == 1) }) { state.closeSheet() }
                   }) {
            V3FormPick(label: "", options: ["店里欠别人", "别人欠店里"], pick: $who, teal: true)
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: who == 1 ? "谁欠的" : "欠谁的", prompt: who == 1 ? "熟客王姐" : "供货商", text: $name, focus: true)
                V3FormField(label: "多少", prompt: "120,00", text: $amount).frame(width: 170)
            }
            V3AmountHint(text: amount)
            V3FormField(label: "什么时候到期", prompt: "可不填，比如：12 月 3 日到期", text: $note)
        }
    }
}
#endif
