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
        HStack(spacing: 0) {
            // 제목은 intrinsic 폭 + 우선권만 갖는다 — greedy frame에 우선권을 주면
            // trailing 값이 압착되므로 전폭 확보는 바깥 frame과 Spacer가 담당한다.
            // 제목-값 최소 간격 16pt는 Spacer minLength 한 곳에서만 부여한다.
            Text(title)
                .woniFont(.body2)
                .foregroundStyle(WoniColor.gray100)
                .layoutPriority(1)

            Spacer(minLength: 16)

            if let value {
                Text(value)
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.olive100)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
