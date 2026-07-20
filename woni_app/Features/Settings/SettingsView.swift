import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var loginViewModel: LoginViewModel

    @State private var showLogin = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showSupportPending = false

    init(loginViewModel: LoginViewModel) {
        _loginViewModel = State(initialValue: loginViewModel)
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
                        if loginViewModel.identityState == .anonymous {
                            SettingsRow(
                                title: WoniStrings.loginSignup(language),
                                value: WoniStrings.identityAnonymous(language)
                            ) {
                                showLogin = true
                            }
                        } else {
                            SettingsRow(
                                title: WoniStrings.loginSignup(language),
                                value: WoniStrings.identitySignedIn(language)
                            )
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
            LoginSheet(language: language, viewModel: loginViewModel)
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
