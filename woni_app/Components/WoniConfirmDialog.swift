import SwiftUI

/// 되돌릴 수 없는 동작을 확인받는 팝업. 주 버튼이 실행, 보조 버튼이 취소다.
struct WoniConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    /// 접근성 식별자 접두사. 화면마다 다른 값을 줘 테스트가 어느 팝업인지 가려낸다.
    let identifier: String
    var isBusy = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            WoniColor.gray100.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(title)
                        .woniFont(.body1)
                        .foregroundStyle(WoniColor.gray100)
                    Text(message)
                        .woniFont(.body3)
                        .foregroundStyle(WoniColor.gray60)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Rectangle()
                    .fill(WoniColor.base20)
                    .frame(height: 1)

                HStack(spacing: 8) {
                    dialogButton(confirmTitle, isPrimary: true, action: onConfirm)
                        .accessibilityIdentifier("\(identifier).confirm")
                        .disabled(isBusy)

                    dialogButton(cancelTitle, isPrimary: false, action: onCancel)
                        .accessibilityIdentifier("\(identifier).cancel")
                        .disabled(isBusy)
                }
                .padding(16)
            }
            .frame(maxWidth: 360)
            .background(WoniColor.gray00)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .woniShadow(.shadow1)
            .padding(.horizontal, 16)
        }
        // 딤 배경은 터치만 막는다. 이 트레이트가 없으면 VoiceOver로는 뒤 화면을 그대로 조작할 수
        // 있어, 같은 확인 화면이 접근성 사용 여부에 따라 다르게 동작한다.
        .accessibilityAddTraits(.isModal)
    }

    private func dialogButton(
        _ title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .woniFont(isPrimary ? .body2 : .body3)
                .foregroundStyle(isPrimary ? WoniColor.base10 : WoniColor.gray60)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isPrimary ? WoniColor.terracotta100 : WoniColor.gray00)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(
                        isPrimary ? WoniColor.terracotta100 : WoniColor.base20,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
    }
}
