import SwiftUI

struct SettingsRow: View {
    let title: String
    var value: String?
    var titleColor: Color = WoniColor.gray100
    var action: (() -> Void)?

    /// 설정 행 글자 16pt — 출시본 값. KR 시안(`552:8198`)은 20 이지만 2026-10-02 사용자 결정으로 16 을 유지한다.
    /// 언어 설정 행(`LanguageOptionRow`)도 같은 값을 쓴다.
    static let textStyle: WoniTypography = .body2

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
                .woniFont(Self.textStyle)
                .foregroundStyle(titleColor)
                .layoutPriority(1)

            Spacer(minLength: 16)

            if let value {
                Text(value)
                    .woniFont(Self.textStyle)
                    .foregroundStyle(WoniColor.olive100)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        // 한 줄 행은 KR 52. 여백으로 맞추면 글꼴 메트릭을 따라 어긋나므로 최소 높이로 정하고,
        // 두 줄로 넘치는 제목은 잘리지 않게 늘어나게 둔다.
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
