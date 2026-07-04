import SwiftUI

struct ChipButton: View {
    let label: String
    let isSelected: Bool
    var accent: ChipAccent = .terracotta
    let action: () -> Void

    enum ChipAccent {
        case terracotta
        case olive

        var background: Color {
            self == .terracotta ? WoniColor.terracotta10 : WoniColor.olive10
        }

        var border: Color {
            self == .terracotta ? WoniColor.terracotta70 : WoniColor.olive70
        }

        var text: Color {
            self == .terracotta ? WoniColor.terracotta100 : WoniColor.olive100
        }
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .woniFont(.body3)
                .foregroundStyle(isSelected ? accent.text : WoniColor.gray80)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? accent.background : WoniColor.base10)
                .overlay {
                    Capsule().stroke(isSelected ? accent.border : WoniColor.gray20, lineWidth: 1)
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
