import SwiftUI

struct LanguageOptionRow: View {
    let title: String
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.gray100)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(WoniColor.terracotta100)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    WoniColor.base20
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
