import SwiftUI

struct SettingsRow: View {
    let title: String
    var value: String?
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            Text(title)
                .woniFont(.body2)
                .foregroundStyle(WoniColor.gray100)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let value {
                Text(value)
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.olive100)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(WoniColor.base20)
            .frame(height: 1)
    }
}
