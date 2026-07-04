import SwiftUI

/// Figma element_btn — 흰 원형 배경 + Shadow 1(올리브 톤 글로우), 아이콘 하나를 감싸는 버튼.
struct CircleIconButton<Icon: View>: View {
    var diameter: CGFloat = 44
    var background: Color = WoniColor.gray00
    @ViewBuilder var icon: Icon

    var body: some View {
        icon
            .frame(width: diameter, height: diameter)
            .background(background)
            .clipShape(Circle())
            .woniShadow(.shadow1)
    }
}
