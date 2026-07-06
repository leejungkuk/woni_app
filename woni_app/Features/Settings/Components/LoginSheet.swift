import SwiftUI

struct LoginSheet: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("로그인 / 회원가입")
                .woniFont(.h4)
                .foregroundStyle(WoniColor.gray100)
                .padding(.top, 8)

            Text("데이터 동기화와 기기 이전을 위해 로그인할 수 있어요")
                .woniFont(.small1)
                .foregroundStyle(WoniColor.gray60)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                socialButton(
                    title: "Google로 계속하기",
                    background: WoniColor.gray00,
                    foreground: WoniColor.gray100,
                    bordered: true
                )
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium])
    }

    private func socialButton(
        title: String,
        background: Color,
        foreground: Color,
        bordered: Bool = false
    ) -> some View {
        Button {
            // TODO: 실제 소셜 로그인 연동은 이후 작업.
        } label: {
            Text(title)
                .woniFont(.body2)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background)
                .overlay {
                    if bordered {
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(WoniColor.gray20, lineWidth: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 100))
        }
        .buttonStyle(.plain)
    }
}
