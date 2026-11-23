import SwiftUI

/// 宽的时候左右两栏（右栏固定宽），窄的时候（iPhone）落成一列。
/// Mac 最小窗口（1000×612）页面只有 700 多宽：右栏收窄到页面的 42%（不小于 300），仍然左右两栏，少往下拉（ming：「尽量不要上下拉动」）。
struct Columns<Main: View, Side: View>: View {
    var sideWidth: CGFloat = 340
    var breakpoint: CGFloat = 600
    @ViewBuilder var main: () -> Main
    @ViewBuilder var side: () -> Side
    @State var width: CGFloat = 1000

    var body: some View {
        let wide = width >= breakpoint
        let side = min(sideWidth, max(300, (width * 0.42).rounded()))
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: Kit.gap)) : AnyLayout(VStackLayout(alignment: .leading, spacing: Kit.gap))
        layout {
            VStack(alignment: .leading, spacing: Kit.gap) { main() }
                .frame(maxWidth: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: Kit.gap) { side() }
                .frame(width: wide ? side : nil)
                .frame(maxWidth: wide ? nil : .infinity, alignment: .top)
        }
        .background { WidthReader(width: $width) }
    }
}

/// 量出自己有多宽，存进 width。
struct WidthReader: View {
    @Binding var width: CGFloat
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { _, w in width = w }
        }
    }
}

/// 等宽并排的几张卡片；窄了就一张一行。
struct CardRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var minWidth: CGFloat = 260
    @ViewBuilder var content: (Item) -> Content
    @State var width: CGFloat = 1000

    var body: some View {
        let perRow = max(1, min(items.count, Int((width + Kit.gap) / (minWidth + Kit.gap))))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Kit.gap, alignment: .top), count: perRow), spacing: Kit.gap) {
            ForEach(items) { content($0) }
        }
        .background { WidthReader(width: $width) }
    }
}

/// 页面能看到多大（窗口里去掉工具栏，不算滚动）。放在 .kitPage() 后面量：
/// `.onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }`
enum Viewport {
    /// 矮窗口（比如 1000×612）：图表收矮、列表少列几条，一屏放下。
    static func isShort(_ size: CGSize) -> Bool { size.height < 700 }
}

/// 页面顶部的状态小字（iPhone 上的大标题下面、Mac 的页面开头）。
struct PageNote: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(Color.fg2).frame(maxWidth: .infinity, alignment: .leading)
    }
}
