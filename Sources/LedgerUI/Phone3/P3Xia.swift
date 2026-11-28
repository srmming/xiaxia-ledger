#if os(iOS)
import FinanceCore
import PhotosUI
import SwiftUI

// 问夏夏：像微信的对话页。拍照或贴图问「要不要买」，夏夏按规则算三件事再给一句意见。
// 示例里不连 AI：夏夏的回话是按固定规则写的。

struct P3Chat {
    enum Action: Equatable {
        /// 听懂的一句（花了、收了、还款、转账、借出、别人还我），记的时候交给 TrialBook.record(_:account:)，和 Mac 同一处
        case phrase(QuickPhrase, account: String)
    }

    struct Msg: Identifiable {
        enum Who { case me, xia }
        let id = UUID()
        var who: Who
        var text = ""
        var image: Image?
        var check: PurchaseCheck?
        var quick: QuickPhrase?
        /// 夏夏听懂要记的那一下（花了 / 收了 / 还款），点「记下」才写。
        var action: Action?
        var done = ""
        var time = Date()
    }

    var messages: [Msg] = []
    var unread = 0

    /// 开头那句：夏夏说的每句话都要能从账本算出来（和 Mac 一样用 savingRemark），没什么可说就不说。
    init(book: TrialBook? = nil) {
        guard let book, let line = book.savingRemark else { return }
        messages = [Msg(who: .xia, text: line)]
        unread = 1
    }
    /// 刚发了一张图，等用户说是什么、多少钱。
    var waitingPrice = false

    var lastLine: String {
        guard let m = messages.last else { return "有什么想问的，直接说" }
        if m.image != nil { return "[图片]" }
        if let c = m.check { return "\(c.name) \(c.price.p3Short)：\(c.line)" }
        return m.text
    }
    var lastTime: String { (messages.last?.time ?? Date()).formatted(date: .omitted, time: .shortened) }

    mutating func demoWant(book: TrialBook) {
        messages.append(Msg(who: .me, image: Image(systemName: "shoe.2.fill")))
        messages.append(Msg(who: .xia, text: "这是什么？多少钱？比如「跑鞋 95」"))
        messages.append(Msg(who: .me, text: "跑鞋 95"))
        if let c = try? book.checkPurchase(name: "跑鞋", price: Money(cents: 95_00)) { messages.append(Msg(who: .xia, check: c)) }
        unread = 0
    }
}

extension P3State {
    func chatSend(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.snappy(duration: 0.2)) { chat.messages.append(.init(who: .me, text: text)) }
        let reply: P3Chat.Msg
        let asksBuy = ["买", "要不要", "值得", "想要"].contains { text.contains($0) }
        if chat.waitingPrice || asksBuy, let want = PurchaseCheck.parseWant(text), let c = try? book.checkPurchase(name: want.name, price: want.price) {
            chat.waitingPrice = false
            reply = .init(who: .xia, check: c)
        } else if chat.waitingPrice {
            reply = .init(who: .xia, text: "没看到价钱。说一下多少钱就行，比如「跑鞋 95」")
        } else if let answer = localAnswer(text) {
            reply = .init(who: .xia, text: answer)
        } else if let q = QuickPhrase.parse(text) {
            reply = understand(q)
        } else if ai.hasKey {
            // 不是记账、不是问要不要买：问 OpenRouter（只带 app 算好的几个数）
            Task { @MainActor in
                let answer = await self.ai.chat(text, numbers: self.book.numbersCard)
                withAnimation(.snappy(duration: 0.25)) {
                    self.chat.messages.append(.init(who: .xia, text: answer ?? "这会儿没连上 OpenRouter，等一下再问我。"))
                }
            }
            return
        } else {
            reply = .init(who: .xia, text: "这个我先记着。想问要不要买，发张图或者说「想买 xx 多少钱」。")
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.snappy(duration: 0.25)) { self.chat.messages.append(reply) }
        }
    }

    /// 听懂一句带钱数的话：是哪一种由共用的 QuickPhrase 认（和 Mac 一样），这里只挑默认账户、问一句。
    private func understand(_ said: QuickPhrase) -> P3Chat.Msg {
        var q = said
        if side == .biz { q.shop = true }
        let b = book
        let shop = q.shop && b.showBiz
        let pay = shop ? (b.shopHeld.first?.name ?? "") : dailyName
        let receive = shop ? (b.shopHeld.first?.name ?? "") : (b.accounts(for: .receive, side: .life).first?.name ?? dailyName)
        let text: String
        let account: String
        switch q.kind {
        case .spend:
            account = pay
            text = shop ? "记一笔店里的开销：\(q.name) \(q.amount.p3)，从\(pay)出？" : "记一笔\(q.name) \(q.amount.p3)，从\(pay)出？"
        case .income:
            account = receive
            text = shop ? "记一笔店里收的 \(q.amount.p3)，进到\(receive)？" : "记一笔收入 \(q.amount.p3)（\(q.name)），进到\(receive)？"
        case .repay(let to):
            account = pay
            text = "还款不算花销。从\(pay)还\(to.isEmpty ? "" : to) \(q.amount.p3)？"
        case .transfer(let to):
            account = pay
            text = "自己账户之间挪，不算花销。从\(pay)转 \(q.amount.p3) 到\(to)？"
        case .lend(let to):
            account = pay
            text = "借出去的不算花销。从\(pay)借给\(to) \(q.amount.p3)？"
        case .borrow(let from):
            account = receive
            text = "借来的钱不算收入，要还的。从\(from)借的 \(q.amount.p3) 进到\(receive)？"
        case .repaidToMe(let from):
            account = receive
            text = "别人还你的不算收入。\(from)还的 \(q.amount.p3) 进到\(receive)？"
        }
        return .init(who: .xia, text: text, action: .phrase(q, account: account))
    }

    /// 不用 AI 也答得上的：这个月还能花多少、花了多少、家底多少。数都是 app 自己算的。
    private func localAnswer(_ text: String) -> String? {
        let b = book
        let m = b.month
        if ["还能花", "能花多少", "还剩多少", "还剩", "随便花"].contains(where: text.contains) {
            if side == .biz {
                let s = b.shopMonth()
                return "店里这个月收进来 \(s.income.p3)，开销 \(s.costs.p3)，真正赚了 \(s.earned.p3)。"
            }
            return m.left > .zero
                ? "这个月现在还能随便花 \(m.left.p3)，到月底还有 \(m.daysLeft) 天，一天大概 \(Money(cents: m.perDay.cents / 100 * 100).p3Short)。"
                : "这个月能随便花的已经用完了，超了 \(m.left.magnitude.p3)，到月底还有 \(m.daysLeft) 天。"
        }
        if ["花了多少", "花掉多少", "一共花"].contains(where: text.contains), QuickPhrase.parse(text) == nil {
            return "这个月一共花掉 \(m.spentTotal.p3)，其中随手花的 \(m.spent.p3)。"
        }
        if ["家底", "净资产", "一共有多少"].contains(where: text.contains), QuickPhrase.parse(text) == nil {
            return "家底现在净剩 \(b.totals.net.p3)。"
        }
        return nil
    }

    /// 点了「记下」：照听懂的那一下写进账本（先在一份副本上试一下，拿到要说的那句话，也先知道记不记得上）。
    func chatDo(_ a: P3Chat.Action) -> Bool {
        guard case let .phrase(q, account) = a else { return false }
        var trial = book
        let line: String
        do { line = try trial.record(q, account: account) }
        catch let e as TrialError { fail(e.message); return false }
        catch { fail("没记上，再试一次"); return false }
        let kind: ChangeRecord.Kind
        switch q.kind {
        case .spend, .income: kind = .add
        case .repay: kind = .repay
        default: kind = .transfer
        }
        return change(line, kind: kind) { _ = try $0.record(q, account: account) }
    }

    func chatSendImage(_ image: Image) {
        withAnimation(.snappy(duration: 0.2)) { chat.messages.append(.init(who: .me, image: image)) }
        chat.waitingPrice = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.snappy(duration: 0.25)) { self.chat.messages.append(.init(who: .xia, text: "这是什么？多少钱？比如「跑鞋 95」")) }
        }
    }

    func chatMark(_ id: UUID, _ done: String) {
        if let i = chat.messages.firstIndex(where: { $0.id == id }) { chat.messages[i].done = done }
    }
}

struct P3ChatView: View {
    var inTab = false
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @FocusState private var typing: Bool
    @State private var voice = SpeechDictation()
    @State private var camera = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if inTab {
                    Color.clear.frame(width: 44, height: 44)
                } else {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(P3.ink)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("返回")
                }
                Spacer()
                Text("夏夏").font(P3.font(17, .bold)).foregroundStyle(P3.ink)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 6)
            .background(P3.bg)
            P3Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        Text((state.isReal ? "" : "示例账本 · ") + (state.ai.hasKey ? "夏夏用 OpenRouter 回话，只带算好的几个数" : "没填密钥，夏夏按固定规则回话")).font(P3.font(11.5, .regular)).foregroundStyle(P3.ink2).padding(.top, 8)
                        if state.chat.messages.isEmpty {
                            Text("问我还能花多少、这个要不要买，或者直接说一句「咖啡 3,5」我帮你记。").font(P3.font(14, .regular)).foregroundStyle(P3.ink2)
                                .multilineTextAlignment(.center).padding(.top, 40).padding(.horizontal, 24)
                        }
                        ForEach(state.chat.messages) { m in
                            bubble(m).id(m.id)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: state.chat.messages.count) { _, _ in
                    if let last = state.chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onAppear { if let last = state.chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .background(P3.hex(0xEDEDF2))

            inputBar
        }
        .background(P3.bg)
        .fullScreenCover(isPresented: $camera) {
            P3Camera { img in
                camera = false
                if let img { state.chatSendImage(Image(uiImage: img)) }
            }
            .ignoresSafeArea()
        }
        .onAppear { runIntent() }
        .onChange(of: state.chatIntent) { _, _ in runIntent() }
        .onChange(of: voice.error) { _, e in if let e { state.fail(e) } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let img = try? await item.loadTransferable(type: Image.self) { state.chatSendImage(img) }
                photo = nil
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { _ = await P3Permissions.camera(); camera = true }
            } label: {
                Image(systemName: "camera").font(.system(size: 20)).foregroundStyle(P3.ink).frame(width: 38, height: 40)
            }
            .accessibilityLabel("拍一张问夏夏要不要买")
            PhotosPicker(selection: $photo, matching: .images) {
                Image(systemName: "photo").font(.system(size: 19)).foregroundStyle(P3.ink).frame(width: 38, height: 40)
            }
            .accessibilityLabel("从相册选一张")
            P3MicButton(voice: voice, live: { text = $0 }) { said in
                if P3Permissions.autoSend { state.chatSend(said); text = "" } else { text = said }
            }
            TextField(voice.listening ? "在听，说完停一下就发" : "问夏夏，比如「想买跑鞋 95」", text: $text)
                .font(P3.font(15.5, .regular))
                .focused($typing)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                .submitLabel(.send)
                .onSubmit(send)
            if !text.isEmpty {
                Button("发送", action: send).font(P3.font(15, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 36).background(Capsule().fill(P3.navy))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(P3.hex(0xF6F6F8))
        .overlay(alignment: .top) { P3Divider() }
    }

    private func runIntent() {
        guard let i = state.chatIntent else { return }
        state.chatIntent = nil
        switch i {
        case .camera: Task { _ = await P3Permissions.camera(); camera = true }
        case .voice:
            P3Permissions.prepare(voice)
            voice.toggle(live: { text = $0 }) { said in
                if P3Permissions.autoSend { state.chatSend(said); text = "" } else { text = said }
            }
        }
    }

    private func send() {
        state.chatSend(text)
        text = ""
    }

    @ViewBuilder private func bubble(_ m: P3Chat.Msg) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if m.who == .me { Spacer(minLength: 50) }
            if m.who == .xia {
                P3.face(m.check != nil ? "think" : "talk").resizable().scaledToFill().frame(width: 40, height: 40)
                    .background(P3.soft).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 8) {
                if let img = m.image {
                    img.resizable().scaledToFit().foregroundStyle(P3.navy).frame(maxWidth: 160, maxHeight: 180).padding(m.text.isEmpty ? 14 : 0)
                }
                if !m.text.isEmpty {
                    Text(m.text).font(P3.font(15.5, .regular)).foregroundStyle(P3.ink).fixedSize(horizontal: false, vertical: true)
                }
                if let c = m.check { checkCard(c, m) }
                if let a = m.action, m.done.isEmpty {
                    HStack(spacing: 8) {
                        Button("记下") { if state.chatDo(a) { state.chatMark(m.id, "记好了") } }
                            .buttonStyle(.p3(.primary, .small))
                        Button("不记") { state.chatMark(m.id, "没记") }.buttonStyle(.p3(.ghost, .small))
                    }
                }
                if !m.done.isEmpty { P3Tag(text: m.done, tone: .green) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(m.who == .me ? P3.hex(0xA9C3FF) : .white))
            if m.who == .me {
                Image(systemName: "person.fill").font(.system(size: 18)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(P3.sky))
            }
            if m.who == .xia { Spacer(minLength: 30) }
        }
    }

    private func checkCard(_ c: PurchaseCheck, _ m: P3Chat.Msg) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(c.name) \(c.price.p3Short)").font(P3.font(15.5, .heavy)).foregroundStyle(P3.ink)
                Spacer()
                P3Tag(text: c.verdict == .ok ? "买得起" : c.verdict == .wait ? "先等等" : "先别买", tone: c.verdict == .ok ? .green : c.verdict == .wait ? .gold : .red)
            }
            Text(c.line).font(P3.font(15, .bold)).foregroundStyle(c.verdict == .no ? P3.red : P3.ink)
            VStack(alignment: .leading, spacing: 3) {
                fact("买完这个月还能随便花", c.leftAfter.p3Short, c.leftAfter < .zero ? P3.red : P3.navy)
                if let d = c.days { fact("等于平时几天的花销", "\(d) 天", P3.navy) }
                if let w = c.weeksLate { fact("从目标里拿，晚到", "\(w) 周", P3.navy) }
            }
            if m.done.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button("先放着想想（48 小时）") {
                        if state.change("放进想要清单了：\(c.name)", kind: .edit, { try $0.addWanted(name: c.name, price: c.price) }) { state.chatMark(m.id, "放进想要清单了") }
                    }
                    .buttonStyle(.p3(.ghost, .small))
                    if state.book.journey.total > .zero {
                        Button("不买了，钱存进目标") {
                            if state.change("算你忍住一次 +\(c.price.p3Short)", kind: .goalDeposit, { _ = try $0.holdBack(name: c.name, amount: c.price) }) { state.chatMark(m.id, "忍住了，存进目标") }
                        }
                        .buttonStyle(.p3(.primary, .small))
                    }
                    Button("买了，记一笔") {
                        let from = state.dailyName
                        if state.change("记好了 · \(c.name) \(c.price.p3) · \(from)", kind: .add, {
                            try $0.record(name: c.name, emoji: "🛍", amount: c.price, account: from, tag: "问过夏夏")
                        }) { state.chatMark(m.id, "记好了") }
                    }
                    .buttonStyle(.p3(.ghost, .small))
                }
            }
        }
        .frame(minWidth: 230, alignment: .leading)
    }

    private func fact(_ l: String, _ v: String, _ c: Color) -> some View {
        HStack {
            Text(l).font(P3.font(13, .regular)).foregroundStyle(P3.ink2)
            Spacer()
            Text(v).font(P3.num(14, .bold)).foregroundStyle(c)
        }
    }
}
#endif
