#if os(macOS)
import FinanceCore
import SwiftUI

// 目标的三个时刻：连上 AI 后定第一步、快到不了时把步子改小、到站时的一封信。

enum V3Moment: Equatable {
    case smallerStep
    case letter(V3State.Letter)
}

extension V3State {
    func openMoment(_ m: V3Moment) { withAnimation(.snappy(duration: 0.28)) { moment = m } }
    func closeMoment() { withAnimation(.snappy(duration: 0.22)) { moment = nil } }

    /// 存一笔；刚好到站就先让星星掉完，再把信拿出来。
    @discardableResult
    func depositAndCelebrate(_ amount: Money = Money(cents: 20_00), from: String? = nil, resisted: Bool = false) -> Bool {
        let before = book.journey.saved
        let reached = deposit(amount, from: from, resisted: resisted)
        celebrate(reached)
        return book.journey.saved != before
    }

    /// 想要清单里忍住一样：钱存进目标。
    func resist(wanted w: TrialBook.Item) {
        var reached: [Journey.Station] = []
        let ok = change("算你忍住一次 +\(w.amount.v3Short)", kind: .goalDeposit) { b in
            reached = try b.resist(wanted: w.id)
            if let i = b.accounts.firstIndex(where: { $0.id == b.bigGoalAccount }) { b.accounts[i].note = Self.goalNote(b.journey) }
        }
        if ok { starDrops += 1; celebrate(reached) }
    }

    func celebrate(_ reached: [Journey.Station]) {
        guard let st = reached.last else { return }
        let letter = arrivalLetter(for: st)
        patch { $0.letters.append(letter) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.9))
            self?.openMoment(.letter(letter))
        }
    }

    /// 到站的信。正式版由连着的 AI 写；试用版先用这封按你自己的数字拼出来的。
    func arrivalLetter(for st: Journey.Station) -> Letter {
        let j = book.journey
        let index = j.stations.firstIndex(of: st) ?? 0
        let isEnd = index == j.stations.count - 1
        let half = st.title.isEmpty ? "" : " · \(st.title)"
        var body = ["小满："]
        if wish.isEmpty {
            body.append("九月我们定了眼前的一步：\(j.name)，\(j.why.replacingOccurrences(of: "为了", with: ""))。那天定的第一步只有 50 块。")
        } else {
            body.append("九月你写过一句：\(wish)。后来我们把它变成了眼前的一步：\(j.name)，\(j.why.replacingOccurrences(of: "为了", with: ""))。那天定的第一步只有 50 块。")
        }
        var middle = "到今天是 76 天。你忍住了 \(j.resisted) 杯 Café Nube"
        middle += j.monthlyPlan < Money(cents: 200_00) ? "，进账少的那个月把步子改成了 \(j.monthlyPlan.v3Short.replacingOccurrences(of: "\u{00A0}€", with: ""))，也没有停。" : "，一次也没有断。"
        body.append(middle)
        body.append(isEnd ? "\(st.target.v3Short.replacingOccurrences(of: "\u{00A0}€", with: "")) 了，全走完了。去把它带回家吧。"
                    : "\(st.target.v3Short.replacingOccurrences(of: "\u{00A0}€", with: "")) 了\(st.title == "走到一半" ? "，走到一半了" : "")。离你想过的那种日子，近了一点。")
        return Letter(title: st.title.isEmpty ? st.target.v3Short : st.title,
                      quote: "「到今天是 76 天，你忍住了 \(j.resisted) 杯…」", date: "11 月 18 日",
                      tag: "第 \(index) 站 · 存到 \(st.target.v3Short)\(half)", headline: isEnd ? "你走完了。" : "你终于做到了。",
                      paragraphs: body,
                      facts: [["76 天", "从出发到这儿"], ["\(j.resisted) 次", "忍住没买"],
                              [j.monthlyPlan < Money(cents: 200_00) ? "1 次" : "0 次", j.monthlyPlan < Money(cents: 200_00) ? "改小步子，没停" : "断过"]])
    }

    /// 从 12 月起再过几个月是哪个月：「明年 4 月」。
    static func monthName(after months: Int) -> String {
        let idx = 11 + max(months, 1) - 1   // 12 月是第 1 个月
        let m = idx % 12 + 1
        let years = idx / 12
        return years == 0 ? "\(m) 月" : years == 1 ? "明年 \(m) 月" : "\(2026 + years) 年 \(m) 月"
    }
}

/// 盖在整个窗口上的那一层。
struct V3MomentLayer: View {
    @Environment(V3State.self) private var state
    var body: some View {
        ZStack {
            switch state.moment {
            case .smallerStep: V3SmallerStepSheet().transition(.opacity)
            case .letter(let l): V3LetterPage(letter: l).transition(.opacity)
            case nil: EmptyView()
            }
        }
    }
}

// MARK: - 快到不了时：夏夏先开口，步子减半

private struct V3SmallerStepSheet: View {
    @Environment(V3State.self) private var state
    @State private var pick = 0

    var body: some View {
        let j = state.book.journey
        let plan = j.monthlyPlan
        let smaller = Journey.smallerSteps(from: plan)
        ZStack {
            V3.ink.opacity(0.42).onTapGesture { state.closeMoment() }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    V3Face(face: "worried")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("这个月的 \(plan.v3Short)，大概到不了。没关系。").font(V3.font(24, .heavy)).foregroundStyle(V3.ink)
                    }
                }
                HStack(spacing: 10) {
                    V3Tile(label: "这个月计划存", value: plan.v3Short)
                    V3Tile(label: "现在已经存了", value: j.savedThisMonth.v3Short, color: V3.navy)
                    V3Tile(label: "照现在，月底大概", value: state.projectedThisMonth.v3Short, color: V3.red)
                }
                V3Bubble("这个月进账少了 260 €，不是你乱花。", flat: true)
                Text("要不要把步子改小一点？").font(V3.font(16, .heavy)).foregroundStyle(V3.ink)
                HStack(spacing: 14) {
                    ForEach(Array(smaller.enumerated()), id: \.offset) { i, m in
                        V3Option(picked: pick == i) { withAnimation(.snappy(duration: 0.18)) { pick = i } } content: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(i == 0 ? "12 月先存 \(m.v3Short)" : "再小一点，\(m.v3Short)").font(V3.num(16)).foregroundStyle(V3.ink)
                                    if i == 0 { V3Tag(text: "推荐", tone: .gold) }
                                }
                                Text((i == 0 ? "减一半。" : "再减一半。先保证不断。") + delayText(j, m))
                                    .font(V3.font(13, .regular)).foregroundStyle(V3.ink2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    V3Option(picked: pick == smaller.count) { withAnimation(.snappy(duration: 0.18)) { pick = smaller.count } } content: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("不改，还是 \(plan.v3Short)").font(V3.num(16)).foregroundStyle(V3.ink)
                            Text("我帮你找两处能省的，凑一凑。").font(V3.font(13, .regular)).foregroundStyle(V3.ink2)
                        }
                    }
                }
                .frame(height: 96)
                HStack(spacing: 12) {
                    V3Label("改小不算失败。")
                    Spacer(minLength: 4)
                    Button("过几天再说") { state.say("好，过几天再说"); state.closeMoment() }.buttonStyle(.v3(.ghost)).keyboardShortcut(.cancelAction)
                    Button(pick < smaller.count ? "就这么改" : "好，不改") {
                        if pick < smaller.count {
                            let m = smaller[pick]
                            state.change("改好了：12 月先存 \(m.v3Short)") { try $0.setMonthlyPlan(m) }
                        } else {
                            state.say("好，不改。我帮你找了两处能省的")
                        }
                        state.closeMoment()
                    }
                    .buttonStyle(.v3).keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 30).padding(.vertical, 26)
            .frame(width: 800)
            .v3Sticker(radius: 26, depth: 6)
            .accessibilityAddTraits(.isModal)
        }
    }

    /// 改小以后电脑晚多久到手：按「12 月只存这么多，之后照旧」算。
    private func delayText(_ j: Journey, _ m: Money) -> String {
        guard let months = j.monthsToFinish(firstMonth: m), let delay = j.delayMonths(ifNextMonthIs: m) else { return "" }
        let when = V3State.monthName(after: months)
        return delay == 0 ? "电脑到手的日子不变，还是\(when)。" : "电脑晚 \(delay) 个月到手，\(when)。"
    }
}

// MARK: - 到站时：一封只写给你的信

private struct V3LetterPage: View {
    let letter: V3State.Letter
    @Environment(V3State.self) private var state
    @State private var shown = false
    private static let stars: [(CGFloat, CGFloat)] = [(60, 70), (150, 40), (1000, 60), (1090, 130), (40, 560), (1110, 500), (520, 36), (940, 610), (230, 640)]

    var body: some View {
        let j = state.book.journey
        ZStack(alignment: .top) {
            LinearGradient(stops: [.init(color: V3.goodBG, location: 0), .init(color: V3.bg, location: 0.6)], startPoint: .top, endPoint: .bottom)
            GeometryReader { g in
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { i, s in
                    Text("★").font(.system(size: CGFloat(18 + i % 3 * 8))).foregroundStyle(V3.star)
                        .shadow(color: V3.ink.opacity(0.8), radius: 0, x: 0.8, y: 0.8)
                        .rotationEffect(.degrees(Double(i) * 23))
                        .scaleEffect(shown ? 1 : 0.2).opacity(shown ? 1 : 0)
                        .animation(.spring(duration: 0.5, bounce: 0.5).delay(Double(i) * 0.05), value: shown)
                        .position(x: s.0 / 1280 * g.size.width + 14, y: s.1 / 800 * g.size.height + 14)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                V3Tag(text: letter.tag, tone: .gold, size: 14).padding(.top, 48)
                Text(letter.headline).font(V3.font(48, .heavy)).foregroundStyle(V3.ink).padding(.top, 10)
                HStack(alignment: .center, spacing: 40) {
                    paper.frame(width: 560)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .bottom, spacing: 10) {
                            V3Xia(width: 130)
                            V3Bubble("这封信只写给你。", tone: .good).fixedSize().padding(.bottom, 40)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            V3CardTitle("这一站的小卡片")
                            HStack(spacing: 10) {
                                ForEach(Array(letter.facts.enumerated()), id: \.offset) { _, f in
                                    V3Tile(label: f.last ?? "", value: f.first ?? "", valueFirst: true)
                                }
                            }
                        }
                        .v3Card()
                        HStack(spacing: 10) {
                            Button("收进沿途风光") { state.say("收好了，在「沿途风光」里"); state.closeMoment(); state.go(.goals) }.buttonStyle(.v3(.ghost))
                            if !j.isFinished, let next = j.nextStation {
                                Button("下一站：\(next.target.v3Short)") {
                                    state.say("下一站：\(next.target.v3Short)，出发"); state.closeMoment(); state.go(.goals)
                                }
                                .buttonStyle(.v3(.primary, .big)).keyboardShortcut(.defaultAction)
                            }
                        }
                    }
                    .frame(width: 440)
                }
                .padding(.top, 22)
                Spacer(minLength: 0)
            }
        }
        .onAppear { shown = true }
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(letter.paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p).font(.custom(V3.kai, size: 19.5)).foregroundStyle(V3.ink).lineSpacing(10).fixedSize(horizontal: false, vertical: true)
            }
            Text("夏夏　\(letter.date)").font(.custom(V3.kai, size: 19.5)).foregroundStyle(V3.ink).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 6)
        }
        .padding(.horizontal, 34).padding(.vertical, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 8)
            ZStack {
                shape.fill(V3.ink).offset(y: 6)
                shape.fill(V3.paper)
                Canvas { ctx, size in
                    var y: CGFloat = 57
                    while y < size.height - 8 {
                        ctx.fill(Path(CGRect(x: 14, y: y, width: size.width - 28, height: 1)), with: .color(V3.hex(0xEADFC4)))
                        y += 36
                    }
                }
                shape.strokeBorder(V3.ink, lineWidth: 2.5)
            }
        }
        .rotationEffect(.degrees(shown ? -1.2 : -4))
        .scaleEffect(shown ? 1 : 0.92).opacity(shown ? 1 : 0)
        .animation(.spring(duration: 0.55, bounce: 0.3), value: shown)
        .accessibilityElement(children: .combine)
    }
}
#endif
