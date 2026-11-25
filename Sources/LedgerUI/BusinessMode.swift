import FinanceCore
import SwiftUI

// 生意模式的界面部分（设计稿 design/mockups/business-mode.html v2，2026-11-25）。
// 规则都在 FinanceCore（Business.swift、BusinessReport.swift、SideGuess.swift），这里只调用。

extension Side {
    /// 界面上的叫法：生活 / 生意。
    var uiLabel: String { self == .business ? tr("生意") : tr("生活") }
}

/// 打开「记一笔」前预先填好的：生意首页「记今天进账」、零碎开销那几个按钮用。
public struct AddPreset: Equatable {
    public var income: Bool
    public var category: String?
    public var bookID: String?
}

extension LedgerModel {
    /// 生意模式开着，而且对得上生意账本。关着时界面和以前完全一样。
    var businessOn: Bool { ledger.business?.enabled == true && ledger.businessBook != nil }

    /// 现在看的是哪一边。
    var side: Side {
        guard businessOn, let id = selectedBookID else { return .life }
        return id == ledger.businessBook?.id ? .business : .life
    }

    /// 顶上「生活 | 生意」切过去：生意 = 生意账本；生活 = 最近记过的那个生活账本。
    func switchSide(_ side: Side) {
        guard let id = ledger.bookID(for: side) else { return }
        selectedBookID = id
        // 两边侧栏不一样：切过去时停在对面没有的页，就回到总览。
        let list = side == .business ? AppSection.businessLook : AppSection.look
        if let s = section, !list.contains(s), ![AppSection.insights, .changes, .transactions, .settings].contains(s) { section = .overview }
    }

    /// 开着生意模式时不看「全部」：落到某一边（第一次按开模式时选的那边，没选过就生活）。
    func settleSide() {
        guard businessOn else { return }
        if let id = selectedBookID, ledger.books.contains(where: { $0.id == id }) { return }
        switchSide(ledger.business?.startSide ?? .life)
    }

    /// 刚记的一笔看着像记错了边（在生意这边记了「书包」）：夏夏马上挪过去，底部提示能撤销。
    /// 拿不准就不动（SideGuess 只在很有把握时才给建议）。
    func checkSide(_ id: UUID) {
        guard businessOn, let tx = transaction(id) else { return }
        guard let guess = SideGuess.guess(tx, current: ledger.side(of: tx), ledger: ledger) else { return }
        do {
            let change = try edit(quiet: true) { try $0.moveToSide(id, side: guess.to, author: xiaName) }
            let what = guess.to == .life ? tr("家里的开销") : (tx.amount.isIncome ? tr("店里的进账") : tr("店里的开销"))
            toast = Toast(text: tr("「\(tx.description) \(tx.amount.balance)」看着像\(what)，已放到\(guess.to.uiLabel)"),
                          changeID: change.canUndo ? change.id : nil, seconds: 6)
        } catch {
            // 挪不了就留在原处，不打扰。
        }
    }

    /// 在生意那边新加的账户就算店里的（ming 2026-11-25：在哪边加就属哪边）。生活那边加的本来就算生活，不用记。
    func claimNewAccount(_ id: String) {
        guard businessOn, side == .business else { return }
        _ = try? edit(quiet: true) { try $0.setAccountSide(id, side: .business, author: author) }
    }

    /// 生意首页上的按钮：打开记一笔，按预设填好。
    func addWith(_ preset: AddPreset) {
        addPreset = preset
        editingID = nil
        sheet = .add
    }
}

/// 顶上的「生活 | 生意」两格（开着生意模式时代替账本菜单）。
struct SideSwitch: View {
    @Environment(LedgerModel.self) var model
    var body: some View {
        let selection = Binding(get: { model.side }, set: { s in withAnimation(.snappy) { model.switchSide(s) } })
        Picker(tr("生活还是生意"), selection: selection) {
            Text(Side.life.uiLabel).tag(Side.life)
            Text(Side.business.uiLabel).tag(Side.business)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .tint(model.side == .business ? Color.shop : Color.brand)
        .help(tr("切换看生活还是生意；在哪边就默认记到哪边"))
        .accessibilityIdentifier("sideSwitch")
        .task(id: model.ledger.business) { model.settleSide() }
    }
}
