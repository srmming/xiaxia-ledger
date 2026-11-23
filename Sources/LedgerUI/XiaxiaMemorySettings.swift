import FinanceCore
import SwiftUI

// 设置 →「夏夏的记忆」的二级页。占位：真正的页面由「让夏夏越用越懂我的财务」线程做，合并时整个文件用那边的版本。
// 约定：这个 View 就是整页（自己加 .kitPage()，不包 NavigationStack，标题由设置页给 navigationTitle）。

struct XiaxiaMemorySettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("夏夏的记忆").font(.title2.weight(.bold))
            Text("夏夏会记住你的规矩、你的习惯和做事的经验，越用越懂你的账。这一页正在做。")
                .font(.callout).foregroundStyle(Color.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
        .kitPage()
    }
}

extension LedgerModel {
    /// 设置那一行右边的小字。
    var memorySummary: String { "还没记住什么" }
}
