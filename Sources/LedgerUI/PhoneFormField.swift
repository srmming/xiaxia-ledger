import SwiftUI

/// 表单里的输入框带上名字：iPhone 的系统表单只显示灰色提示字，填了以后就看不出这格是什么
/// （iPhone 审计 2026-11-26：「店租」看着写了两遍、记分期/记借款的两格看不出是名字还是金额）。
/// iPhone：左边名字、右边填；Mac 的表单本来就在左边写名字，照旧。
struct LabeledField<Field: View>: View {
    let title: String
    @ViewBuilder var field: Field

    init(_ title: String, @ViewBuilder field: () -> Field) {
        self.title = title
        self.field = field()
    }

    var body: some View {
        #if os(iOS)
        LabeledContent(title) { field.multilineTextAlignment(.trailing) }
        #else
        field
        #endif
    }
}
