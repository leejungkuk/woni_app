import SwiftUI

struct SettingsHeader: View {
    let title: String
    /// 아이콘만 있는 뒤로가기 버튼의 접근성 레이블. 주지 않으면 OS가 기기 언어로 자동 생성한다.
    let backLabel: String
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
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier("settings.back")

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
