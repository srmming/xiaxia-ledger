import FinanceCore
import SwiftUI

/// 账本还空着时总览上的「把以前的账搬进来」：教用户从银行、支付宝、微信、别的记账 App 导出账单文件，
/// 再把文件拖给自己电脑上的 AI（Claude 等），复制一句话粘过去，AI 读懂文件、先给预览、确认后导进来（MCP 的 import_rows）。
/// 空总览上点「用 AI 导入旧账 · 查看方法」弹出来看。
struct ImportGuideCard: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.openURL) private var openURL

    struct Source: Identifiable {
        var id: String { name }
        var name: String
        var symbol: String
        var formats: String
        var how: String
        var prompt: String
    }

    static let sources: [Source] = [
        Source(name: tr("银行卡、信用卡"), symbol: "building.columns", formats: "Excel · CSV · PDF",
               how: tr("网银或银行 App 里找「交易明细」或「对账单」，选一段时间导出。"),
               prompt: "附件是我从银行导出的对账单。请帮我导进夏夏账本：先告诉我该记到哪个账户、读到多少笔、哪些像是转给自己或还信用卡，给我看一下预览，我说可以再导。"),
        Source(name: tr("支付宝"), symbol: "qrcode", formats: "Excel · CSV",
               how: tr("支付宝 App：我的 → 账单 → 右上角「…」→ 开具交易流水证明 → 用于个人对账，文件会发到你的邮箱。"),
               prompt: "附件是我的支付宝账单。请帮我导进夏夏账本：「不计收支」、退款、转给自己的钱别算成花销，导之前先给我看预览，我说可以再导。"),
        Source(name: tr("微信支付"), symbol: "bubble.left.and.bubble.right", formats: "Excel · CSV",
               how: tr("微信：我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单 → 用于个人对账，文件会发到你的邮箱。"),
               prompt: "附件是我的微信支付账单。请帮我导进夏夏账本：零钱提现、充值、转给自己的钱别算成花销，导之前先给我看预览，我说可以再导。"),
        Source(name: tr("别的记账 App、自己的表格"), symbol: "tablecells", formats: "Excel · CSV",
               how: tr("钱迹、随手记、iCost 这些在「设置」里找「导出数据」；自己记的 Excel 表格也行。"),
               prompt: "附件是我以前在别的记账软件（或自己的表格）里记的账。请帮我导进夏夏账本，原来的分类能照搬就照搬，导之前先给我看预览，我说可以再导。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                MascotView(.xiaxia, pose: .write, size: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("把以前的账搬进来")).font(.title2.weight(.bold))
                    Text(tr("从银行、支付宝、微信或别的记账 App 导出一份账单，交给你电脑上已经连上夏夏账本的 AI，它会整理好、先给你看预览，你确认了才导进来。"))
                        .font(.subheadline).foregroundStyle(Color.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 三步，一眼看懂要做什么。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { steps }
                VStack(alignment: .leading, spacing: 8) { steps }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(Self.sources) { tile($0) }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(Color.fg3)
                Text(tr("文件只交给你自己的 AI，夏夏账本没有服务器，不会传到别处。不想导也行：直接跟 AI 说「今天午饭 12」，或点右上角「记一笔」。"))
                    .font(.caption).foregroundStyle(Color.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.importGuide")
    }

    @ViewBuilder
    private var steps: some View {
        stepChip(1, tr("导出账单"), tr("Excel、CSV、PDF 都行"))
        stepChip(2, tr("拖进 Claude"), tr("再粘贴复制好的那句话"))
        stepChip(3, tr("看一眼预览"), tr("说「可以」就导进来"))
    }

    private func stepChip(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Color.aiSolid, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func tile(_ s: Source) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: s.symbol).font(.headline).foregroundStyle(Color.ai)
                    .frame(width: 30, height: 30)
                    .background(Color.aiSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.name).font(.headline)
                    Text(s.formats).font(.caption2).foregroundStyle(Color.fg3)
                }
            }
            Text(s.how).font(.caption).foregroundStyle(Color.fg2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            Button { copy(s) } label: {
                Label(tr("复制给 AI 的话"), systemImage: "doc.on.doc").font(.subheadline.weight(.medium))
            }
            .buttonStyle(.softAI)
            .accessibilityHint(tr("复制一句话，在你的 AI 里把账单文件拖进去再粘贴"))
            .accessibilityIdentifier("importGuide.copy.\(s.name)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 要带附件，所以不进 app 里的对话栏：复制好，让用户在自己的 AI 里把文件拖进去再粘贴。
    private func copy(_ s: Source) {
        // 和「问夏夏」一样：复制好、提示停一会儿，要不要打开 Claude 由用户自己点，不自动跳走。
        model.handOffToAI(s.prompt)
        model.toast?.text = tr("提示词已经复制。打开你的 AI，把账单文件拖进去，再粘贴这句话")
        model.toast?.seconds = 10
    }
}

#if os(macOS)
/// 账本还空着时的总览（ming 的稿）：大标题「开始记账」+ 右边夏夏；一张卡两行：记下第一笔 / 用 AI 导入旧账；下面一条「问夏夏」。
/// 记下第一笔（或导进来）以后总览换成正常内容，这一页就不再出现。
struct StartLedgerView: View {
    @Environment(LedgerModel.self) var model
    @State private var showImportHelp = false
    /// 例句的金额跟着主币种写（引导里选了人民币就是「23,40 ¥」）。
    static var example: String { tr("今天超市花了 \(Money(cents: 2340).formatted(in: Money.defaultCurrency))") }

    var body: some View {
        AskAIReader { ask in
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("开始记账")).font(.system(size: 48, weight: .heavy))
                            .accessibilityAddTraits(.isHeader)
                        Text(tr("先记今天的一笔，或把以前的账带过来。")).font(.title3).foregroundStyle(Color.fg2)
                    }
                    Spacer(minLength: 16)
                    MascotView(.xiaxia, pose: .write, size: 170)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 0) {
                    row(symbol: "pencil", title: tr("记下第一笔"), detail: tr("记一笔收入或支出")) {
                        Button { model.sheet = .add } label: {
                            Text(tr("记一笔")).font(.title3.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 28).padding(.vertical, 11)
                                .background(Color.brand, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("overview.start.add")
                    }
                    Divider().padding(.leading, 76)
                    Button { showImportHelp = true } label: {
                        row(symbol: "square.and.arrow.down", title: tr("用 AI 导入旧账"), detail: tr("把账单发给你已连接夏夏账本的 AI，确认后导入。")) {
                            HStack(spacing: 6) {
                                Text(tr("查看方法"))
                                Image(systemName: "chevron.right")
                            }
                            .font(.body).foregroundStyle(Color.fg2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("overview.start.import")
                }
                .kitCard(padding: 0)

                Button { ask(Self.example, page: "总览") } label: {
                    HStack(spacing: 16) {
                        Label(tr("问夏夏"), systemImage: "sparkles").font(.title3.weight(.semibold)).foregroundStyle(Color.ai)
                        Rectangle().fill(Color.fg3.opacity(0.3)).frame(width: 1, height: 26)
                        Text(Self.example).font(.title3).foregroundStyle(Color.fg2)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right").foregroundStyle(Color.fg3)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 18)
                    .kitCard(padding: 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(tr("问夏夏：\(Self.example)"))
                .accessibilityIdentifier("overview.start.ask")
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        }
        .sheet(isPresented: $showImportHelp) { ImportHelpSheet() }
    }

    private func row<Trailing: View>(symbol: String, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 20) {
            Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(.primary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.bold))
                Text(detail).font(.body).foregroundStyle(Color.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
    }
}

/// 「用 AI 导入旧账 · 查看方法」：各家怎么导出账单、复制给 AI 的话。
struct ImportHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            ScrollView { ImportGuideCard().padding(28) }
            Divider()
            HStack {
                Spacer()
                Button(tr("好了")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
    }
}
#endif
