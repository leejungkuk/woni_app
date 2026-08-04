import SwiftUI

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    let language: AppLanguage
    @Bindable var viewModel: LoginViewModel

    @State private var legalSheet: LegalLink?

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
                    bordered: true,
                    action: { startLink(.google) }
                )
                socialButton(
                    title: WoniStrings.loginApple(language),
                    background: WoniColor.gray100,
                    foreground: WoniColor.gray00,
                    action: { startLink(.apple) }
                )
            }
            .padding(.top, 8)

            if viewModel.isWorking {
                ProgressView()
                    .tint(WoniColor.olive100)
            }

            consentNotice

            Spacer()
        }
        .padding(20)
        .sheet(item: $legalSheet) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(viewModel.isWorking)
        .alert(WoniStrings.loginFailedTitle(language), isPresented: failureAlertBinding) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {
                viewModel.dismissFailure()
            }
        } message: {
            Text(WoniStrings.loginFailedMessage(language))
        }
        .alert(WoniStrings.loginFailedTitle(language), isPresented: offlineFailureAlertBinding) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {
                viewModel.dismissOfflineFailure()
            }
        } message: {
            Text(WoniStrings.loginOfflineMessage(language))
        }
        .alert(WoniStrings.restoreFailedTitle(language), isPresented: restoreFailureAlertBinding) {
            Button(WoniStrings.close(language), role: .cancel) {
                Task { await viewModel.finishAfterRestoreFailure() }
            }
            Button(WoniStrings.retry(language)) {
                Task {
                    await viewModel.retryRestore()
                }
            }
        } message: {
            Text(WoniStrings.restoreFailedMessage(language))
        }
        .onChange(of: viewModel.flowState) { _, state in
            if state == .completed {
                dismiss()
            }
        }
    }

    /// 소셜로그인이 곧 이용계약 체결이므로(약관 제4조 1항) 동의 대상 문서를 이 화면에서 바로 열 수 있어야 한다.
    private var consentNotice: some View {
        VStack(spacing: 6) {
            Text(WoniStrings.loginConsentNotice(language))
                .woniFont(.small1)
                .foregroundStyle(WoniColor.gray60)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                legalLink(title: WoniStrings.terms(language)) {
                    legalSheet = LegalContent.termsOfServiceLink(language)
                }
                .accessibilityIdentifier("login.link.terms")
                legalLink(title: WoniStrings.privacy(language)) {
                    legalSheet = LegalContent.privacyPolicyLink(language)
                }
                .accessibilityIdentifier("login.link.privacy")
            }
        }
    }

    /// 로그인 진행 중에는 문서를 열지 않는다. 읽는 도중 로그인이 완료되면 `.onChange`의 `dismiss()`가
    /// 이 시트를 닫으면서 위에 떠 있던 문서 시트까지 함께 사라지기 때문이다.
    private func legalLink(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .woniFont(.small1)
                .foregroundStyle(WoniColor.gray100)
                .underline()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
    }

    private func socialButton(
        title: String,
        background: Color,
        foreground: Color,
        bordered: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
        .disabled(viewModel.isWorking)
    }

    private var failureAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hasFailure },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissFailure()
                }
            }
        )
    }

    private var restoreFailureAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hasRestoreFailure },
            set: { _ in }
        )
    }

    private var offlineFailureAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hasOfflineFailure },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissOfflineFailure()
                }
            }
        )
    }

    private func startLink(_ provider: OAuthProvider) {
        Task {
            await viewModel.linkIdentity(provider)
        }
    }
}
