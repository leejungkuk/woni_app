import SwiftUI

struct MonthHeaderView: View {
    let monthTitle: String
    let language: AppLanguage
    let onOpenMonthPicker: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenMonthPicker) {
                HStack(spacing: 0) {
                    Text(monthTitle)
                        .woniFont(.h4)
                        .foregroundStyle(WoniColor.gray100)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WoniColor.gray100)
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onOpenSettings) {
                CircleIconButton {
                    HamburgerIcon()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WoniStrings.settingsA11y(language))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WoniColor.gray00)
    }
}
