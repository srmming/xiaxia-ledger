#if os(macOS)
import FinanceCore
import SwiftUI

// 生意模式 Mac 版界面预览（UI 套件 v5，2026-11-25）。
// ming 看了网页模拟的稿说「界面不好」：这里直接用 SwiftUI 原生组件搭出 Mac 的几页，
// 数字是示例（写死在 BizSample 里），先给 ming 看样子；他说「开工」后再把这些视图接到真账本上。
// 启动参数：-XiaxiaBizPreview home | short | newshop | payday | empty | daily | fixed | capital | accounts | transfer

enum BizPreview {
    static let page: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-XiaxiaBizPreview"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
}

/// 1.234 € 这种写法（预览用整数欧元）。
private func eur(_ value: Int, plus: Bool = false) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "."
    f.usesGroupingSeparator = true
    f.maximumFractionDigits = 0
    let body = f.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
    let sign = value < 0 ? "−" : (plus && value > 0 ? "+" : "")
    return sign + body + " €"
}

// MARK: - 示例数字

private struct Due: Identifiable {
    let id = UUID()
    let name: String
    let when: String
    let amount: Int
}

private struct HomeSample {
    var profit: Int
    var change: Int
    var onHand: Int
    var dues: [Due]
    var paidSelf: Int
    var payback: Double?
    var paybackNote = ""
    var celebrate = false
    var empty = false

    var dueTotal: Int { dues.reduce(0) { $0 + $1.amount } }
    var gap: Int { onHand - dueTotal }

    static func of(_ page: String) -> HomeSample {
        switch page {
        case "short":
            return HomeSample(profit: 860, change: -420, onHand: 1800,
                              dues: [Due(name: "房租", when: "12 月 1 日", amount: 1200), Due(name: "员工工资", when: "11 月 30 日", amount: 1400)],
                              paidSelf: 1000)
        case "newshop", "capital":
            return HomeSample(profit: 1180, change: 260, onHand: 2150,
                              dues: [Due(name: "员工工资", when: "11 月 30 日", amount: 900)],
                              paidSelf: 800, payback: 0.18, paybackNote: "大约还要 26 个月")
        case "payday":
            return HomeSample(profit: 3950, change: 480, onHand: 5200,
                              dues: [Due(name: "房租", when: "12 月 1 日", amount: 1200)],
                              paidSelf: 1800, celebrate: true)
        case "empty":
            return HomeSample(profit: 0, change: 0, onHand: 0, dues: [], paidSelf: 0, empty: true)
        default:
            return HomeSample(profit: 2340, change: 310, onHand: 3400,
                              dues: [Due(name: "房租", when: "12 月 1 日", amount: 1200)],
                              paidSelf: 1500)
        }
    }
}

private enum BizSheet: String, Identifiable {
    case daily, capital, transfer
    var id: String { rawValue }
}

// MARK: - 窗口：侧栏 + 工具栏，和生活那边的 MacRoot 一样的搭法

struct BizPreviewRoot: View {
    let page: String
    @State private var section: String? = "overview"
    @State private var side = 1
    @State private var sheet: BizSheet?

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("看") {
                    row("overview", "总览", glyph: AppSection.overview.glyph)
                    row("spending", "花销", glyph: AppSection.spending.glyph)
                    row("trends", "趋势", glyph: AppSection.trends.glyph)
                    row("wealth", "家底", glyph: AppSection.wealth.glyph)
                    Label { Text("固定开销") } icon: { Image(systemName: "calendar.badge.clock").foregroundStyle(Color.shop) }
                        .tag("fixed")
                    row("debts", "欠款与分期", glyph: AppSection.debts.glyph)
                }
                Section("记录") { row("transactions", "流水", glyph: AppSection.transactions.glyph) }
                Section { row("settings", "设置", glyph: AppSection.settings.glyph) }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            NavigationStack {
                detail
                    .navigationTitle(title)
                    .toolbar { toolbar }
            }
            .frame(minWidth: 460, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .tint(Color.shop)
        .sheet(item: $sheet) { s in
            switch s {
            case .daily: BizDailySheet()
            case .capital: BizCapitalSheet()
            case .transfer: BizTransferSheet()
            }
        }
        .onAppear {
            switch page {
            case "fixed": section = "fixed"
            case "accounts": section = "wealth"
            case "transfer": section = "wealth"; sheet = .transfer
            case "daily": sheet = .daily
            case "capital": sheet = .capital
            default: break
            }
        }
    }

    private func row(_ id: String, _ name: String, glyph: XiaGlyph) -> some View {
        Label { Text(name) } icon: { glyph.image(size: 18) }.tag(id)
    }

    private var title: String {
        switch section ?? "overview" {
        case "fixed": "固定开销"
        case "wealth": "家底"
        default: "总览"
        }
    }

    @ViewBuilder private var detail: some View {
        switch section ?? "overview" {
        case "fixed": BizFixedPage()
        case "wealth": BizAccountsPage()
        default: BizHomePage(sample: HomeSample.of(page), onCapital: { sheet = .capital }, onDaily: { sheet = .daily })
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("生活还是生意", selection: $side) {
                Text("生活").tag(0)
                Text("生意").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("切换看生活还是生意")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if section == "wealth" {
                Button { sheet = .transfer } label: { Label("两边转钱", systemImage: "arrow.left.arrow.right") }
                    .help("店里和家里之间转钱（⌘T）")
                    .keyboardShortcut("t", modifiers: .command)
            }
            if section == "fixed" {
                Button {} label: { Label("加一项", systemImage: "plus") }
                    .help("加一项固定开销")
            }
            Button { sheet = .daily } label: {
                Label("记今天的账", systemImage: "plus.circle.fill").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.shop)
            .keyboardShortcut("n", modifiers: .command)
            .help("记今天的账（⌘N）")
            Button {} label: { Label("问夏夏", systemImage: "sparkles").labelStyle(.titleAndIcon) }
                .tint(Color.ai)
                .help("问夏夏（⌘K）")
        }
    }
}

// MARK: - 首页：这个月真正赚了多少

private struct BizHomePage: View {
    let sample: HomeSample
    let onCapital: () -> Void
    let onDaily: () -> Void

    var body: some View {
        Group {
            if sample.empty {
                ContentUnavailableView {
                    Label("这个月还没记账", systemImage: "storefront")
                } description: {
                    Text("先加上公司卡和店里的现金，再每天记一次收入。\n夏夏就能算这个月赚了多少、下周房租工资够不够。")
                } actions: {
                    HStack {
                        Button("加店里的账户") {}
                        Button("记今天的账", action: onDaily).buttonStyle(.borderedProminent).tint(Color.shop)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 36) {
                    main
                    side.frame(width: 300)
                }
                .padding(.horizontal, 48)
                .padding(.top, 44)
                .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.pageBackground)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("11 月真正赚了").font(.title3).foregroundStyle(Color.fg2)
            Text(eur(sample.profit))
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.top, 2)
            HStack(spacing: 10) {
                Label(sample.change >= 0 ? String("比 10 月同期多 \(eur(sample.change))") : String("比 10 月同期少 \(eur(-sample.change))"),
                      systemImage: sample.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(sample.change >= 0 ? Color.income : Color.alert)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(sample.change >= 0 ? Color.incomeSoft : Color.alertSoft, in: Capsule())
                Text("已扣掉房租、工资这些固定开销").font(.callout).foregroundStyle(Color.fg3)
            }
            .padding(.top, 10)
            reminder.padding(.top, 36)
            Button {} label: {
                HStack(spacing: 4) {
                    Text("这个月给自己发了").foregroundStyle(Color.fg2)
                    Text(eur(sample.paidSelf)).fontWeight(.semibold).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
                }
                .font(.body)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reminder: some View {
        let ok = sample.gap >= 0
        let dueText = sample.dues.count > 1 ? "下周房租和工资 \(eur(sample.dueTotal))" : "下周要付\(sample.dues.first?.name ?? "") \(eur(sample.dueTotal))"
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.income : Color.alert)
            (Text("手上 \(eur(sample.onHand))，\(dueText)，")
                + Text(ok ? String("够") : String("还差 \(eur(-sample.gap))")).fontWeight(.semibold).foregroundStyle(ok ? Color.income : Color.alert)
                + Text("。"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(ok ? Color.incomeSoft : Color.alertSoft, in: RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
    }

    @ViewBuilder private var side: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sample.celebrate {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.shop)
                    Text("今天回本了！").font(.title2.weight(.bold))
                    Text("开店花的 70.000 € 全赚回来了，用了 19 个月。以后赚的都是净赚。")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("收起这张卡") {}.controlSize(.large).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .kitCard(padding: 22)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("下周要付").font(.headline)
                ForEach(sample.dues) { d in
                    HStack {
                        Text(d.name)
                        Text(d.when).foregroundStyle(Color.fg3)
                        Spacer()
                        Text(eur(d.amount)).monospacedDigit()
                    }
                    .font(.callout)
                }
                Divider()
                HStack {
                    Text("一共").foregroundStyle(Color.fg2)
                    Spacer()
                    Text(eur(sample.dueTotal)).fontWeight(.semibold).monospacedDigit()
                }
                .font(.callout)
            }
            .kitCard()
            if let p = sample.payback {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("回本 \(Int((p * 100).rounded()))%").font(.headline)
                        Spacer()
                        Text(sample.paybackNote).font(.callout).foregroundStyle(Color.fg2)
                    }
                    ProgressView(value: p).tint(Color.shop)
                    HStack {
                        Text("已赚回 12.600 € / 共 70.000 €").font(.caption).foregroundStyle(Color.fg3)
                        Spacer()
                        Button("改", action: onCapital).buttonStyle(.link).font(.caption)
                    }
                }
                .kitCard()
            }
        }
    }
}

// MARK: - 固定开销：左边总数，右边原生表格

private struct FixedRow: Identifiable {
    let id = UUID()
    let name: String
    let day: Int
    let account: String
    let amount: Int
    let soon: Bool
}

private struct BizFixedPage: View {
    @State private var selection: Set<UUID> = []
    private let rows = [
        FixedRow(name: "房租", day: 1, account: "公司卡", amount: 1200, soon: true),
        FixedRow(name: "员工工资", day: 30, account: "公司卡", amount: 1400, soon: true),
        FixedRow(name: "会计", day: 5, account: "公司卡", amount: 80, soon: false),
        FixedRow(name: "网费", day: 12, account: "公司卡", amount: 40, soon: false),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 0) {
                Text("每个月固定要付").font(.title3).foregroundStyle(Color.fg2)
                Text(eur(2720)).font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                Text("到日子自动记上，不用手记").font(.callout).foregroundStyle(Color.fg3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("下周要付").font(.callout).foregroundStyle(Color.fg2)
                    Text(eur(2600)).font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                    Text("30 号工资 1.400 · 1 号房租 1.200").font(.caption).foregroundStyle(Color.fg3)
                }
                .kitCard()
                .padding(.top, 28)
            }
            .frame(width: 250)

            VStack(alignment: .leading, spacing: 8) {
                Table(rows, selection: $selection) {
                    TableColumn("名字") { r in
                        HStack(spacing: 6) {
                            Text(r.name)
                            if r.soon {
                                Text("下周").font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .foregroundStyle(Color.shop)
                                    .background(Color.shopSoft, in: Capsule())
                            }
                        }
                    }
                    TableColumn("每月几号") { r in Text("\(r.day) 号").foregroundStyle(Color.fg2) }
                    TableColumn("从哪付") { r in Text(r.account).foregroundStyle(Color.fg2) }
                    TableColumn("多少") { r in
                        Text(eur(r.amount)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .contextMenu(forSelectionType: UUID.self) { _ in
                    Button("改…") {}
                    Button("这个月先不记") {}
                    Divider()
                    Button("删除", role: .destructive) {}
                } primaryAction: { _ in }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
                Text("双击一行改，右键可以暂停或删除。首页「真正赚了」会扣掉这些。")
                    .font(.caption).foregroundStyle(Color.fg3)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 48)
        .padding(.top, 44)
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pageBackground)
    }
}

// MARK: - 家底（生意这边）：店里的账户 + 两边之间的钱

private struct AccountRow: Identifiable {
    let id = UUID()
    let name: String
    let kind: String
    let symbol: String
    let amount: Int
}

private struct MoveRow: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let amount: Int
}

private struct BizAccountsPage: View {
    @State private var selection: Set<UUID> = []
    private let accounts = [
        AccountRow(name: "公司卡 · CaixaBank", kind: "银行卡", symbol: "creditcard", amount: 5420),
        AccountRow(name: "店里现金", kind: "现金", symbol: "banknote", amount: 860),
    ]
    private let moves = [
        MoveRow(title: "拿钱回家 · 到日常卡", date: "11 月 20 日", amount: -500),
        MoveRow(title: "日常卡帮店里付进货", date: "11 月 18 日", amount: 120),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 0) {
                Text("店里一共").font(.title3).foregroundStyle(Color.fg2)
                Text(eur(6280)).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                Text("生活和生意加起来一共 14.430 €").font(.callout).foregroundStyle(Color.fg3)
                Table(accounts, selection: $selection) {
                    TableColumn("账户") { a in Label(a.name, systemImage: a.symbol) }
                    TableColumn("类型") { a in Text(a.kind).foregroundStyle(Color.fg2) }
                    TableColumn("余额") { a in
                        Text(eur(a.amount)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .contextMenu(forSelectionType: UUID.self) { _ in
                    Button("改名…") {}
                    Button("挪到生活那边…") {}
                } primaryAction: { _ in }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous))
                .padding(.top, 24)
                Text("这两个账户只在生意这边出现。放错了，右键「挪到生活那边」。")
                    .font(.caption).foregroundStyle(Color.fg3).padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text("两边之间的钱").font(.headline)
                VStack(spacing: 0) {
                    ForEach(moves) { m in
                        HStack {
                            Image(systemName: "arrow.left.arrow.right").foregroundStyle(Color.fg3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title)
                                Text(m.date).font(.caption).foregroundStyle(Color.fg3)
                            }
                            Spacer()
                            Text(eur(m.amount, plus: true)).monospacedDigit()
                                .foregroundStyle(m.amount > 0 ? Color.income : Color.primary)
                        }
                        .padding(.vertical, 10)
                        .contextMenu {
                            Button("改…") {}
                            Button("删除", role: .destructive) {}
                        }
                        if m.id != moves.last?.id { Divider() }
                    }
                }
                .kitCard(padding: 14)
                Text("不算开销也不算收入。拿回家的钱算进「这个月给自己发了」。")
                    .font(.caption).foregroundStyle(Color.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 300)
        }
        .padding(.horizontal, 48)
        .padding(.top, 44)
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pageBackground)
    }
}

// MARK: - 弹出的小窗口（sheet）

/// 每天记账：现金一个框、刷卡一个框，下面带出今天已经记的开销，算出今天赚了多少。
private struct BizDailySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cash = "120"
    @State private var card = "300"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("今天收了") {
                        Text(eur(420)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                    TextField("现金", text: $cash, prompt: Text("0")).multilineTextAlignment(.trailing)
                    TextField("刷卡 / 转账", text: $card, prompt: Text("0")).multilineTextAlignment(.trailing)
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("记今天的账").font(.title2.weight(.bold)).foregroundStyle(Color.primary)
                        Text("11 月 25 日 · 周二").font(.callout).foregroundStyle(Color.fg2)
                    }
                    .padding(.bottom, 6)
                } footer: {
                    Text("现金记进店里现金，刷卡记进公司卡；空着的框不记。").font(.caption).foregroundStyle(Color.fg3)
                }
                Section {
                    LabeledContent("今天花了（已经记的 2 笔）", value: eur(36))
                    LabeledContent {
                        Text(eur(384)).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Color.income)
                    } label: {
                        Text("今天赚了").fontWeight(.semibold).foregroundStyle(Color.income)
                    }
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("记好了") { dismiss() } }
            }
        }
        .frame(width: 440, height: 430)
    }
}

/// 开店本钱：只问一个总数、开店日期、已经赚回多少。
private struct BizCapitalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var total = "70.000"
    @State private var recovered = "12.600"
    @State private var opened = DateComponents(calendar: .current, year: 2025, month: 4, day: 12).date ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("一共投了多少", text: $total, prompt: Text("比如 70.000")).multilineTextAlignment(.trailing)
                    DatePicker("哪天开的店", selection: $opened, displayedComponents: .date)
                    TextField("开店到现在已经赚回", text: $recovered, prompt: Text("可以不填")).multilineTextAlignment(.trailing)
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("开店本钱").font(.title2.weight(.bold)).foregroundStyle(Color.primary)
                        Text("夏夏用它算你什么时候回本。只填一个总数，装修、设备、押金、第一批货都算在里面。")
                            .font(.callout).foregroundStyle(Color.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 6)
                } footer: {
                    HStack {
                        Text("店开了一阵子才开始用夏夏的，填一下到现在赚回了多少。").font(.caption).foregroundStyle(Color.fg3)
                        Spacer()
                        Button("老店，不用算回本") {}.buttonStyle(.link).font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("先跳过") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { dismiss() } }
            }
        }
        .frame(width: 480, height: 400)
    }
}

/// 两边转钱：先选是哪种，再填多少和账户。
private struct BizTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 0
    @State private var amount = "500"
    @State private var from = "公司卡"
    @State private var to = "日常卡"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("哪种", selection: $kind) {
                        Text("从店里拿钱回家（算「给自己发了」）").tag(0)
                        Text("自己的钱垫给店里（比如日常卡付了进货）").tag(1)
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Text("两边转钱").font(.title2.weight(.bold)).foregroundStyle(Color.primary).padding(.bottom, 6)
                }
                Section {
                    TextField("多少", text: $amount, prompt: Text("0")).multilineTextAlignment(.trailing)
                    Picker("从", selection: $from) {
                        Text("公司卡").tag("公司卡")
                        Text("店里现金").tag("店里现金")
                    }
                    Picker("到", selection: $to) {
                        Text("日常卡").tag("日常卡")
                        Text("Revolut").tag("Revolut")
                        Text("家里现金").tag("家里现金")
                    }
                } footer: {
                    Text("只是钱换了个地方，不算店里的开销，也不算家里的收入。").font(.caption).foregroundStyle(Color.fg3)
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } }
            }
        }
        .frame(width: 480, height: 400)
    }
}
#endif
