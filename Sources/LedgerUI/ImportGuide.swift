import FinanceCore
import SwiftUI

/// 账本还空着时总览上的「把以前的账搬进来」：教用户从银行、支付宝、微信、别的记账 App 导出账单文件，
/// 再把文件拖给自己电脑上的 AI（Claude 等），复制一句话粘过去，AI 读懂文件、先给预览、确认后导进来（MCP 的 import_rows）。
/// 记下第一笔以后总览换成正常内容，这张卡就不出现了。
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
        Source(name: "银行卡、信用卡", symbol: "building.columns", formats: "Excel · CSV · PDF",
               how: "网银或银行 App 里找「交易明细」或「对账单」，选一段时间导出。",
               prompt: "附件是我从银行导出的对账单。请帮我导进夏夏账本：先告诉我该记到哪个账户、读到多少笔、哪些像是转给自己或还信用卡，给我看一下预览，我说可以再导。"),
        Source(name: "支付宝", symbol: "qrcode", formats: "Excel · CSV",
               how: "支付宝 App：我的 → 账单 → 右上角「…」→ 开具交易流水证明 → 用于个人对账，文件会发到你的邮箱。",
               prompt: "附件是我的支付宝账单。请帮我导进夏夏账本：「不计收支」、退款、转给自己的钱别算成花销，导之前先给我看预览，我说可以再导。"),
        Source(name: "微信支付", symbol: "bubble.left.and.bubble.right", formats: "Excel · CSV",
               how: "微信：我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单 → 用于个人对账，文件会发到你的邮箱。",
               prompt: "附件是我的微信支付账单。请帮我导进夏夏账本：零钱提现、充值、转给自己的钱别算成花销，导之前先给我看预览，我说可以再导。"),
        Source(name: "别的记账 App、自己的表格", symbol: "tablecells", formats: "Excel · CSV",
               how: "钱迹、随手记、iCost 这些在「设置」里找「导出数据」；自己记的 Excel 表格也行。",
               prompt: "附件是我以前在别的记账软件（或自己的表格）里记的账。请帮我导进夏夏账本，原来的分类能照搬就照搬，导之前先给我看预览，我说可以再导。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                MascotView(.xiaxia, pose: .write, size: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text("把以前的账搬进来").font(.title2.weight(.bold))
                    Text("从银行、支付宝、微信或别的记账 App 导出一份账单，交给你电脑上的 AI，它会整理好导进夏夏账本。记下第一笔以后，这张卡就收起来了。")
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
                Text("文件只交给你自己的 AI，夏夏账本没有服务器，不会传到别处。不想导也行：直接跟 AI 说「今天午饭 12」，或点右上角「记一笔」。")
                    .font(.caption).foregroundStyle(Color.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.importGuide")
    }

    @ViewBuilder
    private var steps: some View {
        stepChip(1, "导出账单", "Excel、CSV、PDF 都行")
        stepChip(2, "拖进 Claude", "再粘贴复制好的那句话")
        stepChip(3, "看一眼预览", "说「可以」就导进来")
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
                Label("复制给 AI 的话", systemImage: "doc.on.doc").font(.subheadline.weight(.medium))
            }
            .buttonStyle(.softAI)
            .accessibilityHint("复制一句话并打开 Claude，把账单文件拖进去再粘贴")
            .accessibilityIdentifier("importGuide.copy.\(s.name)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 要带附件，所以不进 app 里的对话栏：复制好，打开 Claude 桌面版，让用户把文件拖进去再粘贴。
    private func copy(_ s: Source) {
        Clipboard.copy(s.prompt)
        guard let app = URL(string: "claude://") else { return }
        openURL(app) { opened in
            model.toast = .init(text: opened ? "已复制。在 Claude 里把账单文件拖进去，再粘贴这句话"
                                             : "已复制。打开你电脑上的 AI（Claude、Codex……），把账单文件拖进去，再粘贴这句话", changeID: nil)
        }
    }
}
