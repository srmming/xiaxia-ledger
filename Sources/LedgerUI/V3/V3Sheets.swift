#if os(macOS)
import FinanceCore
import SwiftUI

// 弹出来填的小窗（规格稿「补的弹窗」）：自己填一笔、存一笔、改分类、改金额、还款、欠款、订阅，
// 和生意那边的：记今天的账、固定开销、进货、盘货、本钱、两边转钱、店里欠款。
// 规则都在核心（FinanceCore/TrialBook.swift）里，这里只管收字、预览、把没做成的原因说出来。

enum V3Sheet: Equatable {
    case manual, save, category(UUID), amount(UUID), subscription, debt, repay(String)
    case shopDay(Int), fixed, purchase, stock, capital, transfer, shopDebt
    /// 删目标（nil 是大目标）、改大目标
    case goalDelete(UUID?), goalEdit, finishedGoal(UUID)
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
                case .goalDelete(let id): V3GoalDeleteSheet(id: id)
                case .goalEdit: V3GoalEditSheet()
                case .finishedGoal(let id): V3FinishedGoalSheet(id: id)
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
    /// 一打开就停在哪一种（0 支出、1 收入、2 转账）。出图和从别处直接跳到某一种时用。
    init(embedded: Bool = false, done: @escaping () -> Void = {}, startKind: Int = 0) {
        self.embedded = embedded; self.done = done
        _kind = State(initialValue: startKind)
    }
    /// 出图用：转账那一种，目标那一行一打开就是展开的。
    init(startKind: Int, jarsOpen: Bool) {
        self.init(startKind: startKind)
        _showJars = State(initialValue: jarsOpen)
    }
    @State private var amount = ""
    @State private var place = ""
    /// 分类一开始不选：免得什么都被记成同一类。
    @State private var cat: Int? = nil
    @State private var incomeCat = 0
    @State private var account = 0
    @State private var from = ""
    @State private var to = ""
    /// 转账「到」那一行：目标的存钱罐展开没有。
    @State private var showJars = false
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
            if let k = state.manualStartKind { kind = k; state.manualStartKind = nil }
            from = state.book.transferSources(bookSide).first?.name ?? ""
            to = state.book.transferTargets(bookSide).first { $0.name != from }?.name ?? ""
        }
        .onChange(of: kind) { _, _ in account = 0 }
    }

    @ViewBuilder private func fields(_ m: Money?, _ names: [String]) -> some View {
        // 这一边只有一个账户时没得转，不出现「转账」
        V3FormPick(label: "", options: state.book.canTransfer(on: bookSide) ? ["支出", "收入", "转账"] : ["支出", "收入"], pick: $kind)
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

    private var dayPick: some View { V3DatePick(daysAgo: $daysAgo) }

    // MARK: 转账：「从」「到」各一行账户胶囊，直接点

    @ViewBuilder private var transferFields: some View {
        let b = state.book
        let cross = b.crossTargets(from: bookSide)
        V3FormField(label: "多少钱", prompt: "200", text: $amount, big: true, focus: true).frame(width: 220)
        V3AmountHint(text: amount)
        pillRow("从", b.transferSources(bookSide), picked: from, other: to) { from = $0 }
        // 「到」这一行：目标的存钱罐有好几个时收成一个「存进目标 ›」，点开再挑哪个目标，免得一排排满（ming 2026-11-28）
        let targets = b.transferTargets(bookSide)
        let jars = targets.filter { $0.block == .goal }
        if jars.count > 1 {
            let inJar = jars.contains { $0.name == to }
            pillRow("到", targets.filter { $0.block != .goal }, picked: to, other: from,
                    extra: (title: inJar ? "⭐ 存进目标 · \(Self.goalName(to))" : "⭐ 存进目标 ›", on: inJar, action: { withAnimation(.snappy(duration: 0.15)) { showJars.toggle() } })) { to = $0; showJars = false }
            if showJars {
                pillRow("存进哪个目标", jars, picked: to, other: from) { to = $0; showJars = false }
            }
        } else {
            pillRow("到", targets, picked: to, other: from) { to = $0 }
        }
        if !cross.isEmpty {
            pillRow(bookSide == .life ? "到 · 店里的" : "到 · 生活的", cross, picked: to, other: from) { to = $0 }
        }
    }

    /// 一行账户胶囊：图标 + 名字 + 余额。选中的深色；另一行已经选了的那个变灰、点不了。
    /// 存钱罐的名字去掉后面的「存钱罐」三个字，就是目标叫什么。
    static func goalName(_ jar: String) -> String {
        let n = jar.replacingOccurrences(of: "存钱罐", with: "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? jar : n
    }

    private func pillRow(_ label: String, _ choices: [V3State.Account], picked: String, other: String,
                         extra: (title: String, on: Bool, action: () -> Void)? = nil, pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            V3Label(label, size: 12.5, weight: .bold)
            FlowLayout(spacing: 6) {
                ForEach(choices) { a in
                    let on = a.name == picked, taken = a.name == other
                    Button { withAnimation(.snappy(duration: 0.15)) { pick(a.name) } } label: {
                        HStack(spacing: 6) {
                            Text(a.emoji).font(.system(size: 13))
                            Text(a.name).font(V3.font(13.5, .bold)).lineLimit(1)
                            Text((a.kind == .debt ? "欠 " : "") + a.balance.v3Short).font(V3.num(12.5)).opacity(0.75).lineLimit(1)
                        }
                        .foregroundStyle(on ? .white : a.kind == .debt ? V3.red : V3.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(on ? V3.navy : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                    }
                    .buttonStyle(V3SinkStyle(depth: 2)).disabled(taken).opacity(taken ? 0.35 : 1)
                    .accessibilityLabel("\(label)：\(a.name)").accessibilityAddTraits(on ? .isSelected : [])
                }
                if let extra {
                    Button(action: extra.action) {
                        Text(extra.title).font(V3.font(13.5, .bold)).lineLimit(1)
                            .foregroundStyle(extra.on ? .white : V3.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(extra.on ? V3.navy : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                    }
                    .buttonStyle(V3SinkStyle(depth: 2)).accessibilityLabel("\(label)：存进目标，点开挑哪一个")
                }
            }
        }
    }

    private func save(_ m: Money?) -> Bool {
        guard let m else { return false }
        if kind == 2 {
            var reached: [Journey.Station] = []
            let ok = state.change("转好了 · 从 \(from) 拿 \(m.v3) 放进 \(to)", kind: .transfer) { reached = try $0.transferAny(m, from: from, to: to) }
            if ok, !reached.isEmpty { state.starDrops += 1 }
            return ok
        }
        guard accounts.indices.contains(account) else { return false }
        let acc = accounts[account].name
        let shop = place.trimmingCharacters(in: .whitespaces)
        let c = kind == 1 ? TrialBook.incomeCategories[min(incomeCat, TrialBook.incomeCategories.count - 1)]
                          : state.book.categories[min(cat ?? state.book.categories.count - 1, state.book.categories.count - 1)]   // 没选分类就记成「还没分」
        return state.change("记好了 · \(c.name) \(m.v3) · \(acc)", kind: .add) {
            try $0.record(name: c.name, emoji: c.emoji, amount: m, income: kind == 1, account: acc, place: shop,
                          tag: "自己记的", daysAgo: daysAgo, side: bookSide, note: note)
        }
    }
}

/// 哪天：今天、昨天，或者点开小日历选一天（只能选今天和以前）。生活的记一笔和店里的记账共用。
struct V3DatePick: View {
    @Binding var daysAgo: Int
    var teal = false
    @Environment(V3State.self) private var state
    @State private var picking = false

    var body: some View {
        let today = state.book.todayDate
        let cal = Calendar(identifier: .gregorian)
        VStack(alignment: .leading, spacing: 5) {
            V3Label("哪天", size: 12.5, weight: .bold)
            HStack(spacing: 6) {
                chip("今天", daysAgo == 0) { daysAgo = 0 }
                chip("昨天", daysAgo == 1) { daysAgo = 1 }
                chip(daysAgo > 1 ? QuickDate.label(daysAgo: daysAgo, today: today, calendar: cal) : "选日期", daysAgo > 1) { picking = true }
                    .popover(isPresented: $picking, arrowEdge: .bottom) {
                        DatePicker("", selection: Binding(
                            get: { cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today },
                            set: { d in daysAgo = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: today)).day ?? 0) }),
                                   in: ...today, displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden().padding(12).frame(width: 300)
                    }
            }
        }
    }

    private func chip(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy(duration: 0.15)) { action() } } label: {
            Text(title).font(V3.font(13.5, .bold)).foregroundStyle(on ? .white : V3.ink).lineLimit(1)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(on ? (teal ? V3.teal : V3.navy) : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
        }
        .buttonStyle(V3SinkStyle(depth: 2)).accessibilityAddTraits(on ? .isSelected : [])
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
        // 大目标没有或者已经存够了：只能存进小目标
        let bigOpen = j.total > .zero && !j.isFinished
        let picked = (goal > 0 || !bigOpen) && small.indices.contains(max(goal - 1, 0)) ? small[max(goal - 1, 0)] : nil
        let gap = (picked.map { $0.target - $0.saved } ?? j.remainingToNext) - (m ?? .zero)
        V3SheetBox(width: 540, title: "存一笔", primary: "存好",
                   canSave: m != nil && enough && from != nil && (picked != nil || bigOpen),
                   save: {
                       guard let m, let from else { return }
                       if let picked {
                           let done = picked.saved + m >= picked.target
                           let text = done ? "🎉「\(picked.name)」存够了！收进走完的路，可以去买了" : "存好了 +\(m.v3Short) · \(picked.name)"
                           if state.change(text, kind: .goalDeposit, { try $0.depositSmall(picked.id, amount: m, from: from.name) }) {
                               if done { state.starDrops += 1 }
                               state.closeSheet()
                           }
                       } else if state.depositAndCelebrate(m, from: from.name) { state.closeSheet() }
                   }) {
            if !small.isEmpty, bigOpen { V3FormPick(label: "存进哪个目标", options: [j.name] + small.map(\.name), pick: $goal) }
            else if small.count > 1 { V3FormPick(label: "存进哪个目标", options: small.map(\.name), pick: Binding(get: { max(goal - 1, 0) }, set: { goal = $0 + 1 })) }
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
/// 新目标的钱放哪：新开一个存钱罐（默认），或者放进一个已有的「存起来的」账户。大目标、小目标共用。
struct V3GoalPlacePick: View {
    let goal: String
    /// 0 是新开存钱罐，后面是已有账户。
    @Binding var pick: Int
    @Environment(V3State.self) private var state

    static func place(_ pick: Int, in book: TrialBook) -> TrialBook.GoalPlace {
        let c = book.goalPlaceCandidates
        return pick > 0 && c.indices.contains(pick - 1) ? .existing(c[pick - 1].name) : .newJar
    }

    var body: some View {
        let c = state.book.goalPlaceCandidates
        let clean = goal.trimmingCharacters(in: .whitespaces)
        V3FormPick(label: "钱单独放在哪", options: ["新开一个存钱罐"] + c.map { "放进\($0.name)" }, pick: $pick)
        if pick > 0, c.indices.contains(pick - 1) {
            let a = c[pick - 1]
            V3FormPreview(text: "「\(a.name)」里现在的钱，算这个目标已经存的", amount: a.balance.v3)
        } else {
            V3FormPreview(text: "新开一个账户「\(TrialBook.jarName(clean.isEmpty ? "目标" : clean))」，从 0 开始存", amount: "0,00\u{00A0}€")
        }
    }
}

/// 加一个小目标，或者改一个。新加分两步：先填名字和金额，再选钱放哪。
struct V3SmallGoalSheet: View {
    let id: UUID?
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    @State private var due = ""
    @State private var step = 0
    @State private var place = 0
    var body: some View {
        let m = V3Form.amount(amount)
        let ok = m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
        V3SheetBox(width: 560, title: id == nil ? (step == 0 ? "加一个小目标" : "「\(name)」的钱放哪") : "改小目标",
                   primary: id != nil ? "改好" : step == 0 ? "下一步" : "加上", canSave: ok,
                   save: {
                       guard let m else { return }
                       if let gid = id {
                           if state.change("改好了：\(name)", kind: .goal, { try $0.editSmallGoal(gid, name: name, target: m, due: due) }) { state.closeSheet() }
                       } else if step == 0 {
                           withAnimation(.snappy(duration: 0.2)) { step = 1 }
                       } else {
                           let where_ = V3GoalPlacePick.place(place, in: state.book)
                           if state.change("加上了：\(name) \(m.v3Short)", kind: .goal, { try $0.addSmallGoal(name: name, target: m, due: due, place: where_) }) { state.closeSheet() }
                       }
                   },
                   extra: { if id == nil, step == 1 { Button("上一步") { withAnimation(.snappy(duration: 0.2)) { step = 0 } }.buttonStyle(.v3(.ghost)) } }) {
            if step == 0 || id != nil {
                V3FormField(label: "想要什么", prompt: "周末短途旅行", text: $name, focus: true)
                HStack(alignment: .top, spacing: 12) {
                    V3FormField(label: "一共要多少", prompt: "300", text: $amount, big: true)
                    V3FormField(label: "想哪天前存够", prompt: "可不填，比如：明年 3 月前", text: $due)
                }
                V3AmountHint(text: amount)
            } else {
                V3GoalPlacePick(goal: name, pick: $place)
            }
        }
        .onAppear {
            if let id, let g = state.book.smallGoals.first(where: { $0.id == id }) { name = g.name; amount = V3Form.plain(g.target); due = g.due }
            if state.goalSheetStep == 1 { name = "周末看海"; amount = "240"; step = 1; state.goalSheetStep = 0 }
        }
    }
}

/// 忍住了一笔：没买的那样东西和它的钱，存进大目标。默认填你最近最常买的小东西；流水里看不出来就空着。
/// 删一个目标：一次问清里面已经存的钱去哪。
struct V3GoalDeleteSheet: View {
    /// nil 是大目标。
    let id: UUID?
    @Environment(V3State.self) private var state
    @State private var pick = 0

    var body: some View {
        let b = state.book
        let small = id.flatMap { id in b.smallGoals.first { $0.id == id } }
        let name = small?.name ?? b.journey.name
        let saved = small?.saved ?? b.journey.saved
        // 能去的地方：自己的账户在前（默认第一个），然后是别的目标
        let owned = small?.ownsAccount ?? b.bigGoalOwnsAccount
        let home = b.accounts.first { $0.id == (small?.account ?? b.bigGoalAccount) }
        let places: [(title: String, to: TrialBook.GoalMoney)] =
            (owned ? [] : [("留在\(home?.name ?? "原账户")", TrialBook.GoalMoney.stay)])
            + b.goalMoneyAccounts.map { ("放回\($0.name)", TrialBook.GoalMoney.account($0.name)) }
            + (id != nil && b.journey.total > .zero ? [("挪给「\(b.journey.name)」", TrialBook.GoalMoney.bigGoal)] : [])
            + b.smallGoals.filter { $0.id != id }.map { ("挪给「\($0.name)」", TrialBook.GoalMoney.smallGoal($0.id)) }
        let to = places.indices.contains(pick) ? places[pick] : nil
        V3SheetBox(width: 560, title: "删掉「\(name)」", primary: "删掉", danger: true, canSave: saved == .zero || to != nil,
                   save: {
                       let text = saved > .zero ? "已删掉：\(name) · \(saved.v3) \(to?.title ?? "")" : "已删掉：\(name)"
                       let ok = state.change(text, kind: .remove) {
                           if let id { try $0.removeSmallGoal(id, moneyTo: saved > .zero ? to?.to : nil) } else { try $0.removeBigGoal(moneyTo: saved > .zero ? to?.to : nil) }
                       }
                       if ok { state.closeSheet() }
                   }) {
            if saved > .zero {
                V3FormPick(label: "里面存的 \(saved.v3) 放到哪", options: places.map(\.title), pick: $pick)
            } else {
                V3Label("里面还没存钱，删掉不动别的。", size: 14)
            }
        }
    }
}

/// 走完的一条路：点开看那条路和最后那封信。
struct V3FinishedGoalSheet: View {
    let id: UUID
    @Environment(V3State.self) private var state
    var body: some View {
        let f = state.book.finishedGoals.first { $0.id == id }
        let letter = state.book.letters.last
        V3SheetBox(width: 600, title: "\(f?.name ?? "")的路", sub: f.map { "\($0.date)走完 · \($0.total.v3)" } ?? "", primary: "好", single: true, save: { state.closeSheet() }) {
            if let f {
                let stops = [10, 25, 50, 75, 100].map { Money(cents: max(f.total.cents * Int64($0) / 100 / 100 * 100, 100)) }
                V3Road(journey: Journey(name: f.name, stops: stops, saved: f.total), mini: true, markerText: "").frame(height: 250)
                if !f.small, let letter {
                    Button("看最后那封信") { state.closeSheet(); state.openMoment(.letter(letter)) }.buttonStyle(.v3(.ghost, .small))
                }
            }
        }
    }
}

/// 改大目标：名字、一共要存多少。
struct V3GoalEditSheet: View {
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    var body: some View {
        let j = state.book.journey
        let m = V3Form.amount(amount)
        V3SheetBox(width: 520, title: "改大目标", primary: "存好", canSave: m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty,
                   save: {
                       guard let m else { return }
                       if state.change("改好了：\(name) · 一共 \(m.v3)", kind: .goal, { try $0.editBigGoal(name: name, total: m) }) { state.closeSheet() }
                   }) {
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "叫什么", text: $name, focus: true)
                V3FormField(label: "一共要存多少", prompt: "1400", text: $amount).frame(width: 180)
            }
            V3AmountHint(text: amount)
            if let m, m <= j.saved { V3FormPreview(text: "已经存了 \(j.saved.v3)，改成这个数就算存够了。") }
        }
        .onAppear { name = j.name; amount = V3Form.plain(j.total) }
    }
}

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
        V3SheetBox(width: 580, title: "这笔算哪一类", sub: e.map { "\(place) · \($0.amount.v3)" } ?? "", foot: "点图标就选好，不用再点确定。", primary: "不改了", single: true,
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

struct V3SubscriptionSheet: View {
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
        // 能扣订阅的账户都列出来：银行卡、储蓄、信用卡、现金（ming 2026-11-28：有那么多付款的，不能只给两个）
        let accounts = state.book.subscriptionAccounts(.life)
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
                       if state.change("加好了：\(name) \(cyc) \(m.v3)", kind: .subscription, { try $0.addSubscription(name: name, amount: m, note: note, forWork: forWork, cycle: cycle, account: acc, dueIn: nextIn) }) { state.closeSheet() }
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
    @State private var day = 8
    @State private var payFrom = 0

    var body: some View {
        let m = V3Form.amount(amount)
        let n = Int(periods.trimmingCharacters(in: .whitespaces)), done = Int(paid.trimmingCharacters(in: .whitespaces))
        let pay = state.book.accounts(for: .pay, side: .life).filter { $0.kind == .own }
        let each = m.flatMap { m in n.flatMap { $0 > 0 ? Money(cents: m.cents / Int64($0)) : nil } }
        let ok = m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty && (who != 2 || (n != nil && done != nil))
        V3SheetBox(width: 600, title: "记一笔欠款", foot: who == 2 ? "每月要还的会从「能随便花」里先扣掉。" : "借钱和还钱不算花也不算赚。", primary: "记上", canSave: ok,
                   save: {
                       guard let m else { return }
                       let saved: Bool
                       if who == 2, let n, let done {
                           let from = pay.indices.contains(payFrom) ? pay[payFrom].name : ""
                           saved = state.change("记上了：\(name) 分 \(n) 期", kind: .installment) { try $0.addInstallment(name: name, total: m, periods: n, paid: done, day: day, from: from) }
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
                    V3DayPick(label: "每月几号扣", day: $day, last: 28)
                }
                if !pay.isEmpty { V3FormPick(label: "从哪个账户扣", options: pay.map(\.name), pick: $payFrom) }
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
    /// 0 收的钱，1 店里的开销
    @State private var kind = 0
    /// 0 按渠道填，1 只填总数
    @State private var mode = 0
    @State private var texts: [String: String] = [:]
    @State private var whole = ""
    @State private var day = 18
    /// 几天前（0 是今天）。能选往前任何一天，不能选还没到的。
    @State private var daysAgo = 0
    /// 就地加一个渠道：正在起的名字（nil 是没在加）。
    @State private var newChannel: String?
    /// 现在格子里的数是不是从记过的那天填回来的。
    @State private var loaded = false
    // 开销
    @State private var amount = ""
    @State private var what = ""
    @State private var cat = 0
    @State private var account = 0
    @State private var note = ""

    private func text(_ name: String) -> Binding<String> {
        Binding(get: { texts[name] ?? "" }, set: { texts[name] = $0 })
    }

    var body: some View {
        let b = state.book
        let held = Array(b.shopHeld.prefix(6))
        let parsed = held.map { (name: $0.name, amount: V3Form.amountOrZero(texts[$0.name] ?? "")) }
        let bad = mode == 0 ? parsed.contains { $0.amount == nil } : V3Form.amountOrZero(whole) == nil
        let total = mode == 0 ? parsed.compactMap(\.amount).reduce(.zero, +) : (V3Form.amountOrZero(whole) ?? .zero)
        let known = b.shopDays.first { $0.day == day }
        let need = b.dailyBreakEven
        let m = V3Form.amount(amount)
        let pay = b.accounts(for: .pay, side: .biz)
        let cats = TrialBook.shopCategories
        let okIn = !bad && total > .zero
        let okOut = m != nil && pay.indices.contains(account)
        let dateText = QuickDate.label(daysAgo: daysAgo, today: b.todayDate, calendar: Calendar(identifier: .gregorian))
        V3SheetBox(width: 640, title: daysAgo == 0 ? "记今天的账" : "补 \(dateText)的账",
                   foot: kind == 0 && known?.state == .open ? "这天记过了，再记就是改数。" : "", teal: true,
                   canSave: kind == 0 ? okIn : okOut,
                   save: {
                       if kind == 0 {
                           let channels: [TrialBook.ShopChannel] = mode == 0
                               ? parsed.compactMap { p in p.amount.map { TrialBook.ShopChannel(p.name, $0) } }
                               : [TrialBook.ShopChannel(b.usualShopChannel, total)]
                           if state.change("记好了 · \(daysAgo == 0 ? "今天" : dateText)收了 \(total.v3)", kind: .add, { try $0.recordShopIncome(daysAgo: daysAgo, channels: channels) }) { state.closeSheet() }
                       } else if let m, pay.indices.contains(account) {
                           let c = cats[min(cat, cats.count - 1)].name
                           let from = pay[account].name
                           let ago = daysAgo
                           if state.change("记好了 · \(c) \(m.v3)", kind: .add, { try $0.recordShopExpense(name: what, amount: m, category: c, account: from, daysAgo: ago, note: note) }) { state.closeSheet() }
                       }
                   }) {
            V3FormPick(label: "", options: ["收的钱", "店里的开销"], pick: $kind, teal: true)
            if kind == 0 {
                if mode == 0 {
                    // 按收款渠道填：渠道就是店里的账户
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 10) {
                        ForEach(Array(held.enumerated()), id: \.element.id) { i, a in
                            V3FormField(label: "\(a.emoji) \(a.name)", prompt: "0", text: text(a.name), big: held.count <= 2, focus: i == 0)
                        }
                    }
                } else {
                    V3FormField(label: "这天一共收了", prompt: "0", text: $whole, big: true, focus: true)
                }
                if bad { V3Label("这个数我没看懂。写成 74 或者 74,50 这样就行。", color: V3.red, weight: .semibold) }
                HStack(spacing: 8) {
                    V3Chip(text: mode == 0 ? "只填总数" : "按渠道填", size: 12.5) { mode = 1 - mode }
                    if mode == 0, newChannel == nil { V3Chip(text: "+ 加一个渠道", size: 12.5) { newChannel = "" } }
                    // 就地加：起个名字就多一格，已经填的数都还在
                    if mode == 0, let name = newChannel {
                        V3Field(prompt: "渠道叫什么，比如：收款机", text: Binding(get: { name }, set: { newChannel = $0 }), size: 13.5, rounded: true) { addChannel() }
                            .frame(width: 210)
                        Button("加上") { addChannel() }.buttonStyle(.v3(.teal, .small)).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("不加了") { newChannel = nil }.buttonStyle(.v3(.ghost, .small))
                    }
                    Spacer()
                }
                V3FormPreview(text: total >= need ? "这天一共 · 这天不亏了" : "这天一共 · 离不亏还差 \((need - total).v3Short)", amount: total.v3)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    V3FormField(label: "花了多少", prompt: "0,00", text: $amount, big: true, focus: true).frame(width: 190)
                    V3FormField(label: "买的什么", prompt: "可不填，比如：包装纸", text: $what, big: true)
                }
                V3AmountHint(text: amount)
                V3CatGrid(pick: cat, items: cats) { cat = $0 }
                V3FormPick(label: "从店里哪个账户出", options: pay.map(\.name), pick: $account, teal: true)
                V3FormField(label: "备注", prompt: "可不填", text: $note)
            }
            HStack(alignment: .bottom, spacing: 8) {
                V3DatePick(daysAgo: $daysAgo, teal: true)
                if kind == 0 {
                    ForEach(b.shopDays.filter { $0.state == .missing && $0.day < b.todayDay && $0.day != day }.map(\.day), id: \.self) { d in
                        V3Chip(text: "\(d) 号还没记", size: 12.5) { daysAgo = b.todayDay - d }
                    }
                }
                Spacer()
                if kind == 0, day >= 1 {
                    Button("这天休息") {
                        if state.change("记好了 · \(dateText)休息", { try $0.markShopRest(day) }) { state.closeSheet() }
                    }
                    .buttonStyle(.v3(.ghost, .small))
                }
            }
        }
        .onAppear {
            day = start; daysAgo = max(b.todayDay - start, 0); fill()
            if state.shopDayExpense { kind = 1; state.shopDayExpense = false }
            account = pay.firstIndex { $0.name == b.usualFixedAccount } ?? 0
        }
        .onChange(of: daysAgo) { _, v in day = b.todayDay - v; fill() }
    }

    private func addChannel() {
        let name = (newChannel ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if state.change("加好了：\(name)", kind: .account, { try $0.addShopAccount(emoji: "📟", name: name, balance: .zero, owes: false) }) { newChannel = nil }
    }

    private func fill() {
        let b = state.book
        // 换日子：这天记过就把记过的数填回来；没记过的日子，已经填的数留着
        guard let known = b.shopDays.first(where: { $0.day == day }), known.state == .open else {
            // 上一天的数是从记过的账里填回来的，就清掉，别带到这一天
            if loaded { texts = [:]; whole = ""; loaded = false }
            return
        }
        _ = known
        texts = [:]; whole = ""; loaded = true
        if let d = b.shopDays.first(where: { $0.day == day }), d.state == .open {
            for c in b.channels(of: d) { texts[c.account] = V3Form.plain(c.amount) }
            whole = V3Form.plain(d.total)
        }
    }
}

// MARK: - 生意：加一样固定开销

/// 每月几号：1 到 31（或 1 到 28）的小选择器。
struct V3DayPick: View {
    let label: String
    @Binding var day: Int
    var last = 31
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
            Picker(label, selection: $day) {
                ForEach(1...last, id: \.self) { Text("\($0) 日").tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).frame(width: 96, height: 38)
            .accessibilityLabel(label)
        }
    }
}

private struct V3FixedSheet: View {
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    @State private var day = 1
    @State private var account = 0

    var body: some View {
        let b = state.book
        let m = V3Form.amount(amount)
        let pay = b.accounts(for: .pay, side: .biz)
        let ok = m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty && pay.indices.contains(account)
        let after = b.fixedTotal + (m ?? .zero)
        V3SheetBox(width: 560, title: "加一样固定开销", primary: "加好", teal: true, canSave: ok,
                   save: {
                       guard let m, pay.indices.contains(account) else { return }
                       let from = pay[account].name
                       if state.change("加好了：\(name) 每月 \(m.v3)", { try $0.addFixedCost(name: name, amount: m, day: day, account: from) }) { state.closeSheet() }
                   }) {
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "叫什么", prompt: "店面保险", text: $name, focus: true)
                V3FormField(label: "每月多少", prompt: "35,00", text: $amount).frame(width: 150)
                V3DayPick(label: "每月几号付", day: $day)
            }
            V3AmountHint(text: amount)
            V3FormPick(label: "从哪个账户扣", options: pay.map(\.name), pick: $account, teal: true)
            if m != nil {
                V3FormPreview(text: "每月固定要付，从 \(b.fixedTotal.v3Short) 变成", amount: after.v3Short)
            }
        }
        .onAppear { account = pay.firstIndex { $0.name == b.usualFixedAccount } ?? 0 }
    }
}

// MARK: - 生意：进货、盘货、又投了钱（都是「叫什么 + 多少」）

private struct V3SimpleSheet: View {
    enum Kind { case purchase, stock, capital }
    let kind: Kind
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    @State private var account = 0

    var body: some View {
        let m = V3Form.amount(amount)
        let pay = state.book.accounts(for: .pay, side: .biz)
        let shop = pay.indices.contains(account) ? pay[account] : nil
        let short = kind == .purchase && shop?.kind == .shop && (m ?? .zero) > (shop?.balance ?? .zero)
        V3SheetBox(width: 520, title: title, hint: [sub, foot].filter { !$0.isEmpty }.joined(separator: "。"), primary: kind == .stock ? "记下" : "记好", teal: true, canSave: m != nil && !short,
                   save: {
                       guard let m else { return }
                       let ok: Bool
                       switch kind {
                       case .purchase: ok = state.change("记好了 · 进货 \(m.v3)", kind: .add) { try $0.addPurchase(name: name, amount: m, note: "今天", account: shop?.name) }
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
            if kind == .purchase { V3FormPick(label: "从店里哪个账户出", options: pay.map(\.name), pick: $account, teal: true) }
            if short, let shop {
                V3FormPreview(text: "\(shop.name)里只有 \(shop.balance.v3)，不够付这次进货。", good: false)
            } else if kind == .purchase, let m, let shop {
                V3FormPreview(text: shop.kind == .debt ? "\(shop.name)刷完一共欠" : "\(shop.name)付完还剩", amount: (shop.kind == .debt ? shop.balance + m : shop.balance - m).v3)
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
        V3SheetBox(width: 480, title: name, sub: x?.note ?? "", hint: "app 不能替你去退，到日子叫你。", primary: "好了", single: true, save: { state.closeSheet() },
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
    @State private var day = 1
    @State private var account = 0
    var body: some View {
        let x = state.book.fixedCosts.first { $0.name == name }
        let m = V3Form.amount(amount)
        let pay = state.book.accounts(for: .pay, side: .biz)
        let from = pay.indices.contains(account) ? pay[account].name : ""
        let changed = m != x?.amount || day != x?.day || from != x?.account
        V3SheetBox(width: 520, title: name, primary: "存好", teal: true, canSave: m != nil && !from.isEmpty && changed,
                   save: {
                       guard let m else { return }
                       if state.change("改好了：\(name) 每月 \(m.v3)", { try $0.editFixedCost(name, amount: m, day: day, account: from) }) { state.closeSheet() }
                   },
                   extra: {
                       Button("不再付这笔了") {
                           if state.change("拿掉了：\(name)", kind: .remove, { try $0.removeFixedCost(name) }) { state.closeSheet() }
                       }
                       .buttonStyle(.v3(.danger))
                   }) {
            HStack(alignment: .top, spacing: 12) {
                V3FormField(label: "每月多少", prompt: "", text: $amount, big: true, focus: true)
                V3DayPick(label: "每月几号付", day: $day)
            }
            V3AmountHint(text: amount)
            V3FormPick(label: "从哪个账户扣", options: pay.map(\.name), pick: $account, teal: true)
            if let x {
                V3FormSwitch(title: "先停一个月", on: Binding(get: { x.off }, set: { v in
                    state.change(v ? "好，\(name)先停着" : "好，\(name)接着付") { try $0.setFixedCost(name, paused: v) }
                }), teal: true)
            }
        }
        .onAppear {
            guard let x else { return }
            amount = V3Form.plain(x.amount); day = (1...31).contains(x.day) ? x.day : 1
            account = pay.firstIndex { $0.name == x.account } ?? pay.firstIndex { $0.name == state.book.usualFixedAccount } ?? 0
        }
    }
}


/// 给店里加一个账户：现金、银行卡、信用卡、收款机里没结的、储蓄、贷款、欠供应商的，或者自己起名。
struct V3ShopAccountSheet: View {
    @Environment(V3State.self) private var state
    @State private var pick = 0
    @State private var name = ""
    @State private var amount = ""
    @State private var customOwes = 0
    /// 没起名时用的名字：这个名字有人用了就在后面加 2、3…
    static func freeName(_ base: String, taken: [String]) -> String {
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
    static let kinds: [(emoji: String, name: String, owes: Bool)] = [
        ("💶", "店里现金", false), ("🏪", "银行卡", false), ("💳", "信用卡", true), ("🧾", "收款机待结算", false),
        ("🏦", "储蓄", false), ("🏦", "贷款", true), ("📦", "欠供应商的", true), ("🏷", "自己起名", false),
    ]

    var body: some View {
        let k = Self.kinds[pick]
        let custom = pick == Self.kinds.count - 1
        let owes = custom ? customOwes == 1 : k.owes
        let m = V3Form.amountOrZero(amount)
        let useName = name.trimmingCharacters(in: .whitespaces).isEmpty ? (custom ? "" : Self.freeName("店的" + k.name, taken: state.book.accounts.map(\.name))) : name
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
