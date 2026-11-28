#if os(macOS)
import FinanceCore
import SwiftUI

// 设置里接正式账本的五页：AI 连接、管哪边、钱怎么进来、同步与币种、数据。
// 逻辑一律用旧界面已有的那一套（AIConnector / AISetup、打开生意模式、主币种、汇率、备份、删除数据），这里只是换成新样子。
// 试用数字（没接正式账本）时不走这里，还是原来那几页演示的样子。

extension V3State {
    /// 打开 / 关掉生意那一边（正式账本的「生意模式」）。生活那一边在正式账本里关不掉。
    @discardableResult
    func setBusiness(on: Bool) -> Bool {
        guard let model else { fail("这是试用数字"); return false }
        guard model.businessOn != on else { return true }
        do {
            let who = author
            try model.edit(quiet: true) { l in
                guard on else { return l.disableBusinessMode(author: who) }
                switch try l.enableBusinessMode(author: who) {
                case .enabled(let change): return change
                case .needsChoice: throw TrialError("账本里有好几个生意账本，先回旧界面选一个")
                }
            }
            refreshFromModel(); settleSide()
            say(on ? "好，两边都管" : "好，只管生活。生意的账还在")
            return true
        } catch let e as TrialError { fail(e.message) } catch { fail((error as? LocalizedError)?.errorDescription ?? "没改成，账本没动") }
        return false
    }

    /// 生活这边从流水里认出来、还没问过的固定开销（正式账本自己的认法，和旧界面趋势页是同一份）。
    var fixedGuesses: [Outlook.FixedGuess] {
        guard let real else { return [] }
        return Outlook.fixedGuesses(real, side: .life, today: bookToday)
    }

    /// 回答「这笔算固定的吗」：算 → 加成一条每月自动记的固定开销；不算 → 记进「不算」的名单，以后不再问。都能撤销。
    @discardableResult
    func answerFixedGuess(_ g: Outlook.FixedGuess, fixed: Bool) -> Bool {
        guard let model else { fail("这是试用数字"); return false }
        do {
            let who = author
            let book = g.bookID ?? model.ledger.books.first { !$0.isBusiness }?.id
            let change = try model.edit(quiet: true) { l in
                fixed ? try l.addFixedCost(name: g.name, amount: g.amount, day: g.day, accountID: g.accountID, category: g.category, bookID: book, today: self.bookToday, author: who)
                      : l.markNotFixed(g.key, name: g.name, author: who)
            }
            refreshFromModel()
            noteRealUndo([change.id])
            sayDone(fixed ? "好，「\(g.name)」算固定开销，以后每月 \(g.day) 号自动记" : "好，「\(g.name)」不算固定开销，以后不再问")
            return true
        } catch { fail((error as? LocalizedError)?.errorDescription ?? "没记成，账本没动") }
        return false
    }

    /// 换主币种（总数都换成它）。
    func setBaseCurrency(_ code: String) {
        guard let model else { return }
        do {
            let who = author
            try model.edit(quiet: true) { try $0.setBaseCurrency(code, author: who) }
            refreshFromModel()
            say("主币种改成\(Currencies.info(code).name)了")
            Task { @MainActor [weak self] in await model.refreshRatesIfNeeded(force: true); self?.refreshFromModel() }
        } catch { fail((error as? LocalizedError)?.errorDescription ?? "没改成，账本没动") }
    }

    /// 删掉全部数据：先自动留一份备份（旧界面同一套）。
    func wipeEverything() {
        guard let model else { return }
        do {
            let backup = try model.wipe(.everything)
            refreshFromModel()
            say(backup == nil ? "已删除全部数据" : "已删除全部数据。删之前的备份留好了")
        } catch { fail((error as? LocalizedError)?.errorDescription ?? "没删成，账本没动") }
    }

    func restoreBackup(_ item: LedgerBackup.Item) {
        guard let model else { return }
        do {
            try model.restore(item)
            refreshFromModel()
            say("已恢复成那份备份。恢复之前的样子也留了一份")
        } catch { fail((error as? LocalizedError)?.errorDescription ?? "没恢复成，账本没动") }
    }
}

// MARK: - AI 连接

struct V3RealAIPage: View {
    @Environment(V3State.self) private var state
    /// 点过「连接」以后重新看一遍状态。
    @State private var tick = 0
    @State private var seen: [String: Date] = [:]

    var body: some View {
        let model = state.model
        let connector = model?.aiConnector
        V3SetColumn {
            V3SetGroup(title: "这台 Mac 上的 AI", note: "点「连接」会在那个 AI 自己的设置里加一项「夏夏账本」，改之前先留一份它原来的设置。") {
                if let connector {
                    ForEach(Array(AIApp.allCases.enumerated()), id: \.element) { i, app in
                        let installed = connector.isInstalled(app)
                        let health = connector.health(app, lastSeen: seen[app.rawValue])
                        V3SetRow(title: app.name, detail: installed ? health.title : "这台 Mac 上没有", line: i > 0) {
                            HStack(spacing: 8) {
                                if installed {
                                    V3Tag(text: health.level == .good ? "在用" : health.level == .waiting ? "等重开" : health.level == .problem ? "有问题" : "没连",
                                          tone: health.level == .good ? .green : health.level == .problem ? .gold : .blue)
                                    Button(connector.isConnected(app) ? "重新连接" : "连接") { connect(app, connector) }
                                        .buttonStyle(.v3(connector.isConnected(app) ? .ghost : .primary, .small))
                                }
                            }
                        }
                    }
                } else {
                    V3SetRow(title: "找不到夏夏账本自带的记账工具", detail: "把夏夏账本放进「应用程序」再打开一次", line: false) { EmptyView() }
                }
            }
            .id(tick)
            V3SetGroup(title: "别的 AI", grow: true) {
                V3SetRow(title: "🔗 复制配置指令", sub: "复制一段话，粘给任何 AI，它会自己把夏夏账本配好", line: false) {
                    Button("复制") { state.copy(model?.aiSetupPrompt ?? V3State.configPrompt, say: "已复制，粘贴给你的 AI 就行") }.buttonStyle(.v3(.ghost, .small))
                }
                V3SetLink(title: "决策模型", sub: "夏夏自己拿主意、回答问题用的", value: state.hasOpenRouterKey ? "已填密钥" : "还没填") { state.openSettings(.decision) }
            }
        }
        .onAppear { if model?.usesSampleData == false { seen = AIConnections.load() } }
    }

    private func connect(_ app: AIApp, _ connector: AIConnector) {
        do {
            try AISetup(connector: connector).connect(app)
            tick += 1
            state.say("\(app.name) 连好了。把它关掉重开一次就能用")
        } catch { state.fail((error as? LocalizedError)?.errorDescription ?? "没连上，它的设置没动") }
    }
}

// MARK: - 管哪边

struct V3RealSidesPage: View {
    @Environment(V3State.self) private var state
    var body: some View {
        let now = state.book.managedSides
        V3SetColumn {
            V3SetGroup(title: "管哪边", note: "生活和生意的钱分开算。先不管的那一边，账还在，只是先不显示。", grow: true) {
                ForEach(Array(ManagedSides.allCases.enumerated()), id: \.element) { i, m in
                    V3SetRow(title: m == .life ? "🏠 只管生活" : m == .biz ? "🏪 只管生意" : "🏠🏪 两边都管",
                             detail: m == .life ? state.book.lifeName : m == .biz ? (state.book.showBiz ? state.book.shopName : "开一家店、做副业的在这边") : "生活和生意都看", line: i > 0) {
                        if m == now { V3Tag(text: "现在是这个", tone: .green) }
                        else { Button("选这个") { state.setSides(life: m.showsLife, biz: m.showsBiz) }.buttonStyle(.v3(.ghost, .small)) }
                    }
                }
            }
        }
    }
}

// MARK: - 钱怎么进来

struct V3RealMoneyPage: View {
    @Environment(V3State.self) private var state
    var body: some View {
        let ledger = state.model?.ledger
        V3SetColumn {
            V3SetGroup(title: "在这里") {
                V3SetRow(title: "📄 银行流水（CSV）", detail: "拖进窗口交给夏夏，先数给你看，点了才导", line: false) {
                    Button("导入流水") { state.handToXia() }.buttonStyle(.v3(.primary, .small))
                }
                V3SetRow(title: "✍️ 记一笔", detail: "说一句或者自己填") { Button("记一笔") { state.showAdd = true }.buttonStyle(.v3(.ghost, .small)) }
                V3SetRow(title: "🔁 每月自动记的", detail: "\(ledger?.recurring.filter { !$0.paused }.count ?? 0) 条在记") { EmptyView() }
                V3SetRow(title: "📱 手机上记的", detail: (ledger?.pendingCaptures.count ?? 0) > 0 ? "还有 \(ledger?.pendingCaptures.count ?? 0) 条没入账" : "都入账了") { EmptyView() }
            }
            V3SetGroup(title: "交给你连着的 AI", note: "照片、PDF、Excel、别的记账软件导出的文件，这里读不了，AI 读得了：复制这段话发给它，再把文件给它。", grow: true) {
                ForEach(Array(ImportGuideCard.sources.enumerated()), id: \.element.id) { i, s in
                    V3SetRow(title: s.name, detail: s.formats, line: i > 0) {
                        Button("复制给 AI") { state.copy(s.prompt, say: "已复制，粘贴给你的 AI，再把文件给它") }.buttonStyle(.v3(.ghost, .small))
                    }
                }
            }
        }
    }
}

// MARK: - 同步与币种

struct V3RealSyncPage: View {
    @Environment(V3State.self) private var state
    @Environment(\.openURL) private var openURL
    @State private var pickingCurrency = false
    @State private var fetching = false

    var body: some View {
        if let model = state.model {
            let base = model.ledger.baseCurrency
            V3SetColumn {
                V3SetGroup(title: "账本") {
                    V3SetRow(title: "状态", line: false) {
                        Text(model.loadError == nil ? "● 账本已读到" : "● 账本没读成").font(V3.font(13, .bold)).foregroundStyle(model.loadError == nil ? V3.green : V3.red)
                    }
                    V3SetRow(title: "账本放在", detail: ledgerLocation(model.store)) { EmptyView() }
                    V3SetRow(title: "重新读取账本", detail: "另一台设备刚改过、这边没变时点一下") {
                        Button("重新读取") { model.refreshIfChanged(); state.refreshFromModel(); state.say("读好了，是最新的") }.buttonStyle(.v3(.ghost, .small))
                    }
                }
                V3SetGroup(title: "币种", note: "取汇率只下载欧洲央行的公开数据，不上传你的任何东西。") {
                    V3SetRow(title: "主币种", detail: "总览、小结里的总数都换成它", line: false) {
                        Button("\(Currencies.info(base).name) \(Currencies.info(base).symbol)  ›") { withAnimation(.snappy(duration: 0.15)) { pickingCurrency.toggle() } }
                            .buttonStyle(.v3(.ghost, .small))
                    }
                    if pickingCurrency {
                        // 换一个：点了就换（能撤销），随后去取一次汇率
                        FlowLayout(spacing: 6) {
                            ForEach(Currencies.all.filter { $0.code != base }, id: \.code) { c in
                                Button("\(c.name) \(c.symbol)") { pickingCurrency = false; state.setBaseCurrency(c.code) }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    V3SetRow(title: "汇率", detail: model.ratesStatus) {
                        Button(fetching ? "在取…" : "更新汇率") {
                            fetching = true
                            Task { @MainActor in
                                await model.refreshRatesIfNeeded(force: true)
                                state.refreshFromModel(); fetching = false
                            }
                        }
                        .buttonStyle(.v3(.ghost, .small)).disabled(fetching || model.ledger.foreignCurrencies.isEmpty)
                    }
                }
                V3SetGroup(title: "更新", grow: true) {
                    V3SetRow(title: "现在的版本", detail: AppUpdateSupport.versionText, line: false) {
                        if AppUpdateSupport.isAvailable { Button("检查更新") { AppUpdateSupport.requestCheck() }.buttonStyle(.v3(.ghost, .small)) }
                    }
                    V3SetLink(title: "更新日志", sub: "每一版改了什么（官网）") { openURL(Changelog.webURL) }
                }
            }
        }
    }
}

// MARK: - 数据

struct V3RealDataPage: View {
    @Environment(V3State.self) private var state
    @State private var confirming = false
    @State private var typed = ""
    @State private var restoring: URL?

    var body: some View {
        if let model = state.model {
            let count = model.ledger.wipeCount(.everything)
            let backups = model.backups
            V3SetColumn {
                V3SetGroup(title: "演示数据", note: "演示数据都是编的，随便点、随便改，不会进你自己的账本。") {
                    V3SetRow(title: model.isTryingDemo ? "正在看演示数据" : "看看有数据时的样子", detail: model.isTryingDemo ? "你自己的账本没动，好好地放着" : "", line: false) {
                        Button(model.isTryingDemo ? "退出演示" : "看看") {
                            if model.isTryingDemo { model.exitDemo() } else { model.enterDemo() }
                            state.refreshFromModel()
                        }
                        .buttonStyle(.v3(.ghost, .small))
                    }
                }
                V3SetGroup(title: "删除数据") {
                    V3SetRow(title: "删掉全部数据", detail: count.isEmpty ? "现在已经是空的了" : count.text, line: false) {
                        if !confirming { Button("删除…") { typed = ""; confirming = true }.buttonStyle(.v3(.danger, .small)).disabled(count.isEmpty || model.isTryingDemo) }
                    }
                    if confirming {
                        // 和旧界面一样问两遍：先说清会删什么，再让人打「删除」两个字
                        VStack(alignment: .leading, spacing: 8) {
                            Text("会删掉：\(count.text)。删之前会自动留一份备份，下面能恢复。真的要删，在这里打「删除」两个字。")
                                .font(V3.font(13, .semibold)).foregroundStyle(V3.ink).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                TextField("删除", text: $typed).textFieldStyle(.roundedBorder).frame(width: 120)
                                Button("确认删除") { confirming = false; state.wipeEverything() }.buttonStyle(.v3(.danger, .small)).disabled(typed != "删除")
                                Button("不删了") { confirming = false }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                V3SetGroup(title: "从备份恢复", note: "删除、恢复之前都会自动留一份，最多留 10 份。", grow: true) {
                    if backups.isEmpty {
                        V3SetRow(title: "还没有备份", line: false) { EmptyView() }
                    }
                    ForEach(Array(backups.prefix(6).enumerated()), id: \.element.url) { i, b in
                        V3SetRow(title: b.url.deletingPathExtension().lastPathComponent, detail: b.date.formatted(date: .abbreviated, time: .shortened), line: i > 0) {
                            if restoring == b.url {
                                HStack(spacing: 6) {
                                    Button("确认恢复") { restoring = nil; state.restoreBackup(b) }.buttonStyle(.v3(.primary, .small))
                                    Button("算了") { restoring = nil }.buttonStyle(.v3(.ghost, .small))
                                }
                            } else {
                                Button("恢复") { restoring = b.url }.buttonStyle(.v3(.ghost, .small))
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
