import SwiftUI

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    let language: AppLanguage
    @Bindable var viewModel: LoginViewModel

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

            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(viewModel.isWorking)
        .alert(
            WoniStrings.identityConflictTitle(language),
            isPresented: conflictAlertBinding
        ) {
            Button(WoniStrings.cancel(language), role: .cancel) {
                viewModel.cancelSignIn()
            }
            Button(WoniStrings.signInExistingAccount(language)) {
                Task {
                    await viewModel.confirmSignIn()
                }
            }
        } message: {
            Text(WoniStrings.identityConflictMessage(language))
        }
        .alert(WoniStrings.loginFailedTitle(language), isPresented: failureAlertBinding) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {
                viewModel.dismissFailure()
            }
        } message: {
            Text(WoniStrings.loginFailedMessage(language))
        }
        .alert(WoniStrings.restoreFailedTitle(language), isPresented: restoreFailureAlertBinding) {
            Button(WoniStrings.close(language), role: .cancel) {
                viewModel.finishAfterRestoreFailure()
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

    private var conflictAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.conflictProvider != nil },
            set: { _ in }
        )
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

    private func startLink(_ provider: OAuthProvider) {
        Task {
            await viewModel.linkIdentity(provider)
        }
    }
}
