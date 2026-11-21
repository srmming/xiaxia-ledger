import FinanceCore
import SwiftUI

/// 夏夏这一句话的好坏：决定按性格加什么语气。
enum Mood { case good, bad, neutral }

extension LedgerModel {
    var persona: Persona { ledger.profile.persona }

    /// 把 app 自己算出来的一句事实，按夏夏的性格说出来。
    func voiced(_ fact: String, _ mood: Mood) -> String {
        switch (persona, mood) {
        case (.gentle, .bad): fact + "可以留意一下。"
        case (.gentle, .good): fact + "挺好的。"
        case (.sharp, .bad): fact + "钱包在哭，你听见了吗。"
        case (.sharp, .good): fact + "难得，别骄傲。"
        case (.sharp, .neutral): fact + "就这样，没什么好夸的。"
        case (.cheer, .bad): fact + "没关系，下个月一起少花一点！"
        case (.cheer, .good): fact + "太棒了，继续保持！"
        case (.cheer, .neutral): fact + "加油！"
        default: fact
        }
    }
}

/// 每页大数字下面固定的「夏夏说」：AI 给这一页写过意见就显示那条；还没写就由 app 先说一句，
/// 下面「让夏夏细说」复制一段话并打开 Claude，让 AI 写一条给这一页的意见。
struct XiaxiaSays: View {
    @Environment(LedgerModel.self) var model
    /// overview / spending / trends / wealth / plans
    let page: String
    /// 页面中文名，比如「花销」。
    let pageName: String
    /// app 自己算出的一句话（已经按性格说好）。
    let sentence: String
    /// 「让夏夏细说」时问的问题。
    let question: String

    var body: some View {
        if let insight = model.ledger.insight(forPage: page, month: model.shownMonth, bookID: model.selectedBookID) {
            InsightCard(insight: insight)
        } else {
            AskAIReader { ask in
                VStack(alignment: .leading, spacing: 10) {
                    XiaxiaHeader(title: "夏夏说")
                    Text(sentence).font(.body).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            ask(question + " 说完用 add_insight 写一条给「\(pageName)」页的意见（page=\(page)）。", page: pageName)
                        } label: { Label("让夏夏细说", systemImage: "sparkles") }
                            .buttonStyle(.softAI)
                            .accessibilityHint("复制一段话并打开 Claude")
                        Spacer()
                        MoreLink(title: "夏夏建议", section: .insights)
                    }
                }
                .aiCard()
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// 「✦ 夏夏说 · 温和直说」小标题。
struct XiaxiaHeader: View {
    @Environment(LedgerModel.self) var model
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Color.ai, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ai)
            Spacer()
            Text(trailing ?? model.persona.label).font(.caption).foregroundStyle(Color.fg2)
        }
    }
}

/// 设置里「夏夏怎么跟你说话」：四种性格，各带一句例句。
struct PersonaPicker: View {
    @Environment(LedgerModel.self) var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Persona.allCases) { p in
                Button {
                    guard p != model.persona else { return }
                    model.perform { try $0.setPersona(p, author: model.author) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: p == model.persona ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(p == model.persona ? Color.ai : Color.fg3)
                            .font(.body)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.label + (p == .gentle ? "（默认）" : "")).font(.callout.weight(.medium)).foregroundStyle(.primary)
                            Text("「\(p.sample)」").font(.caption).foregroundStyle(Color.fg2).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(p == model.persona ? Color.aiSoft : Color.sunken.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("\(p.label)，比如：\(p.sample)")
                .accessibilityAddTraits(p == model.persona ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
    }
}

/// 夏夏建议页顶上：「你想让夏夏帮你做到什么？」
struct AimCard: View {
    @Environment(LedgerModel.self) var model
    @State var editing = false
    @State var text = ""
    @FocusState var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            XiaxiaHeader(title: "你想让夏夏帮你做到什么？", trailing: "")
            if let aim = model.ledger.profile.aim, !editing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("你的目标").font(.caption).foregroundStyle(Color.fg2)
                    Text(aim).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                }
                Text("夏夏每次给意见都会先看这个目标。").font(.caption).foregroundStyle(Color.fg2)
                HStack(spacing: 8) {
                    Button("改一下") { text = aim; editing = true; focused = true }.buttonStyle(.soft)
                    Button("清掉") { save(nil) }.buttonStyle(.soft)
                }
            } else {
                TextField("比如：每个月存下 500 €", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onSubmit { save(text) }
                    .accessibilityLabel("你的目标")
                Text("点一个例子直接用，或者自己写：").font(.caption).foregroundStyle(Color.fg2)
                FlowLayout(spacing: 6) {
                    ForEach(Profile.aimExamples, id: \.self) { e in
                        Button(e) { text = e }
                            .buttonStyle(.soft)
                            .accessibilityHint("填进目标")
                    }
                }
                HStack(spacing: 8) {
                    Button("就这个") { save(text) }
                        .buttonStyle(AISolidButtonStyle())
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing { Button("取消") { editing = false }.buttonStyle(.soft) }
                }
            }
        }
        .aiCard()
    }

    private func save(_ value: String?) {
        model.perform { try $0.setAim(value, author: model.author) }
        editing = false
        text = ""
    }
}
