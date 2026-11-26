import FinanceCore
import SwiftUI

/// 设置 → 数据（ming 2026-11-23：「增一个东西,就是演示数据,以及删除数据」）。
/// - 演示数据：换成内存里的示例账本看看，不写任何文件，退出就回到自己的账本。
/// - 删除数据：全部清空，或只清一个账本。删之前自动把账本文件复制一份，问两次才删。
/// - 从备份恢复：删错了从「删除前备份」里拿回来。
struct DataSettingsPane: View {
    @Environment(LedgerModel.self) var model
    /// 删哪些：nil 是全部，否则是账本 id。
    @State private var bookID: String?
    @State private var askFirst = false
    @State private var askSecond = false
    @State private var typed = ""
    @State private var restoring: LedgerBackup.Item?
    @State private var backups: [LedgerBackup.Item] = []
    @State private var restoringCount: String?
    /// 点「删除…」那一刻定下的范围和数量。两次确认都按它来，期间别处改了账本就不删（审查发现：确认框开着时
    /// 那个账本在别处被删掉，选择会被清成「全部」，再点确认就成了删全部）。
    @State private var pending: WipeConfirmation?

    private var scope: WipeScope { bookID.map { .book($0) } ?? .everything }
    private var count: WipeCount { model.ledger.wipeCount(scope) }
    private var scopeName: String { name(of: scope) }
    private func name(of scope: WipeScope) -> String {
        if case .book(let id) = scope { return tr("「\(model.bookName(id))」账本") }
        return tr("全部数据")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            demoGroup
            wipeGroup
            if !backups.isEmpty && !model.isTryingDemo { restoreGroup }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
        .kitPage()
        .onAppear { backups = model.backups }
        .alert(tr("要删掉\(pending?.name ?? scopeName)吗？"), isPresented: $askFirst) {
            Button(tr("取消"), role: .cancel) { pending = nil }
            Button(tr("继续"), role: .destructive) { typed = ""; askSecond = true }
        } message: {
            Text(tr("会删掉：\((pending?.count ?? count).text)。\(keepNote)\n\n删之前自动备份，删错了能在这一页恢复。"))
        }
        .alert(tr("最后确认一次"), isPresented: $askSecond) {
            TextField(tr("输入「删除」两个字"), text: $typed)
                .accessibilityIdentifier("data.wipe.confirmText")
            Button(tr("取消"), role: .cancel) { pending = nil }
            Button(tr("删除"), role: .destructive) { wipe() }
        } message: {
            Text(tr("在下面输入「删除」两个字，再点删除。"))
        }
        .alert(tr("恢复这份备份吗？"), isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button(tr("取消"), role: .cancel) { restoring = nil }
            Button(tr("恢复")) { restore() }
        } message: {
            Text(tr("这份备份是 \(restoring.map { when($0) } ?? "") 留的\(restoringCount.map { tr("，里面有 \($0)") } ?? "")。\n\n现在的账本也会先备份一份，不会丢。"))
        }
    }

    // MARK: 演示数据

    private var demoGroup: some View {
        group(tr("演示数据"), note: tr("演示数据是编出来的：一个人加一家小花店，一年多的账。看的时候随便点、随便改，都不会进你自己的账本；退出，或者关掉 app 再打开，就回到你自己的账本。")) {
            HStack(spacing: 12) {
                icon("sparkles.rectangle.stack.fill", .ai)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isTryingDemo ? tr("正在看演示数据") : tr("看看演示数据")).font(.callout)
                    Text(model.isTryingDemo ? tr("你自己的账本没动，好好地放着") : tr("先看看每一页有数据时长什么样"))
                        .font(.caption).foregroundStyle(Color.fg2)
                }
                Spacer(minLength: 12)
                if model.isTryingDemo {
                    Button(tr("退出演示")) { withAnimation(.snappy) { model.exitDemo() } }
                        .buttonStyle(.borderedProminent).solidTint()
                        .accessibilityIdentifier("data.demo.exit")
                } else {
                    Button(tr("看看")) { withAnimation(.snappy) { model.enterDemo() } }
                        .buttonStyle(.soft)
                        .accessibilityIdentifier("data.demo.enter")
                }
            }
            .padding(.vertical, 9)
        }
    }

    // MARK: 删除数据

    private var wipeGroup: some View {
        group(tr("删除数据"), note: model.isTryingDemo
              ? tr("现在看的是演示数据，不用删，退出演示就没了。")
              : tr("删之前会自动把账本复制一份，放在账本旁边的「\(LedgerBackup.folderName)」文件夹里。\(model.xiaName)的名字、性格、主币种这些设置不会删。")) {
            if model.ledger.books.count > 1 {
                HStack(spacing: 12) {
                    icon("line.3.horizontal.decrease", .fg3)
                    Text(tr("删哪些")).font(.callout)
                    Spacer(minLength: 12)
                    Picker(tr("删哪些"), selection: $bookID) {
                        Text(tr("全部数据")).tag(String?.none)
                        ForEach(model.ledger.books) { b in Text(tr("只删「\(b.name)」账本")).tag(Optional(b.id)) }
                    }
                    .labelsHidden().fixedSize()
                    .accessibilityIdentifier("data.wipe.scope")
                }
                .padding(.vertical, 9)
                Divider()
            }
            HStack(spacing: 12) {
                icon("trash.fill", .alert)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("删除\(scopeName)")).font(.callout)
                    Text(count.isEmpty ? tr("这里面现在没有东西") : tr("会删掉：\(count.text)"))
                        .font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button(tr("删除…"), role: .destructive) {
                    pending = WipeConfirmation(scope: scope, name: scopeName, ledger: model.ledger)
                    askFirst = true
                }
                    .buttonStyle(.softAlert)
                    .disabled(count.isEmpty || model.isTryingDemo)
                    .accessibilityIdentifier("data.wipe.start")
            }
            .padding(.vertical, 9)
        }
        .onChange(of: model.ledger.books.map(\.id)) { _, ids in
            if let b = bookID, !ids.contains(b) { bookID = nil }
        }
    }

    private var keepNote: String {
        (pending?.scope ?? scope) == .everything ? "" : tr("账本和账户留着，余额会跟着变。")
    }

    // MARK: 从备份恢复

    private var restoreGroup: some View {
        group(tr("从备份恢复"), note: tr("每次删除前、恢复前自动留的备份，只留最近 10 份。")) {
            ForEach(Array(backups.prefix(3).enumerated()), id: \.element.id) { i, b in
                if i > 0 { Divider() }
                HStack(spacing: 12) {
                    icon("clock.arrow.circlepath", .income)
                    Text(label(b)).font(.callout)
                    Spacer(minLength: 12)
                    Button(tr("恢复")) {
                        // 先看一眼备份里有多少东西，确认框里说出来，好判断是不是要的那份。
                        restoringCount = (try? LedgerBackup.load(b.url)).map { $0.wipeCount(.everything).text }
                        restoring = b
                    }
                        .buttonStyle(.soft)
                        .accessibilityIdentifier("data.restore.\(i)")
                }
                .padding(.vertical, 9)
            }
        }
    }

    /// 「11 月 23 日 14:05」
    private func when(_ b: LedgerBackup.Item) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 HH:mm"
        return f.string(from: b.date)
    }

    /// 「11 月 23 日 14:05 · 删除前」
    private func label(_ b: LedgerBackup.Item) -> String {
        "\(when(b)) · \(b.url.lastPathComponent.contains("恢复前") ? tr("恢复前") : tr("删除前"))"
    }

    // MARK: 动作

    private func wipe() {
        // 中文「删除」总能用；换了语言时，界面让输入的是译好的那个词，也认（不分大小写）。
        let word = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word == "删除" || word.caseInsensitiveCompare(tr("删除")) == .orderedSame else {
            model.toast = .init(text: tr("没有删：要输入「删除」两个字才行"), changeID: nil, isError: true)
            return
        }
        guard let frozen = pending else { return }
        pending = nil
        // 两次确认之间账本变了（那个账本被删了、别处记了账）：不删，让人看清楚再来一次。
        guard frozen.stillValid(in: model.ledger) else {
            model.toast = .init(text: tr("没有删：账本刚刚有变化，请重新看一眼再删"), changeID: nil, isError: true)
            return
        }
        let name = frozen.name
        do {
            let backup = try model.wipe(frozen.scope)
            backups = model.backups
            bookID = nil
            model.toast = .init(text: backup == nil ? tr("已删除\(name)") : tr("已删除\(name)。删之前的备份留好了，可以在这一页恢复"),
                                changeID: nil, seconds: 6)
        } catch {
            model.toast = .init(text: tr("没有删：\(error.localizedDescription)"), changeID: nil, isError: true)
        }
    }

    private func restore() {
        guard let b = restoring else { return }
        restoring = nil
        do {
            try model.restore(b)
            backups = model.backups
            model.toast = .init(text: tr("已恢复成 \(when(b)) 那份备份"), changeID: nil, seconds: 5)
        } catch {
            model.toast = .init(text: tr("没有恢复：\(error.localizedDescription)"), changeID: nil, isError: true)
        }
    }

    // MARK: 排版（和设置别的二级页一个样子）

    private func group<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.fg2).padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
            if let note {
                Text(note).font(.caption).foregroundStyle(Color.fg2).padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 26, height: 26).background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 正在看演示数据时，每一页顶上的一条：说清楚这是编的，旁边就是「退出演示」。
struct DemoBanner: View {
    @Environment(LedgerModel.self) var model

    var body: some View {
        if model.isTryingDemo {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(Color.ai)
                Text(tr("正在看演示数据，都是编的。你自己的账本没动。"))
                    .font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(tr("退出演示")) { withAnimation(.snappy) { model.exitDemo() } }
                    .buttonStyle(.borderedProminent).solidTint().controlSize(.small)
                    .accessibilityIdentifier("demo.banner.exit")
            }
            .padding(.horizontal, Kit.side).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.aiSoft)
            .accessibilityElement(children: .contain)
        }
    }
}


/// 删除数据的确认：点「删除…」时把范围和那一刻的整本账本定下来；最后点「删除」时账本只要有一点不一样
/// （删了一笔又记一笔、重建了同名账本……）就不删，让人重新确认。磁盘上已经被别处改过、界面还没刷新的情况，
/// 由保存时的校验拦住（LedgerModel.wipe → store.save）。
struct WipeConfirmation: Equatable {
    let scope: WipeScope
    let name: String
    let count: WipeCount
    private let snapshot: Ledger

    init(scope: WipeScope, name: String, ledger: Ledger) {
        self.scope = scope
        self.name = name
        self.count = ledger.wipeCount(scope)
        self.snapshot = ledger
    }

    /// 和点「删除…」时的账本一模一样，才按当时给人看的范围删。
    func stillValid(in ledger: Ledger) -> Bool { ledger == snapshot }
}
