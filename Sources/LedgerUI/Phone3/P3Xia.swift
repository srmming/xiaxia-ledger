#if os(iOS)
import FinanceCore
import PhotosUI
import SwiftUI

// 问夏夏：像微信的对话页。拍照或贴图问「要不要买」，夏夏按规则算三件事再给一句意见。
// 示例里不连 AI：夏夏的回话是按固定规则写的。

struct P3Chat {
    struct Msg: Identifiable {
        enum Who { case me, xia }
        let id = UUID()
        var who: Who
        var text = ""
        var image: Image?
        var check: PurchaseCheck?
        var quick: QuickPhrase?
        var done = ""
        var time = Date()
    }

    var messages: [Msg] = [
        Msg(who: .xia, text: "照这样花，这个月存钱差一点。周末少点一次外卖就够了。", time: Calendar.current.date(bySettingHour: 2, minute: 17, second: 0, of: Date()) ?? Date()),
    ]
    var unread = 1
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
        } else if let q = QuickPhrase.parse(text) {
            reply = .init(who: .xia, text: "记一笔\(q.name) \(q.amount.p3)，从日常卡出？", quick: q)
        } else {
            reply = .init(who: .xia, text: "这个我先记着。想问要不要买，发张图或者说「想买 xx 多少钱」。")
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.snappy(duration: 0.25)) { self.chat.messages.append(reply) }
        }
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
    @Environment(P3State.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(P3.ink)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("返回")
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
                        Text("示例账本 · 夏夏的回话按固定规则算，不连 AI").font(P3.font(11.5, .regular)).foregroundStyle(P3.ink2).padding(.top, 8)
                        ForEach(state.chat.messages) { m in
                            bubble(m).id(m.id)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
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
            PhotosPicker(selection: $photo, matching: .images) {
                Image(systemName: "camera").font(.system(size: 20)).foregroundStyle(P3.ink).frame(width: 40, height: 40)
            }
            .accessibilityLabel("拍照或选一张图问要不要买")
            PasteButton(payloadType: Image.self) { imgs in
                if let img = imgs.first { Task { @MainActor in state.chatSendImage(img) } }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .tint(P3.navy)
            .accessibilityLabel("贴一张图")
            TextField("问夏夏，比如「想买跑鞋 95」", text: $text, axis: .vertical)
                .lineLimit(1...4)
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
                if let q = m.quick, m.done.isEmpty {
                    HStack(spacing: 8) {
                        Button("记下") {
                            let ok = state.change("记好了 · \(q.name) \(q.amount.p3) · 日常卡", kind: .add) {
                                try $0.record(name: q.name, emoji: q.emoji, amount: q.amount, account: "日常卡", tag: "跟夏夏说的")
                            }
                            if ok { state.chatMark(m.id, "记好了") }
                        }
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
                        if state.change("记好了 · \(c.name) \(c.price.p3) · 日常卡", kind: .add, {
                            try $0.record(name: c.name, emoji: "🛍", amount: c.price, account: "日常卡", tag: "问过夏夏")
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
