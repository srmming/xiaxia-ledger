#if os(iOS)
import FinanceCore
import SwiftUI

// 目标：1 个大目标 + 最多 3 个小目标。大目标能删（存的钱回日常卡）。

struct P3GoalsPage: View {
    @Environment(P3State.self) private var state
    @State private var confirmDelete = false
    @State private var smallMenu: TrialBook.SmallGoal?

    var body: some View {
        let b = state.book
        let j = b.journey
        VStack(spacing: 0) {
            P3Header(title: "目标", meButton: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if j.total > .zero { big(j) } else { noBig(b) }
                    HStack {
                        Text("小目标").font(P3.font(17, .heavy)).foregroundStyle(P3.ink)
                        P3Tag(text: "\(b.activeSmallGoals.count) / 3")
                        Spacer()
                    }
                    .padding(.top, 2)
                    ForEach(b.smallGoals) { g in small(g) }
                    if b.canAddSmallGoal {
                        Button { state.sheet = .smallGoal(nil) } label: {
                            Text("+ 加一个小目标").font(P3.font(15, .bold)).foregroundStyle(P3.navy)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(P3.dash, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(P3Sink())
                    }
                    wanted(b)
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .confirmationDialog("删掉大目标「\(j.name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删掉，存的 \(j.saved.p3Short) 回日常卡", role: .destructive) {
                state.change("删掉了大目标：\(j.name)。\(j.saved.p3Short) 回到日常卡", kind: .remove) { try $0.removeBigGoal() }
            }
            Button("算了", role: .cancel) {}
        } message: {
            Text("小目标不动。删错了点提示条上的「撤销」就回来。")
        }
        .confirmationDialog(smallMenu?.name ?? "", isPresented: Binding(get: { smallMenu != nil }, set: { if !$0 { smallMenu = nil } }), titleVisibility: .visible) {
            if let g = smallMenu {
                Button("存一笔") { state.sheet = .save(g.id) }
                Button("设成大目标") { state.change("好，「\(g.name)」现在是大目标", kind: .goal) { try $0.promoteSmallGoal(g.id) } }
                Button("改名字、金额、日子") { state.sheet = .smallGoal(g.id) }
                Button("删掉（存的钱回日常卡）", role: .destructive) { state.change("删掉了：\(g.name)", kind: .remove) { try $0.removeSmallGoal(g.id) } }
            }
        }
    }

    private func big(_ j: Journey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(j.name).font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
                        if !j.why.isEmpty { P3Tag(text: j.why, tone: .gold) }
                    }
                    Spacer()
                    Menu {
                        Button("改每月存多少") { state.sheet = .smallerStep }
                        Button("改名字和金额") { state.sheet = .editBigGoal }
                        Button("删掉这个大目标", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(P3.ink2)
                            .frame(width: 44, height: 36).contentShape(Rectangle())
                    }
                    .accessibilityLabel("更多")
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    P3Label(j.isFinished ? "都存够了" : "这一站还差")
                    Text(j.isFinished ? j.total.p3Short : j.remainingToNext.p3Short).font(P3.num(34, .heavy)).foregroundStyle(P3.gold)
                        .contentTransition(.numericText())
                    Spacer()
                    Text("一共 \(j.saved.p3Short) / \(j.total.p3Short)").font(P3.num(13.5)).foregroundStyle(P3.navy)
                }
                P3Road(journey: j).frame(height: 70)
                if j.monthlyPlan > .zero {
                    Button { state.sheet = .smallerStep } label: {
                        HStack(spacing: 8) {
                            Text("这个月").font(P3.font(13, .bold)).foregroundStyle(P3.ink)
                            P3Bar(fraction: Double(j.savedThisMonth.cents) / Double(j.monthlyPlan.cents), height: 9)
                            Text("\(j.savedThisMonth.p3Short) / \(j.monthlyPlan.p3Short)").font(P3.num(13)).foregroundStyle(P3.navy).fixedSize()
                        }
                    }
                    .buttonStyle(P3Sink(depth: 1))
                    .accessibilityHint("改每月存多少")
                } else {
                    Button("还没定每月存多少 · 定一下") { state.sheet = .smallerStep }.buttonStyle(.p3(.ghost, .small))
                }
                HStack(spacing: 10) {
                    Button("+ 存一笔") { state.sheet = .save(nil) }.buttonStyle(.p3(.primary, .wide))
                    Button("忍住了一笔") { state.sheet = .holdBack }.buttonStyle(.p3(.ghost, .wide))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .p3Sticker()

            if !j.isFinished, j.monthlyPlan > .zero, let m = j.monthsToFinish() {
                P3Bubble(face: "happy", text: "照每月 \(j.monthlyPlan.p3Short) 存，离下一站还差 \(j.remainingToNext.p3Short)，大概 \(m) 个月走完整条路。") {
                    Button("改每月存多少") { state.sheet = .smallerStep }.buttonStyle(.p3(.ghost, .small))
                }
            }
        }
    }

    /// 问夏夏时点了「先放着想想」的东西。空的时候不出现。
    @ViewBuilder private func wanted(_ b: TrialBook) -> some View {
        let waiting = b.wanted.filter { !$0.off }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                P3SectionTitle(title: "先放着想想的", trail: "\(waiting.count) 样")
                ForEach(waiting) { w in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(w.name).font(P3.font(15, .bold)).foregroundStyle(P3.ink)
                            Text(w.note).font(P3.font(12, .regular)).foregroundStyle(P3.ink2)
                        }
                        Spacer()
                        Text(w.amount.p3Short).font(P3.num(15)).foregroundStyle(P3.navy)
                        if b.journey.total > .zero {
                            Button("不要了") { state.change("忍住了：\(w.name)，\(w.amount.p3Short) 存进目标", kind: .goalDeposit) { _ = try $0.resist(wanted: w.id) } }
                                .buttonStyle(.p3(.ghost, .small))
                        }
                    }
                    .frame(minHeight: 48)
                }
            }
            .p3Card(h: 16, v: 12)
        }
    }

    private func noBig(_ b: TrialBook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            P3.face("think").resizable().scaledToFit().frame(height: 70).blendMode(.multiply)
            Text("现在没有大目标").font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
            Text("大目标是最想存够的那一样，每月先给它留一份。").font(P3.font(14, .regular)).foregroundStyle(P3.ink2)
            Button("+ 定一个大目标") { state.sheet = .newBigGoal }.buttonStyle(.p3(.primary, .wide))
            if !b.smallGoals.isEmpty {
                P3Label("或者从小目标里挑一个")
                ForEach(b.smallGoals.prefix(3)) { g in
                    Button("把「\(g.name)」设成大目标") { state.change("好，「\(g.name)」现在是大目标", kind: .goal) { try $0.promoteSmallGoal(g.id) } }
                        .buttonStyle(.p3(.ghost, .small))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .p3Sticker()
    }

    private func small(_ g: TrialBook.SmallGoal) -> some View {
        Button { smallMenu = g } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(g.name).font(P3.font(15.5, .heavy)).foregroundStyle(P3.ink).lineLimit(1)
                    if g.isDone { P3Tag(text: "存够了", tone: .green) }
                    Spacer(minLength: 4)
                    Text("\(g.saved.p3Short) / \(g.target.p3Short)").font(P3.num(14)).foregroundStyle(P3.navy)
                }
                P3Bar(fraction: g.fraction, height: 9)
                if !g.due.isEmpty { Text(g.due).font(P3.font(12, .regular)).foregroundStyle(P3.ink2) }
            }
            .p3Card(h: 16, v: 12, radius: 18)
        }
        .buttonStyle(P3Sink())
        .accessibilityLabel("小目标 \(g.name)，存了 \(g.saved.p3Short)，一共要 \(g.target.p3Short)")
        .accessibilityHint("点开能存一笔、改、删")
    }
}

/// 大目标的路：一站一站，夏夏站在走到的地方。
struct P3Road: View {
    let journey: Journey
    var body: some View {
        let st = journey.stations
        GeometryReader { g in
            let n = max(st.count - 1, 1)
            let w = g.size.width - 30
            let x = { (i: Int) in 15 + w * CGFloat(i) / CGFloat(n) }
            let pos = journey.position
            let here = x(pos.passed) + (pos.passed < n ? (x(pos.passed + 1) - x(pos.passed)) * pos.fraction : 0)
            ZStack(alignment: .topLeading) {
                Capsule().fill(P3.soft).frame(width: w, height: 8).offset(x: 15, y: 26)
                Capsule().fill(P3.navy).frame(width: max(here - 15, 0), height: 8).offset(x: 15, y: 26)
                ForEach(Array(st.enumerated()), id: \.offset) { i, s in
                    let passed = s.target <= journey.saved
                    Circle().fill(passed ? P3.navy : .white).overlay(Circle().strokeBorder(P3.ink, lineWidth: 2))
                        .overlay { if passed { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white) } }
                        .frame(width: 16, height: 16)
                        .position(x: x(i), y: 30)
                    Text(i == 0 ? "出发" : s.target.p3Short.replacingOccurrences(of: "\u{00A0}€", with: ""))
                        .font(P3.num(11.5, i == journey.nextIndex ? .heavy : .semibold))
                        .foregroundStyle(i == journey.nextIndex ? P3.gold : P3.ink2)
                        .fixedSize()
                        .position(x: x(i), y: 54)
                }
                P3.face("happy").resizable().scaledToFit().frame(width: 30, height: 26).blendMode(.multiply)
                    .position(x: here, y: 10)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("一共要存 \(journey.total.p3Short)，存到 \(journey.saved.p3Short) 了，下一站 \(journey.nextStation?.target.p3Short ?? "")")
    }
}

// MARK: - 存一笔

struct P3SaveSheet: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    let smallID: UUID?
    @State private var target: UUID?
    @State private var pick = 20
    @State private var from = "日常卡"

    var body: some View {
        let b = state.book
        let sources = b.accounts(for: .moveOut, side: .life).filter { $0.block != .goal && $0.kind == .own }
        VStack(alignment: .leading, spacing: 16) {
            Text("存一笔").font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
            P3Label("存进哪个")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if b.journey.total > .zero { chip(b.journey.name, on: target == nil) { target = nil } }
                    ForEach(b.smallGoals.filter { !$0.isDone }) { g in chip(g.name, on: target == g.id) { target = g.id } }
                }
            }
            .scrollIndicators(.hidden)
            P3Label("存多少")
            HStack(spacing: 8) {
                ForEach([5, 10, 20, 50], id: \.self) { v in
                    Button { pick = v } label: {
                        Text("\(v) €").font(P3.num(18, .heavy)).foregroundStyle(pick == v ? .white : P3.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pick == v ? P3.navy : .white))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P3.ink, lineWidth: pick == v ? 2 : 0))
                    }
                    .buttonStyle(P3Sink())
                }
            }
            P3Label("从哪拿")
            ScrollView(.horizontal) { HStack(spacing: 6) { ForEach(sources) { a in chip("\(a.name) · \(a.balance.p3Short)", on: from == a.name) { from = a.name } } } }
                .scrollIndicators(.hidden)
            Text(b.savedPhrase(Money(cents: Int64(pick) * 100))).font(P3.font(13.5, .bold)).foregroundStyle(P3.green)
            Spacer(minLength: 0)
            Button("存进去") {
                let m = Money(cents: Int64(pick) * 100)
                let ok: Bool
                if let id = target {
                    let name = b.smallGoals.first { $0.id == id }?.name ?? ""
                    ok = state.change("存好了 +\(m.p3Short) 进「\(name)」", kind: .goalDeposit) { try $0.depositSmall(id, amount: m, from: from) }
                } else {
                    ok = state.deposit(m, from: from)
                }
                if ok { dismiss() }
            }
            .buttonStyle(.p3(.primary, .wide))
        }
        .padding(16).padding(.top, 12)
        .onAppear { target = smallID ?? (b.journey.total > .zero ? nil : b.smallGoals.first?.id) }
        .presentationDetents([.medium])
    }

    private func chip(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(P3.font(13.5, .bold)).foregroundStyle(on ? .white : P3.ink2).lineLimit(1).fixedSize()
                .padding(.horizontal, 14).frame(height: 34).background(Capsule().fill(on ? P3.navy : P3.soft))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 忍住了一笔

struct P3HoldBackSheet: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var what = ""
    @State private var amount = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("忍住了一笔").font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
            Text("没买的那笔钱，从日常卡存进大目标。").font(P3.font(14, .regular)).foregroundStyle(P3.ink2)
            TextField("忍住没买什么，比如「一杯咖啡」", text: $what).p3Field()
            TextField("多少钱", text: $amount).keyboardType(.decimalPad).p3Field()
            if let m = Money(parsing: amount), m > .zero {
                Text(state.book.savedPhrase(m)).font(P3.font(13.5, .bold)).foregroundStyle(P3.green)
            }
            Spacer(minLength: 0)
            Button("存进目标") {
                guard let m = Money(parsing: amount), m > .zero else { state.fail("填一下多少钱"); return }
                let ok = state.change("算你忍住一次 +\(m.p3Short)", kind: .goalDeposit) { _ = try $0.holdBack(name: what, amount: m) }
                if ok { state.starDrops += 1; dismiss() }
            }
            .buttonStyle(.p3(.primary, .wide))
        }
        .padding(16).padding(.top, 12)
        .presentationDetents([.medium])
    }
}

// MARK: - 每月存多少：自己填，或者几选一

struct P3SmallerStepSheet: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""

    var body: some View {
        let j = state.book.journey
        let plan = j.monthlyPlan
        let options = plan > .zero ? Journey.smallerSteps(from: plan) : [Money(cents: 50_00), Money(cents: 100_00), Money(cents: 200_00)]
        VStack(alignment: .leading, spacing: 12) {
            Text(plan > .zero ? "每月存多少？现在是 \(plan.p3Short)" : "每月给「\(j.name)」存多少？").font(P3.font(17, .heavy)).foregroundStyle(P3.ink)
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, s in
                    if i > 0 { P3Divider() }
                    Button { set(s) } label: {
                        VStack(spacing: 2) {
                            Text(plan > .zero ? (i == 0 ? "减半" : "再减半") : s.p3Short).font(P3.font(17, .heavy)).foregroundStyle(P3.ink)
                            Text(months(j, s)).font(P3.font(13, .regular)).foregroundStyle(P3.ink2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60).contentShape(Rectangle())
                    }
                    .buttonStyle(P3Sink(depth: 1))
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(P3.ink, lineWidth: 2)))
            HStack(spacing: 8) {
                TextField("自己填，比如 150", text: $custom).keyboardType(.decimalPad).p3Field()
                Button("就这样") {
                    guard let m = Money(parsing: custom), m > .zero else { state.fail("填一个比 0 大的数"); return }
                    set(m)
                }
                .buttonStyle(.p3(.primary))
            }
            Button("不改了") { dismiss() }.buttonStyle(.p3(.text, .wide))
        }
        .padding(16).padding(.top, 12)
        .presentationDetents([.medium])
    }

    private func set(_ s: Money) {
        if state.change("好，以后每月存 \(s.p3Short)", kind: .goal, { try $0.setMonthlyPlan(s) }) { dismiss() }
    }

    private func months(_ j: Journey, _ s: Money) -> String {
        if let m = j.monthsToFinish(monthly: s) { return "每月 \(s.p3Short)，大概 \(m) 个月走完" }
        return "每月 \(s.p3Short)"
    }
}

// MARK: - 定 / 改一个目标

struct P3GoalEditor: View {
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    let smallID: UUID?
    let big: Bool
    var editBig = false
    @State private var step = 0
    /// 0 是新开存钱罐，后面是已有的「存起来的」账户。
    @State private var place = 0
    @State private var name = ""
    @State private var amount = ""
    @State private var due = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step == 1 ? "「\(name)」的钱单独放在哪" : editBig ? "改大目标" : big ? "定一个大目标" : smallID == nil ? "加一个小目标" : "改小目标").font(P3.font(20, .heavy)).foregroundStyle(P3.ink)
            if step == 0 {
                TextField("想要什么，比如「换新电脑」", text: $name).p3Field()
                TextField("要多少钱", text: $amount).keyboardType(.decimalPad).p3Field()
                if !big { TextField("想哪天前存够（可不填）", text: $due).p3Field() }
            } else {
                placePick
            }
            Spacer(minLength: 0)
            Button(isNew && step == 0 ? "下一步：钱放哪" : big ? "定好了" : "好了") {
                if isNew && step == 0 {
                    guard let m = Money(parsing: amount), m > .zero, !name.trimmingCharacters(in: .whitespaces).isEmpty else { state.fail("先填名字和要多少钱"); return }
                    withAnimation(.snappy(duration: 0.2)) { step = 1 }
                } else { save() }
            }
            .buttonStyle(.p3(.primary, .wide))
            if step == 1 { Button("上一步") { withAnimation { step = 0 } }.buttonStyle(.p3(.text, .wide)) }
        }
        .padding(16).padding(.top, 12)
        .onAppear {
            if editBig {
                let j = state.book.journey
                name = j.name; amount = j.total.formatted.replacingOccurrences(of: " €", with: "").replacingOccurrences(of: ".", with: "")
            }
            if let id = smallID, let g = state.book.smallGoals.first(where: { $0.id == id }) {
                name = g.name; amount = g.target.formatted.replacingOccurrences(of: " €", with: "").replacingOccurrences(of: ".", with: ""); due = g.due
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 新建（不是改）：要走第二步选钱放哪。
    private var isNew: Bool { !editBig && smallID == nil }

    private var placePick: some View {
        let c = state.book.goalPlaceCandidates
        return VStack(alignment: .leading, spacing: 8) {
            Text("目标的钱一定单独放一个账户，不和日常的钱混。").font(P3.font(13.5, .regular)).foregroundStyle(P3.ink2)
            pickRow(0, "新开一个存钱罐", "账户叫「\(TrialBook.jarName(name.trimmingCharacters(in: .whitespaces)))」，从 0 开始存")
            ForEach(Array(c.enumerated()), id: \.element.id) { i, a in
                pickRow(i + 1, "放进「\(a.name)」", "里面现在的 \(a.balance.p3Short) 算这个目标已经存的")
            }
        }
    }

    private func pickRow(_ k: Int, _ title: String, _ note: String) -> some View {
        Button { place = k } label: {
            HStack(spacing: 12) {
                Image(systemName: place == k ? "largecircle.fill.circle" : "circle").font(.system(size: 20)).foregroundStyle(place == k ? P3.navy : P3.dash)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(P3.font(15.5, .bold)).foregroundStyle(P3.ink)
                    Text(note).font(P3.font(12.5, .regular)).foregroundStyle(P3.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(14).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(place == k ? P3.navy : .clear, lineWidth: 2))
        }
        .buttonStyle(P3Sink(depth: 1))
    }

    private var goalPlace: TrialBook.GoalPlace {
        let c = state.book.goalPlaceCandidates
        return place > 0 && c.indices.contains(place - 1) ? .existing(c[place - 1].name) : .newJar
    }

    private func save() {
        guard let m = Money(parsing: amount), m > .zero else { state.fail("填一下要多少钱"); return }
        // 先算好放哪：改账本的那一下里不能再读账本
        let goalPlace = self.goalPlace
        let ok: Bool
        if editBig {
            ok = state.change("改好了：\(name) \(m.p3Short)", kind: .goal) { try $0.editBigGoal(name: name, total: m) }
        } else if big {
            ok = state.change("定好了大目标：\(name) \(m.p3Short)", kind: .goal) { b in
                try b.startGoal(name: name, total: m, place: goalPlace)
            }
        } else if let id = smallID {
            ok = state.change("改好了：\(name)", kind: .goal) { try $0.editSmallGoal(id, name: name, target: m, due: due) }
        } else {
            ok = state.change("加好了小目标：\(name)", kind: .goal) { try $0.addSmallGoal(name: name, target: m, due: due, place: goalPlace) }
        }
        if ok { dismiss() }
    }
}

extension View {
    func p3Field(fill: Color = .white) -> some View {
        font(P3.font(16, .regular)).padding(.horizontal, 14).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
    }
}
#endif
