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
                        V3Ask(face: "calm", text: "这家店付现金还是刷卡？只问这一次。") {
                            HStack(spacing: 8) {
                                Button("现金") { save(q, "现金") }.buttonStyle(.v3(.primary, .small))
                                Button("日常卡") { save(q, "日常卡") }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                    } else {
                        V3Ask(face: "think", text: text.trimmingCharacters(in: .whitespaces).isEmpty ? "说一句就行，比如「午饭 12,5」「打车 15」。" : "没听出多少钱，带上数字再说一遍？", tone: text.trimmingCharacters(in: .whitespaces).isEmpty ? .plain : .warn)
                    }
                } else {
                    V3Ask(face: "think", text: way == 1 ? "试用版还没接手机。正式版里拍了就到这儿。"
                          : "流水拖到「流水」那页就行，重复的会跳过。") {
                        if way == 2 { Button("去流水页") { close(); state.go(.transactions) }.buttonStyle(.v3(.primary, .small)) }
                    }
                }
                HStack(spacing: 10) {
                    V3Label("记完还剩：这个月能随便花 \((state.book.month.left - (way == 0 ? q?.amount ?? .zero : .zero)).v3)")
                    Spacer()
                    Button("自己填") { close(); state.open(.manual) }.buttonStyle(.v3(.ghost)).help("金额、店、分类、账户、哪天，自己一样样填")
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

// MARK: - 改动记录

struct V3LogPage: View {
    static func emoji(_ k: ChangeRecord.Kind) -> String {
        switch k {
        case .add, .capture: "✏️"
        case .categorize: "🏷"
        case .importBatch: "📥"
        case .goalDeposit, .goal: "⭐"
        case .subscription: "🔁"
        case .account: "🏦"
        case .debt, .repay: "💳"
        case .delete, .remove: "🗑"
        case .transfer: "🔄"
        default: "📝"
        }
    }
    @Environment(V3State.self) private var state
    @State private var filter = "全部"
    private var whos: [String] { ["全部", state.author, "Claude", "夏夏", "流水导入", "拍小票"] }

    var body: some View {
        let items = state.ledger.changes.filter { filter == "全部" || $0.author == filter }
        V3Cols(left: 1.6, right: 1) {
            V3GrowCard(spacing: 4) {
                V3CardTitle(title: "今天") { EmptyView() } trail: {
                    HStack(spacing: 10) {
                        Text("\(items.filter { !$0.undone }.count) 次改动").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                    }
                }
                if items.isEmpty { V3Label("「\(filter)」今天没有改过什么。").padding(.top, 10) }
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(9).enumerated()), id: \.element.id) { i, item in
                        if i > 0 { V3Divider() }
                        HStack(spacing: 12) {
                            V3Ico(emoji: Self.emoji(item.kind))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.summary).font(V3.font(14, .bold)).lineLimit(1).strikethrough(item.undone).foregroundStyle(item.undone ? V3.ink2 : V3.ink)
                                Text(item.createdAt.formatted(date: .omitted, time: .shortened)).font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                            }
                            Spacer(minLength: 6)
                            V3Tag(text: item.author, tone: item.author == "夏夏" ? .green : item.author == "Claude" ? .gold : .blue)
                            if item.undone { V3Tag(text: "已撤销", tone: .blue) }
                            if state.ledger.canUndo(item.id) {
                                Button("撤销") { state.undo(change: item.id) }
                                    .buttonStyle(.v3(.ghost, .small))
                                    .accessibilityLabel("撤销：\(item.summary)")
                                    .help("它后面做的也会一起撤回")
                            }
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
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        V3Label("这个月", size: 12.5)
                        Text("自己进来 96 笔 · 你手记 \(4 + state.ledger.changes.filter { !$0.undone && $0.author == state.author && $0.kind == .add }.count) 笔").font(V3.num(16)).contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(V3.bg))
                }
            }
        }
    }
}
#endif
