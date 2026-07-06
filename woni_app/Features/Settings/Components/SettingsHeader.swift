import SwiftUI

struct SettingsHeader: View {
    let title: String
    var onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                CircleIconButton {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WoniColor.gray80)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 96, alignment: .leading)

            Text(title)
                .woniFont(.body1)
                .foregroundStyle(WoniColor.gray100)
                .frame(maxWidth: .infinity)

            Color.clear.frame(width: 96, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WoniColor.gray00)
    }
}
