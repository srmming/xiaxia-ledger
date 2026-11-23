import FinanceCore
import SwiftUI

// 自己建分类：先挑一个图标，再填名字。也能给已有的分类换图标。
// 图标目录在 FinanceCore 的 CategoryIcons（由 design/icon-kit/build.py 生成），fin / MCP 用的是同一份。

/// 按分组排的图标格子，上面能搜（按中文名）。
struct CategoryIconGrid: View {
    @Binding var selection: XiaGlyph?
    /// 按名字猜的那个图标，没挑的时候淡淡地圈出来。
    var suggestion: XiaGlyph? = nil
    /// 建收入分类时把「收入」那组放最前面。
    var incomeFirst = false
    @State private var search = ""

    private var sections: [(key: String, label: String, icons: [XiaGlyph])] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            var seen = Set<XiaGlyph>()
            let hits = CategoryIcons.all.filter { $0.label.contains(q) || $0.name.contains(q.lowercased()) }
                .compactMap { XiaGlyph(rawValue: $0.name) }.filter { seen.insert($0).inserted }
            return [("search", hits.isEmpty ? tr("没有叫「\(q)」的图标，换个说法试试") : tr("找到 \(hits.count) 个"), hits)]
        }
        let all = CategoryIcons.sections.map { ($0.key, $0.label, $0.icons.compactMap(XiaGlyph.init(rawValue:))) }
        return incomeFirst ? all.filter { $0.0 == "income" } + all.filter { $0.0 != "income" } : all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                XiaGlyph.actSearch.image(size: 15).foregroundStyle(Color.fg3)
                TextField(tr("搜图标，比如「咖啡」「房租」"), text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel(tr("按名字搜图标"))
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.fg3) }
                        .buttonStyle(.plain).accessibilityLabel(tr("清掉搜索"))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.sunken, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            ForEach(sections, id: \.key) { sec in
                VStack(alignment: .leading, spacing: 6) {
                    Text(sec.label).font(.footnote.weight(.semibold)).foregroundStyle(Color.fg2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62, maximum: 80), spacing: 4)], spacing: 4) {
                        ForEach(sec.icons, id: \.self) { g in cell(g) }
                    }
                }
            }
        }
    }

    private func cell(_ g: XiaGlyph) -> some View {
        let picked = selection == g
        let suggested = selection == nil && suggestion == g
        return Button { selection = g } label: {
            VStack(spacing: 4) {
                XiaTile(glyph: g, size: 38)
                Text(g.label).font(.caption2).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(picked ? .primary : Color.fg2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(picked ? Color.brandSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(picked ? Color.brand.opacity(0.6) : (suggested ? Color.brand.opacity(0.35) : .clear),
                              style: StrokeStyle(lineWidth: picked ? 1.5 : 1, dash: suggested ? [3, 3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(g.label)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// 新建分类：上面是预览（图标 + 名字），中间填名字、选支出还是收入，下面挑图标。
/// 没挑图标时按名字自动配一个（虚线圈出来），点「建好了」就用它。
struct CategoryCreator: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    var income = false
    var initialName = ""
    /// 记一笔里方向已经定了，就不再让选支出 / 收入。
    var showsDirection = true
    /// 名字已经有了就直接用它（记一笔里），不报错；挑了图标就顺手换上。
    var allowExisting = false
    /// 建好后把名字交回去（记一笔里用来直接选中）。
    var onCreated: (String) -> Void = { _ in }

    @State private var name = ""
    @State private var isIncome = false
    @State private var icon: XiaGlyph?
    @State private var error: String?
    /// 名字是点图标时自动填的（再点别的图标就跟着换；自己改过就不动）。
    @State private var autoName: String?
    @FocusState private var nameFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var guess: XiaGlyph? {
        let g = CategoryStyle.glyph(trimmed)
        return trimmed.isEmpty || g == .other ? nil : g
    }
    private var shown: XiaGlyph { icon ?? guess ?? .other }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    XiaTile(glyph: shown, size: 60)
                        .animation(.snappy, value: shown)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(tr("分类名字，比如「奶茶」"), text: $name)
                            .font(.title3.weight(.semibold))
                            .textFieldStyle(.plain)
                            .focused($nameFocused)
                            .onSubmit(save)
                            .accessibilityLabel(tr("分类名字"))
                        if showsDirection {
                            Picker(tr("用在"), selection: $isIncome) {
                                Text(tr("支出")).tag(false)
                                Text(tr("收入")).tag(true)
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            .frame(maxWidth: 200)
                        } else {
                            Text(isIncome ? tr("收入分类") : tr("支出分类")).font(.subheadline).foregroundStyle(Color.fg2)
                        }
                    }
                }
                .padding(14)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))

                Text(icon == nil
                     ? (guess == nil ? tr("先在下面点一个图标，名字会跟着填好，想改再改。") : tr("按名字先配了「\(guess!.label)」，想换就在下面点一个。"))
                     : (autoName == nil ? tr("选了「\(icon!.label)」。") : tr("选了「\(icon!.label)」，名字也先填上了，想改就改。")))
                    .font(.subheadline).foregroundStyle(Color.fg2)

                CategoryIconGrid(selection: $icon, suggestion: guess, incomeFirst: isIncome)
            }
            .padding(Kit.side)
        }
        .background(Color.pageBackground)
        .navigationTitle(tr("新建分类"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("建好了"), action: save).disabled(trimmed.isEmpty)
            }
        }
        .errorAlert($error)
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 560, minHeight: 380, idealHeight: 520)
        #endif
        .onAppear { name = initialName; isIncome = income }
        // 先挑图标：名字空着（或还是上次自动填的）就用图标的名字，点一下图标再点「建好了」就行。
        // 不一上来就弹键盘：iPhone 上键盘会把图标格子挡掉一半。
        .onChange(of: icon) { _, g in
            guard let g, trimmed.isEmpty || trimmed == autoName else { return }
            name = g.label; autoName = g.label
        }
        .onChange(of: name) { _, n in if n != autoName { autoName = nil } }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        let picked = (icon ?? guess)?.rawValue
        do {
            try model.edit { try $0.addCategory(trimmed, income: isIncome, icon: picked, author: model.author) }
            onCreated(trimmed)
            dismiss()
        } catch ManageError.duplicateName(_) where allowExisting {
            do {
                if let icon { try model.edit { try $0.setCategoryIcon(trimmed, icon: icon.rawValue, author: model.author) } }
                onCreated(trimmed)
                dismiss()
            } catch { self.error = error.localizedDescription }
        } catch { self.error = error.localizedDescription }
    }
}

/// 给已有分类换图标。
struct CategoryIconEditor: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    let category: String
    @State private var icon: XiaGlyph?
    @State private var error: String?

    private var custom: Bool { model.ledger.categoryIcons[category] != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    XiaTile(glyph: icon ?? CategoryStyle.glyph(category), size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category).font(.title3.weight(.semibold))
                        Text(custom ? tr("你挑过图标") : tr("现在是按名字自动配的")).font(.subheadline).foregroundStyle(Color.fg2)
                    }
                    Spacer()
                    if custom {
                        Button(tr("改回自动")) { set(nil) }.buttonStyle(.soft)
                    }
                }
                .padding(14)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
                CategoryIconGrid(selection: $icon)
            }
            .padding(Kit.side)
        }
        .background(Color.pageBackground)
        .navigationTitle(tr("换图标"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("换好了")) { set(icon?.rawValue) }.disabled(icon == nil)
            }
        }
        .errorAlert($error)
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 560, minHeight: 380, idealHeight: 520)
        #endif
    }

    private func set(_ name: String?) {
        do {
            try model.edit { try $0.setCategoryIcon(category, icon: name, author: model.author) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
