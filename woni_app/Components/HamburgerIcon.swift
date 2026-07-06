import SwiftUI

/// Figma icon_menu — 정확히 3줄, 16pt 폭 x 2pt 높이, 줄 간격 4pt, 끝 둥글게. SF Symbol 근사치 대신 정확한 스펙으로 구현.
struct HamburgerIcon: View {
    var color: Color = WoniColor.gray80

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0 ..< 3, id: \.self) { _ in
                Capsule().fill(color).frame(width: 16, height: 2)
            }
        }
    }
}
