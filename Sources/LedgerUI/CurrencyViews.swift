import FinanceCore
import SwiftUI

// 多币种的界面：设置页「币种」一组、账户的币种选择、汇率自动更新。

extension LedgerModel {
    /// 账户余额的写法：外币账户「1.234,00 US$」，主币种账户照旧。
    func balanceText(_ accountID: String) -> String {
        let code = ledger.currency(ofAccount: accountID)
        let native = nativeBalances[accountID] ?? .zero
        let text = native.magnitude.ui(in: code)
        return native.cents < 0 ? "\u{2212}" + text : text
    }

    /// 外币账户约合多少主币种（主币种账户返回 nil）。
    func approxBaseText(_ accountID: String) -> String? {
        guard ledger.currency(ofAccount: accountID) != ledger.baseCurrency else { return nil }
        return "≈ " + (balances[accountID] ?? .zero).ui(in: ledger.baseCurrency)
    }

    /// 汇率一行的说明：「欧洲央行 · 11 月 21 日的」「还没取过」。
    var ratesStatus: String {
        if ledger.foreignCurrencies.isEmpty { return "没有外币，用不到" }
        if let d = ledger.currency.latestRateDate {
            return "欧洲央行 · \(d.short)的" + (ledger.missingRateCurrencies.isEmpty ? "" : " · 缺 \(ledger.missingRateCurrencies.joined(separator: "、"))")
        }
        return "还没取过"
    }

    /// 有外币、而且今天还没取过汇率：去欧洲央行取一次，存进账本（不算改账，不进改动记录）。
    /// 示例数据（内存里的账本）不联网，汇率写死在示例里。
    func refreshRatesIfNeeded(force: Bool = false) async {
        Money.defaultCurrency = ledger.baseCurrency
        guard !(store is InMemoryLedgerStore) else { return }
        guard force || ledger.needsRateRefresh else { return }
        do {
            let table = try await ECBRates.fetch(since: ledger.earliestForeignDate)
            var fresh = try store.load()          // 取的时候 AI 可能刚写过：以文件里最新的为准
            fresh.applyRates(table)
            try store.save(fresh)
            reload()
            if force { toast = Toast(text: "汇率已更新：\(ratesStatus)", changeID: nil) }
        } catch {
            if force { toast = Toast(text: error.localizedDescription, changeID: nil, isError: true) }
        }
    }
}

/// 选币种（常用的在前面）。selection 空字符串 = 主币种。
struct CurrencyPicker: View {
    @Environment(LedgerModel.self) var model
    let title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text("\(Currencies.info(model.ledger.baseCurrency).name)（主币种）").tag("")
            ForEach(Currencies.all.filter { $0.code != model.ledger.baseCurrency }, id: \.code) { c in
                Text("\(c.name) \(c.code)").tag(c.code)
            }
        }
    }
}

/// 设置页「币种」一组。
struct CurrencySettingsRows: View {
    @Environment(LedgerModel.self) var model
    @State private var pendingBase: String?
    @State private var updating = false

    var body: some View {
        let base = model.ledger.baseCurrency
        let foreign = model.ledger.accounts.filter { model.ledger.currency(ofAccount: $0.id) != base }
        VStack(alignment: .leading, spacing: 0) {
            row(symbol: "eurosign", title: "主币种") {
                Picker("主币种", selection: Binding(get: { base }, set: { if $0 != base { pendingBase = $0 } })) {
                    ForEach(Currencies.all, id: \.code) { c in Text("\(c.name) \(c.symbol)").tag(c.code) }
                }
                .labelsHidden().fixedSize()
                .accessibilityIdentifier("baseCurrency")
            }
            row(symbol: "textformat.123", title: "金额写法") {
                Text(Money(cents: 123456).ui(in: base)).foregroundStyle(Color.fg2).monospacedDigit()
            }
            row(symbol: "arrow.left.arrow.right", title: "汇率") {
                HStack(spacing: 8) {
                    Text(model.ratesStatus).foregroundStyle(Color.fg2).lineLimit(1)
                    if !model.ledger.foreignCurrencies.isEmpty {
                        Button {
                            updating = true
                            Task { await model.refreshRatesIfNeeded(force: true); updating = false }
                        } label: {
                            if updating { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                        }
                        .buttonStyle(.borderless)
                        .disabled(updating)
                        .help("现在去欧洲央行取一次汇率")
                        .accessibilityLabel("更新汇率")
                    }
                }
            }
            row(symbol: "dollarsign", title: "外币账户") {
                Text(foreign.isEmpty ? "没有" : "\(foreign.count) 个（\(Set(foreign.map { Currencies.info(model.ledger.currency(ofAccount: $0.id)).name }).sorted().joined(separator: "、"))）")
                    .foregroundStyle(Color.fg2).lineLimit(1)
            }
        }
        .confirmationDialog("主币种改成\(Currencies.label(pendingBase ?? base))？", isPresented: Binding(get: { pendingBase != nil }, set: { if !$0 { pendingBase = nil } }),
                            titleVisibility: .visible) {
            Button("改成\(Currencies.info(pendingBase ?? base).name)") {
                if let code = pendingBase {
                    model.perform { try $0.setBaseCurrency(code, author: model.author) }
                    Task { await model.refreshRatesIfNeeded(force: true) }
                }
                pendingBase = nil
            }
        } message: {
            Text("已经记的每一笔金额都不变，只是看板、月报里的总数换成\(Currencies.info(pendingBase ?? base).name)。原来的\(Currencies.info(base).name)账户会标成\(Currencies.info(base).name)账户。改错了可以撤销。")
        }
    }

    private func row<Trailing: View>(symbol: String, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(symbol == "eurosign" ? Color.brand : Color.fg3, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title).font(.callout)
            Spacer(minLength: 12)
            trailing().font(.callout)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
