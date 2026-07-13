import SwiftUI

struct LoginSheet: View {
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 16) {
            Text(WoniStrings.loginSheetTitle(language))
                .woniFont(.h4)
                .foregroundStyle(WoniColor.gray100)
                .padding(.top, 8)

            Text(WoniStrings.loginSheetSubtitle(language))
                .woniFont(.small1)
                .foregroundStyle(WoniColor.gray60)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                socialButton(
                    title: WoniStrings.loginGoogle(language),
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
            // 실제 소셜 로그인 연동은 이후 작업.
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
