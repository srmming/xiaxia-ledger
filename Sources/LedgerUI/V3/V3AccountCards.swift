#if os(macOS)
import SwiftUI
import FinanceCore

/// 家底页共用的两样：上面一排置顶的「银行卡」，下面其余账户的紧凑列表。生活和店里都用它，只是各列各的账户。
enum V3CardLook {
    /// 底色（渐变的两头）和字是不是用深色。顺序和 `Account.cardLook` 对应。
    static let all: [(a: Color, b: Color, dark: Bool, name: String)] = [
        (V3.hex(0x26306E), V3.hex(0x4A5BC0), false, "深蓝"),
        (V3.hex(0x4E7FE6), V3.hex(0x8FB6FF), false, "天蓝"),
        (V3.hex(0x17707E), V3.hex(0x3FB0AE), false, "青"),
        (V3.hex(0xF0B647), V3.hex(0xFBDD8C), true, "金"),
        (V3.hex(0xFFD9D4), V3.hex(0xFFF1EE), true, "浅粉"),
        (V3.hex(0xFFFFFF), V3.hex(0xE6ECFF), true, "白"),
    ]
    static func of(_ a: V3State.Account) -> (a: Color, b: Color, dark: Bool, name: String) { all[min(max(a.cardLook, 0), all.count - 1)] }

    /// 右上角表示种类的小图标。
    static func symbol(_ a: V3State.Account) -> String {
        switch a.kind {
        case .shop: a.name.contains("现金") ? "banknote.fill" : "storefront.fill"
        case .debt: a.isCreditCard ? "creditcard.fill" : "doc.text.fill"
        case .lent: "person.fill"
        case .secret: "eye.slash.fill"
        case .own: a.block == .goal ? "star.fill" : a.block == .emergency ? "building.columns.fill" : a.name.contains("现金") ? "banknote.fill" : "creditcard.fill"
        }
    }

    /// 列表里那一行小字：是什么种类。
    static func kind(_ a: V3State.Account) -> String {
        switch a.kind {
        case .shop: a.name.contains("现金") ? "店里的现金" : "店里的账户"
        case .debt: a.isCreditCard ? "信用卡 · 欠的" : "欠的"
        case .lent: "借出去的"
        case .secret: "私房钱"
        case .own: a.block == .goal ? "存在目标里" : a.block == .emergency ? "应急钱" : a.name.contains("现金") ? "现金" : "日常能用"
        }
    }
}

/// 一张银行卡样子的账户卡：左上名字，右上种类图标，右下余额大字。欠的余额是红的。
struct V3BankCard: View {
    let account: V3State.Account
    var width: CGFloat = 222
    static let ratio: CGFloat = 1.586

    var body: some View {
        let look = V3CardLook.of(account)
        let ink: Color = look.dark ? V3.ink : .white
        let money: Color = account.isDebt ? (look.dark ? V3.red : V3.hex(0xFFB9B2)) : ink
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(account.name).font(V3.font(15.5, .heavy)).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: V3CardLook.symbol(account)).font(.system(size: 13, weight: .bold)).foregroundStyle(ink.opacity(0.9))
                    .frame(width: 30, height: 30).background(Circle().fill(ink.opacity(look.dark ? 0.08 : 0.18)))
            }
            Text(V3CardLook.kind(account)).font(V3.font(12, .semibold)).foregroundStyle(ink.opacity(0.72)).lineLimit(1).padding(.top, -6)
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                V3Amount(account.balance.v3, color: money, size: 23, weight: .heavy).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: width, height: (width / Self.ratio).rounded())
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [look.a, look.b], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(V3.ink, lineWidth: 2.5))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(V3.ink).offset(y: 4))
        .padding(.bottom, 4)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.name)，\(account.isDebt ? "欠 " : "")\(account.balance.v3)")
    }
}

/// 置顶的那一排卡片：点一下改这个账户，按住拖动换先后，右键能取消置顶。
struct V3PinnedCards: View {
    let side: TrialBook.Side
    @Environment(V3State.self) private var state
    @State private var dragging: String?
    @State private var shift: CGFloat = 0
    private let w: CGFloat = 222, gap: CGFloat = 14

    var body: some View {
        let cards = state.book.pinned(on: side)
        HStack(spacing: gap) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, a in
                V3BankCard(account: a, width: w)
                    .offset(x: dragging == a.name ? shift : 0)
                    .zIndex(dragging == a.name ? 1 : 0)
                    .scaleEffect(dragging == a.name ? 1.03 : 1)
                    .onTapGesture { state.accountFocus = a.name; state.open(.accounts) }
                    .gesture(DragGesture(minimumDistance: 10)
                        .onChanged { v in dragging = a.name; shift = v.translation.width }
                        .onEnded { v in
                            let to = min(max(i + Int((v.translation.width / (w + gap)).rounded()), 0), cards.count - 1)
                            withAnimation(.snappy(duration: 0.2)) { dragging = nil; shift = 0 }
                            if to != i { state.change("排好了：\(a.name)挪到第 \(to + 1) 张", kind: .account) { try $0.movePin(a.name, to: to) } }
                        })
                    .contextMenu { V3AccountMenu(account: a) }
                    .help("点一下改这个账户，按住能拖着换先后")
            }
            if cards.count < AccountCards.maxPinned, !state.book.listed(on: side).isEmpty {
                Menu {
                    ForEach(state.book.listed(on: side).flatMap(\.accounts)) { a in
                        Button("\(a.emoji) \(a.name)") { state.change("置顶了：\(a.name)", kind: .account) { try $0.setPinned(a.name, true) } }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                        Text("置顶一个").font(V3.font(13, .bold))
                    }
                    .foregroundStyle(side == .biz ? V3.teal : V3.navy)
                    .frame(width: 104, height: (w / V3BankCard.ratio).rounded())
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(V3.dash, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .padding(.bottom, 4)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.25), value: cards.map(\.id))
    }
}

/// 右键菜单：置顶 / 取消置顶、换先后、改这个账户。
struct V3AccountMenu: View {
    let account: V3State.Account
    @Environment(V3State.self) private var state

    var body: some View {
        let b = state.book
        let pins = b.pinned(on: account.side)
        if let i = pins.firstIndex(where: { $0.id == account.id }) {
            if i > 0 { Button("往前挪") { state.change("排好了：\(account.name)往前挪了", kind: .account) { try $0.movePin(account.name, to: i - 1) } } }
            if i < pins.count - 1 { Button("往后挪") { state.change("排好了：\(account.name)往后挪了", kind: .account) { try $0.movePin(account.name, to: i + 1) } } }
            if pins.count > 1 { Button("取消置顶") { state.change("取消置顶了：\(account.name)", kind: .account) { try $0.setPinned(account.name, false) } } }
        } else if account.kind != .secret {
            Button("置顶成卡片") { state.change("置顶了：\(account.name)", kind: .account) { try $0.setPinned(account.name, true) } }
        }
        Divider()
        Button("改这个账户") { state.accountFocus = account.name; state.open(.accounts) }
    }
}

/// 没置顶的账户：按小标题分组，一行一个。放得下就一栏，多了分成两栏。
struct V3AccountList: View {
    let side: TrialBook.Side
    /// 生活那边排在最后的私房钱卡。
    var secret: V3State.Account?
    @Environment(V3State.self) private var state

    var body: some View {
        let groups = state.book.listed(on: side)
        let rows = groups.map { $0.accounts.count + 1 }.reduce(0, +) + (secret == nil ? 0 : 2)
        let two = rows > 8
        // 两栏时尽量两边一样长
        let cut: Int = {
            guard two else { return groups.count }
            var seen = 0
            for (i, g) in groups.enumerated() { seen += g.accounts.count + 1; if seen * 2 >= rows - (secret == nil ? 0 : 2) { return i + 1 } }
            return groups.count
        }()
        HStack(alignment: .top, spacing: 16) {
            column(Array(groups.prefix(cut)), secret: two ? nil : secret)
            if two { column(Array(groups.dropFirst(cut)), secret: secret) }
        }
    }

    private func column(_ groups: [TrialBook.AccountGroup], secret: V3State.Account?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(groups) { g in
                Text(g.title).font(V3.font(12.5, .bold)).foregroundStyle(V3.ink2).padding(.top, 6).padding(.leading, 4)
                ForEach(g.accounts) { a in row(a) }
            }
            if let secret { secretRow(secret).padding(.top, 8) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ a: V3State.Account) -> some View {
        Button {
            if side == .life, a.kind == .debt || a.kind == .lent { state.go(.debts) } else { state.accountFocus = a.name; state.open(.accounts) }
        } label: {
            HStack(spacing: 10) {
                V3Ico(emoji: a.emoji, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(a.name).font(V3.font(14, .heavy)).foregroundStyle(V3.ink).lineLimit(1)
                    if V3CardLook.kind(a) != a.name { Text(V3CardLook.kind(a)).font(V3.font(12, .regular)).foregroundStyle(V3.ink2).lineLimit(1) }
                }
                .frame(minHeight: 34)
                Spacer(minLength: 6)
                V3Amount(a.balance.v3, color: a.isDebt ? V3.red : side == .biz ? V3.teal : V3.navy, size: 15.5, weight: .heavy)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(a.isDebt ? V3.hex(0xFFF6F5) : .white))
            .contentShape(Rectangle())
        }
        .buttonStyle(V3SinkStyle(depth: 1))
        .contextMenu { V3AccountMenu(account: a) }
        .help(side == .life && (a.kind == .debt || a.kind == .lent) ? "去欠款与还债" : "改这个账户")
    }

    /// 私房钱：默认藏着，点一下显示几秒，不算进上面的数。
    private func secretRow(_ a: V3State.Account) -> some View {
        Button { state.revealSecret() } label: {
            HStack(spacing: 10) {
                V3Ico(emoji: state.secretShown ? "👀" : "🙈", size: 34)
                Text(a.name).font(V3.font(14, .heavy)).foregroundStyle(V3.ink)
                Spacer(minLength: 6)
                V3Amount(state.secretShown ? a.balance.v3 : "•••••\u{00A0}€", size: 15.5, weight: .heavy)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(V3.dash, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            .contentShape(Rectangle())
        }
        .buttonStyle(V3SinkStyle(depth: 1))
        .accessibilityLabel(state.secretShown ? "私房钱 \(a.balance.v3)" : "私房钱，藏着，点一下显示")
    }
}
#endif
