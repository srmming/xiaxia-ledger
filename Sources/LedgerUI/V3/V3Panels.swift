#if os(macOS)
import FinanceCore
import SwiftUI

// 记一笔（弹出来的面板）、问夏夏（右边滑出来）、设置、改动记录。

// MARK: - 记一笔

struct V3AddSheet: View {
    @Environment(V3State.self) private var state
    @State private var way = 0
    @State private var text = "刚才咖啡 3 块 2"
    @FocusState private var focused: Bool

    private var parsed: QuickPhrase? { QuickPhrase.parse(text) }

    var body: some View {
        let q = parsed
        ZStack {
            V3.ink.opacity(0.42).onTapGesture { close() }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("记一笔").font(V3.font(22, .heavy))
                    Spacer()
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 26, height: 26) }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("关掉")
                }
                HStack(spacing: 14) {
                    wayOption(0, "💬 说一句", "打一句大白话就行")
                    wayOption(1, "🧾 拍小票", "手机拍，自动传过来")
                    wayOption(2, "📄 拖流水", "一次进来一个月的")
                }
                .frame(height: 72)
                if way == 0 {
                    HStack(spacing: 10) {
                        Text("🎙")
                        TextField("比如：刚才咖啡 3 块 2", text: $text).textFieldStyle(.plain).font(V3.font(17, .bold)).focused($focused)
                            .onSubmit { if let q { save(q, "现金") } }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2)))
                    if let q {
                        HStack(spacing: 14) {
                            V3Ico(emoji: q.emoji, size: 48)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(q.name == "咖啡" ? "咖啡 · Café Nube" : q.name).font(V3.font(17, .heavy))
                                V3Label("今天")
                            }
                            Spacer()
                            V3Amount((-q.amount).v3, size: 26, weight: .heavy)
                        }
                        .padding(.horizontal, 22).padding(.vertical, 16).v3Sticker(fill: V3.bg)
                        V3Ask(face: "calm", text: "这家店你是付现金还是刷日常卡？只问这一次，以后同一家店我按你的习惯记。") {
                            HStack(spacing: 8) {
                                Button("现金") { save(q, "现金") }.buttonStyle(.v3(.primary, .small))
                                Button("日常卡") { save(q, "日常卡") }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                    } else {
                        V3Ask(face: "think", text: text.trimmingCharacters(in: .whitespaces).isEmpty ? "说一句就行，比如「午饭 12,5」「打车 15」。" : "我没听出多少钱。带上数字再说一遍？比如「午饭 12,5」。", tone: text.trimmingCharacters(in: .whitespaces).isEmpty ? .plain : .warn)
                    }
                } else {
                    V3Ask(face: "think", text: way == 1 ? "试用版还没接上手机。正式版里，手机拍的小票会自己出现在这里，日期按小票上印的那天记。"
                          : "把银行流水拖到「流水」那一页就行，数字会一笔一笔跳，重复的自动跳过。") {
                        if way == 2 { Button("去流水页") { close(); state.go(.transactions) }.buttonStyle(.v3(.primary, .small)) }
                    }
                }
                HStack(spacing: 10) {
                    V3Label("记完还剩：这个月能随便花 \((state.book.month.left - (way == 0 ? q?.amount ?? .zero : .zero)).v3)")
                    Spacer()
                    Button("先不记") { close() }.buttonStyle(.v3(.ghost))
                    Button("记好") { if let q { save(q, "现金") } }.buttonStyle(.v3).disabled(q == nil || way != 0).keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 30).padding(.vertical, 26)
            .frame(width: 700)
            .v3Sticker(radius: 26, depth: 6)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { focused = true }
    }

    private func wayOption(_ i: Int, _ title: String, _ sub: String) -> some View {
        V3Option(picked: way == i) { withAnimation(.snappy(duration: 0.18)) { way = i } } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(V3.font(16, .bold)).foregroundStyle(V3.ink)
                Text(sub).font(V3.font(13, .regular)).foregroundStyle(V3.ink2)
            }
        }
    }

    private func save(_ q: QuickPhrase, _ account: String) {
        state.record(q, account: account, place: q.name == "咖啡" ? "Café Nube" : "")
        close()
    }

    private func close() { withAnimation(.snappy(duration: 0.2)) { state.showAdd = false } }
}

// MARK: - 问夏夏

struct V3AskPanel: View {
    @Environment(V3State.self) private var state
    struct Msg: Identifiable { let id = UUID(); var mine: Bool; var text: String }
    @State private var msgs: [Msg] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var offerPlan = true
    private let common = ["这个月还能随便花多少", "下个月钱够不够", "电脑哪天能到手", "哪里花多了", "帮我记一笔"]

    var body: some View {
        let m = state.book.month
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                V3Face(face: thinking ? "think" : "talk", width: 44)
                Text("问夏夏").font(V3.font(18, .heavy))
                Spacer()
                V3Tag(text: state.ai.map { $0 == "夏夏自带的" ? "夏夏自带的 AI" : "\($0) 连着" } ?? "还没连 AI", tone: state.ai == nil ? .blue : .green)
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("收起问夏夏")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        bubble("这个月为什么感觉钱不够花？", mine: true)
                        bubble("不是花多了。这个月进账 \(m.income.v3Short)，比平时少 260 €（少接了一单活）。花销 \(m.spentTotal.v3Short)，比上月同期还少 86 €。", mine: false)
                        bubble("现在还能随便花 \(m.left.v3)，到月底每天 \(Money(cents: m.perDay.cents / 100 * 100).v3Short)，够用。紧的是存钱计划，要不要把 12 月改成 100 €？", mine: false)
                        if offerPlan {
                            HStack(spacing: 8) {
                                Button("改成 100 €") {
                                    state.change("改好了：12 月先存 100 €") { $0.journey.monthlyPlan = Money(cents: 100_00); $0.month.forGoals = Money(cents: 100_00) }
                                    withAnimation(.snappy) { offerPlan = false }
                                }
                                .buttonStyle(.v3(.primary, .small))
                                Button("先不改") { state.say("好，先不改"); withAnimation(.snappy) { offerPlan = false } }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                        ForEach(msgs) { msg in bubble(msg.text, mine: msg.mine).id(msg.id) }
                        if thinking {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); V3Label("正在看你的流水…") }.id("thinking")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: msgs.count) { _, _ in withAnimation { proxy.scrollTo(msgs.last?.id, anchor: .bottom) } }
            }
            VStack(alignment: .leading, spacing: 8) {
                V3Label("常问的", size: 13)
                FlowLayout(spacing: 6) {
                    ForEach(common, id: \.self) { c in V3Chip(text: c, size: 12.5) { ask(c) } }
                }
                HStack(spacing: 10) {
                    Text("🎙")
                    TextField("问一句，或者让我帮你记", text: $input).textFieldStyle(.plain).font(V3.font(14, .semibold))
                        .onSubmit { let t = input; input = ""; ask(t) }
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 22)
        .frame(width: 400).frame(maxHeight: .infinity)
        .background(Color.white)
        .overlay(alignment: .leading) { Rectangle().fill(V3.ink).frame(width: 2.5) }
        .shadow(color: V3.ink.opacity(0.18), radius: 15, x: -10)
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        Text(text).font(V3.font(15, .semibold)).foregroundStyle(mine ? .white : V3.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4, bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16)
                .fill(mine ? V3.navy : V3.soft))
            .frame(maxWidth: 330, alignment: mine ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func ask(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        msgs.append(Msg(mine: true, text: q))
        withAnimation(.snappy) { thinking = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            let answer = reply(q)
            withAnimation(.snappy) { thinking = false }
            msgs.append(Msg(mine: false, text: answer))
        }
    }

    /// 试用版没接 AI：常问的几句按账本里的数字现算，别的就老实说。
    private func reply(_ q: String) -> String {
        let b = state.book
        let m = b.month
        let j = b.journey
        if let p = QuickPhrase.parse(q), q.contains("记") || q.contains("花") || q.contains("买") || q.contains("块") {
            state.record(p, account: "现金")
            return "记好了：\(p.name) \(p.amount.v3)，现金。记错了点下面的「撤销」。"
        }
        if q.contains("帮我记") { return "说一句就行，比如「午饭 12,5」。我听出金额就直接记，记错能撤销。" }
        if q.contains("随便花") { return "现在还能随便花 \(m.left.v3)。到月底还有 \(m.daysLeft) 天，平均每天 \(Money(cents: m.perDay.cents / 100 * 100).v3Short)。" }
        if q.contains("下个月") { return "12 月要付 1.532,00 €：房租 650、信用卡 640、手机分期 200、订阅 42。进账按 2.340 € 算，钱够，还多 808 €。" }
        if q.contains("电脑") {
            if j.isFinished { return "已经存够了，\(j.total.v3Short)。去把它带回家吧。" }
            let months = j.monthsToFinish() ?? 0
            return "还差 \(j.remainingToEnd.v3Short)。照每月存 \(j.monthlyPlan.v3Short)，大概\(V3State.monthName(after: months))到手。"
        }
        if q.contains("花多") { return "这个月没有哪样花多了：一共 \(m.spentTotal.v3)，比上月同期少。要留意的只有外卖，上个月比前一个月多了 4 次。" }
        return "这是试用版，我还没接上 AI，只会答上面那几句常问的。正式版里，这句话会交给你连着的 AI 来答。"
    }

    private func close() { withAnimation(.snappy(duration: 0.25)) { state.showAsk = false } }
}

// MARK: - 设置

struct V3SettingsPage: View {
    @Environment(V3State.self) private var state
    @State private var toggles: [String: Bool] = [:]

    var body: some View {
        if state.showLog { V3LogPage() } else { settings }
    }

    private func bind(_ key: String) -> Binding<Bool> {
        Binding(get: { toggles[key] ?? true }, set: { v in
            toggles[key] = v
            state.say(v ? "打开了：\(key)" : "关掉了：\(key)")
        })
    }

    private var settings: some View {
        V3Cols {
            VStack(spacing: 16) {
                V3Card(spacing: 0) {
                    V3CardTitle("陪你的 AI").padding(.bottom, 4)
                    let ai = state.ai ?? ""
                    let outside = !ai.isEmpty && ai != "夏夏自带的"
                    row(outside ? ai : "还没连别的 AI", outside ? "连上了 · 聊目标、提醒、写信都用它" : "连上以后，聊目标、提醒、写信都用它") {
                        V3Tag(text: outside ? "在用" : "没连", tone: outside ? .green : .blue)
                    }
                    V3Divider()
                    row("夏夏自带的 AI", "没连别的 AI，或者它连不上时用") { V3Tag(text: outside ? "备用" : "在用", tone: outside ? .blue : .green) }
                    V3Divider()
                    row("换一个 AI", "ChatGPT、Gemini、别的") {
                        Button("去连接") { withAnimation(.snappy) { state.onboardingStep = 4 } }.buttonStyle(.v3(.ghost, .small))
                    }
                }
                V3GrowCard(spacing: 0) {
                    V3CardTitle("夏夏什么时候开口").padding(.bottom, 4)
                    toggleRow("目标快到不了时", "说清情况，建议把步子改小"); V3Divider()
                    toggleRow("到站时写一封信", "收进「沿途风光」"); V3Divider()
                    toggleRow("该付钱、该还钱之前", "提前 3 天说一声"); V3Divider()
                    toggleRow("每月小结", "每月 1 日"); V3Divider()
                    toggleRow("每页的夏夏气泡", "关掉以后页面上只留数字")
                }
            }
        } trailing: {
            VStack(spacing: 16) {
                V3Card(spacing: 0) {
                    V3CardTitle("钱怎么进来").padding(.bottom, 4)
                    row("流水导入", "上次：今天 · Revolut 52 笔") { Button("再导一份") { state.go(.transactions) }.buttonStyle(.v3(.ghost, .small)) }
                    V3Divider()
                    toggleRow("手机拍的小票", "自动同步到这台 Mac"); V3Divider()
                    toggleRow("跟 AI 说一句", "「刚才咖啡 3 块 2」")
                }
                V3GrowCard(spacing: 0) {
                    V3CardTitle("账本").padding(.bottom, 4)
                    row("生活和生意都管", "关掉就只管自己的钱") {
                        V3Switch(on: Binding(get: { state.mode != .life }, set: { v in
                            withAnimation(.snappy) { state.mode = v ? .both : .life }
                            state.say(v ? "好，生活和生意都管" : "好，只管自己的钱。左边的「生意」收起来了")
                        }), label: "生活和生意都管")
                    }
                    V3Divider()
                    toggleRow("私房钱", "默认藏起来"); V3Divider()
                    row("夏夏的记忆", state.wish.isEmpty ? "还没写过想要的" : "「\(state.wish)」等 4 条") {
                        V3SayButton("看看", state.wish.isEmpty ? "记忆里还没有你写的那句。在引导里可以写" : "你写过：「\(state.wish)」。每条都能改、能删（试用版先只能看）", .ghost)
                    }
                    V3Divider()
                    row("改动记录", "每一次改动都能撤销") { Button("看看") { withAnimation(.snappy) { state.showLog = true } }.buttonStyle(.v3(.ghost, .small)) }
                    V3Divider()
                    row("再走一遍开头的引导", "开场动画、管哪边、写一句想要的…") {
                        Button("从头看") { withAnimation(.snappy) { state.onboardingStep = 0 } }.buttonStyle(.v3(.ghost, .small))
                    }
                    V3Divider()
                    row("给我们提意见", "写好发到邮箱") { V3SayButton("写一句", "试用版先不发邮件。直接告诉做这个 app 的人就行", .ghost) }
                }
            }
        }
    }

    private func row<Trail: View>(_ title: String, _ sub: String, @ViewBuilder trail: () -> Trail) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(V3.font(14, .bold))
                Text(sub).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            trail()
        }
        .padding(.vertical, 8)
    }

    private func toggleRow(_ title: String, _ sub: String) -> some View {
        row(title, sub) { V3Switch(on: bind(title), label: title) }
    }
}

// MARK: - 改动记录

private struct V3LogPage: View {
    @Environment(V3State.self) private var state
    @State private var filter = "全部"
    private let whos = ["全部", "你", "Claude", "夏夏", "流水导入", "拍小票"]

    var body: some View {
        let items = state.log.filter { filter == "全部" || $0.who == filter }
        V3Cols(left: 1.6, right: 1) {
            V3GrowCard(spacing: 4) {
                V3CardTitle(title: "今天") { EmptyView() } trail: {
                    HStack(spacing: 10) {
                        Text("\(items.count) 次改动").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                        Button("回设置") { withAnimation(.snappy) { state.showLog = false } }.buttonStyle(.v3(.ghost, .small))
                    }
                }
                if items.isEmpty { V3Label("「\(filter)」今天没有改过什么。").padding(.top, 10) }
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(9).enumerated()), id: \.element.id) { i, item in
                        if i > 0 { V3Divider() }
                        HStack(spacing: 12) {
                            V3Ico(emoji: item.emoji)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.what).font(V3.font(14, .bold)).lineLimit(1)
                                Text(item.when).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                            }
                            Spacer(minLength: 6)
                            V3Tag(text: item.who, tone: item.who == "夏夏" ? .green : item.who == "Claude" ? .gold : .blue)
                            Button("撤销") {
                                if item.mine, state.log.first(where: \.mine)?.id == item.id {
                                    state.undo()
                                } else if item.mine {
                                    state.say("先撤销它后面的那几步，才能撤到这一步")
                                } else {
                                    withAnimation(.snappy) { state.log.removeAll { $0.id == item.id } }
                                    state.say("撤销了：\(item.what)")
                                }
                            }
                            .buttonStyle(.v3(.ghost, .small))
                            .accessibilityLabel("撤销：\(item.what)")
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        } trailing: {
            VStack(spacing: 16) {
                V3Card {
                    V3CardTitle("只看谁改的")
                    FlowLayout(spacing: 6) {
                        ForEach(whos, id: \.self) { w in
                            Button { withAnimation(.snappy(duration: 0.15)) { filter = w } } label: {
                                Text(w == "夏夏" ? "夏夏自己认的" : w).font(V3.font(12.5, .bold)).foregroundStyle(filter == w ? .white : V3.ink)
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .background(Capsule().fill(filter == w ? V3.navy : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                            }
                            .buttonStyle(V3SinkStyle(depth: 2))
                            .accessibilityAddTraits(filter == w ? .isSelected : [])
                        }
                    }
                }
                V3GrowCard {
                    V3Ask(face: "calm", text: "AI 帮你记的每一笔都在这里。哪笔不对，点撤销就回到之前的样子。")
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        V3Label("这个月", size: 12.5)
                        Text("自己进来 96 笔 · 你手记 \(4 + state.log.filter(\.mine).count) 笔").font(V3.num(16)).contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(V3.bg))
                }
            }
        }
    }
}
#endif
