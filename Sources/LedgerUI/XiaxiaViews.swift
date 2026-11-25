import FinanceCore
import SwiftUI

/// 夏夏这一句话的好坏：决定按性格加什么语气。
enum Mood { case good, bad, neutral }

extension LedgerModel {
    var persona: Persona { ledger.profile.persona }

    /// 把 app 自己算出来的一句事实，按夏夏的性格说出来。
    func voiced(_ fact: String, _ mood: Mood) -> String {
        switch (persona, mood) {
        case (.gentle, .bad): fact + tr("可以留意一下。")
        case (.gentle, .good): fact + tr("挺好的。")
        case (.sharp, .bad): fact + tr("钱包在哭，你听见了吗。")
        case (.sharp, .good): fact + tr("难得，别骄傲。")
        case (.sharp, .neutral): fact + tr("就这样，没什么好夸的。")
        case (.cheer, .bad): fact + tr("没关系，下个月一起少花一点！")
        case (.cheer, .good): fact + tr("太棒了，继续保持！")
        case (.cheer, .neutral): fact + tr("加油！")
        default: fact
        }
    }
}

/// 每页大数字下面固定的「夏夏说」：AI 给这一页写过意见就显示那条；还没写就由 app 先说一句，
/// 下面「让夏夏细说」复制一段话并打开 Claude，让 AI 写一条给这一页的意见。
struct XiaxiaSays: View {
    @Environment(LedgerModel.self) var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// overview / spending / trends / wealth / plans
    let page: String
    /// 页面中文名，比如「花销」。
    let pageName: String
    /// app 自己算出的一句话（已经按性格说好）。
    let sentence: String
    /// 「让夏夏细说」时问的问题。
    let question: String
    /// 按钮上的字（欠款页催款时是「帮我写句提醒」）。
    var action: String = tr("让夏夏细说")
    /// 问完要不要让 AI 顺手给这一页写条意见（帮忙写提醒消息时不用）。
    var asksInsight = true

    var body: some View {
        if let insight = model.ledger.insight(forPage: page, month: model.shownMonth, bookID: model.selectedBookID) {
            InsightCard(insight: insight)
        } else {
            AskAIReader { ask in
                HStack(alignment: .bottom, spacing: 4) {
                    VStack(alignment: .leading, spacing: 10) {
                        XiaxiaHeader(title: tr("夏夏说"))
                        Text(sentence).font(.body).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button {
                                ask(asksInsight ? question + tr(" 说完用 add_insight 写一条给「\(pageName)」页的意见（page=\(page)）。") : question, page: pageName)
                            } label: { Label(model.xia(action), systemImage: "sparkles") }
                                .buttonStyle(.softAI)
                                .accessibilityHint(tr("复制一段话并打开 Claude"))
                            Spacer()
                            MoreLink(title: tr("夏夏建议"), section: .insights)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 夏夏本人站在卡片右边，按性格摆动作；大字号时让出位置给文字。
                    if !dynamicTypeSize.isAccessibilitySize {
                        MascotView(pose: model.persona.mascotPose, size: 92, interactive: true)
                            .padding(.bottom, -6)
                            .animation(.spring(duration: 0.45, bounce: 0.35), value: model.persona)
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
            XiaxiaAvatar(persona: model.persona, size: 28)
                .accessibilityHidden(true)
            Text(model.xia(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ai)
            Spacer()
            Text(trailing ?? model.persona.label).font(.caption).foregroundStyle(Color.fg2)
        }
    }
}

/// 设置里「夏夏怎么跟你说话」：四种性格，各带一句例句。
struct PersonaPicker: View {
    @Environment(LedgerModel.self) var model
    @AppStorage(MascotLook.storageKey) private var lookRaw = MascotLook.girl.rawValue

    var body: some View {
        VStack(spacing: 8) {
            // 夏夏用女孩版还是男孩版（挑样子的界面做好前只有这两个；男孩版的图到了才显示这个开关）
            if MascotLook.boyAvailable {
                Picker(tr("形象"), selection: Binding(get: { MascotLook.stored(lookRaw) },
                                                    set: { MascotLook.choose($0) }).animation(.spring(duration: 0.45, bounce: 0.3))) {
                    ForEach(MascotLook.kidChoices) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(tr("夏夏的样子"))
                .padding(.bottom, 4)
            }
            ForEach(Persona.allCases) { p in
                Button {
                    guard p != model.persona else { return }
                    model.perform { try $0.setPersona(p, author: model.author) }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        // 每种性格一个夏夏表情；选中的那个会动
                        MascotView(pose: p.mascotPose, size: 44, face: true, animated: p == model.persona)
                            .overlay(alignment: .bottomTrailing) {
                                if p == model.persona {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15, weight: .semibold))
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, Color.ai)
                                        .offset(x: 3, y: 3)
                                }
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.label + (p == .gentle ? tr("（默认）") : "")).font(.callout.weight(.medium)).foregroundStyle(.primary)
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
                .accessibilityLabel(tr("\(p.label)，比如：\(p.sample)"))
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
            XiaxiaHeader(title: tr("你想让夏夏帮你做到什么？"), trailing: "")
            if let aim = model.ledger.profile.aim, !editing {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("你的目标")).font(.caption).foregroundStyle(Color.fg2)
                    Text(aim).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                }
                Text(model.xia(tr("夏夏每次给意见都会先看这个目标。"))).font(.caption).foregroundStyle(Color.fg2)
                HStack(spacing: 8) {
                    Button(tr("改一下")) { text = aim; editing = true; focused = true }.buttonStyle(.soft)
                    Button(tr("清掉")) { save(nil) }.buttonStyle(.soft)
                }
            } else {
                TextField(tr("比如：每个月存下 500 €"), text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onSubmit { save(text) }
                    .accessibilityLabel(tr("你的目标"))
                Text(tr("点一个例子直接用，或者自己写：")).font(.caption).foregroundStyle(Color.fg2)
                FlowLayout(spacing: 6) {
                    ForEach(Profile.aimExamples, id: \.self) { e in
                        Button(e) { text = e }
                            .buttonStyle(.soft)
                            .accessibilityHint(tr("填进目标"))
                    }
                }
                HStack(spacing: 8) {
                    Button(tr("就这个")) { save(text) }
                        .buttonStyle(AISolidButtonStyle())
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing { Button(tr("取消")) { editing = false }.buttonStyle(.soft) }
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
