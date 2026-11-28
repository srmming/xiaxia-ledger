#if os(macOS)
import AppKit
import FinanceCore
import SwiftUI
import UniformTypeIdentifiers

/// 聊天里随一句话带上的东西：一张图，或者一个链接。试用版不识别、不联网，只是带着。
enum V3Attachment: Equatable {
    case image(NSImage, String)
    case link(String)
    var label: String {
        switch self {
        case .image(_, let name): "🖼 " + name
        case .link(let url): "🔗 " + (URL(string: url)?.host ?? url)
        }
    }
}

// 夏夏像聊天助手（ming 2026-11-27）：
// 平时页面上不放她。有事的时候，一条小消息从页面顶上滑下来；不点，几秒后收成「问夏夏」按钮上的小红点。
// 点消息或点「问夏夏」，打开一整页的对话（占满左边栏以右），那句话就是对话里她的第一句。
// 一天最多主动说三句；同一句当天点掉就不再提；一页一次只说一句。

extension V3State {
    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        var mine: Bool
        var text: String
        /// 我发的这句带的图或链接（只留一个名字）。
        var attachment = ""
        /// 夏夏回的「要不要买」那张小卡。
        var check: PurchaseCheck?
        /// 这张卡已经点过哪个按钮了。
        var done = ""
    }

    /// 页面有话要说（或者没话了）。
    func offer(_ id: String?) {
        guard let id else { sayCardID = nil; sayUnreadID = nil; return }
        guard !sayDismissed.contains(id), id != sayCardID else { return }
        if lastSaid?.text != id { lastSaid = (id, Date()) }
        if chatOpen || sheet != nil || showAdd { return }
        // 一页一次只滑下来一句；今天说满三句以后只亮小红点
        if !prefs.bubbles || sayPoppedThisPage || sayPopsToday >= prefs.maxPerDay {
            if sayCardID == nil { sayUnreadID = id }
            return
        }
        sayPoppedThisPage = true
        sayPopsToday += 1
        withAnimation(.easeOut(duration: 0.22)) { sayCardID = id; sayUnreadID = nil }
        sayTask?.cancel()
        sayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled, let self, self.sayCardID == id else { return }
            withAnimation(.easeIn(duration: 0.22)) { self.sayCardID = nil; self.sayUnreadID = id }
        }
    }

    /// 点了叉：今天不再提这一句。
    func dismissSaying(_ id: String) {
        sayDismissed.insert(id)
        withAnimation(.easeIn(duration: 0.18)) { sayCardID = nil; sayUnreadID = nil }
    }

    func openChat() {
        sayTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) { chatOpen = true; sayCardID = nil; sayUnreadID = nil }
    }

    func closeChat() { withAnimation(.easeOut(duration: 0.22)) { chatOpen = false } }

    /// 试用版里用来再看一次效果：今天的次数清零，点掉过的也重新算。
    func sayAgain() {
        sayPopsToday = 0; sayDismissed = []; sayPoppedThisPage = false; sayCardID = nil; sayUnreadID = nil
        closeChat()
        sayReplay += 1
    }
}

/// 盖在主区域上面的那一层：消息卡，或者整页的对话。
struct V3XiaLayer: View {
    let saying: V3Saying?
    @Environment(V3State.self) private var state

    var body: some View {
        ZStack(alignment: .top) {
            if state.chatOpen {
                V3ChatPage(saying: saying.flatMap { state.sayDismissed.contains($0.id) ? nil : $0 })
                    .transition(.opacity.combined(with: .offset(y: 10)))
            } else if let s = saying, state.sayCardID == s.id {
                V3SayCard(saying: s)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: saying?.id, initial: true) { _, id in state.offer(id) }
        .onChange(of: state.sayReplay) { _, _ in state.offer(saying?.id) }
    }
}

/// 从顶上滑下来的小消息：左边小头像，右边一句话，最右一个叉。点卡片本身打开对话。
private struct V3SayCard: View {
    let saying: V3Saying
    @Environment(V3State.self) private var state
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button { state.openChat() } label: {
                HStack(spacing: 10) {
                    V3Face(face: saying.face, width: 40)
                    Text(saying.text).font(V3.font(14, .bold)).foregroundStyle(V3.ink).lineLimit(2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("夏夏说：\(saying.text)。点一下和她聊")
            Button { state.dismissSaying(saying.id) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(V3.ink2)
                    .frame(width: 28, height: 28).background(Circle().fill(V3.bg))
            }
            .buttonStyle(.plain).accessibilityLabel("知道了，今天不再提").help("今天不再提")
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 9)
        .frame(width: 520)
        .v3Sticker(fill: saying.tone == 1 ? V3.goodBG : saying.tone == 2 ? V3.warnBG : .white, radius: 18, depth: 3)
        .offset(y: hover ? 1 : 0)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// 和夏夏聊天：一整页。中间一列对话（最宽 720），底下一个输入框。
struct V3ChatPage: View {
    let saying: V3Saying?
    @Environment(V3State.self) private var state
    @State private var input = ""
    @State private var thinking = false
    @FocusState private var focused: Bool
    @State private var picking = false
    @State private var dropping = false
    private let examples = ["这个月还能花多少", "这个值得买吗？（可以贴图或链接）", "信用卡什么时候还", "帮我记一笔：午饭 12,5"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { state.closeChat() } label: { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.v3(.ghost, .small)).keyboardShortcut(.cancelAction).help("回到刚才那页（esc）")
                Spacer()
                Button("再说一次") { state.sayAgain() }.buttonStyle(.v3(.ghost, .small)).help("试用：让夏夏把刚才那句再说一遍")
            }
            .frame(height: 48)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let s = saying {
                            // 从消息进来：那句话就是她的第一句，要回答的按钮跟在下面
                            HStack(alignment: .top, spacing: 10) {
                                V3Face(face: s.face, width: 44)
                                VStack(alignment: .leading, spacing: 8) {
                                    bubble(s.text, mine: false, lead: true)
                                    s.extra
                                }
                            }
                        }
                        if saying == nil && state.chat.isEmpty && !thinking {
                            VStack(spacing: 14) {
                                V3Face(face: "happy", width: 96)
                                Text("想问什么？").font(V3.font(26, .heavy)).foregroundStyle(V3.ink)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 70)
                        }
                        ForEach(state.chat) { m in
                            if m.mine {
                                VStack(alignment: .trailing, spacing: 4) {
                                    if !m.attachment.isEmpty {
                                        Text(m.attachment).font(V3.font(12.5, .bold)).foregroundStyle(V3.ink2).lineLimit(1)
                                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(V3.soft))
                                    }
                                    if !m.text.isEmpty { bubble(m.text, mine: true) }
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                HStack(alignment: .top, spacing: 10) {
                                    V3Face(face: "talk", width: 44)
                                    if let c = m.check { V3BuyCard(message: m, check: c) } else { bubble(m.text, mine: false, lead: true) }
                                }
                            }
                        }
                        if thinking {
                            HStack(spacing: 10) {
                                V3Face(face: "think", width: 44)
                                Text("正在看你的流水…").font(V3.font(14, .semibold)).foregroundStyle(V3.ink2)
                            }
                            .id("thinking")
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .onChange(of: state.chat.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: thinking) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            VStack(spacing: 10) {
                if state.chat.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(examples, id: \.self) { e in V3Chip(text: e, size: 13) { ask(e) } }
                    }
                }
                if let a = state.chatAttachment {
                    HStack(spacing: 8) {
                        if case .image(let img, _) = a {
                            Image(nsImage: img).resizable().scaledToFill().frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(a.label).font(V3.font(13, .bold)).foregroundStyle(V3.ink).lineLimit(1)
                        Button { withAnimation(.snappy(duration: 0.15)) { state.chatAttachment = nil } } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain).accessibilityLabel("去掉这个附件")
                    }
                    .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(V3.ink, lineWidth: 1.5)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    Button { picking = true } label: {
                        Image(systemName: "paperclip").font(.system(size: 15, weight: .semibold)).foregroundStyle(V3.navy).frame(width: 40, height: 40)
                            .background(Circle().fill(.white).overlay(Circle().strokeBorder(V3.ink, lineWidth: 2)))
                    }
                    .buttonStyle(V3SinkStyle(depth: 2)).help("带一张图（也可以直接把图拖进来、把链接贴进来）").accessibilityLabel("带一张图")
                    TextField("问一句，或者让我帮你记", text: $input).textFieldStyle(.plain).font(V3.font(15, .semibold)).focused($focused)
                        .onSubmit { send() }
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 2)))
                        .accessibilityLabel("对夏夏说")
                    Button("发送") { send() }.buttonStyle(.v3).disabled((input.trimmingCharacters(in: .whitespaces).isEmpty && state.chatAttachment == nil) || thinking)
                }
            }
            .frame(maxWidth: 720).padding(.bottom, 4)
        }
        .padding(.init(top: V3Launch.overTitleBar ? 22 : 14, leading: 30, bottom: 24, trailing: 30))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V3.bg)
        .overlay { if dropping { RoundedRectangle(cornerRadius: 22).strokeBorder(V3.navy, style: StrokeStyle(lineWidth: 3, dash: [9, 7])).padding(12).allowsHitTesting(false) } }
        .onDrop(of: [.image, .fileURL, .url], isTargeted: $dropping) { providers in take(providers); return true }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { attach(file: url) }
        }
        .onAppear { focused = true }
    }

    /// 拖进来的东西：图片文件、图片、链接。
    private func take(_ providers: [NSItemProvider]) {
        guard let p = providers.first else { return }
        if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in attach(file: url) }
            }
        } else if p.canLoadObject(ofClass: NSImage.self) {
            _ = p.loadObject(ofClass: NSImage.self) { img, _ in
                guard let img = img as? NSImage else { return }
                Task { @MainActor in state.chatAttachment = .image(img, "一张图") }
            }
        } else if p.canLoadObject(ofClass: URL.self) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in state.chatAttachment = .link(url.absoluteString) }
            }
        }
    }

    private func attach(file url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let img = NSImage(contentsOf: url) { state.chatAttachment = .image(img, url.lastPathComponent) }
        else { state.fail("这个文件不是图片，换一张图试试") }
    }

    private func bubble(_ text: String, mine: Bool, lead: Bool = false) -> some View {
        Text(text).font(V3.font(15, .semibold)).foregroundStyle(mine ? .white : V3.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(UnevenRoundedRectangle(topLeadingRadius: mine || !lead ? 16 : 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16,
                                               topTrailingRadius: mine ? 4 : 16).fill(mine ? V3.navy : .white))
            .frame(maxWidth: 520, alignment: mine ? .trailing : .leading)
            .frame(maxWidth: lead ? nil : .infinity, alignment: mine ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func send() { let t = input; input = ""; ask(t) }

    private func ask(_ raw: String) {
        var q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 话里贴了链接：拿出来当附件
        if state.chatAttachment == nil, let link = q.split(separator: " ").map(String.init).first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }) {
            state.chatAttachment = .link(link)
            q = q.replacingOccurrences(of: link, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let attachment = state.chatAttachment
        guard !q.isEmpty || attachment != nil, !thinking else { return }
        state.chatAttachment = nil
        state.chat.append(.init(mine: true, text: q, attachment: attachment?.label ?? ""))
        withAnimation(.snappy) { thinking = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            let answer = buyReply(q, attachment: attachment) ?? V3State.ChatMessage(mine: false, text: reply(q))
            withAnimation(.snappy) { thinking = false }
            state.chat.append(answer)
            state.lastSaid = (answer.text, Date())
        }
    }

    /// 「要不要买」：话里有价钱就算三件事；只有图或链接、没说价钱，就只问一句多少钱。不是在问买东西就返回 nil。
    private func buyReply(_ q: String, attachment: V3Attachment?) -> V3State.ChatMessage? {
        let asking = ["想买", "值得买", "要不要买", "能不能买", "买得起", "该不该买"].contains { q.contains($0) }
        guard asking || attachment != nil || state.pendingWant != nil else { return nil }
        guard let want = PurchaseCheck.parseWant(q) else {
            state.pendingWant = state.pendingWant ?? "这样东西"
            return .init(mine: false, text: attachment == nil ? "多少钱？贴图、贴链接也行。" : "多少钱？")
        }
        let name = want.name == "这样东西" ? (state.pendingWant ?? want.name) : want.name
        state.pendingWant = nil
        do {
            let c = try state.book.checkPurchase(name: name, price: want.price)
            return .init(mine: false, text: c.line, check: c)
        } catch let e as TrialError { return .init(mine: false, text: e.message) } catch { return .init(mine: false, text: "没算出来，再说一遍？") }
    }

    /// 试用版没接 AI：常问的几句按账本里的数字现算，别的就老实说。
    private func reply(_ q: String) -> String {
        let b = state.book
        let m = b.month
        let j = b.journey
        if let p = QuickPhrase.parse(q), q.contains("记") || q.contains("花了") || q.contains("买了") || q.contains("块") {
            state.record(p, account: "现金")
            return "记好了：\(p.name) \(p.amount.v3)，现金。记错了点底下的「撤销」。"
        }
        if q.contains("记一笔") || q.contains("帮我记") { return "说一句就行，比如「午饭 12,5」。我听出金额就直接记。" }
        if q.contains("还能花") || q.contains("随便花") {
            return "还能随便花 \(m.left.v3)。到月底还有 \(m.daysLeft) 天，平均每天 \(Money(cents: m.perDay.cents / 100 * 100).v3Short)。"
        }
        if q.contains("信用卡") {
            let card = b.debts.first { $0.name == "信用卡" }?.balance ?? .zero
            return card > .zero ? "12 月 5 日要还 \(card.v3)，日常卡里有 \(b.accounts.first { $0.name == "日常卡" }?.balance.v3 ?? "")，够付。" : "信用卡这个月的已经还清了。"
        }
        if q.contains("下个月") { return "12 月要付 1.532,00 €：房租 650、信用卡 640、手机分期 200、订阅 42。钱够，还多 808 €。" }
        if q.contains("值得买") { return "发张图、贴个链接，或者直接说多少钱。" }
        if q.contains("电脑") {
            if j.isFinished { return "已经存够了，\(j.total.v3Short)。去把它带回家吧。" }
            return "还差 \(j.remainingToEnd.v3Short)。照每月存 \(j.monthlyPlan.v3Short)，大概\(V3State.monthName(after: j.monthsToFinish() ?? 0))到手。"
        }
        if q.contains("花多") { return "这个月没有哪样花多了：一共 \(m.spentTotal.v3)，比上月同期少。" }
        return "这是试用版，我还没接上 AI，只会答下面那几句。正式版里这句话会交给你连着的 AI 来答。"
    }
}

/// 夏夏回的那张小卡：东西和价钱，三个数，一句意见，两个按钮。
struct V3BuyCard: View {
    let message: V3State.ChatMessage
    let check: PurchaseCheck
    @Environment(V3State.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(check.name).font(V3.font(16, .heavy)).foregroundStyle(V3.ink).lineLimit(1)
                Spacer(minLength: 8)
                V3Amount(check.price.v3, size: 18, weight: .heavy)
            }
            HStack(alignment: .top, spacing: 22) {
                V3KV(value: check.leftAfter.v3Short, label: "买了这个月还能随便花", color: check.leftAfter >= .zero ? V3.navy : V3.red)
                if let d = check.days { V3KV(value: "\(d) 天", label: "等于平时几天的花销") }
                if let w = check.weeksLate { V3KV(value: "晚 \(w) 周", label: "从目标里拿的话") }
            }
            Text(check.line).font(V3.font(15, .bold)).foregroundStyle(check.verdict == .no ? V3.red : V3.ink)
            if message.done.isEmpty {
                HStack(spacing: 8) {
                    Button("先放着想想") {
                        if state.change("放进想要清单了：\(check.name)", { try $0.addWanted(name: check.name, price: check.price) }) { mark("放进想要清单了，在「目标」页") }
                    }
                    .buttonStyle(.v3(check.verdict == .ok ? .ghost : .primary, .small))
                    Button("就买了") {
                        guard let acc = state.book.accounts(for: .pay, side: .life).first?.name else { state.fail("还没有能付钱的账户，先去家底加一个"); return }
                        if state.change("记好了 · \(check.name) \(check.price.v3) · \(acc)", kind: .add, { try $0.record(name: check.name, emoji: "🛍", amount: check.price, account: acc, tag: "跟夏夏说的") }) { mark("记了一笔，\(acc)") }
                    }
                    .buttonStyle(.v3(check.verdict == .ok ? .primary : .ghost, .small))
                }
            } else {
                V3Tag(text: message.done, tone: .green)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(width: 520, alignment: .leading)
        .v3Sticker(radius: 18, depth: 3)
    }

    private func mark(_ text: String) {
        if let i = state.chat.firstIndex(where: { $0.id == message.id }) { withAnimation(.snappy) { state.chat[i].done = text } }
    }
}
#endif
