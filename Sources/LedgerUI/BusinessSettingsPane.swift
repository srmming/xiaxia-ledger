import FinanceCore
import SwiftUI

/// 设置 → 生意模式（设计稿 ③）：开关、选哪个是店里的账本、开店本钱。
/// 生意设置先只能在 Mac 上改（2026-11-25 需求单），iPhone 上只看状态。
struct BusinessSettingsPane: View {
    @Environment(LedgerModel.self) var model
    /// 有好几个生意账本、还没定哪个是店里的：列出来让人挑。
    @State private var choices: [Book] = []
    @State private var editingCapital = false

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                #if os(macOS)
                switchCard
                if !choices.isEmpty { chooseCard }
                if model.businessOn { capitalCard }
                #else
                phoneNote
                #endif
                Text(tr("关掉生意模式不会丢账：店里的流水还在原来的账本里，再打开一样。"))
                    .font(.caption).foregroundStyle(Color.fg2)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(Kit.side)
        }
        .background(Color.pageBackground)
        #if os(macOS)
        .sheet(isPresented: $editingCapital) { CapitalEditor().environment(model) }
        #endif
    }

    #if os(macOS)
    private var switchCard: some View {
        let on = Binding(get: { model.businessOn }, set: { $0 ? turnOn() : turnOff() })
        return HStack(spacing: 12) {
            XiaTile(glyph: .shoprent, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("生意模式")).font(.body.weight(.semibold))
                Text(tr("首页分生活、生意两边；店里的账算利润和回本"))
                    .font(.caption).foregroundStyle(Color.fg2)
            }
            Spacer(minLength: 12)
            Toggle(tr("生意模式"), isOn: on).toggleStyle(.switch).labelsHidden().tint(Color.shop)
                .accessibilityIdentifier("business.toggle")
        }
        .kitCard()
    }

    private var chooseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("你有 \(choices.count) 个生意账本，选一个当店里的。别的都算生活那边。不会合并，也不改以前的账。"))
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            ForEach(choices) { book in
                Button { enable(book.id) } label: {
                    HStack {
                        Monogram(text: book.name, color: model.bookColor(book.id), size: 24)
                        Text(book.name)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.fg3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .kitCard()
    }

    private var capitalCard: some View {
        let capital = model.ledger.business?.capital
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("开店本钱")).font(.body.weight(.semibold))
                if let c = capital {
                    let opened = c.openedOn.map { tr(" · \($0.friendly)开店") } ?? ""
                    Text(c.total.ui + opened)
                        .font(.caption).foregroundStyle(Color.fg2)
                } else {
                    Text(tr("还没填。填一个总数，夏夏就能算什么时候回本。")).font(.caption).foregroundStyle(Color.fg2)
                }
            }
            Spacer(minLength: 12)
            Button(capital == nil ? tr("填本钱…") : tr("改本钱…")) { editingCapital = true }
                .accessibilityIdentifier("business.capital")
        }
        .kitCard()
    }

    private func turnOn() {
        let candidates = model.ledger.books.filter(\.isBusiness)
        if model.ledger.businessBook == nil && candidates.count > 1 {
            choices = candidates
        } else {
            enable(nil)
        }
    }

    private func enable(_ bookID: String?) {
        do {
            try model.edit { ledger in
                guard case .enabled(let change) = try ledger.enableBusinessMode(choose: bookID, newBookName: tr("我的生意"), author: model.author) else {
                    throw Failure(message: tr("请先选一个生意账本"))
                }
                return change
            }
            choices = []
            // 打开后先停在生意这边。
            model.switchSide(.business)
        } catch {
            model.toast = .init(text: error.localizedDescription, changeID: nil, isError: true)
        }
    }

    private func turnOff() {
        choices = []
        model.perform { $0.disableBusinessMode(author: model.author) }
    }
    #else
    private var phoneNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.businessOn ? tr("生意模式开着 · \(model.ledger.businessBook?.name ?? "")") : tr("生意模式关着"),
                  systemImage: "storefront")
                .font(.body.weight(.semibold))
            Text(tr("开关和开店本钱先在 Mac 上改：设置 → 生意模式。打开后，手机顶上也会出现「生活 | 生意」切换。"))
                .font(.callout).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kitCard()
    }
    #endif
}
