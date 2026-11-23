import FinanceCore
import SwiftUI

/// 目标页：小金猪存钱罐（ming 2026-11-23）。
/// 目标 = 把「我想要的东西」变成「哪天能到手」，让人感到小小坚持就有改变。
/// 一个大目标（最大的那只猪）+ 最多 3 个小目标（小猪），旁边是夏夏的一句话、本周小挑战、这个月坚持了哪几天。
/// 存一笔 = 金币掉进小猪；点小猪（iPhone 摇手机）叮叮当当，钱越多声音越满。规则都在 FinanceCore/PiggyBank.swift。
struct PlansPage: View {
    @Environment(LedgerModel.self) var model
    /// iPhone 上分三格：目标 / 订阅 / 欠款（Mac 上这三个各是一页）。
    @State private var tab = 0
    /// 页面能看到多大：窗口矮（1000×612）时小猪小一点，一屏放下。
    @State private var viewport = CGSize(width: 1000, height: 800)
    private var short: Bool { Viewport.isShort(viewport) }

    var body: some View {
        #if os(iOS)
        VStack(spacing: Kit.gap) {
            Picker("看哪个", selection: $tab) {
                Text("目标").tag(0)
                Text("订阅").tag(1)
                Text("欠款").tag(2)
                Text("报销").tag(3)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("plansTab")
            switch tab {
            case 1:
                SubscriptionsXiaxia()
                if model.subscriptionStatus.contains(where: { $0.cancelledOn == nil }) { SubscriptionTotalsStrip() }
                SubscriptionsCard()
                AskAICard(title: "让夏夏帮你找订阅", note: nil, page: "订阅",
                          prompts: [AIPrompt(kind: "订阅", text: "帮我从流水里找出所有订阅，问我哪些是，再写进夏夏账本")])
            case 2:
                DebtsPage(embedded: true)
            case 3:
                ReimbursementPage(embedded: true)
            default:
                PiggyGoalsBoard(short: false)
            }
        }
        .kitPage()
        .onAppear {
            switch model.section {
            case .debts: tab = 2
            case .subscriptions: tab = 1
            case .reimburse: tab = 3
            default: break
            }
        }
        #else
        PiggyGoalsBoard(short: short).kitPage()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        #endif
    }
}

/// 存一笔 / 取出 的面板要哪个目标、哪一种。
struct PiggyMoney: Identifiable, Hashable {
    enum Kind: Hashable { case deposit, withdraw }
    var goalID: UUID
    var kind: Kind
    var id: String { "\(goalID)-\(kind)" }
}

struct PiggyGoalsBoard: View {
    @Environment(LedgerModel.self) var model
    var short = false
    @AppStorage(PiggySound.storageKey) private var soundOn = true
    @State private var drops: [UUID: Int] = [:]
    @State private var shakes: [UUID: Int] = [:]
    /// 刚存进去提前了几天：小猪旁边冒一个「+3 天」。
    @State private var bubbles: [UUID: String] = [:]
    @State private var money: PiggyMoney?
    @State private var confetti = false
    @State private var showDone = false
    @State private var showExtra = false

    private var board: GoalBoard { Plans.goalBoard(model.ledger) }

    var body: some View {
        let b = board
        Group {
            if b.isEmpty {
                emptyState(b)
            } else {
                content(b)
            }
        }
        .overlay {
            if confetti { ConfettiView().allowsHitTesting(false).transition(.opacity) }
        }
        .onShake { if let m = b.main { shake(m) } }
        .sheet(item: $money) { m in
            NavigationStack {
                PiggyMoneySheet(goalID: m.goalID, kind: m.kind) { result in after(result) }
            }
            .environment(model)
            #if os(macOS)
            .frame(width: 460, height: 420)
            #endif
        }
        .sensoryFeedback(.impact(weight: .light), trigger: drops)
    }

    // MARK: 有目标

    @ViewBuilder private func content(_ b: GoalBoard) -> some View {
        VStack(alignment: .leading, spacing: Kit.gap) {
            header(b)
            #if os(iOS)
            PiggyXiaxiaCard(board: b, showExtra: $showExtra)
            if let main = b.main { mainCard(main, b) } else { allDone(b) }
            smallRow(b)
            PiggyChallengeCard(habit: b.habit)
            PiggyMonthCard(board: b)
            #else
            Columns(sideWidth: 320) {
                if let main = b.main { mainCard(main, b) } else { allDone(b) }
                smallRow(b)
            } side: {
                PiggyXiaxiaCard(board: b, showExtra: $showExtra)
                PiggyChallengeCard(habit: b.habit, compact: short)
                PiggyMonthCard(board: b, compact: short)
            }
            #endif
        }
    }

    private func header(_ b: GoalBoard) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("存钱目标").font(.kitSection).accessibilityAddTraits(.isHeader)
            Text(roomLine(b)).font(.caption).foregroundStyle(Color.fg2).lineLimit(1)
            Spacer(minLength: 8)
            Button { soundOn.toggle() } label: {
                Image(systemName: soundOn ? "speaker.wave.2" : "speaker.slash")
            }
            .buttonStyle(.borderless).foregroundStyle(Color.fg2)
            .help(soundOn ? "小猪的声音：开（点一下关掉）" : "小猪的声音：关（点一下打开）")
            .accessibilityLabel(soundOn ? "关掉小猪的声音" : "打开小猪的声音")
            if !b.done.isEmpty {
                Button { showDone = true } label: { Label("已完成 \(b.done.count)", systemImage: "checkmark.seal") }
                    .buttonStyle(.borderless).font(.subheadline)
                    .popover(isPresented: $showDone, arrowEdge: .bottom) { doneList(b.done) }
                    .accessibilityIdentifier("goalsDone")
            }
            Button { model.sheet = .plan } label: { Label("新目标", systemImage: "plus") }
                .buttonStyle(.soft)
                .help(b.slotsLeft > 0 ? "还能加 \(b.slotsLeft) 个目标" : Plans.goalLimitSentence)
                .accessibilityIdentifier("goals.new")
        }
    }

    /// 「你每月大约剩 420 € 可以存 · 1 大 3 小」
    private func roomLine(_ b: GoalBoard) -> String {
        var parts: [String] = []
        if let room = b.monthlyRoom {
            parts.append(room.cents > 0 ? "你每月大约剩 \(room.rounded) 可以存" : "最近几个月花的比赚的多，先从小目标开始")
        }
        parts.append("\(b.main == nil ? 0 : 1) 大 \(b.small.count) 小")
        return parts.joined(separator: " · ")
    }

    private func mainCard(_ p: PiggyGoal, _ b: GoalBoard) -> some View {
        PiggyMainCard(goal: p, habit: b.habit, pigSize: pigSize,
                      drop: drops[p.id, default: 0], shakeCount: shakes[p.id, default: 0], bubble: bubbles[p.id],
                      onShake: { shake(p) },
                      onMoney: { money = PiggyMoney(goalID: p.id, kind: $0) },
                      onHeldBack: { heldBack(p, b.habit) })
    }

    private var pigSize: CGFloat {
        #if os(iOS)
        150
        #else
        short ? 120 : 150
        #endif
    }

    private func smallRow(_ b: GoalBoard) -> some View {
        let slots = Plans.maxSmallGoals
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("小目标").font(.subheadline.weight(.semibold))
                Text("最多 3 个 · 目标不在多，在于坚持").font(.caption).foregroundStyle(Color.fg3).lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(b.small.enumerated()), id: \.element.id) { i, p in
                    PiggySmallTile(goal: p, palette: PiggyPalette.small[i % PiggyPalette.small.count], compact: short,
                                   drop: drops[p.id, default: 0], shakeCount: shakes[p.id, default: 0], bubble: bubbles[p.id],
                                   onShake: { shake(p) }, onMoney: { money = PiggyMoney(goalID: p.id, kind: $0) })
                }
                if b.small.count < slots {
                    ForEach(0..<(slots - b.small.count), id: \.self) { _ in emptySlot(enabled: b.slotsLeft > 0) }
                }
            }
        }
        .kitCard(padding: 14)
    }

    private func emptySlot(enabled: Bool) -> some View {
        Button { model.sheet = .plan } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle").font(.title2).foregroundStyle(Color.fg3)
                Text("加一个小目标").font(.caption).foregroundStyle(Color.fg2)
            }
            .frame(maxWidth: .infinity, minHeight: short ? 96 : 140)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.fg3.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel("加一个小目标")
    }

    private func allDone(_ b: GoalBoard) -> some View {
        HStack(spacing: 16) {
            PiggyBankView(fraction: 1, palette: .done, size: 110, sparkle: false)
            VStack(alignment: .leading, spacing: 4) {
                Text("目标都存够了 🎉").font(.title3.weight(.semibold))
                Text("\(b.done.count) 个目标已经到手。再定一个新的吧，小小的一步也能实现大大的目标。").font(.callout).foregroundStyle(Color.fg2)
                Button { model.sheet = .plan } label: { Label("定一个新目标", systemImage: "plus") }.buttonStyle(.soft)
            }
            Spacer(minLength: 0)
        }
        .kitCard(padding: 20)
    }

    private func doneList(_ done: [PiggyGoal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已经到手的目标").font(.headline)
            ForEach(done) { p in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.income)
                    Text(p.name).font(.callout)
                    Spacer(minLength: 12)
                    Text(p.forecast.target.rounded).font(.kitAmount)
                    PiggyGoalMenu(goal: p, onMoney: { money = PiggyMoney(goalID: p.id, kind: $0) })
                }
            }
        }
        .padding(16)
        .frame(minWidth: 280)
    }

    // MARK: 没有目标

    private func emptyState(_ b: GoalBoard) -> some View {
        VStack(spacing: Kit.gap) {
            VStack(spacing: 14) {
                PiggyBankView(fraction: 0, size: 170, sparkle: false)
                Text("还没有存钱目标").font(.title3.weight(.semibold))
                Text("想要的东西，定个数、定个日子，夏夏帮你算出每天存多少、哪天能到手。\n准备一个真的存钱的地方，每次存了钱就来喂一下小猪。小小的一步，也能实现大大的目标。")
                    .font(.callout).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Button { model.sheet = .plan } label: { Label("定第一个目标", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("goals.first")
                if let room = b.monthlyRoom, room.cents > 0 {
                    Text("你最近每月大约剩 \(room.rounded)").font(.caption).foregroundStyle(Color.fg3)
                }
            }
            .frame(maxWidth: .infinity)
            .kitCard(padding: 24)
            AskAICard(title: "也可以跟夏夏说", note: nil, page: "目标", prompts: model.prompts(for: .plans))
        }
    }

    // MARK: 动作

    private func shake(_ p: PiggyGoal) {
        shakes[p.id, default: 0] += 1
        PiggySound.shake(fraction: Double(p.forecast.percent) / 100)
    }

    /// 「忍住了」：常买的小东西的钱，点一下进小猪。
    private func heldBack(_ p: PiggyGoal, _ habit: SmallHabit) {
        let goal = model.ledger.goals.first { $0.id == p.id }
        guard let from = model.visibleAccounts.first(where: { $0.id != goal?.savingsAccountID })?.id ?? model.visibleAccounts.first?.id else {
            model.toast = LedgerModel.Toast(text: "先加一个账户，存的钱从那里划出来", changeID: nil, isError: true)
            return
        }
        let preferred = model.defaultAccountID != goal?.savingsAccountID && !model.defaultAccountID.isEmpty ? model.defaultAccountID : from
        let amount = habit.typical
        let days = Plans.daysEarlier(model.ledger, goalID: p.id, amount: amount)
        do {
            let change = try model.edit(quiet: true) { l in
                try l.deposit(goalID: p.id, amount: amount, fromAccount: preferred, date: .today, heldBack: habit.name, author: model.author)
            }
            after(.init(goalID: p.id, deposit: true, amount: amount, days: days, changeID: change.id, heldBack: habit.name))
        } catch {
            model.toast = LedgerModel.Toast(text: error.localizedDescription, changeID: nil, isError: true)
        }
    }

    /// 存完、取完：金币掉进去、冒「+3 天」、提示；存够了撒花。
    private func after(_ r: PiggyMoneyResult) {
        let finished = Plans.goalBoard(model.ledger).done.contains { $0.id == r.goalID }
        let name = model.ledger.goals.first { $0.id == r.goalID }?.name ?? ""
        if r.deposit {
            drops[r.goalID, default: 0] += 1
            PiggySound.drop()
            if let d = r.days { flash(r.goalID, "+\(d) 天") }
        } else if let d = r.days {
            flash(r.goalID, "−\(d) 天")
        }
        var text: String
        if finished && r.deposit {
            text = "「\(name)」存够了！到手啦 🎉"
            withAnimation { confetti = true }
            Task { try? await Task.sleep(for: .seconds(4)); withAnimation { confetti = false } }
        } else if r.deposit {
            text = (r.heldBack.map { "忍住了「\($0)」，" } ?? "") + "往「\(name)」存了 \(r.amount.rounded)"
            if let d = r.days { text += "，提前 \(d) 天到手" }
        } else {
            text = "从「\(name)」取出 \(r.amount.rounded)" + (r.days.map { "，到手往后推约 \($0) 天" } ?? "") + "。用钱很正常，慢慢补回来就好"
        }
        model.toast = LedgerModel.Toast(text: text, changeID: r.changeID)
    }

    private func flash(_ id: UUID, _ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { bubbles[id] = text }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.3)) { if bubbles[id] == text { bubbles[id] = nil } }
        }
    }
}

// MARK: - 大目标

struct PiggyMainCard: View {
    @Environment(LedgerModel.self) var model
    let goal: PiggyGoal
    let habit: SmallHabit
    var pigSize: CGFloat
    var drop: Int
    var shakeCount: Int
    var bubble: String?
    var onShake: () -> Void
    var onMoney: (PiggyMoney.Kind) -> Void
    var onHeldBack: () -> Void

    var body: some View {
        let p = goal
        let f = p.forecast
        Group {
            #if os(iOS)
            VStack(alignment: .leading, spacing: 12) {
                pig(p).frame(maxWidth: .infinity)
                details(p, f)
            }
            #else
            // Mac：小猪放左边、名字和「还差」放右边，下面整行写日子和按钮——一屏放得下小目标
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    pig(p)
                    VStack(alignment: .leading, spacing: 8) {
                        titleRow(p, f)
                        amountRow(f, savedInline: false)
                        PiggyProgress(fraction: Double(f.percent) / 100)
                        Text("已存 \(f.saved.rounded) / \(f.target.rounded) · \(f.percent)%").font(.caption).foregroundStyle(Color.fg3).lineLimit(1)
                    }
                }
                infoLines(p)
                buttons(p)
            }
            #endif
        }
        .kitCard(padding: 18)
        .accessibilityElement(children: .contain)
    }

    private func pig(_ p: PiggyGoal) -> some View {
        VStack(spacing: 4) {
            Button(action: onShake) {
                PiggyBankView(fraction: Double(p.forecast.percent) / 100, palette: .main, size: pigSize,
                              dropTrigger: drop, shakeTrigger: shakeCount)
                    .overlay(alignment: .topTrailing) { PiggyBubble(text: bubble) }
            }
            .buttonStyle(.plain)
            .help("点一下，摇一摇小猪")
            .accessibilityLabel("小金猪，\(p.name)已经存了 \(p.forecast.percent)%")
            .accessibilityHint("摇一摇，听听里面的钱")
            .accessibilityIdentifier("goals.mainPig")
            #if os(iOS)
            Text("摇一摇手机，听听小猪里的钱").font(.caption2).foregroundStyle(Color.fg3)
            #else
            Text("点小猪摇一摇").font(.caption2).foregroundStyle(Color.fg3)
            #endif
        }
        .fixedSize()
    }

    private func details(_ p: PiggyGoal, _ f: GoalForecast) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            titleRow(p, f)
            amountRow(f, savedInline: true)
            PiggyProgress(fraction: Double(f.percent) / 100)
            infoLines(p)
            buttons(p)
        }
    }

    private func titleRow(_ p: PiggyGoal, _ f: GoalForecast) -> some View {
        HStack(spacing: 8) {
            GoalIconBadge(symbol: goalSymbol(p), color: Color.kit(0xE07A90, 0xF08AA0))
            Text(p.name).font(.title3.weight(.semibold)).lineLimit(1)
            KitTag(text: "大目标", color: Color.kit(0xB4445C, 0xFF9AB0), background: Color.kit(0xF26A86, 0xF26A86, alpha: 0.12, darkAlpha: 0.2))
            if f.locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(Color.fg3).accessibilityLabel("锁定的") }
            Spacer(minLength: 0)
            PiggyGoalMenu(goal: p, onMoney: onMoney)
        }
    }

    private func amountRow(_ f: GoalForecast, savedInline: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(f.left.cents > 0 ? "还差" : "存够了").font(.callout).foregroundStyle(Color.fg2)
            Text(f.left.cents > 0 ? f.left.rounded : f.target.rounded)
                .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            if savedInline {
                Text("已存 \(f.saved.rounded) / \(f.target.rounded)").font(.caption).foregroundStyle(Color.fg3).lineLimit(1)
            }
        }
    }

    private func infoLines(_ p: PiggyGoal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label { Text(arrivalText(p)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "calendar") }
            if let d = p.perDay {
                Label { Text("每天存 \(d.ui)，\(habit.phrase(perDay: d))") } icon: { Image(systemName: "cup.and.saucer") }
            }
            Label { Text(stashText(p)).foregroundStyle(p.stash == nil ? Color.warn : Color.primary) } icon: { Image(systemName: stashSymbol(p.stash)) }
        }
        .font(.callout)
        .labelStyle(PiggyLabelStyle())
    }

    private func buttons(_ p: PiggyGoal) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { depositButton; heldBackButton; withdrawButton }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { depositButton; withdrawButton }
                heldBackButton
            }
        }
        .disabled(p.forecast.isDone)
    }

    private var depositButton: some View {
        Button { onMoney(.deposit) } label: { Label("存一笔", systemImage: "plus.circle.fill") }
            .buttonStyle(.borderedProminent)
            .tint(Color.kit(0xD9557A, 0xE86A8E))
            .accessibilityIdentifier("goals.deposit")
    }

    private var heldBackButton: some View {
        Button(action: onHeldBack) {
            Label("忍住了\(habit.isGuess ? habit.name : "「\(habit.name)」") +\(habit.typical.ui)", systemImage: "hand.raised")
                .lineLimit(1)
        }
        .buttonStyle(.soft)
        .help("想买\(habit.name)的时候忍住了？点一下，这笔钱直接进小猪")
        .accessibilityIdentifier("goals.heldBack")
    }

    private var withdrawButton: some View {
        Button { onMoney(.withdraw) } label: { Label("取出", systemImage: "arrow.uturn.up") }
            .buttonStyle(.soft)
            .disabled(goal.forecast.locked)
            .help(goal.forecast.locked ? "锁定的目标到期前不能取" : "要用钱就取出来，到手日子会往后推一点")
    }
}

// MARK: - 小目标

struct PiggySmallTile: View {
    let goal: PiggyGoal
    var palette: PiggyPalette
    var compact = false
    var drop: Int
    var shakeCount: Int
    var bubble: String?
    var onShake: () -> Void
    var onMoney: (PiggyMoney.Kind) -> Void

    var body: some View {
        let p = goal
        let f = p.forecast
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: goalSymbol(p)).font(.caption).foregroundStyle(palette.dark)
                Text(p.name).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                PiggyGoalMenu(goal: p, onMoney: onMoney)
            }
            Button(action: onShake) {
                PiggyBankView(fraction: Double(f.percent) / 100, palette: palette, size: compact ? 64 : 84,
                              dropTrigger: drop, shakeTrigger: shakeCount, sparkle: false)
                    .overlay(alignment: .topTrailing) { PiggyBubble(text: bubble) }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(p.name)的小猪，已经存了 \(f.percent)%")
            .accessibilityHint("摇一摇")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(f.left.cents > 0 ? "还差 \(f.left.rounded)" : "存够了").font(.kitAmount).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(f.percent)%").font(.caption2.weight(.semibold)).foregroundStyle(Color.fg3).monospacedDigit()
            }
            HStack(spacing: 4) {
                Text(note(p)).font(.caption2).foregroundStyle(p.needsCheck ? Color.warn : Color.fg2).lineLimit(1)
                Spacer(minLength: 0)
                Button { onMoney(.deposit) } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .buttonStyle(.borderless).foregroundStyle(palette.dark)
                    .help("往「\(p.name)」存一笔")
                    .accessibilityLabel("往\(p.name)存一笔")
                    .disabled(f.isDone)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sunken.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func note(_ p: PiggyGoal) -> String {
        if p.needsCheck { return "\(p.idleDays) 天没存了" }
        if let a = p.arrival { return "\(a.year % 100) 年 \(a.month) 月 \(a.day) 日到手" }
        return "最近没在存"
    }
}

// MARK: - 右边：夏夏、小挑战、这个月

/// 夏夏的一句话。很久没存的目标优先：问「它对你还重要吗？」给三个按钮。
struct PiggyXiaxiaCard: View {
    @Environment(LedgerModel.self) var model
    let board: GoalBoard
    @Binding var showExtra: Bool
    @State private var confirmDelete: PiggyGoal?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MascotView(.xiaxia, pose: pose, size: 44, face: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(sentence).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let p = board.needsCheck {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { checkButtons(p) }
                        VStack(alignment: .leading, spacing: 6) { checkButtons(p) }
                    }
                } else if !board.extra.isEmpty {
                    Button { showExtra = true } label: { Text("看看多出来的 \(board.extra.count) 个") }
                        .buttonStyle(.soft)
                        .popover(isPresented: $showExtra, arrowEdge: .bottom) { extraList }
                }
            }
            Spacer(minLength: 0)
        }
        .kitCard(padding: 14)
        .confirmationDialog("删掉目标「\(confirmDelete?.name ?? "")」？", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                if let p = confirmDelete { model.perform { try $0.removeGoal(p.id, author: model.author) } }
                confirmDelete = nil
            }
        } message: { Text("存过的钱不会丢：在现有账户里划出的记录一起删，账户余额不变。删错了可以撤销。") }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func checkButtons(_ p: PiggyGoal) -> some View {
        Button("还重要，继续") { model.perform { try $0.keepGoal(p.id, pause: false, author: model.author) } }
            .buttonStyle(.soft).accessibilityIdentifier("goals.keep")
        Button("先放一放") { model.perform { try $0.keepGoal(p.id, pause: true, author: model.author) } }
            .buttonStyle(.soft)
        Button("删掉") { confirmDelete = p }
            .buttonStyle(.softAlert)
    }

    private var pose: MascotPose {
        if board.needsCheck != nil { return .think }
        if !board.extra.isEmpty { return .think }
        return .cheer
    }

    private var sentence: String {
        if let p = board.needsCheck {
            return model.voiced("「\(p.name)」已经 \(p.idleDays) 天没投币了。这个目标你很久没动了，它对你还重要吗？", .neutral)
        }
        if !board.extra.isEmpty {
            return model.voiced("现在有 \(board.active.count) 个目标，比 1 个大目标 + 3 个小目标多了 \(board.extra.count) 个。目标不在多，在于坚持：挑出最想要的，其它的先完成或删掉。", .neutral)
        }
        guard let m = board.main else { return model.voiced("目标都存够了，真棒。再定一个吧。", .good) }
        let (count, saved) = board.monthHeldBack
        var s = "「\(m.name)」"
        if let a = m.arrival { s += "照现在的存法 \(a.year) 年 \(a.month) 月 \(a.day) 日到手。" } else { s += "最近没在存，存一笔就能算出哪天到手。" }
        if count > 0 { s += "这个月忍住了 \(count) 次，攒下 \(saved.rounded)。" }
        s += "小小的一步也能实现大大的目标。"
        return model.voiced(s, .good)
    }

    private var extraList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("多出来的目标").font(.headline)
            Text("先完成或删掉，留下最想要的 1 个大目标、3 个小目标。").font(.caption).foregroundStyle(Color.fg2)
            ForEach(board.extra) { p in
                HStack(spacing: 10) {
                    Text(p.name).font(.callout)
                    Spacer(minLength: 12)
                    Text("还差 \(p.forecast.left.rounded)").font(.kitAmount)
                    PiggyGoalMenu(goal: p, onMoney: { _ in })
                }
            }
        }
        .padding(16)
        .frame(minWidth: 300)
    }
}

/// 本周小挑战：上周最常买的小东西，这周少一次。
struct PiggyChallengeCard: View {
    let habit: SmallHabit
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered").foregroundStyle(Color.brand)
                Text("本周小挑战").font(.subheadline.weight(.semibold))
            }
            if let limit = habit.challengeLimit {
                Text("上周「\(habit.name)」买了 \(habit.lastWeek) 次，这周少一次：不超过 \(limit) 次。")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    ForEach(0..<max(limit, habit.thisWeek), id: \.self) { i in
                        Circle()
                            .fill(i < habit.thisWeek ? (i < limit ? Color.warn : Color.alert) : Color.sunken)
                            .overlay(Circle().stroke(Color.fg3.opacity(0.3), lineWidth: 0.5))
                            .frame(width: 12, height: 12)
                    }
                    Text(status(limit)).font(.caption).foregroundStyle(habit.thisWeek > limit ? Color.alert : Color.fg2).padding(.leading, 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("这周已经 \(habit.thisWeek) 次，\(status(limit))")
            } else {
                Text("想买\(habit.isGuess ? habit.name : "「\(habit.name)」")的时候忍一下，点「忍住了」，这笔钱直接进小猪。")
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kitCard(padding: compact ? 12 : 14)
    }

    private func status(_ limit: Int) -> String {
        if habit.thisWeek > limit { return "超了一点，没关系，下周再来" }
        if habit.thisWeek == limit { return "到了，这周就到这儿" }
        return "这周 \(habit.thisWeek) 次，还能 \(limit - habit.thisWeek) 次"
    }
}

/// 这个月：小日历点亮投过币的日子 + 忍住了几次、省了多少、提前几天。
struct PiggyMonthCard: View {
    let board: GoalBoard
    var compact = false

    var body: some View {
        let today = board.today
        let days = LocalDate.daysIn(today.yearMonth)
        let first = LocalDate(year: today.year, month: today.month, day: 1).weekdayIndex
        let lit = board.monthDepositDays
        let held = board.monthHeldBack
        let earlier = (board.active + board.done).reduce(0) { $0 + $1.heldBackDays }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Color.warn)
                Text("\(today.month) 月坚持了 \(lit.count) 天").font(.subheadline.weight(.semibold))
            }
            let cell: CGFloat = compact ? 14 : 18
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 4), count: 7), alignment: .leading, spacing: 4) {
                ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { _, w in
                    Text(w).font(.system(size: cell * 0.55)).foregroundStyle(Color.fg3).frame(width: cell, height: cell * 0.8)
                }
                ForEach(0..<(first + days), id: \.self) { i in
                    if i < first {
                        Color.clear.frame(width: cell, height: cell)
                    } else {
                        let d = i - first + 1
                        ZStack {
                            Circle().fill(lit.contains(d) ? Color.kit(0xF2B33D, 0xFFC94D) : Color.sunken)
                            if d == today.day { Circle().stroke(Color.brand, lineWidth: 1.5) }
                            if lit.contains(d) { Text("€").font(.system(size: cell * 0.5, weight: .bold, design: .rounded)).foregroundStyle(Color.kit(0x8A5A00, 0x5A3A00)) }
                        }
                        .frame(width: cell, height: cell)
                        .opacity(d > today.day ? 0.45 : 1)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("这个月有 \(lit.count) 天投了币")
            Text(summary(count: held.count, saved: held.saved, earlier: earlier))
                .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kitCard(padding: compact ? 12 : 14)
    }

    private func summary(count: Int, saved: Money, earlier: Int) -> String {
        if count > 0 {
            var s = "忍住 \(count) 次，省下 \(saved.rounded)"
            if earlier > 0, let m = board.main { s += "，「\(m.name)」提前 \(earlier >= 14 ? "\(earlier / 7) 周" : "\(earlier) 天")" }
            return s + "。"
        }
        return board.monthDepositDays.isEmpty ? "这个月还没投币，今天来一枚？" : "每投一次币，这里亮一格。"
    }
}

// MARK: - 小零件

/// 小猪头上冒的「+3 天」。
struct PiggyBubble: View {
    var text: String?
    var body: some View {
        if let text {
            Text(text)
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.kit(0xD9557A, 0xE86A8E), in: Capsule())
                .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                .offset(y: -6)
        }
    }
}

/// 粗进度条。
struct PiggyProgress: View {
    var fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.sunken)
                Capsule().fill(LinearGradient(colors: [Color.kit(0xF6A5B5, 0xE88DA0), Color.kit(0xF2B33D, 0xFFC94D)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

struct GoalIconBadge: View {
    var symbol: String
    var color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(color.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

/// 图标和文字之间留一样宽，几行对齐。
struct PiggyLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            configuration.icon.foregroundStyle(Color.fg3).frame(width: 18)
            configuration.title
        }
    }
}

/// 目标右上角的「⋯」：存一笔、取出、设成大目标、钱存在哪、改、删。
struct PiggyGoalMenu: View {
    @Environment(LedgerModel.self) var model
    let goal: PiggyGoal
    var onMoney: (PiggyMoney.Kind) -> Void
    @State private var confirmDelete = false
    @State private var editing: Goal?

    var body: some View {
        Menu {
            if !goal.forecast.isDone {
                Button { onMoney(.deposit) } label: { Label("存一笔…", systemImage: "plus.circle") }
            }
            if !goal.forecast.locked && goal.forecast.saved.cents > 0 {
                Button { onMoney(.withdraw) } label: { Label("取出…", systemImage: "arrow.uturn.up") }
            }
            if !goal.isMain && !goal.forecast.isDone {
                Button { model.perform { try $0.setMainGoal(goal.id, author: model.author) } } label: {
                    Label("设成大目标", systemImage: "star")
                }
            }
            if let g = model.ledger.goals.first(where: { $0.id == goal.id }) {
                Button { editing = g } label: { Label("改名字、金额、存在哪…", systemImage: "pencil") }
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("删掉…", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(Color.fg2)
        }
        .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        .accessibilityLabel("\(goal.name) 的操作")
        .confirmationDialog("删掉目标「\(goal.name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删掉", role: .destructive) { model.perform { try $0.removeGoal(goal.id, author: model.author) } }
        } message: { Text("在现有账户里划出的存钱记录一起删，账户余额不变。删错了可以撤销。") }
        .sheet(item: $editing) { g in
            NavigationStack { GoalEditor(goal: g) }
                .environment(model)
                #if os(macOS)
                .frame(width: 460, height: 480)
                #endif
        }
    }
}

/// 目标的图标：挑过的用挑的，没挑过按名字猜。
func goalSymbol(_ p: PiggyGoal) -> String { p.icon ?? GoalIcons.guess(p.name) }

func stashSymbol(_ s: GoalStash?) -> String {
    switch s {
    case .jar: "archivebox"
    case .card: "creditcard"
    case .spot: "mappin.and.ellipse"
    case nil: "questionmark.circle"
    }
}

func stashText(_ p: PiggyGoal) -> String {
    guard let s = p.stash else { return "还没记钱存在哪：点 ⋯ 记一下" }
    return "存在：" + (p.stashNote ?? s.label)
}

func arrivalText(_ p: PiggyGoal) -> String {
    let f = p.forecast
    if f.isDone { return "已经存够了 🎉" }
    if let a = p.arrival {
        var s = "\(a.year) 年 \(a.month) 月 \(a.day) 日到手"
        if let due = f.deadline, a > due {
            let late = due.days(until: a)
            s += "，比定的晚 \(late >= 45 ? "\(late / 30) 个月" : "\(late) 天")"
        } else if f.deadline != nil, f.monthlyPace.cents > 0 {
            s += "，赶得上"
        }
        return s
    }
    if let due = f.deadline, due < .today { return "定的 \(due.year) 年 \(due.month) 月已经过了，改个日子吧" }
    return "最近没在存，存一笔就能算出哪天到手"
}

/// 目标图标：引导第一步给的几个，加上按名字猜。
enum GoalIcons {
    struct Preset: Hashable { var symbol: String; var name: String }
    static let presets: [Preset] = [
        Preset(symbol: "laptopcomputer", name: "换新电脑"), Preset(symbol: "airplane", name: "去旅行"),
        Preset(symbol: "cross.case", name: "应急金"), Preset(symbol: "gift", name: "给家人的礼物"),
        Preset(symbol: "iphone", name: "换手机"), Preset(symbol: "house", name: "买房首付"),
        Preset(symbol: "car", name: "买车"), Preset(symbol: "graduationcap", name: "学习充电"),
        Preset(symbol: "camera", name: "相机"), Preset(symbol: "gamecontroller", name: "游戏机"),
        Preset(symbol: "bicycle", name: "自行车"), Preset(symbol: "star", name: "一个心愿"),
    ]

    static func guess(_ name: String) -> String {
        let n = name.lowercased()
        let rules: [([String], String)] = [
            (["电脑", "laptop", "mac"], "laptopcomputer"), (["旅", "机票", "度假"], "airplane"), (["应急", "备用"], "cross.case"),
            (["礼物", "生日"], "gift"), (["手机", "iphone"], "iphone"), (["房", "首付"], "house"), (["车"], "car"),
            (["学", "课"], "graduationcap"), (["相机"], "camera"), (["游戏", "switch"], "gamecontroller"),
            (["店", "装修"], "storefront"), (["锁", "存钱罐"], "lock.shield"), (["宝宝", "孩子"], "figure.and.child.holdinghands"),
        ]
        for (keys, symbol) in rules where keys.contains(where: { n.contains($0) }) { return symbol }
        return "star"
    }
}
