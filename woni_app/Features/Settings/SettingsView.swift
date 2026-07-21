import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var viewModel: SettingsViewModel

    @State private var showLogin = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showSupportPending = false

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var language: AppLanguage {
        languageStore.language
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: WoniStrings.settingsTitle(language)) {
                dismiss()
            }
            .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsRow(title: WoniStrings.baseCurrency(language), value: "KRW")
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 11) {
                        LanguageSettingsRow(
                            title: WoniStrings.languageRow(language),
                            selection: Binding(
                                get: { languageStore.language },
                                set: { languageStore.language = $0 }
                            )
                        )
                        if viewModel.loginViewModel.identityState == .anonymous {
                            SettingsRow(
                                title: WoniStrings.loginSignup(language),
                                value: WoniStrings.identityAnonymous(language)
                            ) {
                                showLogin = true
                            }
                            // 로그아웃/cleanup 진행 중에는 로그인 진입을 막는다. VM 재생성 후
                            // 세션이 이미 없어 identityState가 anonymous로 보여도, 이전 멤버
                            // 로컬 데이터 정리가 끝나기 전 로그인해 데이터가 섞이는 것을 방지한다.
                            .disabled(viewModel.isLoginBlocked)
                        } else {
                            SettingsRow(
                                title: WoniStrings.loginSignup(language),
                                value: WoniStrings.identitySignedIn(language)
                            )
                            SettingsRow(
                                title: WoniStrings.logout(language),
                                value: viewModel.isLoggingOut
                                    ? WoniStrings.logoutSyncing(language)
                                    : nil
                            ) {
                                Task {
                                    await viewModel.requestLogout()
                                }
                            }
                            .disabled(viewModel.isLoggingOut || viewModel.needsCleanup)
                        }
                    }
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 11) {
                        SettingsRow(title: WoniStrings.appVersion(language), value: appVersion)
                        SettingsRow(title: WoniStrings.support(language)) {
                            showSupportPending = true
                        }
                        SettingsRow(title: WoniStrings.terms(language)) {
                            showTerms = true
                        }
                        SettingsRow(title: WoniStrings.privacy(language)) {
                            showPrivacy = true
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(WoniColor.gray00)
        }
        .background(WoniColor.gray00)
        .sheet(isPresented: $showLogin) {
            LoginSheet(language: language, viewModel: viewModel.loginViewModel)
        }
        .navigationDestination(isPresented: $showTerms) {
            LegalTextView(title: WoniStrings.terms(language), clauses: LegalContent.termsOfService)
        }
        .navigationDestination(isPresented: $showPrivacy) {
            LegalTextView(
                title: WoniStrings.privacy(language),
                clauses: [],
                pendingNote: LegalContent.privacyPolicyPending
            )
        }
        .alert(WoniStrings.support(language), isPresented: $showSupportPending) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {}
        } message: {
            Text(WoniStrings.supportPending(language))
        }
        .alert(
            WoniStrings.unsyncedLogoutTitle(language),
            isPresented: Binding(
                get: { viewModel.hasUnsyncedLogoutWarning },
                set: { _ in }
            )
        ) {
            Button(WoniStrings.cancel(language), role: .cancel) {
                viewModel.cancelForcedLogout()
            }
            Button(WoniStrings.forceLogout(language), role: .destructive) {
                Task {
                    await viewModel.confirmForcedLogout()
                }
            }
        } message: {
            Text(WoniStrings.unsyncedLogoutMessage(language))
        }
        .alert(
            WoniStrings.logoutFailedTitle(language),
            isPresented: Binding(
                get: { viewModel.hasLogoutFailure },
                set: { _ in }
            )
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {
                viewModel.dismissLogoutFailure()
            }
        } message: {
            Text(WoniStrings.logoutFailedMessage(language))
        }
        .alert(
            WoniStrings.logoutCleanupRequiredTitle(language),
            isPresented: Binding(
                get: { viewModel.needsCleanup },
                set: { _ in }
            )
        ) {
            Button(WoniStrings.retry(language)) {
                Task {
                    await viewModel.retryCleanup()
                }
            }
        } message: {
            Text(WoniStrings.logoutCleanupRequiredMessage(language))
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct LanguageSettingsRow: View {
    let title: String
    @Binding var selection: AppLanguage

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .woniFont(.body2)
                .foregroundStyle(WoniColor.gray100)
                .frame(maxWidth: .infinity, alignment: .leading)

            LanguageSegmentedControl(selection: $selection)
        }
        .padding(.vertical, 8)
    }
}

private struct LanguageSegmentedControl: View {
    @Binding var selection: AppLanguage

    var body: some View {
        HStack(spacing: 0) {
            segment(language: .ko, title: "한국어")
            segment(language: .en, title: "English")
        }
        .padding(2)
        .background(WoniColor.base20)
        .clipShape(Capsule())
    }
}

private extension LanguageSegmentedControl {
    func segment(language: AppLanguage, title: String) -> some View {
        let isSelected = selection == language

        return Button {
            selection = language
        } label: {
            Text(title)
                .woniFont(.body3)
                .foregroundStyle(isSelected ? WoniColor.olive100 : WoniColor.gray80)
                .frame(width: 70, height: 30)
                .background {
                    if isSelected {
                        WoniColor.gray00
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
