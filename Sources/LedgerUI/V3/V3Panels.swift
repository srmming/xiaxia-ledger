#if os(macOS)
import AppKit
import FinanceCore
import SwiftUI
import UniformTypeIdentifiers

// 记一笔（弹出来的面板）、问夏夏（右边滑出来）、设置、改动记录。

// MARK: - 记一笔

struct V3AddSheet: View {
    @Environment(V3State.self) private var state
    /// 用哪种方式记：0 说一句、1 自己填、2 拖文件。记住上次用的。
    @AppStorage("xiaxia.v3.addWay") private var way = 0
    @State private var text = ""
    /// 这句话没说怎么付时，问一次；默认先指着第一个。
    @State private var pay = 0
    @State private var receipt: NSImage?
    @State private var picking = false
    @State private var dropping = false
    @FocusState private var focused: Bool
    static let ways = ["说一句", "自己填", "拖文件"]

    /// 话里提到的哪天（「昨天」「上周五」「12 号」）；没提就是今天。日期那几个字先拿掉再认金额。
    private var said: (daysAgo: Int, rest: String) { QuickDate.extract(text, today: state.book.todayDate) ?? (0, text) }
    private var parsed: QuickPhrase? { QuickPhrase.parse(said.rest) }
    private var accounts: [String] { state.book.accounts(for: .pay, side: .life).map(\.name) }
    /// 话里自己说了怎么付（「现金」「刷卡」或者账户的名字）。
    private var saidAccount: String? {
        if let hit = accounts.first(where: { text.contains($0) }) { return hit }
        if text.contains("现金"), accounts.contains("现金") { return "现金" }
        if text.contains("刷卡") || text.contains("卡付"), let card = accounts.first(where: { $0.contains("卡") }) { return card }
        return nil
    }

    var body: some View {
        ZStack {
            V3.ink.opacity(0.42).onTapGesture { close() }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    // 三段等宽：先选用哪种方式，下面才出现那种方式的内容
                    HStack(spacing: 0) {
                        ForEach(Array(Self.ways.enumerated()), id: \.offset) { i, w in
                            Button { withAnimation(.snappy(duration: 0.2)) { way = i } } label: {
                                Text(w).font(V3.font(14, .bold)).foregroundStyle(way == i ? .white : V3.ink)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background { if way == i { Capsule().fill(V3.navy) } }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                            .accessibilityAddTraits(way == i ? .isSelected : [])
                        }
                    }
                    .padding(3).background(Capsule().fill(V3.soft))
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 26, height: 26) }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("关掉")
                }
                switch way {
                case 1: V3ManualSheet(embedded: true) { close() }
                case 2: fileWay
                default: sayWay
                }
            }
            .padding(.horizontal, 26).padding(.vertical, 22)
            .frame(width: way == 1 ? 640 : 560)
            .v3Sticker(radius: 26, depth: 6)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { focused = true }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image, .commaSeparatedText, .pdf, .plainText]) { result in
            if case .success(let url) = result { take(file: url) }
        }
    }

    // MARK: 说一句

    @ViewBuilder private var sayWay: some View {
        let q = parsed
        let said = saidAccount
        TextField("咖啡 3,2 现金", text: $text).textFieldStyle(.plain).font(V3.font(22, .heavy)).foregroundStyle(V3.ink).focused($focused)
            .onSubmit { save(q) }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white).overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(V3.ink, lineWidth: 2.5)))
            .accessibilityLabel("说一句")
        if let receipt { receiptChip(receipt) }
        if let q {
            HStack(spacing: 12) {
                V3Ico(emoji: q.emoji, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(q.name).font(V3.font(16, .heavy)).lineLimit(1)
                    Text("\(QuickDate.label(daysAgo: self.said.daysAgo, today: state.book.todayDate)) · \(said ?? (accounts.indices.contains(pay) ? accounts[pay] : ""))").font(V3.font(12.5, .regular)).foregroundStyle(V3.ink2)
                }
                Spacer(minLength: 6)
                V3Amount((-q.amount).v3, size: 22, weight: .heavy)
                Button("改") { state.manualPrefill = (q.name, q.amount); withAnimation(.snappy(duration: 0.2)) { way = 1 } }.buttonStyle(.v3(.ghost, .small)).help("改日期、账户、分类、备注")
            }
            .padding(.horizontal, 16).padding(.vertical, 12).background(RoundedRectangle(cornerRadius: 16).fill(V3.bg))
            if said == nil, accounts.count > 1 {
                HStack(spacing: 8) {
                    Text("怎么付的？").font(V3.font(13, .semibold)).foregroundStyle(V3.ink2)
                    ForEach(Array(accounts.prefix(4).enumerated()), id: \.offset) { i, a in
                        Button { withAnimation(.snappy(duration: 0.12)) { pay = i } } label: {
                            Text(a).font(V3.font(13, .bold)).foregroundStyle(pay == i ? .white : V3.ink)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(pay == i ? V3.navy : .white).overlay(Capsule().strokeBorder(V3.ink, lineWidth: 1.5)))
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(pay == i ? .isSelected : [])
                    }
                }
            }
        } else if !text.trimmingCharacters(in: .whitespaces).isEmpty || receipt != nil {
            Text(receipt != nil ? "多少钱？" : "没听出多少钱，带上数字再说一遍").font(V3.font(13.5, .semibold)).foregroundStyle(V3.ink2)
        }
        HStack(spacing: 10) {
            V3Label("记完这个月还能随便花 \((state.book.month.left - (q?.amount ?? .zero)).v3)", size: 13)
            Spacer(minLength: 8)
            Button("记好 ↩") { save(q) }.buttonStyle(.v3).disabled(q == nil)
            // ⌘↩：记好，清空接着记下一笔
            Button("") { save(q, keepOpen: true) }.keyboardShortcut(.return, modifiers: .command).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }

    // MARK: 拖文件

    @ViewBuilder private var fileWay: some View {
        Button { picking = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 30, weight: .semibold)).foregroundStyle(V3.navy)
                Text("把小票照片或银行流水拖到这里").font(V3.font(16, .heavy)).foregroundStyle(V3.ink)
            }
            .frame(maxWidth: .infinity).frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 20).fill(dropping ? V3.goodBG : V3.soft)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(V3.ink, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))))
            .contentShape(Rectangle())
        }
        .buttonStyle(V3SinkStyle(depth: 2)).help("也可以点开选一个文件")
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in take(file: url) }
            }
            return true
        }
    }

    private func receiptChip(_ img: NSImage) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: img).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("小票").font(V3.font(13, .bold))
            Button { withAnimation(.snappy(duration: 0.15)) { receipt = nil } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(V3.ink2).frame(width: 20, height: 20)
            }
            .buttonStyle(.plain).accessibilityLabel("去掉这张小票")
        }
        .padding(6).background(RoundedRectangle(cornerRadius: 12).fill(V3.bg))
    }

    /// 放进来的文件：图片当小票（试用版不识别，补一句金额）；别的当银行流水导入（试用版用示例那几笔）。
    private func take(file url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let img = NSImage(contentsOf: url) {
            receipt = img
            withAnimation(.snappy(duration: 0.2)) { way = 0 }
            focused = true
        } else {
            close()
            state.importSample(dropped: true)
        }
    }

    private func save(_ q: QuickPhrase?, keepOpen: Bool = false) {
        guard let q else { return }
        let account = saidAccount ?? (accounts.indices.contains(pay) ? accounts[pay] : accounts.first ?? "")
        guard state.record(q, account: account, place: receipt != nil ? "小票" : "", daysAgo: said.daysAgo) else { return }
        text = ""; receipt = nil
        if keepOpen { focused = true } else { close() }
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
