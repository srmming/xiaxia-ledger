import FinanceCore
import SwiftUI

/// 设置：AI 连上了吗？同步正常吗？
struct SettingsPage: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.openURL) var openURL
    @State var name = ""
    @FocusState var nameFocused: Bool
    @State var manage: AppSheet?
    @AppStorage("xiaxia.appearance") var appearance = "auto"

    var body: some View {
        Columns(sideWidth: 420, breakpoint: 820) {
            group("AI 连接（MCP）", note: "Claude、Codex 这些 AI 通过 MCP 读写同一本账。「用过账本」是 AI 最近一次打开账本的时间。") {
                #if os(macOS)
                AIStatusRows()
                Button {
                    Clipboard.copy(model.aiSetupPrompt)
                    model.toast = .init(text: "已复制，粘贴给你的 AI，它会自己配好", changeID: nil)
                } label: {
                    item(symbol: "text.bubble.fill", color: .ai, title: "复制一段话，让 AI 自己配好") {
                        Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(Color.fg3)
                    }
                }
                .buttonStyle(.plain)
                Button { model.sheet = .connectAI } label: {
                    item(symbol: "link", color: .ai, title: "连上你的 AI（Claude、Codex、Cursor…）") {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.fg3)
                    }
                }
                .buttonStyle(.plain)
                #else
                ForEach(model.aiTools) { t in
                    item(monogram: Monogram.author(t.name, isMe: false, size: 26), title: t.name) {
                        StatusDot(color: .income, text: "\(t.last.friendly) 写过").foregroundStyle(Color.fg2)
                    }
                }
                ConnectAIPhoneNote().padding(.vertical, 8)
                #endif
            }
            group("你") {
                item(symbol: "person.fill", color: .brand, title: "记账的人") {
                    TextField("你的名字", text: $name)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 160)
                        .focused($nameFocused)
                        .onSubmit { saveName(); nameFocused = false }
                }
                Text("你在 app 里记的、改的，改动记录里都记在这个名字下，流水上标「你」。").font(.caption).foregroundStyle(Color.fg2)
                    .padding(.horizontal, 4).padding(.top, 4)
            }
            group("夏夏怎么跟你说话", note: "夏夏在每页说的话、复制给 AI 的话、AI 写回来的意见，都按这个口吻。跟着账本同步。") {
                PersonaPicker()
            }
        } side: {
            group("同步") {
                item(symbol: "icloud.fill", color: Color.kit(0x0A84FF, 0x409CFF), title: "状态") {
                    StatusDot(color: model.loadError == nil ? .income : .alert, text: model.loadError == nil ? "账本已读到" : "读不出来")
                        .foregroundStyle(Color.fg2)
                }
                item(symbol: "doc.fill", color: .fg3, title: "账本文件") {
                    Text(ledgerLocation(model.store)).font(.caption).foregroundStyle(Color.fg2).lineLimit(2)
                        .multilineTextAlignment(.trailing).textSelection(.enabled)
                }
            }
            group("币种", note: "每个账户可以有自己的币种。外币的每一笔记原来的金额和当天汇率，看板上的总数换成主币种；银行实际扣了多少，就以银行为准。取汇率只下载欧洲央行的公开汇率表，不会发出任何账目。") {
                CurrencySettingsRows()
            }
            group("账本、账户和分类") {
                ForEach(model.ledger.books) { b in
                    let n = model.ledger.bookUsage(b.id).transactions
                    item(monogram: Monogram(text: b.name, color: model.bookColor(b.id), size: 26), title: b.name) {
                        Text("\(n) 笔流水").foregroundStyle(Color.fg2)
                    }
                }
                manageRow("books.vertical", "管理账本（新建、改名、删除）", .books)
                manageRow("building.columns", "管理账户（\(model.ledger.accounts.count) 个）", .accounts)
                manageRow("square.grid.2x2", "管理分类", .categories)
            }
            group("隐私和外观") {
                item(symbol: "eye.slash.fill", color: .fg3, title: "显示私房钱") {
                    Toggle("显示私房钱", isOn: Bindable(model).showPrivate).labelsHidden().toggleStyle(.switch)
                }
                item(symbol: "circle.lefthalf.filled", color: .fg3, title: "外观") {
                    Picker("外观", selection: $appearance) {
                        Text("自动").tag("auto"); Text("浅色").tag("light"); Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            group("帮助与反馈") {
                Button { open("https://github.com/srmming/xiaxia-ledger/issues/new") } label: {
                    item(symbol: "exclamationmark.bubble.fill", color: .alert, title: "反馈问题 / 提个想法") {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.fg3)
                    }
                }
                .buttonStyle(.plain)
                item(symbol: "info.circle.fill", color: .fg3, title: "版本") { Text(version).foregroundStyle(Color.fg2) }
            }
        }
        .kitPage()
        // 设置在 iPhone 上本身就是弹出的一页，管理页从这里再弹一层，不走总的 sheet。
        .sheet(item: $manage) { sheet in
            NavigationStack {
                switch sheet {
                case .books: BookManager()
                case .accounts: AccountManager()
                default: CategoryManager()
                }
            }
            .environment(model)
            .tint(Color.brand)
            #if os(macOS)
            .frame(width: 520, height: 580)
            #endif
        }
        .onAppear {
            name = model.author
            // 别让名字框一打开就抢走光标（Mac 会把第一个输入框自动选中）。
            DispatchQueue.main.async { nameFocused = false }
        }
        .onDisappear { saveName() }
    }

    private func manageRow(_ symbol: String, _ title: String, _ sheet: AppSheet) -> some View {
        Button { manage = sheet } label: {
            item(symbol: symbol, color: .brand, title: title) {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.fg3)
            }
        }
        .buttonStyle(.plain)
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v)（\($0)）" } ?? v
    }

    private func saveName() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty, n != model.author { model.author = n }
    }

    private func open(_ s: String) { if let u = URL(string: s) { openURL(u) } }

    private func group<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.fg2).padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
            if let note { Text(note).font(.caption).foregroundStyle(Color.fg2).padding(.horizontal, 4) }
        }
    }

    private func item<Trailing: View>(symbol: String, color: Color, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        item(monogram: nil, symbol: symbol, color: color, title: title, trailing: trailing)
    }

    private func item<Trailing: View>(monogram: Monogram?, symbol: String = "", color: Color = .fg3, title: String,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            if let monogram { monogram } else {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Text(title).font(.callout)
            Spacer(minLength: 12)
            trailing().font(.callout)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
