#if os(macOS)
import FinanceCore
import SwiftUI
import UniformTypeIdentifiers

// 每一页除了「有数据」以外的三种样子（规格稿）：没数据、在读、出错。
// 没数据：一句话 + 该点的按钮；在读：灰块占住位置；出错：说人话，告诉你账没丢。

extension V3State {
    enum Forced: String { case loading, error }

    /// 重新读取账本：先出「在读」的样子，再回来。
    func reload() {
        withAnimation(.easeOut(duration: 0.15)) { forced = .loading }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.2)) { self?.forced = nil }
            self?.say("读好了，是最新的")
        }
    }

    /// 导入流水。试用版不读真文件：进来的是示例里的那几笔，重复的跳过，整批能撤销。
    /// 先去流水页，顶上一条进度走几秒，走完才真的进账本，底下提示条说进来几笔。
    func importSample(dropped: Bool = false) {
        guard importProgress == nil else { return }
        let rows = Self.demoBook.entries
        let total = 40
        if showsLife { go(.transactions) }
        withAnimation(.snappy(duration: 0.2)) { importProgress = (dropped ? "放进来的文件" : "示例流水", 0, total) }
        importTask = Task { @MainActor [weak self] in
            for n in 1...total {
                try? await Task.sleep(for: .milliseconds(55))
                guard let self, !Task.isCancelled, self.importProgress != nil else { return }
                withAnimation(.linear(duration: 0.05)) { self.importProgress?.read = n }
            }
            guard let self, !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) { self.importProgress = nil }
            var result = (added: 0, skipped: 0)
            if self.change("导入好了", kind: .importBatch, { result = try $0.importEntries(rows) }) {
                self.say("进来 \(result.added) 笔\(result.skipped > 0 ? "，跳过重复 \(result.skipped) 笔" : "")（试用版用的是示例流水）") { [weak self] in self?.undo() }
            }
        }
    }

    /// 导入到一半停下：已经读的不进账本。
    func stopImport() {
        importTask?.cancel(); importTask = nil
        withAnimation(.snappy(duration: 0.2)) { importProgress = nil }
        say("停下了，什么都没导进来")
    }

    /// 这一页现在是不是没东西可看。
    func isEmpty(_ p: Page) -> Bool {
        let b = book
        let noMoney = b.owned.allSatisfy { $0.balance == .zero } && b.entries.isEmpty
        switch p {
        case .overview, .wealth: return noMoney
        case .goals: return b.journey.total == .zero
        case .transactions where importProgress != nil: return false
        case .spending, .trends, .transactions, .monthly: return b.entries.filter { $0.side == .life }.isEmpty && noMoney
        case .settings: return false
        case .subscriptions: return b.subscriptions.isEmpty
        case .debts: return b.debts.isEmpty && b.lent.isEmpty
        case .bizHome, .sales, .checkup: return b.shopSalesTotal == .zero
        case .shopWealth: return false
        case .fixed: return b.fixedCosts.isEmpty
        case .payback: return b.capital.isEmpty
        case .stock: return b.stockEstimates.isEmpty
        case .bizDebts: return b.shopDebts.isEmpty && b.shopSalesTotal == .zero
        }
    }
}

struct V3EmptyPage: View {
    let page: V3State.Page
    @Environment(V3State.self) private var state

    private struct Act { let title: String; let run: (V3State) -> Void }

    private var content: (String, String, [Act]) {
        let addAccount = Act(title: "加一个账户") { $0.showAddAccount = true }
        let drop = Act(title: "拖流水进来") { $0.go(.transactions) }
        let record = Act(title: "记一笔") { s in withAnimation(.snappy(duration: 0.2)) { s.showAdd = true } }
        let today = Act(title: "记今天的账") { $0.open(.shopDay($0.book.todayDay)) }
        switch page {
        case .overview: return ("先告诉我你有多少钱", "加一个账户，或者把银行流水拖进来。有了数我才能算这个月还能花多少。", [addAccount, drop])
        case .goals: return ("还没有目标", "不急。想到一件想要的东西再来。", [Act(title: "定一个小目标") { $0.open(.goalNew) }])
        case .wealth: return ("还没有账户里的钱", "加一个银行卡、现金或者信用卡，这里就能算出你的家底。", [addAccount, drop])
        case .spending: return ("这个月还没有花销", "记一笔，或者把银行流水拖进来。", [record, drop])
        case .trends: return ("再等几天", "要有两个星期的流水，我才看得出花钱的速度。", [drop])
        case .transactions: return ("一笔都还没有", "把银行流水拖到窗口里，一个月的账一次进来。", [Act(title: "导入流水") { $0.importSample() }, record])
        case .subscriptions: return ("还没发现订阅", "导入两三个月的流水，每月都扣的那些我会自己找出来。", [Act(title: "自己加一个") { $0.open(.subscription) }, drop])
        case .debts: return ("你不欠钱", "挺好的。借给别人的、分期买的，也可以记在这里。", [Act(title: "记一笔欠款") { $0.open(.debt) }])
        case .monthly: return ("第一份小结下个月 1 日写好", "要有一整个月的账才写得出来。", [])
        case .bizHome: return ("店里还没有账", "先记今天收了多少。记满一个星期，我就能说点有用的。", [today, Act(title: "填开店本钱") { $0.open(.capital) }])
        case .sales: return ("这个月还没记", "每天关门前记一个总数就行，不用记每一单。", [today])
        case .fixed: return ("还没填固定开销", "房租、给自己的工资、水电。填了才知道每天开门要先收多少。", [Act(title: "加一样") { $0.open(.fixed) }])
        case .payback: return ("还没填开店本钱", "填上，我就能算什么时候回本。记不清就填个大概。", [Act(title: "填本钱") { $0.open(.capital) }])
        case .stock: return ("先估一次", "看一眼货架，估个总数就行。以后每个季度估一次。", [Act(title: "现在估") { $0.open(.stock) }])
        case .checkup: return ("第一次体检在季度末", "要有一整个季度的账。", [today])
        case .bizDebts: return ("店里不欠钱", "装修贷款、欠供货商的、熟客挂的账，可以记在这里。", [Act(title: "记一笔欠款") { $0.open(.shopDebt) }])
        case .settings, .shopWealth: return ("", "", [])
        }
    }

    var body: some View {
        let c = content
        let biz = V3State.Page.biz.contains(page)
        VStack(spacing: 12) {
            V3Face(face: "calm", width: 110)
            Text(c.0).font(V3.font(26, .heavy)).foregroundStyle(V3.ink)
            Text(c.1).font(V3.font(15, .regular)).foregroundStyle(V3.ink2).multilineTextAlignment(.center).frame(maxWidth: 440)
            if !c.2.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(c.2.enumerated()), id: \.offset) { i, a in
                        Button(a.title) { a.run(state) }.buttonStyle(.v3(i > 0 ? .ghost : biz ? .teal : .primary))
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v3Soft()
        .onDrop(of: [.fileURL], isTargeted: nil) { _ in
            // 流水页空着时：把文件拖进来就导入（试用版不读真文件，用示例流水）。
            guard page == .transactions else { return false }
            state.importSample(dropped: true)
            return true
        }
        .background {
            // 刚进来、还没有流水：夏夏在顶上说一句，点开就去导入（引导里不再放拖流水）。
            if page == .overview, state.book.entries.isEmpty {
                V3Ask(face: "happy", text: "想省事？把银行流水拖进来，我帮你填") {
                    Button("去导入") { state.closeChat(); state.go(.transactions) }.buttonStyle(.v3(.primary, .small))
                }
                .frame(width: 0, height: 0).hidden()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// 在读：灰色的块占住位置，底下一句「正在读账本…」。
struct V3LoadingPage: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 14) {
            V3Cols(left: 1.35, right: 1) {
                VStack(spacing: 16) { block(160); block(nil) }
            } trailing: {
                VStack(spacing: 16) { block(120); block(nil); block(110) }
            }
            Text("正在读账本…").font(V3.font(14, .semibold)).foregroundStyle(V3.ink2)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
        .accessibilityElement().accessibilityLabel("正在读账本")
    }

    private func block(_ h: CGFloat?) -> some View {
        RoundedRectangle(cornerRadius: 22).fill(V3.soft.opacity(pulse ? 0.9 : 0.5))
            .frame(maxWidth: .infinity).frame(height: h).frame(maxHeight: h == nil ? .infinity : nil)
    }
}

/// 出错：说人话，先告诉你账没丢。
struct V3ErrorPage: View {
    @Environment(V3State.self) private var state
    var body: some View {
        // 流水页有自己的出错：文件读不了（规格稿）。别的页都是账本读不出来。
        let file = state.page == .transactions
        VStack(spacing: 12) {
            V3Face(face: "worried", width: 110)
            Text(file ? "这个文件我读不了" : "账本读不出来").font(V3.font(26, .heavy)).foregroundStyle(V3.ink)
            Text(file ? "你的账没动。换成银行导出的 CSV 再试试；还不行就把文件发给我们看看。" : "你的账没丢，还好好地在 iCloud 云盘的「夏夏账本」文件夹里。可能是它还没同步完。")
                .font(V3.font(15, .regular)).foregroundStyle(V3.ink2).multilineTextAlignment(.center).frame(maxWidth: 440)
            HStack(spacing: 10) {
                if file {
                    Button("换一个文件") { withAnimation(.easeOut(duration: 0.2)) { state.forced = nil } }.buttonStyle(.v3)
                    Button("怎么从银行导出") { state.say("在银行 app 里找「对账单」或「导出」，选 CSV，时间选一个月") }.buttonStyle(.v3(.ghost))
                    Button("发给我们看看") { state.forced = nil; state.open(.feedback) }.buttonStyle(.v3(.ghost))
                } else {
                    Button("重新读取账本") { state.reload() }.buttonStyle(.v3)
                    Button("看看账本在哪") { state.forced = nil; state.page = .settings; state.openSettings(.sync) }.buttonStyle(.v3(.ghost))
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22).fill(V3.warnBG))
    }
}

/// 定一个小目标（空账本里从头开始）。
struct V3GoalNewSheet: View {
    @Environment(V3State.self) private var state
    @State private var name = ""
    @State private var amount = ""
    var body: some View {
        let m = V3Form.amount(amount)
        V3SheetBox(width: 520, title: "定一个小目标", foot: "我会把它拆成几站，一站一站走。", primary: "定下来",
                   canSave: m != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty,
                   save: {
                       guard let m else { return }
                       if state.change("定下来了：\(name) \(m.v3Short)", kind: .goal, { try $0.startGoal(name: name, total: m) }) { state.closeSheet() }
                   }) {
            V3FormField(label: "想要什么", prompt: "换新电脑", text: $name, focus: true)
            V3FormField(label: "一共要多少", prompt: "1400", text: $amount, big: true)
        }
    }
}
#endif
