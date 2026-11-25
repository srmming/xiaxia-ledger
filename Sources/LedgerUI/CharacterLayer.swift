import FinanceCore
import SwiftUI

// 人物层（ming 2026-11-25：「把夏夏界面上的人物都剥离出来」）。
// 界面本身不画人物：卡片、大数字、按钮自己就要好看。人物只放在几个固定位置，全都经过 CharacterSlot：
//   · 夏夏卡右边的全身像（总览、各页最上面那叠卡，夏夏点评）
//   · 小头像（卡片标题、对话、提示里那个圆脸）
//   · 空状态、引导、庆祝里的大图
// 换样子、换装、做动画只改 Mascot.swift 那一层，调用的地方不用动。设置里「界面上显示夏夏」关掉后，
// 全身像和大图都不出现、版面照样整齐；小头像换成一个星星小圆，标题那行不会错位。

enum CharacterLayer {
    static let storageKey = "xiaxia.showCharacter"
}

struct CharacterSlot: View {
    var pose: MascotPose = .idle
    var size: CGFloat
    var face = false
    var talking = false
    var animated = true
    var interactive = false
    @AppStorage(CharacterLayer.storageKey) private var shown = true

    init(pose: MascotPose = .idle, size: CGFloat, face: Bool = false,
         talking: Bool = false, animated: Bool = true, interactive: Bool = false) {
        self.pose = pose; self.size = size; self.face = face
        self.talking = talking; self.animated = animated; self.interactive = interactive
    }

    var body: some View {
        if shown {
            MascotView(pose: pose, size: size, face: face, talking: talking, animated: animated, interactive: interactive)
        } else if face {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(Color.ai)
                .frame(width: size, height: size)
                .background(Color.aiSoft, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

/// 设置里的开关：界面上显示不显示夏夏。
struct CharacterToggle: View {
    @AppStorage(CharacterLayer.storageKey) private var shown = true
    var body: some View {
        Toggle(isOn: $shown.animation(.snappy)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("界面上显示夏夏"))
                Text(tr("关掉后卡片和数字照常，只是不出现人物。")).font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .toggleStyle(.switch)
        .accessibilityIdentifier("settings.showCharacter")
    }
}

// MARK: - AI 提示层

// 页面上的 AI 提示（夏夏点评叠卡、「夏夏说」、问 AI 的话术卡、空状态和欠款页里的「问夏夏」按钮）也剥离成一层：
// ming 2026-11-25：「所有的界面 AI 提示都剥离」「非引导页面」。页面本身只放数字和功能；
// 问夏夏走工具栏右上角的入口（⌘K），AI 写的意见集中在「夏夏建议」页。第一次打开的引导、连 AI 页不受影响。
// 以后想放回页面上，设置里打开「页面上显示夏夏的点评」。
enum AILayer {
    static let storageKey = "xiaxia.aiInPages"
}

struct AILayerToggle: View {
    @AppStorage(AILayer.storageKey) private var shown = false
    var body: some View {
        Toggle(isOn: $shown.animation(.snappy)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("页面上显示夏夏的点评"))
                Text(tr("关着时各页只放数字和功能，夏夏的意见都在「夏夏建议」里，问她点右上角。")).font(.caption).foregroundStyle(Color.fg2)
            }
        }
        .toggleStyle(.switch)
        .accessibilityIdentifier("settings.aiInPages")
    }
}
