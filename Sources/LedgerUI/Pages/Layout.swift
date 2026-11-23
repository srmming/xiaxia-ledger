import SwiftUI

/// 宽的时候左右两栏（右栏固定宽），窄的时候（Mac 窗口小、iPhone）落成一列。
struct Columns<Main: View, Side: View>: View {
    var sideWidth: CGFloat = 340
    var breakpoint: CGFloat = 720
    /// 宽窗口时右栏跟着变宽：右栏至少占这么多比例（nil = 固定 sideWidth）。
    var sideRatio: CGFloat? = nil
    @ViewBuilder var main: () -> Main
    @ViewBuilder var side: () -> Side
    @State var width: CGFloat = 1000

    var body: some View {
        let wide = width >= breakpoint
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: Kit.gap)) : AnyLayout(VStackLayout(alignment: .leading, spacing: Kit.gap))
        layout {
            VStack(alignment: .leading, spacing: Kit.gap) { main() }
                .frame(maxWidth: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: Kit.gap) { side() }
                .frame(width: wide ? max(sideWidth, (sideRatio ?? 0) * width) : nil)
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

/// 页面顶部的状态小字（iPhone 上的大标题下面、Mac 的页面开头）。
struct PageNote: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(Color.fg2).frame(maxWidth: .infinity, alignment: .leading)
    }
}
