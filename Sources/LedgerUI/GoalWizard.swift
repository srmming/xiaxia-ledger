import FinanceCore
import SwiftUI

/// 定一个存钱目标：像开场引导一样，一步一页教会用户（ming 2026-11-23）。
/// ① 小小的一步也能实现大大的目标（1 大 3 小）→ ② 想要什么 → ③ 多少钱 → ④ 哪天要（换算成「每天少一杯咖啡」，超出每月剩的给「晚一点更轻松」）
/// → ⑤ 钱真的存在哪（储蓄罐 / 银行卡 / 固定的地方；每次存了都要记）→ ⑥ 大目标还是小目标 → 建好了，金币掉进小猪。
/// 已经有 1 大 3 小：第一页就说「目标不在多，在于坚持」，让用户先完成或删掉一个。
struct GoalWizard: View {
    enum Step: Int, CaseIterable { case intro, what, amount, when, stash, size, done }
    enum When: String, CaseIterable, Identifiable {
        case three = "3 个月", half = "半年", year = "1 年", custom = "自己选", none = "不定"
        var id: String { rawValue }
    }

    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State private var step: Step = .intro
    @State private var name = ""
    @State private var icon: String?
    @State private var amountText = ""
    @State private var when: When = .year
    @State private var customDate = Calendar.current.date(byAdding: .month, value: 9, to: Date()) ?? Date()
    @State private var stash: GoalStash?
    @State private var stashNote = ""
    @State private var main = true
    @State private var createdName = ""
    @State private var drop = 0
    @State private var error: String?
    @State private var confirmDelete: PiggyGoal?

    private var board: GoalBoard { Plans.goalBoard(model.ledger) }
    private var full: Bool { board.slotsLeft == 0 }
    private var amount: Money? {
        guard let m = Money(parsing: amountText.replacingOccurrences(of: " ", with: "")), m.cents != 0 else { return nil }
        return m.magnitude
    }
    private var deadline: LocalDate? {
        let t = LocalDate.today
        switch when {
        case .three: return t.adding(months: 3)
        case .half: return t.adding(months: 6)
        case .year: return t.adding(months: 12)
        case .custom: return LocalDate(customDate)
        case .none: return nil
        }
    }
    private var advice: GoalAdvice? {
        amount.map { Plans.goalAdvice(model.ledger, target: $0, deadline: deadline) }
    }

    var body: some View {
        content
            .navigationTitle(step == .done ? tr("建好了") : tr("定一个存钱目标"))
            .inlineTitle()
            .toolbar {
                if step != .done {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(primaryTitle, action: next)
                        .disabled(!canGoOn)
                        .accessibilityIdentifier("goalWizard.next")
                }
            }
            .onAppear(perform: start)
            .errorAlert($error)
            .confirmationDialog(tr("删掉目标「\(confirmDelete?.name ?? "")」？"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button(tr("删掉"), role: .destructive) {
                    if let p = confirmDelete { model.perform { try $0.removeGoal(p.id, author: model.author) } }
                    confirmDelete = nil
                }
            } message: { Text(tr("在现有账户里划出的存钱记录一起删，账户余额不变。删错了可以撤销。")) }
    }

    // MARK: 版面：左边夏夏和小猪，右边这一步

    private var content: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 600
            Group {
                if wide {
                    HStack(spacing: 0) {
                        side(pig: 150).frame(width: 220)
                        page.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            side(pig: 96).frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            page
                        }
                        .padding(16)
                    }
                }
            }
        }
        .background(Color.cardBackground)
    }

    private func side(pig: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color.kit(0xFFE3EA, 0x3A2830), Color.kit(0xFFF4D6, 0x33301F)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 8) {
                Text(model.xia(speech))
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .id(step)
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                HStack(alignment: .bottom, spacing: -8) {
                    CharacterSlot(pose: step == .done ? .celebrate : .idle, size: pig * 0.62)
                    PiggyBankView(fraction: step == .done ? 0.12 : 0, palette: main ? .main : PiggyPalette.small[0],
                                  size: pig * 0.72, dropTrigger: drop, sparkle: false)
                }
                stepDots
            }
            .padding(14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("\(model.xiaName)说：\(model.xia(speech))"))
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.filter { $0 != .done }, id: \.self) { s in
                Capsule().fill(s == step ? Color.kit(0xD9557A, 0xE86A8E) : Color.fg3.opacity(0.3))
                    .frame(width: s == step ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy, value: step)
    }

    private var speech: String {
        switch step {
        case .intro: full ? tr("目标不在多，在于坚持哦。") : tr("我们一起养一只小金猪吧！")
        case .what: tr("想要什么都可以，大的小的都行。")
        case .amount: tr("大概要多少钱？写个整数就好。")
        case .when: tr("定个日子，我帮你算每天存多少。")
        case .stash: tr("找个真的地方放钱，比如家里的储蓄罐。")
        case .size: tr("最想要的那个，当大目标。")
        case .done: tr("建好啦！第一枚金币什么时候来？")
        }
    }

    @ViewBuilder private var page: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .intro: intro
            case .what: whatPage
            case .amount: amountPage
            case .when: whenPage
            case .stash: stashPage
            case .size: sizePage
            case .done: donePage
            }
            Spacer(minLength: 0)
            if step != .intro && step != .done {
                Button { withAnimation(.snappy) { step = Step(rawValue: step.rawValue - 1) ?? .intro } } label: {
                    Label(tr("返回"), systemImage: "chevron.left")
                }
                .buttonStyle(.borderless).foregroundStyle(Color.fg2)
                .accessibilityIdentifier("goalWizard.back")
            }
        }
        .id(step)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private func title(_ text: String, _ sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            if let sub { Text(sub).font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: ① 开始

    @ViewBuilder private var intro: some View {
        if full {
            title(tr("已经有 1 个大目标、3 个小目标了"), tr("目标不在多，在于坚持。先把一个存够，或者删掉一个不那么想要的，再来定新的。"))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(board.active) { p in
                    HStack(spacing: 10) {
                        Image(systemName: goalSymbol(p)).frame(width: 22).foregroundStyle(Color.fg2)
                        Text(p.name).font(.callout.weight(.medium))
                        if p.isMain { KitTag(text: tr("大目标")) }
                        Spacer(minLength: 8)
                        Text("\(p.forecast.percent)%").font(.caption).foregroundStyle(Color.fg3).monospacedDigit()
                        Button(tr("删掉")) { confirmDelete = p }.buttonStyle(.softAlert)
                    }
                }
            }
            .padding(12)
            .background(Color.sunken.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            title(tr("小小的一步，也能实现大大的目标"), tr("定好想要什么，夏夏帮你算出每天存多少、哪天能到手。"))
            VStack(alignment: .leading, spacing: 12) {
                introRow(1, "target", tr("想好要什么、多少钱、哪天要"))
                introRow(2, "archivebox", tr("准备一个真的存钱的地方：一个储蓄罐、一张银行卡，或者家里一个固定的位置"))
                introRow(3, "hand.tap", tr("每次真的存了钱，就来点一下小猪，记一笔。钱也可以取出来"))
            }
            Label(tr("最多 1 个大目标 + 3 个小目标。目标不在多，在于坚持。"), systemImage: "heart")
                .font(.callout).foregroundStyle(Color.kit(0xB4445C, 0xFF9AB0))
                .padding(10)
                .background(Color.kit(0xF26A86, 0xF26A86, alpha: 0.1, darkAlpha: 0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if board.slotsLeft < Plans.maxActiveGoals {
                Text(tr("现在有 \(board.active.count) 个在存，还能加 \(board.slotsLeft) 个。")).font(.caption).foregroundStyle(Color.fg3)
            }
        }
    }

    private func introRow(_ n: Int, _ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.callout.weight(.bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Color.kit(0xD9557A, 0xE86A8E), in: Circle())
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: ② 想要什么

    @ViewBuilder private var whatPage: some View {
        title(tr("你想要什么？"), tr("挑一个，或者自己写。"))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
            ForEach(GoalIcons.presets, id: \.symbol) { item in
                Button {
                    let wasPreset = name.isEmpty || GoalIcons.presets.contains { $0.name == name }
                    icon = item.symbol
                    if wasPreset { name = item.name }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.title3)
                        Text(item.name).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(icon == item.symbol ? Color.kit(0xB4445C, 0xFF9AB0) : Color.primary)
                    .background(icon == item.symbol ? Color.kit(0xF26A86, 0xF26A86, alpha: 0.14, darkAlpha: 0.22) : Color.sunken.opacity(0.7),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(icon == item.symbol ? .isSelected : [])
            }
        }
        TextField(tr("想要什么"), text: $name, prompt: Text(tr("比如「换新电脑」")))
            .textFieldStyle(.roundedBorder)
            .font(.title3)
            .accessibilityIdentifier("goalWizard.name")
            .onSubmit(next)
    }

    // MARK: ③ 多少钱

    @ViewBuilder private var amountPage: some View {
        title(tr("「\(trimmedName)」要多少钱？"))
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField(tr("要存多少"), text: $amountText, prompt: Text("1.000"))
                .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                .textFieldStyle(.plain)
                .decimalKeyboard()
                .accessibilityIdentifier("goalWizard.amount")
                .onSubmit(next)
            Text("€").font(.title.weight(.semibold)).foregroundStyle(Color.fg2)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        HStack(spacing: 8) {
            ForEach([100, 300, 500, 1000, 2000, 5000], id: \.self) { v in
                Button(Money(cents: Int64(v) * 100).rounded) { amountText = "\(v)" }.buttonStyle(.soft)
            }
        }
        if let room = board.monthlyRoom, room.cents > 0 {
            Text(tr("参考：你最近每月大约剩 \(room.rounded)。")).font(.caption).foregroundStyle(Color.fg3)
        }
    }

    // MARK: ④ 哪天要

    @ViewBuilder private var whenPage: some View {
        title(tr("哪天想要？"), tr("定个日子更容易坚持。不定也行，先按一年算。"))
        Picker(tr("哪天要"), selection: $when) {
            ForEach(When.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("goalWizard.when")
        if when == .custom {
            DatePicker(tr("哪天前存够"), selection: $customDate, in: Date()..., displayedComponents: .date)
        }
        if let a = advice {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tr("每天存")).font(.callout).foregroundStyle(Color.fg2)
                    Text(a.perDay.ui).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Text("≈ \(a.phrase)").font(.headline).foregroundStyle(Color.kit(0xB4445C, 0xFF9AB0))
                Text(tr("也就是每月 \(a.perMonth.rounded)\(deadline.map { tr("，\($0.year) 年 \($0.month) 月 \($0.day) 日到手") } ?? tr("，一年左右到手"))。"))
                    .font(.callout).foregroundStyle(Color.fg2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kit(0xFFF1D6, 0x332A16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if a.tooTight {
                VStack(alignment: .leading, spacing: 8) {
                    Label(a.monthlyRoom.map { tr("每月要存的比你平时剩的（约 \($0.rounded)，再减去别的目标）还多，会很吃力。") } ?? tr("每月要存的有点多，会很吃力。"),
                          systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(Color.warn).fixedSize(horizontal: false, vertical: true)
                    if let later = a.easierDeadline {
                        Button {
                            customDate = later.asDate
                            withAnimation(.snappy) { when = .custom }
                        } label: { Label(tr("晚一点更轻松：改到 \(later.year) 年 \(later.month) 月"), systemImage: "tortoise") }
                            .buttonStyle(.soft)
                            .accessibilityIdentifier("goalWizard.later")
                    }
                }
                .padding(12)
                .background(Color.warnSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: ⑤ 存在哪

    @ViewBuilder private var stashPage: some View {
        title(tr("钱真的存在哪？"), tr("准备一个真的存钱的地方，存进去就不会被顺手花掉。"))
        VStack(spacing: 8) {
            ForEach(GoalStash.allCases) { s in
                optionCard(selected: stash == s, symbol: stashSymbol(s), title: s.label, detail: tr("比如") + s.example) {
                    stash = s
                }
                .accessibilityIdentifier("goalWizard.stash.\(s.rawValue)")
            }
        }
        TextField(tr("具体在哪"), text: $stashNote, prompt: Text(stash.map { tr("具体在哪（可不填），") + $0.example.components(separatedBy: "、").first! } ?? tr("具体在哪（可不填）")))
            .textFieldStyle(.roundedBorder)
        Label(tr("约好了：每次真的存了钱，一定回来点小猪记一笔。不记下来，小猪就不知道你在努力。"), systemImage: "hand.wave")
            .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: ⑥ 大目标还是小目标

    @ViewBuilder private var sizePage: some View {
        let b = board
        let smallFull = b.small.count + b.extra.count >= Plans.maxSmallGoals
        title(tr("这是大目标还是小目标？"), tr("目标不在多，在于坚持。"))
        optionCard(selected: main, symbol: "star.fill", title: tr("大目标"),
                   detail: tr("最想要的那一个，目标页上最大的那只猪。只有 1 个。") + (b.main.map { tr("选它的话，「\($0.name)」会变成小目标。") } ?? "")) {
            main = true
        }
        .accessibilityIdentifier("goalWizard.main")
        optionCard(selected: !main, symbol: "circle.grid.2x1.fill", title: tr("小目标"),
                   detail: smallFull ? tr("小目标已经有 3 个了。") : tr("最多 3 个，排在大目标下面。还能加 \(Plans.maxSmallGoals - b.small.count - b.extra.count) 个。")) {
            main = false
        }
        .disabled(smallFull || b.main == nil)
        .accessibilityIdentifier("goalWizard.small")
        if let a = advice {
            Text(tr("「\(trimmedName)」\(amount?.rounded ?? "")，每天 \(a.perDay.ui)，存在\(stash.map { stashNote.isEmpty ? $0.label : stashNote } ?? tr("你准备的地方"))。"))
                .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 建好了

    @ViewBuilder private var donePage: some View {
        title(tr("「\(createdName)」建好了！"), nil)
        if let p = (board.active + board.done).first(where: { $0.name == createdName }) {
            VStack(alignment: .leading, spacing: 6) {
                if let d = p.perDay { Label(tr("每天存 \(d.ui)，\(board.habit.phrase(perDay: d))"), systemImage: "cup.and.saucer") }
                Label(arrivalText(p), systemImage: "calendar")
                Label(stashText(p), systemImage: stashSymbol(p.stash))
            }
            .font(.callout)
            .labelStyle(PiggyLabelStyle())
        }
        Text(tr("以后每次存了钱，点目标页的小猪「存一笔」；想买咖啡忍住了，就点「忍住了」。钱要用也可以取出来。"))
            .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
        Text(tr("小小的一步，也能实现大大的目标。")).font(.headline).foregroundStyle(Color.kit(0xB4445C, 0xFF9AB0))
    }

    private func optionCard(selected: Bool, symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.title3).frame(width: 28)
                    .foregroundStyle(selected ? Color.kit(0xD9557A, 0xE86A8E) : Color.fg2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.kit(0xD9557A, 0xE86A8E) : Color.fg3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.kit(0xF26A86, 0xF26A86, alpha: 0.1, darkAlpha: 0.18) : Color.sunken.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.kit(0xD9557A, 0xE86A8E) : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(title)，\(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 走下一步

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var primaryTitle: String {
        switch step {
        case .intro: full ? tr("知道了") : tr("开始")
        case .size: tr("放进小猪")
        case .done: tr("好了")
        default: tr("下一步")
        }
    }

    private var canGoOn: Bool {
        switch step {
        case .what: !trimmedName.isEmpty
        case .amount: amount != nil
        case .stash: stash != nil
        default: true
        }
    }

    private func next() {
        guard canGoOn else { return }
        switch step {
        case .intro:
            if full { dismiss(); return }
            go(.what)
        case .what: go(.amount)
        case .amount: go(.when)
        case .when: go(.stash)
        case .stash: go(.size)
        case .size: save()
        case .done: dismiss()
        }
    }

    private func go(_ s: Step) { withAnimation(.snappy) { step = s } }

    private func save() {
        guard let amount else { return }
        let n = trimmedName
        let book = model.selectedBookID ?? model.defaultBookID
        let author = model.author
        let isMain = main || board.main == nil
        let note = stashNote.trimmingCharacters(in: .whitespaces)
        do {
            try model.edit { l in
                try l.addGoal(name: n, bookID: book, target: amount, deadline: deadline, main: isMain,
                              icon: icon ?? GoalIcons.guess(n), stash: stash, stashNote: note.isEmpty ? nil : note, author: author).1
            }
            createdName = n
            go(.done)
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                drop += 1
                PiggySound.drop()
            }
        } catch { self.error = error.localizedDescription }
    }

    /// 打开时：没有大目标就默认是大目标；截图用 -XiaxiaGoalStep when 直接停在某一步（带一个编好的例子）。
    private func start() {
        main = board.main == nil
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-XiaxiaGoalStep"), i + 1 < args.count,
           let s = ["intro": Step.intro, "what": .what, "amount": .amount, "when": .when, "stash": .stash, "size": .size][args[i + 1]] {
            if s.rawValue > Step.what.rawValue { name = tr("换新相机"); icon = "camera" }
            if s.rawValue > Step.amount.rawValue { amountText = "900"; when = .half }
            if s.rawValue > Step.stash.rawValue { stash = .jar; stashNote = tr("书架上的小铁盒") }
            step = s
        }
    }
}

// MARK: - 存一笔 / 取出

struct PiggyMoneyResult {
    var goalID: UUID
    var deposit: Bool
    var amount: Money
    var days: Int?
    var changeID: UUID?
    var heldBack: String?
}

/// 往小猪里存一笔、从小猪里取出。存：钱从一个账户划出来（不算花销）；取：用钱很正常，不责怪，到手日子往后推一点。
struct PiggyMoneySheet: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    let goalID: UUID
    let kind: PiggyMoney.Kind
    var onDone: (PiggyMoneyResult) -> Void
    @State private var amountText = ""
    @State private var accountID = ""
    @State private var date = Date()
    @State private var error: String?

    private var goal: Goal? { model.ledger.goals.first { $0.id == goalID } }
    private var deposit: Bool { kind == .deposit }
    private var amount: Money? {
        guard let m = Money(parsing: amountText.replacingOccurrences(of: " ", with: "")), m.cents != 0 else { return nil }
        return m.magnitude
    }
    private var accounts: [Account] { model.visibleAccounts.filter { $0.id != goal?.savingsAccountID } }

    var body: some View {
        Form {
            Section {
                FormField(deposit ? tr("存多少") : tr("取多少"), tr("比如 20"), text: $amountText)
                    .decimalKeyboard()
                    .accessibilityIdentifier("piggy.amount")
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { v in
                        Button(Money(cents: v).ui) { amountText = Money(cents: v).formatted.replacingOccurrences(of: " €", with: "") }
                            .buttonStyle(.soft)
                    }
                }
                Picker(deposit ? tr("钱从哪个账户来") : tr("取到哪个账户"), selection: $accountID) {
                    if accountID.isEmpty { Text(tr("选一个")).tag("") }
                    ForEach(accounts) { Text($0.name).tag($0.id) }
                }
                DatePicker(tr("哪天"), selection: $date, in: ...Date(), displayedComponents: .date)
            } header: {
                Text(goal?.name ?? "")
            } footer: {
                Text(footer)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(deposit ? tr("往小猪里存一笔") : tr("从小猪里取出"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(deposit ? tr("存进去") : tr("取出来"), action: save)
                    .disabled(amount == nil || accountID.isEmpty)
                    .accessibilityIdentifier("piggy.save")
            }
        }
        .onAppear {
            if accountID.isEmpty {
                let d = model.defaultAccountID
                accountID = accounts.contains { $0.id == d } ? d : accounts.first?.id ?? ""
            }
        }
        .errorAlert($error)
    }

    private var chips: [Int64] {
        var list: [Int64] = [500, 1000, 2000, 5000]
        let habit = Plans.smallHabit(model.ledger).typical.cents
        if !list.contains(habit) { list.insert(habit, at: 0) }
        return Array(list.prefix(5))
    }

    private var footer: String {
        let days = amount.flatMap { Plans.daysEarlier(model.ledger, goalID: goalID, amount: $0) }
        if deposit {
            var s = goal?.savingsAccountID != nil ? tr("从这个账户转进专门存钱的账户，不算花销。") : tr("钱留在这个账户里，只是划给这个目标，账户余额不变、不算花销。")
            if let days { s += tr("存进去，提前 \(days) 天到手。") }
            return s + tr("记得真的把钱放进你准备的地方。")
        }
        var s = tr("要用钱就取出来，很正常，慢慢再补回来。")
        if let days { s += tr("到手的日子会往后推约 \(days) 天。") }
        return s
    }

    private func save() {
        guard let amount, !accountID.isEmpty else { return }
        let days = Plans.daysEarlier(model.ledger, goalID: goalID, amount: amount)
        let account = accountID
        let day = LocalDate(date)
        let author = model.author
        do {
            let change = try model.edit(quiet: true) { l in
                if deposit { return try l.deposit(goalID: goalID, amount: amount, fromAccount: account, date: day, author: author) }
                return try l.withdraw(goalID: goalID, amount: amount, toAccount: account, date: day, author: author)
            }
            dismiss()
            onDone(PiggyMoneyResult(goalID: goalID, deposit: deposit, amount: amount, days: days, changeID: change.id, heldBack: nil))
        } catch { self.error = error.localizedDescription }
    }
}
