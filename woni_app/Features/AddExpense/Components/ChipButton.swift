import SwiftUI

public struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let palette: AccentPalette
    let action: () -> Void

    public init(label: String, isSelected: Bool, palette: AccentPalette, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.palette = palette
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.woni(.body3))
                .foregroundColor(isSelected ? palette.primary100 : Color.Woni.gray80)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? palette.bg10 : Color.Woni.base10)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? palette.border70 : Color.Woni.gray20, lineWidth: 1)
                )
        }
    }
}

#Preview {
    HStack {
        ChipButton(label: "Food/Dining", isSelected: true, palette: .terracotta, action: {})
        ChipButton(label: "Transport", isSelected: false, palette: .terracotta, action: {})
    }
    .padding()
}
