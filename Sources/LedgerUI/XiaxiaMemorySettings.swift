import FinanceCore
import SwiftUI

// 设置 →「夏夏的记忆」。设计稿 2026-11-23 ming 确认：三格切换、搜索、记一条、每条的菜单、空状态；
// 之后说好再加每月「整理」提示条和「重要」标记。
// 约定（和设置页那边定的）：这个 View 就是整页，自己加 .kitPage()，不包 NavigationStack，标题由外面给。
// 规则都在 FinanceCore/Memory.swift，这里只画界面、调它的方法。写入记在「你」名下，都进改动记录，能撤销。

struct XiaxiaMemorySettings: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.horizontalSizeClass) var sizeClass
    /// 截图和检查用：-XiaxiaMemoryTab rule / topic / lesson 直接停在某一格。
    @State var kind = Memory.Kind(rawValue: UserDefaults.standard.string(forKey: "XiaxiaMemoryTab") ?? "") ?? .topic
    @State var query = ""
    @State var editor: MemoryEditor.Mode?
    @State var forgetting: Memory?
    @State var renaming: Memory?
    @State var renameText = ""
    @State var tidying = false
    @State var error: String?
    /// Mac 上面板一打开，系统会把光标塞给第一个输入框。搜索框先关一下，等面板出来再开，光标就不会被它抢走。
    #if os(macOS)
    @State var searchReady = false
    #else
    @State var searchReady = true
    #endif

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 这一格里的（标了重要的排前面）；在搜的时候三类一起搜。
    private var shown: [Memory] {
        if searching { return model.ledger.searchMemories(query, limit: 50).map(\.memory) }
        let list = model.ledger.memories(kind: kind)
        return list.filter(\.pinned) + list.filter { !$0.pinned }
    }

    var body: some View {
        let tidy = model.ledger.memoryTidyList()
        VStack(alignment: .leading, spacing: 14) {
            if let problem = model.loadError {
                notice(tr("账本读不出来，记忆也就看不了"), detail: problem, symbol: "exclamationmark.triangle.fill", color: .alert)
            } else if model.isLoading {
                ProgressView(tr("正在读账本…")).frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if model.ledger.memories.isEmpty {
                intro(tidyCount: 0, showAdd: false)
                emptyState
                howItWorks
            } else {
                intro(tidyCount: tidy.count, showAdd: true)
                if !tidy.isEmpty, model.ledger.memoryTidyDue() { tidyBanner(tidy.count) }
                controls
                Text(caption).font(.caption).foregroundStyle(Color.fg2).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
                let list = shown
                if list.isEmpty {
                    Text(searching ? tr("没搜到和「\(query)」有关的记忆。") : tr("「\(kind.label)」里还没有东西。"))
                        .font(.callout).foregroundStyle(Color.fg2)
                        .frame(maxWidth: .infinity).padding(.vertical, 28)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
                } else {
                    VStack(spacing: 8) { ForEach(list) { card($0) } }
                }
                howItWorks
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
        .kitPage()
        #if os(macOS)
        .task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            searchReady = true
        }
        #endif
        .sheet(item: $editor) { mode in
            // 记完跳到它所在的那一格，不然记了却「没出来」。
            NavigationStack { MemoryEditor(mode: mode) { saved in kind = saved; query = "" } }
                .environment(model).tint(Color.brand).sheetSize(width: 480, height: 540)
        }
        .sheet(isPresented: $tidying) {
            NavigationStack { MemoryTidySheet() }
                .environment(model).tint(Color.brand).sheetSize(width: 520, height: 540)
        }
        .confirmationDialog(tr("彻底忘掉「\(forgetting?.title ?? "")」？"),
                            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                            titleVisibility: .visible) {
            Button(tr("彻底忘掉"), role: .destructive) {
                if let m = forgetting { model.perform { try $0.forgetMemory(m.id, author: model.author) } }
                forgetting = nil
            }
            Button(tr("取消"), role: .cancel) { forgetting = nil }
        } message: {
            Text(tr("连改动记录里留着的那段话一起抹掉，找不回来，也不能撤销。只是不想让它出现在这里的话，用「删掉」就行。"))
        }
        .alert(tr("改话题名"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(tr("这件事叫什么"), text: $renameText)
            Button(tr("取消"), role: .cancel) { renaming = nil }
            Button(tr("改名")) {
                guard let m = renaming else { return }
                renaming = nil
                do { try model.edit { try $0.editMemory(m.id, title: renameText, author: model.author) } }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text(tr("写话题，不写结论：「工资」，不是「工资涨了」。")) }
        .errorAlert($error)
    }

    // MARK: 上面几块

    private func intro(tidyCount: Int, showAdd: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(tr("夏夏和你连上的 AI 都读这一份，所以越用越懂你。记错了随时改，不想让它记的直接删。"))
                .font(.callout).foregroundStyle(Color.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if showAdd {
                if tidyCount > 0, !model.ledger.memoryTidyDue() {
                    Button(tr("整理 · \(tidyCount)")) { tidying = true }
                        .buttonStyle(.soft)
                        .accessibilityLabel(tr("整理记忆，有 \(tidyCount) 条可能用不上了"))
                }
                Button { editor = .new(kind) } label: { Label(tr("记一条"), systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("memory-add")
            }
        }
    }

    private func tidyBanner(_ count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill").font(.title3).foregroundStyle(Color.ai).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("该整理了：有 \(count) 条可能用不上了")).font(.callout.weight(.semibold))
                Text(tr("到期的、半年没用上的、挂的东西已经没了的。夏夏不会自己删，你看一眼再决定。"))
                    .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(tr("看一看")) { tidying = true }.buttonStyle(.softAI).accessibilityIdentifier("memory-tidy")
        }
        .padding(12)
        .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous).strokeBorder(Color.aiLine, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        let picker = Picker(tr("看哪一类"), selection: $kind) {
            ForEach(Memory.Kind.allCases, id: \.self) { k in
                Text("\(k.label) · \(model.ledger.memories(kind: k).count)").tag(k)
            }
        }
        .pickerStyle(.segmented).labelsHidden()
        .disabled(searching)
        let search = HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.fg3).accessibilityHidden(true)
            TextField(tr("搜记忆"), text: $query).textFieldStyle(.plain).accessibilityIdentifier("memory-search")
                .disabled(!searchReady)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Color.fg3).accessibilityLabel(tr("清空搜索"))
            }
        }
        .padding(.horizontal, 10).frame(minHeight: 30)
        .background(Color.sunken, in: RoundedRectangle(cornerRadius: Kit.buttonRadius, style: .continuous))
        return Group {
            if sizeClass == .compact {
                VStack(spacing: 10) { picker; search }
            } else {
                HStack(spacing: 12) { picker; search.frame(width: 200) }
            }
        }
    }

    private var caption: String {
        if searching { return tr("三类一起搜：标题、挂的东西、每一行都算。") }
        switch kind {
        case .rule: return tr("高频、确定的约定。每次聊天夏夏都会先看这几条，所以要少而准（最多 \(Memory.maxRuleLines) 行，现在 \(model.ledger.ruleLineCount) 行）。")
        case .topic: return tr("一件事一条。聊到相关的，夏夏才把那一条翻出来。")
        case .lesson: return tr("上次怎么做的、踩过什么坑。AI 做这类事之前先看，免得再错一次。")
        }
    }

    private var howItWorks: some View {
        (Text(tr("夏夏是怎么记的：")).fontWeight(.semibold)
            + Text(tr("你亲口说的直接记；它自己从流水里看出来的，会先问你一句；工资、房租这些数字不记，每次现算；卡号、密码从来不记。每个月提醒你整理一次，不会自己删。")))
            .font(.caption).foregroundStyle(Color.fg2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func notice(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(color).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
        }
        .padding(.vertical, 28).padding(.horizontal, 16).frame(maxWidth: .infinity)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
    }

    // MARK: 还没有记忆

    static let meetPrompt = tr("先认识一下我：翻一遍我的流水，把你看出来的规律（固定的收入和开销、常去的地方、分类上的习惯）一条一条问我，我说对的你再记进记忆。")

    private var emptyState: some View {
        AskAIReader { ask in
            VStack(spacing: 10) {
                Image(systemName: "brain.head.profile").font(.system(size: 36)).foregroundStyle(Color.ai).accessibilityHidden(true)
                Text(tr("夏夏还没记住什么")).font(.headline)
                Text(tr("跟夏夏聊天时说一句「记住：转给妈妈的钱不算支出」，它就会记在这里。你也可以自己写一条。"))
                    .font(.subheadline).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                    .frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button { editor = .new(kind) } label: { Label(tr("记一条"), systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("memory-add")
                    Button(tr("让夏夏先认识我")) { ask(Self.meetPrompt, page: "夏夏的记忆") }
                        .buttonStyle(.softAI)
                }
                .padding(.top, 4)
                Text(tr("「让夏夏先认识我」：夏夏翻一遍流水，把看出来的规律一条条问你，你说对的才记。"))
                    .font(.caption).foregroundStyle(Color.fg2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 28).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
        }
    }

    // MARK: 一条记忆

    private func card(_ m: Memory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(m.title).font(.callout.weight(.semibold)).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                if m.pinned { KitTag(text: tr("重要"), color: .warn, background: .warnSoft) }
                if searching { KitTag(text: m.kind.label) }
                Spacer(minLength: 8)
                menu(m)
            }
            if !m.links.isEmpty {
                HStack(spacing: 6) {
                    ForEach(m.links.prefix(3), id: \.self) { l in
                        KitTag(text: model.memoryLinkLabel(l), color: .brand, background: .brandSoft).lineLimit(1)
                    }
                    if m.links.count > 3 { KitTag(text: tr("还有 \(m.links.count - 3) 个")) }
                }
            }
            ForEach(m.notes) { n in
                if n.id != m.notes.first?.id { Divider() }
                line(m, n)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
    }

    private func line(_ m: Memory, _ n: Memory.Note) -> some View {
        Button { editor = .editLine(m, n) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(n.text).font(.callout).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if let q = n.quote {
                    Text(tr("原话：「\(q)」")).font(.caption).foregroundStyle(Color.fg2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                if let s = n.story {
                    Text(tr("当时：\(s)")).font(.caption).foregroundStyle(Color.fg2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Text(meta(n)).font(.caption).foregroundStyle(Color.fg3)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("点一下改这一行"))
        .contextMenu {
            Button(tr("改一下")) { editor = .editLine(m, n) }
            Button(tr("删掉这一行（能撤销）")) { model.perform { try $0.removeMemory(m.id, noteID: n.id, author: model.author) } }
        }
    }

    /// 「你说的 · 11 月 23 日 · Claude 记下」。
    private func meta(_ n: Memory.Note) -> String {
        var parts = [n.source.label, n.date.friendly]
        if n.source != .written { parts.append(Self.who(n.author) + tr("记下")) }
        if let e = n.editedBy { parts.append(Self.who(e) + tr("改过")) }
        if let r = n.reviewOn { parts.append(tr("\(r.friendly)回头看")) }
        return parts.joined(separator: " · ")
    }

    /// 「Claude 记下」中间留个空；「你记下」不留。
    private static func who(_ name: String) -> String {
        name.unicodeScalars.last.map { $0.isASCII } == true ? name + " " : name
    }

    private func menu(_ m: Memory) -> some View {
        Menu {
            Button(tr("加一行")) { editor = .addLine(m) }
            if m.notes.count == 1, let only = m.notes.first {
                Button(tr("改一下")) { editor = .editLine(m, only) }
            }
            Button(tr("改话题名")) { renameText = m.title; renaming = m }
            Button(m.pinned ? tr("不再标成重要") : tr("标成重要（整理时不问）")) {
                model.perform { try $0.editMemory(m.id, pinned: !m.pinned, author: model.author) }
            }
            ForEach(Memory.Kind.allCases.filter { $0 != m.kind }, id: \.self) { k in
                Button(tr("挪到「\(k.label)」")) { model.perform { try $0.editMemory(m.id, kind: k, author: model.author) } }
            }
            Divider()
            Button(tr("删掉（能撤销）")) { model.perform { try $0.removeMemory(m.id, author: model.author) } }
            Button(tr("彻底忘掉（找不回来）"), role: .destructive) { forgetting = m }
        } label: {
            Image(systemName: "ellipsis").font(.callout.weight(.semibold)).foregroundStyle(Color.fg2)
                .frame(width: 30, height: 26)
                .background(Color.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
        .accessibilityLabel(tr("「\(m.title)」的更多操作"))
    }
}

/// 记忆页弹成一个面板时用（现在的设置页、-XiaxiaSheet memory）：加上标题和「完成」。
struct XiaxiaMemoryPanel: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        XiaxiaMemorySettings()
            .navigationTitle(tr("夏夏的记忆"))
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("完成")) { dismiss() } } }
    }
}

// MARK: - 记一条 / 加一行 / 改一行

struct MemoryEditor: View {
    enum Mode: Identifiable {
        case new(Memory.Kind)
        case addLine(Memory)
        case editLine(Memory, Memory.Note)

        var id: String {
            switch self {
            case .new(let k): "new-\(k.rawValue)"
            case .addLine(let m): "add-\(m.id.uuidString)"
            case .editLine(_, let n): "edit-\(n.id.uuidString)"
            }
        }
    }

    let mode: Mode
    /// 新记了一条之后叫一声：它落在哪一类（同名话题会并进已有的那条，类别跟着那条走）。
    var onSaved: (Memory.Kind) -> Void = { _ in }
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss
    @State var kind: Memory.Kind = .topic
    @State var title = ""
    @State var text = ""
    @State var links: [String] = []
    @State var hasReview = false
    @State var review = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State var similar: [String]?
    @State var error: String?
    @State var loaded = false

    private var isNew: Bool { if case .new = mode { return true }; return false }
    private var target: Memory? {
        switch mode {
        case .new: nil
        case .addLine(let m): m
        case .editLine(let m, _): m
        }
    }
    private var editingNote: Memory.Note? { if case .editLine(_, let n) = mode { return n }; return nil }
    private var showsLinks: Bool { if case .addLine = mode { return false }; return true }

    /// 已经有同名的话题：会加在它下面。
    private var existing: Memory? {
        let key = MemorySearch.key(title)
        guard isNew, !key.isEmpty else { return nil }
        return model.ledger.memories.first { MemorySearch.key($0.title) == key }
    }

    private var canSave: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText && (!isNew || !title.trimmingCharacters(in: .whitespaces).isEmpty) && text.count <= Memory.maxText
    }

    var body: some View {
        Form {
            if isNew {
                Section {
                    Picker(tr("放在哪"), selection: $kind) {
                        ForEach(Memory.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(tr("这件事叫什么"), text: $title, prompt: Text(tr("比如：工资、转给妈妈的钱")))
                        .accessibilityIdentifier("memory-title")
                } footer: {
                    if let existing {
                        Text(tr("已经有「\(existing.title)」这一条了，会加在它下面，不另开一条。")).foregroundStyle(Color.ai)
                    } else {
                        Text(kindNote)
                    }
                }
            } else if let target {
                Section { LabeledContent(tr("话题"), value: target.title) }
            }
            Section {
                TextField(tr("要夏夏记住什么"), text: $text, prompt: Text(tr("一句话说清，比如：明年 1 月起涨一点。")), axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("memory-text")
            } footer: {
                Text(tr("\(text.count)/\(Memory.maxText) 个字。「明年」「下个月」会自动换成具体的时间，免得过一阵看不懂。卡号、密码别写在这里。"))
                    .foregroundStyle(text.count > Memory.maxText ? Color.alert : Color.fg2)
            }
            Section {
                Toggle(tr("到某一天回头看看还对不对"), isOn: $hasReview)
                if hasReview { DatePicker(tr("哪天"), selection: $review, displayedComponents: .date) }
            } footer: { Text(tr("会过时的事（比如「明年 3 月退健身房」）设一个日子，到了每月整理时会提醒你。")) }
            if showsLinks {
                Section {
                    ForEach(links, id: \.self) { l in
                        HStack {
                            Text(model.memoryLinkLabel(l))
                            Spacer()
                            Button { links.removeAll { $0 == l } } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(Color.fg3)
                                .accessibilityLabel(tr("不挂在 \(model.memoryLinkLabel(l)) 上"))
                        }
                    }
                    Menu(tr("加一个账户、分类、账本、订阅或目标")) {
                        Menu(tr("分类")) { ForEach(model.usedCategories.prefix(30), id: \.self) { c in Button(c) { attach("category:\(c)") } } }
                        Menu(tr("账户")) { ForEach(model.visibleAccounts) { a in Button(a.name) { attach("account:\(a.id)") } } }
                        Menu(tr("账本")) { ForEach(model.ledger.books) { b in Button(b.name) { attach("book:\(b.id)") } } }
                        if !model.ledger.subscriptions.isEmpty {
                            Menu(tr("订阅")) { ForEach(model.ledger.subscriptions.filter(\.isActive)) { s in Button(s.name) { attach("subscription:\(s.name)") } } }
                        }
                        if !model.ledger.goals.isEmpty {
                            Menu(tr("目标")) { ForEach(model.ledger.goals) { g in Button(g.name) { attach("goal:\(g.name)") } } }
                        }
                    }
                } header: { Text(tr("跟哪个有关（可以不选）")) } footer: {
                    Text(tr("选了以后，聊到这个分类或这个账户，夏夏会自动想起这一条。"))
                }
            }
            if let similar {
                Section {
                    Text(tr("已经有相近的话题：\(similarTitles(similar))。是同一件事的话，把上面的名字改成一样的，就会加在它下面。"))
                        .foregroundStyle(Color.ai)
                    Button(tr("是另一件事，还是另开一条")) { save(allowNew: true) }
                }
            }
            if let error { Section { Text(error).foregroundStyle(Color.alert) } }
            if let m = target, let n = editingNote {
                Section {
                    Button(tr("删掉这一行（能撤销）"), role: .destructive) {
                        model.perform { try $0.removeMemory(m.id, noteID: n.id, author: model.author) }
                        dismiss()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? tr("记一条") : editingNote == nil ? tr("加一行") : tr("改一下"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(editingNote == nil ? tr("记下") : tr("保存")) { save(allowNew: false) }
                    .disabled(!canSave)
                    .accessibilityIdentifier("memory-save")
            }
        }
        .onAppear(perform: load)
    }

    private var kindNote: String {
        switch kind {
        case .rule: tr("规矩：每次聊天都照做的约定，要少而准。写话题不写结论，比如「转给妈妈的钱」。")
        case .topic: tr("记得的事：一件事一条，聊到了夏夏才翻出来。写话题不写结论，比如「工资」。")
        case .lesson: tr("做事经验：导入、对账这类事踩过的坑。名字用任务名，比如「导入对账单」。")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .new(let k): kind = k
        case .addLine(let m): kind = m.kind
        case .editLine(let m, let n):
            kind = m.kind
            text = n.text
            links = m.links
            if let r = n.reviewOn { hasReview = true; review = r.asDate }
        }
    }

    /// 「1a2b3c4d「工资」」→「工资」：id 是给 AI 用的，不给人看。
    private func similarTitles(_ list: [String]) -> String {
        list.map { item in item.firstIndex(of: "「").map { String(item[$0...]) } ?? item }.joined(separator: "、")
    }

    private func attach(_ link: String) {
        if !links.contains(link) { links.append(link) }
    }

    private func save(allowNew: Bool) {
        error = nil
        similar = nil
        let reviewOn: LocalDate? = hasReview ? LocalDate(review) : nil
        let who = model.author
        do {
            switch mode {
            case .new:
                let landed = existing?.kind ?? kind
                try model.edit {
                    try $0.remember(kind: kind, title: title, text: text, source: .written, reviewOn: reviewOn, links: links,
                                    allowNew: allowNew, author: who)
                }
                onSaved(landed)
            case .addLine(let m):
                try model.edit {
                    try $0.remember(kind: m.kind, title: m.title, text: text, source: .written, reviewOn: reviewOn, into: m.id, author: who)
                }
            case .editLine(let m, let n):
                let newText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let textChanged = newText != n.text
                let reviewChanged = reviewOn != n.reviewOn
                let linksChanged = links != m.links
                guard textChanged || reviewChanged || linksChanged else { dismiss(); return }
                let newReview: LocalDate?? = reviewChanged ? .some(reviewOn) : .none
                try model.edit { ledger in
                    var last: ChangeRecord?
                    if textChanged || reviewChanged {
                        last = try ledger.updateMemoryNote(m.id, noteID: n.id, text: textChanged ? newText : nil, reviewOn: newReview, author: who)
                    }
                    if linksChanged { last = try ledger.editMemory(m.id, links: links, author: who) }
                    guard let last else { throw MemoryError.nothingToChange }
                    return last
                }
            }
            dismiss()
        } catch MemoryError.similarExists(let list) {
            similar = list
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 每月整理

struct MemoryTidySheet: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let list = model.ledger.memoryTidyList()
        let removable = list.filter(\.removable)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("这些可能用不上了。清掉的能在改动记录里撤销；留着的半年内不再问。规矩和标了「重要」的不会出现在这里。"))
                    .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                if list.isEmpty {
                    Label(tr("都整理好了，没有要清的。"), systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(Color.income)
                        .frame(maxWidth: .infinity).padding(.vertical, 28)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
                }
                ForEach(list) { row($0) }
                if removable.count > 1 {
                    Button(tr("这 \(removable.count) 条都清掉")) {
                        model.perform { try $0.tidyMemories(remove: removable, author: model.author) }
                    }
                    .buttonStyle(.softAlert)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.pageBackground)
        .navigationTitle(tr("整理记忆"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("好了")) { finish(); dismiss() }.accessibilityIdentifier("memory-tidy-done")
            }
        }
    }

    private func row(_ item: MemoryTidyItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title).font(.callout.weight(.semibold))
            Text(item.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text(item.why).font(.caption).foregroundStyle(Color.warn).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                if item.removable {
                    Button(tr("留着")) { model.perform { try $0.keepMemory(item.memoryID, author: model.author) } }
                        .buttonStyle(.soft)
                        .accessibilityLabel(tr("留着「\(item.title)」"))
                    Button(tr("清掉")) { model.perform { try $0.tidyMemories(remove: [item], author: model.author) } }
                        .buttonStyle(.softAlert)
                        .accessibilityLabel(tr("清掉「\(item.title)」"))
                } else {
                    AskAIReader { ask in
                        Button(tr("让夏夏并一并")) {
                            ask(tr("把记忆里「\(item.title)」下面的几行并成一两句，意思不能丢，并之前先念给我听。"), page: "夏夏的记忆")
                            dismiss()
                        }
                        .buttonStyle(.softAI)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
    }

    /// 看过一遍了：记下「整理过」，一个月内不再提醒。（中途清过东西的话已经记过了。）
    private func finish() {
        guard model.ledger.memoryTidyDue() else { return }
        _ = try? model.edit(quiet: true) { try $0.tidyMemories(remove: [], author: model.author) }
    }
}

// MARK: - 给设置页和别处用

extension LedgerModel {
    /// 设置那一行右边的小字。
    var memorySummary: String {
        let n = ledger.memoryLineCount
        if n == 0 { return tr("还没记住什么") }
        return ledger.memoryTidyDue() ? tr("记得 \(n) 件事 · 该整理了") : tr("记得 \(n) 件事")
    }

    /// 「category:工资」→「分类 · 工资」；账户和账本显示名字，不显示 id。
    func memoryLinkLabel(_ link: String) -> String {
        let (kind, name) = Memory.linkParts(link)
        let label = Memory.linkKindLabels[kind] ?? kind
        let shown: String
        switch kind {
        case "account": shown = accountName(name)
        case "book": shown = bookName(name)
        default: shown = name
        }
        return label.isEmpty ? shown : "\(label) · \(shown)"
    }
}
